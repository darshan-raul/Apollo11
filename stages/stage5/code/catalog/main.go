// Package main - Apollo11 Catalog Service
package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

// Probe latency tracking
var startupTime = time.Now()

func main() {
	r := gin.Default()

	// Startup probe: healthy after initial boot
	r.GET("/healthz/startup", func(c *gin.Context) {
		elapsed := time.Since(startupTime)
		// Consider started after 5 seconds
		if elapsed < 5*time.Second {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"status":  "starting",
				"elapsed": elapsed.Seconds(),
			})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	// Liveness probe: service is alive (not deadlocked)
	r.GET("/healthz/live", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "alive"})
	})

	// Readiness probe: service can handle traffic
	r.GET("/healthz/ready", func(c *gin.Context) {
		// In production: check DB conn, Redis conn, downstream APIs
		c.JSON(http.StatusOK, gin.H{"status": "ready"})
	})

	// Legacy /health for backwards compatibility
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Graceful shutdown on SIGTERM
	go func() {
		<-r.Context().Done()
		log.Println("Catalog shutting down...")
		os.Exit(0)
	}()

	log.Println("Catalog starting on :8081")
	r.Run(":8081")
}