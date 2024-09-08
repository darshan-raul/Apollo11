package main

import (
	"database/sql"
	"fmt"
	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"
	"log"
)

const (
	host     = "localhost"
	port     = 5432
	user     = "apollo"
	password = "tothemoon"
	dbname   = "apollo11"
)

// func createBooking(db *sql.DB) {
// 	sqlStatement := `
// 	INSERT INTO bookings (movie_name, theatre_name, price)
// 	VALUES ($1, $2, $3)
// 	RETURNING id`
// 	id := 0
// 	err := db.QueryRow(sqlStatement, "godzilla", "inox", "56").Scan(&id)
// 	if err != nil {
// 		panic(err)
// 	}
// 	fmt.Println("New record ID is:", id)
// }

type Booking struct {
	Movie_name   string `json:"movie_name"`
	Theatre_name string `json:"theatre_name"`
	Price        string `json:"price"`
}

// func getBookings(db *sql.DB) *[]Booking {
// 	bookings := []Booking{}

// 	sqlStatement := `SELECT movie_name,theatre_name,price FROM bookings`
// 	rows, err := db.Query(sqlStatement)
// 	if err != nil {
// 		panic(err)
// 	}
// 	defer rows.Close()
// 	for rows.Next() {
// 		booking := Booking{}
// 		err = rows.Scan(&booking.movie_name, &booking.theatre_name, &booking.price)
// 		if err != nil {
// 			panic(err)
// 		}
// 		bookings = append(bookings, booking)
// 	}
// 	err = rows.Err()
// 	if err != nil {
// 		panic(err)
// 	}

// 	return &bookings

// }

var db *sql.DB


func main() {
	psqlInfo := fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=disable",
		host, port, user, password, dbname)
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

	log.Fatal(app.Listen(":3000"))
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
		err = rows.Scan(&booking.Movie_name, &booking.Theatre_name, &booking.Price)
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
