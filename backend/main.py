"""
FruitTreeScanner Backend - FastAPI Application
"""

from fastapi import FastAPI, HTTPException, UploadFile, File, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from api.routes import router as api_router
from core.config import settings
from core.database import init_db, close_db
from core.redis import init_redis, close_redis

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    logger.info("Starting FruitTreeScanner Backend...")
    await init_db()
    await init_redis()
    yield
    logger.info("Shutting down FruitTreeScanner Backend...")
    await close_db()
    await close_redis()


app = FastAPI(
    title="FruitTreeScanner API",
    description="Backend API for FruitTreeScanner iOS app - LiDAR point cloud storage, processing, and yield estimation",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routes
app.include_router(api_router, prefix="/api/v1")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "version": "1.0.0"}


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "name": "FruitTreeScanner API",
        "version": "1.0.0",
        "docs": "/docs",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
