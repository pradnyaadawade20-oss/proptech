package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterPropertyRoutes(router *gin.Engine, h *handlers.PropertyHandler) {
	router.GET("/p/:id", h.SharePage)
	properties := router.Group("/api/properties")
	{
		properties.GET("", h.GetAllProperties)
		properties.GET("/my", h.GetMyProperties)
		properties.GET("/:id", h.GetPropertyByID)
		properties.GET("/:id/image", h.ServePropertyImage)
		properties.GET("/:id/media/:mediaId", h.ServePropertyMedia)
		properties.GET("/:id/verification-photo", h.ServeVerificationPhoto)
	}

	propertiesAuthed := router.Group("/api/properties")
	propertiesAuthed.Use(middleware.AuthRequired())
	{
		propertiesAuthed.POST("", h.CreateProperty)
		propertiesAuthed.GET("/dashboard-stats", h.GetDashboardStats)
		propertiesAuthed.PUT("/:id", h.UpdateProperty)
		propertiesAuthed.PATCH("/:id/status", h.UpdateListingStatus)
		propertiesAuthed.DELETE("/:id", h.DeleteProperty)
		propertiesAuthed.POST("/:id/image", h.UploadPropertyImage)
		propertiesAuthed.POST("/:id/media", h.UploadPropertyMedia)
		propertiesAuthed.DELETE("/:id/media/:mediaId", h.DeletePropertyMedia)
		propertiesAuthed.POST("/:id/verify", h.VerifyProperty)
	}
}

func RegisterAuthRoutes(router *gin.Engine, h *handlers.AuthHandler) {
	auth := router.Group("/api/auth")
	{
		auth.POST("/send-otp", h.SendOTP)
		auth.POST("/verify-otp", h.VerifyOTP)
		auth.POST("/skip-otp", h.SkipOTP)
		auth.POST("/google", h.GoogleLogin)
		auth.PATCH("/users/:id/role", middleware.AuthRequired(), h.SwitchRole)
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
	messages.Use(middleware.AuthRequired())
	{
		messages.GET("/conversations", h.GetConversations)
		messages.GET("/thread", h.GetThread)
		messages.POST("", h.SendMessage)
		messages.POST("/read", h.MarkRead)
	}
}

func RegisterProfileRoutes(router *gin.Engine, h *handlers.ProfileHandler) {
	profile := router.Group("/api/profile")
	profile.Use(middleware.AuthRequired())
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

func RegisterBrokerRoutes(router *gin.Engine, h *handlers.BrokerHandler) {
	broker := router.Group("/api/broker")
	broker.Use(middleware.AuthRequired())
	{
		broker.GET("/:id/subscription", h.GetSubscription)
	}
}

func RegisterNotificationRoutes(router *gin.Engine, h *handlers.NotificationHandler) {
	// Jaan-boojh kar POST /api/notifications nahi hai — warna koi bhi kisi
	// ko bhi fake notification/push bhej sakta tha. Server khud banata hai.
	notifications := router.Group("/api/notifications")
	notifications.Use(middleware.AuthRequired())
	{
		notifications.GET("", h.GetNotifications)
		notifications.PATCH("/:id/read", h.MarkRead)
		notifications.POST("/read-all", h.MarkAllRead)
		notifications.DELETE("/:id", h.DeleteNotification)
	}
}

func RegisterDeviceTokenRoutes(router *gin.Engine, h *handlers.DeviceTokenHandler) {
	deviceTokens := router.Group("/api/device-tokens")
	deviceTokens.Use(middleware.AuthRequired())
	{
		deviceTokens.POST("", h.RegisterToken)
		deviceTokens.DELETE("", h.UnregisterToken)
	}
}
