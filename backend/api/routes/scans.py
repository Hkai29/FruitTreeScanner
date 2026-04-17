"""
Scan management endpoints with file upload.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID
import os
import aiofiles
from datetime import datetime

from core.database import get_db
from core.config import settings
from models.models import Scan, Tree, Orchard, ScanStatus, ProcessingJob, ProcessingJobType
from schemas.schemas import ScanCreate, ScanResponse, ScanUploadResponse
from services.storage import upload_file, generate_presigned_url
from services.queue import enqueue_job

router = APIRouter()


@router.get("/", response_model=List[ScanResponse])
async def list_scans(
    tree_id: Optional[UUID] = None,
    orchard_id: Optional[UUID] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    """List scans, optionally filtered by tree or orchard."""
    query = select(Scan)
    if tree_id:
        query = query.where(Scan.tree_id == tree_id)
    if orchard_id:
        query = query.where(Scan.orchard_id == orchard_id)
    query = query.options(selectinload(Scan.tree), selectinload(Scan.orchard))
    query = query.offset(skip).limit(limit).order_by(Scan.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{scan_id}", response_model=ScanResponse)
async def get_scan(scan_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get scan by ID."""
    query = select(Scan).where(Scan.id == scan_id)
    result = await db.execute(query)
    scan = result.scalar_one_or_none()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")
    return scan


@router.post("/", response_model=ScanUploadResponse, status_code=201)
async def create_scan(
    background_tasks: BackgroundTasks,
    tree_id: UUID,
    orchard_id: UUID,
    file: UploadFile = File(...),
    gps_lat: Optional[float] = None,
    gps_lon: Optional[float] = None,
    scan_date: Optional[datetime] = None,
    db: AsyncSession = Depends(get_db),
):
    """Upload a new point cloud scan."""
    # Validate file extension
    if not file.filename:
        raise HTTPException(status_code=400, detail="No filename provided")

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in settings.ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"File type not allowed. Allowed: {settings.ALLOWED_EXTENSIONS}"
        )

    # Validate tree and orchard exist
    tree_query = select(Tree).where(Tree.id == tree_id)
    tree_result = await db.execute(tree_query)
    if not tree_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Tree not found")

    orchard_query = select(Orchard).where(Orchard.id == orchard_id)
    orchard_result = await db.execute(orchard_query)
    if not orchard_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Orchard not found")

    # Create scan record
    scan = Scan(
        tree_id=tree_id,
        orchard_id=orchard_id,
        file_name=file.filename,
        gps_lat=gps_lat,
        gps_lon=gps_lon,
        scan_date=scan_date or datetime.utcnow(),
        status=ScanStatus.PENDING,
    )
    db.add(scan)
    await db.commit()
    await db.refresh(scan)

    # Queue file upload and processing
    background_tasks.add_task(
        process_upload, scan.id, file, db
    )

    return ScanUploadResponse(
        id=scan.id,
        file_name=file.filename,
        status=scan.status,
        message="Scan uploaded successfully. Processing will begin shortly."
    )


async def process_upload(scan_id: UUID, file: UploadFile, db: AsyncSession):
    """Background task to process file upload."""
    try:
        # Read file content
        content = await file.read()
        file_size = len(content)

        # Upload to S3/R2
        file_url = await upload_file(
            content,
            f"scans/{scan_id}/{file.filename}",
            file.content_type or "application/octet-stream"
        )

        # Update scan with file info
        scan_query = select(Scan).where(Scan.id == scan_id)
        result = await db.execute(scan_query)
        scan = result.scalar_one_or_none()
        if scan:
            scan.file_url = file_url
            scan.file_size = file_size
            scan.status = ScanStatus.PENDING
            await db.commit()

            # Enqueue processing job
            await enqueue_job(scan_id, ProcessingJobType.POINT_CLOUD_PROCESSING)
    except Exception as e:
        # Update scan status to failed
        scan_query = select(Scan).where(Scan.id == scan_id)
        result = await db.execute(scan_query)
        scan = result.scalar_one_or_none()
        if scan:
            scan.status = ScanStatus.FAILED
            scan.error_message = str(e)
            await db.commit()


@router.delete("/{scan_id}", status_code=204)
async def delete_scan(scan_id: UUID, db: AsyncSession = Depends(get_db)):
    """Delete a scan."""
    query = select(Scan).where(Scan.id == scan_id)
    result = await db.execute(query)
    scan = result.scalar_one_or_none()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    await db.delete(scan)
    await db.commit()


@router.get("/{scan_id}/download")
async def get_scan_download_url(scan_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get presigned URL for scan download."""
    query = select(Scan).where(Scan.id == scan_id)
    result = await db.execute(query)
    scan = result.scalar_one_or_none()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    if not scan.file_url:
        raise HTTPException(status_code=404, detail="Scan file not yet uploaded")

    presigned_url = await generate_presigned_url(scan.file_url)
    return {"download_url": presigned_url}
