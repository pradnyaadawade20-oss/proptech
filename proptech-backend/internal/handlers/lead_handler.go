package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type LeadHandler struct {
	repo         *repository.LeadRepository
	propertyRepo *repository.PropertyRepository
	userRepo     *repository.UserRepository
}

func NewLeadHandler(repo *repository.LeadRepository, propertyRepo *repository.PropertyRepository, userRepo *repository.UserRepository) *LeadHandler {
	return &LeadHandler{repo: repo, propertyRepo: propertyRepo, userRepo: userRepo}
}

// CreateLead: POST /api/leads
// The buyer is always the logged-in user. The response also carries the
// owner's name/phone so the app can show / dial it right after the enquiry.
func (h *LeadHandler) CreateLead(c *gin.Context) {
	buyerID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.CreateLeadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Phone = strings.TrimSpace(req.Phone)
	req.Message = strings.TrimSpace(req.Message)
	if len(req.Message) > 1000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message is too long (max 1000 characters)"})
		return
	}
	if len(req.Phone) > 20 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone number is too long"})
		return
	}

	property, err := h.propertyRepo.GetByID(c.Request.Context(), req.PropertyID)
	if err != nil || property == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Property not found"})
		return
	}
	if property.OwnerID == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "This listing has no owner to contact"})
		return
	}
	ownerID := *property.OwnerID
	if ownerID == buyerID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "You can't enquire on your own property"})
		return
	}

	// Fill blanks from the buyer's profile so the owner always has a name/phone.
	if buyer, _ := h.userRepo.GetByID(c.Request.Context(), buyerID); buyer != nil {
		if req.Name == "" {
			req.Name = buyer.Name
		}
		if req.Phone == "" {
			req.Phone = buyer.Phone
		}
	}

	lead, isNew, err := h.repo.Upsert(c.Request.Context(), ownerID, buyerID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if isNew {
		notify.SendRoute(ownerID, "lead", "New lead",
			fmt.Sprintf("%s is interested in %s", nameOr(lead.Name, "Someone"), property.Title), "/leads")
	}

	out := gin.H{"lead": lead, "is_new": isNew}
	if owner, _ := h.userRepo.GetByID(c.Request.Context(), ownerID); owner != nil {
		out["owner_name"] = owner.Name
		out["owner_phone"] = owner.Phone
	}
	c.JSON(http.StatusCreated, out)
}

// GetLeads: GET /api/leads?status=new&page=1&limit=20   -> leads on MY properties
//
//	GET /api/leads?as=buyer                              -> enquiries I sent
func (h *LeadHandler) GetLeads(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	if c.Query("as") == "buyer" {
		leads, err := h.repo.ListByBuyer(c.Request.Context(), userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"leads": leads})
		return
	}

	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	switch status {
	case "", "new", "contacted", "visited", "closed":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be new, contacted, visited or closed"})
		return
	}
	page, _ := strconv.Atoi(c.Query("page"))
	limit, _ := strconv.Atoi(c.Query("limit"))

	leads, total, err := h.repo.ListByOwner(c.Request.Context(), userID, status, page, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	counts, err := h.repo.Counts(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if page < 1 {
		page = 1
	}
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	c.JSON(http.StatusOK, gin.H{
		"leads":    leads,
		"total":    total,
		"counts":   counts,
		"page":     page,
		"has_more": page*limit < total,
	})
}

// UpdateLeadStatus: PATCH /api/leads/:id/status {status}
func (h *LeadHandler) UpdateLeadStatus(c *gin.Context) {
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
	lead, err := h.repo.UpdateStatus(c.Request.Context(), c.Param("id"), userID, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if lead == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Lead not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"lead": lead})
}
