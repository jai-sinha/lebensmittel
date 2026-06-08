package handlers

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"
)

func getRequestedGroupID(c *gin.Context) (string, error) {
	groupID := strings.TrimSpace(c.GetHeader("X-Group-ID"))
	if groupID == "" {
		return "", fmt.Errorf("X-Group-ID header required")
	}
	return groupID, nil
}
