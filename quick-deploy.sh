#!/bin/bash

# Quick Station2290 Deployment Script
# Simple deployment without all the advanced features

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Station2290 Quick Deployment${NC}"
echo "=================================="

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker/production/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/configs/environment/.env.prod"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if environment file exists
if [[ ! -f "$ENV_FILE" ]]; then
    warn "Environment file not found: $ENV_FILE"
    log "Creating from template..."
    
    if [[ -f "$SCRIPT_DIR/configs/environment/.env.prod.template" ]]; then
        cp "$SCRIPT_DIR/configs/environment/.env.prod.template" "$ENV_FILE"
        log "Environment file created from template"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT: Edit $ENV_FILE and update all placeholder values!${NC}"
        echo "Required changes:"
        echo "  - POSTGRES_PASSWORD"
        echo "  - JWT_SECRET (min 32 characters)"
        echo "  - JWT_REFRESH_SECRET (min 32 characters)" 
        echo "  - GRAFANA_ADMIN_PASSWORD"
        echo "  - SSL_EMAIL (your email)"
        echo "  - OPENAI_API_KEY (if using bot)"
        echo "  - WHATSAPP tokens (if using bot)"
        echo ""
        read -p "Press Enter after editing the environment file..."
    else
        error "Template file not found. Please create $ENV_FILE manually."
    fi
fi

# Load environment variables
source "$ENV_FILE"

# Basic validation
if [[ "$POSTGRES_PASSWORD" == "CHANGE_THIS_SECURE_PASSWORD" ]] || [[ -z "$POSTGRES_PASSWORD" ]]; then
    error "Please update POSTGRES_PASSWORD in $ENV_FILE"
fi

if [[ "$JWT_SECRET" == "CHANGE_THIS_JWT_SECRET_MIN_32_CHARACTERS" ]] || [[ ${#JWT_SECRET} -lt 32 ]]; then
    error "Please update JWT_SECRET in $ENV_FILE (min 32 characters)"
fi

log "Environment configuration validated"

# Check Docker
if ! command -v docker &> /dev/null; then
    error "Docker is not installed"
fi

if ! docker info &> /dev/null; then
    error "Docker daemon is not running"
fi

# Check Docker Compose file
if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
fi

log "Docker environment validated"

# Create required directories
log "Creating required directories..."
sudo mkdir -p /opt/station2290/{data,logs,ssl,backups,monitoring}
sudo chown -R $(whoami):docker /opt/station2290 2>/dev/null || true

# Create Docker network
log "Creating Docker network..."
docker network create station2290-network 2>/dev/null || true

# Stop any existing containers
log "Stopping existing containers..."
docker-compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans 2>/dev/null || true

# Pull images
log "Pulling Docker images..."
docker-compose -f "$DOCKER_COMPOSE_FILE" pull

# Start infrastructure services
log "Starting infrastructure services (PostgreSQL, Redis)..."
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres redis

# Wait for database
log "Waiting for database to be ready..."
sleep 30

# Check if database is ready
for i in {1..10}; do
    if docker-compose -f "$DOCKER_COMPOSE_FILE" exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null; then
        log "Database is ready"
        break
    fi
    echo "Waiting for database... ($i/10)"
    sleep 5
done

# Start monitoring services
log "Starting monitoring services..."
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d prometheus grafana loki

# Start nginx
log "Starting nginx reverse proxy..."
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d nginx

# Check services
log "Checking service status..."
docker-compose -f "$DOCKER_COMPOSE_FILE" ps

echo ""
echo -e "${GREEN}✅ Infrastructure deployment completed!${NC}"
echo ""
echo "Services started:"
echo "  🗄️  PostgreSQL: localhost:5432"
echo "  🔑 Redis: localhost:6379" 
echo "  📊 Prometheus: http://localhost:9090"
echo "  📈 Grafana: http://localhost:3001 (admin:${GRAFANA_ADMIN_PASSWORD})"
echo "  🌐 Nginx: http://localhost"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Configure your domain DNS to point to this server"
echo "  2. Deploy your applications via GitHub Actions"
echo "  3. Set up SSL certificates: ./deployment/ssl/setup-ssl.sh"
echo "  4. Monitor logs: docker-compose -f $DOCKER_COMPOSE_FILE logs -f"
echo ""
echo -e "${BLUE}Infrastructure is ready for application deployment!${NC}"