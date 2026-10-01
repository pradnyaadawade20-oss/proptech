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

	imageURL := fmt.Sprintf("%s/api/properties/%s/image?v=%d", baseURL(c), id, time.Now().Unix())

	if err := h.repo.SaveImage(c.Request.Context(), id, data, contentType, imageURL); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"image_url": imageURL})
}

// ServePropertyImage: GET /api/properties/:id/image
func (h *PropertyHandler) ServePropertyImage(c *gin.Context) {
	id := c.Param("id")

	data, contentType, err := h.repo.GetImage(c.Request.Context(), id)
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "No uploaded image for this property"})
		return
	}

	c.Data(http.StatusOK, contentType, data)
}

// baseURL builds this server's own public URL from the incoming request.
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

// GetMyProperties returns all properties belonging to the given owner.
// Still public (used to view any owner's listed properties, e.g. from the
// Owner Details screen), so owner_id stays a query param here.
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

// CreateProperty: POST /api/properties (login required)
func (h *PropertyHandler) CreateProperty(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.CreatePropertyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// The owner is ALWAYS the logged-in user; an owner_id in the body is
	// ignored, so nobody can create listings in someone else's name.
	req.OwnerID = userID

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

// requireOwner makes sure the logged-in user owns property `id`.
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

// GetDashboardStats backs OwnerDashboardScreen / BrokerDashboardScreen.
// Stats are always for the logged-in user — an owner_id query param is no
// longer accepted, so nobody can read someone else's dashboard numbers.
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

// VerifyProperty: POST /api/properties/:id/verify (multipart/form-data)
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
