#!/bin/bash
# Test All Service Health Endpoints

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BASE_DOMAIN="${BASE_DOMAIN:-station2290.ru}"
USE_HTTPS="${USE_HTTPS:-false}"
PROTOCOL="http"

if [ "$USE_HTTPS" = "true" ]; then
    PROTOCOL="https"
fi

# Service endpoints
declare -A HEALTH_ENDPOINTS=(
    ["API"]="$PROTOCOL://api.$BASE_DOMAIN/health"
    ["Bot"]="$PROTOCOL://bot.$BASE_DOMAIN/health"
    ["Web"]="$PROTOCOL://$BASE_DOMAIN/api/health"
    ["Admin Panel"]="$PROTOCOL://adminka.$BASE_DOMAIN/"
    ["Order Panel"]="$PROTOCOL://orders.$BASE_DOMAIN/"
    ["Prometheus"]="$PROTOCOL://monitoring.$BASE_DOMAIN:9090/-/healthy"
    ["Grafana"]="$PROTOCOL://monitoring.$BASE_DOMAIN:3001/api/health"
)

# Local endpoints for testing without domain
declare -A LOCAL_ENDPOINTS=(
    ["API"]="http://localhost:3000/health"
    ["Bot"]="http://localhost:3001/health"
    ["Web"]="http://localhost:3000/api/health"
    ["Prometheus"]="http://localhost:9090/-/healthy"
    ["Grafana"]="http://localhost:3001/api/health"
)

echo -e "${BLUE}=== Testing All Service Health Endpoints ===${NC}"
echo "Protocol: $PROTOCOL"
echo "Domain: $BASE_DOMAIN"
echo ""

# Function to test health endpoint
test_health_endpoint() {
    local service="$1"
    local url="$2"
    local expected_code="${3:-200}"
    
    echo -n "Testing $service health endpoint: "
    
    # Test with curl
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
    
    if [ "$RESPONSE" = "$expected_code" ]; then
        echo -e "${GREEN}✓ OK (HTTP $RESPONSE)${NC}"
        return 0
    elif [ "$RESPONSE" = "000" ]; then
        echo -e "${RED}✗ Connection failed${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠ Unexpected response (HTTP $RESPONSE)${NC}"
        return 1
    fi
}

# Function to test detailed health response
test_detailed_health() {
    local service="$1"
    local url="$2"
    
    echo "Getting detailed health info for $service..."
    
    RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "{}")
    
    # Try to parse JSON response
    if echo "$RESPONSE" | jq . >/dev/null 2>&1; then
        # Check for common health indicators
        STATUS=$(echo "$RESPONSE" | jq -r '.status // .health // "unknown"' 2>/dev/null)
        
        if [ "$STATUS" = "ok" ] || [ "$STATUS" = "healthy" ] || [ "$STATUS" = "UP" ]; then
            echo -e "  Status: ${GREEN}$STATUS${NC}"
            
            # Check for database status
            DB_STATUS=$(echo "$RESPONSE" | jq -r '.database.status // .db // "N/A"' 2>/dev/null)
            if [ "$DB_STATUS" != "N/A" ]; then
                echo "  Database: $DB_STATUS"
            fi
            
            # Check for Redis status
            REDIS_STATUS=$(echo "$RESPONSE" | jq -r '.redis.status // .cache // "N/A"' 2>/dev/null)
            if [ "$REDIS_STATUS" != "N/A" ]; then
                echo "  Redis: $REDIS_STATUS"
            fi
            
            # Check uptime
            UPTIME=$(echo "$RESPONSE" | jq -r '.uptime // "N/A"' 2>/dev/null)
            if [ "$UPTIME" != "N/A" ]; then
                echo "  Uptime: $UPTIME"
            fi
        else
            echo -e "  Status: ${RED}$STATUS${NC}"
        fi
    else
        echo "  Response is not JSON or service is not providing detailed health info"
    fi
    echo ""
}

# Test domain-based endpoints
echo -e "${BLUE}Testing domain-based endpoints:${NC}"
echo "================================"

SUCCESS_COUNT=0
FAIL_COUNT=0

for service in "${!HEALTH_ENDPOINTS[@]}"; do
    if test_health_endpoint "$service" "${HEALTH_ENDPOINTS[$service]}"; then
        ((SUCCESS_COUNT++))
        # Get detailed health for certain services
        if [[ "$service" =~ ^(API|Bot|Web)$ ]]; then
            test_detailed_health "$service" "${HEALTH_ENDPOINTS[$service]}"
        fi
    else
        ((FAIL_COUNT++))
    fi
done

# Test local endpoints if running locally
echo ""
echo -e "${BLUE}Testing local endpoints:${NC}"
echo "========================"

LOCAL_SUCCESS=0
LOCAL_FAIL=0

for service in "${!LOCAL_ENDPOINTS[@]}"; do
    if test_health_endpoint "$service (local)" "${LOCAL_ENDPOINTS[$service]}"; then
        ((LOCAL_SUCCESS++))
    else
        ((LOCAL_FAIL++))
    fi
done

# Test container health checks
echo ""
echo -e "${BLUE}Testing Docker container health status:${NC}"
echo "======================================"

CONTAINERS=("station2290_postgres" "station2290_redis" "station2290_api" "station2290_bot" "station2290_web" "station2290_adminka" "station2290_order_panel" "station2290_nginx")

for container in "${CONTAINERS[@]}"; do
    echo -n "Container $container: "
    
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
    
    case $HEALTH_STATUS in
        "healthy")
            echo -e "${GREEN}✓ Healthy${NC}"
            ;;
        "unhealthy")
            echo -e "${RED}✗ Unhealthy${NC}"
            # Show last health check logs
            LAST_CHECK=$(docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$container" 2>/dev/null | tail -1)
            if [ -n "$LAST_CHECK" ]; then
                echo "  Last check output: $LAST_CHECK"
            fi
            ;;
        "starting")
            echo -e "${YELLOW}⚠ Starting${NC}"
            ;;
        "not_found")
            echo -e "${RED}✗ Container not found${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ No health check configured${NC}"
            ;;
    esac
done

# Summary
echo ""
echo -e "${BLUE}=== Health Check Summary ===${NC}"
echo "Domain endpoints: ${GREEN}$SUCCESS_COUNT passed${NC}, ${RED}$FAIL_COUNT failed${NC}"
echo "Local endpoints: ${GREEN}$LOCAL_SUCCESS passed${NC}, ${RED}$LOCAL_FAIL failed${NC}"

TOTAL_FAIL=$((FAIL_COUNT + LOCAL_FAIL))

if [ $TOTAL_FAIL -eq 0 ]; then
    echo -e "\n${GREEN}✓ All health checks passed!${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some health checks failed${NC}"
    exit 1
fi