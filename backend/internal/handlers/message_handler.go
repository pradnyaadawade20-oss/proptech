package handlers

import (
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type MessageHandler struct {
	repo *repository.MessageRepository
}

func NewMessageHandler(repo *repository.MessageRepository) *MessageHandler {
	return &MessageHandler{repo: repo}
}

func (h *MessageHandler) SendMessage(c *gin.Context) {
	var req models.SendMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	message, err := h.repo.Send(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"message": message})
}

// GetConversations: GET /api/messages/conversations?user_id=...
// Returns the chat list screen data (one row per other user).
func (h *MessageHandler) GetConversations(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}

	conversations, err := h.repo.GetConversations(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"conversations": conversations})
}

// GetThread: GET /api/messages/thread?user_id=...&other_user_id=...
// Returns the full message history for the chat detail screen.
func (h *MessageHandler) GetThread(c *gin.Context) {
	userID := c.Query("user_id")
	otherUserID := c.Query("other_user_id")
	if userID == "" || otherUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id and other_user_id are required"})
		return
	}

	messages, err := h.repo.GetMessagesWith(c.Request.Context(), userID, otherUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"messages": messages})
}

// MarkRead: POST /api/messages/read?user_id=...&other_user_id=...
// Marks the thread as read when the user opens the chat detail screen.
func (h *MessageHandler) MarkRead(c *gin.Context) {
	userID := c.Query("user_id")
	otherUserID := c.Query("other_user_id")
	if userID == "" || otherUserID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id and other_user_id are required"})
		return
	}

	if err := h.repo.MarkRead(c.Request.Context(), userID, otherUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Marked as read"})
}