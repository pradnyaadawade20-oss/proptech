package handlers

import (
	"context"
	"encoding/json"
	"log"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
)

type sqlExecer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// adminEmail is who is acting (set by middleware.AdminRequired).
func adminEmail(c *gin.Context) string {
	if v, ok := c.Get("admin_email"); ok {
		if s, ok := v.(string); ok && s != "" {
			return s
		}
	}
	return "unknown-admin"
}

func toJSON(v any) any {
	if v == nil {
		return nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	return string(b)
}

// writeAudit records WHO / WHAT / WHEN / OLD / NEW. It never fails the request.
func writeAudit(ctx context.Context, db sqlExecer, who, action, entityType, entityID string, oldV, newV any) {
	_, err := db.Exec(ctx,
		`INSERT INTO admin_audit_log (admin_email, action, entity_type, entity_id, old_value, new_value)
		 VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb)`,
		who, action, entityType, entityID, toJSON(oldV), toJSON(newV))
	if err != nil {
		log.Printf("audit log write failed (%s %s %s): %v", who, action, entityID, err)
	}
}

// AuditLogs: GET /api/admin/audit-logs?entity_type=&entity_id=&admin=&limit=
func (h *AdminHandler) AuditLogs(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "200"))
	if limit < 1 || limit > 1000 {
		limit = 200
	}
	h.list(c, `SELECT id::text AS id, admin_email, action, entity_type, entity_id,
		old_value, new_value, created_at
		FROM admin_audit_log
		WHERE ($1 = '' OR entity_type = $1) AND ($2 = '' OR entity_id = $2) AND ($3 = '' OR admin_email = $3)
		ORDER BY created_at DESC LIMIT $4`,
		c.Query("entity_type"), c.Query("entity_id"), c.Query("admin"), limit)
}