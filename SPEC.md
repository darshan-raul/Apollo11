# Apollo Airlines — Application Specification

## Purpose

A cloud-native airline reservation platform designed specifically for teaching:

- Docker
- Kubernetes (networking, storage, security, scheduling)
- Observability (Prometheus, Grafana, OpenTelemetry)
- Service Mesh (Linkerd)
- GitOps (ArgoCD)
- Multi-Cluster Operations (EKS / GKE)

The application is simple enough for beginners at Launchpad but complex enough to demonstrate real-world cloud-native operational challenges by Stage 11.

---

## Changelog from v1.1

| Area | Change | Reason |
|---|---|---|
| Kafka | Removed | Not needed for the learning path |
| Stages | Remapped to Apollo11 stage numbers | Align with existing 13-phase structure |
| Redis | Present from Launchpad | Notification service uses it from day 1 |
| Frontend | Served via NGINX in Docker, no npm on host | All builds happen in Docker |
| Test scripts | Per-stage verification scripts | Each stage has a `test/stageN_test.sh` |

---

## Service Inventory

| Service | Role | Language | Database |
|---|---|---|---|
| identity | Auth + passenger management | Python/FastAPI | PostgreSQL |
| flight | Flight inventory + seat management | Go/Gin | PostgreSQL |
| booking | Reservations (flagship service) | Go/Gin | PostgreSQL |
| search | Optimised flight search | Go/Gin | None (Redis from Stage 7) |
| notification | Event fan-out | Go/Gin | None (Redis from Launchpad) |
| frontend | React SPA (Tailwind CSS) | None | Served via NGINX, VITE env vars for API URLs |

Infrastructure (auto-provisioned via Docker Compose init or k8s StatefulSets):

| Service | Type | Version |
|---|---|---|
| identity-db | PostgreSQL | 15 |
| flight-db | PostgreSQL | 15 |
| booking-db | PostgreSQL | 15 |
| redis | Redis | 7 |

**Total: 10 components in Launchpad.**

---

## Stage Mapping (Apollo11 Aligned)

| Apollo11 Stage | Focus | What's Deployed |
|---|---|---|
| Launchpad | Docker Compose | All 10 components, stub code |
| Ignition | kind cluster | — |
| Stage 1 (Liftoff) | K8s: Deployments, ConfigMaps, Secrets, Jobs | All 10 components on cluster |
| Stage 2 (Guidance/N&C) | K8s: Namespaces, DNS, NetworkPolicies, Ingress | Network isolation, Traefik Ingress |
| Stage 3 (Mission Data) | K8s: StatefulSets, PVCs, init containers | DBs become StatefulSets |
| Stage 4 (Flight Control) | K8s: Probes, resource limits, QoS | Code adds `/healthz/startup`, `/healthz/live`, `/healthz/ready` |
| Stage 5 (Payload Integration) | K8s: Helm, Kustomize, GitHub Actions | Packaging + CI/CD |
| Stage 6 (Mission Ops) | K8s: Prometheus, Grafana, OTEL | Code adds `/metrics`, OTEL SDK |
| Stage 7 (Orbital Maneuvering) | K8s: HPA, VPA, Redis cache | Search gets Redis caching |
| Stage 8 (Command Module) | K8s: RBAC, SecurityContext, OPA | Code: non-root, service accounts |
| Stage 9 (Lunar Orbit) | Cloud: Terraform for EKS + GKE | Cloud provisioning |
| Stage 10 (Mission Extensions) | K8s: Linkerd, Argo Rollouts, Chaos Mesh | Service mesh + progressive delivery |
| Stage 11 (Towards Mars) | K8s: CRDs, Operators, k3s, KEDA | Custom operator, event-driven scaling |

---

## Cross-Cutting Standards

Every service must implement the following from Launchpad onward. These are not added later — they exist in the codebase from the beginning. K8s stages configure them, not create them.

### Health Endpoints

```http
GET /healthz
```

Liveness probe. Returns `200 OK` if the process is alive.

```http
GET /readyz
```

Readiness probe. Returns `200 OK` only when all dependencies (DB connections, downstream service reachability) are healthy. Returns `503` otherwise.

---

### Metrics Endpoint

```http
GET /metrics
```

Prometheus-compatible metrics. Exposed on every service from Launchpad.

Minimum required metrics:

```text
http_requests_total          (counter)
http_request_duration_ms     (histogram)
db_connections_active        (gauge, stateful services only)
```

---

### Logging Standard

All services emit structured JSON logs.

