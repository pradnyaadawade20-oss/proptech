package handlers

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// ---- verified (audited) ----------------------------------------------------

// SetVerified: PATCH /api/admin/properties/:id/verified {verified: bool}
func (h *AdminHandler) SetVerified(c *gin.Context) {
	var req struct {
		Verified *bool `json:"verified" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "verified (true/false) is required"})
		return
	}
	ctx := c.Request.Context()
	id := c.Param("id")
	var old bool
	if err := h.db.QueryRow(ctx, `SELECT is_verified FROM properties WHERE id = $1::uuid`, id).Scan(&old); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	tag, err := h.db.Exec(ctx, `UPDATE properties SET is_verified = $1 WHERE id = $2::uuid`, *req.Verified, id)
	if err == nil && tag.RowsAffected() > 0 {
		writeAudit(ctx, h.db, adminEmail(c), "property.verify", "property", id,
			gin.H{"verified": old}, gin.H{"verified": *req.Verified})
	}
	h.done(c, tag.RowsAffected(), err, "Property updated")
}

// ---- maker-checker ---------------------------------------------------------

func isUniqueViolation(err error) bool {
	var pe *pgconn.PgError
	return errors.As(err, &pe) && pe.Code == "23505"
}

func (h *AdminHandler) createApproval(c *gin.Context, action, entityID, summary, reason string, payload gin.H) {
	ctx := c.Request.Context()
	me := adminEmail(c)
	var id string
	err := h.db.QueryRow(ctx,
		`INSERT INTO admin_approvals (action, entity_id, summary, reason, payload, requested_by)
		 VALUES ($1, $2, $3, $4, $5::jsonb, $6) RETURNING id::text`,
		action, entityID, summary, reason, toJSON(payload), me).Scan(&id)
	if err != nil {
		if isUniqueViolation(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "a request for this is already waiting for approval"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create approval request"})
		return
	}
	writeAudit(ctx, h.db, me, "approval.request."+action, "approval", id, nil,
		gin.H{"entity_id": entityID, "summary": summary, "reason": reason})
	c.JSON(http.StatusAccepted, gin.H{
		"message": "Request created. Another admin must approve it.", "approval_id": id, "status": "pending",
	})
}

func bodyReason(c *gin.Context) string {
	var b struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&b)
	return strings.TrimSpace(b.Reason)
}

// RequestDeleteUser: DELETE /api/admin/users/:id  (needs a second admin)
func (h *AdminHandler) RequestDeleteUser(c *gin.Context) {
	id := c.Param("id")
	var name, email string
	if err := h.db.QueryRow(c.Request.Context(),
		`SELECT name, COALESCE(email,'') FROM users WHERE id = $1::uuid`, id).Scan(&name, &email); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	h.createApproval(c, "delete_user", id, "Delete user "+name+" ("+email+")", bodyReason(c),
		gin.H{"name": name, "email": email})
}

// RequestDeleteProperty: DELETE /api/admin/properties/:id  (needs a second admin)
func (h *AdminHandler) RequestDeleteProperty(c *gin.Context) {
	id := c.Param("id")
	var title string
	if err := h.db.QueryRow(c.Request.Context(),
		`SELECT title FROM properties WHERE id = $1::uuid`, id).Scan(&title); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	h.createApproval(c, "delete_property", id, "Delete property "+title, bodyReason(c), gin.H{"title": title})
}

// RequestRefund: POST /api/admin/approvals/refund {lease_id, method, reference, reason}
func (h *AdminHandler) RequestRefund(c *gin.Context) {
	var req struct {
		LeaseID   string `json:"lease_id"`
		Method    string `json:"method"`
		Reference string `json:"reference"`
		Reason    string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.LeaseID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lease_id is required"})
		return
	}
	var amount float64
	var status string
	if err := h.db.QueryRow(c.Request.Context(),
		`SELECT refund_amount::float8, status FROM lease_deposits WHERE lease_id = $1::uuid`,
		req.LeaseID).Scan(&amount, &status); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "deposit not found"})
		return
	}
	if status != "refund_due" {
		c.JSON(http.StatusConflict, gin.H{"error": "deposit is not waiting for a refund"})
		return
	}
	h.createApproval(c, "refund_deposit", req.LeaseID, "Refund deposit", strings.TrimSpace(req.Reason),
		gin.H{"lease_id": req.LeaseID, "amount": amount, "method": req.Method, "reference": req.Reference})
}

// Approvals: GET /api/admin/approvals?status=pending
func (h *AdminHandler) Approvals(c *gin.Context) {
	h.list(c, `SELECT id::text AS id, action, entity_id, summary, reason, payload, status,
		requested_by, COALESCE(decided_by,'') AS decided_by, decision_note, error, created_at, decided_at
		FROM admin_approvals WHERE ($1 = '' OR status = $1)
		ORDER BY created_at DESC LIMIT 500`, c.DefaultQuery("status", "pending"))
}

// ApproveRequest: POST /api/admin/approvals/:id/approve {note}
func (h *AdminHandler) ApproveRequest(c *gin.Context) {
	var req struct {
		Note string `json:"note"`
	}
	_ = c.ShouldBindJSON(&req)
	ctx := c.Request.Context()
	me := adminEmail(c)

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not start"})
		return
	}
	defer tx.Rollback(ctx)

	var action, entityID, requestedBy string
	var method, reference *string
	err = tx.QueryRow(ctx,
		`SELECT action, entity_id, requested_by, payload->>'method', payload->>'reference'
		 FROM admin_approvals WHERE id = $1::uuid AND status = 'pending' FOR UPDATE`, c.Param("id")).
		Scan(&action, &entityID, &requestedBy, &method, &reference)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "pending request not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not load request"})
		return
	}
	if requestedBy == me {
		c.JSON(http.StatusForbidden, gin.H{"error": "a different admin must approve your request"})
		return
	}

	execErr := h.execute(ctx, tx, me, action, entityID, method, reference)
	if execErr != nil {
		_ = tx.Rollback(ctx)
		_, _ = h.db.Exec(ctx,
			`UPDATE admin_approvals SET status = 'failed', error = $2, decided_by = $3, decided_at = NOW()
			 WHERE id = $1::uuid`, c.Param("id"), execErr.Error(), me)
		c.JSON(http.StatusConflict, gin.H{"error": execErr.Error()})
		return
	}
	if _, err := tx.Exec(ctx,
		`UPDATE admin_approvals SET status = 'approved', decided_by = $2, decision_note = $3, decided_at = NOW()
		 WHERE id = $1::uuid`, c.Param("id"), me, strings.TrimSpace(req.Note)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not save decision"})
		return
	}
	writeAudit(ctx, tx, me, "approval.approve", "approval", c.Param("id"),
		gin.H{"status": "pending"}, gin.H{"status": "approved", "requested_by": requestedBy})
	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not commit"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Approved and executed"})
}

func (h *AdminHandler) execute(ctx context.Context, tx pgx.Tx, me, action, entityID string, method, reference *string) error {
	switch action {
	case "delete_user":
		var name, email string
		_ = tx.QueryRow(ctx, `SELECT name, COALESCE(email,'') FROM users WHERE id = $1::uuid`, entityID).Scan(&name, &email)
		tag, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1::uuid`, entityID)
		if err != nil {
			return errors.New("cannot delete user: " + err.Error())
		}
		if tag.RowsAffected() == 0 {
			return errors.New("user no longer exists")
		}
		middleware.InvalidateSuspension(entityID)
		writeAudit(ctx, tx, me, "user.delete", "user", entityID, gin.H{"name": name, "email": email}, nil)
	case "delete_property":
		var title string
		_ = tx.QueryRow(ctx, `SELECT title FROM properties WHERE id = $1::uuid`, entityID).Scan(&title)
		tag, err := tx.Exec(ctx, `DELETE FROM properties WHERE id = $1::uuid`, entityID)
		if err != nil {
			return errors.New("cannot delete property: " + err.Error())
		}
		if tag.RowsAffected() == 0 {
			return errors.New("property no longer exists")
		}
		writeAudit(ctx, tx, me, "property.delete", "property", entityID, gin.H{"title": title}, nil)
	case "refund_deposit":
		m, r := "", ""
		if method != nil {
			m = *method
		}
		if reference != nil {
			r = *reference
		}
		tag, err := tx.Exec(ctx,
			`UPDATE lease_deposits SET status = 'refunded', refunded_at = NOW(), refund_method = $2, refund_reference = $3
			 WHERE lease_id = $1::uuid AND status = 'refund_due'`, entityID, m, r)
		if err != nil {
			return errors.New("cannot refund: " + err.Error())
		}
		if tag.RowsAffected() == 0 {
			return errors.New("deposit is not waiting for a refund")
		}
		writeAudit(ctx, tx, me, "deposit.refund", "lease", entityID,
			gin.H{"status": "refund_due"}, gin.H{"status": "refunded", "method": m, "reference": r})
	default:
		return errors.New("unknown action")
	}
	return nil
}

