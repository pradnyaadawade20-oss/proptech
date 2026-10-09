package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"regexp"
	"strings"
	"time"

	"proptech-backend/internal/cashfree"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/receipt"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PaymentHandler struct {
	repo   *repository.PaymentRepository
	leases *repository.LeaseRepository
	cf     *cashfree.Client
}

func NewPaymentHandler(repo *repository.PaymentRepository, leases *repository.LeaseRepository, cf *cashfree.Client) *PaymentHandler {
	return &PaymentHandler{repo: repo, leases: leases, cf: cf}
}

var (
	ifscRe    = regexp.MustCompile(`^[A-Z]{4}0[A-Z0-9]{6}$`)
	accountRe = regexp.MustCompile(`^[0-9]{9,18}$`)
	holderRe  = regexp.MustCompile(`^[A-Za-z][A-Za-z .'-]{1,98}$`)
)

func round2f(v float64) float64 { return math.Round(v*100) / 100 }

func (h *PaymentHandler) enabled(c *gin.Context) bool {
	if !h.cf.Config().Enabled() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "online payments are not available right now"})
		return false
	}
	return true
}

func (h *PaymentHandler) userID(c *gin.Context) (string, bool) {
	id, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return "", false
	}
	return id, true
}

// lastDigits returns the last 10 digits of a phone number ("" if there are fewer).
func lastDigits(s string) string {
	var d []rune
	for _, r := range s {
		if r >= '0' && r <= '9' {
			d = append(d, r)
		}
	}
	if len(d) < 10 {
		return ""
	}
	return string(d[len(d)-10:])
}

func vendorIDFor(ownerID string) string {
	return "ow_" + strings.ReplaceAll(ownerID, "-", "")[:24]
}

func newOrderID(kind string) string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "pt_" + kind[:1] + "_" + hex.EncodeToString(b)
}

func (h *PaymentHandler) environment() string {
	if h.cf.Config().Sandbox() {
		return "SANDBOX"
	}
	return "PRODUCTION"
}

// GET /api/payments/config
func (h *PaymentHandler) Config(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"enabled":     h.cf.Config().Enabled(),
		"environment": h.environment(),
	})
}

// ---------------------------------------------------------------------------
// Owner bank onboarding
// ---------------------------------------------------------------------------

func bankView(b *repository.BankRow) *models.OwnerBank {
	if b == nil {
		return nil
	}
	v := b.OwnerBank
	return &v
}

// GET /api/owner/bank
func (h *PaymentHandler) GetBank(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	b, err := h.repo.GetBank(c.Request.Context(), userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"bank": bankView(b), "payouts_ready": b != nil && b.Status == "active"})
}

