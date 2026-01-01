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
	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	receipts, err := database.GetAllReceipts(c.Request.Context(), groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"receipts": receipts,
		"count":    len(receipts),
	})
}

func CreateReceipt(c *gin.Context) {
	var data struct {
		Date        string  `json:"date" binding:"required"`
		TotalAmount float64 `json:"totalAmount" binding:"required"`
		PurchasedBy string  `json:"purchasedBy" binding:"required"`
		Notes       *string `json:"notes"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date, totalAmount, and purchasedBy are required"})
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

	// Parse date
	date, err := time.Parse("2006-01-02", data.Date)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
		return
	}

	newReceipt := &models.Receipt{
		ID:          uuid.New().String(),
		Date:        date,
		TotalAmount: data.TotalAmount,
		PurchasedBy: data.PurchasedBy,
		Notes:       data.Notes,
		GroupID:     groupID,
		UserID:      userID,
	}

	if err := database.CreateReceipt(c.Request.Context(), newReceipt); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	websocket.EmitEvent("receipt_created", newReceipt, groupID)

	c.JSON(http.StatusCreated, newReceipt)
}

func UpdateReceipt(c *gin.Context) {
	receiptID := c.Param("receipt_id")

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	// Handle date parsing if provided
	if dateStr, ok := data["date"].(string); ok {
		date, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
			return
		}
		data["date"] = date
	}

	// Handle total amount conversion
	if totalAmount, ok := data["totalAmount"].(float64); ok {
		data["totalAmount"] = totalAmount
	} else if totalAmountStr, ok := data["totalAmount"].(string); ok {
		if totalAmount, err := strconv.ParseFloat(totalAmountStr, 64); err == nil {
			data["totalAmount"] = totalAmount
		}
	}

	// TODO: Verify item belongs to user's group

	receipt, err := database.UpdateReceipt(c.Request.Context(), receiptID, data)
	if err != nil {
		if receipt == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("receipt_updated", receipt, receipt.GroupID)

	c.JSON(http.StatusOK, receipt)
}

func DeleteReceipt(c *gin.Context) {
	receiptID := c.Param("receipt_id")

	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Verify item belongs to user's group

	if err := database.DeleteReceipt(c.Request.Context(), receiptID); err != nil {
		if err.Error() == "receipt not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("receipt_deleted", gin.H{"id": receiptID}, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "Receipt deleted successfully"})
}
