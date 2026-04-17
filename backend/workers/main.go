package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/lib/pq"
)

// Config holds worker configuration
type Config struct {
	DatabaseURL    string
	RedisURL       string
	RedisStream    string
	WorkerID       string
	S3Endpoint     string
	S3AccessKey    string
	S3SecretKey    string
	S3Bucket       string
	APIURL         string
}

// Job represents a processing job from the queue
type Job struct {
	ID      string `json:"job_id"`
	Type    string `json:"job_type"`
	ScanID  string `json:"scan_id"`
}

var cfg Config

func main() {
	// Load configuration
	cfg = Config{
		DatabaseURL:  getEnv("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/fruittreescanner"),
		RedisURL:     getEnv("REDIS_URL", "redis://localhost:6379"),
		RedisStream:  getEnv("REDIS_STREAM", "fruittreescanner:jobs"),
		WorkerID:     getEnv("WORKER_ID", fmt.Sprintf("worker-%d", os.Getpid())),
		S3Endpoint:   getEnv("S3_ENDPOINT", "http://localhost:9000"),
		S3AccessKey:  getEnv("S3_ACCESS_KEY", "minioadmin"),
		S3SecretKey:  getEnv("S3_SECRET_KEY", "minioadmin"),
		S3Bucket:     getEnv("S3_BUCKET", "fruittreescanner"),
		APIURL:       getEnv("API_URL", "http://localhost:8000"),
	}

	log.Printf("Starting FruitTreeScanner Worker [%s]\n", cfg.WorkerID)

	// Connect to Redis
	rdb := redis.NewClient(&redis.Options{
		Addr: cfg.RedisURL,
	})

	ctx := context.Background()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	log.Println("Connected to Redis")

	// Connect to PostgreSQL
	db, err := pq.Open(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("Failed to ping PostgreSQL: %v", err)
	}
	log.Println("Connected to PostgreSQL")

	// Main processing loop
	for {
		// Read from stream
		streams, err := rdb.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    cfg.WorkerID,
			Consumer: cfg.WorkerID,
			Streams:  []string{cfg.RedisStream, ">"},
			Count:    1,
			Block:    5 * time.Second,
		}).Result()

		if err != nil && err != redis.Nil {
			log.Printf("Error reading from stream: %v", err)
			time.Sleep(1 * time.Second)
			continue
		}

		if len(streams) == 0 {
			continue
		}

		for _, stream := range streams {
			for _, message := range stream.Messages {
				var job Job
				if err := json.Unmarshal([]byte(message.Values["job_type"]), &job); err != nil {
					// Handle legacy format
					job = Job{
						ID:   message.Values["job_id"].(string),
						Type: message.Values["job_type"].(string),
					}
				}

				log.Printf("Processing job: %s (type: %s)\n", job.ID, job.Type)

				// Process based on job type
				var jobErr error
				switch job.Type {
				case "point_cloud_processing":
					jobErr = processPointCloud(ctx, db, job.ID)
				case "tree_segmentation":
					jobErr = processTreeSegmentation(ctx, db, job.ID)
				case "yield_estimation_route_a":
					jobErr = processYieldEstimationRouteA(ctx, db, job.ID)
				case "yield_estimation_route_b":
					jobErr = processYieldEstimationRouteB(ctx, db, job.ID)
				default:
					log.Printf("Unknown job type: %s", job.Type)
				}

				// Update job status
				updateJobStatus(db, job.ID, jobErr)

				// Acknowledge message
				rdb.XAck(ctx, cfg.RedisStream, cfg.WorkerID, message.ID)
			}
		}
	}
}

func processPointCloud(ctx context.Context, db *pq.PsqlDatabase, jobID string) error {
	log.Printf("Processing point cloud for job: %s", jobID)

	// Update status to processing
	updateJobProgress(db, jobID, 10)

	// Get scan info
	scanURL, scanID := getScanInfo(db, jobID)
	if scanURL == "" {
		return fmt.Errorf("scan not found")
	}

	// Download point cloud file
	updateJobProgress(db, jobID, 30)

	// Parse PLY file and extract metadata
	updateJobProgress(db, jobID, 50)

	// Update scan with point count
	updateScanMetadata(db, scanID, 1000000) // Example point count

	updateJobProgress(db, jobID, 100)
	return nil
}

