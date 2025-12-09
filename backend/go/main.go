package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func main() {

	// Initialize database
	if err := InitDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer CloseDB()

	// Initialize WebSocket manager
	InitWebSocketManager()

	// Create Gin router
	r := gin.Default()

	// Configure CORS
	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept", "Authorization"}
	r.Use(cors.New(config))

	// API routes list for documentation
	apiRoutes := []map[string]any{
		{"route": "/", "methods": []string{"GET"}, "description": "Home route (API info)"},
		{"route": "/health", "methods": []string{"GET"}, "description": "Health check"},
		{"route": "/ws", "methods": []string{"GET"}, "description": "WebSocket connection"},
		{"route": "/api/grocery-items", "methods": []string{"GET"}, "description": "Get all grocery items"},
		{"route": "/api/grocery-items", "methods": []string{"POST"}, "description": "Create a grocery item"},
		{"route": "/api/grocery-items/:item_id", "methods": []string{"PUT"}, "description": "Update a grocery item"},
		{"route": "/api/grocery-items/:item_id", "methods": []string{"DELETE"}, "description": "Delete a grocery item"},
		{"route": "/api/meal-plans", "methods": []string{"GET"}, "description": "Get all meal plans"},
		{"route": "/api/meal-plans", "methods": []string{"POST"}, "description": "Create a meal plan"},
		{"route": "/api/meal-plans/:meal_id", "methods": []string{"PUT"}, "description": "Update a meal plan"},
		{"route": "/api/meal-plans/:meal_id", "methods": []string{"DELETE"}, "description": "Delete a meal plan"},
		{"route": "/api/receipts", "methods": []string{"GET"}, "description": "Get all receipts"},
		{"route": "/api/receipts", "methods": []string{"POST"}, "description": "Create a receipt"},
		{"route": "/api/receipts/:receipt_id", "methods": []string{"PUT"}, "description": "Update a receipt"},
		{"route": "/api/receipts/:receipt_id", "methods": []string{"DELETE"}, "description": "Delete a receipt"},
	}

	// Home route
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message":   "Welcome to the Lebensmittel Backend API",
			"status":    "success",
			"version":   "2.0.0",
			"apiRoutes": apiRoutes,
		})
	})

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"message": "Service is running",
		})
	})

	// WebSocket endpoint
	r.GET("/ws", wsManager.HandleWebSocket)

	// API routes group
	api := r.Group("/api")

	// Grocery Items routes
	api.GET("/grocery-items", getGroceryItems)
	api.POST("/grocery-items", createGroceryItem)
	api.PUT("/grocery-items/:item_id", updateGroceryItem)
	api.DELETE("/grocery-items/:item_id", deleteGroceryItem)

	// Meal Plans routes
	api.GET("/meal-plans", getMealPlans)
	api.POST("/meal-plans", createMealPlan)
	api.PUT("/meal-plans/:meal_id", updateMealPlan)
	api.DELETE("/meal-plans/:meal_id", deleteMealPlan)

	// Receipts routes
	api.GET("/receipts", getReceipts)
	api.POST("/receipts", createReceipt)
	api.PUT("/receipts/:receipt_id", updateReceipt)
	api.DELETE("/receipts/:receipt_id", deleteReceipt)

	// Get port from environment or default to 8000
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	log.Printf("Server starting on port %s", port)
	r.Run(":" + port)
}

// Grocery Items handlers

func getGroceryItems(c *gin.Context) {
	items, err := GetAllGroceryItems(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"groceryItems": items,
		"count":        len(items),
	})
}

func createGroceryItem(c *gin.Context) {
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

	// Set defaults
	isNeeded := true
	if data.IsNeeded != nil {
		isNeeded = *data.IsNeeded
	}

	isShoppingChecked := false
	if data.IsShoppingChecked != nil {
		isShoppingChecked = *data.IsShoppingChecked
	}

	newItem := NewGroceryItem(data.Name, data.Category, isNeeded, isShoppingChecked)

	if err := CreateGroceryItem(c.Request.Context(), newItem); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	EmitEvent("grocery_item_created", newItem)

	c.JSON(http.StatusCreated, newItem)
}

func updateGroceryItem(c *gin.Context) {
	itemID := c.Param("item_id")

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	item, err := UpdateGroceryItem(c.Request.Context(), itemID, data)
	if err != nil {
		if item == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("grocery_item_updated", item)

	c.JSON(http.StatusOK, item)
}

func deleteGroceryItem(c *gin.Context) {
	itemID := c.Param("item_id")

	if err := DeleteGroceryItem(c.Request.Context(), itemID); err != nil {
		if err.Error() == "grocery item not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Grocery item not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("grocery_item_deleted", gin.H{"id": itemID})

	c.JSON(http.StatusOK, gin.H{"message": "Grocery item deleted successfully"})
}

// Meal Plans handlers

func getMealPlans(c *gin.Context) {
	meals, err := GetAllMealPlans(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"mealPlans": meals,
		"count":     len(meals),
	})
}

func createMealPlan(c *gin.Context) {
	var data struct {
		Date            string `json:"date" binding:"required"`
		MealDescription string `json:"mealDescription" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Date and mealDescription are required"})
		return
	}

	// Parse date
	date, err := time.Parse("2006-01-02", data.Date)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
		return
	}

	newMeal := NewMealPlan(date, data.MealDescription)

	if err := CreateMealPlan(c.Request.Context(), newMeal); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	EmitEvent("meal_plan_created", newMeal)

	c.JSON(http.StatusCreated, newMeal)
}

func updateMealPlan(c *gin.Context) {
	mealID := c.Param("meal_id")

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

	meal, err := UpdateMealPlan(c.Request.Context(), mealID, data)
	if err != nil {
		if meal == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("meal_plan_updated", meal)

	c.JSON(http.StatusOK, meal)
}

func deleteMealPlan(c *gin.Context) {
	mealID := c.Param("meal_id")

	if err := DeleteMealPlan(c.Request.Context(), mealID); err != nil {
		if err.Error() == "meal plan not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("meal_plan_deleted", gin.H{"id": mealID})

	c.JSON(http.StatusOK, gin.H{"message": "Meal plan deleted successfully"})
}

// Receipts handlers

func getReceipts(c *gin.Context) {
	receipts, err := GetAllReceipts(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"receipts": receipts,
		"count":    len(receipts),
	})
}

func createReceipt(c *gin.Context) {
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

	// Parse date
	date, err := time.Parse("2006-01-02", data.Date)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid date format. Use YYYY-MM-DD"})
		return
	}

	newReceipt := &Receipt{
		ID:          uuid.New().String(),
		Date:        date,
		TotalAmount: data.TotalAmount,
		PurchasedBy: data.PurchasedBy,
		Notes:       data.Notes,
	}

	if err := CreateReceipt(c.Request.Context(), newReceipt); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	EmitEvent("receipt_created", newReceipt)

	c.JSON(http.StatusCreated, newReceipt)
}

func updateReceipt(c *gin.Context) {
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

	receipt, err := UpdateReceipt(c.Request.Context(), receiptID, data)
	if err != nil {
		if receipt == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("receipt_updated", receipt)

	c.JSON(http.StatusOK, receipt)
}

func deleteReceipt(c *gin.Context) {
	receiptID := c.Param("receipt_id")

	if err := DeleteReceipt(c.Request.Context(), receiptID); err != nil {
		if err.Error() == "receipt not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Receipt not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	EmitEvent("receipt_deleted", gin.H{"id": receiptID})

	c.JSON(http.StatusOK, gin.H{"message": "Receipt deleted successfully"})
}
