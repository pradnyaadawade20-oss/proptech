package handlers

import (
	"errors"
	"net/http"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type ReviewHandler struct {
	repo         *repository.ReviewRepository
	propertyRepo *repository.PropertyRepository
}

func NewReviewHandler(repo *repository.ReviewRepository, propertyRepo *repository.PropertyRepository) *ReviewHandler {
	return &ReviewHandler{repo: repo, propertyRepo: propertyRepo}
}

// GetReviews: GET /api/properties/:id/reviews (public — same as viewing the listing)
func (h *ReviewHandler) GetReviews(c *gin.Context) {
	propertyID := c.Param("id")

	reviews, err := h.repo.GetByPropertyID(c.Request.Context(), propertyID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"reviews": reviews})
}

// CreateReview: POST /api/properties/:id/reviews (login required)
//
// Eligibility: you can't review your own property, and you must have a
// completed visit on it first — this keeps ratings tied to someone who
// actually visited, not a drive-by review.
func (h *ReviewHandler) CreateReview(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	propertyID := c.Param("id")

	property, err := h.propertyRepo.GetByID(c.Request.Context(), propertyID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "property not found"})
		return
	}
	if property.OwnerID != nil && *property.OwnerID == userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can't review your own property"})
		return
	}

	eligible, err := h.repo.HasCompletedVisit(c.Request.Context(), propertyID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !eligible {
		c.JSON(http.StatusForbidden, gin.H{"error": repository.ErrReviewNotEligible.Error()})
		return
	}

	var req models.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	review, err := h.repo.Create(c.Request.Context(), propertyID, userID, req)
	if err != nil {
		if errors.Is(err, repository.ErrAlreadyReviewed) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"review": review})
}

// CanReview: GET /api/properties/:id/reviews/eligibility (login required)
// Lets the app show/hide the "Write a review" button without guessing.
func (h *ReviewHandler) CanReview(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	propertyID := c.Param("id")

	alreadyReviewed, err := h.repo.HasReviewed(c.Request.Context(), propertyID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if alreadyReviewed {
		c.JSON(http.StatusOK, gin.H{"can_review": false, "reason": "already_reviewed"})
		return
	}

	hasVisit, err := h.repo.HasCompletedVisit(c.Request.Context(), propertyID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !hasVisit {
		c.JSON(http.StatusOK, gin.H{"can_review": false, "reason": "no_completed_visit"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"can_review": true})
}
