// Package main - Apollo11 Fines Service
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

	log.Println("Fines starting on :8084")
	r.Run(":8084")
}