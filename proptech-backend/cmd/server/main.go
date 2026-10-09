package main

import (
	"log"
	"net/http"

	"context"

	"proptech-backend/internal/cashfree"
	"proptech-backend/internal/config"
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/kyc"
	"proptech-backend/internal/mail"
	"proptech-backend/internal/middleware"
	"proptech-backend/internal/migrate"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/push"
	"proptech-backend/internal/repository"
	"proptech-backend/internal/routes"
	"proptech-backend/migrations"

	"github.com/gin-gonic/gin"
)

func main() {
	config.LoadDotEnv()

	cfg := config.LoadConfig()
	if cfg.AppEnv == "production" && (cfg.DevSkipOTP || cfg.DevLogOTP) {
		log.Fatal("DEV_SKIP_OTP / DEV_LOG_OTP must be off when APP_ENV=production")
	}
	middleware.MustInit()
	log.Println("Email OTP:", cfg.EmailTransport())
	if cfg.DevSkipOTP {
		log.Println("WARNING: DEV_SKIP_OTP=true — OTP verification can be skipped. Turn this off before real users sign up.")
	}

	dbPool, err := config.NewDBPool(cfg)
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer dbPool.Close()

	log.Println("Connected to database successfully")

	if err := migrate.Run(context.Background(), dbPool, migrations.Files); err != nil {
		log.Fatal("Failed to run migrations:", err)
	}
	log.Println("Migrations up to date")

	propertyRepo := repository.NewPropertyRepository(dbPool)
	reviewRepo := repository.NewReviewRepository(dbPool)
	reviewHandler := handlers.NewReviewHandler(reviewRepo, propertyRepo)
	propertyHandler := handlers.NewPropertyHandler(propertyRepo)

	userRepo := repository.NewUserRepository(dbPool)
	otpRepo := repository.NewEmailOTPRepository(dbPool)
	mailer := mail.New(mail.Config{
		Host:        cfg.SMTPHost,
		Port:        cfg.SMTPPort,
		Username:    cfg.SMTPUser,
		Password:    cfg.SMTPPass,
		BrevoAPIKey: cfg.BrevoAPIKey,
		FromEmail:   cfg.EmailFrom,
		FromName:    cfg.EmailName,
		DevLogOTP:   cfg.DevLogOTP,
	})
	authHandler := handlers.NewAuthHandler(userRepo, otpRepo, mailer, cfg.DevSkipOTP)
	passwordResetHandler := handlers.NewPasswordResetHandler(userRepo, repository.NewPasswordResetRepository(dbPool), mailer)
	profileHandler := handlers.NewProfileHandler(userRepo)

	favoriteRepo := repository.NewFavoriteRepository(dbPool)
	favoriteHandler := handlers.NewFavoriteHandler(favoriteRepo)

	// --- Track B: leads (shared by visits / chat / agreements) ---
	leadRepo := repository.NewLeadRepository(dbPool)
	leadHandler := handlers.NewLeadHandler(leadRepo)

	visitRepo := repository.NewVisitRepository(dbPool)
	visitHandler := handlers.NewVisitHandler(visitRepo, propertyRepo, leadRepo)

	messageRepo := repository.NewMessageRepository(dbPool)
	messageHandler := handlers.NewMessageHandler(messageRepo, leadRepo)

	// --- Track B: KYC (B3) — must exist before the agreement handler, which gates signing on it ---
	kycProvider, kycHasher, err := kyc.FromEnv(cfg.AppEnv)
	if err != nil {
		log.Fatal("KYC setup: ", err)
	}
	log.Println("KYC provider:", kycProvider.Name())
	kycRepo := repository.NewKYCRepository(dbPool)
	kycHandler := handlers.NewKYCHandler(kycRepo, kycProvider, kycHasher)

	agreementRepo := repository.NewAgreementRepository(dbPool)
	agreementHandler := handlers.NewAgreementHandler(agreementRepo, mailer, leadRepo, kycRepo)

	brokerSubscriptionRepo := repository.NewBrokerSubscriptionRepository(dbPool)
	brokerHandler := handlers.NewBrokerHandler(brokerSubscriptionRepo)

	notificationRepo := repository.NewNotificationRepository(dbPool)
	deviceTokenRepo := repository.NewDeviceTokenRepository(dbPool)

	pushSender, err := push.NewSender(context.Background(), cfg.FirebaseCredentials)
	if err != nil {
		log.Println("Push notifications disabled — Firebase not configured:", err)
		pushSender = nil
	}
	notificationHandler := handlers.NewNotificationHandler(notificationRepo, deviceTokenRepo, pushSender)
	deviceTokenHandler := handlers.NewDeviceTokenHandler(deviceTokenRepo)

	// Auto notifications (chat, visits, agreements, listings, login) use this.
	notify.Init(dbPool, notificationRepo, deviceTokenRepo, pushSender)

	middleware.SetSuspensionChecker(func(ctx context.Context, userID string) bool {
		var s bool
		if err := dbPool.QueryRow(ctx, `SELECT suspended_at IS NOT NULL FROM users WHERE id = $1::uuid`, userID).Scan(&s); err != nil {
			return false
		}
		return s
	})

	router := gin.Default()

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"message": "PropTech backend is running",
			"build":   "google-auth-v1",
		})
	})

	routes.RegisterPropertyRoutes(router, propertyHandler)
	routes.RegisterAuthRoutes(router, authHandler)
	routes.RegisterPasswordResetRoutes(router, passwordResetHandler)
	routes.RegisterFavoriteRoutes(router, favoriteHandler)
	routes.RegisterVisitRoutes(router, visitHandler)
	routes.RegisterMessageRoutes(router, messageHandler)
	routes.RegisterProfileRoutes(router, profileHandler)
	routes.RegisterAgreementRoutes(router, agreementHandler)
	routes.RegisterLeadRoutes(router, leadHandler) // Track B
	routes.RegisterKYCRoutes(router, kycHandler)   // Track B (B3)
	routes.RegisterBrokerRoutes(router, brokerHandler)
	routes.RegisterNotificationRoutes(router, notificationHandler)
	routes.RegisterDeviceTokenRoutes(router, deviceTokenHandler)
	adminHandler := handlers.NewAdminHandler(dbPool)
	routes.RegisterAdminRoutes(router, adminHandler)
	// Step 3: listing moderation (approval, reports, duplicate check)
	moderationHandler := handlers.NewModerationHandler(dbPool)
	routes.RegisterModerationRoutes(router, moderationHandler)
	routes.RegisterReviewRoutes(router, reviewHandler)

	// Rent lifecycle: leases, rent, deposit, move-in/out photos
	leaseRepo := repository.NewLeaseRepository(dbPool)
	leaseHandler := handlers.NewLeaseHandler(leaseRepo)
	routes.RegisterLeaseRoutes(router, leaseHandler)
	startLeaseJobs(context.Background(), leaseRepo)

	// Online payments (Cashfree sandbox/production). Secret keys are read from env vars only.
	cfCfg := cashfree.ConfigFromEnv(cfg.JWTSecret)
	if cfCfg.Enabled() {
		log.Printf("Cashfree enabled (%s). Webhook URL: %q", cfCfg.Env, cfCfg.NotifyURL)
		if cfg.AppEnv == "production" && cfCfg.Sandbox() {
			log.Println("NOTE: running with Cashfree SANDBOX keys - no real money moves")
		}
	} else {
		log.Println("Cashfree NOT configured (set CASHFREE_APP_ID and CASHFREE_SECRET_KEY) - online payments disabled")
	}
	paymentRepo := repository.NewPaymentRepository(dbPool)
	paymentHandler := handlers.NewPaymentHandler(paymentRepo, leaseRepo, cashfree.NewClient(cfCfg))
	routes.RegisterPaymentRoutes(router, paymentHandler)
	paymentHandler.StartPaymentJobs(context.Background())

	log.Println("Server starting on port " + cfg.Port + "...")
	if err := router.Run(":" + cfg.Port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}