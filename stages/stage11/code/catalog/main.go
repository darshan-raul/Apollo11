// Package main - Apollo11 Catalog Service
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

	r.GET("/books", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"books": []gin.H{},
			"total": 0,
			"page":  1,
			"limit": 20,
		})
	})

	r.GET("/books/:id", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"id":              c.Param("id"),
			"isbn":            "stub-isbn",
			"title":           "Stub Book",
			"author":          gin.H{"id": "stub", "name": "Stub Author"},
			"genre":           "Fiction",
			"copies_available": 1,
		})
	})

	r.POST("/books", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{"status": "created"})
	})

	r.GET("/authors", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"authors": []gin.H{},
			"total":   0,
			"page":    1,
			"limit":   20,
		})
	})

	r.GET("/authors/:id", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"id":   c.Param("id"),
			"name": "Stub Author",
			"bio":  "Stub bio",
		})
	})

	r.POST("/authors", func(c *gin.Context) {
		c.JSON(http.StatusCreated, gin.H{"status": "created"})
	})

	log.Println("Catalog starting on :8081")
	r.Run(":8081")
}