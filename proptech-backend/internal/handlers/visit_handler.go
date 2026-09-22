package handlers

import (
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type VisitHandler struct {
	repo *repository.VisitRepository
}

func NewVisitHandler(repo *repository.VisitRepository) *VisitHandler {
	return &VisitHandler{repo: repo}
}

func (h *VisitHandler) CreateVisit(c *gin.Context) {
	var req models.CreateVisitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	visit, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"visit": visit})
}

// GetVisits returns visits for either a visitor (tenant/buyer) or an owner.
// GET /api/visits?visitor_id=...  -> visits I scheduled
// GET /api/visits?owner_id=...    -> visits on my properties
func (h *VisitHandler) GetVisits(c *gin.Context) {
	visitorID := c.Query("visitor_id")
	ownerID := c.Query("owner_id")

	if visitorID == "" && ownerID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "visitor_id or owner_id is required"})
		return
	}

	var visits []models.Visit
	var err error

	if visitorID != "" {
		visits, err = h.repo.GetByVisitorID(c.Request.Context(), visitorID)
	} else {
		visits, err = h.repo.GetByOwnerID(c.Request.Context(), ownerID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"visits": visits})
}

func (h *VisitHandler) UpdateVisitStatus(c *gin.Context) {
	id := c.Param("id")

	var req models.UpdateVisitStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	visit, err := h.repo.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"visit": visit})
}

func (h *VisitHandler) DeleteVisit(c *gin.Context) {
	id := c.Param("id")

	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Visit deleted"})
}