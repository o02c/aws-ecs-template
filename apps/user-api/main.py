from fastapi import FastAPI

app = FastAPI(title="User API")


@app.get("/health")
def health():
    return {"status": "ok", "service": "user-api"}


@app.get("/api/users")
def list_users():
    return [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
    ]


@app.get("/api/users/{user_id}")
def get_user(user_id: int):
    return {"id": user_id, "name": f"User-{user_id}"}
