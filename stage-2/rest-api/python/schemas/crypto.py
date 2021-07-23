from pydantic import BaseModel

class Crypto(BaseModel):
    name: str
    price: int 
    percent: int

