"""
Tree management endpoints.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.orm import selectinload
from typing import List, Optional
from uuid import UUID

from core.database import get_db
from models.models import Tree, Orchard
from schemas.schemas import TreeCreate, TreeUpdate, TreeResponse, TreeStats

router = APIRouter()


@router.get("/", response_model=List[TreeResponse])
async def list_trees(
    orchard_id: Optional[UUID] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    db: AsyncSession = Depends(get_db),
):
    """List trees, optionally filtered by orchard."""
    query = select(Tree)
    if orchard_id:
        query = query.where(Tree.orchard_id == orchard_id)
    query = query.offset(skip).limit(limit).order_by(Tree.tree_number)
    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{tree_id}", response_model=TreeResponse)
async def get_tree(tree_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get tree by ID."""
    query = select(Tree).where(Tree.id == tree_id)
    result = await db.execute(query)
    tree = result.scalar_one_or_none()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")
    return tree


@router.post("/", response_model=TreeResponse, status_code=201)
async def create_tree(
    tree_data: TreeCreate,
    db: AsyncSession = Depends(get_db),
):
    """Create a new tree."""
    # Verify orchard exists
    orchard_query = select(Orchard).where(Orchard.id == tree_data.orchard_id)
    orchard_result = await db.execute(orchard_query)
    if not orchard_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Orchard not found")

    tree = Tree(**tree_data.model_dump())
    db.add(tree)
    await db.commit()
    await db.refresh(tree)
    return tree


@router.put("/{tree_id}", response_model=TreeResponse)
async def update_tree(
    tree_id: UUID,
    tree_data: TreeUpdate,
    db: AsyncSession = Depends(get_db),
):
    """Update a tree."""
    query = select(Tree).where(Tree.id == tree_id)
    result = await db.execute(query)
    tree = result.scalar_one_or_none()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    update_data = tree_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(tree, field, value)

    await db.commit()
    await db.refresh(tree)
    return tree


@router.delete("/{tree_id}", status_code=204)
async def delete_tree(tree_id: UUID, db: AsyncSession = Depends(get_db)):
    """Delete a tree."""
    query = select(Tree).where(Tree.id == tree_id)
    result = await db.execute(query)
    tree = result.scalar_one_or_none()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    await db.delete(tree)
    await db.commit()


@router.get("/{tree_id}/stats", response_model=TreeStats)
async def get_tree_stats(tree_id: UUID, db: AsyncSession = Depends(get_db)):
    """Get tree statistics."""
    query = select(Tree).where(Tree.id == tree_id)
    result = await db.execute(query)
    tree = result.scalar_one_or_none()
    if not tree:
        raise HTTPException(status_code=404, detail="Tree not found")

    from models.models import Scan, YieldEstimate

    # Count scans
    scan_count_query = select(func.count()).select_from(Scan).where(Scan.tree_id == tree_id)
    scan_count_result = await db.execute(scan_count_query)
    total_scans = scan_count_result.scalar()

    # Get latest yield estimate
    latest_yield_query = (
        select(YieldEstimate)
        .where(YieldEstimate.tree_id == tree_id)
        .order_by(YieldEstimate.created_at.desc())
        .limit(1)
    )
    latest_yield_result = await db.execute(latest_yield_query)
    latest_yield = latest_yield_result.scalar_one_or_none()

    return TreeStats(
        tree_id=tree_id,
        tree_number=tree.tree_number,
        total_scans=total_scans or 0,
        latest_yield_estimate_kg=latest_yield.estimated_yield_kg if latest_yield else None,
        yield_trend=None,  # Would need historical analysis
    )
