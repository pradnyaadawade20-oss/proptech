package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterModerationRoutes(router *gin.Engine, h *handlers.ModerationHandler) {
	props := router.Group("/api/properties", middleware.AuthRequired())
	{
		props.GET("/my-moderation", h.MyModeration)
		props.POST("/check-duplicate", h.CheckDuplicate)
		props.POST("/:id/report", h.Report)
	}

	admin := router.Group("/api/admin", middleware.AdminRequired())
	{
		admin.GET("/moderation/pending", h.AdminPending)
		admin.PATCH("/properties/:id/approval", h.AdminReview)
		admin.GET("/reports", h.AdminReports)
		admin.PATCH("/reports/:id", h.AdminResolveReport)
	}
}