```json
{
  "timestamp": "2025-01-15T10:23:00Z",
  "level": "INFO",
  "service": "booking-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "message": "Booking created",
  "booking_reference": "AA-2025-XK9"
}
```

`trace_id` and `span_id` are present from Launchpad. They carry no value until OpenTelemetry is wired in at Stage 6, but the field must exist so that no code changes are required at that stage.

---

### Request ID Propagation

Every inbound HTTP request must be assigned a `X-Request-ID` header if one is not already present. This header is forwarded to all downstream calls.

---

## Identity Service

### Purpose

Unified authentication and passenger management. The single source of truth for all user identity, credentials, and profile data.

No other service owns or stores user data.

### Database

PostgreSQL (identity-db, port 5432)

---

### Tables

#### users

```sql
CREATE TABLE users (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(255) UNIQUE NOT NULL,
    password_hash    VARCHAR(255) NOT NULL,
    first_name       VARCHAR(100),
    last_name        VARCHAR(100),
    passport_number  VARCHAR(50),
    loyalty_tier     VARCHAR(20) DEFAULT 'STANDARD',
    role             VARCHAR(20) DEFAULT 'PASSENGER',
    is_active        BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);
```

---

### Roles

```text
PASSENGER    — default role, can search and book flights
ADMIN        — can create and update flights, view all bookings
```

### Loyalty Tiers

```text
STANDARD
SILVER
GOLD
PLATINUM
```

Tier is set manually by admin for now. No automatic upgrade logic. Exists to make the user profile feel real and to give OTEL traces meaningful attributes.

---

### JWT Specification

```text
Algorithm:  HS256
Expiry:     24 hours
Claims:
  sub       — user UUID
  email     — user email
  role      — PASSENGER | ADMIN
  tier      — loyalty tier
  iat       — issued at
  exp       — expiry
```

The JWT signing secret is an environment variable: `JWT_SECRET`.

All other services validate the JWT **locally** by verifying the signature using `JWT_SECRET`. They do not call Identity Service for JWT validation.

---

### APIs

#### Register

```http
POST /api/users/register
```

Request

```json
{
  "email": "john@example.com",
  "password": "secret123",
  "firstName": "John",
  "lastName": "Doe",
  "passportNumber": "AB123456"
}
```

Response `201`

```json
{
  "id": "uuid",
  "email": "john@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "loyaltyTier": "STANDARD",
  "role": "PASSENGER"
}
```

---

#### Login

```http
POST /api/users/login
```

Request

```json
{
  "email": "john@example.com",
  "password": "secret123"
}
```

Response `200`

```json
{
  "token": "jwt-token",
  "expiresAt": "2025-01-16T10:00:00Z"
}
```

---

#### Get Profile

```http
GET /api/users/me
Authorization: Bearer <token>
```

Response `200`

```json
{
  "id": "uuid",
  "email": "john@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "passportNumber": "AB123456",
  "loyaltyTier": "STANDARD",
  "role": "PASSENGER"
}
```

---

#### Update Profile

```http
PUT /api/users/me
Authorization: Bearer <token>
```

Request (all fields optional)

```json
{
  "firstName": "Johnny",
  "lastName": "Doe",
  "passportNumber": "AB999999"
}
```

---

#### Get User by ID (Internal)

```http
GET /api/users/{id}
Authorization: Bearer <token>
```

Used by Booking Service to confirm a user account is active before creating a booking. Returns `404` if not found, `403` if `is_active = false`.

Admin role required, or the token subject must match the requested `id`.

---

## Flight Service

### Purpose

Owns and manages all flight inventory. The single source of truth for flight schedules, routes, and seat availability.

Seat availability is updated exclusively through Flight Service APIs. No other service writes to the flights table directly.

### Database

PostgreSQL (flight-db, port 5432)

---

### Tables

#### airports

```sql
CREATE TABLE airports (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code     VARCHAR(5) UNIQUE NOT NULL,
    name     VARCHAR(100),
    city     VARCHAR(100),
    country  VARCHAR(100)
);
```

#### flights

```sql
CREATE TABLE flights (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flight_number    VARCHAR(20) UNIQUE NOT NULL,
    origin           VARCHAR(5) REFERENCES airports(code),
    destination      VARCHAR(5) REFERENCES airports(code),
    departure_time   TIMESTAMP NOT NULL,
    arrival_time     TIMESTAMP NOT NULL,
    total_capacity   INT NOT NULL,
    available_seats  INT NOT NULL,
    status           VARCHAR(20) DEFAULT 'SCHEDULED',
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);
```

