package handlers

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/receipt"

	"github.com/gin-gonic/gin"
)

var (
	utrRe = regexp.MustCompile(`^[0-9]{12}$`)
	upiRe = regexp.MustCompile(`^[a-zA-Z0-9._-]{2,64}@[a-zA-Z][a-zA-Z0-9]{1,31}$`)
)

// ---------------------------------------------------------------------------
// Owner UPI id
// ---------------------------------------------------------------------------

// GET /api/owner/upi
func (h *LeaseHandler) OwnerUPIGet(c *gin.Context) {
	userID, ok := ownerCaller(c)
	if !ok {
		return
	}
	upi, err := h.repo.GetOwnerUPI(c.Request.Context(), userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"upi_id": upi})
}

// PUT /api/owner/upi   {"upi_id": "name@bank"}
func (h *LeaseHandler) OwnerUPISet(c *gin.Context) {
	userID, ok := ownerCaller(c)
	if !ok {
		return
	}
	var req struct {
		UPIID string `json:"upi_id"`
	}
	_ = c.ShouldBindJSON(&req)
	upi := strings.ToLower(strings.TrimSpace(req.UPIID))
	if !upiRe.MatchString(upi) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter a valid UPI ID, for example name@okhdfcbank"})
		return
	}
	if err := h.repo.SetOwnerUPI(c.Request.Context(), userID, upi); err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"upi_id": upi})
}

func ownerCaller(c *gin.Context) (string, bool) {
	v, ok := c.Get("user_id")
	id, _ := v.(string)
	if !ok || id == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return "", false
	}
	return id, true
}

// ---------------------------------------------------------------------------
// UPI pay link (UPI id + amount are decided by the SERVER, not typed by the tenant)
// ---------------------------------------------------------------------------

func upiLink(upi, name string, amount float64, note string) string {
	q := url.Values{}
	q.Set("pa", upi)
	q.Set("pn", name)
	q.Set("am", fmt.Sprintf("%.2f", amount))
	q.Set("cu", "INR")
	q.Set("tn", note)
	return "upi://pay?" + strings.ReplaceAll(q.Encode(), "+", "%20")
}

// ownerUPIOrExplain returns the owner's UPI id, or answers 409 (and nudges the owner) when missing.
func (h *LeaseHandler) ownerUPIOrExplain(c *gin.Context, l *models.Lease) (string, bool) {
	upi, err := h.repo.GetOwnerUPI(c.Request.Context(), l.OwnerID)
	if err != nil {
		leaseErr(c, err)
		return "", false
	}
	if upi == "" {
		notify.SendRoute(l.OwnerID, "payout_setup", "Add your UPI ID",
			fmt.Sprintf("%s wants to pay for %s by UPI. Add your UPI ID in your lease or profile.", l.TenantName, l.PropertyTitle),
			leaseRoute(l.ID))
		c.JSON(http.StatusConflict, gin.H{"error": "the owner has not added a UPI ID yet. We have reminded them - please try again later or pay another way", "code": "owner_upi_missing"})
		return "", false
	}
	return upi, true
}

