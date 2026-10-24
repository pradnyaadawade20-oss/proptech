package repository

// Early exit: what a tenant owes when leaving before the lease ends. It only
// SUGGESTS deductions; the owner decides in the normal deposit inspection.

import (
	"context"
	"errors"
	"fmt"
	"time"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

const defaultNoticeDays = 30

// EarlyExitPreview works out the notice shortfall and unpaid rent for a move-out on moveOut.
// While the tenant is still choosing a date the notice date is today; once notice was
// given it is the day the notice was actually given.
func (r *LeaseRepository) EarlyExitPreview(ctx context.Context, l *models.Lease, moveOut time.Time) (*models.EarlyExit, error) {
	noticeDate := models.TodayIST()
	if l.Status == "notice_given" || l.Status == "moved_out" {
		var at time.Time
		err := r.db.QueryRow(ctx, `
			SELECT created_at FROM lease_events
			WHERE lease_id = $1 AND event = 'notice_given'
			ORDER BY created_at DESC LIMIT 1`, l.ID).Scan(&at)
		if err == nil {
			noticeDate = models.DateIST(at)
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	required := defaultNoticeDays
	var days *int
	if err := r.db.QueryRow(ctx, `SELECT notice_period_days FROM agreements WHERE id = $1`, l.AgreementID).Scan(&days); err == nil {
		if days != nil && *days > 0 {
			required = *days
		}
	}

	end := models.ParseDate(l.EndDate)
	early := moveOut.Before(end)
	given := int(moveOut.Sub(noticeDate).Hours() / 24)
	if given < 0 {
		given = 0
	}

	out := &models.EarlyExit{
		Early:              early,
		EndDate:            l.EndDate,
		MoveOutDate:        moveOut.Format(models.DateLayout),
		NoticeDate:         noticeDate.Format(models.DateLayout),
		NoticeRequiredDays: required,
		NoticeGivenDays:    given,
		DepositAmount:      l.SecurityDeposit,
		Items:              []models.EarlyExitItem{},
	}

	// Unpaid rent (with late fees) for months that fall on or before the move-out date.
	payments, err := r.ListPayments(ctx, l.ID)
	if err != nil {
		return nil, err
	}
	for _, p := range payments {
		if p.DisplayStatus != "pending" && p.DisplayStatus != "overdue" {
			continue // paid, or the tenant says paid and the owner is yet to confirm
		}
		if models.ParseDate(p.DueDate).After(moveOut) {
			continue
		}
		out.UnpaidRent += p.Total
		out.UnpaidMonths++
	}
	out.UnpaidRent = round2(out.UnpaidRent)
	if out.UnpaidRent > 0 {
		out.Items = append(out.Items, models.EarlyExitItem{
			Category: "unpaid_rent",
			Reason:   fmt.Sprintf("Unpaid rent till move-out (%d month%s, incl. late fees)", out.UnpaidMonths, plural(out.UnpaidMonths)),
			Amount:   out.UnpaidRent,
		})
	}

	// Leaving before the lease end without giving the full notice: rent for the missing days.
	if early && given < required {
		out.ShortfallDays = required - given
		out.ShortfallAmount = round2(l.MonthlyRent / 30 * float64(out.ShortfallDays))
		if out.ShortfallAmount > 0 {
			out.Items = append(out.Items, models.EarlyExitItem{
				Category: "other",
				Reason: fmt.Sprintf("Notice period shortfall (%d day%s short of the %d-day notice)",
					out.ShortfallDays, plural(out.ShortfallDays), required),
				Amount: out.ShortfallAmount,
			})
		}
	}

	for _, it := range out.Items {
		out.TotalDeduction += it.Amount
	}
	out.TotalDeduction = round2(out.TotalDeduction)
	out.EstimatedRefund = round2(maxFloat(0, out.DepositAmount-out.TotalDeduction))
	return out, nil
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

func maxFloat(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}