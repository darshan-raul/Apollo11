package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"strconv"

	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"
)

var (
	host     = os.Getenv("PSQL_HOST")
	port     = os.Getenv("PSQL_PORT")
	user     = os.Getenv("PSQL_USER")
	password = os.Getenv("PSQL_PASSWORD")
	dbname   = os.Getenv("PSQL_DB")
)

type Booking struct {
	MovieName   string `json:"movie_name"`
	TheatreName string `json:"theatre_name"`
	Price       string `json:"price"`
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

	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello, World!")
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

	sqlStatement := `
	INSERT INTO bookings (movie_name, theatre_name, price)
	VALUES ($1, $2, $3)`
	_, err := db.Exec(sqlStatement, b.MovieName, b.TheatreName, b.Price)
	if err != nil {
		return err
	}

	return nil
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