func processTreeSegmentation(ctx context.Context, db *pq.PsqlDatabase, jobID string) error {
	log.Printf("Processing tree segmentation for job: %s", jobID)

	updateJobProgress(db, jobID, 10)

	// Get scan info
	_, scanID := getScanInfo(db, jobID)
	if scanID == "" {
		return fmt.Errorf("scan not found")
	}

	// Load point cloud
	updateJobProgress(db, jobID, 30)

	// Apply segmentation algorithm (placeholder)
	updateJobProgress(db, jobID, 70)

	// Save segmentation results
	saveSegmentationResults(db, scanID, map[string]interface{}{
		"tree_mask": []int{},
		"canopy_bounds": []float64{0, 0, 0, 1, 1, 1},
	})

	updateJobProgress(db, jobID, 100)
	return nil
}

func processYieldEstimationRouteA(ctx context.Context, db *pq.PsqlDatabase, jobID string) error {
	// Route A: Canopy regression
	// Uses canopy volume/dimensions to estimate yield
	log.Printf("Processing yield estimation (Route A) for job: %s", jobID)

	updateJobProgress(db, jobID, 10)

	// Get scan info
	_, scanID := getScanInfo(db, jobID)
	if scanID == "" {
		return fmt.Errorf("scan not found")
	}

	// Get segmentation results
	updateJobProgress(db, jobID, 30)

	// Calculate canopy volume
	canopyVolume := 15.5 // Placeholder
	canopyDiameter := 3.2
	canopyHeight := 2.8

	// Apply regression model (placeholder)
	// Y = a * V + b (where Y is yield, V is canopy volume)
	estimatedYield := canopyVolume * 2.5 // kg per cubic meter

	// Save yield estimate
	saveYieldEstimate(db, scanID, map[string]interface{}{
		"canopy_volume_m3":   canopyVolume,
		"canopy_diameter_m":   canopyDiameter,
		"canopy_height_m":    canopyHeight,
		"estimated_yield_kg":  estimatedYield,
		"confidence_score":    0.75,
		"route_a_used":        true,
	})

	updateJobProgress(db, jobID, 100)
	return nil
}

func processYieldEstimationRouteB(ctx context.Context, db *pq.PsqlDatabase, jobID string) error {
	// Route B: Fruit detection
	// Uses ML-based fruit detection in point cloud
	log.Printf("Processing yield estimation (Route B) for job: %s", jobID)

	updateJobProgress(db, jobID, 10)

	// Get scan info
	_, scanID := getScanInfo(db, jobID)
	if scanID == "" {
		return fmt.Errorf("scan not found")
	}

	// Apply fruit detection model (placeholder)
	updateJobProgress(db, jobID, 40)

	// Count detected fruits
	fruitCount := 150 // Placeholder
	fruitSizeAvg := 65.5 // mm

	// Calculate yield from fruit count
	// Average fruit weight ~200g
	estimatedYield := float64(fruitCount) * 0.2

	saveYieldEstimate(db, scanID, map[string]interface{}{
		"fruit_count":         fruitCount,
		"fruit_size_avg_mm":   fruitSizeAvg,
		"estimated_yield_kg":  estimatedYield,
		"confidence_score":    0.85,
		"route_b_used":        true,
	})

	updateJobProgress(db, jobID, 100)
	return nil
}

// Helper functions

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getScanInfo(db *pq.PsqlDatabase, jobID string) (string, string) {
	// Query database for scan info
	// Returns file_url and scan_id
	return "", ""
}

func updateJobProgress(db *pq.PsqlDatabase, jobID string, progress int) {
	// Update processing_jobs set progress = $1, updated_at = NOW() where id = $2
	log.Printf("Job %s progress: %d%%", jobID, progress)
}

func updateJobStatus(db *pq.PqlDatabase, jobID string, err error) {
	if err != nil {
		// Update to FAILED
		log.Printf("Job %s failed: %v", jobID, err)
	} else {
		// Update to COMPLETED
		log.Printf("Job %s completed", jobID)
	}
}

func updateScanMetadata(db *pq.PsqlDatabase, scanID string, pointCount int) {
	// Update scans set point_count = $1, status = 'completed', updated_at = NOW() where id = $2
	log.Printf("Updated scan %s with point count: %d", scanID, pointCount)
}

func saveSegmentationResults(db *pq.PsqlDatabase, scanID string, results map[string]interface{}) {
	// Save segmentation results to processing_jobs result_data
	log.Printf("Saved segmentation results for scan %s", scanID)
}

func saveYieldEstimate(db *pq.PsqlDatabase, scanID string, results map[string]interface{}) {
	// Insert into yield_estimates table
	log.Printf("Saved yield estimate for scan %s: %.2f kg", scanID, results["estimated_yield_kg"])
}
