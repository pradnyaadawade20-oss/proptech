package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

type LeadHandler struct {
	repo *repository.LeadRepository
}

func NewLeadHandler(repo *repository.LeadRepository) *LeadHandler {
	return &LeadHandler{repo: repo}
}

// POST /api/leads  {property_id, message?, source?}  -> "Contact Owner"
func (h *LeadHandler) Create(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.CreateLeadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	req.Name = strings.TrimSpace(req.Name)
	req.Phone = strings.TrimSpace(req.Phone)
	if len(req.Message) > 1000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is too long"})
		return
	}

	lead, created, err := h.repo.Upsert(c.Request.Context(), req.PropertyID, userID, req.Name, req.Phone, req.Source, req.Message)
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrLeadOwnProperty):
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		case errors.Is(err, repository.ErrLeadNoOwner), errors.Is(err, pgx.ErrNoRows):
			c.JSON(http.StatusNotFound, gin.H{"error": "property not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	if created {
		notify.SendRoute(lead.OwnerID, "lead", "New enquiry",
			fmt.Sprintf("%s is interested in %s", nameOr(lead.Name, "Someone"), lead.PropertyTitle), "/home")
	}
	ownerName, ownerPhone, _ := h.repo.OwnerContact(c.Request.Context(), lead.OwnerID)
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	c.JSON(status, gin.H{
		"lead":        lead,
		"is_new":      created,
		"owner_name":  ownerName,
		"owner_phone": ownerPhone,
	})
}

// GET /api/leads?status=&page=&limit=  -> leads on MY properties (default, what the app's Leads screen uses)
//   response: {leads, counts{all,new,contacted,visited,closed}, total, has_more}
// GET /api/leads?as=buyer               -> enquiries I made
func (h *LeadHandler) List(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	ctx := c.Request.Context()

	if c.Query("as") == "buyer" {
		leads, err := h.repo.ListByBuyer(ctx, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"leads": leads})
		return
	}

	status := c.Query("status")
	switch status {
	case "", "new", "contacted", "visited", "closed":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status"})
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 50 {
		limit = 20
	}
	offset := (page - 1) * limit

	leads, total, err := h.repo.ListByOwner(ctx, userID, status, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	counts, err := h.repo.CountsByOwner(ctx, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"leads":    leads,
		"counts":   counts,
		"total":    total,
		"has_more": offset+len(leads) < total,
	})
}

// PATCH /api/leads/:id/status {status: new|contacted|visited|closed}  (owner only)
func (h *LeadHandler) UpdateStatus(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.UpdateLeadStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	lead, err := h.repo.GetByID(c.Request.Context(), c.Param("id"))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "lead not found"})
		return
	}
	if lead.OwnerID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the property owner can update this lead"})
		return
	}
	updated, err := h.repo.SetStatus(c.Request.Context(), lead.ID, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"lead": updated})
}