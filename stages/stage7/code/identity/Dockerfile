FROM python:3.12.15-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN groupadd --system --gid 10001 apollo \
    && useradd --system --uid 10001 --gid apollo --no-create-home apollo

COPY --chown=10001:10001 . .

EXPOSE 8080

# Numeric UID so Kubernetes runAsNonRoot can verify it (Stage 8).
USER 10001:10001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]