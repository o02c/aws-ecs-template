from fastapi import FastAPI

app = FastAPI(title="Admin API")


@app.get("/health")
def health():
    return {"status": "ok", "service": "admin-api"}


@app.get("/api/dashboard")
def dashboard():
    return {"total_users": 42, "active_sessions": 7}


@app.get("/api/settings")
def settings():
    return {"maintenance_mode": False, "log_level": "info"}
