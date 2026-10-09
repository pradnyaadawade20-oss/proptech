// Package cashfree is a small, dependency-free client for the Cashfree
// Payment Gateway + Easy Split APIs (version 2023-08-01).
//
// The secret key lives ONLY in server environment variables. The mobile app
// receives just a short-lived payment_session_id for one order.
package cashfree

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	AppID          string
	SecretKey      string
	Env            string // "sandbox" (default) | "production"
	APIVersion     string
	ReturnURL      string  // where Cashfree sends the browser after checkout (optional)
	NotifyURL      string  // PUBLIC https URL of POST /api/webhooks/cashfree
	PlatformFeePct float64 // % of every payment kept by the platform (0 = none)
	VerifyAccount  bool    // penny-drop verify owner bank account (use false in sandbox)
	EncKey         []byte  // 32 bytes, encrypts owner account numbers at rest
}

func (c *Config) Enabled() bool { return c != nil && c.AppID != "" && c.SecretKey != "" }
func (c *Config) Sandbox() bool { return c.Env != "production" }

func (c *Config) baseURL() string {
	if c.Sandbox() {
		return "https://sandbox.cashfree.com/pg"
	}
	return "https://api.cashfree.com/pg"
}

// ConfigFromEnv reads CASHFREE_* variables. jwtSecret is only used to derive an
// encryption key when PAYMENT_ENC_KEY is not set.
func ConfigFromEnv(jwtSecret string) *Config {
	env := strings.ToLower(strings.TrimSpace(os.Getenv("CASHFREE_ENV")))
	if env != "production" {
		env = "sandbox"
	}
	cfg := &Config{
		AppID:      strings.TrimSpace(os.Getenv("CASHFREE_APP_ID")),
		SecretKey:  strings.TrimSpace(os.Getenv("CASHFREE_SECRET_KEY")),
		Env:        env,
		APIVersion: envOr("CASHFREE_API_VERSION", "2023-08-01"),
		ReturnURL:  strings.TrimSpace(os.Getenv("CASHFREE_RETURN_URL")),
		NotifyURL:  strings.TrimSpace(os.Getenv("CASHFREE_NOTIFY_URL")),
	}
	if v, err := strconv.ParseFloat(os.Getenv("PLATFORM_FEE_PCT"), 64); err == nil && v >= 0 && v < 50 {
		cfg.PlatformFeePct = v
	}
	cfg.VerifyAccount = strings.EqualFold(os.Getenv("CASHFREE_VERIFY_ACCOUNT"), "true")

	if raw := strings.TrimSpace(os.Getenv("PAYMENT_ENC_KEY")); raw != "" {
		if k, err := base64.StdEncoding.DecodeString(raw); err == nil && len(k) == 32 {
			cfg.EncKey = k
		} else {
			log.Println("PAYMENT_ENC_KEY must be base64 of 32 bytes; falling back to a key derived from JWT_SECRET")
		}
	}
	if cfg.EncKey == nil {
		sum := sha256.Sum256([]byte("proptech-bank-enc:" + jwtSecret))
		cfg.EncKey = sum[:]
	}
	return cfg
}

func envOr(k, d string) string {
	if v := strings.TrimSpace(os.Getenv(k)); v != "" {
		return v
	}
	return d
}

// ---------------------------------------------------------------------------
// Encryption of owner account numbers (AES-256-GCM)
// ---------------------------------------------------------------------------

func (c *Config) Encrypt(plain string) (string, error) {
	block, err := aes.NewCipher(c.EncKey)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(gcm.Seal(nonce, nonce, []byte(plain), nil)), nil
}

func (c *Config) Decrypt(enc string) (string, error) {
	raw, err := base64.StdEncoding.DecodeString(enc)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(c.EncKey)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	if len(raw) < gcm.NonceSize() {
		return "", errors.New("ciphertext too short")
	}
	out, err := gcm.Open(nil, raw[:gcm.NonceSize()], raw[gcm.NonceSize():], nil)
	return string(out), err
}

// ---------------------------------------------------------------------------
// Webhook signature
// ---------------------------------------------------------------------------

// VerifyWebhook checks x-webhook-signature = base64(HMAC-SHA256(secret, timestamp + rawBody)).
func (c *Config) VerifyWebhook(timestamp string, rawBody []byte, signature string) bool {
	if c.SecretKey == "" || timestamp == "" || signature == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(c.SecretKey))
	mac.Write([]byte(timestamp))
	mac.Write(rawBody)
	want := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	return subtle.ConstantTimeCompare([]byte(want), []byte(signature)) == 1
}

