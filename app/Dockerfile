FROM python:3.12-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY src/ ./src/

RUN adduser --disabled-password --gecos "" appuser && \
    chown -R appuser:appuser /app
USER appuser

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health').raise_for_status()"

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
