// Package main - Apollo11 Circulation Service
package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

var startupTime = time.Now()

func main() {
	r := gin.Default()

	r.GET("/healthz/startup", func(c *gin.Context) {
		elapsed := time.Since(startupTime)
		if elapsed < 5*time.Second {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"status":  "starting",
				"elapsed": elapsed.Seconds(),
			})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	r.GET("/healthz/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "alive"})
	})

	r.GET("/healthz/ready", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.POST("/loans", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{
			"id":          "stub-loan-id",
			"book_id":     "stub-book-id",
			"borrowed_at": "2024-01-01T00:00:00Z",
			"due_date":    "2024-01-15T00:00:00Z",
			"status":      "active",
		})
	})

	r.POST("/loans/:id/return", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"id":          c.Param("id"),
			"returned_at": "2024-01-10T00:00:00Z",
			"status":      "returned",
		})
	})

	r.GET("/loans", func(c *gin.Context) {
		c.JSON(http.StatusOK, []gin.H{})
	})

	r.POST("/reservations", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{
			"id":         "stub-reservation-id",
			"book_id":    "stub-book-id",
			"status":     "active",
			"expires_at": "2024-01-15T00:00:00Z",
		})
	})

	r.GET("/reservations", func(c *gin.Context) {
		c.JSON(http.StatusOK, []gin.H{})
	})

	r.DELETE("/reservations/:id", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	go func() {
		<-r.Context().Done()
		log.Println("Circulation shutting down...")
		os.Exit(0)
	}()

	log.Println("Circulation starting on :8082")
	r.Run(":8082")
}