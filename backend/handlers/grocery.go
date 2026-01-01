package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func GetGroceryItems(c *gin.Context) {
	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	items, err := database.GetAllGroceryItems(c.Request.Context(), groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"groceryItems": items,
		"count":        len(items),
	})
}

func CreateGroceryItem(c *gin.Context) {
	var data struct {
		Name              string `json:"name" binding:"required"`
		Category          string `json:"category" binding:"required"`
		IsNeeded          *bool  `json:"isNeeded"`
		IsShoppingChecked *bool  `json:"isShoppingChecked"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Name and category are required"})
		return
	}

	userID := c.GetString("userID")
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Set defaults
	isNeeded := true
	if data.IsNeeded != nil {
		isNeeded = *data.IsNeeded
	}

	isShoppingChecked := false
	if data.IsShoppingChecked != nil {
		isShoppingChecked = *data.IsShoppingChecked
	}

	newItem := models.NewGroceryItem(data.Name, data.Category, isNeeded, isShoppingChecked, groupID, userID)

	if err := database.CreateGroceryItem(c.Request.Context(), newItem); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	websocket.EmitEvent("grocery_item_created", newItem)

	c.JSON(http.StatusCreated, newItem)
}

func UpdateGroceryItem(c *gin.Context) {
	itemID := c.Param("item_id")

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	// TODO: Verify item belongs to user's group

	item, err := database.UpdateGroceryItem(c.Request.Context(), itemID, data)
	if err != nil {
		if item == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("grocery_item_updated", item)

	c.JSON(http.StatusOK, item)
}

func DeleteGroceryItem(c *gin.Context) {
	itemID := c.Param("item_id")

	// TODO: Verify item belongs to user's group

	if err := database.DeleteGroceryItem(c.Request.Context(), itemID); err != nil {
		if err.Error() == "grocery item not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("grocery_item_deleted", gin.H{"id": itemID})

	c.JSON(http.StatusOK, gin.H{"message": "Grocery item deleted successfully"})
}
