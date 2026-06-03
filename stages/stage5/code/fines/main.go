// Package main - Apollo11 Fines Service
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

	r.GET("/fines", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"fines":        []gin.H{},
			"total_unpaid": 0.0,
		})
	})

	r.POST("/fines/:id/pay", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"id":      c.Param("id"),
			"paid":    true,
			"paid_at": "2024-01-10T00:00:00Z",
		})
	})

	go func() {
		<-r.Context().Done()
		log.Println("Fines shutting down...")
		os.Exit(0)
	}()

	log.Println("Fines starting on :8084")
	r.Run(":8084")
}