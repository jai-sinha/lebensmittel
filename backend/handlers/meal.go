package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
	"github.com/lebensmittel/backend/websocket"
)

func GetMealPlans(c *gin.Context) {
	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	meals, err := database.GetAllMealPlans(c.Request.Context(), groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if meals == nil { // ensure JSON never returns null
		meals = []models.MealPlan{}
	}

	c.JSON(http.StatusOK, gin.H{
		"mealPlans": meals,
		"count":     len(meals),
	})
}

func CreateMealPlan(c *gin.Context) {
	var data struct {
		Date            string `json:"date" binding:"required"`
		MealDescription string `json:"mealDescription" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Date and mealDescription are required"})
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

	newMeal := models.NewMealPlan(date, data.MealDescription, groupID, userID)

	if err := database.CreateMealPlan(c.Request.Context(), newMeal); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Emit websocket event
	websocket.EmitEvent("meal_plan_created", newMeal, groupID)

	c.JSON(http.StatusCreated, newMeal)
}

func UpdateMealPlan(c *gin.Context) {
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

	// TODO: Verify item belongs to user's group

	meal, err := database.UpdateMealPlan(c.Request.Context(), mealID, data)
	if err != nil {
		if meal == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("meal_plan_updated", meal, meal.GroupID)

	c.JSON(http.StatusOK, meal)
}

func DeleteMealPlan(c *gin.Context) {
	mealID := c.Param("meal_id")

	groupID, err := getActiveGroupID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// TODO: Verify item belongs to user's group

	if err := database.DeleteMealPlan(c.Request.Context(), mealID); err != nil {
		if err.Error() == "meal plan not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Meal plan not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Emit websocket event
	websocket.EmitEvent("meal_plan_deleted", gin.H{"id": mealID}, groupID)

	c.JSON(http.StatusOK, gin.H{"message": "Meal plan deleted successfully"})
}
