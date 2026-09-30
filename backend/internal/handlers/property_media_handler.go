package handlers

import (
	"bytes"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

const (
	maxExtraImages  = 15
	maxImageBytes   = 10 << 20 // 10 MB per photo
	maxVideoBytes   = 50 << 20 // 50 MB per video
	maxRequestBytes = 120 << 20
)

var videoExtTypes = map[string]string{
	".mp4":  "video/mp4",
	".m4v":  "video/mp4",
	".mov":  "video/quicktime",
	".3gp":  "video/3gpp",
	".webm": "video/webm",
	".mkv":  "video/x-matroska",
}

// resolveContentType trusts the uploaded Content-Type when it's specific,
// otherwise falls back to the file extension, then to sniffing the bytes.
func resolveContentType(fh *multipart.FileHeader, data []byte) string {
	ct := fh.Header.Get("Content-Type")
	if ct != "" && ct != "application/octet-stream" {
		return ct
	}
	ext := strings.ToLower(filepath.Ext(fh.Filename))
	if t, ok := videoExtTypes[ext]; ok {
		return t
	}
	if t := mime.TypeByExtension(ext); t != "" {
		return t
	}
	return http.DetectContentType(data)
}

func readUpload(fh *multipart.FileHeader) ([]byte, error) {
	f, err := fh.Open()
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return io.ReadAll(f)
}

// UploadPropertyMedia: POST /api/properties/:id/media (multipart/form-data)
//
//	images — zero or more extra photos (repeat the field)
//	video  — optional walkthrough video (replaces any existing one)
//
// The cover photo still goes through POST /:id/image. Responds with the
// property's full current extras: additional_image_urls + video_tour_url.
func (h *PropertyHandler) UploadPropertyMedia(c *gin.Context) {
	id := c.Param("id")

	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxRequestBytes)
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "could not read upload (too large or malformed): " + err.Error()})
		return
	}

	images := form.File["images"]
	videos := form.File["video"]
	if len(images) == 0 && len(videos) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send photos in field 'images' and/or a video in field 'video'"})
		return
	}

	existing, err := h.repo.CountMedia(c.Request.Context(), id, "image")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing+len(images) > maxExtraImages {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("a listing can have at most %d extra photos", maxExtraImages)})
		return
	}

	for _, fh := range images {
		if fh.Size > maxImageBytes {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("photo %s is larger than %d MB", fh.Filename, maxImageBytes>>20)})
			return
		}
		data, err := readUpload(fh)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		ct := resolveContentType(fh, data)
		if !strings.HasPrefix(ct, "image/") {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("%s is not an image", fh.Filename)})
			return
		}
		if _, err := h.repo.SaveMedia(c.Request.Context(), id, "image", ct, data); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	if len(videos) > 0 {
		fh := videos[0]
		if fh.Size > maxVideoBytes {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("video is larger than %d MB", maxVideoBytes>>20)})
			return
		}
		data, err := readUpload(fh)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		ct := resolveContentType(fh, data)
		if !strings.HasPrefix(ct, "video/") {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("%s is not a video", fh.Filename)})
			return
		}
		if _, err := h.repo.SaveMedia(c.Request.Context(), id, "video", ct, data); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	refs, err := h.repo.ListMedia(c.Request.Context(), []string{id})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	imgURLs, videoURL := repository.MediaURLs(refs, baseURL(c))
	resp := gin.H{"additional_image_urls": imgURLs}
	if videoURL != "" {
		resp["video_tour_url"] = videoURL
	}
	c.JSON(http.StatusOK, resp)
}

// ServePropertyMedia: GET /api/properties/:id/media/:mediaId
// Serves a stored extra photo or the video. Uses ServeContent so video
// players get Range support (seeking / progressive playback).
func (h *PropertyHandler) ServePropertyMedia(c *gin.Context) {
	data, contentType, err := h.repo.GetMedia(c.Request.Context(), c.Param("id"), c.Param("mediaId"))
	if err != nil || len(data) == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "media not found"})
		return
	}
	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=86400")
	http.ServeContent(c.Writer, c.Request, "", time.Time{}, bytes.NewReader(data))
}