package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"
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

func main() {
	portNum64, _ := strconv.ParseInt(port, 10, 32)
	portNum := int(portNum64)
	psqlInfo := fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=disable",
		host, portNum, user, password, dbname)
	var err error
	db, err = sql.Open("postgres", psqlInfo)
	if err != nil {
		panic(err)
	}
	defer db.Close()
	app := fiber.New()

	app.Get("/ping", func(c *fiber.Ctx) error {
		return c.SendString("pong")
	})
	app.Get("/started", func(c *fiber.Ctx) error {
		return c.SendString("started")
	})
	app.Get("/ready", func(c *fiber.Ctx) error {
		return c.SendString("ready")
	})
	app.Get("/api/bookings", getAllBookings)
	app.Post("/api/bookings", createBooking)
	log.Fatal(app.Listen(":3000"))
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
	var movie_match bool = false
	var theatre_match bool = false
	for _, movie := range movies {
		if movie.Title == b.MovieName {
			fmt.Println("movie name matches")
			movie_match = true
		}
		for _, theatre := range movie.Theatres {
			theatre_url := fmt.Sprintf("http://%s:%s/theatres", theatre_host, theatre_port)
			resp, err := http.Get(theatre_url)
			if err != nil {
				fmt.Println("No response from request")
			}
			defer resp.Body.Close()
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				fmt.Println("No response from request")
			}
			var theatres []Theatre
			if err := json.Unmarshal(body, &theatres); err != nil {
				fmt.Println("Can not unmarshal JSON")
			}
			fmt.Println(theatres)
			if theatre.Name == b.TheatreName {
				fmt.Println("theatre name matches")
				theatre_match = true
			}
		}
	}
	if !movie_match {
		return c.Status(409).JSON(&fiber.Map{
			"success": false,
			"error":   "There is no such movie!",
		})
	}
	if !theatre_match {
		return c.Status(409).JSON(&fiber.Map{
			"success": false,
			"error":   "There is no such theatre!",
		})
	}

	sqlStatement := `
	INSERT INTO bookings (movie_name, theatre_name, price)
	VALUES ($1, $2, $3)
	RETURNING id`
	id := 0
	qerr := db.QueryRow(sqlStatement, b.MovieName, b.TheatreName, b.Price).Scan(&id)
	if qerr != nil {
		return err
	}
	fmt.Println("New record ID is:", id)
	m := make(map[string]int)

	m["id"] = id
	return c.JSON(m)
}

func getAllBookings(c *fiber.Ctx) error {
	bookings := &[]Booking{}

	sqlStatement := `SELECT movie_name,theatre_name,price FROM bookings`
	rows, err := db.Query(sqlStatement)
	if err != nil {
		panic(err)
	}
	defer rows.Close()
	for rows.Next() {
		booking := &Booking{}
		err = rows.Scan(&booking.MovieName, &booking.TheatreName, &booking.Price)
		if err != nil {
			panic(err)
		}
		*bookings = append(*bookings, *booking)
	}
	err = rows.Err()
	if err != nil {
		panic(err)
	}
	fmt.Println(bookings)
	if len(*bookings) == 0 {
		return c.Status(404).JSON(&fiber.Map{
			"success": false,
			"error":   "There are no bookings!",
		})
	}
	return c.JSON(*bookings)
}
