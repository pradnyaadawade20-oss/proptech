package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterPaymentRoutes(router *gin.Engine, h *handlers.PaymentHandler) {
	// Public: called by Cashfree. Protected by the HMAC signature check, not by a login.
	router.POST("/api/webhooks/cashfree", h.Webhook)

	api := router.Group("/api", middleware.AuthRequired())

	api.GET("/payments/config", h.Config)

	// Owner bank onboarding
	api.GET("/owner/bank", h.GetBank)
	api.PUT("/owner/bank", h.SaveBank)
	api.POST("/owner/bank/refresh", h.RefreshBank)

	// Start an online payment (tenant)
	api.POST("/rent/:paymentId/online-order", h.RentOrder)
	api.POST("/leases/:id/deposit/online-order", h.DepositOrder)

	// Status, history, settlements, receipts
	api.GET("/payments/orders/:orderId", h.OrderStatus)
	api.GET("/leases/:id/payments", h.LeasePayments)
	api.GET("/payments/settlements", h.Settlements)
	api.POST("/payments/orders/:orderId/settlement", h.RefreshSettlement)
	api.GET("/leases/:id/deposit/receipt", h.DepositReceipt)
}