"""
API routes aggregation.
"""

from fastapi import APIRouter
from api.routes import orchards, trees, scans, processing, yields, auth

router = APIRouter()

router.include_router(orchards.router, prefix="/orchards", tags=["Orchards"])
router.include_router(trees.router, prefix="/trees", tags=["Trees"])
router.include_router(scans.router, prefix="/scans", tags=["Scans"])
router.include_router(processing.router, prefix="/processing", tags=["Processing"])
router.include_router(yields.router, prefix="/yields", tags=["Yields"])
router.include_router(auth.router, prefix="/auth", tags=["Auth"])
