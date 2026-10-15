package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	"proptech-backend/internal/cashfree"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// PaymentHandler = Cashfree online payments for rent + security deposit.
// It embeds LeaseHandler to reuse payment() / party() / need() / leaseErr().
type PaymentHandler struct {
	*LeaseHandler
	cf *cashfree.Client
}

func NewPaymentHandler(lh *LeaseHandler, cf *cashfree.Client) *PaymentHandler {
	return &PaymentHandler{LeaseHandler: lh, cf: cf}
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

// publicBase is the URL Cashfree / the browser can reach this server on.
func (h *PaymentHandler) publicBase(c *gin.Context) string {
	if b := strings.TrimRight(strings.TrimSpace(os.Getenv("PUBLIC_BASE_URL")), "/"); b != "" {
		return b
	}
	scheme := "http"
	if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
		scheme = "https"
	}
	return scheme + "://" + c.Request.Host
}

func tenDigits(phone string) string {
	var d []byte
	for i := 0; i < len(phone); i++ {
		if phone[i] >= '0' && phone[i] <= '9' {
			d = append(d, phone[i])
		}
	}
	if len(d) >= 10 {
		return string(d[len(d)-10:])
	}
	return "9999999999" // Cashfree needs a 10 digit phone; used only when the profile has none
}

type orderSpec struct {
	kind          string // rent | deposit
	targetID      string // rent_payment id | lease id
	leaseID       string
	rentPaymentID *string
	payerID       string
	ownerID       string
	amount        float64
	rentAmount    float64
	lateDays      int
	lateFee       float64
	note          string
}

func (h *PaymentHandler) checkoutJSON(c *gin.Context, o *repository.PaymentOrder) gin.H {
	return gin.H{
		"order_id":           o.OrderID,
		"payment_session_id": o.PaymentSessionID,
		"checkout_url":       h.publicBase(c) + "/pay/checkout?s=" + url.QueryEscape(o.PaymentSessionID),
		"amount":             o.Amount,
		"expires_at":         o.ExpiresAt,
		"env":                h.cf.Env,
	}
}

// startCheckout creates (or reuses) the Cashfree order and answers with the checkout link.
func (h *PaymentHandler) startCheckout(c *gin.Context, s orderSpec) {
	ctx := c.Request.Context()
	if !h.cf.Configured() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "online payment is not set up yet, please try again later"})
		return
	}
	s.amount = math.Round(s.amount*100) / 100
	if s.amount < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "amount is too small for online payment"})
		return
	}

	// Same amount + still open -> reuse it, so a double tap never creates two orders.
	open, err := h.repo.OpenOrder(ctx, s.kind, s.targetID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if open != nil && open.PaymentSessionID != "" && math.Abs(open.Amount-s.amount) < 0.01 {
		c.JSON(http.StatusOK, h.checkoutJSON(c, open))
		return
	}
	if err := h.repo.SupersedeOpen(ctx, s.kind, s.targetID); err != nil {
		leaseErr(c, err)
		return
	}

	name, phone, email, _ := h.repo.UserContact(ctx, s.payerID)
	prefix := "RENT"
	switch s.kind {
	case "deposit":
		prefix = "DEP"
	case "commission":
		prefix = "COM"
	}
	// Cashfree order_id: max 50 chars (4 + 1 + 32 + 1 + 10 = 48).
	orderID := fmt.Sprintf("%s-%s-%d", prefix, strings.ReplaceAll(s.targetID, "-", ""), time.Now().Unix())
	base := h.publicBase(c)
	notifyURL := ""
	if strings.HasPrefix(base, "https://") {
		notifyURL = base + "/api/payments/webhook"
	}
	expires := time.Now().Add(45 * time.Minute)

	cfo, err := h.cf.CreateOrder(ctx, cashfree.CreateOrderReq{
		OrderID: orderID,
		Amount:  s.amount,
		Note:    s.note,
		Customer: cashfree.Customer{
			ID: "u_" + strings.ReplaceAll(s.payerID, "-", ""), Name: name, Phone: tenDigits(phone), Email: email,
		},
		ReturnURL:  base + "/pay/return?order_id={order_id}",
		NotifyURL:  notifyURL,
		ExpiryTime: expires,
	})
	if err != nil {
		log.Printf("cashfree create order failed: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not start the payment, please try again"})
		return
	}

	o := &repository.PaymentOrder{
		OrderID: orderID, Kind: s.kind, LeaseID: s.leaseID, RentPaymentID: s.rentPaymentID,
		PayerID: s.payerID, OwnerID: s.ownerID, Amount: s.amount, RentAmount: s.rentAmount,
		LateDays: s.lateDays, LateFee: s.lateFee, CFOrderID: cfo.CFOrderID,
		PaymentSessionID: cfo.PaymentSessionID, ExpiresAt: expires,
	}
	if err := h.repo.InsertOrder(ctx, o); err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, h.checkoutJSON(c, o))
}

