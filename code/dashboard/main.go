package dashboard

import (
	"encoding/json"
	"html/template"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	"github.com/gofiber/fiber/v2"
)

type Telemetry struct {
	Timestamp string
	Position  float64
	Speed     float64
	Status    string
	Received  string
}

func fetchTelemetry() []Telemetry {
	url := os.Getenv("TELEMETRY_URL")
	if url == "" {
		url = "http://telemetry:8000/data"
	}
	resp, err := http.Get(url)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	body, _ := ioutil.ReadAll(resp.Body)
	var result struct{ Data [][]interface{} }
	json.Unmarshal(body, &result)
	var out []Telemetry
	for _, row := range result.Data {
		out = append(out, Telemetry{
			Timestamp: row[0].(string),
			Position:  row[1].(float64),
			Speed:     row[2].(float64),
			Status:    row[3].(string),
			Received:  row[4].(string),
		})
	}
	return out
}

func main() {
	app := fiber.New()
	app.Get("/", func(c *fiber.Ctx) error {
		telemetry := fetchTelemetry()
		tmpl, _ := template.ParseFiles("templates/index.html")
		return tmpl.Execute(c.Response().BodyWriter(), telemetry)
	})
	log.Fatal(app.Listen(":8080"))
}