// PUT /api/owner/bank   (owner adds / changes the account that receives rent)
func (h *PaymentHandler) SaveBank(c *gin.Context) {
	if !h.enabled(c) {
		return
	}
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	var req models.SaveBankRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter account holder name, account number (twice) and IFSC"})
		return
	}
	holder := strings.TrimSpace(req.AccountHolder)
	acc := strings.TrimSpace(req.AccountNumber)
	ifsc := strings.ToUpper(strings.TrimSpace(req.IFSC))
	switch {
	case !holderRe.MatchString(holder):
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the account holder name exactly as in the bank"})
		return
	case !accountRe.MatchString(acc):
		c.JSON(http.StatusBadRequest, gin.H{"error": "account number must be 9 to 18 digits"})
		return
	case acc != strings.TrimSpace(req.ConfirmAccountNumber):
		c.JSON(http.StatusBadRequest, gin.H{"error": "the two account numbers do not match"})
		return
	case !ifscRe.MatchString(ifsc):
		c.JSON(http.StatusBadRequest, gin.H{"error": "IFSC looks wrong (example: HDFC0001234)"})
		return
	}

	ctx := c.Request.Context()
	u, err := h.repo.GetUserContact(ctx, userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	phone := lastDigits(u.Phone)
	email := strings.TrimSpace(u.Email)
	if h.cf.Config().Sandbox() {
		// Test mode: accounts created with only an email or only a phone still work.
		short := strings.ReplaceAll(userID, "-", "")[:10]
		if phone == "" {
			phone = "9999999999"
		}
		if email == "" {
			email = "owner" + short + "@example.com"
		}
	} else if phone == "" || email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "add your phone number and email in your profile first"})
		return
	}

	vendorID := vendorIDFor(userID)
	enc, err := h.cf.Config().Encrypt(acc)
	if err != nil {
		leaseErr(c, err)
		return
	}
	last4 := acc[len(acc)-4:]

	status, detail := "pending", "Bank details sent for verification"
	v, cfErr := h.cf.UpsertVendor(ctx, cashfree.VendorReq{
		VendorID: vendorID, Name: holder, Email: email, Phone: phone,
		Bank: cashfree.VendorBank{AccountNumber: acc, AccountHolder: holder, IFSC: ifsc},
	})
	if cfErr != nil {
		var ae *cashfree.APIError
		if errors.As(cfErr, &ae) && ae.Status >= 400 && ae.Status < 500 {
			// Bad bank details etc. Keep the entry so the owner can see why and fix it.
			status, detail = "verification_failed", "Cashfree rejected the details: "+ae.Message
		} else {
			log.Printf("cashfree vendor upsert failed: %v", cfErr)
			c.JSON(http.StatusBadGateway, gin.H{"error": "could not reach the payment partner, please try again"})
			return
		}
	} else {
		status = cashfree.VendorState(v.Status)
		if status == "active" {
			detail = "Ready to receive rent"
		} else if status == "pending" {
			detail = "Verification in progress (" + v.Status + ")"
		} else {
			detail = "Verification status: " + v.Status
		}
	}

	if err := h.repo.SaveBank(ctx, userID, vendorID, holder, enc, last4, ifsc, status, detail); err != nil {
		leaseErr(c, err)
		return
	}
	b, _ := h.repo.GetBank(ctx, userID)
	code := http.StatusOK
	if status == "verification_failed" {
		code = http.StatusUnprocessableEntity
	}
	c.JSON(code, gin.H{"bank": bankView(b), "payouts_ready": status == "active", "error": errIf(status == "verification_failed", detail)})
}

func errIf(cond bool, msg string) any {
	if cond {
		return msg
	}
	return nil
}

// POST /api/owner/bank/refresh   (re-check verification status at Cashfree)
func (h *PaymentHandler) RefreshBank(c *gin.Context) {
	if !h.enabled(c) {
		return
	}
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	b, err := h.repo.GetBank(ctx, userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if b == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "add your bank account first"})
		return
	}
	v, err := h.cf.GetVendor(ctx, b.VendorID)
	if err != nil {
		log.Printf("cashfree get vendor: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not reach the payment partner, please try again"})
		return
	}
	status := cashfree.VendorState(v.Status)
	detail := "Verification status: " + v.Status
	if status == "active" {
		detail = "Ready to receive rent"
	}
	_ = h.repo.SetBankStatus(ctx, userID, status, detail)
	b, _ = h.repo.GetBank(ctx, userID)
	c.JSON(http.StatusOK, gin.H{"bank": bankView(b), "payouts_ready": status == "active"})
}

// ---------------------------------------------------------------------------
// Creating a checkout (rent / deposit)
// ---------------------------------------------------------------------------

// POST /api/rent/:paymentId/online-order   (tenant)
func (h *PaymentHandler) RentOrder(c *gin.Context) {
	if !h.enabled(c) {
		return
	}
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	p, err := h.leases.GetPayment(ctx, c.Param("paymentId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	l, err := h.leases.GetLease(ctx, p.LeaseID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if l.RoleOf(userID) != "tenant" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the tenant can pay rent"})
		return
	}
	switch p.Status {
	case "paid":
		c.JSON(http.StatusConflict, gin.H{"error": "this rent is already paid"})
		return
	case "submitted":
		c.JSON(http.StatusConflict, gin.H{"error": "you already sent proof for this rent - waiting for the owner to confirm"})
		return
	}
	h.checkout(c, l, userID, "rent", p, p.Total, p.Amount, p.LateDays, p.LateFee)
}

