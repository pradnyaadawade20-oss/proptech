package routes

import (
	"time"

	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/ratelimit"

	"github.com/gin-gonic/gin"
)

func RegisterCallRoutes(router *gin.Engine, h *handlers.CallHandler) {
	calls := router.Group("/api/calls", middleware.AuthRequired())
	{
		calls.POST("", ratelimit.User("call-start", 10, time.Minute, time.Minute), h.Create)
		calls.GET("", h.History)
		calls.GET("/ice-servers", h.IceServers)
		calls.POST("/:id/reject", h.Reject)
	}
	// WebSocket signaling. Authenticates itself (Authorization header, or ?token=).
	router.GET("/ws/calls", h.Socket)
}