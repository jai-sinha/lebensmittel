package handlers

import (
	"fmt"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
)

// getActiveGroupID determines the group ID to use for the request.
// It checks the "X-Group-ID" header. If present, it verifies the user is a member.
// If absent, it defaults to the user's first group.
func getActiveGroupID(c *gin.Context) (string, error) {
	userID := c.GetString("userID")
	if userID == "" {
		return "", fmt.Errorf("unauthorized")
	}

	// Get all groups for the user
	userGroups, err := database.GetUserGroups(c.Request.Context(), userID)
	if err != nil {
		return "", fmt.Errorf("failed to get user groups: %w", err)
	}
	if len(userGroups) == 0 {
		return "", fmt.Errorf("user has no groups")
	}

	// Check for X-Group-ID header
	requestedGroupID := c.GetHeader("X-Group-ID")

	if requestedGroupID != "" {
		// Verify membership
		isMember := false
		for _, g := range userGroups {
			if g.ID == requestedGroupID {
				isMember = true
				break
			}
		}
		if !isMember {
			return "", fmt.Errorf("user is not a member of the requested group")
		}
		return requestedGroupID, nil
	}

	// Default to the first group
	return userGroups[0].ID, nil
}
