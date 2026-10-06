package models

import (
	"math"
	"time"
)

const (
	DateLayout = "2006-01-02"

	DefaultGraceDays = 5
	// Late fee per day = 0.1% of monthly rent (~3% a month), capped at 10% of one month's rent.
	LateFeePerDayPct = 0.001
	LateFeeCapPct    = 0.10
	// Tenant may ask for renewal / give notice only this many days before the lease ends.
	RenewalWindowDays = 90
)

var istZone = time.FixedZone("IST", 5*3600+1800)

// TodayIST returns today's calendar date (IST) as midnight UTC, so it can be
// compared directly with DATE columns scanned by pgx.
func TodayIST() time.Time {
	n := time.Now().In(istZone)
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}

// DateIST converts a timestamp to its IST calendar date (midnight UTC).
func DateIST(t time.Time) time.Time {
	n := t.In(istZone)
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}

func ParseDate(s string) time.Time {
	t, _ := time.Parse(DateLayout, s)
	return t
}

// AddMonthsClamped adds months to t, keeping the day-of-month where possible
// (31 Jan + 1 month = 28/29 Feb). Always call it on the ORIGINAL start date
// so the day never drifts.
func AddMonthsClamped(t time.Time, months int) time.Time {
	y, m, d := t.Date()
	first := time.Date(y, m+time.Month(months), 1, 0, 0, 0, 0, time.UTC)
	last := time.Date(first.Year(), first.Month()+1, 0, 0, 0, 0, 0, time.UTC).Day()
	if d > last {
		d = last
	}
	return time.Date(first.Year(), first.Month(), d, 0, 0, 0, 0, time.UTC)
}

type LateParams struct {
	GraceDays int
	PerDay    float64
	Rent      float64
}

// CalcLate returns late days (after the grace period) and the late fee.
func CalcLate(due, asOf time.Time, p LateParams) (int, float64) {
	days := int(asOf.Sub(due).Hours()/24) - p.GraceDays
	if days <= 0 {
		return 0, 0
	}
	fee := float64(days) * p.PerDay
	maxFee := p.Rent * LateFeeCapPct
	if fee > maxFee {
		fee = maxFee
	}
	return days, math.Round(fee*100) / 100
}

type Lease struct {
	ID               string `json:"id"`
	AgreementID      string `json:"agreement_id"`
	PropertyID       string `json:"property_id"`
	PropertyTitle    string `json:"property_title"`
	PropertyImageURL string `json:"property_image_url"`
	OwnerID          string `json:"owner_id"`
	OwnerName        string `json:"owner_name"`
	TenantID         string `json:"tenant_id"`
	TenantName       string `json:"tenant_name"`

	MonthlyRent     float64 `json:"monthly_rent"`
	SecurityDeposit float64 `json:"security_deposit"`
	StartDate       string  `json:"start_date"`
	EndDate         string  `json:"end_date"`
	GraceDays       int     `json:"grace_days"`
	LateFeePerDay   float64 `json:"late_fee_per_day"`

	Status             string     `json:"status"`         // active | notice_given | moved_out | renewed
	RenewalStatus      string     `json:"renewal_status"` // none | renew_requested | renew_accepted | renew_declined | vacate
	MoveOutDate        *string    `json:"move_out_date,omitempty"`
	MovedOutAt         *time.Time `json:"moved_out_at,omitempty"`
	MoveInConfirmedAt  *time.Time `json:"move_in_confirmed_at,omitempty"`
	RenewedAgreementID *string    `json:"renewed_agreement_id,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`

	// Summary fields (computed on read).
	OverdueCount  int     `json:"overdue_count"`
	NextDueDate   *string `json:"next_due_date,omitempty"`
	DepositStatus string  `json:"deposit_status"`
	DaysToExpiry  int     `json:"days_to_expiry"`
}

func (l *Lease) RoleOf(userID string) string {
	switch userID {
	case l.OwnerID:
		return "owner"
	case l.TenantID:
		return "tenant"
	}
	return ""
}

type RentPayment struct {
	ID       string  `json:"id"`
	LeaseID  string  `json:"lease_id"`
	PeriodNo int     `json:"period_no"`
	DueDate  string  `json:"due_date"`
	Amount   float64 `json:"amount"`

	Status        string  `json:"status"`         // stored: pending | submitted | paid
	DisplayStatus string  `json:"display_status"` // pending | submitted | paid | overdue
	LateDays      int     `json:"late_days"`
	LateFee       float64 `json:"late_fee"`
	Total         float64 `json:"total"`
	PaidLate      bool    `json:"paid_late"`

	PaymentMethod string     `json:"payment_method,omitempty"`
	Reference     string     `json:"reference,omitempty"`
	SubmittedAt   *time.Time `json:"submitted_at,omitempty"`
	PaidAt        *time.Time `json:"paid_at,omitempty"`
	ReceiptNo     string     `json:"receipt_no,omitempty"`
	RejectReason  string     `json:"reject_reason,omitempty"`
}

