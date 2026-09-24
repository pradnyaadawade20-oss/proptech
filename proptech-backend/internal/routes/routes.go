package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterPropertyRoutes(router *gin.Engine, h *handlers.PropertyHandler) {
	auth := middleware.AuthRequired()

	properties := router.Group("/api/properties")
	{
		properties.GET("", h.GetAllProperties)
		properties.GET("/:id", h.GetPropertyByID)
	}

	myProperties := router.Group("/api/properties")
	myProperties.Use(auth)
	{
		myProperties.GET("/my", h.GetMyProperties)
		myProperties.GET("/dashboard-stats", h.GetDashboardStats)
		myProperties.POST("", h.CreateProperty)
		myProperties.PUT("/:id", h.UpdateProperty)
		myProperties.PATCH("/:id/status", h.UpdateListingStatus)
		myProperties.DELETE("/:id", h.DeleteProperty)
	}
}

func RegisterAuthRoutes(router *gin.Engine, h *handlers.AuthHandler) {
	auth := router.Group("/api/auth")
	{
		auth.POST("/send-otp", h.SendOTP)
		auth.POST("/verify-otp", h.VerifyOTP)
	}

	authProtected := router.Group("/api/auth")
	authProtected.Use(middleware.AuthRequired())
	{
		authProtected.PATCH("/users/:id/role", h.SwitchRole)
	}
}

func RegisterFavoriteRoutes(router *gin.Engine, h *handlers.FavoriteHandler) {
	favorites := router.Group("/api/favorites")
	favorites.Use(middleware.AuthRequired())
	{
		favorites.GET("", h.GetFavorites)
		favorites.POST("", h.AddFavorite)
		favorites.DELETE("", h.RemoveFavorite)
	}
}

func RegisterVisitRoutes(router *gin.Engine, h *handlers.VisitHandler) {
	visits := router.Group("/api/visits")
	visits.Use(middleware.AuthRequired())
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
	agreements.Use(middleware.AuthRequired())
	{
		agreements.GET("", h.GetAgreements)
		agreements.GET("/:id", h.GetAgreementByID)
		agreements.POST("", h.CreateAgreement)
		agreements.PUT("/:id/draft", h.UpdateDraft)
		agreements.POST("/:id/sign", h.SignAgreement)
		agreements.PATCH("/:id/status", h.UpdateStatus)
	}
}

func RegisterNotificationRoutes(router *gin.Engine, h *handlers.NotificationHandler) {
	notifications := router.Group("/api/notifications")
	{
		notifications.GET("", h.GetNotifications)
		notifications.POST("", h.CreateNotification)
		notifications.POST("/read-all", h.MarkAllRead)
		notifications.PATCH("/:id/read", h.MarkRead)
		notifications.DELETE("/:id", h.DeleteNotification)
	}
}

func RegisterDeviceTokenRoutes(router *gin.Engine, h *handlers.DeviceTokenHandler) {
	deviceTokens := router.Group("/api/device-tokens")
	{
		deviceTokens.POST("", h.RegisterToken)
		deviceTokens.DELETE("", h.UnregisterToken)
	}
}

func RegisterBrokerRoutes(router *gin.Engine, h *handlers.BrokerHandler) {
	broker := router.Group("/api/broker")
	{
		broker.GET("/:id/subscription", h.GetSubscription)
	}
}