---

### Flight Status

```text
SCHEDULED   — default state
BOARDING    — gate open, boarding in progress
DELAYED     — departure pushed
DEPARTED    — aircraft airborne
ARRIVED     — flight completed
CANCELLED   — flight will not operate
```

Status is updated by admin via `PUT /api/flights/{id}`.

---

### APIs

#### Search Flights

```http
GET /api/flights
```

Query parameters

```text
origin        — IATA airport code (required)
destination   — IATA airport code (required)
date          — YYYY-MM-DD (required)
```

Response `200`

```json
{
  "flights": [
    {
      "id": "uuid",
      "flightNumber": "AA101",
      "origin": "BOM",
      "destination": "SIN",
      "departureTime": "2025-06-01T08:00:00Z",
      "arrivalTime": "2025-06-01T14:30:00Z",
      "availableSeats": 42,
      "status": "SCHEDULED"
    }
  ]
}
```

---

#### Get Flight

```http
GET /api/flights/{id}
```

Returns single flight object.

---

#### Create Flight (Admin)

```http
POST /api/flights
Authorization: Bearer <token>  (role: ADMIN)
```

Request

```json
{
  "flightNumber": "AA101",
  "origin": "BOM",
  "destination": "SIN",
  "departureTime": "2025-06-01T08:00:00Z",
  "arrivalTime": "2025-06-01T14:30:00Z",
  "totalCapacity": 180
}
```

`available_seats` is set to `totalCapacity` on creation.

---

#### Update Flight (Admin)

```http
PUT /api/flights/{id}
Authorization: Bearer <token>  (role: ADMIN)
```

Can update: `status`, `departureTime`, `arrivalTime`. Cannot directly update `available_seats` via this endpoint.

---

#### Update Seat Availability (Internal)

```http
PATCH /api/flights/{id}/seats
Authorization: Bearer <token>  (role: ADMIN or service-to-service)
```

Request

```json
{
  "delta": -1
}
```

`delta` is `-1` when a booking is confirmed (consume a seat), `+1` when a booking is cancelled (restore a seat).

Returns `409 Conflict` if `delta = -1` and `available_seats = 0`.

This is the only way seat availability changes. Booking Service calls this endpoint — it does not write to the flights table.

---

## Booking Service

### Purpose

Manages flight reservations. The most operationally complex service in the platform and the primary vehicle for teaching distributed systems concepts.

Booking Service is the flagship service for:

- OpenTelemetry distributed tracing (Stage 6)
- Service mesh traffic management (Stage 10)
- Load testing (Stage 9)
- Chaos/fault injection (Stage 10)

### Database

PostgreSQL (booking-db, port 5432)

---

### Tables

#### bookings

```sql
CREATE TABLE bookings (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_reference VARCHAR(20) UNIQUE NOT NULL,
    user_id           UUID NOT NULL,
    flight_id         UUID NOT NULL,
    seat_number       VARCHAR(10),
    status            VARCHAR(20) DEFAULT 'CONFIRMED',
    created_at        TIMESTAMP DEFAULT NOW(),
    updated_at        TIMESTAMP DEFAULT NOW()
);
```

`booking_reference` format: `AA-{YEAR}-{6 random alphanumeric uppercase}`. Example: `AA-2025-XK9P2M`.

---

### Booking Status

```text
CONFIRMED    — booking is active
CANCELLED    — booking cancelled by passenger or admin
```

---

### Dependencies and Call Model

```text
Identity Service   — verify user account is active (HTTP GET)
Flight Service     — check seat availability + update seats (HTTP GET + PATCH)
Notification Svc   — fire booking event (HTTP POST, synchronous in early stages)
```

**JWT validation is always local** — Booking Service verifies the token signature using the shared `JWT_SECRET`. It never calls Identity Service to validate a token. The call to Identity Service is only to confirm `is_active = true` on the user account.

---

### APIs

#### Create Booking

```http
POST /api/bookings
Authorization: Bearer <token>
```

Request

```json
{
  "flightId": "uuid"
}
```

Response `201`

```json
{
  "id": "uuid",
  "bookingReference": "AA-2025-XK9P2M",
  "flightId": "uuid",
  "userId": "uuid",
  "status": "CONFIRMED",
  "createdAt": "2025-01-15T10:23:00Z"
}
```

---

##### Create Booking — Execution Steps

This is the trace that students will see in Jaeger/Tempo at Stage 6.

