#!/bin/bash
# Test API Service

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
API_HOST="${API_HOST:-localhost}"
API_PORT="${API_PORT:-3000}"
API_CONTAINER="station2290_api"
API_BASE_URL="http://$API_HOST:$API_PORT"

echo "Testing API service..."

# Check if API container is running
if docker ps --format "table {{.Names}}" | grep -q "$API_CONTAINER"; then
    echo -e "${GREEN}✓ API container is running${NC}"
else
    echo -e "${RED}✗ API container is not running${NC}"
    echo "Checking container status..."
    docker ps -a --filter "name=$API_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# Wait for API to be ready
echo "Waiting for API to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" "$API_BASE_URL/health" | grep -q "200"; then
        echo -e "${GREEN}✓ API is ready${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for API... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗ API failed to become ready${NC}"
    docker logs --tail 100 "$API_CONTAINER"
    exit 1
fi

# Test health endpoint
echo "Testing API health endpoint..."
HEALTH_RESPONSE=$(curl -s "$API_BASE_URL/health")
if echo "$HEALTH_RESPONSE" | jq -e '.status == "ok"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health endpoint returns OK status${NC}"
else
    echo -e "${RED}✗ Health endpoint failed${NC}"
    echo "Response: $HEALTH_RESPONSE"
    exit 1
fi

# Test API documentation
echo "Testing API documentation endpoint..."
if curl -s -o /dev/null -w "%{http_code}" "$API_BASE_URL/api" | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ API documentation is accessible${NC}"
else
    echo -e "${YELLOW}⚠ API documentation endpoint not accessible${NC}"
fi

# Test database connectivity from API
echo "Testing database connectivity from API..."
DB_CHECK=$(docker exec "$API_CONTAINER" sh -c 'echo "SELECT 1" | psql $DATABASE_URL -t 2>&1' || echo "failed")
if echo "$DB_CHECK" | grep -q "1"; then
    echo -e "${GREEN}✓ API can connect to database${NC}"
else
    echo -e "${RED}✗ API cannot connect to database${NC}"
    echo "Database check output: $DB_CHECK"
    exit 1
fi

# Test Redis connectivity from API
echo "Testing Redis connectivity from API..."
if docker exec "$API_CONTAINER" sh -c 'redis-cli -h redis ping 2>/dev/null' | grep -q "PONG"; then
    echo -e "${GREEN}✓ API can connect to Redis${NC}"
else
    echo -e "${YELLOW}⚠ API cannot connect to Redis${NC}"
fi

# Test authentication endpoints
echo "Testing authentication endpoints..."

# Test login endpoint exists
if curl -s -o /dev/null -w "%{http_code}" -X POST "$API_BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d '{}' | grep -q "400\|401\|422"; then
    echo -e "${GREEN}✓ Login endpoint is responding${NC}"
else
    echo -e "${RED}✗ Login endpoint not responding correctly${NC}"
fi

# Test API rate limiting
echo "Testing API rate limiting..."
RATE_LIMIT_HEADER=$(curl -s -I "$API_BASE_URL/health" | grep -i "x-ratelimit-limit" || echo "")
if [ -n "$RATE_LIMIT_HEADER" ]; then
    echo -e "${GREEN}✓ Rate limiting is enabled${NC}"
    echo "Rate limit header: $RATE_LIMIT_HEADER"
else
    echo -e "${YELLOW}⚠ Rate limiting headers not found${NC}"
fi

# Check API logs for errors
echo "Checking API logs for recent errors..."
ERROR_COUNT=$(docker logs --tail 1000 "$API_CONTAINER" 2>&1 | grep -i "error" | wc -l || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ No errors found in recent logs${NC}"
else
    echo -e "${YELLOW}⚠ Found $ERROR_COUNT error entries in recent logs${NC}"
    echo "Recent errors:"
    docker logs --tail 1000 "$API_CONTAINER" 2>&1 | grep -i "error" | tail -5
fi

# Test CORS headers
echo "Testing CORS configuration..."
CORS_HEADERS=$(curl -s -I -X OPTIONS "$API_BASE_URL/health" \
    -H "Origin: https://station2290.ru" \
    -H "Access-Control-Request-Method: GET")

if echo "$CORS_HEADERS" | grep -q "Access-Control-Allow-Origin"; then
    echo -e "${GREEN}✓ CORS headers are configured${NC}"
else
    echo -e "${YELLOW}⚠ CORS headers not found${NC}"
fi

# Check API memory usage
echo "Checking API container resource usage..."
API_STATS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$API_CONTAINER" 2>/dev/null || echo "")
if [ -n "$API_STATS" ]; then
    echo "Resource usage:"
    echo "$API_STATS"
fi

echo -e "${GREEN}✓ API validation completed${NC}"
exit 0