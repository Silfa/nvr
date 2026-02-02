import logging
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api.routers import cameras, events, system, stream

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# NVR Configuration Paths
NVR_CONFIG_DIR = os.getenv("NVR_CONFIG_DIR", "/etc/nvr")
NVR_BASE_DIR = os.getenv("NVR_BASE_DIR", "/usr/local/bin/nvr")

app = FastAPI(
    title="NVR Web API",
    description="API for Home NVR System",
    version="1.0.0",
    root_path="/nvr/api",  # Nginx handled prefix
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# CORS Configuration
origins = [
    "http://localhost",
    "http://nvr.local",
    "http://localhost:5173", # Vite Dev Server
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(system.router, prefix="/system", tags=["System"])
app.include_router(cameras.router, prefix="/cameras", tags=["Cameras"])
app.include_router(events.router, prefix="/events", tags=["Events"])
app.include_router(stream.router, prefix="/stream", tags=["Stream"])

@app.get("/")
async def root():
    return {"message": "NVR Web API is running"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
