from fastapi import FastAPI, Request
from datetime import datetime
import os
import uvicorn

app = FastAPI()

SERVICE_NAME = os.getenv("SERVICE_NAME", "python-service")

@app.get("/")
async def root(request: Request):
    return {
        "service": SERVICE_NAME,
        "message": "Hello from Python service! This is a public endpoint.",
        "timestamp": datetime.now().isoformat(),
        "user": get_user(request)
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/api/data")
async def api_data(request: Request):
    return {
        "service": SERVICE_NAME,
        "message": "API data endpoint - requires user or admin role",
        "timestamp": datetime.now().isoformat(),
        "user": get_user(request)
    }

@app.post("/api/data")
async def api_data_post(request: Request):
    return {
        "service": SERVICE_NAME,
        "message": "API data POST endpoint - requires admin role",
        "timestamp": datetime.now().isoformat(),
        "user": get_user(request)
    }

@app.get("/admin/users")
async def admin_users(request: Request):
    return {
        "service": SERVICE_NAME,
        "message": "Admin endpoint - requires admin role",
        "timestamp": datetime.now().isoformat(),
        "user": get_user(request)
    }

# ReBAC: Resource-based access control
# Pattern: /users/{user_id}/profile or /users/{user_id}/data
@app.get("/users/{user_id}/{resource}")
async def user_resource(user_id: str, resource: str, request: Request):
    return {
        "service": SERVICE_NAME,
        "message": f"Resource-based access: user {user_id}'s {resource} (OPA validates ownership)",
        "timestamp": datetime.now().isoformat(),
        "user": user_id
    }

def get_user(request: Request):
    auth = request.headers.get("authorization", "")
    return "authenticated-user" if auth else "anonymous"

if __name__ == "__main__":
    port = int(os.getenv("SERVICE_PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)