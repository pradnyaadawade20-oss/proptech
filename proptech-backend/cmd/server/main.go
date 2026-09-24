package main

import (
	"log"
	"net/http"

	"context"

	"proptech-backend/internal/config"
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/migrate"
	"proptech-backend/internal/repository"
	"proptech-backend/internal/routes"
	"proptech-backend/migrations"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	cfg := config.LoadConfig()

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
	propertyHandler := handlers.NewPropertyHandler(propertyRepo)

	userRepo := repository.NewUserRepository(dbPool)
	authHandler := handlers.NewAuthHandler(userRepo)
	profileHandler := handlers.NewProfileHandler(userRepo)

	favoriteRepo := repository.NewFavoriteRepository(dbPool)
	favoriteHandler := handlers.NewFavoriteHandler(favoriteRepo)

	visitRepo := repository.NewVisitRepository(dbPool)
	visitHandler := handlers.NewVisitHandler(visitRepo, propertyRepo)

	messageRepo := repository.NewMessageRepository(dbPool)
	messageHandler := handlers.NewMessageHandler(messageRepo)

	agreementRepo := repository.NewAgreementRepository(dbPool)
	agreementHandler := handlers.NewAgreementHandler(agreementRepo)

	router := gin.Default()

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"message": "PropTech backend is running",
		})
	})

	routes.RegisterPropertyRoutes(router, propertyHandler)
	routes.RegisterAuthRoutes(router, authHandler)
	routes.RegisterFavoriteRoutes(router, favoriteHandler)
	routes.RegisterVisitRoutes(router, visitHandler)
	routes.RegisterMessageRoutes(router, messageHandler)
	routes.RegisterProfileRoutes(router, profileHandler)
	routes.RegisterAgreementRoutes(router, agreementHandler)

	log.Println("Server starting on port " + cfg.Port + "...")
	if err := router.Run(":" + cfg.Port); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}
