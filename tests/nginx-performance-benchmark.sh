#!/bin/bash
# Nginx Performance Benchmark Script for Station2290
# Tests nginx performance under various load conditions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
NGINX_HOST="${NGINX_HOST:-localhost}"
NGINX_PORT="${NGINX_PORT:-80}"
BENCHMARK_DURATION="${BENCHMARK_DURATION:-30}"
REPORT_FILE="nginx-performance-report.md"

# Test endpoints
declare -A ENDPOINTS=(
    ["health"]="/health"
    ["api_root"]="/"
    ["static_asset"]="/static/test.css"
)

# Benchmark configurations
declare -A BENCHMARKS=(
    ["light"]="10 100"      # 10 connections, 100 requests/sec
    ["medium"]="50 500"     # 50 connections, 500 requests/sec
    ["heavy"]="100 1000"    # 100 connections, 1000 requests/sec
    ["stress"]="200 2000"   # 200 connections, 2000 requests/sec
)

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Nginx Performance Benchmark Report
Generated: $(date)
Host: $NGINX_HOST:$NGINX_PORT
Duration per test: ${BENCHMARK_DURATION}s

## Test Environment
- Host: $(hostname)
- CPU: $(sysctl -n hw.ncpu 2>/dev/null || nproc)
- Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo "N/A")
- OS: $(uname -s) $(uname -r)

## Benchmark Results

EOF
}

