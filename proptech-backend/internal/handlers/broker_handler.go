package handlers

import (
	"net/http"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type BrokerHandler struct {
	subscriptionRepo *repository.BrokerSubscriptionRepository
}

func NewBrokerHandler(subscriptionRepo *repository.BrokerSubscriptionRepository) *BrokerHandler {
	return &BrokerHandler{subscriptionRepo: subscriptionRepo}
}

// own returns the logged-in user id if it matches :id, else writes the error.
func (h *BrokerHandler) own(c *gin.Context) (string, bool) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return "", false
	}
	if c.Param("id") != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only access your own subscription"})
		return "", false
	}
	return userID, true
}

// GetSubscription: GET /api/broker/:id/subscription
// Returns the broker's current plan plus the purchasable plans.
func (h *BrokerHandler) GetSubscription(c *gin.Context) {
	brokerID, ok := h.own(c)
	if !ok {
		return
	}
	sub, err := h.subscriptionRepo.GetByBrokerID(c.Request.Context(), brokerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"subscription": sub, "plans": models.SubscriptionPlans})
}

type subscribeRequest struct {
	Plan       string `json:"plan" binding:"required,oneof=monthly yearly"`
	PaymentRef string `json:"payment_ref"`
}

// Subscribe: POST /api/broker/:id/subscription/subscribe
//
// Disabled on purpose: activating a plan without payment would let anyone get it free.
// Plans are now bought with POST /api/broker/:id/subscription/checkout (Cashfree) and are
// activated by the server only after the payment is confirmed.
func (h *BrokerHandler) Subscribe(c *gin.Context) {
	if _, ok := h.own(c); !ok {
		return
	}
	c.JSON(http.StatusPaymentRequired, gin.H{"error": "please pay online to activate a plan"})
}