#!/bin/bash
# Test Docker Compose Configuration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

DOCKER_COMPOSE_FILE="../../docker/production/docker-compose.yml"
INFRA_COMPOSE_FILE="../../docker/production/docker-compose.infrastructure.yml"

echo "Testing Docker Compose configuration..."

# Test main docker-compose.yml
if [ -f "$DOCKER_COMPOSE_FILE" ]; then
    echo "Validating main docker-compose.yml..."
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Main docker-compose.yml is valid${NC}"
    else
        echo -e "${RED}✗ Main docker-compose.yml has errors:${NC}"
        docker-compose -f "$DOCKER_COMPOSE_FILE" config 2>&1
        exit 1
    fi
else
    echo -e "${RED}✗ Main docker-compose.yml not found${NC}"
    exit 1
fi

# Test infrastructure docker-compose
if [ -f "$INFRA_COMPOSE_FILE" ]; then
    echo "Validating infrastructure docker-compose.yml..."
    if docker-compose -f "$INFRA_COMPOSE_FILE" config > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Infrastructure docker-compose.yml is valid${NC}"
    else
        echo -e "${RED}✗ Infrastructure docker-compose.yml has errors:${NC}"
        docker-compose -f "$INFRA_COMPOSE_FILE" config 2>&1
        exit 1
    fi
else
    echo -e "${RED}✗ Infrastructure docker-compose.yml not found${NC}"
    exit 1
fi

# Check for required services
echo "Checking required services in configuration..."
REQUIRED_SERVICES=("postgres" "redis" "api" "bot" "web" "adminka" "order-panel" "nginx" "prometheus" "grafana")

for service in "${REQUIRED_SERVICES[@]}"; do
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config --services 2>/dev/null | grep -q "^$service$"; then
        echo -e "${GREEN}✓ Service '$service' is defined${NC}"
    else
        echo -e "${RED}✗ Service '$service' is missing${NC}"
        exit 1
    fi
done

# Check volume definitions
echo "Checking volume definitions..."
REQUIRED_VOLUMES=("postgres_data" "redis_data" "nginx_logs" "api_uploads" "prometheus_data" "grafana_data")

for volume in "${REQUIRED_VOLUMES[@]}"; do
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config | grep -q "$volume:"; then
        echo -e "${GREEN}✓ Volume '$volume' is defined${NC}"
    else
        echo -e "${RED}✗ Volume '$volume' is missing${NC}"
        exit 1
    fi
done

# Check network definitions
echo "Checking network definitions..."
REQUIRED_NETWORKS=("station2290_network" "monitoring_network" "database_network")

for network in "${REQUIRED_NETWORKS[@]}"; do
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config | grep -q "$network:"; then
        echo -e "${GREEN}✓ Network '$network' is defined${NC}"
    else
        echo -e "${RED}✗ Network '$network' is missing${NC}"
        exit 1
    fi
done

# Check health checks
echo "Checking health check definitions..."
SERVICES_WITH_HEALTH=("postgres" "redis" "api" "bot" "web" "adminka" "order-panel" "nginx")

for service in "${SERVICES_WITH_HEALTH[@]}"; do
    if docker-compose -f "$DOCKER_COMPOSE_FILE" config | grep -A 10 "$service:" | grep -q "healthcheck:"; then
        echo -e "${GREEN}✓ Health check defined for '$service'${NC}"
    else
        echo -e "${YELLOW}⚠ No health check for '$service'${NC}"
    fi
done

echo -e "${GREEN}✓ Docker Compose configuration validation completed${NC}"
exit 0