package handlers

import (
	"fmt"
	"net/http"
	"time"

	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

const maxAvatarBytes = 5 << 20 // 5 MB

var allowedAvatarTypes = map[string]bool{
	"image/jpeg": true,
	"image/png":  true,
	"image/webp": true,
	"image/gif":  true,
}

// UploadAvatar: POST /api/profile/:id/avatar (multipart/form-data, field "avatar")
// Only the owner of the profile can change it. Responds with {"user": {...}}
// where user.avatar_url already points at the new photo.
func (h *ProfileHandler) UploadAvatar(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	id := c.Param("id")
	if id != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only change your own photo"})
		return
	}

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxAvatarBytes+(1<<20))
	fh, err := c.FormFile("avatar")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "photo is required (field name: avatar)"})
		return
	}
	if fh.Size > maxAvatarBytes {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("photo is larger than %d MB", maxAvatarBytes>>20)})
		return
	}
	data, err := readUpload(fh)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Sniff the real bytes instead of trusting the client's Content-Type.
	ct := http.DetectContentType(data)
	if !allowedAvatarTypes[ct] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "only JPG, PNG, WebP or GIF photos are allowed"})
		return
	}

	// ?v= busts the app's image cache whenever the photo changes.
	avatarURL := fmt.Sprintf("%s/api/profile/%s/avatar?v=%d", baseURL(c), id, time.Now().Unix())
	user, err := h.repo.SaveAvatar(c.Request.Context(), id, data, ct, avatarURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": user})
}

// ServeAvatar: GET /api/profile/:id/avatar  (public — Image.network can't send
// the JWT, and chat / owner screens show other people's photos too).
func (h *ProfileHandler) ServeAvatar(c *gin.Context) {
	data, ct, err := h.repo.GetAvatar(c.Request.Context(), c.Param("id"))
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no photo"})
		return
	}
	c.Header("Cache-Control", "public, max-age=86400")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, ct, data)
}

// DeleteAvatar: DELETE /api/profile/:id/avatar
func (h *ProfileHandler) DeleteAvatar(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	id := c.Param("id")
	if id != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only change your own photo"})
		return
	}
	user, err := h.repo.ClearAvatar(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": user})
}