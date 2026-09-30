package handlers

import (
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type DeviceTokenHandler struct {
	repo *repository.DeviceTokenRepository
}

func NewDeviceTokenHandler(repo *repository.DeviceTokenRepository) *DeviceTokenHandler {
	return &DeviceTokenHandler{repo: repo}
}

// RegisterToken saves (or refreshes) a device's FCM token against a user.
// Called on login and whenever FCM rotates the token (onTokenRefresh).
func (h *DeviceTokenHandler) RegisterToken(c *gin.Context) {
	var req models.RegisterDeviceTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.repo.Upsert(c.Request.Context(), req); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Device token registered"})
}

// UnregisterToken removes a token, e.g. on logout, so this device stops
// getting pushes for a user who's no longer signed in on it.
func (h *DeviceTokenHandler) UnregisterToken(c *gin.Context) {
	var req models.UnregisterDeviceTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.repo.Delete(c.Request.Context(), req.Token); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Device token removed"})
}