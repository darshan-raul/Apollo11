// Package main - Apollo11 Notification Service
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

	r.POST("/notifications", func(c *gin.Context) {
		c.JSON(http.StatusAccepted, gin.H{
			"id":     "stub-notification-id",
			"queued": true,
		})
	})

	r.GET("/notifications", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"pending": 0})
	})

	go func() {
		<-r.Context().Done()
		log.Println("Notification shutting down...")
		os.Exit(0)
	}()

	log.Println("Notification starting on :8083")
	r.Run(":8083")
}