package handlers

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/receipt"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type LeaseHandler struct {
	repo *repository.LeaseRepository
}

func NewLeaseHandler(repo *repository.LeaseRepository) *LeaseHandler {
	return &LeaseHandler{repo: repo}
}

// leaseErr maps repository errors to HTTP answers.
func leaseErr(c *gin.Context, err error) {
	var se *repository.StateError
	switch {
	case errors.Is(err, repository.ErrLeaseNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
	case errors.As(err, &se):
		c.JSON(http.StatusConflict, gin.H{"error": se.Msg})
	default:
		log.Printf("lease handler error: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "something went wrong, please try again"})
	}
}

func leaseRoute(leaseID string) string { return "/lease/" + leaseID }

func rupees(v float64) string { return fmt.Sprintf("₹%.0f", v) }

// party loads lease :id and makes sure the caller is its owner or tenant.
// On failure it has already written the response.
func (h *LeaseHandler) party(c *gin.Context) (*models.Lease, string, string, bool) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return nil, "", "", false
	}
	l, err := h.repo.GetLease(c.Request.Context(), c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return nil, "", "", false
	}
	role := l.RoleOf(userID)
	if role == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you are not a party on this lease"})
		return nil, "", "", false
	}
	return l, userID, role, true
}

// need writes 403 unless role matches.
func need(c *gin.Context, role, want string) bool {
	if role != want {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the " + want + " can do this"})
		return false
	}
	return true
}

func otherParty(l *models.Lease, role string) string {
	if role == "owner" {
		return l.TenantID
	}
	return l.OwnerID
}

// ---------------------------------------------------------------------------
// Lease
// ---------------------------------------------------------------------------

// GET /api/leases
func (h *LeaseHandler) ListMine(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	leases, err := h.repo.ListForUser(c.Request.Context(), userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"leases": leases})
}

// GET /api/agreements/:id/lease — returns the lease of a completed agreement
// (creates it on the spot if the background job has not done it yet).
func (h *LeaseHandler) GetByAgreement(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	l, _, err := h.repo.CreateFromAgreement(c.Request.Context(), c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if l.RoleOf(userID) == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you are not a party on this lease"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": l})
}

// GET /api/leases/:id
func (h *LeaseHandler) Get(c *gin.Context) {
	l, _, role, ok := h.party(c)
	if !ok {
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": l, "role": role})
}

// GET /api/leases/:id/events
func (h *LeaseHandler) Events(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	events, err := h.repo.ListEvents(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"events": events})
}

// ---------------------------------------------------------------------------
// Monthly rent
// ---------------------------------------------------------------------------

// GET /api/leases/:id/rent
func (h *LeaseHandler) Rent(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	payments, err := h.repo.ListPayments(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	var paid, pending, overdue, lateFees float64
	for _, p := range payments {
		switch p.DisplayStatus {
		case "paid":
			paid += p.Total
			lateFees += p.LateFee
		case "overdue":
			overdue += p.Total
		default:
			pending += p.Total
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"payments": payments,
		"summary": gin.H{
			"paid_total":    paid,
			"pending_total": pending,
			"overdue_total": overdue,
			"late_fees":     lateFees,
		},
	})
}

// payment loads :paymentId + its lease and checks the caller is a party.
func (h *LeaseHandler) payment(c *gin.Context) (*models.RentPayment, *models.Lease, string, string, bool) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return nil, nil, "", "", false
	}
	p, err := h.repo.GetPayment(c.Request.Context(), c.Param("paymentId"))
	if err != nil {
		leaseErr(c, err)
		return nil, nil, "", "", false
	}
	l, err := h.repo.GetLease(c.Request.Context(), p.LeaseID)
	if err != nil {
		leaseErr(c, err)
		return nil, nil, "", "", false
	}
	role := l.RoleOf(userID)
	if role == "" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you are not a party on this lease"})
		return nil, nil, "", "", false
	}
	return p, l, userID, role, true
}

func periodLabel(dueDate string) string {
	return models.ParseDate(dueDate).Format("January 2006")
}

