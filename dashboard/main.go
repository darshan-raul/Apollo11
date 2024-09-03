package main

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"fmt"
)

type Movie struct {
	Title    string
	Genre    string
	Theatres []Theatre
}

type Theatre struct {
	Name  string
	Location string
}

func main() {
	r := gin.Default()
	r.LoadHTMLGlob("templates/*")
	r.Static("/static", "./static")

	movies := []Movie{
		{
			Title: "Inception",
			Genre: "Sci-Fi",
			Theatres: []Theatre{
				{Name: "Cineplex", Location: "Downtown"},
				{Name: "AMC", Location: "Uptown"},
			},
		},
		{
			Title: "The Godfather",
			Genre: "Crime",
			Theatres: []Theatre{
				{Name: "Regal", Location: "Suburb"},
				{Name: "Cineplex", Location: "Downtown"},
			},
		},
		{
			Title: "Pulp Fiction",
			Genre: "Crime",
			Theatres: []Theatre{
				{Name: "AMC", Location: "Uptown"},
				{Name: "Regal", Location: "Suburb"},
			},
		},
	}

	r.GET("/", func(c *gin.Context) {
		c.HTML(http.StatusOK, "index.html", gin.H{
			"movies": movies,
		})
	})

	r.GET("/theatres/:movie", func(c *gin.Context) {
		movieTitle := c.Param("movie")
		for _, movie := range movies {
			if movie.Title == movieTitle {
				c.HTML(http.StatusOK, "theatres.html", gin.H{
					"theatres": movie.Theatres,
					"movietitle": movie.Title,
				})
				return
			}
		}
		c.String(http.StatusNotFound, "Movie not found")
	})

	r.POST("/book-ticket", func(c *gin.Context) {
		movie := c.PostForm("movie")
		theatre := c.PostForm("theatre")
		fmt.Println("Movie:", movie)
		fmt.Println("Theatre:", theatre)
		c.HTML(http.StatusOK, "booking.html", gin.H{
			"movie":   movie,
			"theatre": theatre,
		})
	})

	r.Run(":8080")
}