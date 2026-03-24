# ---- Build stage ----
# Install compiled dependencies here so the final image doesn't need build tools
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build deps for psycopg binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Run stage ----
FROM python:3.12-slim

WORKDIR /app

# Runtime library for psycopg
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

COPY worker.py config.py ./

# Non-root user — principle of least privilege
RUN useradd --no-create-home --shell /bin/false worker
USER worker

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import boto3; print('ok')" || exit 1

CMD ["python", "worker.py"]
