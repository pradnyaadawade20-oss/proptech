package routes

import (
	"time"

	"proptech-backend/internal/ratelimit"
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterLeadRoutes(router *gin.Engine, h *handlers.LeadHandler) {
	leads := router.Group("/api/leads")
	leads.Use(middleware.AuthRequired())
	{
		leads.POST("", h.Create)
		leads.GET("", h.List)
		leads.PATCH("/:id/status", h.UpdateStatus)
	}
}
func RegisterKYCRoutes(router *gin.Engine, h *handlers.KYCHandler) {
	kycGroup := router.Group("/api/kyc")
	kycGroup.Use(middleware.AuthRequired())
	{
		kycGroup.GET("/status", h.GetStatus)
		kycGroup.POST("/aadhaar/send-otp", ratelimit.User("kyc-send-otp", 5, time.Hour, time.Hour), h.SendOTP)
		kycGroup.POST("/aadhaar/verify-otp", ratelimit.User("kyc-verify-otp", 10, time.Hour, time.Hour), h.VerifyOTP)
	}
}

func RegisterContactRoutes(router *gin.Engine, h *handlers.ContactHandler) {
	contact := router.Group("/api/contact", middleware.AuthRequired())
	contact.POST("/request-call", h.RequestCall)
}