package handlers

import (
	"crypto/rand"
	"math/big"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
)

const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

func generateRandomCode(length int) (string, error) {
	b := make([]byte, length)
	for i := range b {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		b[i] = charset[num.Int64()]
	}
	return string(b), nil
}

// GenerateJoinCode creates a temporary code for a group
func GenerateJoinCode(c *gin.Context) {
	groupID := c.Param("group_id")
	userID := c.GetString("userID")

	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	code, err := generateRandomCode(6)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate code"})
		return
	}

	// Default expiry: 15 minutes
	expiresIn := 15 * time.Minute
	joinCode := models.NewJoinCode(code, groupID, userID, expiresIn)

	if err := database.CreateJoinCode(c.Request.Context(), joinCode); err != nil {
		// In a real app, you'd want to handle collisions (duplicate code) by retrying
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"code":      joinCode.Code,
		"expiresAt": joinCode.ExpiresAt,
	})
}

// JoinGroupWithCode allows a user to join a group using a 6-digit code
func JoinGroupWithCode(c *gin.Context) {
	var data struct {
		Code string `json:"code" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Code is required"})
		return
	}

	userID := c.GetString("userID")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	// 1. Get Code
	joinCode, err := database.GetJoinCode(c.Request.Context(), data.Code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if joinCode == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Invalid or non-existent code"})
		return
	}

	// 2. Check Expiry
	if time.Now().After(joinCode.ExpiresAt) {
		// Clean up expired code
		_ = database.DeleteJoinCode(c.Request.Context(), data.Code)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Code has expired"})
		return
	}

	// 3. Add User to Group
	if err := database.AddUserToGroup(c.Request.Context(), userID, joinCode.GroupID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 4. Return success with group ID
	c.JSON(http.StatusOK, gin.H{
		"message": "Successfully joined group",
		"groupId": joinCode.GroupID,
	})
}
