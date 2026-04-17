"""
Processing job management endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID

from core.database import get_db
from models.models import ProcessingJob, ProcessingJobType, Scan, ScanStatus
from schemas.schemas import ProcessingJobCreate, ProcessingJobResponse, ProcessingJobUpdate
from services.queue import enqueue_job

router = APIRouter()


@router.get("/", response_model=List[ProcessingJobResponse])
async def list_processing_jobs(
    scan_id: Optional[UUID] = None,
    status: Optional[ScanStatus] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    """List processing jobs, optionally filtered."""
    query = select(ProcessingJob)
    if scan_id:
        query = query.where(ProcessingJob.scan_id == scan_id)
    if status:
        query = query.where(ProcessingJob.status == status)
    query = query.options(selectinload(ProcessingJob.scan))
    query = query.offset(skip).limit(limit).order_by(ProcessingJob.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{job_id}", response_model=ProcessingJobResponse)
async def get_processing_job(job_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get processing job by ID."""
    query = select(ProcessingJob).where(ProcessingJob.id == job_id)
    result = await db.execute(query)
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Processing job not found")
    return job


@router.post("/", response_model=ProcessingJobResponse, status_code=201)
async def create_processing_job(
    job_data: ProcessingJobCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """Create a new processing job."""
    # Verify scan exists
    scan_query = select(Scan).where(Scan.id == job_data.scan_id)
    scan_result = await db.execute(scan_query)
    scan = scan_result.scalar_one_or_none()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    # Check scan has a file
    if not scan.file_url:
        raise HTTPException(status_code=400, detail="Scan file not yet uploaded")

    # Create job
    job = ProcessingJob(
        scan_id=job_data.scan_id,
        job_type=job_data.job_type,
        status=ScanStatus.PENDING,
    )
    db.add(job)
    await db.commit()
    await db.refresh(job)

    # Enqueue job for processing
    await enqueue_job(job.id, job_data.job_type)

    return job


@router.patch("/{job_id}", response_model=ProcessingJobResponse)
async def update_processing_job(
    job_id: UUID,
    job_data: ProcessingJobUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Update processing job status/progress."""
    query = select(ProcessingJob).where(ProcessingJob.id == job_id)
    result = await db.execute(query)
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Processing job not found")

    update_data = job_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(job, field, value)

    await db.commit()
    await db.refresh(job)
    return job


@router.post("/{job_id}/retry", response_model=ProcessingJobResponse)
async def retry_processing_job(
    job_id: UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """Retry a failed processing job."""
    query = select(ProcessingJob).where(ProcessingJob.id == job_id)
    result = await db.execute(query)
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Processing job not found")

    if job.status not in [ScanStatus.FAILED, ScanStatus.PENDING]:
        raise HTTPException(
            status_code=400,
            detail="Can only retry failed or pending jobs"
        )

    job.status = ScanStatus.PENDING
    job.error_message = None
    job.progress = 0
    await db.commit()
    await db.refresh(job)

    # Re-enqueue job
    await enqueue_job(job.id, job.job_type)

    return job


@router.post("/segmentation/{scan_id}", response_model=ProcessingJobResponse)
async def start_tree_segmentation(
    scan_id: UUID,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """Start tree segmentation processing for a scan."""
    return await create_processing_job(
        ProcessingJobCreate(
            scan_id=scan_id,
            job_type=ProcessingJobType.TREE_SEGMENTATION,
        ),
        background_tasks,
        db,
    )


@router.post("/yield-estimation/{scan_id}", response_model=ProcessingJobResponse)
async def start_yield_estimation(
    scan_id: UUID,
    route: str = Query(..., regex="^(a|b)$", description="Route A (canopy) or Route B (fruit detection)"),
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    """Start yield estimation for a scan using specified route."""
    job_type = (
        ProcessingJobType.YIELD_ESTIMATION_ROUTE_A
        if route.lower() == "a"
        else ProcessingJobType.YIELD_ESTIMATION_ROUTE_B
    )
    return await create_processing_job(
        ProcessingJobCreate(scan_id=scan_id, job_type=job_type),
        background_tasks,
        db,
    )
