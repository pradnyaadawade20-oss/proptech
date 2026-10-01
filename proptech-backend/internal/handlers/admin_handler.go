package handlers

import (
	"crypto/subtle"
	"net/http"
	"os"
	"strings"

	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type AdminHandler struct {
	db *pgxpool.Pool
}

func NewAdminHandler(db *pgxpool.Pool) *AdminHandler { return &AdminHandler{db: db} }

// Login: POST /api/admin/login {email, password}
// Credentials come from ADMIN_EMAIL / ADMIN_PASSWORD in .env (no DB changes).
func (h *AdminHandler) Login(c *gin.Context) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "email and password are required"})
		return
	}
	wantEmail := strings.ToLower(strings.TrimSpace(os.Getenv("ADMIN_EMAIL")))
	wantPass := os.Getenv("ADMIN_PASSWORD")
	if wantEmail == "" || wantPass == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "admin login is not configured: set ADMIN_EMAIL and ADMIN_PASSWORD"})
		return
	}
	gotEmail := strings.ToLower(strings.TrimSpace(req.Email))
	okEmail := subtle.ConstantTimeCompare([]byte(gotEmail), []byte(wantEmail)) == 1
	okPass := subtle.ConstantTimeCompare([]byte(req.Password), []byte(wantPass)) == 1
	if !okEmail || !okPass {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "wrong email or password"})
		return
	}
	token, err := middleware.GenerateToken(middleware.AdminUserID, wantEmail, "admin")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create token"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"token": token, "email": wantEmail})
}

func (h *AdminHandler) list(c *gin.Context, sql string, args ...any) {
	rows, err := h.db.Query(c.Request.Context(), sql, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	items, err := pgx.CollectRows(rows, pgx.RowToMap)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if items == nil {
		items = []map[string]any{}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (h *AdminHandler) Stats(c *gin.Context) {
	var users, props, verified, visits, agreements, completed int
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT (SELECT count(*) FROM users),
		       (SELECT count(*) FROM properties),
		       (SELECT count(*) FROM properties WHERE is_verified),
		       (SELECT count(*) FROM visits),
		       (SELECT count(*) FROM agreements),
		       (SELECT count(*) FROM agreements WHERE status = 'completed')`).
		Scan(&users, &props, &verified, &visits, &agreements, &completed)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"users": users, "properties": props, "verified_properties": verified,
		"visits": visits, "agreements": agreements, "completed_agreements": completed,
	})
}

func (h *AdminHandler) Users(c *gin.Context) {
	h.list(c, `SELECT id::text AS id, name, COALESCE(email,'') AS email, COALESCE(phone,'') AS phone,
		COALESCE(active_role, role) AS active_role, roles, email_verified, created_at
		FROM users ORDER BY created_at DESC LIMIT 1000`)
}

func (h *AdminHandler) Properties(c *gin.Context) {
	h.list(c, `SELECT p.id::text AS id, p.title, p.price::float8 AS price, p.price_unit, p.bhk, p.category,
		p.city, p.locality, p.location, p.is_verified, p.listing_status, p.created_at,
		COALESCE(u.name,'') AS owner_name
		FROM properties p LEFT JOIN users u ON u.id = p.owner_id
		ORDER BY p.created_at DESC LIMIT 1000`)
}

func (h *AdminHandler) Visits(c *gin.Context) {
	h.list(c, `SELECT v.id::text AS id, COALESCE(p.title,'(deleted)') AS property, COALESCE(u.name,'') AS visitor,
		v.scheduled_at, v.status
		FROM visits v LEFT JOIN properties p ON p.id = v.property_id LEFT JOIN users u ON u.id = v.visitor_id
		ORDER BY v.scheduled_at DESC LIMIT 1000`)
}

func (h *AdminHandler) Agreements(c *gin.Context) {
	h.list(c, `SELECT a.id::text AS id, COALESCE(p.title,'(deleted)') AS property, o.name AS owner, t.name AS tenant,
		a.status, COALESCE(a.monthly_rent,0)::float8 AS monthly_rent, a.created_at
		FROM agreements a
		LEFT JOIN properties p ON p.id = a.property_id
		JOIN users o ON o.id = a.owner_id JOIN users t ON t.id = a.tenant_id
		ORDER BY a.created_at DESC LIMIT 1000`)
}

// SetVerified: PATCH /api/admin/properties/:id/verified {verified: bool}
func (h *AdminHandler) SetVerified(c *gin.Context) {
	var req struct {
		Verified *bool `json:"verified" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "verified (true/false) is required"})
		return
	}
	tag, err := h.db.Exec(c.Request.Context(), `UPDATE properties SET is_verified = $1 WHERE id = $2::uuid`, *req.Verified, c.Param("id"))
	h.done(c, tag.RowsAffected(), err, "Property updated")
}

func (h *AdminHandler) DeleteProperty(c *gin.Context) {
	tag, err := h.db.Exec(c.Request.Context(), `DELETE FROM properties WHERE id = $1::uuid`, c.Param("id"))
	h.done(c, tag.RowsAffected(), err, "Property deleted")
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	tag, err := h.db.Exec(c.Request.Context(), `DELETE FROM users WHERE id = $1::uuid`, c.Param("id"))
	h.done(c, tag.RowsAffected(), err, "User deleted")
}

func (h *AdminHandler) done(c *gin.Context, affected int64, err error, msg string) {
	switch {
	case err != nil:
		// e.g. a user who is part of an agreement can't be deleted (foreign key).
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
	case affected == 0:
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
	default:
		c.JSON(http.StatusOK, gin.H{"message": msg})
	}
}