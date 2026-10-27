package handlers

import (
	"net/http"

	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

// GET /api/properties/my-stats  (login required) - views / interested for the caller's own listings.
func (h *PropertyHandler) GetMyPropertyStats(c *gin.Context) {
	ownerID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	stats, err := h.repo.OwnerStats(c.Request.Context(), ownerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"stats": stats})
}