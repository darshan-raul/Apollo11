from fastapi import Depends,FastAPI,HTTPException,Response
from sqlmodel import select
from sqlmodel import Session
from sqlalchemy.exc import SQLAlchemyError
from app.db import get_session, init_db

from app.models import Payment,PaymentCreate

from prometheus_client import Counter, Gauge, Histogram, generate_latest
from prometheus_client import CONTENT_TYPE_LATEST
import time 

app = FastAPI()

REQUESTS = Counter('http_requests_total', 'Total HTTP Requests', ['status','method', 'endpoint'])
PAYMENTS_COUNT = Counter('payment_count', 'Number of payments in the database')
REQUEST_LATENCY = Histogram(
    'request_latency_seconds', 
    'Latency of requests in seconds', 
    ['status','method', 'endpoint']
)

PAYMENTS_RECEIVED = Counter('payment_received', 'Total money received in payments')

@app.middleware("http")
async def measure_latency(request, call_next):
    method = request.method
    endpoint = request.url.path
    start_time = time.time()
    
    response = await call_next(request)
    request_duration = time.time() - start_time
    status = response.status_code
    
    REQUEST_LATENCY.labels(status, method, endpoint).observe(request_duration) 
    return response

@app.on_event("startup")
def on_startup():
    init_db()

@app.get("/started")
def check_db_readiness(session: Session = Depends(get_session)):
    try:
        # Perform a simple query
        session.exec(select(Payment).limit(1)).first()
        REQUESTS.labels(status='200', method='GET', endpoint='/started' ).inc()
        return {"status": "ready", "database": "up"}
    except SQLAlchemyError as e:
        REQUESTS.labels(status='503',method='GET', endpoint='/started' ).inc()
        raise HTTPException(status_code=503, detail=f"Database is not ready: {str(e)}")

@app.get("/metrics")
def metrics():
    REQUESTS.labels(status='200', method='GET', endpoint='/metrics').inc()
    return Response(generate_latest(), media_type="text/plain")

@app.get("/ready")
async def ready():
    REQUESTS.labels(status='200', method='GET', endpoint='/ready').inc()
    return {"yesiam": "ready!"}

@app.get("/ping")
async def pong():
    REQUESTS.labels(status='200', method='GET', endpoint='/ping').inc()
    return {"ping": "pong"}

@app.get("/payments", response_model=list[Payment])
def get_payments(session: Session = Depends(get_session)):
    result = session.execute(select(Payment))
    payments = result.scalars().all()
    REQUESTS.labels(status='200', method='GET', endpoint='/payments').inc()
    return [Payment(mode=payment.mode, price=payment.price, id=payment.id, status=payment.status) for payment in payments]

@app.get("/payments/{payment_id}", response_model=list[Payment])
def get_payments(payment_id,session: Session = Depends(get_session)):
    result = session.execute(select(Payment).where(Payment.id == payment_id))
    print(result)
    payment = result.scalars().all()
    print(payment)
    REQUESTS.labels(status='200', method='GET', endpoint='/payments/id').inc()

    return payment

@app.post("/payments")
def add_song(payment: PaymentCreate, session: Session = Depends(get_session)):
    payment = Payment(mode=payment.mode, price=payment.price, status=payment.status)
    session.add(payment)
    session.commit()
    session.refresh(payment)

    PAYMENTS_COUNT.inc()
    PAYMENTS_RECEIVED.inc(payment.price)
    REQUESTS.labels(status='200', method='POST', endpoint='/payments').inc()

    return payment