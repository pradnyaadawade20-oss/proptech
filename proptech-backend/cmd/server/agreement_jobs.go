package main

import (
	"context"
	"log"
	"time"

	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"
)

// startAgreementJobs expires agreements that sat idle past their deadline
// (models.AgreementExpiryDays after the last step) and tells both parties.
// The expiry is claimed in the database, so several server instances running
// this never notify twice. Sign / status changes also refuse a past-deadline
// agreement on their own, so the hourly cadence is not a loophole.
func startAgreementJobs(ctx context.Context, repo *repository.AgreementRepository) {
	run := func() {
		expired, err := repo.ExpireStale(ctx)
		if err != nil {
			log.Println("agreement jobs: expire:", err)
			return
		}
		for _, a := range expired {
			route := "/agreement/" + a.ID + "/status"
			body := "The agreement for " + a.PropertyTitle + " expired because it was not completed in time. You can request a new one."
			notify.SendRoute(a.OwnerID, "agreement", "Agreement expired", body, route)
			notify.SendRoute(a.TenantID, "agreement", "Agreement expired", body, route)
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