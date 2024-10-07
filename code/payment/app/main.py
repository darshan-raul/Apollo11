from fastapi import Depends,FastAPI,HTTPException,Response
from sqlmodel import select
from sqlmodel import Session
from sqlalchemy.exc import SQLAlchemyError
from app.db import get_session, init_db

from app.models import Payment,PaymentCreate

from prometheus_client import Counter, Gauge, generate_latest
from prometheus_client import CONTENT_TYPE_LATEST

app = FastAPI()

GET_REQUESTS = Counter('get_requests_total', 'Total number of GET requests')


@app.on_event("startup")
def on_startup():
    init_db()


@app.get("/started")
def check_db_readiness(session: Session = Depends(get_session)):
    GET_REQUESTS.inc()
    try:
        # Perform a simple query
        session.exec(select(Payment).limit(1)).first()
        return {"status": "ready", "database": "up"}
    except SQLAlchemyError as e:
        raise HTTPException(status_code=503, detail=f"Database is not ready: {str(e)}")

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type="text/plain")

@app.get("/ready")
async def ready():
    GET_REQUESTS.inc()
    return {"yesiam": "ready!"}

@app.get("/ping")
async def pong():
    GET_REQUESTS.inc()
    return {"ping": "pong!"}

@app.get("/payments", response_model=list[Payment])
def get_payments(session: Session = Depends(get_session)):
    GET_REQUESTS.inc()
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