// ---------------------------------------------------------------------------
// HTTP client
// ---------------------------------------------------------------------------

type Client struct {
	cfg  *Config
	http *http.Client
}

func NewClient(cfg *Config) *Client {
	return &Client{cfg: cfg, http: &http.Client{Timeout: 20 * time.Second}}
}

func (c *Client) Config() *Config { return c.cfg }

// APIError is a non-2xx answer from Cashfree.
type APIError struct {
	Status  int
	Code    string
	Message string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("cashfree %d %s: %s", e.Status, e.Code, e.Message)
}

func (c *Client) do(ctx context.Context, method, path string, body any, out any) error {
	if !c.cfg.Enabled() {
		return errors.New("online payments are not configured on the server")
	}
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.cfg.baseURL()+path, rdr)
	if err != nil {
		return err
	}
	req.Header.Set("x-client-id", c.cfg.AppID)
	req.Header.Set("x-client-secret", c.cfg.SecretKey)
	req.Header.Set("x-api-version", c.cfg.APIVersion)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		ae := &APIError{Status: resp.StatusCode}
		var e struct {
			Code    string `json:"code"`
			Type    string `json:"type"`
			Message string `json:"message"`
		}
		if json.Unmarshal(raw, &e) == nil {
			ae.Code, ae.Message = e.Code, e.Message
			if ae.Code == "" {
				ae.Code = e.Type
			}
		}
		if ae.Message == "" {
			ae.Message = strings.TrimSpace(string(raw))
		}
		return ae
	}
	if out != nil && len(raw) > 0 {
		return json.Unmarshal(raw, out)
	}
	return nil
}

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

type Customer struct {
	ID    string `json:"customer_id"`
	Name  string `json:"customer_name,omitempty"`
	Email string `json:"customer_email,omitempty"`
	Phone string `json:"customer_phone"`
}

type Split struct {
	VendorID string  `json:"vendor_id"`
	Amount   float64 `json:"amount"`
}

type CreateOrderReq struct {
	OrderID   string
	Amount    float64
	Customer  Customer
	Note      string
	Tags      map[string]string
	ExpiresAt time.Time
	Splits    []Split
	ReturnURL string
	NotifyURL string
}

type Order struct {
	CFOrderID        string  `json:"cf_order_id"`
	OrderID          string  `json:"order_id"`
	OrderStatus      string  `json:"order_status"` // ACTIVE | PAID | EXPIRED | TERMINATED | TERMINATION_REQUESTED
	PaymentSessionID string  `json:"payment_session_id"`
	OrderAmount      float64 `json:"order_amount"`
}

