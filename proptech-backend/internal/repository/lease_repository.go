package repository

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"time"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// sqlToday is today's date in India (the DB runs in UTC).
const sqlToday = `(now() AT TIME ZONE 'Asia/Kolkata')::date`

var ErrLeaseNotFound = errors.New("not found")

// StateError is a "you can't do that right now" error. Handlers answer it with 409.
type StateError struct{ Msg string }

func (e *StateError) Error() string { return e.Msg }

func badState(msg string) error { return &StateError{Msg: msg} }

type LeaseRepository struct {
	db *pgxpool.Pool
}

func NewLeaseRepository(db *pgxpool.Pool) *LeaseRepository {
	return &LeaseRepository{db: db}
}

// ---------------------------------------------------------------------------
// Lease
// ---------------------------------------------------------------------------

const leaseSelect = `
	SELECT l.id, l.agreement_id, l.property_id, p.title, COALESCE(p.image_url, ''),
	       l.owner_id, ou.name, l.tenant_id, tu.name,
	       l.monthly_rent, l.security_deposit, l.start_date, l.end_date, l.grace_days, l.late_fee_per_day,
	       l.status, l.renewal_status, l.move_out_date, l.moved_out_at, l.move_in_confirmed_at,
	       l.renewed_agreement_id, l.created_at,
	       (SELECT COUNT(*) FROM rent_payments rp
	         WHERE rp.lease_id = l.id AND rp.status = 'pending' AND rp.due_date < ` + sqlToday + `),
	       (SELECT MIN(rp.due_date) FROM rent_payments rp
	         WHERE rp.lease_id = l.id AND rp.status IN ('pending', 'submitted')),
	       COALESCE((SELECT d.status FROM lease_deposits d WHERE d.lease_id = l.id), '')
	FROM leases l
	JOIN properties p ON p.id = l.property_id
	JOIN users ou ON ou.id = l.owner_id
	JOIN users tu ON tu.id = l.tenant_id
`

func scanLease(row interface{ Scan(dest ...any) error }) (*models.Lease, error) {
	var l models.Lease
	var start, end time.Time
	var moveOut, nextDue *time.Time
	err := row.Scan(
		&l.ID, &l.AgreementID, &l.PropertyID, &l.PropertyTitle, &l.PropertyImageURL,
		&l.OwnerID, &l.OwnerName, &l.TenantID, &l.TenantName,
		&l.MonthlyRent, &l.SecurityDeposit, &start, &end, &l.GraceDays, &l.LateFeePerDay,
		&l.Status, &l.RenewalStatus, &moveOut, &l.MovedOutAt, &l.MoveInConfirmedAt,
		&l.RenewedAgreementID, &l.CreatedAt,
		&l.OverdueCount, &nextDue, &l.DepositStatus,
	)
	if err != nil {
		return nil, err
	}
	l.StartDate = start.Format(models.DateLayout)
	l.EndDate = end.Format(models.DateLayout)
	if moveOut != nil {
		s := moveOut.Format(models.DateLayout)
		l.MoveOutDate = &s
	}
	if nextDue != nil {
		s := nextDue.Format(models.DateLayout)
		l.NextDueDate = &s
	}
	l.DaysToExpiry = int(end.Sub(models.TodayIST()).Hours() / 24)
	return &l, nil
}

