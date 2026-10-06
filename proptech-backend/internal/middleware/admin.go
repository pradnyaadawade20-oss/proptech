package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// AdminUserID is not a UUID, so no real user row can ever match it.
// Signup does not validate "role", so we never trust the role claim alone.
const AdminUserID = "admin"

func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or invalid Authorization header"})
			return
		}
		claims, err := ParseToken(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}
		uid, _ := claims["user_id"].(string)
		role, _ := claims["role"].(string)
		if uid != AdminUserID || role != "admin" {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access only"})
			return
		}
		c.Set("user_id", uid)
		if email, ok := claims["email"].(string); ok {
			c.Set("admin_email", email)
		}
		c.Next()
	}
}