// ---------------------------------------------------------------------------
// tenant: start a payment
// ---------------------------------------------------------------------------

// POST /api/rent/:paymentId/checkout   (tenant taps "Pay rent")
func (h *PaymentHandler) RentCheckout(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	if p.Status != "pending" {
		c.JSON(http.StatusConflict, gin.H{"error": "this rent is already paid or waiting for confirmation"})
		return
	}
	pid := p.ID
	h.startCheckout(c, orderSpec{
		kind: "rent", targetID: p.ID, leaseID: l.ID, rentPaymentID: &pid,
		payerID: userID, ownerID: l.OwnerID,
		amount: p.Total, rentAmount: p.Amount, lateDays: p.LateDays, lateFee: p.LateFee,
		note: "Rent " + periodLabel(p.DueDate),
	})
}

// POST /api/leases/:id/deposit/checkout   (tenant taps "Pay deposit")
func (h *PaymentHandler) DepositCheckout(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	d, err := h.repo.GetDeposit(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.Status != "pending" {
		c.JSON(http.StatusConflict, gin.H{"error": "the deposit is not waiting for payment"})
		return
	}
	h.startCheckout(c, orderSpec{
		kind: "deposit", targetID: l.ID, leaseID: l.ID,
		payerID: userID, ownerID: l.OwnerID,
		amount: d.Amount, rentAmount: d.Amount, note: "Security deposit",
	})
}

// ---------------------------------------------------------------------------
// status (app polls this after the Cashfree page closes) + shared "mark paid"
// ---------------------------------------------------------------------------

// settle finalizes a paid order and tells both people. Safe to call repeatedly.
func (h *PaymentHandler) settle(ctx context.Context, o *repository.PaymentOrder, cfPaymentID, group string, amount float64) (string, error) {
	method := cashfree.MethodName(group)
	fin, done, dup, err := h.repo.FinalizeOrder(ctx, o.OrderID, cfPaymentID, method, amount)
	if err != nil {
		return "", err
	}
	if dup {
		if done {
			log.Printf("DUPLICATE PAYMENT order=%s lease=%s amount=%.2f - already settled, refund manually", o.OrderID, o.LeaseID, amount)
			h.repo.LogEvent(ctx, o.LeaseID, o.PayerID, "payment_duplicate", "Extra online payment "+o.OrderID+" needs a refund")
		}
		return "duplicate", nil
	}
	if done {
		h.afterPaid(ctx, fin)
	}
	return "paid", nil
}

func (h *PaymentHandler) afterPaid(ctx context.Context, o *repository.PaymentOrder) {
	l, err := h.repo.GetLease(ctx, o.LeaseID)
	if err != nil {
		return
	}
	via := "online (" + o.PaymentMethod + ")"
	if o.Kind == "commission" {
		h.repo.LogEvent(ctx, l.ID, o.PayerID, "commission_paid_online", "Agent commission "+rupees(o.Amount)+" paid "+via)
		notify.SendRoute(l.TenantID, "commission", "Commission paid",
			fmt.Sprintf("Your agent commission of %s for %s is paid. Receipt is ready.", rupees(o.Amount), l.PropertyTitle), leaseRoute(l.ID))
		notify.Send(o.OwnerID, "commission", "Commission received",
			fmt.Sprintf("%s paid your commission of %s for %s.", l.TenantName, rupees(o.Amount), l.PropertyTitle))
		return
	}
	if o.Kind == "rent" && o.RentPaymentID != nil {
		label := "rent"
		if p, err := h.repo.GetPayment(ctx, *o.RentPaymentID); err == nil {
			label = periodLabel(p.DueDate) + " rent"
		}
		h.repo.LogEvent(ctx, l.ID, o.PayerID, "rent_paid_online", fmt.Sprintf("%s %s paid %s", label, rupees(o.Amount), via))
		notify.SendRoute(l.TenantID, "rent", "Payment successful",
			fmt.Sprintf("Your %s of %s for %s is paid. Receipt is ready.", label, rupees(o.Amount), l.PropertyTitle), leaseRoute(l.ID))
		notify.SendRoute(l.OwnerID, "rent", "Rent received",
			fmt.Sprintf("%s paid %s for %s (%s).", l.TenantName, rupees(o.Amount), l.PropertyTitle, label), leaseRoute(l.ID))
		return
	}
	h.repo.LogEvent(ctx, l.ID, o.PayerID, "deposit_paid_online", "Security deposit "+rupees(o.Amount)+" paid "+via)
	notify.SendRoute(l.TenantID, "deposit", "Deposit paid",
		fmt.Sprintf("Your security deposit of %s for %s is paid and held.", rupees(o.Amount), l.PropertyTitle), leaseRoute(l.ID))
	notify.SendRoute(l.OwnerID, "deposit", "Security deposit received",
		fmt.Sprintf("%s paid the security deposit of %s for %s.", l.TenantName, rupees(o.Amount), l.PropertyTitle), leaseRoute(l.ID))
}

// GET /api/payments/orders/:orderId   -> {status: paid | pending | expired | duplicate, failure_reason}
func (h *PaymentHandler) OrderStatus(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ctx := c.Request.Context()
	o, err := h.repo.GetOrderByOrderID(ctx, c.Param("orderId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if userID != o.PayerID && userID != o.OwnerID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your payment"})
		return
	}

	status, reason := o.Status, o.FailureReason
	switch o.Status {
	case "paid":
		status = "paid"
	case "duplicate":
		status = "duplicate"
	case "expired", "cancelled":
		status = "expired"
	default: // created / superseded: ask Cashfree (the webhook may be late or missing)
		status = "pending"
		if h.cf.Configured() {
			status, reason = h.syncWithCashfree(ctx, o, reason)
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"status": status, "failure_reason": reason, "order_id": o.OrderID,
		"kind": o.Kind, "amount": o.Amount, "lease_id": o.LeaseID,
	})
}

