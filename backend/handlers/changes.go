package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
)

func GetChanges(c *gin.Context) {
	gid := groupID(c)

	afterSeq, err := parseAfterSeq(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	changes, err := database.GetGroupChanges(c.Request.Context(), gid, afterSeq)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, changes)
}

// parseAfterSeq reads the client's cursor, if no cursor then return nil, this will be treated as
// a full fetch request
func parseAfterSeq(c *gin.Context) (*int64, error) {
	raw := c.Query("afterSeq")
	if raw == "" {
		return nil, nil
	}
	seq, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || seq < 0 {
		return nil, errors.New("afterSeq must be a non-negative integer")
	}
	return &seq, nil
}