// POST /api/leases/:id/deposit/online-order   (tenant)
func (h *PaymentHandler) DepositOrder(c *gin.Context) {
	if !h.enabled(c) {
		return
	}
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	l, err := h.leases.GetLease(ctx, c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if l.RoleOf(userID) != "tenant" {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the tenant can pay the deposit"})
		return
	}
	d, err := h.leases.GetDeposit(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "this lease has no security deposit"})
		return
	}
	switch d.Status {
	case "pending":
	case "submitted":
		c.JSON(http.StatusConflict, gin.H{"error": "you already sent proof for the deposit - waiting for the owner to confirm"})
		return
	default:
		c.JSON(http.StatusConflict, gin.H{"error": "the deposit is already paid"})
		return
	}
	h.checkout(c, l, userID, "deposit", nil, d.Amount, 0, 0, 0)
}

func (h *PaymentHandler) checkout(c *gin.Context, l *models.Lease, userID, kind string, rp *models.RentPayment, amount, rentAmount float64, lateDays int, lateFee float64) {
	ctx := c.Request.Context()
	if l.Status != "active" && l.Status != "notice_given" {
		c.JSON(http.StatusConflict, gin.H{"error": "this lease is not active"})
		return
	}
	amount = round2f(amount)
	if amount < 1 {
		c.JSON(http.StatusConflict, gin.H{"error": "nothing to pay"})
		return
	}

	bank, err := h.repo.GetBank(ctx, l.OwnerID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if bank == nil || bank.Status != "active" {
		notify.SendRoute(l.OwnerID, "payout_setup", "Add your bank account",
			fmt.Sprintf("%s wants to pay online for %s. Add your bank details to receive payments.", l.TenantName, l.PropertyTitle),
			"/owner/bank")
		c.JSON(http.StatusConflict, gin.H{"error": "the owner has not finished bank setup yet. We have reminded them - please try again later or pay another way", "code": "owner_bank_missing"})
		return
	}

	rentID := ""
	if rp != nil {
		rentID = rp.ID
	}

	// Resume the same checkout if it is still valid and nothing changed (e.g. app was closed mid-payment).
	open, err := h.repo.FindOpenOrder(ctx, kind, l.ID, rentID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if open != nil && open.PaymentSessionID != "" && open.ExpiresAt.After(time.Now().Add(2*time.Minute)) && math.Abs(open.Amount-amount) < 0.01 {
		c.JSON(http.StatusOK, gin.H{"session": h.session(open, true)})
		return
	}
	if open != nil {
		h.retire(ctx, kind, l.ID, rentID)
	}

	cfg := h.cf.Config()
	fee := round2f(amount * cfg.PlatformFeePct / 100)
	ownerAmt := round2f(amount - fee)
	expires := time.Now().Add(30 * time.Minute).UTC().Truncate(time.Second)
	orderID := newOrderID(kind)

	if err := h.repo.InsertOrder(ctx, repository.NewOrder{
		OrderID: orderID, Kind: kind, LeaseID: l.ID, RentPaymentID: rentID, PayerID: userID, OwnerID: l.OwnerID,
		VendorID: bank.VendorID, Amount: amount, RentAmount: rentAmount, LateDays: lateDays, LateFee: lateFee,
		PlatformFee: fee, OwnerAmount: ownerAmt, ExpiresAt: expires,
	}); err != nil {
		if errors.Is(err, repository.ErrOpenOrderExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "a payment is already being started, please wait a moment and try again"})
			return
		}
		leaseErr(c, err)
		return
	}

	payer, _ := h.repo.GetUserContact(ctx, userID)
	phone := lastDigits(payer.Phone)
	if phone == "" {
		phone = "9999999999" // Cashfree needs a phone; real value is used whenever the profile has one
	}
	note := "Security deposit - " + l.PropertyTitle
	if rp != nil {
		note = "Rent " + periodLabel(rp.DueDate) + " - " + l.PropertyTitle
	}
	req := cashfree.CreateOrderReq{
		OrderID:   orderID,
		Amount:    amount,
		Customer:  cashfree.Customer{ID: userID, Name: payer.Name, Email: payer.Email, Phone: phone},
		Note:      truncateStr(note, 100),
		Tags:      map[string]string{"kind": kind, "lease_id": l.ID},
		ExpiresAt: expires,
		Splits:    []cashfree.Split{{VendorID: bank.VendorID, Amount: ownerAmt}},
		ReturnURL: cfg.ReturnURL,
	}
	if strings.HasPrefix(cfg.NotifyURL, "https://") {
		req.NotifyURL = cfg.NotifyURL
	}
	cfOrder, err := h.cf.CreateOrder(ctx, req)
	if err != nil {
		log.Printf("cashfree create order failed: %v", err)
		h.repo.DropOrder(ctx, orderID)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not start the payment, please try again"})
		return
	}
	if err := h.repo.AttachCashfree(ctx, orderID, cfOrder.CFOrderID, cfOrder.PaymentSessionID); err != nil {
		leaseErr(c, err)
		return
	}
	h.leases.LogEvent(ctx, l.ID, userID, kind+"_checkout_started", fmt.Sprintf("online checkout for %s", rupees(amount)))
	o, err := h.repo.GetOrder(ctx, orderID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"session": h.session(o, false)})
}

