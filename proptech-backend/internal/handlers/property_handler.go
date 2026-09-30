package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
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
	if !h.requireOwner(c, id) {
		return
	}

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

	// ?v=<time> makes the URL change whenever the cover is replaced, so the
	// app doesn't keep showing the old cached photo.
	imageURL := fmt.Sprintf("%s/api/properties/%s/image?v=%d", baseURL(c), id, time.Now().Unix())

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
	h.repo.AttachMedia(c.Request.Context(), properties, baseURL(c))
	c.JSON(http.StatusOK, gin.H{"properties": properties})
}

func (h *PropertyHandler) GetPropertyByID(c *gin.Context) {
	id := c.Param("id")
	property, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Property not found"})
		return
	}
	one := []models.Property{*property}
	h.repo.AttachMedia(c.Request.Context(), one, baseURL(c))
	property = &one[0]
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
	h.repo.AttachMedia(c.Request.Context(), properties, baseURL(c))
	c.JSON(http.StatusOK, gin.H{"properties": properties})
}

func (h *PropertyHandler) CreateProperty(c *gin.Context) {
	var req models.CreatePropertyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if _, err := req.ParsedAvailableFrom(); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	property, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if property.OwnerID != nil {
		ownerID := *property.OwnerID
		propRoute := "/property/" + property.ID
		notify.SendRoute(ownerID, "property", "Property listed",
			fmt.Sprintf("Your property \"%s\" is now live.", property.Title), propRoute)

		// Tell everyone else about the new listing (set NOTIFY_NEW_LISTINGS=false to turn off).
		if os.Getenv("NOTIFY_NEW_LISTINGS") != "false" {
			title, location := property.Title, property.Location
			go func() {
				who := notify.UserName(ownerID)
				if who == "" {
					who = "Someone"
				}
				notify.BroadcastExcept(ownerID, "property", "New property listed",
					fmt.Sprintf("%s added %s in %s", who, title, location), propRoute)
			}()
		}
	}

	c.JSON(http.StatusCreated, gin.H{"property": property})
}

// requireOwner makes sure the logged-in user owns property `id`. On failure it
// writes the error response itself and returns false.
func (h *PropertyHandler) requireOwner(c *gin.Context, id string) bool {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return false
	}
	p, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Property not found"})
		return false
	}
	if p.OwnerID == nil || *p.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only change your own properties"})
		return false
	}
	return true
}

func (h *PropertyHandler) UpdateProperty(c *gin.Context) {
	id := c.Param("id")
	if !h.requireOwner(c, id) {
		return
	}

	var req models.UpdatePropertyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if _, err := req.ParsedAvailableFrom(); err != nil {
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
	if !h.requireOwner(c, id) {
		return
	}

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
	if !h.requireOwner(c, id) {
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

// VerifyProperty: POST /api/properties/:id/verify (multipart/form-data)
//
//	photo — required, a photo taken with the in-app camera (not gallery)
//	lat   — required, GPS latitude captured at the same moment
//	lng   — required, GPS longitude captured at the same moment
//
// This is what earns the "Verified" badge: a real photo of the property
// with GPS proof it was taken there, not a screenshot/downloaded/WhatsApp
// image (those never carry usable location data). Only the property's
// owner can verify it.
func (h *PropertyHandler) VerifyProperty(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	property, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "property not found"})
		return
	}
	if property.OwnerID == nil || *property.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the property's owner can verify it"})
		return
	}

	lat, err := strconv.ParseFloat(c.PostForm("lat"), 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lat is required and must be a number"})
		return
	}
	lng, err := strconv.ParseFloat(c.PostForm("lng"), 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lng is required and must be a number"})
		return
	}
	if lat == 0 && lng == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not get a GPS location for this photo — make sure location is turned on and try again"})
		return
	}

	file, header, err := c.Request.FormFile("photo")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a photo is required (field name: photo)"})
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(data) > maxImageBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("photo is larger than %d MB", maxImageBytes>>20)})
		return
	}

	contentType := header.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/jpeg"
	}

	if err := h.repo.SaveVerification(c.Request.Context(), id, data, contentType, lat, lng); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"is_verified":            true,
		"verification_photo_url": fmt.Sprintf("%s/api/properties/%s/verification-photo", baseURL(c), id),
	})
}

// ServeVerificationPhoto: GET /api/properties/:id/verification-photo
func (h *PropertyHandler) ServeVerificationPhoto(c *gin.Context) {
	data, contentType, err := h.repo.GetVerificationPhoto(c.Request.Context(), c.Param("id"))
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no verification photo for this property"})
		return
	}
	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=86400")
	c.Data(http.StatusOK, contentType, data)
}
