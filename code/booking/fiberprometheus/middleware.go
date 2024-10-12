package fiberprometheus

// NOTE
// Below code is referred from: https://github.com/ansrivas/fiberprometheus/blob/master/middleware.go
// I have simplified it for the purposes of this code

import (
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/adaptor"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type FiberPrometheus struct {
	gatherer        prometheus.Gatherer
	requestsTotal   *prometheus.CounterVec
	requestDuration *prometheus.HistogramVec
	defaultURL      string
}

func create(registry prometheus.Registerer, serviceName, namespace, subsystem string, labels map[string]string) *FiberPrometheus {
	if registry == nil {
		registry = prometheus.NewRegistry()
	}

	constLabels := make(prometheus.Labels)
	if serviceName != "" {
		constLabels["service"] = serviceName
	}
	for label, value := range labels {
		constLabels[label] = value
	}

	counter := promauto.With(registry).NewCounterVec(
		prometheus.CounterOpts{
			Name:        prometheus.BuildFQName(namespace, subsystem, "requests_total"),
			Help:        "Count all http requests by status code, method and path.",
			ConstLabels: constLabels,
		},
		[]string{"status_code", "method", "path"},
	)

	histogram := promauto.With(registry).NewHistogramVec(prometheus.HistogramOpts{
		Name:        prometheus.BuildFQName(namespace, subsystem, "request_duration_seconds"),
		Help:        "Duration of all HTTP requests by status code, method and path.",
		ConstLabels: constLabels,
		Buckets: []float64{
			0.001, // 1ms
			0.002,
			0.005,
			0.01, // 10ms
			0.02,
			0.05,
			0.1, // 100 ms
			0.2,
			0.5,
			1.0, // 1s
			2.0,
			5.0,
			10.0, // 10s
			15.0,
			20.0,
			30.0,
		},
	},
		[]string{"status_code", "method", "path"},
	)

	// If the registerer is also a gatherer, use it, falling back to the
	// DefaultGatherer.
	gatherer, ok := registry.(prometheus.Gatherer)
	if !ok {
		gatherer = prometheus.DefaultGatherer
	}

	return &FiberPrometheus{
		gatherer:        gatherer,
		requestsTotal:   counter,
		requestDuration: histogram,
		defaultURL:      "/metrics",
	}
}

func New(serviceName, namespace, subsystem string) *FiberPrometheus {
	return create(nil, serviceName, namespace, subsystem, nil)
}
func (ps *FiberPrometheus) RegisterAt(app fiber.Router, url string, handlers ...fiber.Handler) {
	ps.defaultURL = url

	h := append(handlers, adaptor.HTTPHandler(promhttp.HandlerFor(ps.gatherer, promhttp.HandlerOpts{})))
	app.Get(ps.defaultURL, h...)
}

func (ps *FiberPrometheus) Middleware(ctx *fiber.Ctx) error {
	path := string(ctx.Request().RequestURI())

	if path == ps.defaultURL {
		return ctx.Next()
	}

	// Start metrics timer
	start := time.Now()
	method := ctx.Route().Method

	err := ctx.Next()

	// initialize with default error code
	// https://docs.gofiber.io/guide/error-handling
	status := fiber.StatusInternalServerError
	if err != nil {
		if e, ok := err.(*fiber.Error); ok {
			status = e.Code
		}
	} else {
		status = ctx.Response().StatusCode()
	}

	// Get status as string
	statusCode := strconv.Itoa(status)

	// Update total requests counter
	ps.requestsTotal.WithLabelValues(statusCode, method, path).Inc()

	// Update the request duration histogram
	elapsed := float64(float64(time.Since(start).Milliseconds()))
	ps.requestDuration.WithLabelValues(statusCode, method, path).Observe(elapsed)

	return err
}