func (h *PaymentHandler) syncWithCashfree(ctx context.Context, o *repository.PaymentOrder, lastReason string) (string, string) {
	cfo, err := h.cf.GetOrder(ctx, o.OrderID)
	if err != nil {
		log.Printf("cashfree get order %s: %v", o.OrderID, err)
		return "pending", lastReason
	}
	payments, perr := h.cf.GetPayments(ctx, o.OrderID)
	if perr != nil {
		log.Printf("cashfree get payments %s: %v", o.OrderID, perr)
	}

	if strings.EqualFold(cfo.OrderStatus, "PAID") {
		for _, p := range payments {
			if strings.EqualFold(p.Status, "SUCCESS") {
				st, err := h.settle(ctx, o, p.CFPaymentID.String(), p.Group, p.Amount)
				if err != nil {
					log.Printf("settle %s: %v", o.OrderID, err)
					return "pending", lastReason
				}
				return st, ""
			}
		}
		return "pending", lastReason
	}
	switch strings.ToUpper(cfo.OrderStatus) {
	case "EXPIRED", "TERMINATED", "TERMINATION_REQUESTED":
		_ = h.repo.ExpireOrder(ctx, o.OrderID)
		return "expired", lastReason
	}
	// Still active: surface the latest failed attempt so the tenant knows why.
	reason := lastReason
	for _, p := range payments {
		if strings.EqualFold(p.Status, "FAILED") && p.Message != "" {
			reason = p.Message
		}
	}
	return "pending", reason
}

// ---------------------------------------------------------------------------
// background sweeper: works even if the webhook is not set up / was missed
// ---------------------------------------------------------------------------

// SweepOpenOrders asks Cashfree about every open order and settles the ones that got paid.
func (h *PaymentHandler) SweepOpenOrders(ctx context.Context) {
	if !h.cf.Configured() {
		return
	}
	orders, err := h.repo.ListOpenOrders(ctx)
	if err != nil {
		log.Printf("payment sweeper: %v", err)
		return
	}
	for i := range orders {
		h.syncWithCashfree(ctx, &orders[i], orders[i].FailureReason)
	}
}

// StartSweeper checks open orders every 2 minutes.
func (h *PaymentHandler) StartSweeper(ctx context.Context) {
	go func() {
		t := time.NewTicker(2 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				h.SweepOpenOrders(ctx)
			}
		}
	}()
}

// ---------------------------------------------------------------------------
// webhook (Cashfree -> us). Public route, protected by the HMAC signature.
// ---------------------------------------------------------------------------

type webhookEvent struct {
	Type string `json:"type"`
	Data struct {
		Order struct {
			OrderID string `json:"order_id"`
		} `json:"order"`
		Payment struct {
			CFPaymentID json.Number `json:"cf_payment_id"`
			Status      string      `json:"payment_status"`
			Amount      float64     `json:"payment_amount"`
			Group       string      `json:"payment_group"`
			Message     string      `json:"payment_message"`
		} `json:"payment"`
	} `json:"data"`
}

