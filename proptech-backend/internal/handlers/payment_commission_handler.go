package handlers

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/receipt"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// Commission agreement between broker and tenant (see CommissionAgreement in the repository):
//   broker creates + signs -> tenant signs (or declines) -> tenant may now request the rental agreement
//   -> after the rental agreement is completed the tenant pays the commission through Cashfree.

func commissionStateErr(c *gin.Context, err error) {
	var se *repository.StateError
	if errors.As(err, &se) {
		c.JSON(http.StatusConflict, gin.H{"error": se.Msg})
		return
	}
	leaseErr(c, err)
}

// commissionAgreementFor loads :id and works out whether the caller is the agent or the tenant.
func (h *PaymentHandler) commissionAgreementFor(c *gin.Context) (*repository.CommissionAgreement, string, bool) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return nil, "", false
	}
	ca, err := h.repo.GetCommissionAgreement(c.Request.Context(), c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return nil, "", false
	}
	switch userID {
	case ca.TenantID:
		ca.Role = "tenant"
	case ca.AgentID:
		ca.Role = "agent"
	default:
		c.JSON(http.StatusForbidden, gin.H{"error": "not your commission agreement"})
		return nil, "", false
	}
	return ca, userID, true
}

func validSignature(t, data string) bool {
	return (t == "draw" || t == "type") && strings.TrimSpace(data) != "" && len(data) <= 700000
}

// POST /api/properties/:id/commission-agreement   (broker, after the visit, when the tenant is interested)
func (h *PaymentHandler) CreateCommissionAgreement(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var body struct {
		TenantEmail   string  `json:"tenant_email"`
		Amount        float64 `json:"amount"`
		Note          string  `json:"note"`
		SignatureType string  `json:"signature_type"`
		SignatureData string  `json:"signature_data"`
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
	if !strings.Contains(body.TenantEmail, "@") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the tenant's email address"})
		return
	}
	if !validSignature(body.SignatureType, body.SignatureData) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "please sign the agreement"})
		return
	}

	ctx := c.Request.Context()
	propertyID := c.Param("id")
	ownerID, postedBy, err := h.repo.PropertyPoster(ctx, propertyID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if postedBy != "broker" || ownerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the broker who listed this property can create a commission agreement"})
		return
	}
	tenantID, _, err := h.repo.UserByEmail(ctx, body.TenantEmail)
	if err != nil {
		if errors.Is(err, repository.ErrLeaseNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "No PropTech account found with this email. Ask the tenant to sign up with it first."})
			return
		}
		leaseErr(c, err)
		return
	}
	if tenantID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "you cannot be the tenant on your own listing"})
		return
	}
	ca, err := h.repo.CreateCommissionAgreement(ctx, propertyID, userID, tenantID, body.Amount, body.Note, body.SignatureType, body.SignatureData)
	if err != nil {
		commissionStateErr(c, err)
		return
	}
	ca.Role = "agent"
	notify.SendRoute(tenantID, "commission", "Commission agreement",
		fmt.Sprintf("%s sent you a commission agreement of %s for %s. Review and sign it to continue.", ca.AgentName, rupees(ca.Amount), ca.PropertyTitle),
		"/commission-agreements")
	c.JSON(http.StatusCreated, ca)
}

