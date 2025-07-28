#!/bin/bash
# Test Redis Service

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_CONTAINER="station2290_redis"

echo "Testing Redis service..."

# Check if Redis is running
if docker ps --format "table {{.Names}}" | grep -q "$REDIS_CONTAINER"; then
    echo -e "${GREEN}✓ Redis container is running${NC}"
else
    echo -e "${RED}✗ Redis container is not running${NC}"
    echo "Checking container status..."
    docker ps -a --filter "name=$REDIS_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# Test port connectivity
echo "Testing Redis port connectivity on $REDIS_HOST:$REDIS_PORT..."
if timeout 5 nc -zv "$REDIS_HOST" "$REDIS_PORT" 2>&1 | grep -q "succeeded"; then
    echo -e "${GREEN}✓ Redis port $REDIS_PORT is accessible${NC}"
else
    echo -e "${RED}✗ Cannot connect to Redis port $REDIS_PORT${NC}"
    exit 1
fi

# Test Redis health
echo "Testing Redis health check..."
if docker exec "$REDIS_CONTAINER" redis-cli ping | grep -q "PONG"; then
    echo -e "${GREEN}✓ Redis is healthy and responding to PING${NC}"
else
    echo -e "${RED}✗ Redis health check failed${NC}"
    docker logs --tail 50 "$REDIS_CONTAINER"
    exit 1
fi

# Test Redis connection from host
echo "Testing Redis connection from host..."
if command -v redis-cli &> /dev/null; then
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping | grep -q "PONG"; then
        echo -e "${GREEN}✓ Redis connection from host successful${NC}"
    else
        echo -e "${RED}✗ Redis connection from host failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ redis-cli not found on host, skipping host connection test${NC}"
fi

# Check Redis info
echo "Checking Redis server info..."
REDIS_VERSION=$(docker exec "$REDIS_CONTAINER" redis-cli INFO server | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
if [ -n "$REDIS_VERSION" ]; then
    echo -e "${GREEN}✓ Redis version: $REDIS_VERSION${NC}"
else
    echo -e "${YELLOW}⚠ Could not determine Redis version${NC}"
fi

# Check Redis memory usage
echo "Checking Redis memory usage..."
MEMORY_USAGE=$(docker exec "$REDIS_CONTAINER" redis-cli INFO memory | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
if [ -n "$MEMORY_USAGE" ]; then
    echo "Redis memory usage: $MEMORY_USAGE"
fi

# Check Redis persistence
echo "Checking Redis persistence configuration..."
AOF_ENABLED=$(docker exec "$REDIS_CONTAINER" redis-cli CONFIG GET appendonly | tail -1)
if [ "$AOF_ENABLED" = "yes" ]; then
    echo -e "${GREEN}✓ AOF persistence is enabled${NC}"
else
    echo -e "${YELLOW}⚠ AOF persistence is disabled${NC}"
fi

# Check RDB saves
RDB_LASTSAVE=$(docker exec "$REDIS_CONTAINER" redis-cli LASTSAVE)
if [ -n "$RDB_LASTSAVE" ] && [ "$RDB_LASTSAVE" -gt 0 ]; then
    LASTSAVE_DATE=$(date -d "@$RDB_LASTSAVE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
    echo "Last RDB save: $LASTSAVE_DATE"
fi

# Check Redis connected clients
echo "Checking connected clients..."
CONNECTED_CLIENTS=$(docker exec "$REDIS_CONTAINER" redis-cli INFO clients | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
if [ -n "$CONNECTED_CLIENTS" ]; then
    echo "Connected clients: $CONNECTED_CLIENTS"
fi

# Test Redis operations
echo "Testing Redis operations..."
TEST_KEY="station2290:test:$(date +%s)"
TEST_VALUE="test_validation_$(date +%s)"

# Set a test key
if docker exec "$REDIS_CONTAINER" redis-cli SET "$TEST_KEY" "$TEST_VALUE" EX 60 | grep -q "OK"; then
    echo -e "${GREEN}✓ Redis SET operation successful${NC}"
    
    # Get the test key
    RETRIEVED_VALUE=$(docker exec "$REDIS_CONTAINER" redis-cli GET "$TEST_KEY")
    if [ "$RETRIEVED_VALUE" = "$TEST_VALUE" ]; then
        echo -e "${GREEN}✓ Redis GET operation successful${NC}"
        
        # Delete the test key
        if docker exec "$REDIS_CONTAINER" redis-cli DEL "$TEST_KEY" > /dev/null; then
            echo -e "${GREEN}✓ Redis DEL operation successful${NC}"
        fi
    else
        echo -e "${RED}✗ Redis GET operation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Redis SET operation failed${NC}"
    exit 1
fi

# Check Redis maxmemory policy
echo "Checking Redis memory policy..."
MAXMEMORY_POLICY=$(docker exec "$REDIS_CONTAINER" redis-cli CONFIG GET maxmemory-policy | tail -1)
if [ -n "$MAXMEMORY_POLICY" ]; then
    echo "Maxmemory policy: $MAXMEMORY_POLICY"
fi

echo -e "${GREEN}✓ Redis validation completed${NC}"
exit 0