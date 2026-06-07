/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's shaders.
*/

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

// Camera's RGB vertex shader outputs
struct RGBVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
constexpr sampler nearestSampler(mip_filter::nearest, mag_filter::nearest, min_filter::nearest);
constant auto yCbCrToRGB = float4x4(float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));
constant float2 viewVertices[] = { float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1) };
constant float2 viewTexCoords[] = { float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1) };

/// Retrieves the world position of a specified camera point with depth
static simd_float4 worldPoint(simd_float2 cameraPoint, float depth, matrix_float3x3 cameraIntrinsicsInversed, matrix_float4x4 localToWorld) {
    const auto localPoint = cameraIntrinsicsInversed * simd_float3(cameraPoint, 1) * depth;
    const auto worldPoint = localToWorld * simd_float4(localPoint, 1);
    
    return worldPoint / worldPoint.w;
}

///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            device ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]],
                            constant float2 *gridPoints [[buffer(kGridPoints)]],
                            texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                            texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]) {

    const auto gridPoint = gridPoints[vertexID];
    const auto currentPointIndex = (uniforms.pointCloudCurrentIndex + vertexID) % uniforms.maxPoints;
    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;

    // Filter: skip points outside depth range (0.5m - 5m) or zero depth
    if (depth < uniforms.minDepth || depth > uniforms.maxDepth || depth <= 0.0) {
        particleUniforms[currentPointIndex].confidence = 0.0f;  // Mark as invalid
        return;
    }

    // Filter flying pixels near depth discontinuities. Consumer LiDAR often produces
    // unstable edges around leaves, branches, and fruit boundaries.
    if (uniforms.depthEdgeThreshold > 0.0f) {
        const float2 texel = 1.0f / float2(depthTexture.get_width(), depthTexture.get_height());
        int stableNeighbors = 0;

        float neighborDepth = depthTexture.sample(colorSampler, texCoord + float2(texel.x, 0)).r;
        if (neighborDepth >= uniforms.minDepth &&
            neighborDepth <= uniforms.maxDepth &&
            abs(neighborDepth - depth) <= uniforms.depthEdgeThreshold) {
            stableNeighbors += 1;
        }

        neighborDepth = depthTexture.sample(colorSampler, texCoord - float2(texel.x, 0)).r;
        if (neighborDepth >= uniforms.minDepth &&
            neighborDepth <= uniforms.maxDepth &&
            abs(neighborDepth - depth) <= uniforms.depthEdgeThreshold) {
            stableNeighbors += 1;
        }

        neighborDepth = depthTexture.sample(colorSampler, texCoord + float2(0, texel.y)).r;
        if (neighborDepth >= uniforms.minDepth &&
            neighborDepth <= uniforms.maxDepth &&
            abs(neighborDepth - depth) <= uniforms.depthEdgeThreshold) {
            stableNeighbors += 1;
        }

        neighborDepth = depthTexture.sample(colorSampler, texCoord - float2(0, texel.y)).r;
        if (neighborDepth >= uniforms.minDepth &&
            neighborDepth <= uniforms.maxDepth &&
            abs(neighborDepth - depth) <= uniforms.depthEdgeThreshold) {
            stableNeighbors += 1;
        }

        if (stableNeighbors < 2) {
            particleUniforms[currentPointIndex].confidence = 0.0f;
            return;
        }
    }

    // With a 2D point plus depth, we can now get its 3D position
    const auto position = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);

    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    const auto ycbcr = float4(capturedImageTextureY.sample(colorSampler, texCoord).r, capturedImageTextureCbCr.sample(colorSampler, texCoord.xy).rg, 1);
    const auto sampledColor = (yCbCrToRGB * ycbcr).rgb;
    // Sample the confidence map to get the confidence value
    const auto confidence = confidenceTexture.sample(nearestSampler, texCoord).r;

    // Write the data to the buffer
    particleUniforms[currentPointIndex].position = position.xyz;
    particleUniforms[currentPointIndex].color = sampledColor;
    particleUniforms[currentPointIndex].confidence = confidence;
}

vertex RGBVertexOut rgbVertex(uint vertexID [[vertex_id]],
                              constant RGBUniforms &uniforms [[buffer(0)]]) {
    const float3 texCoord = float3(viewTexCoords[vertexID], 1) * uniforms.viewToCamera;
    
    RGBVertexOut out;
    out.position = float4(viewVertices[vertexID], 0, 1);
    out.texCoord = texCoord.xy;
    
    return out;
}

fragment float4 rgbFragment(RGBVertexOut in [[stage_in]],
                            constant RGBUniforms &uniforms [[buffer(0)]],
                            texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                            texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]]) {
    
    const float2 offset = (in.texCoord - 0.5) * float2(1, 1 / uniforms.viewRatio) * 2;
    const float visibility = saturate(uniforms.radius * uniforms.radius - length_squared(offset));
    const float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, in.texCoord.xy).r, capturedImageTextureCbCr.sample(colorSampler, in.texCoord.xy).rg, 1);
    
    // convert and save the color back to the buffer
    const float3 sampledColor = (yCbCrToRGB * ycbcr).rgb;
    return float4(sampledColor, 1) * visibility;
}

