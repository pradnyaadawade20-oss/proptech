package handlers

import (
	"net/http"
	"strconv"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type PropertyHandler struct {
	repo *repository.PropertyRepository
}

func NewPropertyHandler(repo *repository.PropertyRepository) *PropertyHandler {
	return &PropertyHandler{repo: repo}
}

func (h *PropertyHandler) GetAllProperties(c *gin.Context) {
	filter := models.PropertyFilter{
		Location:      c.Query("location"),
		BHK:           c.Query("bhk"),
		Furnishing:    c.Query("furnishing"),
		Category:      c.Query("category"),
		ListingStatus: c.Query("listing_status"),
		Sort:          c.Query("sort"),
	}
	if v := c.Query("min_price"); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil {
			filter.MinPrice = &parsed
		}
	}
	if v := c.Query("max_price"); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil {
			filter.MaxPrice = &parsed
		}
	}

	properties, err := h.repo.GetFiltered(c.Request.Context(), filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"properties": properties})
}

func (h *PropertyHandler) GetPropertyByID(c *gin.Context) {
	id := c.Param("id")
	property, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Property not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"property": property})
}

func (h *PropertyHandler) GetMyProperties(c *gin.Context) {
	ownerID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	properties, err := h.repo.GetByOwnerID(c.Request.Context(), ownerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"properties": properties})
}

func (h *PropertyHandler) CreateProperty(c *gin.Context) {
	var req models.CreatePropertyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ownerID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	req.OwnerID = ownerID

	property, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"property": property})
}

func (h *PropertyHandler) UpdateProperty(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userOwnsProperty(c, id, userID) {
		return
	}

	var req models.UpdatePropertyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	property, err := h.repo.Update(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"property": property})
}

func (h *PropertyHandler) DeleteProperty(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userOwnsProperty(c, id, userID) {
		return
	}

	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Property deleted"})
}

func (h *PropertyHandler) UpdateListingStatus(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userOwnsProperty(c, id, userID) {
		return
	}

	var req models.UpdateListingStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	property, err := h.repo.UpdateListingStatus(c.Request.Context(), id, req.ListingStatus)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"property": property})
}

func (h *PropertyHandler) GetDashboardStats(c *gin.Context) {
	ownerID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	stats, err := h.repo.GetDashboardStats(c.Request.Context(), ownerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"stats": stats})
}

func (h *PropertyHandler) userOwnsProperty(c *gin.Context, propertyID, userID string) bool {
	property, err := h.repo.GetByID(c.Request.Context(), propertyID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Property not found"})
		return false
	}
	if property.OwnerID == nil || *property.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you don't own this property"})
		return false
	}
	return true
}
