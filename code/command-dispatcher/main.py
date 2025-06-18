from fastapi import FastAPI, Request
import requests
import os

app = FastAPI()

LUNAR_MODULE_URL = os.getenv("LUNAR_MODULE_URL", "http://lunar-module:8080/command")

@app.post("/dispatch")
async def dispatch_command(request: Request):
    data = await request.json()
    # Relay to lunar module
    resp = requests.post(LUNAR_MODULE_URL, json=data)
    return {"status": "relayed", "lunar_module_response": resp.json()}
