from fastapi import FastAPI
from routes.index import crypto

app = FastAPI()

app.include_router(crypto)