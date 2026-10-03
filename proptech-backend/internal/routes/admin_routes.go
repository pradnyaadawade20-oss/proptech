package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterAdminRoutes(router *gin.Engine, h *handlers.AdminHandler) {
	router.POST("/api/admin/login", h.Login)

	admin := router.Group("/api/admin", middleware.AdminRequired())
	{
		admin.GET("/stats", h.Stats)
		admin.GET("/users", h.Users)
		admin.DELETE("/users/:id", h.DeleteUser)
		admin.GET("/properties", h.Properties)
		admin.PATCH("/properties/:id/verified", h.SetVerified)
		admin.DELETE("/properties/:id", h.DeleteProperty)
		admin.GET("/visits", h.Visits)
		admin.GET("/agreements", h.Agreements)
	}
}
