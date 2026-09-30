package handlers

import (
	"net/http"

	"proptech-backend/internal/middleware"
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

func (h *AgreementHandler) CreateAgreement(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req models.CreateAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if req.OwnerID != userID && req.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you must be the owner or tenant on this agreement"})
		return
	}

	agreement, err := h.repo.Create(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) GetAgreements(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreements, err := h.repo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreements": agreements})
}

func (h *AgreementHandler) GetAgreementByID(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreement, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}
	if agreement.OwnerID != userID && agreement.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you're not a party on this agreement"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": agreement})
}

func (h *AgreementHandler) UpdateDraft(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userIsParty(c, id, userID) {
		return
	}

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

func (h *AgreementHandler) SignAgreement(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	agreement, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return
	}

	var req models.SignAgreementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if (req.SignerRole == "owner" && agreement.OwnerID != userID) ||
		(req.SignerRole == "tenant" && agreement.TenantID != userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only sign as yourself"})
		return
	}

	signed, err := h.repo.Sign(c.Request.Context(), id, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"agreement": signed})
}

func (h *AgreementHandler) UpdateStatus(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userIsParty(c, id, userID) {
		return
	}

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

func (h *AgreementHandler) userIsParty(c *gin.Context, agreementID, userID string) bool {
	agreement, err := h.repo.GetByID(c.Request.Context(), agreementID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agreement not found"})
		return false
	}
	if agreement.OwnerID != userID && agreement.TenantID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you're not a party on this agreement"})
		return false
	}
	return true
}