vertex ParticleVertexOut particleVertex(uint vertexID [[vertex_id]],
                                        constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                                        constant ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]]) {
    
    // get point data
    const auto particleData = particleUniforms[vertexID];
    const auto position = particleData.position;
    const auto confidence = particleData.confidence;
    const auto sampledColor = particleData.color;
    const auto visibility = confidence >= uniforms.confidenceThreshold;
    
    // animate and project the point
    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(position, 1.0);
    const float pointSize = max(uniforms.particleSize / max(1.0, projectedPosition.z), 2.0);
    projectedPosition /= projectedPosition.w;
    
    // prepare for output
    ParticleVertexOut out;
    out.position = projectedPosition;
    out.pointSize = pointSize;
    out.color = float4(sampledColor, visibility);
    
    return out;
}

fragment float4 particleFragment(ParticleVertexOut in [[stage_in]],
                                 const float2 coords [[point_coord]]) {
    // we draw within a circle
    const float distSquared = length_squared(coords - float2(0.5));
    if (in.color.a == 0 || distSquared > 0.25) {
        discard_fragment();
    }

    return in.color;
}

// MARK: - Compute Shaders for Point Cloud Processing

struct VoxelFilterUniforms {
    float voxelSize;
    int pointCount;
    int maxPoints;
    int confidenceThreshold;
    int pointStartIndex;     // ring buffer start
};

// Compute shader: mark each particle with its voxel key hash.
// Output: per-particle voxel hash (uint) for CPU-side dedup, or 0 for invalid particles.
kernel void computeVoxelKeys(
    constant ParticleUniforms *particles [[buffer(0)]],
    device uint *voxelKeys [[buffer(1)]],
    constant VoxelFilterUniforms &uniforms [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (int(gid) >= uniforms.pointCount) return;

    const int bufferIndex = (uniforms.pointStartIndex - uniforms.pointCount + int(gid) + uniforms.maxPoints) % uniforms.maxPoints;
    const auto particle = particles[bufferIndex];

    // Validate particle
    if (particle.confidence < float(uniforms.confidenceThreshold)) {
        voxelKeys[gid] = 0;
        return;
    }
    const auto pos = particle.position;
    if (!isfinite(pos.x) || !isfinite(pos.y) || !isfinite(pos.z)) {
        voxelKeys[gid] = 0;
        return;
    }
    if (length_squared(pos) < 0.000001f) {
        voxelKeys[gid] = 0;
        return;
    }

    // Compute voxel key hash
    const float invVoxel = 1.0f / uniforms.voxelSize;
    const int vx = int(floor(pos.x * invVoxel));
    const int vy = int(floor(pos.y * invVoxel));
    const int vz = int(floor(pos.z * invVoxel));

    // FNV-1a inspired hash (non-zero for valid points)
    uint h = 2166136261u;
    h ^= uint(vx); h *= 16777619u;
    h ^= uint(vy); h *= 16777619u;
    h ^= uint(vz); h *= 16777619u;
    // Ensure non-zero (0 reserved for invalid)
    voxelKeys[gid] = (h == 0) ? 1u : h;
}

// Compute shader: compute per-particle neighbor count within a radius.
// Used for fast SOR pre-filter on GPU (count neighbors, CPU does threshold).
kernel void computeNeighborCounts(
    constant ParticleUniforms *particles [[buffer(0)]],
    device uint *neighborCounts [[buffer(1)]],
    constant VoxelFilterUniforms &uniforms [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (int(gid) >= uniforms.pointCount) return;

    const int myIdx = (uniforms.pointStartIndex - uniforms.pointCount + int(gid) + uniforms.maxPoints) % uniforms.maxPoints;
    const auto myPos = particles[myIdx].position;

    if (particles[myIdx].confidence < float(uniforms.confidenceThreshold)) {
        neighborCounts[gid] = 0;
        return;
    }

    const float radius = uniforms.voxelSize * 3.0f; // search radius = 3x voxel size
    const float radiusSq = radius * radius;
    uint count = 0;

    // Sample a subset of points for efficiency (every 8th point)
    for (int i = 0; i < uniforms.pointCount; i += 8) {
        if (i == int(gid)) continue;
        const int idx = (uniforms.pointStartIndex - uniforms.pointCount + i + uniforms.maxPoints) % uniforms.maxPoints;
        const auto otherPos = particles[idx].position;
        if (particles[idx].confidence < float(uniforms.confidenceThreshold)) continue;

        const float distSq = length_squared(myPos - otherPos);
        if (distSq < radiusSq) {
            count++;
            if (count >= 32) break; // cap for performance
        }
    }

    neighborCounts[gid] = count;
}
