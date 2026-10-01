package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"
	"time"

	"proptech-backend/internal/mail"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

const (
	otpTTL            = 10 * time.Minute
	otpResendCooldown = 60 * time.Second
	otpMaxAttempts    = 5
	minPasswordLen    = 8
	maxPasswordBytes  = 72 // bcrypt limit
)

type AuthHandler struct {
	userRepo   *repository.UserRepository
	otpRepo    *repository.EmailOTPRepository
	mailer     *mail.Mailer
	devSkipOTP bool // testing only (DEV_SKIP_OTP=true)
}

func NewAuthHandler(userRepo *repository.UserRepository, otpRepo *repository.EmailOTPRepository, mailer *mail.Mailer, devSkipOTP bool) *AuthHandler {
	return &AuthHandler{userRepo: userRepo, otpRepo: otpRepo, mailer: mailer, devSkipOTP: devSkipOTP}
}

// SkipOTPRequest: the caller must already have passed send-otp (which checks
// the password / validates the signup), so a pending record exists.
type SkipOTPRequest struct {
	Email string   `json:"email" binding:"required,email"`
	Role  string   `json:"role"`
	Roles []string `json:"roles"`
}

func generateOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// normalizePhone turns "98765 43210", "09876543210", "+91 98765-43210" etc.
// into "+919876543210". Returns "" if it isn't a valid Indian mobile number
// (10 digits, starting with 6-9).
func normalizePhone(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	d := digits.String()
	switch {
	case len(d) == 12 && strings.HasPrefix(d, "91"):
		d = d[2:]
	case len(d) == 11 && strings.HasPrefix(d, "0"):
		d = d[1:]
	}
	if len(d) != 10 || d[0] < '6' || d[0] > '9' {
		return ""
	}
	return "+91" + d
}

func hashOTP(email, otp string) string {
	sum := sha256.Sum256([]byte(email + ":" + otp))
	return hex.EncodeToString(sum[:])
}

// SendOTP: POST /api/auth/send-otp  {name, email, password}
//
//   - Existing account: password must match, then a login OTP is emailed.
//   - New account: name + password are validated and parked (password hashed)
//     next to the OTP; the account is only created once the OTP is verified.
func (h *AuthHandler) SendOTP(c *gin.Context) {
	var req models.SendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Please enter a valid email and password"})
		return
	}

	ctx := c.Request.Context()
	email := strings.ToLower(strings.TrimSpace(req.Email))
	name := strings.TrimSpace(req.Name)

	user, existingHash, err := h.userRepo.GetAuthByEmail(ctx, email)
	if err != nil {
		log.Printf("send-otp: lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}

	// Phone is required for a new signup. For an existing account it is
	// optional, but if given it must be valid (used to back-fill old accounts).
	phone := normalizePhone(req.Phone)
	if strings.TrimSpace(req.Phone) != "" && phone == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Enter a valid 10-digit mobile number"})
		return
	}

	var pendingName, pendingHash string
	if user != nil {
		if existingHash == "" || bcrypt.CompareHashAndPassword([]byte(existingHash), []byte(req.Password)) != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
			return
		}
	} else {
		if phone == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Please enter your mobile number"})
			return
		}
		taken, err := h.userRepo.PhoneTaken(ctx, phone)
		if err != nil {
			log.Printf("send-otp: phone lookup failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
			return
		}
		if taken {
			c.JSON(http.StatusConflict, gin.H{"error": "This mobile number is already registered with another account"})
			return
		}
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Please enter your name"})
			return
		}
		if len(req.Password) < minPasswordLen {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Password must be at least %d characters", minPasswordLen)})
			return
		}
		if len([]byte(req.Password)) > maxPasswordBytes {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Password must be at most %d characters", maxPasswordBytes)})
			return
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
			return
		}
		pendingName, pendingHash = name, string(hash)
	}

	// Resend throttle: one email per address per minute (relaxed in skip/testing mode).
	if rec, err := h.otpRepo.Get(ctx, email); err == nil && rec != nil && !h.devSkipOTP {
		if wait := otpResendCooldown - time.Since(rec.LastSentAt); wait > 0 {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": fmt.Sprintf("Please wait %d seconds before requesting another OTP", int(wait.Seconds())+1),
			})
			return
		}
	}

	otp, err := generateOTP()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}

	if err := h.otpRepo.Upsert(ctx, email, hashOTP(email, otp), pendingName, phone, pendingHash, time.Now().Add(otpTTL)); err != nil {
		log.Printf("send-otp: store failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}

	emailSent := true
	if err := h.mailer.SendOTP(ctx, email, otp); err != nil {
		log.Printf("send-otp: email to %s failed: %v", email, err)
		if !h.devSkipOTP {
			_ = h.otpRepo.Delete(ctx, email) // don't leave the cooldown stuck after a failed send
			c.JSON(http.StatusBadGateway, gin.H{"error": "Could not send the OTP email. Please try again in a moment."})
			return
		}
		// Testing mode: keep the pending signup so the app can offer "Skip".
		emailSent = false
	}

	// The OTP is never returned in the response — it only goes to the inbox.
	message := "OTP sent to your email"
	if !emailSent {
		message = "Could not send the email right now. You can skip verification for now."
	}
	c.JSON(http.StatusOK, gin.H{
		"message":        message,
		"expires_in":     int(otpTTL.Seconds()),
		"email_sent":     emailSent,
		"skip_available": h.devSkipOTP,
	})
}

// VerifyOTP: POST /api/auth/verify-otp  {email, otp, role?, roles?}
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req models.VerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Please enter the OTP"})
		return
	}

	ctx := c.Request.Context()
	email := strings.ToLower(strings.TrimSpace(req.Email))
	otp := strings.TrimSpace(req.OTP)

	rec, err := h.otpRepo.Get(ctx, email)
	if err != nil {
		log.Printf("verify-otp: lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if rec == nil || time.Now().After(rec.ExpiresAt) {
		if rec != nil {
			_ = h.otpRepo.Delete(ctx, email)
		}
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired OTP"})
		return
	}

	// Count the attempt first, then compare, so parallel guesses can't beat the limit.
	attempts, err := h.otpRepo.IncrementAttempts(ctx, email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if attempts > otpMaxAttempts {
		_ = h.otpRepo.Delete(ctx, email)
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "Too many wrong attempts. Please request a new OTP."})
		return
	}
	if subtle.ConstantTimeCompare([]byte(rec.OTPHash), []byte(hashOTP(email, otp))) != 1 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired OTP"})
		return
	}

	h.completeLogin(c, email, rec, req.Role, req.Roles, true)
}

