package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterLeadRoutes(router *gin.Engine, h *handlers.LeadHandler) {
	leads := router.Group("/api/leads")
	leads.Use(middleware.AuthRequired())
	{
		leads.POST("", h.CreateLead)
		leads.GET("", h.GetLeads)
		leads.PATCH("/:id/status", h.UpdateLeadStatus)
	}
}