func (c *Client) CreateOrder(ctx context.Context, r CreateOrderReq) (*Order, error) {
	meta := map[string]any{}
	if r.ReturnURL != "" {
		meta["return_url"] = r.ReturnURL
	}
	if r.NotifyURL != "" {
		meta["notify_url"] = r.NotifyURL
	}
	body := map[string]any{
		"order_id":          r.OrderID,
		"order_amount":      r.Amount,
		"order_currency":    "INR",
		"customer_details":  r.Customer,
		"order_meta":        meta,
		"order_note":        r.Note,
		"order_expiry_time": r.ExpiresAt.UTC().Format(time.RFC3339),
	}
	if len(r.Tags) > 0 {
		body["order_tags"] = r.Tags
	}
	if len(r.Splits) > 0 {
		body["order_splits"] = r.Splits
	}
	var out Order
	if err := c.do(ctx, http.MethodPost, "/orders", body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) GetOrder(ctx context.Context, orderID string) (*Order, error) {
	var out Order
	if err := c.do(ctx, http.MethodGet, "/orders/"+orderID, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// TerminateOrder stops an unpaid order so it can never be paid later.
func (c *Client) TerminateOrder(ctx context.Context, orderID string) error {
	return c.do(ctx, http.MethodPatch, "/orders/"+orderID, map[string]string{"order_status": "TERMINATED"}, nil)
}

type PaymentAttempt struct {
	CFPaymentID    json.Number `json:"cf_payment_id"`
	PaymentStatus  string      `json:"payment_status"` // SUCCESS | FAILED | PENDING | USER_DROPPED | CANCELLED | NOT_ATTEMPTED | VOID
	PaymentAmount  float64     `json:"payment_amount"`
	PaymentGroup   string      `json:"payment_group"`
	PaymentMessage string      `json:"payment_message"`
	PaymentTime    string      `json:"payment_time"`
	ErrorDetails   *struct {
		Description string `json:"error_description"`
		Reason      string `json:"error_reason"`
	} `json:"error_details"`
}

func (p PaymentAttempt) FailureText() string {
	if p.ErrorDetails != nil {
		if p.ErrorDetails.Description != "" {
			return p.ErrorDetails.Description
		}
		if p.ErrorDetails.Reason != "" {
			return p.ErrorDetails.Reason
		}
	}
	return p.PaymentMessage
}

func (c *Client) GetOrderPayments(ctx context.Context, orderID string) ([]PaymentAttempt, error) {
	var out []PaymentAttempt
	if err := c.do(ctx, http.MethodGet, "/orders/"+orderID+"/payments", nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// Settlements (merchant settlement of an order)
// ---------------------------------------------------------------------------

type Settlement struct {
	CFSettlementID   json.Number `json:"cf_settlement_id"`
	SettlementAmount float64     `json:"settlement_amount"`
	TransferUTR      string      `json:"transfer_utr"`
	TransferTime     string      `json:"transfer_time"`
}

// GetOrderSettlement returns (nil, nil) while Cashfree has not settled the order yet.
func (c *Client) GetOrderSettlement(ctx context.Context, orderID string) (*Settlement, error) {
	var out Settlement
	if err := c.do(ctx, http.MethodGet, "/orders/"+orderID+"/settlements", nil, &out); err != nil {
		var ae *APIError
		if errors.As(err, &ae) && (ae.Status == 404 || ae.Status == 400) {
			return nil, nil
		}
		return nil, err
	}
	if out.TransferUTR == "" && out.CFSettlementID.String() == "" {
		return nil, nil
	}
	return &out, nil
}

// ---------------------------------------------------------------------------
// Easy Split vendors (owner bank onboarding)
// ---------------------------------------------------------------------------

type VendorBank struct {
	AccountNumber string `json:"account_number"`
	AccountHolder string `json:"account_holder"`
	IFSC          string `json:"ifsc"`
}

type VendorReq struct {
	VendorID string
	Name     string
	Email    string
	Phone    string
	Bank     VendorBank
}

type Vendor struct {
	VendorID string `json:"vendor_id"`
	Status   string `json:"status"`
}

func (c *Client) vendorBody(v VendorReq, withID bool) map[string]any {
	b := map[string]any{
		"status":           "ACTIVE",
		"name":             v.Name,
		"email":            v.Email,
		"phone":            v.Phone,
		"verify_account":   c.cfg.VerifyAccount,
		"dashboard_access": false,
		"schedule_option":  1,
		"bank":             v.Bank,
	}
	if withID {
		b["vendor_id"] = v.VendorID
	}
	return b
}

// UpsertVendor creates the vendor, or updates it when it already exists.
func (c *Client) UpsertVendor(ctx context.Context, v VendorReq) (*Vendor, error) {
	var out Vendor
	err := c.do(ctx, http.MethodPost, "/easy-split/vendors", c.vendorBody(v, true), &out)
	if err == nil {
		return &out, nil
	}
	var ae *APIError
	if errors.As(err, &ae) && (ae.Status == 409 || strings.Contains(strings.ToLower(ae.Message), "already")) {
		if err := c.do(ctx, http.MethodPatch, "/easy-split/vendors/"+v.VendorID, c.vendorBody(v, false), &out); err != nil {
			return nil, err
		}
		if out.VendorID == "" {
			out.VendorID = v.VendorID
		}
		return &out, nil
	}
	return nil, err
}

func (c *Client) GetVendor(ctx context.Context, vendorID string) (*Vendor, error) {
	var out Vendor
	if err := c.do(ctx, http.MethodGet, "/easy-split/vendors/"+vendorID, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// VendorState maps Cashfree's vendor status text to our status.
func VendorState(cfStatus string) string {
	s := strings.ToUpper(cfStatus)
	switch {
	case s == "ACTIVE":
		return "active"
	case strings.Contains(s, "FAIL"), strings.Contains(s, "REJECT"), strings.Contains(s, "BLOCK"):
		return "verification_failed"
	case s == "INACTIVE", s == "DELETED":
		return "inactive"
	default: // BANK_DETAILS_UNDER_VERIFICATION, IN_BENE_CREATION, ...
		return "pending"
	}
}
