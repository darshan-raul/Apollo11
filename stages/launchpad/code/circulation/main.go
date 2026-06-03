// Package main - Apollo11 Circulation Service
package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func main() {
	r := gin.Default()
	r.Use(cors())

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.POST("/loans", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{
			"id":          "stub-loan-id",
			"book_id":     "stub-book-id",
			"borrowed_at": "2024-01-01T00:00:00Z",
			"due_date":    "2024-01-15T00:00:00Z",
			"status":     "active",
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

	log.Println("Circulation starting on :8082")
	r.Run(":8082")
}