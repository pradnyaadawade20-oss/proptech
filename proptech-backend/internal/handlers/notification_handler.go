package handlers

import (
	"context"
	"errors"
	"net/http"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/push"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type NotificationHandler struct {
	repo       *repository.NotificationRepository
	deviceRepo *repository.DeviceTokenRepository
	pushSender *push.Sender
}

func NewNotificationHandler(repo *repository.NotificationRepository, deviceRepo *repository.DeviceTokenRepository, pushSender *push.Sender) *NotificationHandler {
	return &NotificationHandler{repo: repo, deviceRepo: deviceRepo, pushSender: pushSender}
}

func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	notifications, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notifications": notifications})
}

// sendPush server-internal use ke liye (notify package se call hota hai).
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
		"route":           n.Route,
	}
	invalid := h.pushSender.SendToTokens(ctx, tokens, n.Title, n.Body, data)
	if len(invalid) > 0 {
		_ = h.deviceRepo.DeleteInvalid(ctx, invalid)
	}
}

func (h *NotificationHandler) MarkRead(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	notification, err := h.repo.MarkRead(c.Request.Context(), c.Param("id"), userID)
	if err != nil {
		if errors.Is(err, repository.ErrNotificationNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "notification not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notification": notification})
}

func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	if err := h.repo.MarkAllRead(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All notifications marked as read"})
}

func (h *NotificationHandler) DeleteNotification(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	if err := h.repo.Delete(c.Request.Context(), c.Param("id"), userID); err != nil {
		if errors.Is(err, repository.ErrNotificationNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "notification not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification deleted"})
}
