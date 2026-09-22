package handlers

import (
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type FavoriteHandler struct {
	repo *repository.FavoriteRepository
}

func NewFavoriteHandler(repo *repository.FavoriteRepository) *FavoriteHandler {
	return &FavoriteHandler{repo: repo}
}

func (h *FavoriteHandler) AddFavorite(c *gin.Context) {
	var req models.AddFavoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	favorite, err := h.repo.Add(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"favorite": favorite})
}

// RemoveFavorite expects user_id and property_id as query params:
// DELETE /api/favorites?user_id=...&property_id=...
func (h *FavoriteHandler) RemoveFavorite(c *gin.Context) {
	userID := c.Query("user_id")
	propertyID := c.Query("property_id")
	if userID == "" || propertyID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id and property_id are required"})
		return
	}

	if err := h.repo.Remove(c.Request.Context(), userID, propertyID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Removed from favorites"})
}

// GetFavorites expects user_id as a query param:
// GET /api/favorites?user_id=...
func (h *FavoriteHandler) GetFavorites(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}

	properties, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"properties": properties})
}