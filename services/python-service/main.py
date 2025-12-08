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

@app.get("/admin/users")
async def admin_users(request: Request):
    return {
        "service": SERVICE_NAME,
        "message": "Admin endpoint - requires admin role",
        "timestamp": datetime.now().isoformat(),
        "user": get_user(request)
    }

def get_user(request: Request):
    auth = request.headers.get("authorization", "")
    return "authenticated-user" if auth else "anonymous"

if __name__ == "__main__":
    port = int(os.getenv("SERVICE_PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
