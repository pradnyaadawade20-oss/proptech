package handlers

// Deposit refund through Cashfree. The money goes back to the tenant's ORIGINAL
// payment method (UPI / card / net banking) that paid the deposit, so the app
// never needs the tenant's bank details.

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"

	"github.com/gin-gonic/gin"
)

// POST /api/leases/:id/deposit/refund-online   (owner)
func (h *PaymentHandler) RefundDepositOnline(c *gin.Context) {
	l, userID, role, ok := h.party(c)
	if !ok || !need(c, role, "owner") {
		return
	}
	if !h.cf.Configured() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "online refunds are not available right now"})
		return
	}
	ctx := c.Request.Context()
	d, err := h.repo.GetDeposit(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.Status != "refund_due" || d.RefundAmount <= 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "there is no refund due on this deposit"})
		return
	}
	if d.OnlineRefundStatus == "PENDING" || d.OnlineRefundStatus == "ONHOLD" {
		h.syncOnlineRefund(ctx, l, d) // already started: just refresh
		h.respondDeposit(c, l.ID)
		return
	}
	order, err := h.repo.PaidDepositOrder(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if order == nil || order.Amount < d.RefundAmount {
		c.JSON(http.StatusConflict, gin.H{"error": "this deposit was not paid through the app, so it cannot be refunded here. Refund it yourself and record it."})
		return
	}

	// Cashfree needs a unique id per refund attempt (a failed one can be retried).
	refundID := fmt.Sprintf("dep%s_%d", strings.ReplaceAll(l.ID, "-", ""), time.Now().Unix())
	rf, err := h.cf.CreateRefund(ctx, order.OrderID, refundID, d.RefundAmount, "Security deposit refund")
	if err != nil {
		log.Printf("cashfree create refund failed (lease %s): %v", l.ID, err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "could not start the refund. Please try again in a while"})
		return
	}
	_ = h.repo.SaveOnlineRefund(ctx, l.ID, refundID, rf.Status)
	h.repo.LogEvent(ctx, l.ID, userID, "deposit_refund_started", fmt.Sprintf("%s via the app (%s)", rupees(d.RefundAmount), rf.Status))
	h.applyRefundStatus(ctx, l, refundID, rf.Status, d.RefundAmount)
	if rf.Status == "FAILED" || rf.Status == "CANCELLED" {
		c.JSON(http.StatusBadGateway, gin.H{"error": "the refund was not accepted by the payment provider. You can try again or refund it yourself and record it"})
		return
	}
	h.respondDeposit(c, l.ID)
}

// GET /api/leases/:id/deposit/refund-online   (owner or tenant)
// Checks the refund's progress with Cashfree and finishes the deposit when it succeeded.
func (h *PaymentHandler) RefreshOnlineRefund(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	ctx := c.Request.Context()
	d, err := h.repo.GetDeposit(ctx, l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	h.syncOnlineRefund(ctx, l, d)
	h.respondDeposit(c, l.ID)
}

func (h *PaymentHandler) syncOnlineRefund(ctx context.Context, l *models.Lease, d *models.Deposit) {
	if d.OnlineRefundStatus != "PENDING" && d.OnlineRefundStatus != "ONHOLD" {
		return
	}
	refundID, _, err := h.repo.OnlineRefund(ctx, l.ID)
	if err != nil || refundID == "" {
		return
	}
	order, err := h.repo.PaidDepositOrder(ctx, l.ID)
	if err != nil || order == nil {
		return
	}
	rf, err := h.cf.GetRefund(ctx, order.OrderID, refundID)
	if err != nil {
		log.Printf("cashfree get refund failed (lease %s): %v", l.ID, err)
		return
	}
	_ = h.repo.SaveOnlineRefund(ctx, l.ID, refundID, rf.Status)
	h.applyRefundStatus(ctx, l, refundID, rf.Status, d.RefundAmount)
}

// applyRefundStatus closes the deposit when Cashfree says the refund is done.
func (h *PaymentHandler) applyRefundStatus(ctx context.Context, l *models.Lease, refundID, status string, amount float64) {
	switch status {
	case "SUCCESS":
		if err := h.repo.MarkRefunded(ctx, l.ID, "online_refund", refundID); err != nil {
			return // already closed
		}
		h.repo.LogEvent(ctx, l.ID, l.OwnerID, "deposit_refunded", "via the app")
		notify.SendRoute(l.TenantID, "deposit", "Deposit refunded",
			fmt.Sprintf("%s of your deposit for %s was refunded to your original payment method.", rupees(amount), l.PropertyTitle),
			leaseRoute(l.ID))
	case "FAILED", "CANCELLED":
		notify.SendRoute(l.OwnerID, "deposit", "Deposit refund failed",
			fmt.Sprintf("The refund for %s did not go through. Open the lease to try again.", l.PropertyTitle), leaseRoute(l.ID))
	}
}