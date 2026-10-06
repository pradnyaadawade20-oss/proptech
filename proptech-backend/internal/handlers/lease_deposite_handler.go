package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"

	"github.com/gin-gonic/gin"
)

var validMethods = map[string]bool{"upi": true, "bank_transfer": true, "cash": true, "cheque": true, "other": true}

func validMethod(m string) bool { return validMethods[m] }

var deductionCategories = map[string]bool{"damage": true, "unpaid_rent": true, "cleaning": true, "other": true}

// GET /api/leases/:id/deposit
func (h *LeaseHandler) Deposit(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	d, err := h.repo.GetDeposit(c.Request.Context(), l.ID)
	if err != nil {
		// No deposit on this lease (deposit amount was 0).
		c.JSON(http.StatusOK, gin.H{"deposit": nil})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deposit": d})
}

// POST /api/leases/:id/deposit/pay   (tenant: "deposit paid")
func (h *LeaseHandler) DepositPay(c *gin.Context) {
	l, userID, role, ok := h.party(c)
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
	ctx := c.Request.Context()
	if err := h.repo.SubmitDeposit(ctx, l.ID, req.Method, strings.TrimSpace(req.Reference)); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_submitted", "via "+req.Method)
	notify.SendRoute(l.OwnerID, "deposit", "Security deposit paid",
		fmt.Sprintf("%s says the deposit for %s is paid. Please confirm.", l.TenantName, l.PropertyTitle), leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/confirm   (owner: deposit received -> HELD)
func (h *LeaseHandler) DepositConfirm(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	var req struct {
		Method    string `json:"method"`
		Reference string `json:"reference"`
	}
	_ = c.ShouldBindJSON(&req)
	if req.Method != "" && !validMethod(req.Method) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown payment method"})
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.ConfirmDeposit(ctx, l.ID, req.Method, strings.TrimSpace(req.Reference)); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_held", "deposit received by owner")
	notify.SendRoute(l.TenantID, "deposit", "Deposit received",
		fmt.Sprintf("%s confirmed your security deposit for %s. It is now held.", l.OwnerName, l.PropertyTitle), leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/reject   (owner: not received)
func (h *LeaseHandler) DepositReject(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.RejectDeposit(ctx, l.ID); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_rejected", "owner did not receive the deposit")
	notify.SendRoute(l.TenantID, "deposit", "Deposit not received",
		fmt.Sprintf("%s did not receive the deposit for %s. Please check and submit again.", l.OwnerName, l.PropertyTitle),
		leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/inspection   (owner starts the post-move-out inspection)
func (h *LeaseHandler) DepositInspection(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.StartInspection(ctx, l); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "inspection_started", "")
	notify.SendRoute(l.TenantID, "deposit", "Deposit inspection started",
		fmt.Sprintf("%s is inspecting %s. You will see any deductions before they are final.", l.OwnerName, l.PropertyTitle),
		leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/deductions   (owner; multipart: category, reason, amount, images[])
func (h *LeaseHandler) DeductionAdd(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()

	category := strings.TrimSpace(c.PostForm("category"))
	reason := strings.TrimSpace(c.PostForm("reason"))
	amount, err := strconv.ParseFloat(strings.TrimSpace(c.PostForm("amount")), 64)
	if !deductionCategories[category] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category must be damage, unpaid_rent, cleaning or other"})
		return
	}
	if len(reason) < 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "write the reason for this deduction"})
		return
	}
	if err != nil || amount <= 0 || amount > 10000000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter a valid deduction amount"})
		return
	}
	if category == "damage" {
		// Damage needs proof — the whole point of the flow.
		form, ferr := c.MultipartForm()
		if ferr != nil || len(form.File["images"]) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "add at least one photo as proof of the damage"})
			return
		}
	}

	id, err := h.repo.AddDeduction(ctx, l.ID, userID, category, reason, amount)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if _, perr := h.savePhotos(c, l, userID, "damage", "Damage", reason, &id, nil, 6); perr != "" {
		// Photos failed validation: roll the deduction back so nothing half-saved remains.
		_ = h.repo.DeleteDeduction(ctx, l.ID, id)
		c.JSON(http.StatusBadRequest, gin.H{"error": perr})
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deduction_added", fmt.Sprintf("%s %s: %s", category, rupees(amount), reason))
	h.respondDeposit(c, l.ID)
}

// DELETE /api/leases/:id/deposit/deductions/:deductionId
func (h *LeaseHandler) DeductionDelete(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.DeleteDeduction(ctx, l.ID, c.Param("deductionId")); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deduction_removed", "")
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/settlement   (owner sends the final settlement to the tenant)
func (h *LeaseHandler) DepositSettlement(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.SubmitSettlement(ctx, l.ID); err != nil {
		leaseErr(c, err)
		return
	}
	d, err := h.repo.GetDeposit(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "settlement_sent",
		fmt.Sprintf("deductions %s, refund %s", rupees(d.TotalDeductions), rupees(d.RefundAmount)))
	notify.SendRoute(l.TenantID, "deposit", "Deposit settlement ready",
		fmt.Sprintf("Deductions %s, refund %s for %s. Please review and respond.",
			rupees(d.TotalDeductions), rupees(d.RefundAmount), l.PropertyTitle), leaseRoute(l.ID))
	c.JSON(http.StatusOK, gin.H{"deposit": d})
}

// POST /api/leases/:id/deposit/respond   (tenant accepts or disputes)
func (h *LeaseHandler) DepositRespond(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "tenant") {
		return
	}
	var req models.DepositRespondRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	note := strings.TrimSpace(req.Note)
	if !req.Accept && len(note) < 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tell us what you disagree with (at least a few words)"})
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.TenantRespond(ctx, l.ID, req.Accept, note); err != nil {
		leaseErr(c, err)
		return
	}
	if req.Accept {
		h.repo.LogEvent(ctx, l.ID, userID, "settlement_accepted", note)
		notify.SendRoute(l.OwnerID, "deposit", "Settlement accepted",
			fmt.Sprintf("%s accepted the deposit settlement for %s.", l.TenantName, l.PropertyTitle), leaseRoute(l.ID))
	} else {
		h.repo.LogEvent(ctx, l.ID, userID, "settlement_disputed", note)
		notify.SendRoute(l.OwnerID, "deposit", "Settlement disputed",
			fmt.Sprintf("%s disputed the deposit settlement for %s. PropTech support will review it.", l.TenantName, l.PropertyTitle),
			leaseRoute(l.ID))
	}
	h.respondDeposit(c, l.ID)
}

// POST /api/leases/:id/deposit/refund   (owner: refund paid back)
func (h *LeaseHandler) DepositRefund(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	var req models.DepositRefundRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose how you refunded (upi, bank_transfer, cash, cheque, other)"})
		return
	}
	if req.Method != "cash" && strings.TrimSpace(req.Reference) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the transaction / reference number"})
		return
	}
	ctx := c.Request.Context()
	if err := h.repo.MarkRefunded(ctx, l.ID, req.Method, strings.TrimSpace(req.Reference)); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_refunded", "via "+req.Method)
	notify.SendRoute(l.TenantID, "deposit", "Deposit refunded",
		fmt.Sprintf("%s marked your deposit refund for %s as paid.", l.OwnerName, l.PropertyTitle), leaseRoute(l.ID))
	h.respondDeposit(c, l.ID)
}

func (h *LeaseHandler) respondDeposit(c *gin.Context, leaseID string) {
	d, err := h.repo.GetDeposit(c.Request.Context(), leaseID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"deposit": d})
}