# --- Stage 1 : builder -----------------------------------------------------
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# --- Stage 2 : image finale --------------------------------------------------
FROM python:3.12-slim
WORKDIR /app

RUN useradd --create-home --shell /bin/bash appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY app/ ./app/
RUN chown -R appuser:appuser /app

USER appuser
ENV PATH=/home/appuser/.local/bin:$PATH

# Cloud Run injecte $PORT (8080 par défaut) — l'app doit écouter dessus
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
