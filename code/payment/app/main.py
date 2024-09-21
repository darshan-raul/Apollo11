from fastapi import Depends,FastAPI
from sqlmodel import select
from sqlmodel import Session

from app.db import get_session, init_db

from app.models import Payment,PaymentCreate

app = FastAPI()


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/started")
async def pong():
    return {"yesihave": "started"}

@app.get("/ready")
async def pong():
    return {"yesiam": "ready!"}

@app.get("/ping")
async def pong():
    return {"ping": "pong!"}

@app.get("/payments", response_model=list[Payment])
def get_payments(session: Session = Depends(get_session)):
    result = session.execute(select(Payment))
    payments = result.scalars().all()
    return [Payment(mode=payment.mode, price=payment.price, id=payment.id, status=payment.status) for payment in payments]

@app.get("/payments/{payment_id}", response_model=list[Payment])
def get_payments(payment_id,session: Session = Depends(get_session)):
    result = session.execute(select(Payment).where(Payment.id == payment_id))
    print(result)
    payment = result.scalars().all()
    print(payment)
    return payment

@app.post("/payments")
def add_song(payment: PaymentCreate, session: Session = Depends(get_session)):
    payment = Payment(mode=payment.mode, price=payment.price, status=payment.status)
    session.add(payment)
    session.commit()
    session.refresh(payment)
    return payment