// RejectRequest: POST /api/admin/approvals/:id/reject {note}
func (h *AdminHandler) RejectRequest(c *gin.Context) {
	var req struct {
		Note string `json:"note"`
	}
	_ = c.ShouldBindJSON(&req)
	ctx := c.Request.Context()
	me := adminEmail(c)
	var requestedBy string
	if err := h.db.QueryRow(ctx,
		`SELECT requested_by FROM admin_approvals WHERE id = $1::uuid AND status = 'pending'`,
		c.Param("id")).Scan(&requestedBy); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "pending request not found"})
		return
	}
	if requestedBy == me {
		c.JSON(http.StatusForbidden, gin.H{"error": "a different admin must decide your request"})
		return
	}
	tag, err := h.db.Exec(ctx,
		`UPDATE admin_approvals SET status = 'rejected', decided_by = $2, decision_note = $3, decided_at = NOW()
		 WHERE id = $1::uuid AND status = 'pending'`, c.Param("id"), me, strings.TrimSpace(req.Note))
	if err != nil || tag.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "could not reject"})
		return
	}
	writeAudit(ctx, h.db, me, "approval.reject", "approval", c.Param("id"),
		gin.H{"status": "pending"}, gin.H{"status": "rejected"})
	c.JSON(http.StatusOK, gin.H{"message": "Rejected"})
}

