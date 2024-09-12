package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/gin-gonic/gin"
)

type Movie struct {
	Title    string    `json:"title"`
	Genre    string    `json:"genre"`
	Theatres []Theatre `json:"theatres"`
}

type Theatre struct {
	Name     string
	Location string
}

func main() {
	r := gin.Default()
	r.LoadHTMLGlob("templates/*")
	r.Static("/static", "./static")

	// movies := []Movie{
	// 	{
	// 		Title: "Inception",
	// 		Genre: "Sci-Fi",
	// 		Theatres: []Theatre{
	// 			{Name: "Cineplex", Location: "Downtown"},
	// 			{Name: "AMC", Location: "Uptown"},
	// 		},
	// 	},
	// 	{
	// 		Title: "The Godfather",
	// 		Genre: "Crime",
	// 		Theatres: []Theatre{
	// 			{Name: "Regal", Location: "Suburb"},
	// 			{Name: "Cineplex", Location: "Downtown"},
	// 		},
	// 	},
	// 	{
	// 		Title: "Pulp Fiction",
	// 		Genre: "Crime",
	// 		Theatres: []Theatre{
	// 			{Name: "AMC", Location: "Uptown"},
	// 			{Name: "Regal", Location: "Suburb"},
	// 		},
	// 	},
	// }

	r.GET("/", func(c *gin.Context) {
		resp, err := http.Get("http://movie:8000/movies")
		if err != nil {
			fmt.Println("No response from request")
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Println("No response from request")
		}
		var movies []Movie
		if err := json.Unmarshal(body, &movies); err != nil {
			fmt.Println("Can not unmarshal JSON")
		}
		fmt.Println(movies)

		c.HTML(http.StatusOK, "index.html", gin.H{
			"movies": movies,
		})
	})

	r.GET("/theatres/:movie", func(c *gin.Context) {
		movieTitle := c.Param("movie")
		resp, err := http.Get("http://movie:8000/movies")
		if err != nil {
			fmt.Println("No response from request")
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Println("No response from request")
		}
		var movies []Movie
		if err := json.Unmarshal(body, &movies); err != nil {
			fmt.Println("Can not unmarshal JSON")
		}
		fmt.Println(movies)
		for _, movie := range movies {
			if movie.Title == movieTitle {
				c.HTML(http.StatusOK, "theatres.html", gin.H{
					"theatres":   movie.Theatres,
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