func (r *LeaseRepository) GetLease(ctx context.Context, id string) (*models.Lease, error) {
	l, err := scanLease(r.db.QueryRow(ctx, leaseSelect+` WHERE l.id = $1`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	return l, nil
}

func (r *LeaseRepository) ListForUser(ctx context.Context, userID string) ([]models.Lease, error) {
	rows, err := r.db.Query(ctx, leaseSelect+`
		WHERE l.owner_id = $1 OR l.tenant_id = $1
		ORDER BY l.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Lease{}
	for rows.Next() {
		l, err := scanLease(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *l)
	}
	return out, rows.Err()
}

// LogEvent writes one line to the audit trail. Never fails the caller.
func (r *LeaseRepository) LogEvent(ctx context.Context, leaseID, actorID, event, detail string) {
	_, err := r.db.Exec(ctx,
		`INSERT INTO lease_events (lease_id, actor_id, event, detail) VALUES ($1, $2, $3, $4)`,
		leaseID, actorID, event, detail)
	if err != nil {
		log.Printf("lease event log failed (%s): %v", event, err)
	}
}

func (r *LeaseRepository) ListEvents(ctx context.Context, leaseID string) ([]models.LeaseEvent, error) {
	rows, err := r.db.Query(ctx, `
		SELECT e.id, COALESCE(u.name, CASE e.actor_id WHEN 'system' THEN 'System' WHEN 'admin' THEN 'Admin' ELSE '' END),
		       e.event, e.detail, e.created_at
		FROM lease_events e
		LEFT JOIN users u ON u.id::text = e.actor_id
		WHERE e.lease_id = $1
		ORDER BY e.created_at DESC
		LIMIT 200`, leaseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.LeaseEvent{}
	for rows.Next() {
		var e models.LeaseEvent
		if err := rows.Scan(&e.ID, &e.ActorName, &e.Event, &e.Detail, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// CreateFromAgreement turns a COMPLETED agreement into a lease + rent schedule
// + deposit record. Safe to call many times: the second call just returns the
// existing lease (created == false).
func (r *LeaseRepository) CreateFromAgreement(ctx context.Context, agreementID string) (*models.Lease, bool, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, false, err
	}
	defer tx.Rollback(ctx)

	var propertyID, ownerID, tenantID, status string
	var rent, deposit *float64
	var start *time.Time
	var months *int
	var renewalOf *string
	err = tx.QueryRow(ctx, `
		SELECT property_id, owner_id, tenant_id, status, monthly_rent, security_deposit,
		       start_date, duration_months, renewal_of_lease_id
		FROM agreements WHERE id = $1 FOR UPDATE`, agreementID).
		Scan(&propertyID, &ownerID, &tenantID, &status, &rent, &deposit, &start, &months, &renewalOf)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, false, ErrLeaseNotFound
		}
		return nil, false, err
	}
	if status != "completed" {
		return nil, false, badState("the agreement is not completed yet")
	}

	var existing string
	err = tx.QueryRow(ctx, `SELECT id FROM leases WHERE agreement_id = $1`, agreementID).Scan(&existing)
	if err == nil {
		l, gerr := r.GetLease(ctx, existing)
		return l, false, gerr
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, false, err
	}

	if rent == nil || *rent <= 0 || start == nil {
		return nil, false, badState("this agreement has no monthly rent / start date, so there is no rent schedule")
	}
	n := 11
	if months != nil && *months > 0 {
		n = *months
	}
	if n > 60 {
		n = 60
	}
	end := models.AddMonthsClamped(*start, n).AddDate(0, 0, -1)
	dep := 0.0
	if deposit != nil && *deposit > 0 {
		dep = *deposit
	}
	perDay := math.Round(*rent * models.LateFeePerDayPct)

	var leaseID string
	err = tx.QueryRow(ctx, `
		INSERT INTO leases (agreement_id, property_id, owner_id, tenant_id, monthly_rent, security_deposit,
		                    start_date, end_date, grace_days, late_fee_per_day, previous_lease_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id`,
		agreementID, propertyID, ownerID, tenantID, *rent, dep, *start, end,
		models.DefaultGraceDays, perDay, renewalOf).Scan(&leaseID)
	if err != nil {
		return nil, false, err
	}

	for i := 1; i <= n; i++ {
		due := models.AddMonthsClamped(*start, i-1)
		if _, err := tx.Exec(ctx, `
			INSERT INTO rent_payments (lease_id, period_no, due_date, amount)
			VALUES ($1, $2, $3, $4)`, leaseID, i, due, *rent); err != nil {
			return nil, false, err
		}
	}

	if dep > 0 {
		carried := false
		if renewalOf != nil {
			tag, err := tx.Exec(ctx, `
				UPDATE lease_deposits SET status = 'carried_forward', updated_at = now()
				WHERE lease_id = $1 AND status = 'held'`, *renewalOf)
			if err != nil {
				return nil, false, err
			}
			carried = tag.RowsAffected() > 0
		}
		if carried {
			_, err = tx.Exec(ctx, `
				INSERT INTO lease_deposits (lease_id, amount, status, payment_method, received_at)
				VALUES ($1, $2, 'held', 'carried_forward', now())`, leaseID, dep)
		} else {
			_, err = tx.Exec(ctx, `
				INSERT INTO lease_deposits (lease_id, amount, status) VALUES ($1, $2, 'pending')`, leaseID, dep)
		}
		if err != nil {
			return nil, false, err
		}
	}

	if renewalOf != nil {
		if _, err := tx.Exec(ctx, `
			UPDATE leases SET status = 'renewed', renewal_status = 'renew_accepted',
			       renewed_agreement_id = $2, updated_at = now()
			WHERE id = $1`, *renewalOf, agreementID); err != nil {
			return nil, false, err
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE properties SET listing_status = 'rented' WHERE id = $1`, propertyID); err != nil {
		return nil, false, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO lease_events (lease_id, actor_id, event, detail) VALUES ($1, 'system', 'lease_created', $2)`,
		leaseID, fmt.Sprintf("%d monthly rent entries created", n)); err != nil {
		return nil, false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, false, err
	}
	l, err := r.GetLease(ctx, leaseID)
	return l, true, err
}

// ---------------------------------------------------------------------------
// Monthly rent
// ---------------------------------------------------------------------------

const paymentSelect = `
	SELECT rp.id, rp.lease_id, rp.period_no, rp.due_date, rp.amount, rp.status, rp.late_days, rp.late_fee,
	       COALESCE(rp.payment_method, ''), COALESCE(rp.reference, ''), rp.submitted_at, rp.paid_at,
	       COALESCE(rp.receipt_no, ''), COALESCE(rp.reject_reason, ''),
	       l.grace_days, l.late_fee_per_day, l.monthly_rent
	FROM rent_payments rp
	JOIN leases l ON l.id = rp.lease_id
`

func scanPayment(row interface{ Scan(dest ...any) error }) (*models.RentPayment, error) {
	var p models.RentPayment
	var due time.Time
	var grace int
	var perDay, rent float64
	err := row.Scan(
		&p.ID, &p.LeaseID, &p.PeriodNo, &due, &p.Amount, &p.Status, &p.LateDays, &p.LateFee,
		&p.PaymentMethod, &p.Reference, &p.SubmittedAt, &p.PaidAt,
		&p.ReceiptNo, &p.RejectReason,
		&grace, &perDay, &rent,
	)
	if err != nil {
		return nil, err
	}
	p.DueDate = due.Format(models.DateLayout)
	p.Finalize(models.LateParams{GraceDays: grace, PerDay: perDay, Rent: rent}, models.TodayIST())
	return &p, nil
}

func (r *LeaseRepository) ListPayments(ctx context.Context, leaseID string) ([]models.RentPayment, error) {
	rows, err := r.db.Query(ctx, paymentSelect+` WHERE rp.lease_id = $1 ORDER BY rp.period_no`, leaseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.RentPayment{}
	for rows.Next() {
		p, err := scanPayment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

func (r *LeaseRepository) GetPayment(ctx context.Context, id string) (*models.RentPayment, error) {
	p, err := scanPayment(r.db.QueryRow(ctx, paymentSelect+` WHERE rp.id = $1`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	return p, nil
}

// SubmitPayment: tenant says "I paid" (UPI / bank / cash...). The late fee is
// frozen as of today, so the owner confirming later never adds extra fee.
func (r *LeaseRepository) SubmitPayment(ctx context.Context, id, method, reference string) (*models.RentPayment, error) {
	p, err := r.GetPayment(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.Status != "pending" {
		return nil, badState("this rent is already submitted or paid")
	}
	tag, err := r.db.Exec(ctx, `
		UPDATE rent_payments
		SET status = 'submitted', payment_method = $2, reference = $3, submitted_at = now(),
		    late_days = $4, late_fee = $5, reject_reason = NULL
		WHERE id = $1 AND status = 'pending'`, id, method, reference, p.LateDays, p.LateFee)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, badState("this rent is already submitted or paid")
	}
	return r.GetPayment(ctx, id)
}

const receiptNoSQL = `'RC-' || to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYMM') || '-' || upper(substr(id::text, 1, 6))`

// ConfirmPayment: owner confirms the money arrived -> paid + receipt number.
func (r *LeaseRepository) ConfirmPayment(ctx context.Context, id string) (*models.RentPayment, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE rent_payments
		SET status = 'paid', paid_at = now(), receipt_no = `+receiptNoSQL+`
		WHERE id = $1 AND status = 'submitted'`, id)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, badState("only a rent payment that the tenant has submitted can be confirmed")
	}
	return r.GetPayment(ctx, id)
}

// OwnerMarkPaid: owner records a payment himself (e.g. cash) -> paid.
func (r *LeaseRepository) OwnerMarkPaid(ctx context.Context, id, method, reference string) (*models.RentPayment, error) {
	p, err := r.GetPayment(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.Status == "paid" {
		return nil, badState("this rent is already paid")
	}
	tag, err := r.db.Exec(ctx, `
		UPDATE rent_payments
		SET status = 'paid', paid_at = now(),
		    submitted_at = COALESCE(submitted_at, now()),
		    payment_method = CASE WHEN $2::text <> '' THEN $2::text ELSE payment_method END,
		    reference = CASE WHEN $3::text <> '' THEN $3::text ELSE reference END,
		    late_days = $4, late_fee = $5,
		    receipt_no = `+receiptNoSQL+`
		WHERE id = $1 AND status <> 'paid'`, id, method, reference, p.LateDays, p.LateFee)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, badState("this rent is already paid")
	}
	return r.GetPayment(ctx, id)
}

// RejectPayment: owner says "I did not receive it" -> back to pending.
func (r *LeaseRepository) RejectPayment(ctx context.Context, id, reason string) (*models.RentPayment, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE rent_payments
		SET status = 'pending', payment_method = NULL, reference = NULL, submitted_at = NULL,
		    late_days = 0, late_fee = 0, reject_reason = $2
		WHERE id = $1 AND status = 'submitted'`, id, reason)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, badState("only a submitted payment can be rejected")
	}
	return r.GetPayment(ctx, id)
}

// ---------------------------------------------------------------------------
// Renewal + move-out
// ---------------------------------------------------------------------------

// RequestRenewal: tenant answers "renew?" with YES.
func (r *LeaseRepository) RequestRenewal(ctx context.Context, l *models.Lease) error {
	if l.Status != "active" {
		return badState("only an active lease can be renewed")
	}
	if l.RenewalStatus == "renew_requested" || l.RenewalStatus == "renew_accepted" {
		return badState("renewal is already in progress")
	}
	if l.DaysToExpiry > models.RenewalWindowDays {
		return badState(fmt.Sprintf("renewal opens %d days before the lease ends", models.RenewalWindowDays))
	}
	_, err := r.db.Exec(ctx, `
		UPDATE leases SET renewal_status = 'renew_requested', updated_at = now()
		WHERE id = $1 AND status = 'active'`, l.ID)
	return err
}

// RespondRenewal: owner accepts (creates the NEW agreement, already in
// draft_ready so both sides can sign it) or declines.
// Returns the new agreement id when accepted.
func (r *LeaseRepository) RespondRenewal(ctx context.Context, l *models.Lease, accept bool, newRent *float64, newMonths *int) (string, error) {
	if l.Status != "active" || l.RenewalStatus != "renew_requested" {
		return "", badState("there is no pending renewal request on this lease")
	}
	if !accept {
		_, err := r.db.Exec(ctx, `
			UPDATE leases SET renewal_status = 'renew_declined', updated_at = now() WHERE id = $1`, l.ID)
		return "", err
	}
	if newRent != nil && *newRent <= 0 {
		return "", badState("monthly rent must be more than 0")
	}
	if newMonths != nil && (*newMonths < 1 || *newMonths > 60) {
		return "", badState("duration must be between 1 and 60 months")
	}

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	var newID string
	err = tx.QueryRow(ctx, `
		INSERT INTO agreements (property_id, owner_id, tenant_id, status, monthly_rent, security_deposit,
		                        start_date, duration_months, terms, renewal_of_lease_id)
		SELECT a.property_id, a.owner_id, a.tenant_id, 'draft_ready',
		       COALESCE($2::numeric, l.monthly_rent), a.security_deposit,
		       l.end_date + 1, COALESCE($3::int, a.duration_months, 11),
		       'RENEWAL of the previous rental agreement. All earlier terms continue unless changed below.' || E'\n\n' || COALESCE(a.terms, ''),
		       l.id
		FROM leases l JOIN agreements a ON a.id = l.agreement_id
		WHERE l.id = $1
		RETURNING id`, l.ID, newRent, newMonths).Scan(&newID)
	if err != nil {
		return "", err
	}
	tag, err := tx.Exec(ctx, `
		UPDATE leases SET renewal_status = 'renew_accepted', renewed_agreement_id = $2, updated_at = now()
		WHERE id = $1 AND renewal_status = 'renew_requested'`, l.ID, newID)
	if err != nil {
		return "", err
	}
	if tag.RowsAffected() == 0 {
		return "", badState("there is no pending renewal request on this lease")
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return newID, nil
}

// GiveNotice: tenant answers "renew?" with NO (or just wants to leave) -> move-out flow.
func (r *LeaseRepository) GiveNotice(ctx context.Context, l *models.Lease, moveOut time.Time) error {
	if l.Status != "active" {
		return badState("notice can only be given on an active lease")
	}
	if l.RenewalStatus == "renew_accepted" {
		return badState("a renewal agreement is already in progress")
	}
	if moveOut.Before(models.TodayIST()) {
		return badState("move-out date cannot be in the past")
	}
	tag, err := r.db.Exec(ctx, `
		UPDATE leases SET status = 'notice_given', renewal_status = 'vacate', move_out_date = $2, updated_at = now()
		WHERE id = $1 AND status = 'active'`, l.ID, moveOut)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("notice can only be given on an active lease")
	}
	return nil
}

// CompleteMoveOut: owner confirms the tenant has left -> property becomes
// Available again and unpaid FUTURE rent entries are dropped.
func (r *LeaseRepository) CompleteMoveOut(ctx context.Context, l *models.Lease) error {
	if l.Status != "notice_given" {
		return badState("the tenant has not given notice yet")
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE leases SET status = 'moved_out', moved_out_at = now(), updated_at = now()
		WHERE id = $1 AND status = 'notice_given'`, l.ID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the tenant has not given notice yet")
	}
	if _, err := tx.Exec(ctx, `
		DELETE FROM rent_payments
		WHERE lease_id = $1 AND status = 'pending'
		  AND due_date > COALESCE((SELECT move_out_date FROM leases WHERE id = $1), `+sqlToday+`)`, l.ID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE properties SET listing_status = 'available'
		WHERE id = $1
		  AND NOT EXISTS (SELECT 1 FROM leases o
		                  WHERE o.property_id = $1 AND o.id <> $2 AND o.status IN ('active', 'notice_given'))`,
		l.PropertyID, l.ID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ConfirmMoveIn: tenant confirms the move-in photos -> they become read-only evidence.
func (r *LeaseRepository) ConfirmMoveIn(ctx context.Context, l *models.Lease) error {
	if l.Status != "active" {
		return badState("move-in can only be confirmed on an active lease")
	}
	if l.MoveInConfirmedAt != nil {
		return badState("move-in is already confirmed")
	}
	n, err := r.CountPhotos(ctx, l.ID, "move_in", nil, nil)
	if err != nil {
		return err
	}
	if n == 0 {
		return badState("upload at least one move-in photo first")
	}
	_, err = r.db.Exec(ctx, `
		UPDATE leases SET move_in_confirmed_at = now(), updated_at = now()
		WHERE id = $1 AND move_in_confirmed_at IS NULL`, l.ID)
	return err
}