package repository

import (
	"context"
	"time"

	"proptech-backend/internal/models"
)

// RentReminder is one rent notification that must be sent now.
type RentReminder struct {
	LeaseID       string
	PaymentID     string
	TenantID      string
	OwnerID       string
	PropertyTitle string
	DueDate       time.Time
	Amount        float64
	DaysLeft      int  // negative = days overdue
	NotifyOwner   bool // true on the first overdue alert
}

// RenewalPrompt is one "your lease is ending" notification.
type RenewalPrompt struct {
	LeaseID       string
	TenantID      string
	OwnerID       string
	PropertyTitle string
	EndDate       time.Time
	DaysLeft      int
	Expired       bool
}

// EnsureLeasesForCompletedAgreements creates leases for completed rent
// agreements that don't have one yet (covers old agreements and any failed
// hook). Returns the leases created in this run.
func (r *LeaseRepository) EnsureLeasesForCompletedAgreements(ctx context.Context) ([]models.Lease, error) {
	rows, err := r.db.Query(ctx, `
		SELECT a.id FROM agreements a
		WHERE a.status = 'completed'
		  AND a.monthly_rent IS NOT NULL AND a.monthly_rent > 0 AND a.start_date IS NOT NULL
		  AND NOT EXISTS (SELECT 1 FROM leases l WHERE l.agreement_id = a.id)
		LIMIT 50`)
	if err != nil {
		return nil, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	created := []models.Lease{}
	for _, id := range ids {
		l, isNew, err := r.CreateFromAgreement(ctx, id)
		if err != nil {
			continue // one bad agreement must not block the others
		}
		if isNew {
			created = append(created, *l)
		}
	}
	return created, nil
}

func (r *LeaseRepository) claimReminders(ctx context.Context, q string) ([]RentReminder, error) {
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []RentReminder{}
	for rows.Next() {
		var x RentReminder
		if err := rows.Scan(&x.LeaseID, &x.PaymentID, &x.TenantID, &x.OwnerID, &x.PropertyTitle,
			&x.DueDate, &x.Amount, &x.DaysLeft); err != nil {
			return nil, err
		}
		out = append(out, x)
	}
	return out, rows.Err()
}

// ClaimRentReminders marks reminders as sent (so they are never sent twice,
// even with several server instances) and returns what to notify:
//
//	3 days before due, on the due date, first day overdue (tenant + owner),
//	and every 3 days while still overdue (tenant only).
func (r *LeaseRepository) ClaimRentReminders(ctx context.Context) ([]RentReminder, error) {
	const returning = `
		RETURNING rp.lease_id, rp.id, l.tenant_id, l.owner_id,
		          (SELECT title FROM properties WHERE id = l.property_id),
		          rp.due_date, rp.amount, (rp.due_date - ` + sqlToday + `)`

	var all []RentReminder

	// 1) due in 1..3 days
	a, err := r.claimReminders(ctx, `
		UPDATE rent_payments rp SET remind_3d_at = now()
		FROM leases l
		WHERE l.id = rp.lease_id AND l.status IN ('active', 'notice_given')
		  AND rp.status = 'pending' AND rp.remind_3d_at IS NULL
		  AND rp.due_date - `+sqlToday+` BETWEEN 1 AND 3`+returning)
	if err != nil {
		return nil, err
	}
	all = append(all, a...)

	// 2) due today
	b, err := r.claimReminders(ctx, `
		UPDATE rent_payments rp SET remind_due_at = now()
		FROM leases l
		WHERE l.id = rp.lease_id AND l.status IN ('active', 'notice_given')
		  AND rp.status = 'pending' AND rp.remind_due_at IS NULL
		  AND rp.due_date = `+sqlToday+returning)
	if err != nil {
		return nil, err
	}
	all = append(all, b...)

	// 3) first overdue alert -> tenant and owner
	c, err := r.claimReminders(ctx, `
		UPDATE rent_payments rp SET remind_overdue_at = now()
		FROM leases l
		WHERE l.id = rp.lease_id AND l.status IN ('active', 'notice_given')
		  AND rp.status = 'pending' AND rp.remind_overdue_at IS NULL
		  AND rp.due_date < `+sqlToday+returning)
	if err != nil {
		return nil, err
	}
	for i := range c {
		c[i].NotifyOwner = true
	}
	all = append(all, c...)

	// 4) repeat overdue alert every 3 days (max ~30 days after due) -> tenant only
	d, err := r.claimReminders(ctx, `
		UPDATE rent_payments rp SET remind_overdue_at = now()
		FROM leases l
		WHERE l.id = rp.lease_id AND l.status IN ('active', 'notice_given')
		  AND rp.status = 'pending' AND rp.remind_overdue_at IS NOT NULL
		  AND rp.remind_overdue_at < now() - interval '3 days'
		  AND rp.due_date >= `+sqlToday+` - 30
		  AND rp.due_date < `+sqlToday+returning)
	if err != nil {
		return nil, err
	}
	all = append(all, d...)
	return all, nil
}

func (r *LeaseRepository) claimPrompts(ctx context.Context, q string, args ...any) ([]RenewalPrompt, error) {
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []RenewalPrompt{}
	for rows.Next() {
		var x RenewalPrompt
		if err := rows.Scan(&x.LeaseID, &x.TenantID, &x.OwnerID, &x.PropertyTitle, &x.EndDate, &x.DaysLeft); err != nil {
			return nil, err
		}
		x.Expired = x.DaysLeft < 0
		out = append(out, x)
	}
	return out, rows.Err()
}

// ClaimRenewalPrompts finds leases whose end date is near and the tenant has
// not decided yet. Stages: 1 = 60 days left, 2 = 30 days, 3 = 7 days, 4 = ended.
// Stages are claimed from the nearest to the farthest so a lease first seen
// at 20 days left gets ONE notification, not three.
func (r *LeaseRepository) ClaimRenewalPrompts(ctx context.Context) ([]RenewalPrompt, error) {
	const returning = `
		RETURNING l.id, l.tenant_id, l.owner_id,
		          (SELECT title FROM properties WHERE id = l.property_id),
		          l.end_date, (l.end_date - ` + sqlToday + `)`

	var all []RenewalPrompt

	// stage 4: lease already ended and still no decision
	e, err := r.claimPrompts(ctx, `
		UPDATE leases l SET renewal_prompt_stage = 4, updated_at = now()
		WHERE l.status = 'active' AND l.renewal_status IN ('none', 'renew_declined')
		  AND l.renewal_prompt_stage < 4 AND l.end_date < `+sqlToday+returning)
	if err != nil {
		return nil, err
	}
	all = append(all, e...)

	for _, st := range []struct{ stage, days int }{{3, 7}, {2, 30}, {1, 60}} {
		p, err := r.claimPrompts(ctx, `
			UPDATE leases l SET renewal_prompt_stage = $1, updated_at = now()
			WHERE l.status = 'active' AND l.renewal_status = 'none'
			  AND l.renewal_prompt_stage < $1
			  AND l.end_date >= `+sqlToday+`
			  AND l.end_date - `+sqlToday+` <= $2`+returning, st.stage, st.days)
		if err != nil {
			return nil, err
		}
		all = append(all, p...)
	}
	return all, nil
}