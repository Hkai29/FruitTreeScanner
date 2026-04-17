"""Initial migration

Revision ID: 001
Revises:
Create Date: 2026-04-17

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create orchards table
    op.create_table(
        'orchards',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('location_name', sa.String(255)),
        sa.Column('gps_lat', sa.Float),
        sa.Column('gps_lon', sa.Float),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()')),
    )

    # Create trees table
    op.create_table(
        'trees',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('orchard_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('orchards.id'), nullable=False),
        sa.Column('tree_number', sa.String(50), nullable=False),
        sa.Column('gps_lat', sa.Float),
        sa.Column('gps_lon', sa.Float),
        sa.Column('species', sa.String(100)),
        sa.Column('planted_date', sa.DateTime()),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()')),
    )
    op.create_index('ix_trees_orchard_id', 'trees', ['orchard_id'])

    # Create scans table
    op.create_table(
        'scans',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('tree_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('trees.id'), nullable=False),
        sa.Column('orchard_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('orchards.id'), nullable=False),
        sa.Column('file_name', sa.String(255), nullable=False),
        sa.Column('file_size', sa.Integer),
        sa.Column('file_url', sa.String(512)),
        sa.Column('point_count', sa.Integer),
        sa.Column('gps_lat', sa.Float),
        sa.Column('gps_lon', sa.Float),
        sa.Column('scan_date', sa.DateTime()),
        sa.Column('status', sa.String(20), server_default='pending'),
        sa.Column('error_message', sa.Text),
        sa.Column('processing_results', postgresql.JSONB),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()')),
    )
    op.create_index('ix_scans_tree_id', 'scans', ['tree_id'])
    op.create_index('ix_scans_orchard_id', 'scans', ['orchard_id'])
    op.create_index('ix_scans_status', 'scans', ['status'])

    # Create processing_jobs table
    op.create_table(
        'processing_jobs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('scan_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('scans.id'), nullable=False),
        sa.Column('job_type', sa.String(50), nullable=False),
        sa.Column('status', sa.String(20), server_default='pending'),
        sa.Column('worker_id', sa.String(100)),
        sa.Column('progress', sa.Integer, server_default='0'),
        sa.Column('error_message', sa.Text),
        sa.Column('result_url', sa.String(512)),
        sa.Column('result_data', postgresql.JSONB),
        sa.Column('started_at', sa.DateTime()),
        sa.Column('completed_at', sa.DateTime()),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()')),
    )
    op.create_index('ix_processing_jobs_scan_id', 'processing_jobs', ['scan_id'])
    op.create_index('ix_processing_jobs_status', 'processing_jobs', ['status'])

    # Create yield_estimates table
    op.create_table(
        'yield_estimates',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('tree_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('trees.id'), nullable=False),
        sa.Column('scan_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('scans.id'), nullable=False),
        sa.Column('canopy_volume_m3', sa.Float),
        sa.Column('canopy_diameter_m', sa.Float),
        sa.Column('canopy_height_m', sa.Float),
        sa.Column('fruit_count', sa.Integer),
        sa.Column('fruit_size_avg_mm', sa.Float),
        sa.Column('estimated_yield_kg', sa.Float),
        sa.Column('confidence_score', sa.Float),
        sa.Column('route_a_used', sa.Boolean, server_default='false'),
        sa.Column('route_b_used', sa.Boolean, server_default='false'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
    )
    op.create_index('ix_yield_estimates_tree_id', 'yield_estimates', ['tree_id'])
    op.create_index('ix_yield_estimates_scan_id', 'yield_estimates', ['scan_id'])

    # Create users table
    op.create_table(
        'users',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('email', sa.String(255), unique=True, nullable=False),
        sa.Column('hashed_password', sa.String(255), nullable=False),
        sa.Column('full_name', sa.String(255)),
        sa.Column('is_active', sa.Boolean, server_default='true'),
        sa.Column('is_superuser', sa.Boolean, server_default='false'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()')),
    )
    op.create_index('ix_users_email', 'users', ['email'])


def downgrade() -> None:
    op.drop_table('users')
    op.drop_table('yield_estimates')
    op.drop_table('processing_jobs')
    op.drop_table('scans')
    op.drop_table('trees')
    op.drop_table('orchards')
