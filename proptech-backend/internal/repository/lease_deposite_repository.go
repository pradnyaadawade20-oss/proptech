package repository

import (
	"context"
	"errors"
	"math"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

func round2(v float64) float64 { return math.Round(v*100) / 100 }

const depositSelect = `
	SELECT id, lease_id, amount, status, COALESCE(payment_method, ''), COALESCE(reference, ''),
	       submitted_at, received_at, total_deductions, refund_amount, tenant_owes,
	       COALESCE(tenant_note, ''), COALESCE(admin_note, ''),
	       COALESCE(refund_method, ''), COALESCE(refund_reference, ''),
	       settlement_at, responded_at, refunded_at
	FROM lease_deposits
`

// GetDeposit returns the deposit with deductions (+ their damage photos).
// Returns ErrLeaseNotFound when the lease has no deposit (deposit = 0).
func (r *LeaseRepository) GetDeposit(ctx context.Context, leaseID string) (*models.Deposit, error) {
	var d models.Deposit
	err := r.db.QueryRow(ctx, depositSelect+` WHERE lease_id = $1`, leaseID).Scan(
		&d.ID, &d.LeaseID, &d.Amount, &d.Status, &d.PaymentMethod, &d.Reference,
		&d.SubmittedAt, &d.ReceivedAt, &d.TotalDeductions, &d.RefundAmount, &d.TenantOwes,
		&d.TenantNote, &d.AdminNote, &d.RefundMethod, &d.RefundReference,
		&d.SettlementAt, &d.RespondedAt, &d.RefundedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, deposit_id, category, reason, amount, created_at
		FROM deposit_deductions WHERE deposit_id = $1 ORDER BY created_at`, d.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	d.Deductions = []models.Deduction{}
	total := 0.0
	for rows.Next() {
		var x models.Deduction
		if err := rows.Scan(&x.ID, &x.DepositID, &x.Category, &x.Reason, &x.Amount, &x.CreatedAt); err != nil {
			return nil, err
		}
		x.Photos = []models.LeasePhoto{}
		total += x.Amount
		d.Deductions = append(d.Deductions, x)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()

	photos, err := r.ListPhotos(ctx, leaseID, "damage")
	if err != nil {
		return nil, err
	}
	for _, ph := range photos {
		if ph.DeductionID == nil {
			continue
		}
		for i := range d.Deductions {
			if d.Deductions[i].ID == *ph.DeductionID {
				d.Deductions[i].Photos = append(d.Deductions[i].Photos, ph)
			}
		}
	}

	if d.Status == "inspection" {
		d.PreviewRefund = round2(math.Max(0, d.Amount-total))
	}
	return &d, nil
}

// SubmitDeposit: tenant says "deposit paid".
func (r *LeaseRepository) SubmitDeposit(ctx context.Context, leaseID, method, reference string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits
		SET status = 'submitted', payment_method = $2, reference = $3, submitted_at = now(), updated_at = now()
		WHERE lease_id = $1 AND status = 'pending'`, leaseID, method, reference)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the deposit is not waiting for payment")
	}
	return nil
}

// ConfirmDeposit: owner confirms the deposit arrived -> Deposit Held.
// Owner may also record it directly (cash) when it is still pending.
func (r *LeaseRepository) ConfirmDeposit(ctx context.Context, leaseID, method, reference string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits
		SET status = 'held', received_at = now(),
		    payment_method = CASE WHEN $2::text <> '' THEN $2::text ELSE payment_method END,
		    reference = CASE WHEN $3::text <> '' THEN $3::text ELSE reference END,
		    updated_at = now()
		WHERE lease_id = $1 AND status IN ('pending', 'submitted')`, leaseID, method, reference)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the deposit is already received")
	}
	return nil
}

// RejectDeposit: owner did not receive it -> back to pending.
func (r *LeaseRepository) RejectDeposit(ctx context.Context, leaseID string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits
		SET status = 'pending', payment_method = NULL, reference = NULL, submitted_at = NULL, updated_at = now()
		WHERE lease_id = $1 AND status = 'submitted'`, leaseID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("only a submitted deposit can be rejected")
	}
	return nil
}

