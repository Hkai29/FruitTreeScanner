"""
Yield estimation endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID
from datetime import datetime, timedelta

from core.database import get_db
from models.models import YieldEstimate, Tree, Scan
from schemas.schemas import YieldEstimateCreate, YieldEstimateResponse

router = APIRouter()


@router.get("/", response_model=List[YieldEstimateResponse])
async def list_yield_estimates(
    tree_id: Optional[UUID] = None,
    scan_id: Optional[UUID] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    """List yield estimates with optional filters."""
    query = select(YieldEstimate)
    if tree_id:
        query = query.where(YieldEstimate.tree_id == tree_id)
    if scan_id:
        query = query.where(YieldEstimate.scan_id == scan_id)
    if start_date:
        query = query.where(YieldEstimate.created_at >= start_date)
    if end_date:
        query = query.where(YieldEstimate.created_at <= end_date)

    query = query.options(selectinload(YieldEstimate.tree), selectinload(YieldEstimate.scan))
    query = query.offset(skip).limit(limit).order_by(YieldEstimate.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{yield_id}", response_model=YieldEstimateResponse)
async def get_yield_estimate(yield_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get yield estimate by ID."""
    query = select(YieldEstimate).where(YieldEstimate.id == yield_id)
    result = await db.execute(query)
    yield_est = result.scalar_one_or_none()
    if not yield_est:
        raise HTTPException(status_code=404, detail="Yield estimate not found")
    return yield_est


@router.post("/", response_model=YieldEstimateResponse, status_code=201)
async def create_yield_estimate(
    yield_data: YieldEstimateCreate,
    db: AsyncSession = Depends(get_db),
):
    """Create a new yield estimate (typically from processing job)."""
    # Verify tree and scan exist
    tree_query = select(Tree).where(Tree.id == yield_data.tree_id)
    tree_result = await db.execute(tree_query)
    if not tree_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Tree not found")

    scan_query = select(Scan).where(Scan.id == yield_data.scan_id)
    scan_result = await db.execute(scan_query)
    if not scan_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Scan not found")

    yield_est = YieldEstimate(**yield_data.model_dump())
    db.add(yield_est)
    await db.commit()
    await db.refresh(yield_est)
    return yield_est


@router.get("/tree/{tree_id}/history")
async def get_tree_yield_history(
    tree_id: UUID,
    days: int = Query(30, ge=1, le=365),
    db: AsyncSession = Depends(get_db),
):
    """Get yield history for a tree over specified days."""
    start_date = datetime.utcnow() - timedelta(days=days)

    query = (
        select(YieldEstimate)
        .where(
            YieldEstimate.tree_id == tree_id,
            YieldEstimate.created_at >= start_date
        )
        .order_by(YieldEstimate.created_at.asc())
    )
    result = await db.execute(query)
    estimates = result.scalars().all()

    return {
        "tree_id": tree_id,
        "period_days": days,
        "estimates": [
            {
                "id": str(e.id),
                "estimated_yield_kg": e.estimated_yield_kg,
                "confidence_score": e.confidence_score,
                "route_a_used": e.route_a_used,
                "route_b_used": e.route_b_used,
                "created_at": e.created_at.isoformat(),
            }
            for e in estimates
        ],
    }


@router.get("/tree/{tree_id}/comparison")
async def compare_tree_yields(
    tree_id: UUID,
    db: AsyncSession = Depends(get_db),
):
    """Compare latest yield with historical average."""
    tree_query = select(Tree).where(Tree.id == tree_id)
    tree_result = await db.execute(tree_query)
    tree = tree_result.scalar_one_or_none()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    # Get all estimates for this tree
    query = (
        select(YieldEstimate)
        .where(YieldEstimate.tree_id == tree_id)
        .order_by(YieldEstimate.created_at.desc())
    )
    result = await db.execute(query)
    estimates = result.scalars().all()

    if not estimates:
        raise HTTPException(status_code=404, detail="No yield estimates found for this tree")

    latest = estimates[0]
    avg_yield = sum(e.estimated_yield_kg for e in estimates if e.estimated_yield_kg) / len(estimates)

    return {
        "tree_id": tree_id,
        "tree_number": tree.tree_number,
        "latest_estimate": {
            "id": str(latest.id),
            "estimated_yield_kg": latest.estimated_yield_kg,
            "confidence_score": latest.confidence_score,
            "created_at": latest.created_at.isoformat(),
        },
        "historical_average_kg": avg_yield,
        "total_estimates": len(estimates),
        "difference_from_avg_kg": latest.estimated_yield_kg - avg_yield if latest.estimated_yield_kg else None,
        "percent_change": ((latest.estimated_yield_kg - avg_yield) / avg_yield * 100) if latest.estimated_yield_kg else None,
    }