// POST /api/rent/:paymentId/pay   (tenant: "I have paid")
func (h *LeaseHandler) PayRent(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	var req models.PayRentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose how you paid (upi, bank_transfer, cash, cheque, other)"})
		return
	}
	if req.Method != "cash" && strings.TrimSpace(req.Reference) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the transaction / reference number"})
		return
	}
	updated, err := h.repo.SubmitPayment(c.Request.Context(), p.ID, req.Method, strings.TrimSpace(req.Reference))
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, "rent_submitted",
		fmt.Sprintf("%s rent %s via %s", periodLabel(p.DueDate), rupees(updated.Total), req.Method))
	notify.SendRoute(l.OwnerID, "rent", "Rent payment submitted",
		fmt.Sprintf("%s says %s rent for %s is paid. Please confirm.", l.TenantName, periodLabel(p.DueDate), l.PropertyTitle),
		leaseRoute(l.ID))
	c.JSON(http.StatusOK, gin.H{"payment": updated})
}

// POST /api/rent/:paymentId/confirm   (owner)
func (h *LeaseHandler) ConfirmRent(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	updated, err := h.repo.ConfirmPayment(c.Request.Context(), p.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, "rent_confirmed",
		fmt.Sprintf("%s rent confirmed, receipt %s", periodLabel(p.DueDate), updated.ReceiptNo))
	notify.SendRoute(l.TenantID, "rent", "Rent received",
		fmt.Sprintf("%s rent for %s is confirmed. Your receipt is ready.", periodLabel(p.DueDate), l.PropertyTitle),
		leaseRoute(l.ID))
	c.JSON(http.StatusOK, gin.H{"payment": updated})
}

