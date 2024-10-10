from fastapi import FastAPI,HTTPException,Response
from pymongo import MongoClient
from pydantic import BaseModel
import httpx
import os

from prometheus_client import Counter, Gauge, Histogram, generate_latest
from prometheus_client import CONTENT_TYPE_LATEST
import time 

class Movie(BaseModel):
    name: str
    genre: str | None = None
    stars: str
    theatres: list | None = None # aan be empty

mongoUser = os.environ['MONGO_USER']
mongoPassword = os.environ['MONGO_PASSWORD']
mongoUrl = os.environ['MONGO_URL']
mongoPort = os.environ['MONGO_PORT']
theatreUrl = os.environ['THEATRE_URL']
theatrePort = os.environ['THEATRE_PORT']

app = FastAPI()

REQUESTS = Counter('http_requests_total', 'Total HTTP Requests', ['method', 'endpoint', 'status'])
MOVIE_COUNT = Gauge('movies_count', 'Number of movies in the database')
REQUEST_LATENCY = Histogram(
    'request_latency_seconds', 
    'Latency of requests in seconds', 
    ['method', 'endpoint']
)

MOVIES_CREATED = Counter('movies_created', 'Total movies added to the db')

def get_database():
 
   # Provide the mongodb atlas url to connect python to mongodb using pymongo
   CONNECTION_STRING = f"mongodb://{mongoUser}:{mongoPassword}@{mongoUrl}:{mongoPort}"
 
   # Create a connection using MongoClient. You can import MongoClient or use pymongo.MongoClient
   client = MongoClient(CONNECTION_STRING)
   return client['movies']

db = get_database()

@app.middleware("http")
async def measure_latency(request, call_next):
    method = request.method
    endpoint = request.url.path
    start_time = time.time()
    
    response = await call_next(request)
    request_duration = time.time() - start_time
    REQUEST_LATENCY.labels(method, endpoint).observe(request_duration) 
    return response

@app.get("/metrics")
def metrics():
    REQUESTS.labels(method='GET', endpoint='/metrics', status='2xx').inc()
    return Response(generate_latest(), media_type="text/plain")


@app.get("/ping")
async def root():
    REQUESTS.labels(method='GET', endpoint='/ping', status='2xx').inc()
    return {"message": "pong"}

@app.get("/ready")
async def root():
    REQUESTS.labels(method='GET', endpoint='/ready', status='2xx').inc()
    return {"message": "ready"}

@app.get("/started")
async def root():
    REQUESTS.labels(method='GET', endpoint='/started', status='2xx').inc()
    return {"message": "started"}

@app.get("/movies")
async def movies():
    REQUESTS.labels(method='GET', endpoint='/movies', status='2xx').inc()
    collection_name = db["movies"]
    result = collection_name.find()
    movies = []
    for doc in result:
        doc['_id'] = str(doc['_id'])
        movie = {}
        movie["title"] = doc["name"]
        movie["theatres"] = doc["theatres"]
        movie["genre"] = doc["genre"]
        movies.append(movie)
    MOVIE_COUNT.set(len(movies))
    return movies

@app.get("/movies/{movie}")
async def getmovie(movie):
    REQUESTS.labels(method='GET', endpoint='/movies/<movie>', status='2xx').inc()
    collection_name = db["movies"]
    result = collection_name.find_one({"movie_name": movie})
    return {"message": result}


@app.post("/movies")
async def create_movie(movie: Movie):
    
    collection_name = db["movies"]
   
    theatresrequest = httpx.get(f'http://{theatreUrl}:{theatrePort}/theatres')
    theatreslist = theatresrequest.json()

    theatres = []
    for theatre in theatreslist:
        theatreentry = {"name": theatre["name"], "location": theatre["location"]}
        theatres.append(theatreentry)
    print(theatres)
    moviejson = {
    "name" : movie.name,
    "genre" : movie.genre,
    "stars" : movie.stars,
    "theatres": theatres
    }
    collection_name.insert_one(moviejson)
    MOVIES_CREATED.inc()
    REQUESTS.labels(method='POST', endpoint='/movies', status='2xx').inc()
    return {"message": movie}