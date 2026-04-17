"""
Redis connection and caching utilities.
"""

import redis.asyncio as redis
from core.config import settings

redis_client: redis.Redis = None


async def init_redis():
    """Initialize Redis connection."""
    global redis_client
    redis_client = redis.from_url(
        settings.REDIS_URL,
        encoding="utf-8",
        decode_responses=True,
    )


async def close_redis():
    """Close Redis connection."""
    global redis_client
    if redis_client:
        await redis_client.close()


async def get_redis() -> redis.Redis:
    """Get Redis client."""
    return redis_client
