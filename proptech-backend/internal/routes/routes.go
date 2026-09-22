package routes

import (
	"proptech-backend/internal/handlers"

	"github.com/gin-gonic/gin"
)

func RegisterPropertyRoutes(router *gin.Engine, h *handlers.PropertyHandler) {
	properties := router.Group("/api/properties")
	{
		properties.GET("", h.GetAllProperties)
		properties.GET("/my", h.GetMyProperties)
		properties.GET("/dashboard-stats", h.GetDashboardStats)
		properties.GET("/:id", h.GetPropertyByID)
		properties.POST("", h.CreateProperty)
		properties.PUT("/:id", h.UpdateProperty)
		properties.PATCH("/:id/status", h.UpdateListingStatus)
		properties.DELETE("/:id", h.DeleteProperty)
	}
}

func RegisterAuthRoutes(router *gin.Engine, h *handlers.AuthHandler) {
	auth := router.Group("/api/auth")
	{
		auth.POST("/send-otp", h.SendOTP)
		auth.POST("/verify-otp", h.VerifyOTP)
		auth.PATCH("/users/:id/role", h.SwitchRole)
	}
}

func RegisterFavoriteRoutes(router *gin.Engine, h *handlers.FavoriteHandler) {
	favorites := router.Group("/api/favorites")
	{
		favorites.GET("", h.GetFavorites)
		favorites.POST("", h.AddFavorite)
		favorites.DELETE("", h.RemoveFavorite)
	}
}

func RegisterVisitRoutes(router *gin.Engine, h *handlers.VisitHandler) {
	visits := router.Group("/api/visits")
	{
		visits.GET("", h.GetVisits)
		visits.POST("", h.CreateVisit)
		visits.PATCH("/:id/status", h.UpdateVisitStatus)
		visits.DELETE("/:id", h.DeleteVisit)
	}
}

func RegisterMessageRoutes(router *gin.Engine, h *handlers.MessageHandler) {
	messages := router.Group("/api/messages")
	{
		messages.GET("/conversations", h.GetConversations)
		messages.GET("/thread", h.GetThread)
		messages.POST("", h.SendMessage)
		messages.POST("/read", h.MarkRead)
	}
}

func RegisterProfileRoutes(router *gin.Engine, h *handlers.ProfileHandler) {
	profile := router.Group("/api/profile")
	{
		profile.GET("/:id", h.GetProfile)
		profile.PUT("/:id", h.UpdateProfile)
	}
}

func RegisterAgreementRoutes(router *gin.Engine, h *handlers.AgreementHandler) {
	agreements := router.Group("/api/agreements")
	{
		agreements.GET("", h.GetAgreements)
		agreements.GET("/:id", h.GetAgreementByID)
		agreements.POST("", h.CreateAgreement)
		agreements.PUT("/:id/draft", h.UpdateDraft)
		agreements.POST("/:id/sign", h.SignAgreement)
		agreements.PATCH("/:id/status", h.UpdateStatus)
	}
}

func RegisterBrokerRoutes(router *gin.Engine, h *handlers.BrokerHandler) {
	broker := router.Group("/api/broker")
	{
		broker.GET("/:id/subscription", h.GetSubscription)
	}
}