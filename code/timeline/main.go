package timeline

import (
	"database/sql"
	"log"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"
)

type Event struct {
	ID   int       `json:"id"`
	Name string    `json:"name"`
	Time time.Time `json:"time"`
}

func main() {
	db, err := sql.Open("postgres", os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	app := fiber.New()

	app.Get("/data", func(c *fiber.Ctx) error {
		rows, _ := db.Query("SELECT id, name, time FROM events ORDER BY time ASC")
		var events []Event
		for rows.Next() {
			var e Event
			rows.Scan(&e.ID, &e.Name, &e.Time)
			events = append(events, e)
		}
		return c.JSON(events)
	})

	app.Post("/input", func(c *fiber.Ctx) error {
		var e Event
		if err := c.BodyParser(&e); err != nil {
			return err
		}
		db.Exec("INSERT INTO events (name, time) VALUES ($1, $2)", e.Name, e.Time)
		return c.SendStatus(201)
	})

	log.Fatal(app.Listen(":8080"))
}
