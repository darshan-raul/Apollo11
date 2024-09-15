package main

import (
	"bytes"
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
type BookingRequest struct {
	Movie   string `json:"movie_name"`
	Theatre string `json:"theatre_name"`
	Price   int    `json:"price"`
}
type BookingResult struct {
	Id int `json:"id"`
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
		// HTTP endpoint
		posturl := "http://booking:3000/api/bookings"

		data := BookingRequest{
			Movie:   movie,
			Theatre: theatre,
			Price:   50,
		}

		jsonData, err := json.Marshal(data)
		if err != nil {
			fmt.Println("Error marshaling data:", err)
			return
		}

		r, err := http.NewRequest("POST", posturl, bytes.NewBuffer(jsonData))
		if err != nil {
			panic(err)
		}
		r.Header.Add("Content-Type", "application/json")
		client := &http.Client{}
		res, err := client.Do(r)
		if err != nil {
			fmt.Println("Error sending request:", err)
			panic(err)
		}

		defer res.Body.Close()

		booking_res := &BookingResult{}

		derr := json.NewDecoder(res.Body).Decode(booking_res)
		if derr != nil {
			panic(derr)
		}
		if res.StatusCode != http.StatusOK {
			panic(res.Status)
		}
		fmt.Println("Id:", booking_res.Id)
		c.HTML(http.StatusOK, "booking.html", gin.H{
			"movie":   movie,
			"theatre": theatre,
			"id":      booking_res.Id,
		})
	})

	r.Run(":8080")
}
