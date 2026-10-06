package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/privacy"
	"proptech-backend/internal/ratelimit"
	"proptech-backend/internal/relay"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ContactHandler: Buyer -> Lead -> Relay -> Owner. The owner's number is never returned.
type ContactHandler struct {
	db       *pgxpool.Pool
	provider relay.Provider
}

func NewContactHandler(db *pgxpool.Pool, p relay.Provider) *ContactHandler {
	return &ContactHandler{db: db, provider: p}
}

// RequestCall: POST /api/contact/request-call {lead_id}
func (h *ContactHandler) RequestCall(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req struct {
		LeadID string `json:"lead_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "lead_id is required"})
		return
	}
	ctx := c.Request.Context()

	var buyerID, ownerID, buyerPhone, ownerPhone, buyerName, title string
	err = h.db.QueryRow(ctx, `
		SELECT l.buyer_id::text, l.owner_id::text,
		       COALESCE(NULLIF(l.phone, ''), b.phone, ''), COALESCE(o.phone, ''),
		       COALESCE(NULLIF(l.name, ''), b.name, ''), COALESCE(p.title, '')
		FROM leads l
		JOIN users b ON b.id = l.buyer_id
		JOIN users o ON o.id = l.owner_id
		LEFT JOIN properties p ON p.id = l.property_id
		WHERE l.id = $1::uuid`, req.LeadID).
		Scan(&buyerID, &ownerID, &buyerPhone, &ownerPhone, &buyerName, &title)
	if err != nil || buyerID != userID {
		c.JSON(http.StatusNotFound, gin.H{"error": "enquiry not found"})
		return
	}
	if blocked, retry := ratelimit.Hit(ctx, "contact-call:"+userID, 5, time.Hour, time.Hour); blocked {
		ratelimit.Reject(c, retry)
		return
	}

	mode, status := h.provider.Name(), "requested"
	if mode == "relay" {
		if err := h.provider.Connect(ctx, relay.Request{LeadID: req.LeadID, BuyerPhone: buyerPhone, OwnerPhone: ownerPhone}); err != nil {
			log.Printf("relay connect failed for lead %s: %v", req.LeadID, err)
			mode, status = "callback", "failed"
		} else {
			status = "connected"
		}
	}
	_, _ = h.db.Exec(ctx,
		`INSERT INTO contact_requests (lead_id, requester_id, target_id, mode, status)
		 VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5)`, req.LeadID, userID, ownerID, mode, status)

	if mode == "callback" {
		name := buyerName
		if name == "" {
			name = "A buyer"
		}
		notify.SendRoute(ownerID, "lead", "Call request",
			fmt.Sprintf("%s asked for a call about %s. Open Leads to call back.", name, title), "/home")
	}
	msg := "The owner has been asked to call you back."
	if mode == "relay" {
		msg = "You will get a call shortly that connects you to the owner."
	}
	c.JSON(http.StatusOK, gin.H{
		"status":             status,
		"mode":               mode,
		"message":            msg,
		"owner_phone_masked": privacy.MaskPhone(ownerPhone),
	})
}