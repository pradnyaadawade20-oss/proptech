package handlers

import (
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

const maxMessageLen = 2000

type MessageHandler struct {
	repo *repository.MessageRepository
}

func NewMessageHandler(repo *repository.MessageRepository) *MessageHandler {
	return &MessageHandler{repo: repo}
}

func (h *MessageHandler) SendMessage(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.SenderID = userID // body ka sender_id ignore
	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message can't be empty"})
		return
	}
	if len(req.Text) > maxMessageLen {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is too long"})
		return
	}
	if req.ReceiverID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "you can't message yourself"})
		return
	}

	message, err := h.repo.Send(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	notify.NewMessage(req.SenderID, req.ReceiverID, req.Text)

	c.JSON(http.StatusCreated, gin.H{"message": message})
}

func (h *MessageHandler) GetConversations(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	conversations, err := h.repo.GetConversations(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"conversations": conversations})
}

func (h *MessageHandler) GetThread(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	otherUserID := c.Query("other_user_id")
	if otherUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "other_user_id is required"})
		return
	}

	messages, err := h.repo.GetMessagesWith(c.Request.Context(), userID, otherUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"messages": messages})
}

func (h *MessageHandler) MarkRead(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	otherUserID := c.Query("other_user_id")
	if otherUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "other_user_id is required"})
		return
	}

	if err := h.repo.MarkRead(c.Request.Context(), userID, otherUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Marked as read"})
}
