from fastapi import FastAPI
import uvicorn
import os
import time

app = FastAPI(title="analytics-service")

SERVICE_NAME = "analytics-service"
PORT = int(os.getenv("PORT", 3004))
START_TIME = time.time()

# Counters — will be populated when RabbitMQ consumer is added in Phase 6
events_processed = 0

@app.get("/health")
def health():
    return {"status": "ok", "service": SERVICE_NAME, "uptime_seconds": int(time.time() - START_TIME)}

@app.get("/metrics")
def metrics():
    # Prometheus text format
    lines = [
        "# HELP analytics_events_processed Total click events processed",
        "# TYPE analytics_events_processed counter",
        f"analytics_events_processed {events_processed}",
        "# HELP analytics_uptime_seconds Service uptime",
        "# TYPE analytics_uptime_seconds gauge",
        f"analytics_uptime_seconds {int(time.time() - START_TIME)}",
    ]
    from fastapi.responses import PlainTextResponse
    return PlainTextResponse("\n".join(lines) + "\n")

@app.get("/")
def root():
    return {
        "service": SERVICE_NAME,
        "status": "waiting for RabbitMQ consumer (Phase 6)",
        "events_processed": events_processed,
    }

if __name__ == "__main__":
    print(f"[{SERVICE_NAME}] running on :{PORT}")
    print(f"[{SERVICE_NAME}] RabbitMQ consumer will be added in Phase 6")
    uvicorn.run(app, host="0.0.0.0", port=PORT)
