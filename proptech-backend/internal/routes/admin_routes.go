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
		admin.DELETE("/users/:id", h.RequestDeleteUser) // needs 2nd admin
		admin.POST("/users/:id/suspend", h.SuspendUser)
		admin.POST("/users/:id/unsuspend", h.UnsuspendUser)
		admin.GET("/properties", h.Properties)
		admin.PATCH("/properties/:id/verified", h.SetVerified)
		admin.DELETE("/properties/:id", h.RequestDeleteProperty) // needs 2nd admin
		admin.GET("/properties/hidden", h.HiddenProperties)
		admin.PATCH("/properties/:id/visibility", h.SetPropertyHidden)
		admin.GET("/audit-logs", h.AuditLogs)
		admin.GET("/approvals", h.Approvals)
		admin.POST("/approvals/refund", h.RequestRefund)
		admin.POST("/approvals/:id/approve", h.ApproveRequest)
		admin.POST("/approvals/:id/reject", h.RejectRequest)
		admin.GET("/visits", h.Visits)
		admin.GET("/agreements", h.Agreements)
	}
}