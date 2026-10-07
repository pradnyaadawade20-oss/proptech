package handlers

import (
	"crypto/subtle"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"proptech-backend/internal/mail"
	"proptech-backend/internal/ratelimit"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// Forgot password: email -> 6-digit code by email -> code + new password.
// Reuses the OTP constants / helpers from auth_handler.go.
type PasswordResetHandler struct {
	userRepo  *repository.UserRepository
	resetRepo *repository.PasswordResetRepository
	mailer    *mail.Mailer
}

func NewPasswordResetHandler(userRepo *repository.UserRepository, resetRepo *repository.PasswordResetRepository, mailer *mail.Mailer) *PasswordResetHandler {
	return &PasswordResetHandler{userRepo: userRepo, resetRepo: resetRepo, mailer: mailer}
}

type forgotPasswordRequest struct {
	Email string `json:"email" binding:"required,email"`
}

type resetPasswordRequest struct {
	Email       string `json:"email" binding:"required,email"`
	OTP         string `json:"otp" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// Separate hash namespace so a login OTP can never be used as a reset code.
func resetHash(email, otp string) string { return hashOTP("reset:"+email, otp) }

// ForgotPassword: POST /api/auth/forgot-password  {email}
//
// Always answers the same way, whether or not the email has an account, so it
// can't be used to find out who is registered.
func (h *PasswordResetHandler) ForgotPassword(c *gin.Context) {
	var req forgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Please enter a valid email"})
		return
	}

	ctx := c.Request.Context()
	email := strings.ToLower(strings.TrimSpace(req.Email))
	generic := gin.H{
		"message":    "If an account exists for this email, a reset code has been sent.",
		"expires_in": int(otpTTL.Seconds()),
	}

	if blocked, retry := ratelimit.Hit(ctx, "pwd-reset-send:"+email, 5, 15*time.Minute, 30*time.Minute); blocked {
		ratelimit.Reject(c, retry)
		return
	}

	user, _, err := h.userRepo.GetAuthByEmail(ctx, email)
	if err != nil {
		log.Printf("forgot-password: lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if user == nil {
		c.JSON(http.StatusOK, generic)
		return
	}

	// One email per minute per address (silently — same response).
	if rec, err := h.resetRepo.Get(ctx, email); err == nil && rec != nil {
		if time.Since(rec.LastSentAt) < otpResendCooldown {
			c.JSON(http.StatusOK, generic)
			return
		}
	}

	otp, err := generateOTP()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if err := h.resetRepo.Upsert(ctx, email, resetHash(email, otp), time.Now().Add(otpTTL)); err != nil {
		log.Printf("forgot-password: store failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if err := h.mailer.SendPasswordReset(ctx, email, otp); err != nil {
		log.Printf("forgot-password: email to %s failed: %v", email, err)
		_ = h.resetRepo.Delete(ctx, email)
	}

	c.JSON(http.StatusOK, generic)
}

// ResetPassword: POST /api/auth/reset-password  {email, otp, new_password}
func (h *PasswordResetHandler) ResetPassword(c *gin.Context) {
	var req resetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Enter the code and a new password"})
		return
	}
	if len(req.NewPassword) < minPasswordLen {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Password must be at least %d characters", minPasswordLen)})
		return
	}
	if len([]byte(req.NewPassword)) > maxPasswordBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Password must be at most %d characters", maxPasswordBytes)})
		return
	}

	ctx := c.Request.Context()
	email := strings.ToLower(strings.TrimSpace(req.Email))
	otp := strings.TrimSpace(req.OTP)

	if blocked, retry := ratelimit.Hit(ctx, "pwd-reset-verify:"+email, 10, 15*time.Minute, 30*time.Minute); blocked {
		ratelimit.Reject(c, retry)
		return
	}

	rec, err := h.resetRepo.Get(ctx, email)
	if err != nil {
		log.Printf("reset-password: lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if rec == nil || time.Now().After(rec.ExpiresAt) {
		if rec != nil {
			_ = h.resetRepo.Delete(ctx, email)
		}
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired code"})
		return
	}

	attempts, err := h.resetRepo.IncrementAttempts(ctx, email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if attempts > otpMaxAttempts {
		_ = h.resetRepo.Delete(ctx, email)
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "Too many wrong attempts. Please request a new code."})
		return
	}
	if subtle.ConstantTimeCompare([]byte(rec.OTPHash), []byte(resetHash(email, otp))) != 1 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired code"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if err := h.userRepo.SetPasswordByEmail(ctx, email, string(hash)); err != nil {
		log.Printf("reset-password: update failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not update your password. Please try again."})
		return
	}
	_ = h.resetRepo.Delete(ctx, email)

	c.JSON(http.StatusOK, gin.H{"message": "Password updated. Please log in with your new password."})
}