"""
Orchard management endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID

from core.database import get_db
from models.models import Orchard, Tree
from schemas.schemas import OrchardCreate, OrchardUpdate, OrchardResponse, OrchardStats

router = APIRouter()


@router.get("/", response_model=List[OrchardResponse])
async def list_orchards(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    """List all orchards."""
    query = select(Orchard).offset(skip).limit(limit).order_by(Orchard.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{orchard_id}", response_model=OrchardResponse)
async def get_orchard(orchard_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get orchard by ID."""
    query = select(Orchard).where(Orchard.id == orchard_id)
    result = await db.execute(query)
    orchard = result.scalar_one_or_none()
    if not orchard:
        raise HTTPException(status_code=404, detail="Orchard not found")
    return orchard


@router.post("/", response_model=OrchardResponse, status_code=201)
async def create_orchard(
    orchard_data: OrchardCreate,
    db: AsyncSession = Depends(get_db),
):
    """Create a new orchard."""
    orchard = Orchard(**orchard_data.model_dump())
    db.add(orchard)
    await db.commit()
    await db.refresh(orchard)
    return orchard


@router.put("/{orchard_id}", response_model=OrchardResponse)
async def update_orchard(
    orchard_id: UUID,
    orchard_data: OrchardUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Update an orchard."""
    query = select(Orchard).where(Orchard.id == orchard_id)
    result = await db.execute(query)
    orchard = result.scalar_one_or_none()
    if not orchard:
        raise HTTPException(status_code=404, detail="Orchard not found")

    update_data = orchard_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(orchard, field, value)

    await db.commit()
    await db.refresh(orchard)
    return orchard


@router.delete("/{orchard_id}", status_code=204)
async def delete_orchard(orchard_id: UUID, db: AsyncSession = Depends(get_db)):
    """Delete an orchard."""
    query = select(Orchard).where(Orchard.id == orchard_id)
    result = await db.execute(query)
    orchard = result.scalar_one_or_none()
    if not orchard:
        raise HTTPException(status_code=404, detail="Orchard not found")

    await db.delete(orchard)
    await db.commit()


@router.get("/{orchard_id}/stats", response_model=OrchardStats)
async def get_orchard_stats(orchard_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get orchard statistics."""
    query = select(Orchard).where(Orchard.id == orchard_id)
    result = await db.execute(query)
    orchard = result.scalar_one_or_none()
    if not orchard:
        raise HTTPException(status_code=404, detail="Orchard not found")

    # Count trees
    tree_count_query = select(func.count()).select_from(Tree).where(Tree.orchard_id == orchard_id)
    tree_count_result = await db.execute(tree_count_query)
    total_trees = tree_count_result.scalar()

    # Get scans count
    scan_count_query = select(func.count()).select_from(Scan).where(Scan.orchard_id == orchard_id)
    scan_count_result = await db.execute(scan_count_query)
    total_scans = scan_count_result.scalar()

    # Get average yield (simplified - would need join with yields)
    from models.models import YieldEstimate, Scan
    avg_yield_query = select(func.avg(YieldEstimate.estimated_yield_kg)).join(
        Scan, Scan.id == YieldEstimate.scan_id
    ).where(Scan.orchard_id == orchard_id)
    avg_result = await db.execute(avg_yield_query)
    average_yield = avg_result.scalar()

    # Get last scan date
    last_scan_query = select(func.max(Scan.created_at)).where(Scan.orchard_id == orchard_id)
    last_scan_result = await db.execute(last_scan_query)
    last_scan_date = last_scan_result.scalar()

    return OrchardStats(
        orchard_id=orchard_id,
        total_trees=total_trees or 0,
        total_scans=total_scans or 0,
        average_yield_kg=average_yield,
        last_scan_date=last_scan_date,
    )


# Import Scan here to avoid circular import
from models.models import Scan