```text
1. Validate JWT locally (verify signature, check expiry)
2. Extract user_id from JWT claims
3. Call Identity Service: GET /api/users/{user_id}
   → Abort with 403 if user not found or is_active = false
4. Call Flight Service: GET /api/flights/{flightId}
   → Abort with 404 if flight not found
   → Abort with 422 if flight status is CANCELLED or DEPARTED
5. Call Flight Service: PATCH /api/flights/{flightId}/seats { "delta": -1 }
   → Abort with 409 if no seats available
6. Generate booking_reference
7. Write booking record to Booking DB
8. Call Notification Service: POST /api/notify
9. Return 201 with booking object
```

Each step is a distinct span in the OTEL trace. Steps 3, 5, and 8 cross service boundaries and produce child spans in the downstream service.

---

#### Get Booking

```http
GET /api/bookings/{id}
Authorization: Bearer <token>
```

Passengers can only retrieve their own bookings. Admins can retrieve any booking.

---

#### My Bookings

```http
GET /api/bookings
Authorization: Bearer <token>
```

Returns all bookings for the authenticated user ordered by `created_at DESC`.

---

#### Cancel Booking

```http
DELETE /api/bookings/{id}
Authorization: Bearer <token>
```

##### Cancel Booking — Execution Steps

```text
1. Validate JWT locally
2. Fetch booking — abort 404 if not found
3. Verify booking belongs to token subject — abort 403 if not
4. Verify booking status is CONFIRMED — abort 422 if already CANCELLED
5. Update booking status to CANCELLED in Booking DB
6. Call Flight Service: PATCH /api/flights/{flightId}/seats { "delta": +1 }
7. Call Notification Service: POST /api/notify (BOOKING_CANCELLED)
8. Return 200
```

---

## Search Service

### Purpose

Provides an optimised, cacheable flight search endpoint that is intentionally decoupled from Flight Service.

Stateless. No database in Launchpad. Redis added in Stage 7.

### Why It Is a Separate Service

Search Service is the primary teaching target for:

```text
Horizontal Pod Autoscaler (HPA) — Stage 7
Canary deployments — Stage 10
Load testing (k6) — Stage 9
Service mesh traffic splitting — Stage 10
Response caching (Redis) — Stage 7
```

These demonstrations would pollute Flight Service if combined. The separation is intentional and justified by real-world practice: high-traffic read paths are routinely extracted from transactional services.

---

### Dependencies

```text
Flight Service   — HTTP GET (read only)
Redis            — optional cache (Stage 7+)
```

---

### APIs

#### Search

```http
GET /api/search
```

Query parameters

```text
origin        — IATA code (required)
destination   — IATA code (required)
date          — YYYY-MM-DD (required)
sort          — price | duration | departure  (optional, default: departure)
page          — integer (optional, default: 1)
limit         — integer (optional, default: 20, max: 100)
```

Response `200`

```json
{
  "results": [
    {
      "id": "uuid",
      "flightNumber": "AA101",
      "origin": "BOM",
      "destination": "SIN",
      "departureTime": "2025-06-01T08:00:00Z",
      "arrivalTime": "2025-06-01T14:30:00Z",
      "duration": 390,
      "availableSeats": 42,
      "status": "SCHEDULED"
    }
  ],
  "total": 3,
  "page": 1,
  "limit": 20
}
```

`duration` is in minutes. Calculated by Search Service from departure and arrival times.

---

### Caching Behaviour (Stage 7+)

```text
Cache key:    search:{origin}:{destination}:{date}
TTL:          5 minutes
Cache miss:   call Flight Service, populate cache, return result
Cache hit:    return cached result (add X-Cache: HIT header)
```

This makes cache behaviour observable in load test results and service mesh dashboards.

---

## Notification Service

### Purpose

Receives booking and flight events and dispatches notifications. Currently logs only.

Stateless. No database. Uses Redis for queue management from Launchpad.

---

### Event Types

```text
BOOKING_CONFIRMED    — passenger booked a flight
BOOKING_CANCELLED    — passenger cancelled a booking
FLIGHT_DELAYED       — flight departure pushed (admin triggered)
FLIGHT_CANCELLED     — flight cancelled (admin triggered)
FLIGHT_BOARDING      — flight now boarding (admin triggered)
```

---

### APIs

#### Notify

```http
POST /api/notify
```

Request

