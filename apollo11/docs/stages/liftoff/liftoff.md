
This is where it all begins!

- Although the main agenda of this tutorial is to understand how to levarage all the useful tools in the cloud native ecosystem, we will be needing a good enough test application to work on to really understand their workings and advantages.
- It could not be any hello world app as there was no scope to create microservices around it nor could it be a very sofisticated multi usecase app. Henced I turned my hobby of boxoffice tracking and created a simple movie ticket booking app. I have purposely kept the workflow dead simple and used shortcuts compared to the realworld application flow to avoid complexity. 
- The flow has been designed in such a way that we can easily leverage service mesh, logging, tracing, metrics and many more features we will be visiting along the way.

## Components

The architecture consists of following:

| Name | Language/Db |
|---|---|
| Dashboard frontend |  Golang,htmx,gin |
| Movie api |  Python, Fastapi |
| Movie db |   MongoDb|
| Theatre api |  Golang, Fiber  |
| Theatre db |   MongoDb|
| Booking api |  Golang, Fiber |
| Booking db |   Postgres |
| Payment api |   Python, Fastapi |
| Payment db |   Mysql |

> You **donot** need to worry if you are not accustomed with any of the this languages or libraries. The code has been kept dead easy purposefully and you will not need to even look at it if all goes well but if you may have to, it will be easy to troubleshoot. For any one coming from a programming background, this will be right up your sleeve

## Workflow

Here's the workflow we will be following

``` mermaid
sequenceDiagram
  actor Customer
  participant App
  participant Movie
  actor MovieAdmin
  participant Theatre
  participant Booking
  autonumber
  MovieAdmin->>Movie: Add movie
  Note over MovieAdmin,Movie: At the start and whenever new movies are added
  Movie->>Theatre: Check all available theatres
  Movie->>Movie: Add the movie and theatre listing in db
  Customer->>App: Opens website
  App->>Movie: Get movie list
  Movie->>App: Send back movie and its theatreslist
  Customer->>App: Select movie
  App->>Booking: Send selected movie and theatre
  Booking->>Movie: Check if movie is valid
  Booking->>Theatre: Check if theatre is valid
  Booking->>App: Share status of booking
  App->>Payment: Make payment for the booking
  Payment->>App: Payment successful
  App->>Booking: Confirm booking
  Booking->>App: Booking confirmed enjoy!
```

We will be skipping any local setup and directly setup everything in docker. You donot need to install any dependency like python,go

# Running locally with docker

## Prereqs:

- ensure docker is installed


## Run the stack

- `docker compose up --watch`
- This command will ensure that all the components are up and if you change anything in the codebase of the microservices, their images are rebuild automatically

    