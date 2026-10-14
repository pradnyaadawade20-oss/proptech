package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// LandlordInviteHandler links a broker's listing to the REAL owner. The owner accepts
// from their own account (Aadhaar KYC), and the agreement names them as the landlord.
type LandlordInviteHandler struct {
	repo   *repository.LandlordInviteRepository
	kyc    *repository.KYCRepository
	leases *repository.LeaseRepository
}

func NewLandlordInviteHandler(repo *repository.LandlordInviteRepository, kyc *repository.KYCRepository, leases *repository.LeaseRepository) *LandlordInviteHandler {
	return &LandlordInviteHandler{repo: repo, kyc: kyc, leases: leases}
}

func onlyDigits(s string) string {
	var b strings.Builder
	for _, r := range s {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func looksLikeEmail(s string) bool {
	at := strings.Index(s, "@")
	return at > 0 && len(s) <= 254 && strings.Contains(s[at:], ".") && !strings.ContainsAny(s, " \t\n")
}

// writeInviteError maps repository errors to HTTP responses; false = not an invite error.
func writeInviteError(c *gin.Context, err error) bool {
	switch {
	case errors.Is(err, repository.ErrInviteNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
	case errors.Is(err, repository.ErrInviteForbidden):
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
	case errors.Is(err, repository.ErrInviteSelf), errors.Is(err, repository.ErrInviteNotBrokerListing):
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
	case errors.Is(err, repository.ErrInviteAlreadyLinked):
		c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "already_linked"})
	default:
		return false
	}
	return true
}

// POST /api/properties/:id/landlord-invite  (broker)
func (h *LandlordInviteHandler) Create(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.CreateLandlordInviteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "owner name is required"})
		return
	}
	name := strings.TrimSpace(req.Name)
	phone := strings.TrimSpace(req.Phone)
	email := strings.ToLower(strings.TrimSpace(req.Email))

	if len(name) < 2 || len(name) > 100 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the owner's full name"})
		return
	}
	if phone == "" && email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the owner's phone number or email"})
		return
	}
	if phone != "" {
		if d := onlyDigits(phone); len(d) < 10 || len(d) > 15 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "enter a valid owner phone number"})
			return
		}
	}
	if email != "" && !looksLikeEmail(email) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter a valid owner email"})
		return
	}

	invite, err := h.repo.Create(c.Request.Context(), c.Param("id"), userID, name, phone, email)
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create the invite"})
		return
	}

	// Owner already has an account -> tell them right away.
	if invite.LandlordUserID != "" {
		notify.SendRoute(invite.LandlordUserID, "landlord_invite", "Broker invitation",
			fmt.Sprintf("%s wants to list \"%s\" for you on PropTech. Open to review and accept.", notify.UserName(userID), invite.PropertyTitle),
			"/landlord-invites")
	}
	c.JSON(http.StatusCreated, gin.H{"invite": invite})
}

// GET /api/properties/:id/landlord-invite  (broker) - latest invite or null
func (h *LandlordInviteHandler) GetForProperty(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	invite, err := h.repo.LatestForProperty(c.Request.Context(), c.Param("id"), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load the invite"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"invite": invite})
}

// DELETE /api/properties/:id/landlord-invite  (broker) - withdraw a pending invite
func (h *LandlordInviteHandler) Cancel(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ok, err := h.repo.Cancel(c.Request.Context(), c.Param("id"), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not cancel the invite"})
		return
	}
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "there is no pending invite to cancel"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "invite cancelled"})
}

// GET /api/landlord-invites/mine  (owner)
func (h *LandlordInviteHandler) Mine(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	invites, err := h.repo.ListMine(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load invitations"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"invites": invites})
}

// GET /api/landlord-invites/by-code/:code  (owner enters the code a broker shared)
func (h *LandlordInviteHandler) ByCode(c *gin.Context) {
	if _, err := middleware.GetUserID(c); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	invite, err := h.repo.GetByCode(c.Request.Context(), c.Param("code"))
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not look up the code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"invite": invite})
}

type inviteActionRequest struct {
	InviteID string `json:"invite_id"`
	Code     string `json:"code"`
}

// POST /api/landlord-invites/accept  (owner)
// The owner must have verified KYC first: they are the landlord on the agreement.
func (h *LandlordInviteHandler) Accept(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req inviteActionRequest
	if err := c.ShouldBindJSON(&req); err != nil || (req.InviteID == "" && req.Code == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send the invite id or the invite code"})
		return
	}

	verified, err := h.kyc.IsVerified(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not check KYC status"})
		return
	}
	if !verified {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "complete Aadhaar KYC before accepting, as you will be the landlord on the agreement",
			"code":  "kyc_required",
		})
		return
	}
	invite, err := h.repo.Accept(c.Request.Context(), userID, req.InviteID, req.Code)
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not accept the invitation"})
		return
	}

	notify.SendRoute(invite.BrokerID, "landlord_invite", "Owner accepted your invite",
		fmt.Sprintf("%s accepted. Tenants can now request an agreement for \"%s\" and rent goes directly to the owner.",
			notify.UserName(userID), invite.PropertyTitle),
		"/owner/properties")
	c.JSON(http.StatusOK, gin.H{"invite": invite})
}

// POST /api/landlord-invites/decline  (owner)
func (h *LandlordInviteHandler) Decline(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req inviteActionRequest
	if err := c.ShouldBindJSON(&req); err != nil || (req.InviteID == "" && req.Code == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send the invite id or the invite code"})
		return
	}
	invite, err := h.repo.Decline(c.Request.Context(), userID, req.InviteID, req.Code)
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not decline the invitation"})
		return
	}
	notify.SendRoute(invite.BrokerID, "landlord_invite", "Owner declined your invite",
		fmt.Sprintf("The owner declined the invitation for \"%s\".", invite.PropertyTitle),
		"/owner/properties")
	c.JSON(http.StatusOK, gin.H{"invite": invite})
}

// GET /api/properties/:id/agreement-eligibility  (public, no private data)
func (h *LandlordInviteHandler) AgreementEligibility(c *gin.Context) {
	ok, reason, err := h.repo.AgreementEligibility(c.Request.Context(), c.Param("id"))
	if err != nil || reason == "not_found" {
		c.JSON(http.StatusNotFound, gin.H{"error": "property not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"available": ok, "reason": reason})
}