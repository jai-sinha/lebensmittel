package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/auth"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/models"
)

func CreateUser(c *gin.Context) {
	var data struct {
		Username    string `json:"username" binding:"required"`
		Password    string `json:"password" binding:"required"`
		DisplayName string `json:"displayName" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Username, password, and displayName are required"})
		return
	}

	hashedPassword, err := auth.HashPassword(data.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to hash password"})
		return
	}

	newUser := models.NewUser(data.Username, hashedPassword, data.DisplayName)

	if err := database.CreateUser(c.Request.Context(), newUser); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, newUser)
}

func GetUser(c *gin.Context) {
	username := c.Param("username")

	user, err := database.GetUserByUsername(c.Request.Context(), username)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

func UpdateUser(c *gin.Context) {
	userID := c.Param("user_id")

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	user, err := database.UpdateUser(c.Request.Context(), userID, data)
	if err != nil {
		if user == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, user)
}

func DeleteUser(c *gin.Context) {
	userID := c.Param("user_id")

	if err := database.DeleteUser(c.Request.Context(), userID); err != nil {
		if err.Error() == "user not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User deleted successfully"})
}

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

	var data map[string]any
	if err := c.ShouldBindJSON(&data); err != nil || len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No data provided"})
		return
	}

	group, err := database.UpdateGroup(c.Request.Context(), groupID, data)
	if err != nil {
		if group == nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Group not found"})
		} else {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, group)
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

	c.JSON(http.StatusOK, gin.H{"message": "Group deleted successfully"})
}

func AddUserToGroup(c *gin.Context) {
	groupID := c.Param("group_id")
	var data struct {
		UserID string `json:"userId" binding:"required"`
	}

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "userId is required"})
		return
	}

	if err := database.AddUserToGroup(c.Request.Context(), data.UserID, groupID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User added to group successfully"})
}