// StartInspection: after move-out the owner inspects the flat.
func (r *LeaseRepository) StartInspection(ctx context.Context, l *models.Lease) error {
	if l.Status != "moved_out" {
		return badState("confirm the tenant's move-out before starting the inspection")
	}
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits SET status = 'inspection', updated_at = now()
		WHERE lease_id = $1 AND status = 'held'`, l.ID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the deposit must be in 'held' state to start the inspection")
	}
	return nil
}

// AddDeduction adds one deduction while the deposit is in inspection.
func (r *LeaseRepository) AddDeduction(ctx context.Context, leaseID, ownerID, category, reason string, amount float64) (string, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO deposit_deductions (deposit_id, category, reason, amount, created_by)
		SELECT d.id, $2, $3, $4, $5 FROM lease_deposits d
		WHERE d.lease_id = $1 AND d.status = 'inspection'
		RETURNING id`, leaseID, category, reason, round2(amount), ownerID).Scan(&id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", badState("deductions can only be added during the inspection")
		}
		return "", err
	}
	return id, nil
}

func (r *LeaseRepository) DeleteDeduction(ctx context.Context, leaseID, deductionID string) error {
	tag, err := r.db.Exec(ctx, `
		DELETE FROM deposit_deductions x
		USING lease_deposits d
		WHERE x.id = $2 AND x.deposit_id = d.id AND d.lease_id = $1 AND d.status = 'inspection'`,
		leaseID, deductionID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("this deduction cannot be removed now")
	}
	return nil
}

// SubmitSettlement locks the deductions and shows the final refund to the tenant.
func (r *LeaseRepository) SubmitSettlement(ctx context.Context, leaseID string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits d
		SET status = 'settlement', settlement_at = now(), updated_at = now(),
		    total_deductions = COALESCE((SELECT SUM(x.amount) FROM deposit_deductions x WHERE x.deposit_id = d.id), 0),
		    refund_amount = GREATEST(0, d.amount - COALESCE((SELECT SUM(x.amount) FROM deposit_deductions x WHERE x.deposit_id = d.id), 0)),
		    tenant_owes = GREATEST(0, COALESCE((SELECT SUM(x.amount) FROM deposit_deductions x WHERE x.deposit_id = d.id), 0) - d.amount)
		WHERE d.lease_id = $1 AND d.status = 'inspection'`, leaseID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the deposit is not in inspection")
	}
	return nil
}

// TenantRespond: accept -> refund_due (or refunded when nothing to refund),
// dispute -> disputed (admin decides).
func (r *LeaseRepository) TenantRespond(ctx context.Context, leaseID string, accept bool, note string) error {
	var q string
	if accept {
		q = `
			UPDATE lease_deposits
			SET status = CASE WHEN refund_amount > 0 THEN 'refund_due' ELSE 'refunded' END,
			    refunded_at = CASE WHEN refund_amount > 0 THEN NULL ELSE now() END,
			    responded_at = now(), tenant_note = NULLIF($2::text, ''), updated_at = now()
			WHERE lease_id = $1 AND status = 'settlement'`
	} else {
		q = `
			UPDATE lease_deposits
			SET status = 'disputed', responded_at = now(), tenant_note = NULLIF($2::text, ''), updated_at = now()
			WHERE lease_id = $1 AND status = 'settlement'`
	}
	tag, err := r.db.Exec(ctx, q, leaseID, note)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("there is no settlement waiting for your response")
	}
	return nil
}

// MarkRefunded: owner paid the refund back.
func (r *LeaseRepository) MarkRefunded(ctx context.Context, leaseID, method, reference string) error {
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits
		SET status = 'refunded', refund_method = $2, refund_reference = $3, refunded_at = now(), updated_at = now()
		WHERE lease_id = $1 AND status = 'refund_due'`, leaseID, method, reference)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("there is no refund due on this deposit")
	}
	return nil
}

// AdminResolve settles a disputed deposit with the admin's final refund amount.
func (r *LeaseRepository) AdminResolve(ctx context.Context, leaseID string, refund float64, note string) error {
	if refund < 0 {
		return badState("refund cannot be negative")
	}
	tag, err := r.db.Exec(ctx, `
		UPDATE lease_deposits
		SET refund_amount = LEAST($2::numeric, amount),
		    status = CASE WHEN LEAST($2::numeric, amount) > 0 THEN 'refund_due' ELSE 'refunded' END,
		    refunded_at = CASE WHEN LEAST($2::numeric, amount) > 0 THEN NULL ELSE now() END,
		    admin_note = $3, updated_at = now()
		WHERE lease_id = $1 AND status = 'disputed'`, leaseID, round2(refund), note)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("this deposit is not under dispute")
	}
	return nil
}