// GET /api/rent/:paymentId/upi-link   (tenant)
func (h *LeaseHandler) RentUPILink(c *gin.Context) {
	p, l, _, role, ok := h.payment(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	if p.Status != "pending" {
		c.JSON(http.StatusConflict, gin.H{"error": "this rent is already submitted or paid"})
		return
	}
	upi, ok := h.ownerUPIOrExplain(c, l)
	if !ok {
		return
	}
	note := "Rent " + periodLabel(p.DueDate)
	c.JSON(http.StatusOK, gin.H{
		"upi_id": upi, "payee_name": l.OwnerName, "amount": p.Total, "note": note,
		"link": upiLink(upi, l.OwnerName, p.Total, note),
	})
}

// GET /api/leases/:id/deposit/upi-link   (tenant)
func (h *LeaseHandler) DepositUPILink(c *gin.Context) {
	l, _, role, ok := h.party(c)
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
	upi, ok := h.ownerUPIOrExplain(c, l)
	if !ok {
		return
	}
	note := "Security deposit"
	c.JSON(http.StatusOK, gin.H{
		"upi_id": upi, "payee_name": l.OwnerName, "amount": d.Amount, "note": note,
		"link": upiLink(upi, l.OwnerName, d.Amount, note),
	})
}

// ---------------------------------------------------------------------------
// Submit proof: UTR (12 digits) + screenshot, multipart form
// ---------------------------------------------------------------------------

func readUPIProof(c *gin.Context) (utr, ctype string, data []byte, ok bool) {
	limitBody(c)
	utr = strings.TrimSpace(c.PostForm("utr"))
	if !utrRe.MatchString(utr) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the 12-digit UTR / transaction number shown in your UPI app"})
		return
	}
	fh, err := c.FormFile("screenshot")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "attach the payment screenshot"})
		return
	}
	if fh.Size > leasePhotoMaxBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "screenshot is too large (max 8 MB)"})
		return
	}
	f, err := fh.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read the screenshot"})
		return
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, leasePhotoMaxBytes+1))
	if err != nil || len(raw) == 0 || len(raw) > leasePhotoMaxBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read the screenshot"})
		return
	}
	ct, isImg := imageType(fh.Header.Get("Content-Type"), raw)
	if !isImg {
		c.JSON(http.StatusBadRequest, gin.H{"error": "the screenshot must be an image (JPG, PNG or WebP)"})
		return
	}
	return utr, ct, raw, true
}

// POST /api/rent/:paymentId/upi-submit   (tenant)
func (h *LeaseHandler) RentUPISubmit(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	utr, ct, data, ok := readUPIProof(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.SubmitRentUPI(ctx, p, userID, utr, ct, data); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "rent_submitted",
		fmt.Sprintf("%s rent %s via UPI, UTR %s", periodLabel(p.DueDate), rupees(p.Total), utr))
	notify.SendRoute(l.OwnerID, "rent", "Rent payment submitted",
		fmt.Sprintf("%s paid %s rent for %s by UPI (UTR %s). Check your bank and confirm.", l.TenantName, periodLabel(p.DueDate), l.PropertyTitle, utr),
		leaseRoute(l.ID))
	updated, err := h.repo.GetPayment(ctx, p.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"payment": updated})
}

// POST /api/leases/:id/deposit/upi-submit   (tenant)
func (h *LeaseHandler) DepositUPISubmit(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	utr, ct, data, ok := readUPIProof(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.SubmitDepositUPI(ctx, l.ID, userID, utr, ct, data); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_submitted", "via UPI, UTR "+utr)
	notify.SendRoute(l.OwnerID, "deposit", "Security deposit paid",
		fmt.Sprintf("%s paid the deposit for %s by UPI (UTR %s). Check your bank and confirm.", l.TenantName, l.PropertyTitle, utr),
		leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

// ---------------------------------------------------------------------------
// View proof (owner or tenant of that lease)
// ---------------------------------------------------------------------------

// GET /api/rent/:paymentId/proof
func (h *LeaseHandler) RentProof(c *gin.Context) {
	p, _, _, _, ok := h.payment(c)
	if !ok {
		return
	}
	h.serveProof(c, "rent", p.ID)
}

// GET /api/leases/:id/deposit/proof
func (h *LeaseHandler) DepositProof(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	h.serveProof(c, "deposit", l.ID)
}

func (h *LeaseHandler) serveProof(c *gin.Context, kind, targetID string) {
	data, ct, err := h.repo.GetProof(c.Request.Context(), kind, targetID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.Header("Cache-Control", "private, max-age=300")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, ct, data)
}

// ---------------------------------------------------------------------------
// Deposit receipt PDF (after the owner confirmed the deposit)
// ---------------------------------------------------------------------------

// GET /api/leases/:id/deposit/receipt
func (h *LeaseHandler) DepositReceipt(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	d, err := h.repo.GetDeposit(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.ReceivedAt == nil || d.Status == "pending" || d.Status == "submitted" {
		c.JSON(http.StatusConflict, gin.H{"error": "a receipt is available only after the owner confirms the deposit"})
		return
	}
	no := "DP-" + d.ReceivedAt.Format("0601") + "-" + strings.ToUpper(strings.ReplaceAll(d.ID, "-", "")[:6])
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