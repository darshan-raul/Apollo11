// Package main - Apollo11 Notification Service
package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

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