# Check dependencies
check_dependencies() {
    echo -e "${CYAN}Checking dependencies...${NC}"
    
    local deps=("ab" "curl" "jq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
        echo "Please install: ${missing[*]}"
        exit 1
    fi
    
    echo -e "${GREEN}All dependencies satisfied${NC}"
}

# Test endpoint availability
test_endpoint() {
    local endpoint=$1
    local url="http://${NGINX_HOST}:${NGINX_PORT}${endpoint}"
    
    if curl -sf -o /dev/null -w "%{http_code}" "$url" | grep -q "^[23]"; then
        return 0
    else
        return 1
    fi
}

# Run Apache Bench test
run_ab_test() {
    local endpoint=$1
    local connections=$2
    local requests_per_sec=$3
    local duration=$4
    local url="http://${NGINX_HOST}:${NGINX_PORT}${endpoint}"
    
    echo -e "${BLUE}Running benchmark: $endpoint (C:$connections, R:$requests_per_sec/s)${NC}"
    
    # Calculate total requests
    local total_requests=$((requests_per_sec * duration))
    
    # Run Apache Bench
    local ab_output=$(ab -n "$total_requests" -c "$connections" -t "$duration" \
        -H "Accept-Encoding: gzip,deflate" \
        -H "Accept: text/html,application/json" \
        "$url" 2>&1)
    
    # Parse results
    local requests_sec=$(echo "$ab_output" | grep "Requests per second" | awk '{print $4}')
    local time_per_req=$(echo "$ab_output" | grep "Time per request" | head -1 | awk '{print $4}')
    local transfer_rate=$(echo "$ab_output" | grep "Transfer rate" | awk '{print $3}')
    local failed_requests=$(echo "$ab_output" | grep "Failed requests" | awk '{print $3}')
    local non_2xx=$(echo "$ab_output" | grep "Non-2xx responses" | awk '{print $3}' || echo "0")
    
    # Calculate percentiles
    local p50=$(echo "$ab_output" | grep "50%" | awk '{print $2}')
    local p90=$(echo "$ab_output" | grep "90%" | awk '{print $2}')
    local p95=$(echo "$ab_output" | grep "95%" | awk '{print $2}')
    local p99=$(echo "$ab_output" | grep "99%" | awk '{print $2}')
    
    echo "$endpoint|$connections|$requests_per_sec|$requests_sec|$time_per_req|$transfer_rate|$failed_requests|$non_2xx|$p50|$p90|$p95|$p99"
}

# Monitor nginx during test
monitor_nginx() {
    local duration=$1
    local endpoint="http://${NGINX_HOST}:8080/nginx_status"
    local samples=()
    
    echo -e "${CYAN}Monitoring nginx metrics...${NC}"
    
    for ((i=0; i<duration; i+=5)); do
        if status=$(curl -sf "$endpoint" 2>/dev/null); then
            local active=$(echo "$status" | grep "Active" | awk '{print $3}')
            local reading=$(echo "$status" | grep "Reading" | awk '{print $2}')
            local writing=$(echo "$status" | grep "Reading" | awk '{print $4}')
            local waiting=$(echo "$status" | grep "Reading" | awk '{print $6}')
            samples+=("$active,$reading,$writing,$waiting")
        fi
        sleep 5
    done
    
    echo "${samples[@]}"
}

# Test SSL/TLS performance
test_ssl_performance() {
    echo -e "\n${PURPLE}=== SSL/TLS Performance Test ===${NC}"
    
    local ssl_endpoint="https://${NGINX_HOST}:443/health"
    
    # Test SSL handshake time
    echo -e "${BLUE}Testing SSL handshake performance...${NC}"
    
    local handshake_times=()
    for i in {1..10}; do
        local handshake_time=$(curl -w "%{time_appconnect}-%{time_connect}\n" -o /dev/null -s "$ssl_endpoint" | bc)
        handshake_times+=("$handshake_time")
    done
    
    # Calculate average
    local avg_handshake=$(printf '%s\n' "${handshake_times[@]}" | awk '{sum+=$1} END {print sum/NR}')
    
    echo "### SSL/TLS Performance" >> "$REPORT_FILE"
    echo "- Average SSL handshake time: ${avg_handshake}s" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Test compression performance
test_compression() {
    echo -e "\n${PURPLE}=== Compression Performance Test ===${NC}"
    
    # Create test files of different sizes
    local test_files=("1kb" "10kb" "100kb" "1mb")
    local compression_results=""
    
    for size in "${test_files[@]}"; do
        local url="http://${NGINX_HOST}:${NGINX_PORT}/test-${size}.json"
        
        # Test with and without compression
        local uncompressed=$(curl -sf -H "Accept-Encoding: identity" -w "%{size_download}" -o /dev/null "$url" 2>/dev/null || echo "0")
        local compressed=$(curl -sf -H "Accept-Encoding: gzip" -w "%{size_download}" -o /dev/null "$url" 2>/dev/null || echo "0")
        
        if [ "$uncompressed" -gt 0 ] && [ "$compressed" -gt 0 ]; then
            local ratio=$(echo "scale=2; (1 - $compressed / $uncompressed) * 100" | bc)
            compression_results+="- ${size}: ${ratio}% compression ratio\n"
        fi
    done
    
    echo "### Compression Performance" >> "$REPORT_FILE"
    echo -e "$compression_results" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Test caching performance
test_caching() {
    echo -e "\n${PURPLE}=== Caching Performance Test ===${NC}"
    
    local cache_endpoint="/api/cached-endpoint"
    local url="http://${NGINX_HOST}:${NGINX_PORT}${cache_endpoint}"
    
    # First request (cache miss)
    local miss_time=$(curl -w "%{time_total}" -o /dev/null -s "$url" 2>/dev/null || echo "0")
    
    # Second request (cache hit)
    local hit_time=$(curl -w "%{time_total}" -o /dev/null -s "$url" 2>/dev/null || echo "0")
    
    if [ "$miss_time" != "0" ] && [ "$hit_time" != "0" ]; then
        local improvement=$(echo "scale=2; (($miss_time - $hit_time) / $miss_time) * 100" | bc)
        
        echo "### Caching Performance" >> "$REPORT_FILE"
        echo "- Cache miss time: ${miss_time}s" >> "$REPORT_FILE"
        echo "- Cache hit time: ${hit_time}s" >> "$REPORT_FILE"
        echo "- Performance improvement: ${improvement}%" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

# Generate performance recommendations
generate_recommendations() {
    echo -e "\n${PURPLE}=== Generating Recommendations ===${NC}"
    
    cat >> "$REPORT_FILE" << 'EOF'

## Performance Recommendations

Based on the benchmark results, consider the following optimizations:

### 1. Connection Handling
- If seeing high connection wait times, increase `worker_connections`
- Consider enabling `multi_accept on` for high-traffic scenarios
- Tune `keepalive_timeout` based on your traffic patterns

### 2. Buffer Optimization
- Adjust `client_body_buffer_size` for large POST requests
- Tune `proxy_buffer_size` and `proxy_buffers` for backend responses
- Monitor `large_client_header_buffers` usage

### 3. Caching Strategy
- Enable proxy caching for static and semi-static content
- Configure appropriate cache zones and TTLs
- Use `proxy_cache_valid` to control cache duration

### 4. Compression Settings
- Enable Brotli compression for better ratios
- Adjust `gzip_comp_level` based on CPU vs bandwidth trade-off
- Add more MIME types to compression list

### 5. Rate Limiting
- Implement appropriate rate limits for different endpoints
- Use burst parameters to handle traffic spikes
- Consider different zones for different API endpoints

### 6. SSL/TLS Optimization
- Enable SSL session caching
- Use OCSP stapling to reduce handshake time
- Consider HTTP/2 for multiplexing benefits

EOF
}

# Main benchmark execution
run_benchmarks() {
    echo -e "\n${PURPLE}=== Running Performance Benchmarks ===${NC}"
    
    # Test each endpoint with different load levels
    echo "### Load Test Results" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for endpoint_name in "${!ENDPOINTS[@]}"; do
        local endpoint="${ENDPOINTS[$endpoint_name]}"
        
        # Check if endpoint is available
        if ! test_endpoint "$endpoint"; then
            echo -e "${YELLOW}Skipping $endpoint_name - endpoint not available${NC}"
            continue
        fi
        
        echo -e "\n${CYAN}Testing endpoint: $endpoint_name ($endpoint)${NC}"
        echo "#### Endpoint: $endpoint_name ($endpoint)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Table header
        echo "| Load Level | Connections | Target RPS | Actual RPS | Avg Response (ms) | Transfer Rate (KB/s) | Failed | Non-2xx | P50 | P90 | P95 | P99 |" >> "$REPORT_FILE"
        echo "|------------|-------------|------------|------------|-------------------|----------------------|--------|---------|-----|-----|-----|-----|" >> "$REPORT_FILE"
        
        for load_level in "${!BENCHMARKS[@]}"; do
            read -r connections requests_per_sec <<< "${BENCHMARKS[$load_level]}"
            
            # Run the benchmark
            result=$(run_ab_test "$endpoint" "$connections" "$requests_per_sec" "$BENCHMARK_DURATION")
            
            # Parse result
            IFS='|' read -r _ _ _ actual_rps avg_response transfer_rate failed non_2xx p50 p90 p95 p99 <<< "$result"
            
            # Add to report
            echo "| $load_level | $connections | $requests_per_sec | $actual_rps | $avg_response | $transfer_rate | $failed | $non_2xx | $p50 | $p90 | $p95 | $p99 |" >> "$REPORT_FILE"
            
            # Check for issues
            if [ "${failed:-0}" -gt 0 ] || [ "${non_2xx:-0}" -gt 0 ]; then
                echo -e "${RED}  Warning: Failed requests detected${NC}"
            fi
            
            # Cool down between tests
            sleep 5
        done
        
        echo "" >> "$REPORT_FILE"
    done
}

# Main execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    Station2290 Nginx Performance Benchmark Suite       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Initialize report
    init_report
    
    # Run benchmarks
    run_benchmarks
    
    # Additional performance tests
    test_ssl_performance
    test_compression
    test_caching
    
    # Generate recommendations
    generate_recommendations
    
    echo -e "\n${GREEN}Benchmark complete!${NC}"
    echo -e "${CYAN}Report saved to: ${REPORT_FILE}${NC}"
}

# Run main function
main "$@"