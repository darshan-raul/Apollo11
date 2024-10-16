package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	// prometheus middleware
	"github.com/darshan-raul/Apollo11/theatre/fiberprometheus"

	// for json logging
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

var collection *mongo.Collection
var ctx = context.TODO()
var logger zerolog.Logger

type Theatre struct {
	ID        primitive.ObjectID `bson:"_id"`
	CreatedAt time.Time          `bson:"created_at"`
	UpdatedAt time.Time          `bson:"updated_at"`
	Name      string             `bson:"name"`
	Location  string             `bson:"location"`
	Seats     int                `bson:"seats"`
}
type TheatreRequest struct {
	Name     string `json:"name"`
	Location string `json:"location"`
	Seats    int    `json:"seats"`
}
type TheatreResponse struct {
	Name     string `json:"name"`
	Location string `json:"location"`
}

func init() {

	// logging config
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// ref: https://programmingpercy.tech/blog/how-to-use-structured-json-logging-in-golang-applications/
	logger = log.With().
		Str("service", "theatre").
		Logger()

	debug := os.Getenv("DEBUG_LEVEL")
	// Apply log level in the beginning of the application
	zerolog.SetGlobalLevel(zerolog.InfoLevel)
	if debug == "true" {
		zerolog.SetGlobalLevel(zerolog.DebugLevel)
	}

	// mongo db connectivity
	mongouser := os.Getenv("MONGO_USER")
	mongopass := os.Getenv("MONGO_PASSWORD")
	mongoauthdb := os.Getenv("MONGO_AUTH_DB")
	mongourl := os.Getenv("MONGO_URL")
	mongoport := os.Getenv("MONGO_PORT")
	credential := options.Credential{
		Username:   mongouser,
		Password:   mongopass,
		AuthSource: mongoauthdb,
	}
	mongouri := fmt.Sprintf("mongodb://%s:%s/", mongourl, mongoport)

	clientOptions := options.Client().ApplyURI(mongouri).
		SetAuth(credential)
	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		logger.Fatal().AnErr("error while creating db client", err)
	}
	err = client.Ping(ctx, nil)
	if err != nil {
		logger.Fatal().AnErr("error while pinging the db", err)
	}
	logger.Info().Msg("db connected")

	collection = client.Database("theatres").Collection("theatres")

}

func createTheatre(task *Theatre) error {
	_, err := collection.InsertOne(ctx, task)
	return err
}

func main() {

	logger.Info().Msg("Theatre app has started")
	app := fiber.New()

	// promethues instrumentation section
	prometheus := fiberprometheus.New("theatre", "apollo11", "api")
	prometheus.RegisterAt(app, "/metrics")
	app.Use(prometheus.Middleware)

	app.Get("/ping", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Ping received")

		return c.SendString("pong")
	})

	app.Get("/ready", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Ready call received")
		return c.SendString("iam ready")
	})

	app.Get("/started", func(c *fiber.Ctx) error {
		logger.Debug().Msg("Started call received")
		return c.SendString("i have started")
	})

	// get particular
	app.Get("/theatre/:theatrename", func(c *fiber.Ctx) error {

		filter := bson.D{
			primitive.E{Key: "name", Value: c.Params("theatrename")},
		}
		theatre, err := filterTheatres(filter)
		if err != nil {
			logger.Fatal().AnErr("error", err)
		}
		return c.JSON(theatre)
	})
	// get all
	app.Get("/theatres", func(c *fiber.Ctx) error {

		filter := bson.D{{}}
		theatres, err := filterTheatres(filter)
		if err != nil {
			logger.Fatal().AnErr("error", err)
		}

		var theatreList []any

		for _, theatre := range theatres {
			var m TheatreResponse
			m.Name = theatre.Name
			m.Location = theatre.Location

			theatreList = append(theatreList, m)
		}
		return c.JSON(theatreList)
	})

	app.Post("/theatre", func(c *fiber.Ctx) error {
		t := new(TheatreRequest)

		if err := c.BodyParser(t); err != nil {
			return err
		}

		logger.Info().Msg("recevied this name for the theatre" + t.Name)
		logger.Info().Msg("recevied this location for the theatre" + t.Location)

		theatre := &Theatre{
			ID:        primitive.NewObjectID(),
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
			Name:      t.Name,
			Location:  t.Location,
			Seats:     t.Seats,
		}

		createTheatre(theatre)
		return c.SendString("theatre created")
	})
	logger.Fatal().AnErr("error", app.Listen(":7000"))
}

func filterTheatres(filter interface{}) ([]*Theatre, error) {

	var theatres []*Theatre

	cur, err := collection.Find(ctx, filter)
	if err != nil {
		return theatres, err
	}

	for cur.Next(ctx) {
		var t Theatre
		err := cur.Decode(&t)
		if err != nil {
			return theatres, err
		}

		theatres = append(theatres, &t)
	}

	if err := cur.Err(); err != nil {
		return theatres, err
	}

	cur.Close(ctx)

	if len(theatres) == 0 {
		return theatres, mongo.ErrNoDocuments
	}

	return theatres, nil
}