// retire stops the old open order locally AND at Cashfree so it can never be paid later.
func (h *PaymentHandler) retire(ctx context.Context, kind, leaseID, rentID string) {
	ids, err := h.repo.SupersedeOpen(ctx, kind, leaseID, rentID)
	if err != nil {
		log.Printf("supersede orders: %v", err)
		return
	}
	for _, id := range ids {
		if err := h.cf.TerminateOrder(ctx, id); err != nil {
			log.Printf("terminate order %s: %v", id, err)
			// A late success on a superseded order is still applied/flagged by ApplySuccess.
		}
	}
}

func (h *PaymentHandler) session(o *models.PaymentOrder, resumed bool) models.CheckoutSession {
	return models.CheckoutSession{
		OrderID: o.OrderID, PaymentSessionID: o.PaymentSessionID, Amount: o.Amount,
		Environment: h.environment(), ExpiresAt: o.ExpiresAt, Resumed: resumed,
	}
}

func truncateStr(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ---------------------------------------------------------------------------
// Status / history / settlements
// ---------------------------------------------------------------------------

func outcomeOf(o *models.PaymentOrder) (string, string) {
	switch o.Status {
	case "paid":
		return "success", "Payment received"
	case "duplicate":
		return "duplicate", "This was already paid. The extra amount will be refunded."
	case "expired", "cancelled", "superseded":
		return "expired", "This payment session ended. Start the payment again."
	}
	if o.FailureReason != "" && o.LastFailedAt != nil {
		return "failed", "Payment failed: " + o.FailureReason + ". You have not been charged - please try again."
	}
	return "pending", "Waiting for the bank to confirm the payment"
}

// GET /api/payments/orders/:orderId   (payer or owner) - also re-checks Cashfree when still open
func (h *PaymentHandler) OrderStatus(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	o, err := h.repo.GetOrder(ctx, c.Param("orderId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if o.PayerID != userID && o.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your payment"})
		return
	}
	if o.Status == "created" && h.cf.Config().Enabled() {
		if fresh, err := h.syncOrder(ctx, o.OrderID); err != nil {
			log.Printf("sync order %s: %v", o.OrderID, err)
		} else if fresh != nil {
			o = fresh
		}
	}
	outcome, msg := outcomeOf(o)
	c.JSON(http.StatusOK, gin.H{"order": o, "outcome": outcome, "message": msg})
}

