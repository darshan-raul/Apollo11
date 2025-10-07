package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"

	// prometheus middleware
	"github.com/darshan-raul/Apollo11/booking/fiberprometheus"

	// for json logging
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

var (
	host         = os.Getenv("PSQL_HOST")
	port         = os.Getenv("PSQL_PORT")
	user         = os.Getenv("PSQL_USER")
	password     = os.Getenv("PSQL_PASSWORD")
	dbname       = os.Getenv("PSQL_DB")
	movie_host   = os.Getenv("MOVIE_HOST")
	movie_port   = os.Getenv("MOVIE_PORT")
	theatre_host = os.Getenv("THEATRE_HOST")
	theatre_port = os.Getenv("THEATRE_PORT")
)

var logger zerolog.Logger

type Booking struct {
	MovieName   string `json:"movie_name"`
	TheatreName string `json:"theatre_name"`
	Price       int    `json:"price"`
}
type Movie struct {
	Title    string    `json:"title"`
	Genre    string    `json:"genre"`
	Theatres []Theatre `json:"theatres"`
}
type Theatre struct {
	Name     string
	Location string
}

var db *sql.DB

func init() {

	// logging config
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// ref: https://programmingpercy.tech/blog/how-to-use-structured-json-logging-in-golang-applications/
	logger = log.With().
		Str("service", "booking").
		Logger()

	debug := os.Getenv("DEBUG_LEVEL")
	// Apply log level in the beginning of the application
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	if debug == "true" {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}

}

func main() {

	logger.Info().Msg("Booking app has started")
	portNum64, _ := strconv.ParseInt(port, 10, 32)
	portNum := int(portNum64)
	psqlInfo := fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=disable",
		host, portNum, user, password, dbname)
	var err error
	db, err = sql.Open("postgres", psqlInfo)
	if err != nil {
		logger.Fatal().AnErr("error when opening a db connection", err)
	}
	defer db.Close()
	app := fiber.New()

	// promethues instrumentation section
	prometheus := fiberprometheus.New("booking", "apollo11", "api")
	prometheus.RegisterAt(app, "/metrics")
	app.Use(prometheus.Middleware)

	app.Get("/ping", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Ping received")
		return c.SendString("pong")
	})
	app.Get("/started", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Ping received")
		return c.SendString("started")
	})
	app.Get("/ready", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Ping received")
		return c.SendString("ready")
	})
	app.Get("/api/bookings", getAllBookings)
	app.Post("/api/bookings", createBooking)
	logger.Fatal().AnErr("error", app.Listen(":3000"))
}

func createBooking(c *fiber.Ctx) error {

	b := new(Booking)

	if err := c.BodyParser(b); err != nil {
		return err
	}

	// check if movie exists
	movie_url := fmt.Sprintf("http://%s:%s/movies", movie_host, movie_port)
	resp, err := http.Get(movie_url)
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
		logger.Error().AnErr("Error while marshalling json from movie response", err)
	}

	logger.Info().Msg(fmt.Sprintf("Got following movies in response %s", movies))

	var movie_exists bool = false
	var theatre_exists bool = false
	var theatre_match bool = false

	for _, movie := range movies {
		if movie.Title == b.MovieName {
			logger.Info().Msg(fmt.Sprintf("Movie %s exists in the movie database", b.MovieName))
			movie_exists = true
		}
		for _, theatre := range movie.Theatres {
			theatre_url := fmt.Sprintf("http://%s:%s/theatres", theatre_host, theatre_port)
			resp, err := http.Get(theatre_url)
			if err != nil {
				logger.Error().AnErr("Error when connecting to theatre service", err)

			}
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				logger.Error().AnErr("Error parsing body from theatre service response", err)
			}
			var theatres []Theatre
			if err := json.Unmarshal(body, &theatres); err != nil {
				logger.Error().AnErr("Error while marshalling json from theatre response", err)

			}
			logger.Info().Msg(fmt.Sprintf("Got following theatres in response %s", theatres))

			for _, t := range theatres {
				if t.Name == b.TheatreName {
					theatre_exists = true
					logger.Info().Msg(fmt.Sprintf("Theatre %s exists in the theatre database", b.TheatreName))
					break
				}
			}

			if theatre.Name == b.TheatreName {
				logger.Info().Msg(fmt.Sprintf("Movie %s does have a screening at Theatre %s", b.MovieName, b.TheatreName))
			}
		}
	}
	if !movie_exists {
		return c.Status(409).JSON(&fiber.Map{
			"success": false,
			"error":   "There is no such movie!",
		})
	}
	if !theatre_exists {
		return c.Status(409).JSON(&fiber.Map{
			"success": false,
			"error":   "There is no such theatre!",
		})
	}
	if !theatre_match {
		return c.Status(409).JSON(&fiber.Map{
			"success": false,
			"error":   "The movie does not have any screening in this theatre!",
		})
	}

	sqlStatement := `
	INSERT INTO bookings (movie_name, theatre_name, price)
	VALUES ($1, $2, $3)
	RETURNING id`
	id := 0
	qerr := db.QueryRow(sqlStatement, b.MovieName, b.TheatreName, b.Price).Scan(&id)
	if qerr != nil {
		logger.Error().AnErr("Error while inserting booking record in db", err)
		return err
	}
	logger.Info().Msg(fmt.Sprintf("New booking record added to the database. id is %s", id))

	m := make(map[string]int)

	m["id"] = id
	return c.JSON(m)
}

func getAllBookings(c *fiber.Ctx) error {
	bookings := &[]Booking{}

	sqlStatement := `SELECT movie_name,theatre_name,price FROM bookings`
	rows, err := db.Query(sqlStatement)
	if err != nil {
		logger.Fatal().AnErr("error when running get all query", err)
	}
	defer rows.Close()
	for rows.Next() {
		booking := &Booking{}
		err = rows.Scan(&booking.MovieName, &booking.TheatreName, &booking.Price)
		if err != nil {
			logger.Fatal().AnErr("error scanning through booking db entries", err)
		}
		*bookings = append(*bookings, *booking)
	}
	err = rows.Err()
	if err != nil {
		logger.Fatal().AnErr("error when opening a db connection", err)
	}
	logger.Info().Msg(fmt.Sprintf("Got following bookings from db %s", bookings))
	if len(*bookings) == 0 {
		return c.Status(404).JSON(&fiber.Map{
			"success": false,
			"error":   "There are no bookings!",
		})
	}
	return c.JSON(*bookings)
}
