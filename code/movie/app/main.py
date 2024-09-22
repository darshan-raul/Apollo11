from fastapi import FastAPI
from pymongo import MongoClient
from pydantic import BaseModel
import httpx
import os

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


def get_database():
 
   # Provide the mongodb atlas url to connect python to mongodb using pymongo
   CONNECTION_STRING = f"mongodb://{mongoUser}:{mongoPassword}@{mongoUrl}:{mongoPort}"
 
   # Create a connection using MongoClient. You can import MongoClient or use pymongo.MongoClient
   client = MongoClient(CONNECTION_STRING)
   return client['movies']

db = get_database()

@app.get("/ping")
async def root():
    return {"message": "pong"}

@app.get("/ready")
async def root():
    return {"message": "ready"}

@app.get("/started")
async def root():
    return {"message": "started"}

@app.get("/movies")
async def movies():
    collection_name = db["user_1_items"]
    result = collection_name.find()
    movies = []
    for doc in result:
        doc['_id'] = str(doc['_id'])
        movie = {}
        movie["title"] = doc["name"]
        movie["theatres"] = doc["theatres"]
        movie["genre"] = doc["genre"]
        movies.append(movie)
    return movies

@app.get("/movies/{movie}")
async def getmovie(movie):
    collection_name = db["user_1_items"]
    result = collection_name.find_one({"movie_name": movie})
    return {"message": result}


@app.post("/movies")
async def create_movie(movie: Movie):
    collection_name = db["user_1_items"]
   
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
    return {"message": movie}