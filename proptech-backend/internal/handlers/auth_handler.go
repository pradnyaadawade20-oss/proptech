package handlers

import (
	"net/http"
	"sync"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	userRepo *repository.UserRepository
	otpStore map[string]string
	mu       sync.Mutex
}

func NewAuthHandler(userRepo *repository.UserRepository) *AuthHandler {
	return &AuthHandler{
		userRepo: userRepo,
		otpStore: make(map[string]string),
	}
}

// SendOTP: for now, always generates a dummy OTP "1234" (replace with real SMS gateway later)
func (h *AuthHandler) SendOTP(c *gin.Context) {
	var req models.SendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	dummyOTP := "1234"

	h.mu.Lock()
	h.otpStore[req.Phone] = dummyOTP
	h.mu.Unlock()

	c.JSON(http.StatusOK, gin.H{
		"message": "OTP sent successfully",
		"otp":     dummyOTP, // NOTE: only exposed here for testing; remove once real SMS is wired up
	})
}

func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req models.VerifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	h.mu.Lock()
	storedOTP, exists := h.otpStore[req.Phone]
	h.mu.Unlock()

	if !exists || storedOTP != req.OTP {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired OTP"})
		return
	}

	// Check if user already exists
	user, err := h.userRepo.GetByPhone(c.Request.Context(), req.Phone)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if user == nil {
		// New user, create account
		user, err = h.userRepo.Create(c.Request.Context(), req.Name, req.Phone, req.Role, req.Roles)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	token, err := middleware.GenerateToken(user.ID, user.Phone, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	// Clear used OTP
	h.mu.Lock()
	delete(h.otpStore, req.Phone)
	h.mu.Unlock()

	c.JSON(http.StatusOK, gin.H{
		"user":  user,
		"token": token,
	})
}

// SwitchRole matches role_switcher_sheet.dart — the person picks a role
// (existing or new) from the bottom sheet and this becomes their active
// "mode" without a fresh login.
func (h *AuthHandler) SwitchRole(c *gin.Context) {
	userID := c.Param("id")

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