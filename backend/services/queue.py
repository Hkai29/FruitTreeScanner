"""
Redis queue service for job processing.
"""

import json
import logging
from uuid import UUID
from typing import Optional, Dict, Any
import redis.asyncio as redis

from core.config import settings
from core.redis import get_redis
from models.models import ProcessingJobType

logger = logging.getLogger(__name__)


async def enqueue_job(job_id: UUID, job_type: ProcessingJobType) -> bool:
    """
    Enqueue a processing job to Redis stream.

    Args:
        job_id: UUID of the processing job
        job_type: Type of processing job

    Returns:
        True if enqueued successfully
    """
    try:
        redis_client = await get_redis()
        job_data = {
            "job_id": str(job_id),
            "job_type": job_type.value,
        }
        await redis_client.xadd(
            settings.REDIS_STREAM_NAME,
            job_data,
            maxlen=1000,
        )
        logger.info(f"Enqueued job {job_id} of type {job_type.value}")
        return True
    except Exception as e:
        logger.error(f"Failed to enqueue job: {e}")
        return False


async def get_job_from_queue(timeout: int = 5) -> Optional[Dict[str, Any]]:
    """
    Get a job from the Redis stream queue.

    Args:
        timeout: Blocking timeout in seconds

    Returns:
        Job data dict or None if timeout
    """
    try:
        redis_client = await get_redis()
        result = await redis_client.xread(
            {settings.REDIS_STREAM_NAME: "$"},
            count=1,
            block=timeout * 1000,  # milliseconds
        )
        if result:
            stream_name, messages = result[0]
            for message_id, data in messages:
                return {
                    "id": message_id.decode() if isinstance(message_id, bytes) else message_id,
                    **data,
                }
        return None
    except Exception as e:
        logger.error(f"Failed to get job from queue: {e}")
        return None


async def acknowledge_job(message_id: str) -> bool:
    """
    Acknowledge/complete a job (remove from stream).

    Args:
        message_id: The stream message ID to acknowledge

    Returns:
        True if acknowledged successfully
    """
    try:
        redis_client = await get_redis()
        await redis_client.xdel(settings.REDIS_STREAM_NAME, message_id)
        return True
    except Exception as e:
        logger.error(f"Failed to acknowledge job: {e}")
        return False


async def get_queue_length() -> int:
    """Get current queue length."""
    try:
        redis_client = await get_redis()
        length = await redis_client.xlen(settings.REDIS_STREAM_NAME)
        return length
    except Exception as e:
        logger.error(f"Failed to get queue length: {e}")
        return 0


async def enqueue_with_delay(
    job_id: UUID,
    job_type: ProcessingJobType,
    delay_seconds: int,
) -> bool:
    """
    Enqueue a job with a delay (using Redis sorted set).

    Args:
        job_id: UUID of the processing job
        job_type: Type of processing job
        delay_seconds: Delay before job becomes available

    Returns:
        True if enqueued successfully
    """
    try:
        redis_client = await get_redis()
        import time
        score = time.time() + delay_seconds
        job_data = json.dumps({
            "job_id": str(job_id),
            "job_type": job_type.value,
        })
        await redis_client.zadd(
            f"{settings.REDIS_STREAM_NAME}:delayed",
            {job_data: score},
        )
        logger.info(f"Enqueued delayed job {job_id} with {delay_seconds}s delay")
        return True
    except Exception as e:
        logger.error(f"Failed to enqueue delayed job: {e}")
        return False