```json
{
  "type": "BOOKING_CONFIRMED",
  "recipient": "john@example.com",
  "payload": {
    "bookingReference": "AA-2025-XK9P2M",
    "flightNumber": "AA101",
    "origin": "BOM",
    "destination": "SIN",
    "departureTime": "2025-06-01T08:00:00Z"
  }
}
```

Response `202 Accepted`

---

### Current Behaviour

```text
Log the event as structured JSON
Return 202
```

No email is sent. No external system is called.

---

## Frontend

Technology: React with Tailwind CSS (served via NGINX in Docker — no npm required on host machine).

Build-time environment variables via VITE_IDENTITY_URL, VITE_FLIGHT_URL, VITE_BOOKING_URL, VITE_SEARCH_URL allow the same image to work in Docker Compose (localhost-based URLs) and Kubernetes (service-based URLs) environments.

Keep intentionally simple. The frontend is not the subject of the course. It must be functional enough that learners feel they are working with a real application.

---

### Pages

| Route | Purpose |
|---|---|
| `/login` | Email + password login |
| `/register` | New user registration |
| `/dashboard` | Authenticated landing page, upcoming bookings summary |
| `/search` | Flight search form + results |
| `/flights/{id}` | Flight details + Book button |
| `/bookings` | My bookings list |
| `/bookings/{id}` | Single booking detail + Cancel button |

---

## Primary Workflows

### Workflow 1 — Register

```text
Frontend → Identity Service → Identity DB
```

---

### Workflow 2 — Login

```text
Frontend → Identity Service → Identity DB → JWT returned
```

---

### Workflow 3 — Search Flights

```text
Frontend → Search Service → Flight Service → Flight DB
```

In Stage 7+, Search Service checks Redis before calling Flight Service.

---

### Workflow 4 — View Flight

```text
Frontend → Flight Service → Flight DB
```

---

### Workflow 5 — Create Booking (Flagship Workflow)

```text
Frontend
    │
    ▼
Booking Service ──► Identity Service  (is user active?)
    │
    ├──────────────► Flight Service   (get flight details)
    │
    ├──────────────► Flight Service   (decrement seats)
    │
    ├──────────────► Booking DB       (write booking)
    │
    └──────────────► Notification Svc (BOOKING_CONFIRMED)
```

This workflow generates the distributed trace that students observe in Jaeger/Tempo at Stage 6. Every arrow is a span. Every service boundary is a new span parent.

---

### Workflow 6 — Cancel Booking

```text
Frontend
    │
    ▼
Booking Service ──► Booking DB       (mark CANCELLED)
    │
    ├──────────────► Flight Service   (restore seat)
    │
    └──────────────► Notification Svc (BOOKING_CANCELLED)
```

---

## Seed Data

The following data must be present after a fresh `docker compose up`. Learners should not have to create flights or airports manually at any stage.

### Airports

| Code | Name | City | Country |
|---|---|---|---|
| BOM | Chhatrapati Shivaji Maharaj International | Mumbai | India |
| DEL | Indira Gandhi International | New Delhi | India |
| SIN | Changi Airport | Singapore | Singapore |
| DXB | Dubai International | Dubai | UAE |
| LHR | Heathrow Airport | London | UK |
| JFK | John F. Kennedy International | New York | USA |

---

### Flights (sample — scheduled from today + 30 days)

| Flight | Route | Departure | Seats |
|---|---|---|---|
| AA101 | BOM → SIN | 08:00 | 180 |
| AA102 | SIN → BOM | 20:00 | 180 |
| AA201 | DEL → DXB | 09:30 | 220 |
| AA202 | DXB → DEL | 22:00 | 220 |
| AA301 | BOM → LHR | 01:00 | 300 |
| AA401 | DEL → JFK | 02:00 | 280 |

Seed script must use deterministic UUIDs so that foreign keys are stable across resets.

---

### Users

| Email | Password | Role |
|---|---|---|
| `admin@apolloairlines.com` | `admin123` | ADMIN |
| `passenger@apolloairlines.com` | `pass123` | PASSENGER |

Passwords are stored as bcrypt hashes in the seed. Plain text values are only in this spec for learner reference.

---

## Observability Design

The trace students will observe at Stage 6 for a Create Booking request:

```text
Booking Service (root span)
    │
    ├── Identity Service: GET /api/users/{id}
    │
    ├── Flight Service: GET /api/flights/{id}
    │
    ├── Flight Service: PATCH /api/flights/{id}/seats
    │
    ├── Booking DB: INSERT bookings
    │
    └── Notification Service: POST /api/notify
```

Total spans for a successful booking: 6 spans across 3 services + 1 DB span.