// GET /api/commission-agreements   -> everything where I am the agent or the tenant
func (h *PaymentHandler) ListCommissionAgreements(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	rows, err := h.repo.ListCommissionAgreements(c.Request.Context(), userID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	for i := range rows {
		if rows[i].TenantID == userID {
			rows[i].Role = "tenant"
		} else {
			rows[i].Role = "agent"
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": rows})
}

// GET /api/commission-agreements/:id
func (h *PaymentHandler) GetCommissionAgreement(c *gin.Context) {
	ca, _, ok := h.commissionAgreementFor(c)
	if !ok {
		return
	}
	c.JSON(http.StatusOK, ca)
}

// POST /api/commission-agreements/:id/sign   {signature_type, signature_data}   (tenant)
func (h *PaymentHandler) SignCommissionAgreement(c *gin.Context) {
	ca, userID, ok := h.commissionAgreementFor(c)
	if !ok || !need(c, ca.Role, "tenant") {
		return
	}
	var body struct {
		SignatureType string `json:"signature_type"`
		SignatureData string `json:"signature_data"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || !validSignature(body.SignatureType, body.SignatureData) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "please sign the agreement"})
		return
	}
	signed, err := h.repo.SignCommissionAgreement(c.Request.Context(), ca.ID, userID, body.SignatureType, body.SignatureData)
	if err != nil {
		commissionStateErr(c, err)
		return
	}
	signed.Role = "tenant"
	notify.Send(ca.AgentID, "commission", "Commission agreement signed",
		fmt.Sprintf("%s signed your commission agreement for %s. They can now request the rental agreement.", signed.TenantName, signed.PropertyTitle))
	c.JSON(http.StatusOK, signed)
}

// POST /api/commission-agreements/:id/decline   (tenant)
func (h *PaymentHandler) DeclineCommissionAgreement(c *gin.Context) {
	ca, userID, ok := h.commissionAgreementFor(c)
	if !ok || !need(c, ca.Role, "tenant") {
		return
	}
	if err := h.repo.DeclineCommissionAgreement(c.Request.Context(), ca.ID, userID); err != nil {
		commissionStateErr(c, err)
		return
	}
	notify.Send(ca.AgentID, "commission", "Commission agreement declined",
		fmt.Sprintf("%s did not accept your commission for %s. You can talk to them and send a new one.", ca.TenantName, ca.PropertyTitle))
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// POST /api/commission-agreements/:id/cancel   (broker, before the tenant signs)
func (h *PaymentHandler) CancelCommissionAgreement(c *gin.Context) {
	ca, userID, ok := h.commissionAgreementFor(c)
	if !ok || !need(c, ca.Role, "agent") {
		return
	}
	if err := h.repo.CancelCommissionAgreement(c.Request.Context(), ca.ID, userID); err != nil {
		commissionStateErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// POST /api/commission-agreements/:id/checkout   (tenant taps "Pay commission")
func (h *PaymentHandler) CommissionCheckout(c *gin.Context) {
	ca, userID, ok := h.commissionAgreementFor(c)
	if !ok || !need(c, ca.Role, "tenant") {
		return
	}
	switch {
	case ca.Status != "signed":
		c.JSON(http.StatusConflict, gin.H{"error": "please sign the commission agreement first"})
		return
	case ca.PayStatus == "paid":
		c.JSON(http.StatusConflict, gin.H{"error": "this commission is already paid"})
		return
	case ca.LeaseID == "":
		c.JSON(http.StatusConflict, gin.H{"error": "you can pay the commission once the rental agreement is signed by both owner and tenant"})
		return
	}
	h.startCheckout(c, orderSpec{
		kind: "commission", targetID: ca.LeaseID, leaseID: ca.LeaseID,
		payerID: userID, ownerID: ca.AgentID, // the money is the agent's
		amount: ca.Amount, rentAmount: ca.Amount, note: "Agent commission",
	})
}

// GET /api/commission-agreements/:id/pdf   (signed agreements only)
func (h *PaymentHandler) CommissionAgreementPDF(c *gin.Context) {
	ca, _, ok := h.commissionAgreementFor(c)
	if !ok {
		return
	}
	if ca.Status != "signed" {
		c.JSON(http.StatusConflict, gin.H{"error": "the PDF is available once both of you have signed"})
		return
	}
	fmtTime := func(t interface{ Format(string) string }) string { return t.Format("2 Jan 2006, 15:04") }
	d := receipt.CommissionAgreementData{
		AgreementNumber: ca.AgreementNumber,
		PropertyTitle:   ca.PropertyTitle,
		AgentName:       ca.AgentName,
		TenantName:      ca.TenantName,
		Amount:          ca.Amount,
		Note:            ca.Note,
		AgentSignType:   ca.AgentSignType,
		AgentSignData:   ca.AgentSignData,
		TenantSignType:  ca.TenantSignType,
		TenantSignData:  ca.TenantSignData,
	}
	if ca.AgentSignedAt != nil {
		d.AgentSignedAt = fmtTime(ca.AgentSignedAt)
	}
	if ca.TenantSignedAt != nil {
		d.TenantSignedAt = fmtTime(ca.TenantSignedAt)
	}
	c.Header("Content-Disposition", `attachment; filename="`+ca.AgreementNumber+`.pdf"`)
	c.Data(http.StatusOK, "application/pdf", receipt.BuildCommissionAgreement(d))
}

// GET /api/leases/:id/commission-agreement   (tenant or agent of that lease; shows the pay card)
func (h *PaymentHandler) LeaseCommissionAgreement(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ca, err := h.repo.CommissionAgreementForLease(c.Request.Context(), c.Param("id"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if ca == nil || (userID != ca.TenantID && userID != ca.AgentID) {
		c.JSON(http.StatusOK, gin.H{"commission_agreement": nil})
		return
	}
	if userID == ca.TenantID {
		ca.Role = "tenant"
	} else {
		ca.Role = "agent"
	}
	c.JSON(http.StatusOK, gin.H{"commission_agreement": ca})
}