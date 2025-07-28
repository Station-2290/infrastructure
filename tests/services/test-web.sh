#!/bin/bash
# Test Web Service (Next.js)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
WEB_HOST="${WEB_HOST:-localhost}"
WEB_PORT="${WEB_PORT:-3000}"
WEB_CONTAINER="station2290_web"
WEB_BASE_URL="http://$WEB_HOST:$WEB_PORT"

echo "Testing Web service (Next.js)..."

# Check if Web container is running
if docker ps --format "table {{.Names}}" | grep -q "$WEB_CONTAINER"; then
    echo -e "${GREEN}✓ Web container is running${NC}"
else
    echo -e "${RED}✗ Web container is not running${NC}"
    echo "Checking container status..."
    docker ps -a --filter "name=$WEB_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# Wait for Web service to be ready
echo "Waiting for Web service to be ready..."
MAX_RETRIES=60  # Next.js can take longer to start
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL/api/health" | grep -q "200"; then
        echo -e "${GREEN}✓ Web service is ready${NC}"
        break
    elif curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL/" | grep -q "200"; then
        echo -e "${GREEN}✓ Web service is responding (health endpoint may not exist)${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for Web service... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗ Web service failed to become ready${NC}"
    docker logs --tail 100 "$WEB_CONTAINER"
    exit 1
fi

# Test health endpoint (if exists)
echo "Testing Web health endpoint..."
HEALTH_RESPONSE=$(curl -s "$WEB_BASE_URL/api/health" 2>/dev/null || echo "not_found")
if [ "$HEALTH_RESPONSE" != "not_found" ]; then
    if echo "$HEALTH_RESPONSE" | jq -e '.status == "ok"' > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Health endpoint returns OK status${NC}"
    else
        echo -e "${YELLOW}⚠ Health endpoint exists but status unclear${NC}"
        echo "Response: $HEALTH_RESPONSE"
    fi
