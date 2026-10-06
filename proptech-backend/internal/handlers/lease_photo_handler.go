package handlers

import (
	"fmt"
	"net/http"
	"sort"
	"strings"

	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"

	"github.com/gin-gonic/gin"
)

const (
	leasePhotoMaxBytes   = 8 << 20  // 8 MB per photo
	leaseUploadMaxBytes  = 40 << 20 // whole request
	leasePhotosPerKind   = 60       // move_in / move_out photos per lease
	ticketPhotosMax      = 8
	deductionPhotosMax   = 6
	leasePhotosPerUpload = 10
)

// Rooms shown in the move-in / move-out comparison, in this order.
var roomOrder = []string{"Living Room", "Bedroom", "Kitchen", "Bathroom", "Balcony", "Other"}

func limitBody(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, leaseUploadMaxBytes)
}

func validRoom(r string) string {
	r = strings.TrimSpace(r)
	for _, x := range roomOrder {
		if strings.EqualFold(x, r) {
			return x
		}
	}
	return "Other"
}

// imageType checks the real bytes (not just the filename) — only photos get in.
func imageType(declared string, data []byte) (string, bool) {
	sniff := http.DetectContentType(data)
	switch sniff {
	case "image/jpeg", "image/png", "image/webp", "image/gif":
		return sniff, true
	}
	// HEIC/HEIF (iPhone) is not detected by the standard library.
	d := strings.ToLower(declared)
	if d == "image/heic" || d == "image/heif" {
		return d, true
	}
	return "", false
}

// savePhotos stores every file of the form field "images". It returns the
// created photos, or a user-facing message when something is wrong (in which
// case NOTHING was saved for the failing file; earlier files of the same call
// may already be saved).
func (h *LeaseHandler) savePhotos(c *gin.Context, l *models.Lease, userID, kind, room, caption string,
	deductionID, ticketID *string, maxPerCall int) ([]models.LeasePhoto, string) {

	form, err := c.MultipartForm()
	if err != nil {
		return nil, "could not read the upload (too large or malformed)"
	}
	files := form.File["images"]
	if len(files) == 0 {
		return nil, ""
	}
	if len(files) > maxPerCall {
		return nil, fmt.Sprintf("you can add at most %d photos at a time", maxPerCall)
	}
	ctx := c.Request.Context()

	n, err := h.repo.CountPhotos(ctx, l.ID, kind, deductionID, ticketID)
	if err != nil {
		return nil, "could not check existing photos"
	}
	limit := leasePhotosPerKind
	if ticketID != nil {
		limit = ticketPhotosMax
	}
	if deductionID != nil {
		limit = deductionPhotosMax
	}
	if n+len(files) > limit {
		return nil, fmt.Sprintf("only %d photos are allowed here", limit)
	}

	// Validate everything first, then store — so a bad file does not leave half an upload.
	type item struct {
		ct   string
		data []byte
	}
	items := make([]item, 0, len(files))
	for _, fh := range files {
		if fh.Size > leasePhotoMaxBytes {
			return nil, fmt.Sprintf("photo %s is larger than %d MB", fh.Filename, leasePhotoMaxBytes>>20)
		}
		data, rerr := readUpload(fh)
		if rerr != nil {
			return nil, "could not read " + fh.Filename
		}
		ct, ok := imageType(resolveContentType(fh, data), data)
		if !ok {
			return nil, fh.Filename + " is not a photo (use JPG, PNG or WebP)"
		}
		items = append(items, item{ct: ct, data: data})
	}

	created := make([]models.LeasePhoto, 0, len(items))
	for _, it := range items {
		id, serr := h.repo.AddPhoto(ctx, l.ID, userID, kind, room, caption, deductionID, ticketID, it.ct, it.data)
		if serr != nil {
			return created, "could not save the photo, please try again"
		}
		meta, merr := h.repo.GetPhotoMeta(ctx, l.ID, id)
		if merr == nil {
			created = append(created, *meta)
		}
	}
	return created, ""
}

// photoPhaseOpen tells whether photos of this kind may still be added / removed.
func photoPhaseOpen(l *models.Lease, kind string) (bool, string) {
	switch kind {
	case "move_in":
		if l.Status != "active" {
			return false, "move-in photos can only be added while the lease is active"
		}
		if l.MoveInConfirmedAt != nil {
			return false, "move-in photos are locked because the tenant confirmed them"
		}
	case "move_out":
		if l.Status != "notice_given" && l.Status != "moved_out" {
			return false, "move-out photos can be added after the tenant gives notice"
		}
		switch l.DepositStatus {
		case "settlement", "disputed", "refund_due", "refunded":
			return false, "move-out photos are locked because the deposit settlement has started"
		}
	default:
		return false, "invalid photo type"
	}
	return true, ""
}

