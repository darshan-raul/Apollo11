FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN addgroup --system apollo \
    && adduser --system --ingroup apollo --no-create-home apollo

COPY --chown=apollo:apollo . .

EXPOSE 8080

USER apollo

# main.py runs uvicorn with a 30 s graceful-shutdown timeout and logs SIGTERM.
CMD ["python", "main.py"]
