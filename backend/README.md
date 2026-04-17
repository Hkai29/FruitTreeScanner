# FruitTreeScanner Backend

FastAPI-based backend for the FruitTreeScanner iOS app. Handles point cloud storage, processing, tree segmentation, and yield estimation.

## Architecture

- **FastAPI** - REST API server
- **PostgreSQL + PostGIS + TimescaleDB** - Primary database
- **Redis** - Job queue and caching
- **S3/R2** - Point cloud file storage
- **Go Workers** - Background processing

## Quick Start

### Using Docker Compose

```bash
# Start all services
docker-compose up -d

# Run migrations
docker-compose exec api alembic upgrade head

# API is available at http://localhost:8000
# API docs at http://localhost:8000/docs
```

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/fruittreescanner
export REDIS_URL=redis://localhost:6379/0

# Run migrations
alembic upgrade head

# Start API
uvicorn main:app --reload

# Start worker (in separate terminal)
cd workers && go run main.go
```

## API Endpoints

### Authentication
- `POST /api/v1/auth/register` - Register new user
- `POST /api/v1/auth/token` - Login and get JWT token
- `GET /api/v1/auth/me` - Get current user info

### Orchards
- `GET /api/v1/orchards` - List all orchards
- `POST /api/v1/orchards` - Create orchard
- `GET /api/v1/orchards/{id}` - Get orchard
- `PUT /api/v1/orchards/{id}` - Update orchard
- `DELETE /api/v1/orchards/{id}` - Delete orchard
- `GET /api/v1/orchards/{id}/stats` - Get orchard statistics

### Trees
- `GET /api/v1/trees` - List trees (filter by orchard_id)
- `POST /api/v1/trees` - Create tree
- `GET /api/v1/trees/{id}` - Get tree
- `PUT /api/v1/trees/{id}` - Update tree
- `DELETE /api/v1/trees/{id}` - Delete tree
- `GET /api/v1/trees/{id}/stats` - Get tree statistics

### Scans
- `GET /api/v1/scans` - List scans (filter by tree_id, orchard_id)
- `POST /api/v1/scans` - Upload new point cloud scan
- `GET /api/v1/scans/{id}` - Get scan
- `DELETE /api/v1/scans/{id}` - Delete scan
- `GET /api/v1/scans/{id}/download` - Get presigned download URL

### Processing Jobs
- `GET /api/v1/processing` - List processing jobs
- `POST /api/v1/processing` - Create processing job
- `GET /api/v1/processing/{id}` - Get job status
- `PATCH /api/v1/processing/{id}` - Update job
- `POST /api/v1/processing/{id}/retry` - Retry failed job
- `POST /api/v1/processing/segmentation/{scan_id}` - Start tree segmentation
- `POST /api/v1/processing/yield-estimation/{scan_id}?route=a|b` - Start yield estimation

### Yields
- `GET /api/v1/yields` - List yield estimates
- `POST /api/v1/yields` - Create yield estimate
- `GET /api/v1/yields/{id}` - Get yield estimate
- `GET /api/v1/yields/tree/{tree_id}/history` - Get yield history
- `GET /api/v1/yields/tree/{tree_id}/comparison` - Compare yields

## Data Models

### Orchard
Contains orchard/plantation information with GPS coordinates.

### Tree
Individual trees within an orchard, identified by tree_number (T001-T100).

### Scan
Point cloud scan data from LiDAR capture, stored as PLY files in S3.

### ProcessingJob
Background jobs for point cloud processing, segmentation, and yield estimation.

### YieldEstimate
Yield estimation results from Route A (canopy regression) or Route B (fruit detection).

## Processing Pipeline

1. **Upload**: User uploads PLY file via iOS app
2. **Queue**: Job is enqueued to Redis stream
3. **Process**: Go worker picks up job
   - Point cloud processing: Parse PLY, extract metadata
   - Tree segmentation: Identify tree canopy in point cloud
   - Yield estimation:
     - Route A: Canopy volume → yield regression
     - Route B: ML-based fruit detection → fruit count → yield
4. **Store**: Results stored in PostgreSQL

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | postgresql+asyncpg://... | PostgreSQL connection |
| `REDIS_URL` | redis://localhost:6379 | Redis connection |
| `S3_ENDPOINT` | http://localhost:9000 | S3/R2 endpoint |
| `S3_ACCESS_KEY` | minioadmin | S3 access key |
| `S3_SECRET_KEY` | minioadmin | S3 secret key |
| `S3_BUCKET` | fruittreescanner | S3 bucket name |
