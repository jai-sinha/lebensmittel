package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/websocket"
)

const groupIDKey = "groupID"

func RequireGroup(c *gin.Context) {
	groupID := strings.TrimSpace(c.GetHeader("X-Group-ID"))
	if groupID == "" {
		c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "X-Group-ID header required"})
		return
	}
	c.Set(groupIDKey, groupID)
	c.Next()
}

func groupID(c *gin.Context) string {
	return c.GetString(groupIDKey)
}

// write the retry-aware response for a Create* call
func createdOnce[T any](c *gin.Context, created T, isNew bool, groupID, event string) {
	if !isNew {
		// a previous attempt already stored this id, so return the row without re-emitting
		c.JSON(http.StatusOK, created)
		return
	}
	websocket.EmitEvent(event, created, groupID)
	c.JSON(http.StatusCreated, created)
}