// Finalize fills the computed fields. Pending rows get a live late fee; submitted
// and paid rows keep the late fee frozen at submission time.
func (p *RentPayment) Finalize(lp LateParams, today time.Time) {
	due := ParseDate(p.DueDate)
	switch p.Status {
	case "paid":
		p.DisplayStatus = "paid"
		p.PaidLate = p.LateDays > 0
	case "submitted":
		p.DisplayStatus = "submitted"
	default:
		p.DisplayStatus = "pending"
		if today.After(due) {
			p.DisplayStatus = "overdue"
		}
		p.LateDays, p.LateFee = CalcLate(due, today, lp)
	}
	p.Total = math.Round((p.Amount+p.LateFee)*100) / 100
}

type Deduction struct {
	ID        string       `json:"id"`
	DepositID string       `json:"deposit_id"`
	Category  string       `json:"category"` // damage | unpaid_rent | cleaning | other
	Reason    string       `json:"reason"`
	Amount    float64      `json:"amount"`
	CreatedAt time.Time    `json:"created_at"`
	Photos    []LeasePhoto `json:"photos"`
}

type Deposit struct {
	ID      string  `json:"id"`
	LeaseID string  `json:"lease_id"`
	Amount  float64 `json:"amount"`
	// pending | submitted | held | inspection | settlement | disputed | refund_due | refunded | carried_forward
	Status          string      `json:"status"`
	PaymentMethod   string      `json:"payment_method,omitempty"`
	Reference       string      `json:"reference,omitempty"`
	SubmittedAt     *time.Time  `json:"submitted_at,omitempty"`
	ReceivedAt      *time.Time  `json:"received_at,omitempty"`
	TotalDeductions float64     `json:"total_deductions"`
	RefundAmount    float64     `json:"refund_amount"`
	TenantOwes      float64     `json:"tenant_owes"`
	TenantNote      string      `json:"tenant_note,omitempty"`
	AdminNote       string      `json:"admin_note,omitempty"`
	RefundMethod    string      `json:"refund_method,omitempty"`
	RefundReference string      `json:"refund_reference,omitempty"`
	SettlementAt    *time.Time  `json:"settlement_at,omitempty"`
	RespondedAt     *time.Time  `json:"responded_at,omitempty"`
	RefundedAt      *time.Time  `json:"refunded_at,omitempty"`
	Deductions      []Deduction `json:"deductions"`
	// Live preview while the owner is still adding deductions.
	PreviewRefund float64 `json:"preview_refund"`
}

type LeasePhoto struct {
	ID           string    `json:"id"`
	LeaseID      string    `json:"lease_id"`
	UploaderID   string    `json:"uploader_id"`
	UploaderName string    `json:"uploader_name"`
	Kind         string    `json:"kind"` // move_in | move_out | damage | maintenance
	Room         string    `json:"room"`
	Caption      string    `json:"caption"`
	DeductionID  *string   `json:"deduction_id,omitempty"`
	TicketID     *string   `json:"ticket_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	URL          string    `json:"url"`
}

type TicketUpdate struct {
	ID        string    `json:"id"`
	ActorID   string    `json:"actor_id"`
	ActorName string    `json:"actor_name"`
	Status    string    `json:"status"`
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
}

type Ticket struct {
	ID            string         `json:"id"`
	LeaseID       string         `json:"lease_id"`
	PropertyID    string         `json:"property_id"`
	PropertyTitle string         `json:"property_title"`
	TenantID      string         `json:"tenant_id"`
	TenantName    string         `json:"tenant_name"`
	OwnerID       string         `json:"owner_id"`
	Title         string         `json:"title"`
	Description   string         `json:"description"`
	Category      string         `json:"category"`
	Priority      string         `json:"priority"`
	Status        string         `json:"status"` // reported | in_progress | resolved
	ResolvedAt    *time.Time     `json:"resolved_at,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	PhotoCount    int            `json:"photo_count"`
	Updates       []TicketUpdate `json:"updates,omitempty"`
	Photos        []LeasePhoto   `json:"photos,omitempty"`
}

type LeaseEvent struct {
	ID        string    `json:"id"`
	ActorName string    `json:"actor_name"`
	Event     string    `json:"event"`
	Detail    string    `json:"detail"`
	CreatedAt time.Time `json:"created_at"`
}

// ---- requests ----

type PayRentRequest struct {
	Method    string `json:"method" binding:"required,oneof=upi bank_transfer cash cheque other"`
	Reference string `json:"reference"`
}

type RejectPaymentRequest struct {
	Reason string `json:"reason" binding:"required"`
}

type RenewalRequest struct {
	Decision    string `json:"decision" binding:"required,oneof=renew vacate"`
	MoveOutDate string `json:"move_out_date"` // YYYY-MM-DD, needed when decision = vacate
}

type RenewalRespondRequest struct {
	Accept         bool     `json:"accept"`
	MonthlyRent    *float64 `json:"monthly_rent"`
	DurationMonths *int     `json:"duration_months"`
}

type MoveOutRequest struct {
	MoveOutDate string `json:"move_out_date" binding:"required"`
}

type DepositRespondRequest struct {
	Accept bool   `json:"accept"`
	Note   string `json:"note"`
}

type DepositRefundRequest struct {
	Method    string `json:"method" binding:"required,oneof=upi bank_transfer cash cheque other"`
	Reference string `json:"reference"`
}

type TicketStatusRequest struct {
	Status string `json:"status" binding:"required,oneof=in_progress resolved reopen"`
	Note   string `json:"note"`
}

type AdminResolveDepositRequest struct {
	RefundAmount float64 `json:"refund_amount"`
	Note         string  `json:"note" binding:"required"`
}