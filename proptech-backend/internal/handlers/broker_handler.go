package handlers

import (
	"net/http"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type BrokerHandler struct {
	subscriptionRepo *repository.BrokerSubscriptionRepository
}

func NewBrokerHandler(subscriptionRepo *repository.BrokerSubscriptionRepository) *BrokerHandler {
	return &BrokerHandler{subscriptionRepo: subscriptionRepo}
}

func (h *BrokerHandler) GetSubscription(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	brokerID := c.Param("id")
	if brokerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only view your own subscription"})
		return
	}

	subscription, err := h.subscriptionRepo.GetByBrokerID(c.Request.Context(), brokerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"subscription": subscription})
}