This single trace demonstrates:

- Cross-service context propagation
- Database query timing
- Downstream dependency latency
- Failure points for fault injection (Stage 10)

---

## Stage-by-Stage Code Evolution

| Stage | Code Changes |
|---|---|
| Launchpad | Stub code — all services return hardcoded JSON. `/healthz`, `/readyz`, `/metrics` implemented. Structured logging with trace_id/span_id fields. Frontend: React/Tailwind CSS with VITE env var configuration for API URLs. |
| Stage 1 | (no code change — k8s deployment layer only) |
| Stage 2 | (no code change — networking layer only) |
| Stage 3 | (no code change — storage layer only) |
| Stage 4 | `/healthz/startup`, `/healthz/live`, `/healthz/ready` probe handlers. Graceful shutdown on SIGTERM. Frontend: Go stub replaced with React/Tailwind app (multi-stage Docker build). |
| Stage 5 | (no code change — packaging layer only) |
| Stage 6 | Full `/metrics` endpoint (Prometheus format). OTEL SDK integrated (traces + metrics). Trace context propagates through all calls. |
| Stage 7 | Search Service: Redis caching (key: `search:{origin}:{destination}:{date}`, TTL 5min). `X-Cache: HIT/MISS` header. |
| Stage 8 | Non-root user in all Dockerfiles. Service account annotations. |
| Stage 9 | (no code change — cloud provisioning layer only) |
| Stage 10 | (no code change — service mesh + progressive delivery) |
| Stage 11 | Custom operator for flight status management. KEDA scaledobject for booking service. Graceful shutdown fully implemented. |

---

## Port Map

| Service | Port | Notes |
|---|---|---|
| frontend | 3000 | React SPA |
| identity | 8080 | FastAPI |
| flight | 8081 | Go/Gin |
| booking | 8082 | Go/Gin |
| search | 8083 | Go/Gin |
| notification | 8084 | Go/Gin |
| identity-db | 5432 | PostgreSQL |
| flight-db | 5432 | PostgreSQL (separate PVC) |
| booking-db | 5432 | PostgreSQL (separate PVC) |
| redis | 6379 | Redis 7 |

---

## Docker Image Base Images

```text
Go services (flight, booking, search, notification):  golang:1.22-alpine
Python service (identity):                           python:3.12-slim
Frontend (React):                                     node:20-alpine
NGINX (for frontend serving):                         nginx:alpine
PostgreSQL:                                           postgres:15-alpine
Redis:                                                redis:7-alpine
```

---

## Kubernetes Namespace Structure

Starting Stage 1:

```text
apollo-airlines          — single namespace (stage1)
apollo-airlines-infra    — infra DBs (stage2 onward)
apollo-airlines-apps    — app services (stage2 onward)
apollo-airlines-ui      — frontend (stage2 onward)
```

---

## Test Scripts

Each stage has a `test/stageN_test.sh` that verifies:
- All expected k8s resources exist
- Services are healthy
- Network policies are in place
- Seed data is present
- Ingress routes work

Run with: `bash stages/stageN/test/stageN_test.sh`

---

## API Endpoint Summary

| Service | Method | Path | Auth | Description |
|---|---|---|---|---|
| identity | POST | /api/users/register | — | Register |
| identity | POST | /api/users/login | — | Login |
| identity | GET | /api/users/me | Bearer | Get own profile |
| identity | PUT | /api/users/me | Bearer | Update own profile |
| identity | GET | /api/users/{id} | Bearer | Get user by ID (internal) |
| flight | GET | /api/flights | — | Search flights |
| flight | GET | /api/flights/{id} | — | Get flight |
| flight | POST | /api/flights | ADMIN | Create flight |
| flight | PUT | /api/flights/{id} | ADMIN | Update flight |
| flight | PATCH | /api/flights/{id}/seats | ADMIN/service | Update seats |
| booking | POST | /api/bookings | Bearer | Create booking |
| booking | GET | /api/bookings/{id} | Bearer | Get booking |
| booking | GET | /api/bookings | Bearer | My bookings |
| booking | DELETE | /api/bookings/{id} | Bearer | Cancel booking |
| search | GET | /api/search | — | Search (proxied) |
| notification | POST | /api/notify | Bearer | Send notification |
| frontend | GET | / | — | Index |
| frontend | GET | /healthz | — | Health |
| all | GET | /readyz | — | Readiness |
| all | GET | /metrics | — | Prometheus metrics |

(End of file — total 1024 lines)