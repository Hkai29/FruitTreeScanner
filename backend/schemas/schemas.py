"""
Pydantic schemas for API request/response validation.
"""

from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List
from datetime import datetime
from uuid import UUID
from enum import Enum


# Enums
class ScanStatusEnum(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class ProcessingJobTypeEnum(str, Enum):
    TREE_SEGMENTATION = "tree_segmentation"
    YIELD_ESTIMATION_ROUTE_A = "yield_estimation_route_a"
    YIELD_ESTIMATION_ROUTE_B = "yield_estimation_route_b"
    POINT_CLOUD_PROCESSING = "point_cloud_processing"
    ORCHARD_MAPPING = "orchard_mapping"


# Orchards
class OrchardBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    location_name: Optional[str] = None
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None


class OrchardCreate(OrchardBase):
    pass


class OrchardUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    location_name: Optional[str] = None
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None


class OrchardResponse(OrchardBase):
    id: UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Trees
class TreeBase(BaseModel):
    tree_number: str = Field(..., min_length=1, max_length=50)
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    species: Optional[str] = Field(None, max_length=100)
    planted_date: Optional[datetime] = None


class TreeCreate(TreeBase):
    orchard_id: UUID


class TreeUpdate(BaseModel):
    tree_number: Optional[str] = Field(None, min_length=1, max_length=50)
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    species: Optional[str] = Field(None, max_length=100)
    planted_date: Optional[datetime] = None


class TreeResponse(TreeBase):
    id: UUID
    orchard_id: UUID
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# Scans
class ScanBase(BaseModel):
    tree_id: UUID
    orchard_id: UUID
    gps_lat: Optional[float] = None
    gps_lon: Optional[float] = None
    scan_date: Optional[datetime] = None


class ScanCreate(ScanBase):
    file_name: str


class ScanResponse(ScanBase):
    id: UUID
    file_name: str
    file_size: Optional[int] = None
    file_url: Optional[str] = None
    point_count: Optional[int] = None
    status: ScanStatusEnum
    error_message: Optional[str] = None
    processing_results: Optional[dict] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ScanUploadResponse(BaseModel):
    id: UUID
    file_name: str
    status: ScanStatusEnum
    message: str


# Processing Jobs
class ProcessingJobBase(BaseModel):
    scan_id: UUID
    job_type: ProcessingJobTypeEnum


class ProcessingJobCreate(ProcessingJobBase):
    pass


class ProcessingJobResponse(ProcessingJobBase):
    id: UUID
    status: ScanStatusEnum
    worker_id: Optional[str] = None
    progress: int
    error_message: Optional[str] = None
    result_url: Optional[str] = None
    result_data: Optional[dict] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ProcessingJobUpdate(BaseModel):
    status: Optional[ScanStatusEnum] = None
    progress: Optional[int] = Field(None, ge=0, le=100)
    error_message: Optional[str] = None
    result_url: Optional[str] = None
    result_data: Optional[dict] = None
    worker_id: Optional[str] = None


# Yield Estimates
class YieldEstimateBase(BaseModel):
    tree_id: UUID
    scan_id: UUID
    canopy_volume_m3: Optional[float] = None
    canopy_diameter_m: Optional[float] = None
    canopy_height_m: Optional[float] = None
    fruit_count: Optional[int] = None
    fruit_size_avg_mm: Optional[float] = None
    estimated_yield_kg: Optional[float] = None
    confidence_score: Optional[float] = Field(None, ge=0.0, le=1.0)
    route_a_used: bool = False
    route_b_used: bool = False


class YieldEstimateCreate(YieldEstimateBase):
    pass


class YieldEstimateResponse(YieldEstimateBase):
    id: UUID
    created_at: datetime

    class Config:
        from_attributes = True


# Users
class UserBase(BaseModel):
    email: EmailStr
    full_name: Optional[str] = None


class UserCreate(UserBase):
    password: str = Field(..., min_length=8)


class UserResponse(UserBase):
    id: UUID
    is_active: bool
    is_superuser: bool
    created_at: datetime

    class Config:
        from_attributes = True


# Auth
class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    user_id: Optional[UUID] = None


# Pagination
class PaginatedResponse(BaseModel):
    items: List
    total: int
    page: int
    page_size: int
    total_pages: int


# Statistics
class OrchardStats(BaseModel):
    orchard_id: UUID
    total_trees: int
    total_scans: int
    average_yield_kg: Optional[float] = None
    last_scan_date: Optional[datetime] = None


class TreeStats(BaseModel):
    tree_id: UUID
    tree_number: str
    total_scans: int
    latest_yield_estimate_kg: Optional[float] = None
    yield_trend: Optional[str] = None  # "increasing", "decreasing", "stable"
