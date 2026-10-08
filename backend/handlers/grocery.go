package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func GetGroceryItems(c *gin.Context) {
	gid := groupID(c)

	items, err := database.GetAllGroceryItems(c.Request.Context(), gid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if items == nil { // ensure JSON never returns null
		items = []models.GroceryItem{}
	}

	c.JSON(http.StatusOK, gin.H{
		"groceryItems": items,
		"count":        len(items),
	})
}

func CreateGroceryItem(c *gin.Context) {
	var data CreateGroceryItemRequest
	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "id (uuid), name and category are required"})
		return
	}

	item := data.toModel(groupID(c))

	created, isNew, err := database.CreateGroceryItem(c.Request.Context(), &item)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	createdOnce(c, created, isNew, groupID(c), "grocery_item_created")
}

func UpdateGroceryItem(c *gin.Context) {
	itemID, _ := uuid.Parse(c.Param("item_id"))

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	gid := groupID(c)

	item, err := database.UpdateGroceryItem(c.Request.Context(), itemID, gid, data)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if item == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		return
	}

	// Emit websocket event
	websocket.EmitEvent("grocery_item_updated", item, item.GroupID)

	c.JSON(http.StatusOK, item)
}

func DeleteGroceryItem(c *gin.Context) {
	itemID, _ := uuid.Parse(c.Param("item_id"))

	gid := groupID(c)

	if err := database.DeleteGroceryItem(c.Request.Context(), itemID, gid); err != nil {
		if err.Error() == "grocery item not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("grocery_item_deleted", gin.H{"id": itemID}, gid)

	c.JSON(http.StatusOK, gin.H{"message": "Grocery item deleted successfully"})
}
