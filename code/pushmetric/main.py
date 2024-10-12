import requests
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway
import os

theatre_url = os.environ['THEATRE_URL']
booking_url = os.environ['BOOKING_URL']
payment_url = os.environ['PAYMENT_URL']
movie_url = os.environ['MOVIE_URL']
pushgateway_url = os.environ['PUSHGATEWAY_URL']

# reference: https://prometheus.github.io/client_python/exporting/pushgateway/

url_to_check = "http://example.com/metrics"  # The endpoint you want to scrape
pushgateway_url = "http://localhost:9091"    # Pushgateway URL
job_name = "example_job"                     # Job name for Pushgateway

registry = CollectorRegistry()
theatre_count = Gauge('theatre_count', 'Number of Theatres in the system', registry=registry)

try:
    response = requests.get(theatre_url)

    # Extract some value from the response (assumes JSON response)
    value = response.json()

    theatre_count.set(value)

    push_to_gateway(pushgateway_url, job=pushgateway, registry=registry)

    print(f"Pushed metric with value {value} to {pushgateway_url}")

except requests.exceptions.RequestException as e:
    print(f"Error while making GET request: {e}")
