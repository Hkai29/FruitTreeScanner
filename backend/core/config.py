"""
Application configuration using Pydantic settings.
"""

from pydantic_settings import BaseSettings
from typing import List
import os


class Settings(BaseSettings):
    # Application
    APP_NAME: str = "FruitTreeScanner API"
    DEBUG: bool = True
    API_V1_PREFIX: str = "/api/v1"

    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://postgres:postgres@localhost:5432/fruittreescanner"
    )
    DATABASE_POOL_SIZE: int = 20
    DATABASE_MAX_OVERFLOW: int = 10

    # Redis
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    REDIS_STREAM_NAME: str = "fruittreescanner:jobs"

    # S3/R2 Storage
    S3_ENDPOINT: str = os.getenv("S3_ENDPOINT", "http://localhost:9000")
    S3_ACCESS_KEY: str = os.getenv("S3_ACCESS_KEY", "minioadmin")
    S3_SECRET_KEY: str = os.getenv("S3_SECRET_KEY", "minioadmin")
    S3_BUCKET: str = os.getenv("S3_BUCKET", "fruittreescanner")
    S3_REGION: str = os.getenv("S3_REGION", "us-east-1")

    # Processing
    MAX_UPLOAD_SIZE: int = 500 * 1024 * 1024  # 500MB
    ALLOWED_EXTENSIONS: List[str] = ["ply", "pcd", "xyz"]

    # CORS
    CORS_ORIGINS: List[str] = ["*"]

    # Workers
    GO_WORKER_URL: str = os.getenv("GO_WORKER_URL", "http://localhost:8081")

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
