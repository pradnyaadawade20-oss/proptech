package handlers

import (
	"context"
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/push"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type NotificationHandler struct {
	repo        *repository.NotificationRepository
	deviceRepo  *repository.DeviceTokenRepository
	pushSender  *push.Sender // nil if Firebase isn't configured — pushes are skipped, not fatal
}

func NewNotificationHandler(repo *repository.NotificationRepository, deviceRepo *repository.DeviceTokenRepository, pushSender *push.Sender) *NotificationHandler {
	return &NotificationHandler{repo: repo, deviceRepo: deviceRepo, pushSender: pushSender}
}

// GetNotifications returns notifications for a user.
// GET /api/notifications?user_id=...
func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}

	notifications, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notifications": notifications})
}

func (h *NotificationHandler) CreateNotification(c *gin.Context) {
	var req models.CreateNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notification, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Fire the push in the background so the API response doesn't wait on
	// Firebase. Best-effort: a failed push never fails notification creation.
	go h.sendPush(notification)

	c.JSON(http.StatusCreated, gin.H{"notification": notification})
}

// sendPush looks up the user's device tokens and pushes the notification to
// all of them, then cleans up any tokens FCM reports as dead.
func (h *NotificationHandler) sendPush(n *models.Notification) {
	if h.pushSender == nil {
		return
	}

	ctx := context.Background()
	tokens, err := h.deviceRepo.GetTokensForUser(ctx, n.UserID)
	if err != nil || len(tokens) == 0 {
		return
	}

	data := map[string]string{
		"type":            n.Type,
		"notification_id": n.ID,
	}
	invalid := h.pushSender.SendToTokens(ctx, tokens, n.Title, n.Body, data)
	if len(invalid) > 0 {
		_ = h.deviceRepo.DeleteInvalid(ctx, invalid)
	}
}

func (h *NotificationHandler) MarkRead(c *gin.Context) {
	id := c.Param("id")

	notification, err := h.repo.MarkRead(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notification": notification})
}

// MarkAllRead marks every notification for a user as read.
// POST /api/notifications/read-all  { "user_id": "..." }
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	var req struct {
		UserID string `json:"user_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.repo.MarkAllRead(c.Request.Context(), req.UserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All notifications marked as read"})
}

func (h *NotificationHandler) DeleteNotification(c *gin.Context) {
	id := c.Param("id")

	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification deleted"})
}