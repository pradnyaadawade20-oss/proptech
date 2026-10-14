package handlers

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"proptech-backend/internal/models"
	"proptech-backend/internal/receipt"

	"github.com/gin-gonic/gin"
)

// GET /api/leases/:id/deposit/receipt
func (h *LeaseHandler) DepositReceipt(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	d, err := h.repo.GetDeposit(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.ReceivedAt == nil || d.Status == "pending" || d.Status == "submitted" {
		c.JSON(http.StatusConflict, gin.H{"error": "a receipt is available only after the owner confirms the deposit"})
		return
	}
	no := "DP-" + d.ReceivedAt.Format("0601") + "-" + strings.ToUpper(strings.ReplaceAll(d.ID, "-", "")[:6])
	ist := time.FixedZone("IST", 5*3600+1800)
	pdf := receipt.Build(receipt.Data{
		Title:         "SECURITY DEPOSIT RECEIPT",
		PeriodRowName: "Lease period",
		AmountLabel:   "Security deposit",
		HideLate:      true,
		ReceiptNo:     no,
		PropertyTitle: l.PropertyTitle,
		TenantName:    l.TenantName,
		OwnerName:     l.OwnerName,
		PeriodLabel:   models.ParseDate(l.StartDate).Format("2 Jan 2006") + " to " + models.ParseDate(l.EndDate).Format("2 Jan 2006"),
		PaidDate:      d.ReceivedAt.In(ist).Format("2 Jan 2006"),
		Method:        strings.ReplaceAll(d.PaymentMethod, "_", " "),
		Reference:     d.Reference,
		RentAmount:    d.Amount,
		Total:         d.Amount,
	})
	c.Header("Content-Disposition", fmt.Sprintf(`inline; filename="%s.pdf"`, no))
	c.Data(http.StatusOK, "application/pdf", pdf)
}