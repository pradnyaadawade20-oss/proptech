package handlers

import (
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ModerationHandler: listing approval status, duplicate check, reports.
type ModerationHandler struct {
	db   *pgxpool.Pool
	repo *repository.PropertyRepository
}

func NewModerationHandler(db *pgxpool.Pool) *ModerationHandler {
	return &ModerationHandler{db: db, repo: repository.NewPropertyRepository(db)}
}

var validReportReasons = map[string]bool{
	"spam": true, "fake_listing": true, "wrong_info": true,
	"already_rented_sold": true, "duplicate": true, "inappropriate": true, "other": true,
}

// MyModeration: GET /api/properties/my-moderation
func (h *ModerationHandler) MyModeration(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id::text, approval_status, rejection_reason FROM properties WHERE owner_id = $1::uuid`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load listing status"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, status, reason string
		if err := rows.Scan(&id, &status, &reason); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read listing status"})
			return
		}
		items = append(items, gin.H{"property_id": id, "approval_status": status, "rejection_reason": reason})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// CheckDuplicate: POST /api/properties/check-duplicate
func (h *ModerationHandler) CheckDuplicate(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req struct {
		Category    string  `json:"category"`
		BHK         string  `json:"bhk"`
		Area        float64 `json:"area"`
		FloorNumber int     `json:"floor_number"`
		Society     string  `json:"society"`
		Locality    string  `json:"locality"`
		City        string  `json:"city"`
		Pincode     string  `json:"pincode"`
		Latitude    float64 `json:"latitude"`
		Longitude   float64 `json:"longitude"`
		ExcludeID   string  `json:"exclude_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	matches, err := h.repo.FindDuplicates(c.Request.Context(), repository.DupQuery{
		Category: req.Category, BHK: req.BHK, Society: req.Society, Locality: req.Locality,
		City: req.City, Pincode: req.Pincode, Area: req.Area, Floor: req.FloorNumber,
		Lat: req.Latitude, Lng: req.Longitude, ExcludeID: req.ExcludeID,
	}, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not check duplicates"})
		return
	}
	blocked := false
	for _, m := range matches {
		if m.SameOwner {
			blocked = true
			break
		}
	}
	c.JSON(http.StatusOK, gin.H{"has_duplicates": len(matches) > 0, "blocked": blocked, "duplicates": matches})
}

// Report: POST /api/properties/:id/report {reason, details}
func (h *ModerationHandler) Report(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req struct {
		Reason  string `json:"reason"`
		Details string `json:"details"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || !validReportReasons[req.Reason] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a valid reason is required"})
		return
	}
	id := c.Param("id")
	var owner *string
	if err := h.db.QueryRow(c.Request.Context(),
		`SELECT owner_id::text FROM properties WHERE id = $1::uuid`, id).Scan(&owner); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}
	if owner != nil && *owner == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "you cannot report your own listing"})
		return
	}
	tag, err := h.db.Exec(c.Request.Context(),
		`INSERT INTO property_reports (property_id, reporter_id, reason, details)
		 VALUES ($1::uuid, $2::uuid, $3, $4)
		 ON CONFLICT (property_id, reporter_id) DO NOTHING`,
		id, userID, req.Reason, strings.TrimSpace(req.Details))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not save report"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "you have already reported this listing"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"message": "report submitted"})
}

// ---- admin ----------------------------------------------------------------

// AdminPending: GET /api/admin/moderation/pending
func (h *ModerationHandler) AdminPending(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id::text, title, location, approval_status, COALESCE(duplicate_of::text, '')
		 FROM properties WHERE approval_status = 'pending' ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load listings"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, title, loc, status, dup string
		if err := rows.Scan(&id, &title, &loc, &status, &dup); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read listings"})
			return
		}
		items = append(items, gin.H{"id": id, "title": title, "location": loc, "approval_status": status, "duplicate_of": dup})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// AdminReview: PATCH /api/admin/properties/:id/approval {status, reason}
func (h *ModerationHandler) AdminReview(c *gin.Context) {
	var req struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil ||
		(req.Status != repository.ApprovalApproved && req.Status != repository.ApprovalRejected) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be approved or rejected"})
		return
	}
	if req.Status == repository.ApprovalRejected && strings.TrimSpace(req.Reason) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a rejection reason is required"})
		return
	}
	tag, err := h.db.Exec(c.Request.Context(),
		`UPDATE properties SET approval_status = $2, rejection_reason = $3, reviewed_at = NOW()
		 WHERE id = $1::uuid`, c.Param("id"), req.Status, strings.TrimSpace(req.Reason))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not update listing"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "listing not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "updated"})
}

// AdminReports: GET /api/admin/reports?status=open
func (h *ModerationHandler) AdminReports(c *gin.Context) {
	status := c.DefaultQuery("status", "open")
	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id::text, property_id::text, reporter_id::text, reason, details, status, created_at::text
		 FROM property_reports WHERE status = $1 ORDER BY created_at DESC LIMIT 200`, status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load reports"})
		return
	}
	defer rows.Close()
	items := []gin.H{}
	for rows.Next() {
		var id, pid, rid, reason, details, st, created string
		if err := rows.Scan(&id, &pid, &rid, &reason, &details, &st, &created); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read reports"})
			return
		}
		items = append(items, gin.H{"id": id, "property_id": pid, "reporter_id": rid,
			"reason": reason, "details": details, "status": st, "created_at": created})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// AdminResolveReport: PATCH /api/admin/reports/:id {status, admin_note}
func (h *ModerationHandler) AdminResolveReport(c *gin.Context) {
	var req struct {
		Status    string `json:"status"`
		AdminNote string `json:"admin_note"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || (req.Status != "dismissed" && req.Status != "resolved") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be dismissed or resolved"})
		return
	}
	tag, err := h.db.Exec(c.Request.Context(),
		`UPDATE property_reports SET status = $2, admin_note = $3, resolved_at = NOW() WHERE id = $1::uuid`,
		c.Param("id"), req.Status, strings.TrimSpace(req.AdminNote))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not update report"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "report not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "updated"})
}