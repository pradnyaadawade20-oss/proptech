package handlers

import (
	"net/http"

	"proptech-backend/internal/models"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

type AgreementHandler struct {
	repo *repository.AgreementRepository
}

func NewAgreementHandler(repo *repository.AgreementRepository) *AgreementHandler {
	return &AgreementHandler{repo: repo}
}

// POST /api/agreements — tenant/owner raises a request for an agreement
func (h *AgreementHandler) CreateAgreement(c *gin.Context) {
	var req models.CreateAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agreement, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"agreement": agreement})
}

// GET /api/agreements?user_id=... — all agreements where user is owner or tenant
func (h *AgreementHandler) GetAgreements(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}

	agreements, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreements": agreements})
}

// GET /api/agreements/:id
func (h *AgreementHandler) GetAgreementByID(c *gin.Context) {
	id := c.Param("id")
	agreement, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

// PUT /api/agreements/:id/draft — fill in terms, moves status -> draft_ready
func (h *AgreementHandler) UpdateDraft(c *gin.Context) {
	id := c.Param("id")

	var req models.UpdateDraftRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agreement, err := h.repo.UpdateDraft(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

// POST /api/agreements/:id/sign — draw or type signature, no OTP
func (h *AgreementHandler) SignAgreement(c *gin.Context) {
	id := c.Param("id")

	var req models.SignAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agreement, err := h.repo.Sign(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

// PATCH /api/agreements/:id/status — cancel / reject
func (h *AgreementHandler) UpdateStatus(c *gin.Context) {
	id := c.Param("id")

	var req models.UpdateAgreementStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agreement, err := h.repo.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}