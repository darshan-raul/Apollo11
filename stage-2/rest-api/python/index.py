from fastapi import FastAPI
from routes.index import user
app = FastAPI()

app.include_router(user)