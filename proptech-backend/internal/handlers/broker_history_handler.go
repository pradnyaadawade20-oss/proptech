package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// GetHistory: GET /api/broker/:id/subscription/history
func (h *BrokerHandler) GetHistory(c *gin.Context) {
	brokerID, ok := h.own(c)
	if !ok {
		return
	}
	list, err := h.subscriptionRepo.History(c.Request.Context(), brokerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"history": list})
}