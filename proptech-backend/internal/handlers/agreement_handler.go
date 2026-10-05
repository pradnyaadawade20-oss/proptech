package handlers

import (
	"crypto/rand"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"

	"proptech-backend/internal/mail"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type AgreementHandler struct {
	repo   *repository.AgreementRepository
	mailer *mail.Mailer
	leads  *repository.LeadRepository
}

func NewAgreementHandler(repo *repository.AgreementRepository, mailer *mail.Mailer, leads *repository.LeadRepository) *AgreementHandler {
	return &AgreementHandler{repo: repo, mailer: mailer, leads: leads}
}

func (h *AgreementHandler) CreateAgreement(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.CreateAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.OwnerID != userID && req.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you must be the owner or tenant on this agreement"})
		return
	}

	agreement, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	notifyOtherParty(agreement, userID, "New agreement request",
		fmt.Sprintf("%s requested an agreement for %s", notify.UserName(userID), agreement.PropertyTitle))

	c.JSON(http.StatusCreated, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) GetAgreements(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreements, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreements": agreements})
}

func (h *AgreementHandler) GetAgreementByID(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreement, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if agreement.OwnerID != userID && agreement.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you're not a party on this agreement"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) UpdateDraft(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ag0, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if ag0.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the owner can edit the draft"})
		return
	}

	var req models.UpdateDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agreement, err := h.repo.UpdateDraft(c.Request.Context(), id, req)
	if err != nil {
		if errors.Is(err, repository.ErrAgreementLocked) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	notifyOtherParty(agreement, userID, "Agreement draft updated",
		fmt.Sprintf("The draft agreement for %s was updated", agreement.PropertyTitle))

	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) SignAgreement(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreement, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}

	var req models.SignAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if (req.SignerRole == "owner" && agreement.OwnerID != userID) ||
		(req.SignerRole == "tenant" && agreement.TenantID != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only sign as yourself"})
		return
	}

	signed, err := h.repo.Sign(c.Request.Context(), id, req)
	if err != nil {
		if errors.Is(err, repository.ErrOTPNotVerified) || errors.Is(err, repository.ErrAgreementBadState) || errors.Is(err, repository.ErrAlreadySigned) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Lead hook: both parties signed -> tenant's lead is "closed".
	if signed.Status == "completed" {
		if lerr := h.leads.Advance(c.Request.Context(), signed.PropertyID, signed.TenantID, "closed"); lerr != nil {
			log.Printf("lead advance (closed) failed: %v", lerr)
		}
	}
	notifyOtherParty(signed, userID, "Agreement signed",
		fmt.Sprintf("%s signed the agreement for %s", notify.UserName(userID), signed.PropertyTitle))

	c.JSON(http.StatusOK, gin.H{"agreement": signed})
}

// SendSignOTP emails a 6-digit code to the signer; must be verified before signing.
func (h *AgreementHandler) SendSignOTP(c *gin.Context) {
	id := c.Param("id")
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.AgreementOTPSendRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ag, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if (req.SignerRole == "owner" && ag.OwnerID != userID) || (req.SignerRole == "tenant" && ag.TenantID != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only sign as yourself"})
		return
	}
	if ag.Status == "requested" || ag.Status == "completed" || ag.Status == "rejected" || ag.Status == "cancelled" {
		c.JSON(http.StatusConflict, gin.H{"error": repository.ErrAgreementBadState.Error()})
		return
	}
	email, err := h.repo.PartyEmail(c.Request.Context(), id, req.SignerRole)
	if err != nil || email == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no email on your account to send the OTP"})
		return
	}
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not generate OTP"})
		return
	}
	code := fmt.Sprintf("%06d", n.Int64())
	if err := h.repo.SetOTP(c.Request.Context(), id, req.SignerRole, code); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create OTP"})
		return
	}
	if err := h.mailer.SendOTP(c.Request.Context(), email, code); err != nil {
		log.Printf("agreement otp mail failed: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not send OTP email, try again"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "OTP sent"})
}

// VerifySignOTP checks the code; after this the party can call /sign.
func (h *AgreementHandler) VerifySignOTP(c *gin.Context) {
	id := c.Param("id")
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.AgreementOTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ag, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if (req.SignerRole == "owner" && ag.OwnerID != userID) || (req.SignerRole == "tenant" && ag.TenantID != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only sign as yourself"})
		return
	}
	if err := h.repo.VerifyOTP(c.Request.Context(), id, req.SignerRole, req.Code); err != nil {
		if errors.Is(err, repository.ErrOTPInvalid) {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not verify OTP"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"verified": true})
}

func (h *AgreementHandler) UpdateStatus(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userIsParty(c, id, userID) {
		return
	}

	var req models.UpdateAgreementStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	cur, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if (req.Status == "rejected" || req.Status == "awaiting_signatures") && cur.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the owner can do this"})
		return
	}

	agreement, err := h.repo.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		if errors.Is(err, repository.ErrAgreementBadState) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	notifyOtherParty(agreement, userID, "Agreement update",
		fmt.Sprintf("The agreement for %s is now: %s", agreement.PropertyTitle, strings.ReplaceAll(agreement.Status, "_", " ")))

	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) userIsParty(c *gin.Context, agreementID, userID string) bool {
	agreement, err := h.repo.GetByID(c.Request.Context(), agreementID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return false
	}
	if agreement.OwnerID != userID && agreement.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you're not a party on this agreement"})
		return false
	}
	return true
}

// notifyOtherParty sends the notification to whichever side (owner / tenant)
// did NOT perform the action.
func notifyOtherParty(a *models.Agreement, actorID, title, body string) {
	target := a.OwnerID
	if actorID == a.OwnerID {
		target = a.TenantID
	}
	notify.SendRoute(target, "agreement", title, body, "/agreement/"+a.ID+"/status")
}
