package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	// for json logging
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
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

var moviehost string
var movieport string
var bookinghost string
var bookingport string
var logger zerolog.Logger

var (
	requestCountVec = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Number of HTTP requests processed, labeled by status code, method, and path.",
		},
		[]string{"status_code", "method", "path"},
	)

	requestDurationVec = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Duration of HTTP requests in seconds, labeled by status code, method, and path.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"status_code", "method", "path"},
	)
)

func init() {
	prometheus.MustRegister(requestCountVec, requestDurationVec)
	moviehost = os.Getenv("MOVIE_HOST")
	movieport = os.Getenv("MOVIE_PORT")
	bookingport = os.Getenv("BOOKING_PORT")
	bookinghost = os.Getenv("BOOKING_HOST")

	// logging config
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// ref: https://programmingpercy.tech/blog/how-to-use-structured-json-logging-in-golang-applications/
	logger = log.With().
		Str("service", "dashboard").
		Logger()

	debug := os.Getenv("DEBUG_LEVEL")
	// Apply log level in the beginning of the application
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	if debug == "true" {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}
}

func prometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.FullPath()
		method := c.Request.Method

		// Skip recording for /metrics path
		// else I have seen duplicate metric errors here
		if path == "/metrics" {
			c.Next()
			return
		}

		// first process the request then record the metrics
		c.Next()

		statusCode := fmt.Sprintf("%d", c.Writer.Status())
		duration := float64(time.Since(start).Milliseconds())

		requestCountVec.WithLabelValues(statusCode, method, path).Inc()
		requestDurationVec.WithLabelValues(statusCode, method, path).Observe(duration)
	}
}

func main() {
	r := gin.Default()
	r.LoadHTMLGlob("templates/*")
	r.Static("/static", "./static")

	// Apply Prometheus middleware for request metrics
	r.Use(prometheusMiddleware())

	// Serve Prometheus metrics endpoint at /metrics
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	r.GET("/ping", func(c *gin.Context) {
		logger.Debug().Msg("Ping received")
		c.JSON(http.StatusOK, gin.H{
			"message": "pong",
		})
	})

	r.GET("/ready", func(c *gin.Context) {
		logger.Debug().Msg("Ping received")
		c.JSON(http.StatusOK, gin.H{
			"message": "ready",
		})
	})

	r.GET("/started", func(c *gin.Context) {
		logger.Debug().Msg("Ping received")
		c.JSON(http.StatusOK, gin.H{
			"message": "started",
		})
	})

	r.GET("/", func(c *gin.Context) {
		movieUrl := fmt.Sprintf("http://%s:%s/movies", moviehost, movieport)
		resp, err := http.Get(movieUrl)
		if err != nil {
			logger.Error().AnErr("Error when connecting to movie service", err)
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			logger.Error().AnErr("Error parsing body from movie service response", err)
		}
		var movies []Movie
		if err := json.Unmarshal(body, &movies); err != nil {
			logger.Error().AnErr("Error while unmarshalling json from movie response", err)
		}
		logger.Info().Msg(fmt.Sprintf("Got following movies in response %s", movies))

		c.HTML(http.StatusOK, "index.html", gin.H{
			"movies": movies,
		})
	})

	r.GET("/theatres/:movie", func(c *gin.Context) {
		movieTitle := c.Param("movie")
		movieUrl := fmt.Sprintf("http://%s:%s/movies", moviehost, movieport)
		resp, err := http.Get(movieUrl)
		if err != nil {
			logger.Error().AnErr("Error when connecting to movie service", err)
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			logger.Error().AnErr("Error parsing body from movie service response", err)
		}
		var movies []Movie
		if err := json.Unmarshal(body, &movies); err != nil {
			logger.Error().AnErr("Error while unmarshalling json from movie response", err)

		}
		fmt.Println(movies)
		for _, movie := range movies {
			if movie.Title == movieTitle {
				logger.Info().Msg(fmt.Sprintf("Selected movie %s matches in the movies", movieTitle))

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

		logger.Info().Msg(fmt.Sprintf("Booking ticket for movie: %s", movie))
		logger.Info().Msg(fmt.Sprintf("Booking ticket for theatre: %s", theatre))

		posturl := fmt.Sprintf("http://%s:%s/api/bookings", bookinghost, bookingport)

		data := BookingRequest{
			Movie:   movie,
			Theatre: theatre,
			Price:   50, // TODO: keeping this static for now, later add logic to get this price from theatre service
		}

		jsonData, err := json.Marshal(data)
		if err != nil {
			logger.Error().AnErr("Error marshaling data:", err)
			return
		}

		r, err := http.NewRequest("POST", posturl, bytes.NewBuffer(jsonData))
		if err != nil {
			logger.Fatal().AnErr("error creating request for booking service", err)
		}
		r.Header.Add("Content-Type", "application/json")
		client := &http.Client{}
		res, err := client.Do(r)
		if err != nil {
			logger.Fatal().AnErr("Error sending request to booking service", err)
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
