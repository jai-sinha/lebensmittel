package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/lebensmittel/backend/database"
	"github.com/lebensmittel/backend/handlers"
	"github.com/lebensmittel/backend/websocket"
)

func main() {
	if err := database.InitDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.CloseDB()

	websocket.InitWebSocketManager()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	config := cors.DefaultConfig()
	config.AllowAllOrigins = true
	config.AllowMethods = []string{"GET", "POST", "PATCH", "DELETE", "OPTIONS"}
	config.AllowHeaders = []string{"Origin", "Content-Type", "Accept", "X-Group-ID"}
	r.Use(cors.New(config))

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"message": "Service is running",
		})
	})

	r.GET("/ws", websocket.HandleWebSocket)

	api := r.Group("/api")

	api.GET("/grocery-items", handlers.GetGroceryItems)
	api.POST("/grocery-items", handlers.CreateGroceryItem)
	api.PATCH("/grocery-items/:item_id", handlers.UpdateGroceryItem)
	api.DELETE("/grocery-items/:item_id", handlers.DeleteGroceryItem)

	api.GET("/meal-plans", handlers.GetMealPlans)
	api.POST("/meal-plans", handlers.CreateMealPlan)
	api.PATCH("/meal-plans/:meal_id", handlers.UpdateMealPlan)
	api.DELETE("/meal-plans/:meal_id", handlers.DeleteMealPlan)

	api.GET("/receipts", handlers.GetReceipts)
	api.POST("/receipts", handlers.CreateReceipt)
	api.PATCH("/receipts/:receipt_id", handlers.UpdateReceipt)
	api.DELETE("/receipts/:receipt_id", handlers.DeleteReceipt)

	api.POST("/groups", handlers.CreateGroup)
	api.GET("/groups/:group_id", handlers.GetGroup)
	api.PATCH("/groups/:group_id", handlers.UpdateGroup)
	api.DELETE("/groups/:group_id", handlers.DeleteGroup)

	// temporary migration endpoint for recovering legacy user group memberships
	api.GET("/migration/users/:user_id/groups", handlers.GetGroupsFromLegacyUserID)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	log.Printf("Server starting on port %s", port)
	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %s\n", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exiting")
}
