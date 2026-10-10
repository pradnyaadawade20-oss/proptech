package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"
)

// startLeaseJobs creates missing leases and sends rent / renewal reminders.
// Reminders are claimed in the database first, so running several server
// instances never sends the same reminder twice.
func startLeaseJobs(ctx context.Context, repo *repository.LeaseRepository) {
	run := func() {
		if _, err := repo.EnsureLeasesForCompletedAgreements(ctx); err != nil {
			log.Println("lease jobs: ensure leases:", err)
		}

		reminders, err := repo.ClaimRentReminders(ctx)
		if err != nil {
			log.Println("lease jobs: rent reminders:", err)
		}
		for _, r := range reminders {
			route := "/lease/" + r.LeaseID
			var title, body string
			switch {
			case r.DaysLeft > 0:
				title, body = "Rent due soon", fmt.Sprintf("Rent of ₹%.0f for %s is due in %d day(s).", r.Amount, r.PropertyTitle, r.DaysLeft)
			case r.DaysLeft == 0:
				title, body = "Rent due today", fmt.Sprintf("Rent of ₹%.0f for %s is due today.", r.Amount, r.PropertyTitle)
			default:
				title, body = "Rent overdue", fmt.Sprintf("Rent of ₹%.0f for %s is %d day(s) overdue.", r.Amount, r.PropertyTitle, -r.DaysLeft)
			}
			notify.SendRoute(r.TenantID, "rent_reminder", title, body, route)
			if r.NotifyOwner {
				notify.SendRoute(r.OwnerID, "rent_overdue", "Tenant rent overdue", body, route)
			}
		}

		// Owner has not confirmed a UPI payment for 24h -> remind (once per payment).
		confirms, err := repo.ClaimConfirmReminders(ctx)
		if err != nil {
			log.Println("lease jobs: confirm reminders:", err)
		}
		for _, cr := range confirms {
			what := "rent"
			if cr.What == "deposit" {
				what = "security deposit"
			}
			notify.SendRoute(cr.OwnerID, "payment_confirm", "Confirm payment received",
				fmt.Sprintf("%s paid %s of ₹%.0f for %s by UPI over 24 hours ago. Please check your bank and confirm or reject it.",
					cr.TenantName, what, cr.Amount, cr.PropertyTitle),
				"/lease/"+cr.LeaseID)
		}

		prompts, err := repo.ClaimRenewalPrompts(ctx)
		if err != nil {
			log.Println("lease jobs: renewal prompts:", err)
		}
		for _, p := range prompts {
			route := "/lease/" + p.LeaseID
			if p.Expired {
				notify.SendRoute(p.TenantID, "lease_ended", "Lease ended", "Your lease for "+p.PropertyTitle+" has ended.", route)
				notify.SendRoute(p.OwnerID, "lease_ended", "Lease ended", "The lease for "+p.PropertyTitle+" has ended.", route)
				continue
			}
			body := fmt.Sprintf("Your lease for %s ends in %d day(s). Do you want to renew?", p.PropertyTitle, p.DaysLeft)
			notify.SendRoute(p.TenantID, "lease_renewal", "Lease ending soon", body, route)
		}
	}

	go func() {
		run()
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				run()
			}
		}
	}()
}