else
    # Test main page instead
    MAIN_PAGE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL/")
    if [ "$MAIN_PAGE_RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ Main page is accessible (health endpoint not configured)${NC}"
    else
        echo -e "${RED}✗ Web service not responding properly${NC}"
        exit 1
    fi
fi

# Test main routes
echo "Testing main Web routes..."
ROUTES=("/" "/about" "/contact" "/menu")

for route in "${ROUTES[@]}"; do
    ROUTE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL$route")
    if [ "$ROUTE_RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ Route '$route' is accessible${NC}"
    elif [ "$ROUTE_RESPONSE" = "404" ]; then
        echo -e "${YELLOW}⚠ Route '$route' returns 404 (may not be implemented)${NC}"
    else
        echo -e "${YELLOW}⚠ Route '$route' returned HTTP $ROUTE_RESPONSE${NC}"
    fi
done

# Check if Next.js is properly configured
echo "Checking Next.js configuration..."

# Check for Next.js specific headers
NEXT_HEADERS=$(curl -s -I "$WEB_BASE_URL/" | grep -i "x-powered-by" || echo "")
if echo "$NEXT_HEADERS" | grep -q "Next.js"; then
    echo -e "${GREEN}✓ Next.js is properly configured${NC}"
else
    # Check for other Next.js indicators
    NEXT_RESPONSE=$(curl -s "$WEB_BASE_URL/" | head -20)
    if echo "$NEXT_RESPONSE" | grep -q "_next"; then
        echo -e "${GREEN}✓ Next.js assets detected${NC}"
    else
        echo -e "${YELLOW}⚠ Next.js configuration unclear${NC}"
    fi
fi

# Test static assets
echo "Testing static assets..."
STATIC_ASSETS=("/favicon.ico" "/_next/static/chunks/webpack.js")

for asset in "${STATIC_ASSETS[@]}"; do
    ASSET_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL$asset" 2>/dev/null || echo "000")
    if [ "$ASSET_RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ Static asset '$asset' is accessible${NC}"
    elif [ "$ASSET_RESPONSE" = "404" ]; then
        echo -e "${YELLOW}⚠ Static asset '$asset' not found (may be normal)${NC}"
    else
        echo -e "${YELLOW}⚠ Static asset '$asset' returned HTTP $ASSET_RESPONSE${NC}"
    fi
done

# Check Web service configuration
echo "Checking Web service configuration..."

# Check if API URL is configured
if docker exec "$WEB_CONTAINER" sh -c 'test -n "${NEXT_PUBLIC_API_URL:-}"' 2>/dev/null; then
    API_URL=$(docker exec "$WEB_CONTAINER" sh -c 'echo ${NEXT_PUBLIC_API_URL}' 2>/dev/null || echo "not_set")
    echo -e "${GREEN}✓ NEXT_PUBLIC_API_URL is configured: $API_URL${NC}"
else
    echo -e "${YELLOW}⚠ NEXT_PUBLIC_API_URL may not be configured${NC}"
fi

# Check NextAuth configuration
if docker exec "$WEB_CONTAINER" sh -c 'test -n "${NEXTAUTH_SECRET:-}"' 2>/dev/null; then
    echo -e "${GREEN}✓ NextAuth secret is configured${NC}"
else
    echo -e "${YELLOW}⚠ NextAuth secret may not be configured${NC}"
fi

# Test API connectivity from Web service
echo "Testing API connectivity from Web service..."
if docker exec "$WEB_CONTAINER" sh -c 'curl -s -f http://api:3000/health > /dev/null' 2>/dev/null; then
    echo -e "${GREEN}✓ Web service can connect to API${NC}"
else
    echo -e "${YELLOW}⚠ Web service cannot connect to API (may use external URL)${NC}"
fi

# Check for build optimization
echo "Checking Next.js build optimization..."
if docker exec "$WEB_CONTAINER" test -d "/app/.next" 2>/dev/null; then
    echo -e "${GREEN}✓ Next.js build directory exists${NC}"
    
    # Check for optimized builds
    if docker exec "$WEB_CONTAINER" test -f "/app/.next/BUILD_ID" 2>/dev/null; then
        BUILD_ID=$(docker exec "$WEB_CONTAINER" cat "/app/.next/BUILD_ID" 2>/dev/null || echo "unknown")
        echo "Build ID: $BUILD_ID"
    fi
else
    echo -e "${YELLOW}⚠ Next.js build directory not found${NC}"
fi

# Check Web service logs for errors
echo "Checking Web service logs for recent errors..."
ERROR_COUNT=$(docker logs --tail 1000 "$WEB_CONTAINER" 2>&1 | grep -i "error" | grep -v "warn" | wc -l || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ No errors found in recent logs${NC}"
else
    echo -e "${YELLOW}⚠ Found $ERROR_COUNT error entries in recent logs${NC}"
    echo "Recent errors:"
    docker logs --tail 1000 "$WEB_CONTAINER" 2>&1 | grep -i "error" | grep -v "warn" | tail -5
fi

# Test SEO and meta tags
echo "Testing SEO and meta tags..."
MAIN_PAGE_CONTENT=$(curl -s "$WEB_BASE_URL/" 2>/dev/null || echo "")
if echo "$MAIN_PAGE_CONTENT" | grep -q "<title>"; then
    echo -e "${GREEN}✓ Page has title tag${NC}"
else
    echo -e "${YELLOW}⚠ No title tag found${NC}"
fi

if echo "$MAIN_PAGE_CONTENT" | grep -q "<meta.*description"; then
    echo -e "${GREEN}✓ Page has meta description${NC}"
else
    echo -e "${YELLOW}⚠ No meta description found${NC}"
fi

# Check robots.txt
ROBOTS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_BASE_URL/robots.txt")
if [ "$ROBOTS_RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓ robots.txt is accessible${NC}"
else
    echo -e "${YELLOW}⚠ robots.txt not found${NC}"
fi

# Check memory usage
echo "Checking Web container resource usage..."
WEB_STATS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$WEB_CONTAINER" 2>/dev/null || echo "")
if [ -n "$WEB_STATS" ]; then
    echo "Resource usage:"
    echo "$WEB_STATS"
fi

echo -e "${GREEN}✓ Web service validation completed${NC}"
exit 0