// ---- suspension ------------------------------------------------------------

// SuspendUser: POST /api/admin/users/:id/suspend {reason}
func (h *AdminHandler) SuspendUser(c *gin.Context) {
	reason := bodyReason(c)
	if reason == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "a reason is required"})
		return
	}
	ctx := c.Request.Context()
	id := c.Param("id")
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not start"})
		return
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`UPDATE users SET suspended_at = NOW(), suspended_reason = $2
		 WHERE id = $1::uuid AND suspended_at IS NULL`, id, reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not suspend user"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "user not found or already suspended"})
		return
	}
	hidden, err := tx.Exec(ctx,
		`UPDATE properties SET approval_status = 'hidden', hidden_reason = 'owner_suspended'
		 WHERE owner_id = $1::uuid AND approval_status = 'approved'`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not hide listings"})
		return
	}
	writeAudit(ctx, tx, adminEmail(c), "user.suspend", "user", id,
		gin.H{"suspended": false}, gin.H{"suspended": true, "reason": reason, "listings_hidden": hidden.RowsAffected()})
	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not commit"})
		return
	}
	middleware.InvalidateSuspension(id)
	c.JSON(http.StatusOK, gin.H{"message": "User suspended", "listings_hidden": hidden.RowsAffected()})
}

// UnsuspendUser: POST /api/admin/users/:id/unsuspend
func (h *AdminHandler) UnsuspendUser(c *gin.Context) {
	ctx := c.Request.Context()
	id := c.Param("id")
	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not start"})
		return
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`UPDATE users SET suspended_at = NULL, suspended_reason = ''
		 WHERE id = $1::uuid AND suspended_at IS NOT NULL`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not unsuspend user"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "user not found or not suspended"})
		return
	}
	restored, err := tx.Exec(ctx,
		`UPDATE properties SET approval_status = 'approved', hidden_reason = ''
		 WHERE owner_id = $1::uuid AND approval_status = 'hidden' AND hidden_reason = 'owner_suspended'`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not restore listings"})
		return
	}
	writeAudit(ctx, tx, adminEmail(c), "user.unsuspend", "user", id,
		gin.H{"suspended": true}, gin.H{"suspended": false, "listings_restored": restored.RowsAffected()})
	if err := tx.Commit(ctx); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not commit"})
		return
	}
	middleware.InvalidateSuspension(id)
	c.JSON(http.StatusOK, gin.H{"message": "User unsuspended", "listings_restored": restored.RowsAffected()})
}

// ---- hidden listings (reports) ---------------------------------------------

// HiddenProperties: GET /api/admin/properties/hidden — auto-hidden listings waiting for review.
func (h *AdminHandler) HiddenProperties(c *gin.Context) {
	h.list(c, `SELECT p.id::text AS id, p.title, p.location, p.hidden_reason,
		(SELECT COUNT(DISTINCT reporter_id) FROM property_reports r WHERE r.property_id = p.id AND r.status = 'open') AS open_reports
		FROM properties p WHERE p.approval_status = 'hidden' ORDER BY p.created_at DESC LIMIT 500`)
}

// SetPropertyHidden: PATCH /api/admin/properties/:id/visibility {hidden: bool}
func (h *AdminHandler) SetPropertyHidden(c *gin.Context) {
	var req struct {
		Hidden *bool `json:"hidden" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "hidden (true/false) is required"})
		return
	}
	ctx := c.Request.Context()
	id := c.Param("id")
	var old string
	if err := h.db.QueryRow(ctx, `SELECT approval_status FROM properties WHERE id = $1::uuid`, id).Scan(&old); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	var tag pgconn.CommandTag
	var err error
	if *req.Hidden {
		tag, err = h.db.Exec(ctx,
			`UPDATE properties SET approval_status = 'hidden', hidden_reason = 'admin'
			 WHERE id = $1::uuid AND approval_status = 'approved'`, id)
	} else {
		tag, err = h.db.Exec(ctx,
			`UPDATE properties SET approval_status = 'approved', hidden_reason = ''
			 WHERE id = $1::uuid AND approval_status = 'hidden'`, id)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not update listing"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "listing is not in a state that can be changed"})
		return
	}
	if !*req.Hidden {
		_, _ = h.db.Exec(ctx,
			`UPDATE property_reports SET status = 'dismissed', resolved_at = NOW()
			 WHERE property_id = $1::uuid AND status = 'open'`, id)
	}
	now := "approved"
	if *req.Hidden {
		now = "hidden"
	}
	writeAudit(ctx, h.db, adminEmail(c), "property.visibility", "property", id,
		gin.H{"approval_status": old}, gin.H{"approval_status": now})
	c.JSON(http.StatusOK, gin.H{"message": "updated"})
}