package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

var errUTRUsed = &StateError{Msg: "this UTR number was already used for another payment"}

// ---- owner UPI id ----

func (r *LeaseRepository) GetOwnerUPI(ctx context.Context, ownerID string) (string, error) {
	var s *string
	if err := r.db.QueryRow(ctx, `SELECT upi_id FROM users WHERE id = $1`, ownerID).Scan(&s); err != nil {
		return "", err
	}
	if s == nil {
		return "", nil
	}
	return *s, nil
}

func (r *LeaseRepository) SetOwnerUPI(ctx context.Context, ownerID, upi string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET upi_id = $2 WHERE id = $1`, ownerID, upi)
	return err
}

// ---- submit payment with UTR + screenshot ----

// utrInUse: a UTR may belong to ONE live payment only. A rejected payment goes back
// to pending, so its UTR becomes free again (tenant can fix a typo).
func utrInUse(ctx context.Context, tx pgx.Tx, utr string) (bool, error) {
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, "utr:"+utr); err != nil {
		return false, err
	}
	var used bool
	err := tx.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM rent_payments  WHERE reference = $1 AND status IN ('submitted', 'paid'))
		    OR EXISTS (SELECT 1 FROM lease_deposits WHERE reference = $1 AND status <> 'pending')`, utr).Scan(&used)
	return used, err
}

func saveProof(ctx context.Context, tx pgx.Tx, kind, targetID, leaseID, uploaderID, ctype string, data []byte) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO payment_proofs (kind, target_id, lease_id, uploader_id, content_type, data)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (kind, target_id) DO UPDATE SET
			uploader_id = EXCLUDED.uploader_id, content_type = EXCLUDED.content_type,
			data = EXCLUDED.data, created_at = now()`,
		kind, targetID, leaseID, uploaderID, ctype, data)
	return err
}

// SubmitRentUPI: tenant paid by UPI -> rent becomes "submitted" (late fee frozen as of today).
func (r *LeaseRepository) SubmitRentUPI(ctx context.Context, p *models.RentPayment, uploaderID, utr, ctype string, data []byte) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	used, err := utrInUse(ctx, tx, utr)
	if err != nil {
		return err
	}
	if used {
		return errUTRUsed
	}
	tag, err := tx.Exec(ctx, `
		UPDATE rent_payments
		SET status = 'submitted', payment_method = 'upi', reference = $2, submitted_at = now(),
		    late_days = $3, late_fee = $4, reject_reason = NULL, confirm_reminded_at = NULL
		WHERE id = $1 AND status = 'pending'`, p.ID, utr, p.LateDays, p.LateFee)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("this rent is already submitted or paid")
	}
	if err := saveProof(ctx, tx, "rent", p.ID, p.LeaseID, uploaderID, ctype, data); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *LeaseRepository) SubmitDepositUPI(ctx context.Context, leaseID, uploaderID, utr, ctype string, data []byte) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	used, err := utrInUse(ctx, tx, utr)
	if err != nil {
		return err
	}
	if used {
		return errUTRUsed
	}
	tag, err := tx.Exec(ctx, `
		UPDATE lease_deposits
		SET status = 'submitted', payment_method = 'upi', reference = $2, submitted_at = now(),
		    confirm_reminded_at = NULL, updated_at = now()
		WHERE lease_id = $1 AND status = 'pending'`, leaseID, utr)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the deposit is not waiting for payment")
	}
	if err := saveProof(ctx, tx, "deposit", leaseID, leaseID, uploaderID, ctype, data); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// GetProof returns the screenshot bytes. kind = rent|deposit, targetID = rent payment id / lease id.
func (r *LeaseRepository) GetProof(ctx context.Context, kind, targetID string) ([]byte, string, error) {
	var data []byte
	var ct string
	err := r.db.QueryRow(ctx, `SELECT data, content_type FROM payment_proofs WHERE kind = $1 AND target_id = $2`,
		kind, targetID).Scan(&data, &ct)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", ErrLeaseNotFound
		}
		return nil, "", err
	}
	return data, ct, nil
}

// ---- 24h "please confirm" reminder to the owner ----

type ConfirmReminder struct {
	LeaseID       string
	OwnerID       string
	TenantName    string
	PropertyTitle string
	What          string // "rent" | "deposit"
	Amount        float64
}

func (r *LeaseRepository) claimConfirm(ctx context.Context, q string) ([]ConfirmReminder, error) {
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ConfirmReminder
	for rows.Next() {
		var c ConfirmReminder
		if err := rows.Scan(&c.LeaseID, &c.OwnerID, &c.TenantName, &c.PropertyTitle, &c.What, &c.Amount); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ClaimConfirmReminders marks and returns UPI payments the owner has not confirmed for 24h.
// Marked in the DB first, so every payment is reminded once even with several servers.
func (r *LeaseRepository) ClaimConfirmReminders(ctx context.Context) ([]ConfirmReminder, error) {
	rent, err := r.claimConfirm(ctx, `
		UPDATE rent_payments rp SET confirm_reminded_at = now()
		FROM leases l
		JOIN users tu ON tu.id = l.tenant_id
		JOIN properties p ON p.id = l.property_id
		WHERE l.id = rp.lease_id AND rp.status = 'submitted' AND rp.payment_method = 'upi'
		  AND rp.confirm_reminded_at IS NULL AND rp.submitted_at < now() - interval '24 hours'
		RETURNING rp.lease_id, l.owner_id, tu.name, p.title, 'rent', (rp.amount + rp.late_fee)`)
	if err != nil {
		return nil, err
	}
	dep, err := r.claimConfirm(ctx, `
		UPDATE lease_deposits d SET confirm_reminded_at = now()
		FROM leases l
		JOIN users tu ON tu.id = l.tenant_id
		JOIN properties p ON p.id = l.property_id
		WHERE l.id = d.lease_id AND d.status = 'submitted' AND d.payment_method = 'upi'
		  AND d.confirm_reminded_at IS NULL AND d.submitted_at < now() - interval '24 hours'
		RETURNING d.lease_id, l.owner_id, tu.name, p.title, 'deposit', d.amount`)
	if err != nil {
		return rent, err
	}
	return append(rent, dep...), nil
}