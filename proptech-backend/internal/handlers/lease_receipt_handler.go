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

var receiptIST = time.FixedZone("IST", 5*3600+1800)

// stamp formats a time as "2 Jan 2006, 3:04 PM IST".
func stamp(t time.Time) string { return t.In(receiptIST).Format("2 Jan 2006, 3:04 PM") + " IST" }

func upperFirst(s string) string {
	s = strings.ReplaceAll(s, "_", " ")
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// GET /api/leases/:id/deposit/receipt   (payment receipt - after the owner confirms the deposit)
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
		PaidDate:      stamp(*d.ReceivedAt),
		Method:        strings.ReplaceAll(d.PaymentMethod, "_", " "),
		Reference:     d.Reference,
		RentAmount:    d.Amount,
		Total:         d.Amount,
	})
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s.pdf"`, no))
	c.Data(http.StatusOK, "application/pdf", pdf)
}

// GET /api/leases/:id/deposit/refund-receipt   (after the deposit is settled and refunded)
func (h *LeaseHandler) RefundReceipt(c *gin.Context) {
	l, _, _, ok := h.party(c)
	if !ok {
		return
	}
	d, err := h.repo.GetDeposit(c.Request.Context(), l.ID)
	if err != nil {
		leaseErr(c, err)
		return
	}
	if d.Status != "refunded" || d.RefundedAt == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "the refund receipt is available only after the deposit is refunded"})
		return
	}
	no := "RF-" + d.RefundedAt.Format("0601") + "-" + strings.ToUpper(strings.ReplaceAll(d.ID, "-", "")[:6])

	method := strings.ReplaceAll(d.RefundMethod, "_", " ")
	if d.RefundMethod == "online_refund" {
		method = "Online refund (to original payment method)"
	} else {
		method = upperFirst(method)
	}
	paidOn := ""
	if d.ReceivedAt != nil {
		paidOn = stamp(*d.ReceivedAt)
	}
	ded := make([]receipt.RefundDeduction, 0, len(d.Deductions))
	for _, x := range d.Deductions {
		ded = append(ded, receipt.RefundDeduction{Category: upperFirst(x.Category), Reason: x.Reason, Amount: x.Amount})
	}

	pdf := receipt.BuildRefund(receipt.RefundData{
		ReceiptNo:       no,
		PropertyTitle:   l.PropertyTitle,
		TenantName:      l.TenantName,
		OwnerName:       l.OwnerName,
		LeasePeriod:     models.ParseDate(l.StartDate).Format("2 Jan 2006") + " to " + models.ParseDate(l.EndDate).Format("2 Jan 2006"),
		DepositPaidOn:   paidOn,
		RefundedOn:      stamp(*d.RefundedAt),
		Method:          method,
		Reference:       d.RefundReference,
		DepositAmount:   d.Amount,
		Deductions:      ded,
		TotalDeductions: d.TotalDeductions,
		TenantOwes:      d.TenantOwes,
		RefundAmount:    d.RefundAmount,
		GeneratedOn:     stamp(time.Now()),
	})
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s.pdf"`, no))
	c.Data(http.StatusOK, "application/pdf", pdf)
}