// SkipOTP: POST /api/auth/skip-otp  {email, role?, roles?}
//
// TESTING ONLY. Enabled by DEV_SKIP_OTP=true (returns 404 otherwise). Needs a
// pending, unexpired send-otp record, i.e. the password was already checked
// (existing account) or the signup was validated (new account). Email
// ownership is NOT proven, so never leave this on for real users.
func (h *AuthHandler) SkipOTP(c *gin.Context) {
	if !h.devSkipOTP {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	var req SkipOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	ctx := c.Request.Context()
	email := strings.ToLower(strings.TrimSpace(req.Email))

	rec, err := h.otpRepo.Get(ctx, email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}
	if rec == nil || time.Now().After(rec.ExpiresAt) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Session expired. Please go back and tap Send OTP again."})
		return
	}

	log.Printf("WARNING: OTP verification skipped for %s (DEV_SKIP_OTP is on)", email)
	h.completeLogin(c, email, rec, req.Role, req.Roles, false)
}

// completeLogin creates the account if needed (new signup), issues the JWT and
// consumes the pending record. Shared by VerifyOTP (emailVerified=true) and
// SkipOTP (emailVerified=false).
func (h *AuthHandler) completeLogin(c *gin.Context, email string, rec *repository.EmailOTP, role string, roles []string, emailVerified bool) {
	ctx := c.Request.Context()

	user, _, err := h.userRepo.GetAuthByEmail(ctx, email)
	if err != nil {
		log.Printf("verify-otp: user lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}

	if user == nil {
		if rec.Name == "" || rec.PasswordHash == "" {
			_ = h.otpRepo.Delete(ctx, email)
			c.JSON(http.StatusBadRequest, gin.H{"error": "Please go back and sign up again."})
			return
		}
		user, err = h.userRepo.CreateWithEmail(ctx, rec.Name, email, rec.Phone, rec.PasswordHash, role, roles, emailVerified)
		if err != nil {
			log.Printf("verify-otp: create user failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not create your account. Please try again."})
			return
		}
	} else {
		if emailVerified {
			_ = h.userRepo.MarkEmailVerified(ctx, user.ID)
		}
		// Older account created before phone was collected: fill it in now.
		if user.Phone == "" && rec.Phone != "" {
			if saved, err := h.userRepo.SetPhoneIfEmpty(ctx, user.ID, rec.Phone); err == nil && saved {
				user.Phone = rec.Phone
			}
		}
	}

	token, err := middleware.GenerateToken(user.ID, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	_ = h.otpRepo.Delete(ctx, email) // single use

	// Login alert (delayed so this device can register its push token first).
	notify.SendLater(6*time.Second, user.ID, "account", "New login", "You just signed in to PropTech.")

	c.JSON(http.StatusOK, gin.H{
		"user":  user,
		"token": token,
	})
}

// SwitchRole matches role_switcher_sheet.dart — the person picks a role
// (existing or new) from the bottom sheet and this becomes their active
// "mode" without a fresh login.
func (h *AuthHandler) SwitchRole(c *gin.Context) {
	authUserID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID := c.Param("id")
	if userID != authUserID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only change your own role"})
		return
	}
	var req models.SwitchRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user, err := h.userRepo.SwitchRole(c.Request.Context(), userID, req.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"user": user})
}
