package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func GetReceipts(c *gin.Context) {
	gid := groupID(c)

	receipts, err := database.GetAllReceipts(c.Request.Context(), gid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if receipts == nil { // ensure JSON never returns null
		receipts = []models.Receipt{}
	}

	c.JSON(http.StatusOK, gin.H{
		"receipts": receipts,
		"count":    len(receipts),
	})
}

func CreateReceipt(c *gin.Context) {
	var data CreateReceiptRequest
	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date, totalAmount, and purchasedBy are required"})
		return
	}

	receipt, err := data.toModel(groupID(c))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	created, updatedItems, isNew, err := database.CreateReceipt(c.Request.Context(), &receipt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// emit grocery items changed before receipt is created
	if isNew && len(updatedItems) > 0 {
		websocket.EmitEvent("grocery_items_updated", updatedItems, groupID(c))
	}

	createdOnce(c, created, isNew, groupID(c), "receipt_created")
}

func UpdateReceipt(c *gin.Context) {
	receiptID, _ := uuid.Parse(c.Param("receipt_id"))

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	if dateStr, ok := data["date"].(string); ok {
		date, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
			return
		}
		data["date"] = date
	}

	if totalAmount, ok := data["totalAmount"].(float64); ok {
		data["totalAmount"] = totalAmount
	} else if totalAmountStr, ok := data["totalAmount"].(string); ok {
		if totalAmount, err := strconv.ParseFloat(totalAmountStr, 64); err == nil {
			data["totalAmount"] = totalAmount
		}
	}

	gid := groupID(c)

	receipt, err := database.UpdateReceipt(c.Request.Context(), receiptID, gid, data)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if receipt == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		return
	}

	websocket.EmitEvent("receipt_updated", receipt, receipt.GroupID)

	c.JSON(http.StatusOK, receipt)
}

func DeleteReceipt(c *gin.Context) {
	receiptID, _ := uuid.Parse(c.Param("receipt_id"))

	gid := groupID(c)

	if err := database.DeleteReceipt(c.Request.Context(), receiptID, gid); err != nil {
		if err.Error() == "receipt not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	websocket.EmitEvent("receipt_deleted", gin.H{"id": receiptID}, gid)

	c.JSON(http.StatusOK, gin.H{"message": "Receipt deleted successfully"})
}
