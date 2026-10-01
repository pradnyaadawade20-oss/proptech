package middleware

import (
	"errors"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

var (
	jwtSecret []byte
	jwtOnce   sync.Once
)

// secret reads JWT_SECRET lazily (after .env is loaded in main()).
// No hardcoded fallback — old code had "proptech-secret-key-change-in-production"
// as default, so anyone could forge tokens with that known string.
func secret() []byte {
	jwtOnce.Do(func() {
		s := strings.TrimSpace(os.Getenv("JWT_SECRET"))
		if len(s) < 32 {
			log.Fatal("JWT_SECRET is missing or too short. Set it to a random string of at least 32 characters (openssl rand -hex 32).")
		}
		jwtSecret = []byte(s)
	})
	return jwtSecret
}

// MustInit fails fast at startup if JWT_SECRET isn't configured.
func MustInit() { secret() }

func GenerateToken(userID, email, role string) (string, error) {
	claims := jwt.MapClaims{
		"user_id": userID,
		"email":   email,
		"role":    role,
		"iat":     time.Now().Unix(),
		"exp":     time.Now().Add(30 * 24 * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(secret())
}

func ParseToken(tokenString string) (jwt.MapClaims, error) {
	token, err := jwt.Parse(
		tokenString,
		func(t *jwt.Token) (interface{}, error) { return secret(), nil },
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, jwt.ErrTokenInvalidClaims
	}
	return claims, nil
}

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or invalid Authorization header"})
			return
		}
		tokenString := strings.TrimPrefix(header, "Bearer ")
		claims, err := ParseToken(tokenString)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}
		userID, ok := claims["user_id"].(string)
		if !ok || userID == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token claims"})
			return
		}
		c.Set("user_id", userID)
		if email, ok := claims["email"].(string); ok {
			c.Set("email", email)
		}
		if role, ok := claims["role"].(string); ok {
			c.Set("role", role)
		}
		c.Next()
	}
}

func GetUserID(c *gin.Context) (string, error) {
	v, exists := c.Get("user_id")
	if !exists {
		return "", errors.New("no authenticated user on context")
	}
	userID, ok := v.(string)
	if !ok || userID == "" {
		return "", errors.New("invalid user id on context")
	}
	return userID, nil
}
