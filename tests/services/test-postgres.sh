#!/bin/bash
# Test PostgreSQL Service

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
PG_HOST="${POSTGRES_HOST:-localhost}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_USER="${POSTGRES_USER:-station2290_user}"
PG_DB="${POSTGRES_DB:-station2290}"
PG_CONTAINER="station2290_postgres"

echo "Testing PostgreSQL service..."

# Check if PostgreSQL is running
if docker ps --format "table {{.Names}}" | grep -q "$PG_CONTAINER"; then
    echo -e "${GREEN}✓ PostgreSQL container is running${NC}"
else
    echo -e "${RED}✗ PostgreSQL container is not running${NC}"
    echo "Checking container status..."
    docker ps -a --filter "name=$PG_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# Test port connectivity
echo "Testing PostgreSQL port connectivity on $PG_HOST:$PG_PORT..."
if timeout 5 nc -zv "$PG_HOST" "$PG_PORT" 2>&1 | grep -q "succeeded"; then
    echo -e "${GREEN}✓ PostgreSQL port $PG_PORT is accessible${NC}"
else
    echo -e "${RED}✗ Cannot connect to PostgreSQL port $PG_PORT${NC}"
    exit 1
fi

# Test PostgreSQL health
echo "Testing PostgreSQL health check..."
if docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL is healthy and accepting connections${NC}"
else
    echo -e "${RED}✗ PostgreSQL health check failed${NC}"
    docker logs --tail 50 "$PG_CONTAINER"
    exit 1
fi

# Test database connection
echo "Testing database connection..."
if [ -n "${POSTGRES_PASSWORD:-}" ]; then
    export PGPASSWORD="$POSTGRES_PASSWORD"
    if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "SELECT version();" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Database connection successful${NC}"
    else
        echo -e "${RED}✗ Database connection failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Skipping database connection test (no password set)${NC}"
fi

# Check database size and tables
echo "Checking database statistics..."
if docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "\\l" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Can list databases${NC}"
    
    # Check table count
    TABLE_COUNT=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
    echo "Tables in database: $TABLE_COUNT"
    
    # Check database size
    DB_SIZE=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -c "SELECT pg_size_pretty(pg_database_size('$PG_DB'));" 2>/dev/null | tr -d ' ' || echo "unknown")
    echo "Database size: $DB_SIZE"
fi

# Check PostgreSQL configuration
echo "Checking PostgreSQL configuration..."
if docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -c "SHOW shared_buffers;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PostgreSQL configuration is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Cannot check PostgreSQL configuration${NC}"
fi

# Check replication status (if configured)
echo "Checking replication status..."
REPLICATION_STATUS=$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" -t -c "SELECT COUNT(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ' || echo "0")
if [ "$REPLICATION_STATUS" -gt 0 ]; then
    echo -e "${GREEN}✓ Replication is active ($REPLICATION_STATUS replicas)${NC}"
else
    echo -e "${YELLOW}⚠ No active replication${NC}"
fi

# Check backup directory
echo "Checking backup configuration..."
if docker exec "$PG_CONTAINER" test -d "/backups" 2>/dev/null; then
    echo -e "${GREEN}✓ Backup directory is mounted${NC}"
else
    echo -e "${YELLOW}⚠ Backup directory not found${NC}"
fi

echo -e "${GREEN}✓ PostgreSQL validation completed${NC}"
exit 0