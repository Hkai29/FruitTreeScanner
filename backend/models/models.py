"""
SQLAlchemy database models for FruitTreeScanner.
"""

from sqlalchemy import Column, String, Integer, Float, DateTime, Boolean, Text, ForeignKey, Enum, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from datetime import datetime
import uuid
import enum

from core.database import Base


class ScanStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class ProcessingJobType(str, enum.Enum):
    TREE_SEGMENTATION = "tree_segmentation"
    YIELD_ESTIMATION_ROUTE_A = "yield_estimation_route_a"
    YIELD_ESTIMATION_ROUTE_B = "yield_estimation_route_b"
    POINT_CLOUD_PROCESSING = "point_cloud_processing"
    ORCHARD_MAPPING = "orchard_mapping"


class Orchard(Base):
    __tablename__ = "orchards"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String(255), nullable=False)
    location_name = Column(String(255))
    gps_lat = Column(Float)
    gps_lon = Column(Float)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    trees = relationship("Tree", back_populates="orchard", cascade="all, delete-orphan")
    scans = relationship("Scan", back_populates="orchard", cascade="all, delete-orphan")


class Tree(Base):
    __tablename__ = "trees"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    orchard_id = Column(UUID(as_uuid=True), ForeignKey("orchards.id"), nullable=False)
    tree_number = Column(String(50), nullable=False)  # e.g., "T001", "T100"
    gps_lat = Column(Float)
    gps_lon = Column(Float)
    species = Column(String(100))
    planted_date = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    orchard = relationship("Orchard", back_populates="trees")
    scans = relationship("Scan", back_populates="tree", cascade="all, delete-orphan")
    yield_estimates = relationship("YieldEstimate", back_populates="tree", cascade="all, delete-orphan")


class Scan(Base):
    __tablename__ = "scans"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tree_id = Column(UUID(as_uuid=True), ForeignKey("trees.id"), nullable=False)
    orchard_id = Column(UUID(as_uuid=True), ForeignKey("orchards.id"), nullable=False)

    # File info
    file_name = Column(String(255), nullable=False)
    file_size = Column(Integer)
    file_url = Column(String(512))  # S3/R2 URL

    # Point cloud metadata
    point_count = Column(Integer)
    gps_lat = Column(Float)
    gps_lon = Column(Float)
    scan_date = Column(DateTime)

    # Status
    status = Column(Enum(ScanStatus), default=ScanStatus.PENDING)
    error_message = Column(Text)

    # Processing results
    processing_results = Column(JSON)  # Stores segmentation and other results

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    tree = relationship("Tree", back_populates="scans")
    orchard = relationship("Orchard", back_populates="scans")
    processing_jobs = relationship("ProcessingJob", back_populates="scan", cascade="all, delete-orphan")


class ProcessingJob(Base):
    __tablename__ = "processing_jobs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    scan_id = Column(UUID(as_uuid=True), ForeignKey("scans.id"), nullable=False)

    job_type = Column(Enum(ProcessingJobType), nullable=False)
    status = Column(Enum(ScanStatus), default=ScanStatus.PENDING)

    # Worker assignment
    worker_id = Column(String(100))

    # Progress tracking
    progress = Column(Integer, default=0)  # 0-100
    error_message = Column(Text)

    # Results
    result_url = Column(String(512))  # URL to processed result file
    result_data = Column(JSON)

    started_at = Column(DateTime)
    completed_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    scan = relationship("Scan", back_populates="processing_jobs")


class YieldEstimate(Base):
    __tablename__ = "yield_estimates"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tree_id = Column(UUID(as_uuid=True), ForeignKey("trees.id"), nullable=False)
    scan_id = Column(UUID(as_uuid=True), ForeignKey("scans.id"), nullable=False)

    # Route A: Canopy regression
    canopy_volume_m3 = Column(Float)
    canopy_diameter_m = Column(Float)
    canopy_height_m = Column(Float)

    # Route B: Fruit detection
    fruit_count = Column(Integer)
    fruit_size_avg_mm = Column(Float)

    # Combined estimate
    estimated_yield_kg = Column(Float)
    confidence_score = Column(Float)  # 0.0 - 1.0

    # Method used
    route_a_used = Column(Boolean, default=False)
    route_b_used = Column(Boolean, default=False)

    created_at = Column(DateTime, default=datetime.utcnow)

    tree = relationship("Tree", back_populates="yield_estimates")
    scan = relationship("Scan")


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(255))
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
