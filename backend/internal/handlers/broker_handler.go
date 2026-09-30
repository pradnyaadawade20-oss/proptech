package handlers

import (
	"net/http"

	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type BrokerHandler struct {
	subscriptionRepo *repository.BrokerSubscriptionRepository
}

func NewBrokerHandler(subscriptionRepo *repository.BrokerSubscriptionRepository) *BrokerHandler {
	return &BrokerHandler{subscriptionRepo: subscriptionRepo}
}

// GetSubscription backs the "Free Plan / 3 of 3 listings used / Upgrade"
// card on BrokerDashboardScreen.
func (h *BrokerHandler) GetSubscription(c *gin.Context) {
	brokerID := c.Param("id")

	subscription, err := h.subscriptionRepo.GetByBrokerID(c.Request.Context(), brokerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"subscription": subscription})
}