// GET /api/leases/:id/payments   (owner or tenant)
func (h *PaymentHandler) LeasePayments(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	l, err := h.leases.GetLease(ctx, c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if l.RoleOf(userID) == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you are not a party on this lease"})
		return
	}
	orders, err := h.repo.ListLeaseOrders(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	bank, _ := h.repo.GetBank(ctx, l.OwnerID)
	c.JSON(http.StatusOK, gin.H{
		"orders":             orders,
		"owner_payouts_ready": bank != nil && bank.Status == "active",
		"online_enabled":     h.cf.Config().Enabled(),
	})
}

// GET /api/payments/settlements   (owner: what was collected / settled)
func (h *PaymentHandler) Settlements(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	orders, err := h.repo.ListOwnerOrders(ctx, userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	totals, err := h.repo.OwnerTotals(ctx, userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	b, _ := h.repo.GetBank(ctx, userID)
	c.JSON(http.StatusOK, gin.H{"orders": orders, "totals": totals, "bank": bankView(b)})
}

// POST /api/payments/orders/:orderId/settlement   (owner: check settlement now)
func (h *PaymentHandler) RefreshSettlement(c *gin.Context) {
	if !h.enabled(c) {
		return
	}
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	o, err := h.repo.GetOrder(ctx, c.Param("orderId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if o.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the owner can do this"})
		return
	}
	if o.Status != "paid" {
		c.JSON(http.StatusConflict, gin.H{"error": "this payment is not completed"})
		return
	}
	if err := h.syncSettlement(ctx, o.OrderID); err != nil {
		log.Printf("settlement sync %s: %v", o.OrderID, err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not reach the payment partner, please try again"})
		return
	}
	o, _ = h.repo.GetOrder(ctx, o.OrderID)
	c.JSON(http.StatusOK, gin.H{"order": o})
}

// GET /api/leases/:id/deposit/receipt -> application/pdf
func (h *PaymentHandler) DepositReceipt(c *gin.Context) {
	userID, ok := h.userID(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	l, err := h.leases.GetLease(ctx, c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if l.RoleOf(userID) == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you are not a party on this lease"})
		return
	}
	d, err := h.leases.GetDeposit(ctx, l.ID)
	if err != nil || d == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "no deposit on this lease"})
		return
	}
	no, err := h.repo.DepositReceiptNo(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.ReceivedAt == nil || (d.Status == "pending" || d.Status == "submitted") {
		c.JSON(http.StatusConflict, gin.H{"error": "a receipt is available only after the deposit is received"})
		return
	}
	if no == "" {
		no = "DP-" + strings.ToUpper(strings.ReplaceAll(l.ID, "-", "")[:8])
	}
	ist := time.FixedZone("IST", 5*3600+1800)
	pdf := receipt.Build(receipt.Data{
		Title:         "SECURITY DEPOSIT RECEIPT",
		PeriodRowName: "Lease period",
		AmountLabel:   "Security deposit",
		HideLate:      true,
		ReceiptNo:     no,
		PropertyTitle: l.PropertyTitle,
		TenantName:    l.TenantName,
		OwnerName:     l.OwnerName,
		PeriodLabel:   models.ParseDate(l.StartDate).Format("2 Jan 2006") + " to " + models.ParseDate(l.EndDate).Format("2 Jan 2006"),
		PaidDate:      d.ReceivedAt.In(ist).Format("2 Jan 2006"),
		Method:        strings.ReplaceAll(d.PaymentMethod, "_", " "),
		Reference:     d.Reference,
		RentAmount:    d.Amount,
		Total:         d.Amount,
	})
	c.Header("Content-Disposition", fmt.Sprintf(`inline; filename="%s.pdf"`, no))
	c.Data(http.StatusOK, "application/pdf", pdf)
}

// ---------------------------------------------------------------------------
// Syncing with Cashfree (used by polling, the background job and webhooks)
// ---------------------------------------------------------------------------

// syncOrder asks Cashfree what happened to an open order and applies it.
func (h *PaymentHandler) syncOrder(ctx context.Context, orderID string) (*models.PaymentOrder, error) {
	attempts, err := h.cf.GetOrderPayments(ctx, orderID)
	if err != nil {
		return nil, err
	}
	failed := 0
	lastFail := ""
	for _, a := range attempts {
		switch strings.ToUpper(a.PaymentStatus) {
		case "SUCCESS":
			outcome, o, err := h.repo.ApplySuccess(ctx, orderID, a.CFPaymentID.String(), strings.ToLower(a.PaymentGroup), a.PaymentAmount)
			if err != nil {
				return nil, err
			}
			h.afterApply(outcome, o)
			return o, nil
		case "FAILED", "USER_DROPPED", "CANCELLED":
			failed++
			if t := a.FailureText(); t != "" {
				lastFail = t
			} else if lastFail == "" {
				lastFail = "payment was not completed"
			}
		}
	}
	if failed > 0 {
		_ = h.repo.RecordFailure(ctx, orderID, failed, lastFail)
	}
	// Nothing paid: if Cashfree has closed the order, close it here too.
	if cfo, err := h.cf.GetOrder(ctx, orderID); err == nil {
		switch strings.ToUpper(cfo.OrderStatus) {
		case "EXPIRED":
			_ = h.repo.CloseOrder(ctx, orderID, "expired")
		case "TERMINATED", "TERMINATION_REQUESTED":
			_ = h.repo.CloseOrder(ctx, orderID, "cancelled")
		}
	}
	return h.repo.GetOrder(ctx, orderID)
}

// afterApply sends notifications once, only when this call really changed something.
func (h *PaymentHandler) afterApply(outcome string, o *models.PaymentOrder) {
	if o == nil {
		return
	}
	what := "Security deposit"
	if o.Kind == "rent" {
		what = "Rent for " + o.PeriodLabel
	}
	switch outcome {
	case repository.OutcomeApplied:
		notify.SendRoute(o.PayerID, "payment", "Payment successful",
			fmt.Sprintf("%s of %s for %s was received. Your receipt is ready.", what, rupees(o.Amount), o.PropertyTitle), leaseRoute(o.LeaseID))
		notify.SendRoute(o.OwnerID, "payment", "Payment received",
			fmt.Sprintf("%s paid %s for %s. It will be settled to your bank account.", what, rupees(o.OwnerAmount), o.PropertyTitle), leaseRoute(o.LeaseID))
	case repository.OutcomeDuplicate:
		notify.SendRoute(o.PayerID, "payment", "Paid twice",
			fmt.Sprintf("%s for %s was already paid. The extra %s will be refunded.", what, o.PropertyTitle, rupees(o.Amount)), leaseRoute(o.LeaseID))
	case repository.OutcomeAmountMismatch:
		log.Printf("PAYMENT AMOUNT MISMATCH on order %s - needs manual review", o.OrderID)
	}
}

func (h *PaymentHandler) syncSettlement(ctx context.Context, orderID string) error {
	s, err := h.cf.GetOrderSettlement(ctx, orderID)
	if err != nil {
		return err
	}
	if s == nil {
		h.repo.TouchSettlementChecked(ctx, orderID)
		return nil
	}
	var at *time.Time
	if t, err := time.Parse(time.RFC3339, s.TransferTime); err == nil {
		at = &t
	}
	return h.repo.SetSettled(ctx, orderID, s.CFSettlementID.String(), s.TransferUTR, s.SettlementAmount, at)
}

// StartPaymentJobs: every 2 minutes, catch payments whose webhook never arrived,
// expire dead checkouts and check settlements.
func (h *PaymentHandler) StartPaymentJobs(ctx context.Context) {
	if !h.cf.Config().Enabled() {
		log.Println("Cashfree not configured - online payments and payment jobs are off")
		return
	}
	run := func() {
		ids, err := h.repo.StaleOpenOrders(ctx, 30)
		if err != nil {
			log.Println("payment jobs: stale orders:", err)
		}
		for _, id := range ids {
			if _, err := h.syncOrder(ctx, id); err != nil {
				log.Printf("payment jobs: sync %s: %v", id, err)
			}
		}
		sids, err := h.repo.SettlementCandidates(ctx, 20)
		if err != nil {
			log.Println("payment jobs: settlement candidates:", err)
		}
		for _, id := range sids {
			if err := h.syncSettlement(ctx, id); err != nil {
				log.Printf("payment jobs: settlement %s: %v", id, err)
			}
		}
	}
	go func() {
		t := time.NewTicker(2 * time.Minute)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				run()
			}
		}
	}()
}

