from fastapi import FastAPI
from pymongo import MongoClient
from pydantic import BaseModel
import os

class Movie(BaseModel):
    name: str
    genre: str | None = None
    stars: str

mongoUser = os.environ['MONGO_USER']
mongoPassword = os.environ['MONGO_PASSWORD']
mongoUrl = os.environ['MONGO_URL']

app = FastAPI()


def get_database():
 
   # Provide the mongodb atlas url to connect python to mongodb using pymongo
   CONNECTION_STRING = f"mongodb://{mongoUser}:{mongoPassword}@{mongoUrl}"
 
   # Create a connection using MongoClient. You can import MongoClient or use pymongo.MongoClient
   client = MongoClient(CONNECTION_STRING)
   return client['movies']

db = get_database()

@app.get("/")
async def root():
    return {"message": "pong"}

@app.get("/movies")
async def movies():
    collection_name = db["user_1_items"]
    result = collection_name.find()
    movies = []
    for doc in result:
        print(doc)
        doc['_id'] = str(doc['_id'])
        movies.append(doc)

    return {"message": movies}

@app.get("/movies/{movie}")
async def getmovie(movie):
    collection_name = db["user_1_items"]
    result = collection_name.find_one({"movie_name": movie})
    return {"message": result}


@app.post("/movies")
async def create_movie(movie: Movie):
    collection_name = db["user_1_items"]
    moviejson = {
    "name" : movie.name,
    "genre" : movie.genre,
    "stars" : movie.stars,
    }
    collection_name.insert_one(moviejson)
    return {"message": movie}