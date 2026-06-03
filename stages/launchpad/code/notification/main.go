// Package main - Apollo11 Notification Service
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

	r.POST("/notifications", func(c *gin.Context) {
		c.JSON(http.StatusAccepted, gin.H{
			"id":      "stub-notification-id",
			"queued":  true,
		})
	})

	r.GET("/notifications", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"pending": 0})
	})

	log.Println("Notification starting on :8083")
	r.Run(":8083")
}