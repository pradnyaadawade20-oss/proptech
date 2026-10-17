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
	api.POST("/broker/:id/subscription/checkout", h.SubscriptionCheckout) // broker plan via Cashfree

	// Commission agreement (broker <-> tenant): broker sends + signs, tenant signs, tenant pays after the lease exists
	api.POST("/properties/:id/commission-agreement", h.CreateCommissionAgreement)
	api.GET("/commission-agreements", h.ListCommissionAgreements)
	api.GET("/commission-agreements/:id", h.GetCommissionAgreement)
	api.POST("/commission-agreements/:id/sign", h.SignCommissionAgreement)
	api.POST("/commission-agreements/:id/decline", h.DeclineCommissionAgreement)
	api.POST("/commission-agreements/:id/cancel", h.CancelCommissionAgreement)
	api.POST("/commission-agreements/:id/checkout", h.CommissionCheckout)
	api.GET("/commission-agreements/:id/pdf", h.CommissionAgreementPDF)
	api.GET("/leases/:id/commission-agreement", h.LeaseCommissionAgreement)
}