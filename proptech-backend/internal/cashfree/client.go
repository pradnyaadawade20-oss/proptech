// Package cashfree is a tiny client for the Cashfree Payment Gateway (PG) REST API.
// Secret keys are read from env vars only and never leave the backend.
package cashfree

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const apiVersion = "2023-08-01"

type Client struct {
	AppID   string
	Secret  string
	Env     string // "sandbox" | "production"
	BaseURL string
	http    *http.Client
}

// FromEnv reads CASHFREE_APP_ID, CASHFREE_SECRET_KEY and CASHFREE_ENV (sandbox by default).
func FromEnv() *Client {
	env := strings.ToLower(strings.TrimSpace(os.Getenv("CASHFREE_ENV")))
	if env != "production" {
		env = "sandbox"
	}
	base := "https://sandbox.cashfree.com/pg"
	if env == "production" {
		base = "https://api.cashfree.com/pg"
	}
	return &Client{
		AppID:   strings.TrimSpace(os.Getenv("CASHFREE_APP_ID")),
		Secret:  strings.TrimSpace(os.Getenv("CASHFREE_SECRET_KEY")),
		Env:     env,
		BaseURL: base,
		http:    &http.Client{Timeout: 20 * time.Second},
	}
}

func (c *Client) Configured() bool { return c != nil && c.AppID != "" && c.Secret != "" }

// ---- create order ----

type Customer struct {
	ID    string `json:"customer_id"`
	Name  string `json:"customer_name,omitempty"`
	Phone string `json:"customer_phone"`
	Email string `json:"customer_email,omitempty"`
}

type CreateOrderReq struct {
	OrderID    string
	Amount     float64
	Note       string
	Customer   Customer
	ReturnURL  string // may contain {order_id}
	NotifyURL  string // webhook
	ExpiryTime time.Time
}

type Order struct {
	CFOrderID        string  `json:"cf_order_id"`
	OrderID          string  `json:"order_id"`
	OrderStatus      string  `json:"order_status"` // ACTIVE | PAID | EXPIRED | TERMINATED...
	PaymentSessionID string  `json:"payment_session_id"`
	OrderAmount      float64 `json:"order_amount"`
}

func (c *Client) CreateOrder(ctx context.Context, r CreateOrderReq) (*Order, error) {
	meta := map[string]string{"return_url": r.ReturnURL}
	if r.NotifyURL != "" {
		meta["notify_url"] = r.NotifyURL
	}
	body := map[string]any{
		"order_id":         r.OrderID,
		"order_amount":     r.Amount,
		"order_currency":   "INR",
		"order_note":       r.Note,
		"customer_details": r.Customer,
		"order_meta":       meta,
		"order_expiry_time": r.ExpiryTime.UTC().Format(time.RFC3339),
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

// ---- payments of an order ----

type Payment struct {
	CFPaymentID   json.Number `json:"cf_payment_id"`
	Status        string      `json:"payment_status"` // SUCCESS | FAILED | PENDING | USER_DROPPED...
	Amount        float64     `json:"payment_amount"`
	Group         string      `json:"payment_group"` // upi | credit_card | debit_card | net_banking | wallet...
	Message       string      `json:"payment_message"`
}

func (c *Client) GetPayments(ctx context.Context, orderID string) ([]Payment, error) {
	var out []Payment
	if err := c.do(ctx, http.MethodGet, "/orders/"+orderID+"/payments", nil, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// MethodName turns Cashfree's payment_group into what we store/show ("online_upi", "online_card"...).
// The "online_" prefix keeps these apart from the old manual "upi" proof-screenshot payments.
func MethodName(group string) string {
	switch strings.ToLower(group) {
	case "upi":
		return "online_upi"
	case "credit_card", "debit_card", "prepaid_card", "card", "emi":
		return "online_card"
	case "net_banking", "netbanking":
		return "online_netbanking"
	case "wallet", "app":
		return "online_wallet"
	case "":
		return "online"
	}
	return "online_" + strings.ToLower(group)
}

// ---- refunds ----

type Refund struct {
	CFRefundID   json.Number `json:"cf_refund_id"`
	RefundID     string      `json:"refund_id"`
	OrderID      string      `json:"order_id"`
	RefundAmount float64     `json:"refund_amount"`
	Status       string      `json:"refund_status"` // SUCCESS | PENDING | ONHOLD | CANCELLED | FAILED
	Description  string      `json:"status_description"`
}

// CreateRefund refunds part (or all) of a PAID order back to the payer's original payment method.
// refundID must be unique per refund (Cashfree rejects a repeated one).
func (c *Client) CreateRefund(ctx context.Context, orderID, refundID string, amount float64, note string) (*Refund, error) {
	body := map[string]any{
		"refund_amount": amount,
		"refund_id":     refundID,
		"refund_note":   note,
	}
	var out Refund
	if err := c.do(ctx, http.MethodPost, "/orders/"+orderID+"/refunds", body, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (c *Client) GetRefund(ctx context.Context, orderID, refundID string) (*Refund, error) {
	var out Refund
	if err := c.do(ctx, http.MethodGet, "/orders/"+orderID+"/refunds/"+refundID, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// ---- webhook signature ----

// VerifyWebhook checks x-webhook-signature = base64(HMAC-SHA256(timestamp + rawBody, secret)).
func (c *Client) VerifyWebhook(timestamp, signature string, rawBody []byte) bool {
	if c == nil || c.Secret == "" || timestamp == "" || signature == "" {
		return false
	}
	mac := hmac.New(sha256.New, []byte(c.Secret))
	mac.Write([]byte(timestamp))
	mac.Write(rawBody)
	want := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(want), []byte(signature))
}

// ---- http ----

func (c *Client) do(ctx context.Context, method, path string, in any, out any) error {
	var rdr io.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, rdr)
	if err != nil {
		return err
	}
	req.Header.Set("x-client-id", c.AppID)
	req.Header.Set("x-client-secret", c.Secret)
	req.Header.Set("x-api-version", apiVersion)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var e struct {
			Message string `json:"message"`
			Code    string `json:"code"`
		}
		_ = json.Unmarshal(raw, &e)
		return fmt.Errorf("cashfree %s %s: HTTP %d %s %s", method, path, resp.StatusCode, e.Code, e.Message)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(raw, out)
}