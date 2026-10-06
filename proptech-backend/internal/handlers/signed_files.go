package handlers

import (
	"net/http"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/signedurl"

	"github.com/gin-gonic/gin"
)

const signedURLTTL = 5 * time.Minute

func verificationResource(propertyID string) string { return "property-verification:" + propertyID }
func leasePhotoResource(leaseID, photoID string) string {
	return "lease-photo:" + leaseID + ":" + photoID
}

// ---- property verification photo ------------------------------------------

// VerificationPhotoURL: GET /api/properties/:id/verification-photo-url
// Owner or admin only. Returns a link that stops working after 5 minutes.
func (h *PropertyHandler) VerificationPhotoURL(c *gin.Context) {
	id := c.Param("id")
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	role, _ := c.Get("role")
	isAdmin := userID == middleware.AdminUserID && role == "admin"
	if !isAdmin && !h.requireOwner(c, id) {
		return
	}
	q, err := signedurl.Query(verificationResource(id), signedURLTTL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create link"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"url":        baseURL(c) + "/api/properties/" + id + "/verification-photo?" + q,
		"expires_in": int(signedURLTTL.Seconds()),
	})
}

// ServeVerificationPhoto: GET /api/properties/:id/verification-photo?exp=&sig=
// Only works with a valid, unexpired signed link.
func (h *PropertyHandler) ServeVerificationPhoto(c *gin.Context) {
	id := c.Param("id")
	if !signedurl.Verify(verificationResource(id), c.Query("exp"), c.Query("sig")) {
		c.JSON(http.StatusForbidden, gin.H{"error": "link expired or invalid"})
		return
	}
	data, contentType, err := h.repo.GetVerificationPhoto(c.Request.Context(), id)
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no verification photo for this property"})
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, contentType, data)
}

// ---- lease photos ----------------------------------------------------------

// PhotoSignedURL: GET /api/leases/:id/photos/:photoId/url  (only the two parties)
func (h *LeaseHandler) PhotoSignedURL(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	photoID := c.Param("photoId")
	if _, err := h.repo.GetPhotoMeta(c.Request.Context(), l.ID, photoID); err != nil {
		leaseErr(c, err)
		return
	}
	q, err := signedurl.Query(leasePhotoResource(l.ID, photoID), signedURLTTL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create link"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"url":        baseURL(c) + "/api/files/lease-photo/" + l.ID + "/" + photoID + "?" + q,
		"expires_in": int(signedURLTTL.Seconds()),
	})
}

// PhotoServeSigned: GET /api/files/lease-photo/:leaseId/:photoId?exp=&sig=
func (h *LeaseHandler) PhotoServeSigned(c *gin.Context) {
	leaseID, photoID := c.Param("leaseId"), c.Param("photoId")
	if !signedurl.Verify(leasePhotoResource(leaseID, photoID), c.Query("exp"), c.Query("sig")) {
		c.JSON(http.StatusForbidden, gin.H{"error": "link expired or invalid"})
		return
	}
	data, ct, err := h.repo.GetPhotoData(c.Request.Context(), leaseID, photoID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.Header("Cache-Control", "private, no-store")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, ct, data)
}