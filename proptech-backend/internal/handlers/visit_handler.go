package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

// maxReschedules caps how many times one visit can be moved.
const maxReschedules = 3

type VisitHandler struct {
	repo         *repository.VisitRepository
	propertyRepo *repository.PropertyRepository
	leads        *repository.LeadRepository
}

func NewVisitHandler(repo *repository.VisitRepository, propertyRepo *repository.PropertyRepository, leads *repository.LeadRepository) *VisitHandler {
	return &VisitHandler{repo: repo, propertyRepo: propertyRepo, leads: leads}
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

	// Lead hook: booking a visit = an enquiry (own-property etc. errors are ignored).
	if _, _, lerr := h.leads.Upsert(c.Request.Context(), visit.PropertyID, userID, "", "", "visit", ""); lerr != nil {
		log.Printf("lead upsert (visit) skipped: %v", lerr)
	}

	// Tell the property owner someone wants to visit.
	if property, perr := h.propertyRepo.GetByID(c.Request.Context(), visit.PropertyID); perr == nil && property.OwnerID != nil {
		notify.Send(*property.OwnerID, "visit", "New visit request",
			fmt.Sprintf("%s wants to visit %s", nameOr(visit.VisitorName, "Someone"), visit.PropertyTitle))
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

	// Lead hook: completed visit -> lead becomes "visited" (forward only).
	if visit.Status == "completed" {
		if lerr := h.leads.Advance(c.Request.Context(), visit.PropertyID, visit.VisitorID, "visited"); lerr != nil {
			log.Printf("lead advance (visited) failed: %v", lerr)
		}
	}

	h.notifyVisitStatus(c, visit, userID)

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

// notifyVisitStatus tells the *other* party that the visit status changed:
// visitor changed it -> owner is told; owner changed it -> visitor is told.
func (h *VisitHandler) notifyVisitStatus(c *gin.Context, visit *models.Visit, actorID string) {
	title := "Visit " + visit.Status
	if actorID == visit.VisitorID {
		if property, err := h.propertyRepo.GetByID(c.Request.Context(), visit.PropertyID); err == nil && property.OwnerID != nil {
			notify.Send(*property.OwnerID, "visit", title,
				fmt.Sprintf("%s marked the visit to %s as %s", nameOr(visit.VisitorName, "The visitor"), visit.PropertyTitle, visit.Status))
		}
		return
	}
	notify.Send(visit.VisitorID, "visit", title,
		fmt.Sprintf("Your visit to %s is now %s", visit.PropertyTitle, visit.Status))
}

func nameOr(name, fallback string) string {
	if name == "" {
		return fallback
	}
	return name
}

// POST /api/visits/:id/feedback
// The visitor tells the owner how the visit went (only after it is completed).
func (h *VisitHandler) SubmitFeedback(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	visit, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "visit not found"})
		return
	}
	if visit.VisitorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the visitor can give feedback"})
		return
	}
	if visit.Status != "completed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "feedback can be given after the visit is completed"})
		return
	}

	var req models.VisitFeedbackRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	visit, err = h.repo.SetFeedback(c.Request.Context(), id, req.Interest, req.Note)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Tell the owner.
	if property, perr := h.propertyRepo.GetByID(c.Request.Context(), visit.PropertyID); perr == nil && property.OwnerID != nil {
		who := nameOr(visit.VisitorName, "The visitor")
		var body string
		switch req.Interest {
		case "interested":
			body = fmt.Sprintf("%s is interested in %s", who, visit.PropertyTitle)
		case "maybe":
			body = fmt.Sprintf("%s is still thinking about %s", who, visit.PropertyTitle)
		default:
			body = fmt.Sprintf("%s is not interested in %s", who, visit.PropertyTitle)
		}
		notify.SendRoute(*property.OwnerID, "visit", "Visit feedback", body, "/visits")
	}

	c.JSON(http.StatusOK, gin.H{"visit": visit})
}

// PATCH /api/visits/:id/reschedule   body: {"scheduled_at": "<RFC3339>"}
// Visitor or property owner can move a pending/confirmed visit to a new time.
//   visitor reschedules -> status goes back to "pending" (owner re-confirms)
//   owner reschedules   -> status becomes "confirmed" (visitor is told the new time)
func (h *VisitHandler) RescheduleVisit(c *gin.Context) {
	id := c.Param("id")

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	if !h.userCanActOnVisit(c, id, userID) {
		return
	}

	var req models.RescheduleVisitRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	visit, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "visit not found"})
		return
	}
	if visit.Status != "pending" && visit.Status != "confirmed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "only upcoming (pending or confirmed) visits can be rescheduled"})
		return
	}
	if visit.RescheduleCount >= maxReschedules {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("this visit was already rescheduled %d times", maxReschedules)})
		return
	}
	if !req.ScheduledAt.After(time.Now().Add(15 * time.Minute)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "please pick a time in the future"})
		return
	}
	if req.ScheduledAt.Equal(visit.ScheduledAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "new time is the same as the current time"})
		return
	}

	actorIsVisitor := visit.VisitorID == userID
	newStatus := "confirmed"
	if actorIsVisitor {
		newStatus = "pending"
	}

	updated, err := h.repo.Reschedule(c.Request.Context(), id, req.ScheduledAt, newStatus)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Tell the other party.
	when := updated.ScheduledAt.Local().Format("2 Jan, 3:04 PM")
	if actorIsVisitor {
		if property, perr := h.propertyRepo.GetByID(c.Request.Context(), updated.PropertyID); perr == nil && property.OwnerID != nil {
			notify.SendRoute(*property.OwnerID, "visit", "Visit rescheduled",
				fmt.Sprintf("%s moved the visit to %s to %s — please confirm", nameOr(updated.VisitorName, "The visitor"), updated.PropertyTitle, when), "/visits")
		}
	} else {
		notify.SendRoute(updated.VisitorID, "visit", "Visit rescheduled",
			fmt.Sprintf("Your visit to %s was moved to %s", updated.PropertyTitle, when), "/visits")
	}

	c.JSON(http.StatusOK, gin.H{"visit": updated})
}