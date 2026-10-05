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

	if err := database.EnsureSchema(); err != nil {
		log.Fatalf("Failed to ensure schema: %v", err)
	}
	database.EnsurePruneJob()

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

	// entity routes resolve their group from the X-Group-ID header
	auth := api.Group("", handlers.RequireGroup)

	auth.GET("/changes", handlers.GetChanges)

	auth.GET("/grocery-items", handlers.GetGroceryItems)
	auth.POST("/grocery-items", handlers.CreateGroceryItem)
	auth.PATCH("/grocery-items/:item_id", handlers.UpdateGroceryItem)
	auth.DELETE("/grocery-items/:item_id", handlers.DeleteGroceryItem)

	auth.GET("/meal-plans", handlers.GetMealPlans)
	auth.POST("/meal-plans", handlers.CreateMealPlan)
	auth.PATCH("/meal-plans/:meal_id", handlers.UpdateMealPlan)
	auth.DELETE("/meal-plans/:meal_id", handlers.DeleteMealPlan)

	auth.GET("/receipts", handlers.GetReceipts)
	auth.POST("/receipts", handlers.CreateReceipt)
	auth.PATCH("/receipts/:receipt_id", handlers.UpdateReceipt)
	auth.DELETE("/receipts/:receipt_id", handlers.DeleteReceipt)

	auth.POST("/groups/seed", handlers.SeedGroup)

	// these name their group in the path or body, so they run without a header.
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