// POST /api/rent/:paymentId/mark-paid   (owner records e.g. a cash payment himself)
func (h *LeaseHandler) MarkRentPaid(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	var req struct {
		Method    string `json:"method"`
		Reference string `json:"reference"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Method == "" {
		req.Method = "cash"
	}
	updated, err := h.repo.OwnerMarkPaid(c.Request.Context(), p.ID, req.Method, strings.TrimSpace(req.Reference))
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, "rent_marked_paid",
		fmt.Sprintf("%s rent marked paid by owner (%s)", periodLabel(p.DueDate), req.Method))
	notify.SendRoute(l.TenantID, "rent", "Rent marked as paid",
		fmt.Sprintf("%s recorded your %s rent for %s as paid.", l.OwnerName, periodLabel(p.DueDate), l.PropertyTitle),
		leaseRoute(l.ID))
	c.JSON(http.StatusOK, gin.H{"payment": updated})
}

// POST /api/rent/:paymentId/reject   (owner: "I did not receive it")
func (h *LeaseHandler) RejectRent(c *gin.Context) {
	p, l, userID, role, ok := h.payment(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	var req models.RejectPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tell the tenant why (reason is required)"})
		return
	}
	updated, err := h.repo.RejectPayment(c.Request.Context(), p.ID, strings.TrimSpace(req.Reason))
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, "rent_rejected",
		fmt.Sprintf("%s rent payment rejected: %s", periodLabel(p.DueDate), req.Reason))
	notify.SendRoute(l.TenantID, "rent", "Rent payment not received",
		fmt.Sprintf("%s did not receive your %s rent: %s", l.OwnerName, periodLabel(p.DueDate), req.Reason),
		leaseRoute(l.ID))
	c.JSON(http.StatusOK, gin.H{"payment": updated})
}

// GET /api/rent/:paymentId/receipt   -> application/pdf
func (h *LeaseHandler) Receipt(c *gin.Context) {
	p, l, _, _, ok := h.payment(c)
	if !ok {
		return
	}
	if p.Status != "paid" {
		c.JSON(http.StatusConflict, gin.H{"error": "a receipt is available only after the rent is paid"})
		return
	}
	paidDate := ""
	if p.PaidAt != nil {
		paidDate = p.PaidAt.In(time.FixedZone("IST", 5*3600+1800)).Format("2 Jan 2006")
	}
	pdf := receipt.Build(receipt.Data{
		ReceiptNo:     p.ReceiptNo,
		PropertyTitle: l.PropertyTitle,
		TenantName:    l.TenantName,
		OwnerName:     l.OwnerName,
		PeriodLabel:   periodLabel(p.DueDate),
		DueDate:       models.ParseDate(p.DueDate).Format("2 Jan 2006"),
		PaidDate:      paidDate,
		Method:        strings.ReplaceAll(p.PaymentMethod, "_", " "),
		Reference:     p.Reference,
		RentAmount:    p.Amount,
		LateFee:       p.LateFee,
		LateDays:      p.LateDays,
		Total:         p.Total,
	})
	c.Header("Content-Disposition", fmt.Sprintf(`inline; filename="%s.pdf"`, p.ReceiptNo))
	c.Data(http.StatusOK, "application/pdf", pdf)
}

// ---------------------------------------------------------------------------
// Renewal / move-out
// ---------------------------------------------------------------------------

// POST /api/leases/:id/renewal   (tenant: renew? YES / NO)
func (h *LeaseHandler) Renewal(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	var req models.RenewalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "decision must be 'renew' or 'vacate'"})
		return
	}
	ctx := c.Request.Context()

	if req.Decision == "renew" {
		if err := h.repo.RequestRenewal(ctx, l); err != nil {
			leaseErr(c, err)
			return
		}
		h.repo.LogEvent(ctx, l.ID, userID, "renewal_requested", "tenant wants to renew")
		notify.SendRoute(l.OwnerID, "lease", "Renewal request",
			fmt.Sprintf("%s wants to renew the lease for %s.", l.TenantName, l.PropertyTitle), leaseRoute(l.ID))
	} else {
		if !h.giveNotice(c, l, userID, req.MoveOutDate) {
			return
		}
	}
	updated, err := h.repo.GetLease(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": updated})
}

// POST /api/leases/:id/move-out   (tenant gives notice)
func (h *LeaseHandler) MoveOut(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	var req models.MoveOutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "move_out_date (YYYY-MM-DD) is required"})
		return
	}
	if !h.giveNotice(c, l, userID, req.MoveOutDate) {
		return
	}
	updated, err := h.repo.GetLease(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": updated})
}

func (h *LeaseHandler) giveNotice(c *gin.Context, l *models.Lease, userID, dateStr string) bool {
	d, err := time.Parse(models.DateLayout, strings.TrimSpace(dateStr))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "move-out date must look like 2026-12-31"})
		return false
	}
	if err := h.repo.GiveNotice(c.Request.Context(), l, d); err != nil {
		leaseErr(c, err)
		return false
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, "notice_given", "move-out on "+dateStr)
	notify.SendRoute(l.OwnerID, "lease", "Tenant is moving out",
		fmt.Sprintf("%s will move out of %s on %s.", l.TenantName, l.PropertyTitle, d.Format("2 Jan 2006")),
		leaseRoute(l.ID))
	return true
}

// POST /api/leases/:id/renewal/respond   (owner accepts / declines)
func (h *LeaseHandler) RenewalRespond(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	var req models.RenewalRespondRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ctx := c.Request.Context()
	newAgreementID, err := h.repo.RespondRenewal(ctx, l, req.Accept, req.MonthlyRent, req.DurationMonths)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if req.Accept {
		h.repo.LogEvent(ctx, l.ID, userID, "renewal_accepted", "new agreement "+newAgreementID)
		notify.SendRoute(l.TenantID, "agreement", "Renewal accepted",
			fmt.Sprintf("%s accepted your renewal for %s. Review and sign the new agreement.", l.OwnerName, l.PropertyTitle),
			"/agreement/"+newAgreementID+"/draft")
	} else {
		h.repo.LogEvent(ctx, l.ID, userID, "renewal_declined", "")
		notify.SendRoute(l.TenantID, "lease", "Renewal declined",
			fmt.Sprintf("%s did not accept the renewal for %s. Please plan your move-out.", l.OwnerName, l.PropertyTitle),
			leaseRoute(l.ID))
	}
	updated, err := h.repo.GetLease(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": updated, "new_agreement_id": newAgreementID})
}

// POST /api/leases/:id/move-out/complete   (owner: tenant has left -> property Available)
func (h *LeaseHandler) MoveOutComplete(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()
	n, err := h.repo.CountPhotos(ctx, l.ID, "move_out", nil, nil)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if n == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "upload at least one move-out photo before confirming the move-out"})
		return
	}
	if err := h.repo.CompleteMoveOut(ctx, l); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "moved_out", "property is available again")
	notify.SendRoute(l.TenantID, "lease", "Move-out confirmed",
		fmt.Sprintf("Your move-out from %s is confirmed. The deposit inspection comes next.", l.PropertyTitle),
		leaseRoute(l.ID))
	updated, err := h.repo.GetLease(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": updated})
}

// POST /api/leases/:id/move-in/confirm   (tenant locks the move-in photos)
func (h *LeaseHandler) MoveInConfirm(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.ConfirmMoveIn(ctx, l); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "move_in_confirmed", "move-in photos locked")
	notify.SendRoute(l.OwnerID, "lease", "Move-in confirmed",
		fmt.Sprintf("%s confirmed the move-in condition of %s.", l.TenantName, l.PropertyTitle), leaseRoute(l.ID))
	updated, err := h.repo.GetLease(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"lease": updated})
}