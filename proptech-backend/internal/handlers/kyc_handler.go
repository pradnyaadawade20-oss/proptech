package handlers

import (
	"errors"
	"log"
	"net/http"
	"time"

	"proptech-backend/internal/kyc"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type KYCHandler struct {
	repo     *repository.KYCRepository
	provider kyc.Provider
	hasher   kyc.Hasher
}

func NewKYCHandler(repo *repository.KYCRepository, provider kyc.Provider, hasher kyc.Hasher) *KYCHandler {
	return &KYCHandler{repo: repo, provider: provider, hasher: hasher}
}

// GetStatus: GET /api/kyc/status -> {"kyc": {status, masked_aadhaar?, verified_at?}}
func (h *KYCHandler) GetStatus(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	k, err := h.repo.Get(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load KYC status"})
		return
	}
	if k == nil {
		k = &models.KYC{Status: models.KYCNotStarted}
	}
	c.JSON(http.StatusOK, gin.H{"kyc": k})
}

// SendOTP: POST /api/kyc/aadhaar/send-otp {aadhaar, consent:true}
func (h *KYCHandler) SendOTP(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.KYCSendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "aadhaar is required"})
		return
	}
	if !req.Consent {
		c.JSON(http.StatusBadRequest, gin.H{"error": "you must consent to Aadhaar verification", "code": "kyc_consent_required"})
		return
	}
	aadhaar, ok := kyc.NormalizeAadhaar(req.Aadhaar, h.provider.Name() != "mock")
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter a valid 12-digit Aadhaar number", "code": "kyc_invalid_aadhaar"})
		return
	}

	ctx := c.Request.Context()
	cur, err := h.repo.Get(ctx, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load KYC status"})
		return
	}
	if cur != nil && cur.Status == models.KYCVerified {
		c.JSON(http.StatusConflict, gin.H{"error": repository.ErrKYCAlreadyVerified.Error(), "code": "kyc_already_verified"})
		return
	}
	// Check the cooldown BEFORE calling the provider (every OTP can cost money / SMS).
	if cur != nil && cur.OTPSentAt != nil {
		wait := time.Duration(repository.KYCResendCooldownSeconds)*time.Second - time.Since(*cur.OTPSentAt)
		if wait > 0 {
			secs := int(wait.Seconds()) + 1
			c.JSON(http.StatusTooManyRequests, gin.H{"error": repository.ErrKYCCooldown.Error(), "code": "kyc_cooldown", "retry_after_seconds": secs})
			return
		}
	}

	ref, err := h.provider.SendOTP(ctx, aadhaar)
	if err != nil {
		log.Printf("kyc provider %s send otp failed for user %s: %v", h.provider.Name(), userID, err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not send the OTP, try again"})
		return
	}
	last4 := aadhaar[len(aadhaar)-4:]
	if err := h.repo.StartOTP(ctx, userID, h.hasher.Hash(aadhaar), last4, h.provider.Name(), ref); err != nil {
		switch {
		case errors.Is(err, repository.ErrKYCAlreadyVerified):
			c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "kyc_already_verified"})
		case errors.Is(err, repository.ErrKYCCooldown):
			c.JSON(http.StatusTooManyRequests, gin.H{"error": err.Error(), "code": "kyc_cooldown", "retry_after_seconds": repository.KYCResendCooldownSeconds})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not start KYC"})
		}
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"message":              "OTP sent to the mobile number linked with your Aadhaar",
		"masked_aadhaar":       "XXXX XXXX " + last4,
		"resend_after_seconds": repository.KYCResendCooldownSeconds,
	})
}

// VerifyOTP: POST /api/kyc/aadhaar/verify-otp {otp}
func (h *KYCHandler) VerifyOTP(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.KYCVerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "enter the 6-digit OTP"})
		return
	}

	ctx := c.Request.Context()
	ref, attempts, err := h.repo.RegisterAttempt(ctx, userID)
	if err != nil {
		if errors.Is(err, repository.ErrKYCNoActiveOTP) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "kyc_no_active_otp"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not verify OTP"})
		return
	}
	if attempts > repository.KYCMaxAttempts {
		_ = h.repo.MarkRejected(ctx, userID, "too many wrong OTP attempts")
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "too many wrong attempts, request a new OTP", "code": "kyc_too_many_attempts"})
		return
	}

	if err := h.provider.VerifyOTP(ctx, ref, req.OTP); err != nil {
		if errors.Is(err, kyc.ErrInvalidOTP) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error":         "invalid OTP",
				"code":          "kyc_invalid_otp",
				"attempts_left": repository.KYCMaxAttempts - attempts,
			})
			return
		}
		log.Printf("kyc provider %s verify otp failed for user %s: %v", h.provider.Name(), userID, err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not verify the OTP, try again"})
		return
	}

	if err := h.repo.MarkVerified(ctx, userID); err != nil {
		if errors.Is(err, repository.ErrKYCAadhaarInUse) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "kyc_aadhaar_in_use"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not save KYC"})
		return
	}
	k, err := h.repo.Get(ctx, userID)
	if err != nil || k == nil {
		c.JSON(http.StatusOK, gin.H{"kyc": models.KYC{Status: models.KYCVerified}})
		return
	}
	c.JSON(http.StatusOK, gin.H{"kyc": k})
}