"""
S3/R2 storage service for file uploads.
"""

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from core.config import settings
import logging

logger = logging.getLogger(__name__)

# S3 client
s3_client = None


def get_s3_client():
    """Get or create S3 client."""
    global s3_client
    if s3_client is None:
        s3_client = boto3.client(
            "s3",
            endpoint_url=settings.S3_ENDPOINT,
            aws_access_key_id=settings.S3_ACCESS_KEY,
            aws_secret_access_key=settings.S3_SECRET_KEY,
            region_name=settings.S3_REGION,
            config=Config(signature_version="s3v4"),
        )
    return s3_client


async def upload_file(content: bytes, key: str, content_type: str) -> str:
    """
    Upload a file to S3/R2.

    Args:
        content: File content as bytes
        key: S3 object key (path in bucket)
        content_type: MIME type

    Returns:
        S3 URL of uploaded file
    """
    try:
        client = get_s3_client()
        client.put_object(
            Bucket=settings.S3_BUCKET,
            Key=key,
            Body=content,
            ContentType=content_type,
        )
        url = f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/{key}"
        logger.info(f"Uploaded file to {url}")
        return url
    except ClientError as e:
        logger.error(f"Failed to upload file: {e}")
        raise


async def generate_presigned_url(key: str, expiration: int = 3600) -> str:
    """
    Generate a presigned URL for downloading a file.

    Args:
        key: S3 object key
        expiration: URL expiration time in seconds

    Returns:
        Presigned URL for download
    """
    try:
        client = get_s3_client()
        # Extract key from full URL if needed
        if key.startswith(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):
            key = key[len(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):]

        url = client.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.S3_BUCKET, "Key": key},
            ExpiresIn=expiration,
        )
        return url
    except ClientError as e:
        logger.error(f"Failed to generate presigned URL: {e}")
        raise


async def delete_file(key: str) -> bool:
    """
    Delete a file from S3/R2.

    Args:
        key: S3 object key

    Returns:
        True if deleted successfully
    """
    try:
        client = get_s3_client()
        # Extract key from full URL if needed
        if key.startswith(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):
            key = key[len(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):]

        client.delete_object(Bucket=settings.S3_BUCKET, Key=key)
        logger.info(f"Deleted file {key}")
        return True
    except ClientError as e:
        logger.error(f"Failed to delete file: {e}")
        return False


async def file_exists(key: str) -> bool:
    """Check if a file exists in S3/R2."""
    try:
        client = get_s3_client()
        # Extract key from full URL if needed
        if key.startswith(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):
            key = key[len(f"{settings.S3_ENDPOINT}/{settings.S3_BUCKET}/"):]

        client.head_object(Bucket=settings.S3_BUCKET, Key=key)
        return True
    except ClientError:
        return False