// ---------------------------------------------------------------------------
// Webhook  POST /api/webhooks/cashfree   (public - protected by signature)
// ---------------------------------------------------------------------------

type webhookBody struct {
	Type string `json:"type"`
	Data struct {
		Order struct {
			OrderID string `json:"order_id"`
		} `json:"order"`
		Payment struct {
			CFPaymentID    json.Number `json:"cf_payment_id"`
			PaymentStatus  string      `json:"payment_status"`
			PaymentAmount  float64     `json:"payment_amount"`
			PaymentGroup   string      `json:"payment_group"`
			PaymentMessage string      `json:"payment_message"`
			ErrorDetails   *struct {
				Description string `json:"error_description"`
				Reason      string `json:"error_reason"`
			} `json:"error_details"`
		} `json:"payment"`
	} `json:"data"`
}

func (h *PaymentHandler) Webhook(c *gin.Context) {
	raw, err := c.GetRawData()
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	// 1. Signature over the RAW body. Anything unsigned / forged is rejected.
	if !h.cf.Config().VerifyWebhook(c.GetHeader("x-webhook-timestamp"), raw, c.GetHeader("x-webhook-signature")) {
		log.Printf("cashfree webhook: bad signature from %s", c.ClientIP())
		c.Status(http.StatusUnauthorized)
		return
	}
	var w webhookBody
	if err := json.Unmarshal(raw, &w); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	ctx := c.Request.Context()
	orderID := w.Data.Order.OrderID
	cfPay := w.Data.Payment.CFPaymentID.String()

	// 2. Only our own orders are handled; unknown events (refunds, other products) are acknowledged.
	handled := w.Type == "PAYMENT_SUCCESS_WEBHOOK" || w.Type == "PAYMENT_FAILED_WEBHOOK" || w.Type == "PAYMENT_USER_DROPPED_WEBHOOK"
	if !handled || !strings.HasPrefix(orderID, "pt_") {
		c.Status(http.StatusOK)
		return
	}

	// 3. Idempotency: Cashfree delivers at-least-once.
	key := w.Type + ":" + orderID + ":" + cfPay
	isNew, err := h.repo.InsertWebhookEvent(ctx, key, w.Type, orderID, raw)
	if err != nil {
		log.Printf("cashfree webhook: store event: %v", err)
		c.Status(http.StatusInternalServerError)
		return
	}
	if !isNew {
		c.Status(http.StatusOK)
		return
	}

	result := ""
	var procErr error
	switch w.Type {
	case "PAYMENT_SUCCESS_WEBHOOK":
		if strings.ToUpper(w.Data.Payment.PaymentStatus) != "SUCCESS" {
			result = "ignored: status " + w.Data.Payment.PaymentStatus
			break
		}
		outcome, o, err := h.repo.ApplySuccess(ctx, orderID, cfPay, strings.ToLower(w.Data.Payment.PaymentGroup), w.Data.Payment.PaymentAmount)
		if err != nil {
			procErr = err
			break
		}
		result = outcome
		h.afterApply(outcome, o)
	default: // failed / user dropped
		reason := w.Data.Payment.PaymentMessage
		if e := w.Data.Payment.ErrorDetails; e != nil {
			if e.Description != "" {
				reason = e.Description
			} else if e.Reason != "" {
				reason = e.Reason
			}
		}
		if w.Type == "PAYMENT_USER_DROPPED_WEBHOOK" && reason == "" {
			reason = "payment was cancelled before completing"
		}
		if reason == "" {
			reason = "payment was declined"
		}
		if err := h.repo.BumpFailure(ctx, orderID, reason); err != nil {
			procErr = err
			break
		}
		result = "failure recorded"
		if o, err := h.repo.GetOrder(ctx, orderID); err == nil && o.Status == "created" {
			notify.SendRoute(o.PayerID, "payment", "Payment failed",
				fmt.Sprintf("Your payment of %s for %s failed: %s. You were not charged - please try again.", rupees(o.Amount), o.PropertyTitle, reason),
				leaseRoute(o.LeaseID))
		}
	}
	if procErr != nil {
		// Let Cashfree's retry run this again.
		log.Printf("cashfree webhook: process %s: %v", key, procErr)
		h.repo.ForgetWebhookEvent(ctx, key)
		c.Status(http.StatusInternalServerError)
		return
	}
	h.repo.SetWebhookResult(ctx, key, result)
	c.Status(http.StatusOK)
}