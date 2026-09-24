package handlers

import (
	"net/http"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type VisitHandler struct {
	repo         *repository.VisitRepository
	propertyRepo *repository.PropertyRepository
}

func NewVisitHandler(repo *repository.VisitRepository, propertyRepo *repository.PropertyRepository) *VisitHandler {
	return &VisitHandler{repo: repo, propertyRepo: propertyRepo}
}

func (h *VisitHandler) CreateVisit(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.CreateVisitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.VisitorID = userID

	visit, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"visit": visit})
}

// GET /api/visits            -> visits I booked (as visitor)
// GET /api/visits?as=owner   -> visits on properties I own
func (h *VisitHandler) GetVisits(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var visits []models.Visit
	if c.Query("as") == "owner" {
		visits, err = h.repo.GetByOwnerID(c.Request.Context(), userID)
	} else {
		visits, err = h.repo.GetByVisitorID(c.Request.Context(), userID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"visits": visits})
}

func (h *VisitHandler) UpdateVisitStatus(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userCanActOnVisit(c, id, userID) {
		return
	}

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

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userCanActOnVisit(c, id, userID) {
		return
	}

	if err := h.repo.Delete(c.Request.Context(), id); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Visit deleted"})
}

func (h *VisitHandler) userCanActOnVisit(c *gin.Context, visitID, userID string) bool {
	visit, err := h.repo.GetByID(c.Request.Context(), visitID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "visit not found"})
		return false
	}
	if visit.VisitorID == userID {
		return true
	}

	property, err := h.propertyRepo.GetByID(c.Request.Context(), visit.PropertyID)
	if err == nil && property.OwnerID != nil && *property.OwnerID == userID {
		return true
	}

	c.JSON(http.StatusForbidden, gin.H{"error": "you can't modify this visit"})
	return false
}