// POST /api/leases/:id/photos   multipart: kind (move_in|move_out), room, caption, images[]
func (h *LeaseHandler) PhotoUpload(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok {
		return
	}
	limitBody(c)
	kind := strings.TrimSpace(c.PostForm("kind"))
	if kind != "move_in" && kind != "move_out" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "kind must be move_in or move_out"})
		return
	}
	if open, msg := photoPhaseOpen(l, kind); !open {
		c.JSON(http.StatusConflict, gin.H{"error": msg})
		return
	}
	room := validRoom(c.PostForm("room"))
	caption := strings.TrimSpace(c.PostForm("caption"))
	if len(caption) > 200 {
		caption = caption[:200]
	}
	photos, msg := h.savePhotos(c, l, userID, kind, room, caption, nil, nil, leasePhotosPerUpload)
	if msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	if len(photos) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "choose at least one photo (field name: images)"})
		return
	}
	h.repo.LogEvent(c.Request.Context(), l.ID, userID, kind+"_photos",
		fmt.Sprintf("%d photo(s) in %s by %s", len(photos), room, role))
	notify.SendRoute(otherParty(l, role), "lease", "New "+strings.ReplaceAll(kind, "_", "-")+" photos",
		fmt.Sprintf("%d photo(s) added for %s (%s).", len(photos), l.PropertyTitle, room), leaseRoute(l.ID))
	c.JSON(http.StatusCreated, gin.H{"photos": photos})
}

// GET /api/leases/:id/photos?kind=move_in|move_out|damage|maintenance
func (h *LeaseHandler) PhotoList(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	photos, err := h.repo.ListPhotos(c.Request.Context(), l.ID, c.Query("kind"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"photos": photos})
}

// GET /api/leases/:id/photos/:photoId   -> the image bytes (only the two parties)
func (h *LeaseHandler) PhotoServe(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	data, ct, err := h.repo.GetPhotoData(c.Request.Context(), l.ID, c.Param("photoId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	c.Header("Cache-Control", "private, max-age=86400")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Data(http.StatusOK, ct, data)
}

// DELETE /api/leases/:id/photos/:photoId   (only the uploader, only while the phase is open)
func (h *LeaseHandler) PhotoDelete(c *gin.Context) {
	l, userID, _, ok := h.party(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	meta, err := h.repo.GetPhotoMeta(ctx, l.ID, c.Param("photoId"))
	if err != nil {
		leaseErr(c, err)
		return
	}
	if meta.UploaderID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only delete photos you uploaded"})
		return
	}
	switch meta.Kind {
	case "move_in", "move_out":
		if open, msg := photoPhaseOpen(l, meta.Kind); !open {
			c.JSON(http.StatusConflict, gin.H{"error": msg})
			return
		}
	case "damage":
		if l.DepositStatus != "inspection" {
			c.JSON(http.StatusConflict, gin.H{"error": "damage photos are locked after the inspection"})
			return
		}
	}
	if err := h.repo.DeletePhoto(ctx, l.ID, meta.ID); err != nil {
		leaseErr(c, err)
		return
	}
	h.repo.LogEvent(ctx, l.ID, userID, "photo_deleted", meta.Kind+" / "+meta.Room)
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

type roomComparison struct {
	Room    string              `json:"room"`
	MoveIn  []models.LeasePhoto `json:"move_in"`
	MoveOut []models.LeasePhoto `json:"move_out"`
}

// GET /api/leases/:id/comparison   — move-in vs move-out per room + deductions
func (h *LeaseHandler) Comparison(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	photos, err := h.repo.ListPhotos(ctx, l.ID, "")
	if err != nil {
		leaseErr(c, err)
		return
	}
	byRoom := map[string]*roomComparison{}
	for _, p := range photos {
		if p.Kind != "move_in" && p.Kind != "move_out" {
			continue
		}
		rc := byRoom[p.Room]
		if rc == nil {
			rc = &roomComparison{Room: p.Room, MoveIn: []models.LeasePhoto{}, MoveOut: []models.LeasePhoto{}}
			byRoom[p.Room] = rc
		}
		if p.Kind == "move_in" {
			rc.MoveIn = append(rc.MoveIn, p)
		} else {
			rc.MoveOut = append(rc.MoveOut, p)
		}
	}
	rooms := make([]roomComparison, 0, len(byRoom))
	for _, rc := range byRoom {
		rooms = append(rooms, *rc)
	}
	rank := func(room string) int {
		for i, x := range roomOrder {
			if x == room {
				return i
			}
		}
		return len(roomOrder)
	}
	sort.Slice(rooms, func(i, j int) bool {
		ri, rj := rank(rooms[i].Room), rank(rooms[j].Room)
		if ri != rj {
			return ri < rj
		}
		return rooms[i].Room < rooms[j].Room
	})

	deductions := []models.Deduction{}
	if d, derr := h.repo.GetDeposit(ctx, l.ID); derr == nil {
		deductions = d.Deductions
	}
	c.JSON(http.StatusOK, gin.H{
		"rooms":              rooms,
		"deductions":         deductions,
		"move_in_confirmed":  l.MoveInConfirmedAt != nil,
		"move_out_date":      l.MoveOutDate,
		"lease_status":       l.Status,
		"deposit_status":     l.DepositStatus,
	})
}