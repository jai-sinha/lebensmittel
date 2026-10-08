package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func CreateGroup(c *gin.Context) {
	var data struct {
		Name string `json:"name" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Name is required"})
		return
	}

	newGroup := models.NewGroup(data.Name)
	if err := database.CreateGroup(c.Request.Context(), newGroup); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, newGroup)
}

func SeedGroup(c *gin.Context) {
	gid := groupID(c)

	group, err := database.GetGroupByID(c.Request.Context(), gid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if group == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}

	var data struct {
		Grocery []CreateGroceryItemRequest `json:"grocery"`
		Meal    []CreateMealPlanRequest    `json:"meal"`
		Receipt *CreateReceiptRequest      `json:"receipt"`
	}
	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid seed payload"})
		return
	}

	ctx := c.Request.Context()
	for _, item := range data.Grocery {
		entity := item.toModel(gid)
		if _, _, err := database.CreateGroceryItem(ctx, &entity); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	for _, plan := range data.Meal {
		meal, err := plan.toModel(gid)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if _, _, err := database.CreateMealPlan(ctx, &meal); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	if data.Receipt != nil {
		receipt, err := data.Receipt.toModel(gid)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if _, _, _, err := database.CreateReceipt(ctx, &receipt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	c.JSON(http.StatusCreated, gin.H{"seeded": true})
}

func GetGroup(c *gin.Context) {
	groupID := c.Param("group_id")

	group, err := database.GetGroupByID(c.Request.Context(), groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if group == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		return
	}

	c.JSON(http.StatusOK, group)
}

func UpdateGroup(c *gin.Context) {
	groupID := c.Param("group_id")

	var data struct {
		Name       *string   `json:"name"`
		Categories *[]string `json:"categories"`
		Members    *[]string `json:"members"`
	}
	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid group update payload"})
		return
	}

	updates := map[string]any{}
	if data.Name != nil {
		name := strings.TrimSpace(*data.Name)
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Group name cannot be empty"})
			return
		}
		updates["name"] = name
	}
	if data.Categories != nil {
		updates["categories"] = normalizeGroupValues(*data.Categories)
	}
	if data.Members != nil {
		updates["members"] = normalizeGroupValues(*data.Members)
	}
	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	group, err := database.UpdateGroup(c.Request.Context(), groupID, updates)
	if err != nil {
		if group == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	websocket.EmitEvent("group_updated", group, groupID)

	c.JSON(http.StatusOK, group)
}

func normalizeGroupValues(values []string) []string {
	normalized := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			normalized = append(normalized, trimmed)
		}
	}
	return normalized
}

func DeleteGroup(c *gin.Context) {
	groupID := c.Param("group_id")

	if err := database.DeleteGroup(c.Request.Context(), groupID); err != nil {
		if err.Error() == "group not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	websocket.EmitEvent("group_deleted", gin.H{"id": groupID}, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "Group deleted successfully"})
}

// temporary migration endpoint for group memberships from the legacy user_groups table
func GetGroupsFromLegacyUserID(c *gin.Context) {
	userID := strings.TrimSpace(c.Param("user_id"))
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
		return
	}

	groups, err := database.GetGroupsFromID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, groups)
}
