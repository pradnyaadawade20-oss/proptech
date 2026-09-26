package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"

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

// UploadPropertyImage: POST /api/properties/:id/image (multipart/form-data, field "image")
// Stores the actual uploaded photo bytes and points image_url at
// ServePropertyImage, so it's the exact photo the owner picked — not a
// placeholder — that shows up everywhere (home, buyer listings, detail).
func (h *PropertyHandler) UploadPropertyImage(c *gin.Context) {
	id := c.Param("id")

	file, header, err := c.Request.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image file is required (field name: image)"})
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/jpeg"
	}

	imageURL := fmt.Sprintf("%s/api/properties/%s/image", baseURL(c), id)

	if err := h.repo.SaveImage(c.Request.Context(), id, data, contentType, imageURL); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"image_url": imageURL})
}

// ServePropertyImage: GET /api/properties/:id/image
// Serves the raw bytes uploaded via UploadPropertyImage, so buyers,
// the home screen, and every other screen that renders image_url see
// the owner's actual photo.
func (h *PropertyHandler) ServePropertyImage(c *gin.Context) {
	id := c.Param("id")

	data, contentType, err := h.repo.GetImage(c.Request.Context(), id)
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "No uploaded image for this property"})
		return
	}

	c.Data(http.StatusOK, contentType, data)
}

// baseURL builds this server's own public URL from the incoming request,
// so image_url works both locally and once deployed (e.g. on Render)
// without hardcoding a host. Render's proxy terminates TLS and forwards
// the original scheme via X-Forwarded-Proto.
func baseURL(c *gin.Context) string {
	scheme := c.Request.Header.Get("X-Forwarded-Proto")
	if scheme == "" {
		if c.Request.TLS != nil {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}
	host := c.Request.Host
	if envURL := os.Getenv("PUBLIC_BASE_URL"); envURL != "" {
		return envURL
	}
	return fmt.Sprintf("%s://%s", scheme, host)
}

func (h *PropertyHandler) GetAllProperties(c *gin.Context) {
	properties, err := h.repo.GetAll(c.Request.Context())
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

// GetMyProperties returns all properties belonging to the logged-in owner.
// Expects owner_id as a query param for now (until auth middleware sets it on the context).
func (h *PropertyHandler) GetMyProperties(c *gin.Context) {
	ownerID := c.Query("owner_id")
	if ownerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "owner_id is required"})
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

	property, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"property": property})
}

func (h *PropertyHandler) UpdateProperty(c *gin.Context) {
	id := c.Param("id")

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

	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Property deleted"})
}

// UpdateListingStatus marks a property Available, Rented, or Sold — used
// from My Properties (owner/broker), feeds the dashboard stat pills.
func (h *PropertyHandler) UpdateListingStatus(c *gin.Context) {
	id := c.Param("id")

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

// GetDashboardStats backs OwnerDashboardScreen / BrokerDashboardScreen's
// "My Properties" card, Active Leads, and Visits This Week.
// Expects owner_id as a query param for now (until auth middleware sets it on the context).
func (h *PropertyHandler) GetDashboardStats(c *gin.Context) {
	ownerID := c.Query("owner_id")
	if ownerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "owner_id is required"})
		return
	}

	stats, err := h.repo.GetDashboardStats(c.Request.Context(), ownerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"stats": stats})
}