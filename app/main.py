"""Orders API with request metrics and structured logs."""

import json
import logging
import os
import time
from datetime import datetime, timezone

import psycopg
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import Counter, CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel


DB_URL = os.environ.get(
    "DB_URL",
    "postgresql://app:app@localhost:5432/app",
)

app = FastAPI(title="Orders API")

requests_total = Counter(
    "http_requests_total",
    "Number of HTTP requests",
    ["method", "route", "status"],
)

request_log = logging.getLogger("orders.requests")
request_log.setLevel(logging.INFO)
request_log.addHandler(logging.StreamHandler())
request_log.propagate = False


class Order(BaseModel):
    amount: float
    status: str = "pending"


def _conn():
    return psycopg.connect(DB_URL)


@app.middleware("http")
async def record_request(request: Request, call_next):
    if request.url.path == "/metrics":
        return await call_next(request)

    started = time.perf_counter()
    status = 500

    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = getattr(request.scope.get("route"), "path", "unmatched")

        requests_total.labels(
            method=request.method,
            route=route,
            status=str(status),
        ).inc()

        request_log.info(json.dumps({
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "event": "request",
            "method": request.method,
            "route": route,
            "status": status,
            "duration_ms": round(
                (time.perf_counter() - started) * 1000, 2
            ),
        }))


@app.get("/health")
def health():
    try:
        with _conn() as conn:
            conn.execute("SELECT 1")
        return {"status": "ok"}
    except psycopg.Error as exc:
        raise HTTPException(
            status_code=503,
            detail="Database unavailable",
        ) from exc


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(
        content=generate_latest(),
        headers={"Content-Type": CONTENT_TYPE_LATEST},
    )


@app.get("/orders")
def list_orders():
    with _conn() as conn:
        rows = conn.execute(
            "SELECT id, amount, status FROM orders ORDER BY id"
        ).fetchall()

    return [
        {"id": row[0], "amount": float(row[1]), "status": row[2]}
        for row in rows
    ]


@app.post("/orders")
def create_order(order: Order):
    with _conn() as conn:
        row = conn.execute(
            """
            INSERT INTO orders (amount, status)
            VALUES (%s, %s)
            RETURNING id
            """,
            (order.amount, order.status),
        ).fetchone()
        conn.commit()

    return {
        "id": row[0],
        "amount": order.amount,
        "status": order.status,
    }