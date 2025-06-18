import requests
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
import os

theatre_url = os.environ['THEATRE_URL']
booking_url = os.environ['BOOKING_URL']
payment_url = os.environ['PAYMENT_URL']
movie_url = os.environ['MOVIE_URL']
pushgateway_url = os.environ['PUSHGATEWAY_URL']

# reference: https://prometheus.github.io/client_python/exporting/pushgateway/

registry = CollectorRegistry()
theatres_count = Gauge('theatres_count', 'Number of Theatres in the system', registry=registry)
payments_count = Gauge('payments_count', 'Number of Payments made in the system', registry=registry)
movies_count = Gauge('movies_count', 'Number of movies in the system', registry=registry)
bookings_count = Gauge('bookings_count', 'Number of bookings made in the system', registry=registry)

payments_len = 0
theatres_len = 0 
movies_len = 0
bookings_len = 0 

try:
    response = requests.get(f"http://{payment_url}/payments")
    if response.status_code == 200:
        payments_len = len(response.json())
    else:
        print("got non success code")

    response = requests.get(f"http://{theatre_url}/theatres")
    if response.status_code == 200:
        theatres_len = len(response.json())
    else:
        print("got non success code")

    response = requests.get(f"http://{movie_url}/movies")
    if response.status_code == 200:
        movies_len = len(response.json())
    else:
        print("got non success code")

    response = requests.get(f"http://{booking_url}/api/bookings")
    if response.status_code == 200:
        bookings_len = len(response.json())
    else:
        print("got non success code")

    payments_count.set(payments_len)
    theatres_count.set(theatres_len)
    movies_count.set(movies_len)
    bookings_count.set(bookings_len)

    push_to_gateway(pushgateway_url, job="pushgateway", registry=registry)
    print(f"Pushed metric with value {payments_len} to pushgateway")
    print(f"Pushed metric with value {theatres_len} to pushgateway")
    print(f"Pushed metric with value {movies_len} to pushgateway")
    print(f"Pushed metric with value {bookings_len} to pushgateway")

except requests.exceptions.RequestException as e:
    print(f"Error while making GET request: {e}")
