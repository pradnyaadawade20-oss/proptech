package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

// RegisterPaymentRoutes wires Cashfree online payments.
func RegisterPaymentRoutes(router *gin.Engine, h *handlers.PaymentHandler) {
	// Public: Cashfree calls the webhook; the browser opens the two pages.
	router.POST("/api/payments/webhook", h.Webhook)
	router.GET("/pay/checkout", h.CheckoutPage)
	router.GET("/pay/return", h.ReturnPage)

	api := router.Group("/api", middleware.AuthRequired())
	api.POST("/rent/:paymentId/checkout", h.RentCheckout)
	api.POST("/leases/:id/deposit/checkout", h.DepositCheckout)
	api.GET("/payments/orders/:orderId", h.OrderStatus)

	// Agent (broker) commission: agent proposes -> tenant accepts -> tenant pays after both sign
	api.GET("/agreements/:id/commission", h.GetCommission)
	api.PUT("/agreements/:id/commission", h.SetCommission)
	api.POST("/agreements/:id/commission/accept", h.AcceptCommission)
	api.POST("/agreements/:id/commission/decline", h.DeclineCommission)
	api.POST("/agreements/:id/commission/checkout", h.CommissionCheckout)
	api.GET("/agent/agreements", h.AgentAgreements)
}