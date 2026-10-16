package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"os"
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
	props  *repository.PropertyRepository
}

func NewLandlordInviteHandler(repo *repository.LandlordInviteRepository, kyc *repository.KYCRepository, leases *repository.LeaseRepository, props *repository.PropertyRepository) *LandlordInviteHandler {
	return &LandlordInviteHandler{repo: repo, kyc: kyc, leases: leases, props: props}
}

// shareURL is the link the broker sends to the owner (WhatsApp / SMS). It opens the app via
// Android App Links, or the landing page (see InviteLandingPage) when the app is not installed.
func shareURL(c *gin.Context, token string) string {
	return baseURL(c) + "/o/" + token
}

// withShareURL fills ShareURL for the broker who owns the invite.
func (h *LandlordInviteHandler) withShareURL(c *gin.Context, inv *models.LandlordInvite) *models.LandlordInvite {
	if inv != nil && inv.Token != "" {
		inv.ShareURL = shareURL(c, inv.Token)
	}
	return inv
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
			fmt.Sprintf("%s wants to list \"%s\" for you on PropTech. Open to review and approve.", notify.UserName(userID), invite.PropertyTitle),
			"/landlord-invites")
	}
	c.JSON(http.StatusCreated, gin.H{"invite": h.withShareURL(c, invite)})
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
	c.JSON(http.StatusOK, gin.H{"invite": h.withShareURL(c, invite)})
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

// GET /api/landlord-invites/by-token/:token  (owner opened the share link and is logged in)
// Returns the invitation and the full listing so the owner can review it before approving.
func (h *LandlordInviteHandler) ByToken(c *gin.Context) {
	if _, err := middleware.GetUserID(c); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	invite, err := h.repo.GetByToken(c.Request.Context(), c.Param("token"))
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not open the invitation"})
		return
	}
	prop, err := h.props.GetByID(c.Request.Context(), invite.PropertyID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "this property no longer exists"})
		return
	}
	one := []models.Property{*prop}
	h.props.AttachMedia(c.Request.Context(), one, baseURL(c))
	c.JSON(http.StatusOK, models.LandlordInviteView{Invite: invite, Property: &one[0]})
}

type inviteActionRequest struct {
	InviteID string `json:"invite_id"`
	Token    string `json:"token"`
}

// POST /api/landlord-invites/accept  (owner)
// This is the owner's APPROVAL: the listing goes live right now, not before. The owner
// must have verified KYC first: they are the landlord on the agreement.
func (h *LandlordInviteHandler) Accept(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req inviteActionRequest
	if err := c.ShouldBindJSON(&req); err != nil || (req.InviteID == "" && req.Token == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send the invite id or the link token"})
		return
	}

	verified, err := h.kyc.IsVerified(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not check KYC status"})
		return
	}
	if !verified {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "complete Aadhaar KYC before approving, as you will be the landlord on the agreement",
			"code":  "kyc_required",
		})
		return
	}
	invite, err := h.repo.Accept(c.Request.Context(), userID, req.InviteID, req.Token)
	if err != nil {
		if writeInviteError(c, err) {
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not accept the invitation"})
		return
	}

	notify.SendRoute(invite.BrokerID, "landlord_invite", "Owner approved your listing",
		fmt.Sprintf("%s approved \"%s\". It is now live for tenants, and they can request an agreement.",
			notify.UserName(userID), invite.PropertyTitle),
		"/property/"+invite.PropertyID)

	// Only now is the listing public, so only now does everyone hear about it.
	if os.Getenv("NOTIFY_NEW_LISTINGS") != "false" {
		brokerID, title, propID := invite.BrokerID, invite.PropertyTitle, invite.PropertyID
		notify.BroadcastExcept(brokerID, "property", "New property listed", title, "/property/"+propID)
	}
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
	if err := c.ShouldBindJSON(&req); err != nil || (req.InviteID == "" && req.Token == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send the invite id or the link token"})
		return
	}
	invite, err := h.repo.Decline(c.Request.Context(), userID, req.InviteID, req.Token)
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