// POST /api/payments/webhook
func (h *PaymentHandler) Webhook(c *gin.Context) {
	raw, err := io.ReadAll(io.LimitReader(c.Request.Body, 1<<20))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if !h.cf.VerifyWebhook(c.GetHeader("x-webhook-timestamp"), c.GetHeader("x-webhook-signature"), raw) {
		c.Status(http.StatusUnauthorized)
		return
	}
	var ev webhookEvent
	if err := json.Unmarshal(raw, &ev); err != nil {
		c.Status(http.StatusOK) // not an event we understand (e.g. dashboard test ping)
		return
	}
	switch ev.Type {
	case "PAYMENT_SUCCESS_WEBHOOK", "PAYMENT_FAILED_WEBHOOK", "PAYMENT_USER_DROPPED_WEBHOOK":
	default:
		c.Status(http.StatusOK)
		return
	}

	ctx := c.Request.Context()
	orderID := ev.Data.Order.OrderID
	cfPay := ev.Data.Payment.CFPaymentID.String()
	key := ev.Type + ":" + orderID + ":" + cfPay

	fresh, err := h.repo.LogWebhook(ctx, key, ev.Type, orderID, raw)
	if err != nil {
		log.Printf("webhook log: %v", err)
		c.Status(http.StatusInternalServerError) // Cashfree retries
		return
	}
	if !fresh {
		c.Status(http.StatusOK)
		return
	}

	result := "ok"
	o, err := h.repo.GetOrderByOrderID(ctx, orderID)
	switch {
	case errors.Is(err, repository.ErrLeaseNotFound):
		result = "unknown_order"
	case err != nil:
		log.Printf("webhook order lookup: %v", err)
		c.Status(http.StatusInternalServerError)
		return
	case ev.Type == "PAYMENT_SUCCESS_WEBHOOK":
		if _, err := h.settle(ctx, o, cfPay, ev.Data.Payment.Group, ev.Data.Payment.Amount); err != nil {
			var se *repository.StateError
			if errors.As(err, &se) {
				log.Printf("webhook %s: %v", orderID, err)
				result = "rejected: " + se.Msg
			} else {
				log.Printf("webhook settle %s: %v", orderID, err)
				c.Status(http.StatusInternalServerError)
				return
			}
		}
	default: // failed / user dropped
		msg := ev.Data.Payment.Message
		if msg == "" {
			msg = "Payment was not completed"
		}
		_ = h.repo.MarkFailure(ctx, orderID, msg)
	}
	h.repo.WebhookDone(ctx, key, result)
	c.Status(http.StatusOK)
}

// ---------------------------------------------------------------------------
// Pages opened in the browser (no login: the page only holds the one-time payment session id)
// ---------------------------------------------------------------------------

var sessionRe = regexp.MustCompile(`^[A-Za-z0-9_\-=+/.]{10,600}$`)

// GET /pay/checkout?s=<payment_session_id>   -> opens Cashfree's page (UPI / card / netbanking)
func (h *PaymentHandler) CheckoutPage(c *gin.Context) {
	s := c.Query("s")
	if !sessionRe.MatchString(s) {
		c.Data(http.StatusBadRequest, "text/html; charset=utf-8", []byte(simplePage("Invalid link", "This payment link is not valid. Please go back to the app and tap Pay again.")))
		return
	}
	mode := "sandbox"
	if h.cf != nil && h.cf.Env == "production" {
		mode = "production"
	}
	page := fmt.Sprintf(`<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Secure payment</title>
<style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;color:#333}</style>
<script src="https://sdk.cashfree.com/js/v3/cashfree.js"></script></head>
<body><p>Opening secure payment…</p>
<script>
  var cashfree = Cashfree({mode: "%s"});
  cashfree.checkout({paymentSessionId: "%s", redirectTarget: "_self"});
</script></body></html>`, mode, s)
	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(page))
}

// GET /pay/return?order_id=...   -> where Cashfree sends the browser when done
func (h *PaymentHandler) ReturnPage(c *gin.Context) {
	c.Header("Cache-Control", "no-store")
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(simplePage(
		"Thank you",
		"Your payment is being confirmed. Please go back to the app - the status updates automatically.")))
}

func simplePage(title, msg string) string {
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>` + title + `</title><style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;padding:24px;text-align:center;color:#333}
h2{margin:0 0 8px}</style></head><body><div><h2>` + title + `</h2><p>` + msg + `</p></div></body></html>`
}