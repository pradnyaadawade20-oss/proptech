package handlers

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// Agent commission flow:
//   agent proposes (PUT) -> tenant accepts (POST /accept) or declines -> both sign the rent agreement
//   -> tenant pays through Cashfree (POST /checkout, only once the lease exists).

type commissionParty struct {
	agreementID string
	userID      string
	tenantID    string
	agentID     string
	agrStatus   string
	role        string // tenant | agent
}

func agreementRoute(id string) string { return "/agreement/" + id + "/status" }

// commissionCtx finds out who is calling: the tenant of the agreement or the agent (broker) on it.
func (h *PaymentHandler) commissionCtx(c *gin.Context) (commissionParty, bool) {
	var p commissionParty
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return p, false
	}
	agentID, tenantID, status, err := h.repo.AgreementParties(c.Request.Context(), c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return p, false
	}
	p = commissionParty{agreementID: c.Param("id"), userID: userID, tenantID: tenantID, agentID: agentID, agrStatus: status}
	switch {
	case userID == tenantID:
		p.role = "tenant"
	case agentID != "" && userID == agentID:
		p.role = "agent"
	default:
		c.JSON(http.StatusForbidden, gin.H{"error": "not your agreement"})
		return p, false
	}
	return p, true
}

func agreementClosed(status string) bool {
	return status == "rejected" || status == "cancelled" || status == "expired"
}

func commissionStateErr(c *gin.Context, err error) {
	var se *repository.StateError
	if errors.As(err, &se) {
		c.JSON(http.StatusConflict, gin.H{"error": se.Msg})
		return
	}
	leaseErr(c, err)
}

// GET /api/agreements/:id/commission
func (h *PaymentHandler) GetCommission(c *gin.Context) {
	p, ok := h.commissionCtx(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	cm, err := h.repo.GetCommission(ctx, p.agreementID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	leaseID, err := h.repo.LeaseIDForAgreement(ctx, p.agreementID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	agentName := ""
	if p.agentID != "" {
		agentName, _, _, _ = h.repo.UserContact(ctx, p.agentID)
	}
	open := !agreementClosed(p.agrStatus)
	c.JSON(http.StatusOK, gin.H{
		"has_agent":  p.agentID != "",
		"agent_name": agentName,
		"role":       p.role,
		"lease_id":   leaseID,
		"commission": cm,
		"can_set":    p.role == "agent" && open && (cm == nil || cm.Status == "requested"),
		"can_accept": p.role == "tenant" && open && cm != nil && cm.Status == "requested",
		"can_pay":    p.role == "tenant" && cm != nil && cm.Status == "accepted" && leaseID != "",
	})
}

// PUT /api/agreements/:id/commission   {amount, note}   (agent proposes the commission)
func (h *PaymentHandler) SetCommission(c *gin.Context) {
	p, ok := h.commissionCtx(c)
	if !ok || !need(c, p.role, "agent") {
		return
	}
	if agreementClosed(p.agrStatus) {
		c.JSON(http.StatusConflict, gin.H{"error": "this agreement is closed"})
		return
	}
	var body struct {
		Amount float64 `json:"amount"`
		Note   string  `json:"note"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	body.Amount = math.Round(body.Amount*100) / 100
	body.Note = strings.TrimSpace(body.Note)
	if body.Amount < 1 || body.Amount > 10000000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter a commission between ₹1 and ₹1,00,00,000"})
		return
	}
	if len(body.Note) > 200 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "note is too long (max 200 characters)"})
		return
	}
	cm, err := h.repo.SetCommission(c.Request.Context(), p.agreementID, p.userID, p.tenantID, body.Amount, body.Note)
	if err != nil {
		commissionStateErr(c, err)
		return
	}
	notify.SendRoute(p.tenantID, "commission", "Agent commission",
		fmt.Sprintf("Your agent has proposed a commission of %s. Please review and accept it.", rupees(cm.Amount)), agreementRoute(p.agreementID))
	c.JSON(http.StatusOK, cm)
}

// POST /api/agreements/:id/commission/accept   (tenant)
func (h *PaymentHandler) AcceptCommission(c *gin.Context) {
	p, ok := h.commissionCtx(c)
	if !ok || !need(c, p.role, "tenant") {
		return
	}
	cm, err := h.repo.AcceptCommission(c.Request.Context(), p.agreementID, p.userID)
	if err != nil {
		commissionStateErr(c, err)
		return
	}
	notify.Send(p.agentID, "commission", "Commission accepted",
		fmt.Sprintf("The tenant accepted your commission of %s. They will pay it after the agreement is signed.", rupees(cm.Amount)))
	c.JSON(http.StatusOK, cm)
}

// POST /api/agreements/:id/commission/decline   (tenant)
func (h *PaymentHandler) DeclineCommission(c *gin.Context) {
	p, ok := h.commissionCtx(c)
	if !ok || !need(c, p.role, "tenant") {
		return
	}
	if err := h.repo.DeclineCommission(c.Request.Context(), p.agreementID, p.userID); err != nil {
		commissionStateErr(c, err)
		return
	}
	notify.Send(p.agentID, "commission", "Commission declined",
		"The tenant did not accept your commission. Please talk to them and propose an amount again.")
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// POST /api/agreements/:id/commission/checkout   (tenant taps "Pay commission")
func (h *PaymentHandler) CommissionCheckout(c *gin.Context) {
	p, ok := h.commissionCtx(c)
	if !ok || !need(c, p.role, "tenant") {
		return
	}
	ctx := c.Request.Context()
	cm, err := h.repo.GetCommission(ctx, p.agreementID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	switch {
	case cm == nil:
		c.JSON(http.StatusConflict, gin.H{"error": "your agent has not proposed a commission yet"})
		return
	case cm.Status == "paid":
		c.JSON(http.StatusConflict, gin.H{"error": "this commission is already paid"})
		return
	case cm.Status != "accepted":
		c.JSON(http.StatusConflict, gin.H{"error": "please accept the commission first"})
		return
	}
	leaseID, err := h.repo.LeaseIDForAgreement(ctx, p.agreementID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if leaseID == "" {
		c.JSON(http.StatusConflict, gin.H{"error": "you can pay the commission once both parties have signed the agreement"})
		return
	}
	h.startCheckout(c, orderSpec{
		kind: "commission", targetID: leaseID, leaseID: leaseID,
		payerID: p.userID, ownerID: p.agentID, // the money is the agent's
		amount: cm.Amount, rentAmount: cm.Amount, note: "Agent commission",
	})
}

// GET /api/agent/agreements   -> the logged-in broker's agreements with commission status
func (h *PaymentHandler) AgentAgreements(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	rows, err := h.repo.ListAgentAgreements(c.Request.Context(), userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreements": rows})
}