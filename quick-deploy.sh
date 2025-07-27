#!/bin/bash

# Station2290 Infrastructure Deployment Script
# Deploys only infrastructure services (PostgreSQL, Redis, Nginx, Monitoring)
# Applications are deployed separately via GitHub Actions

# Remove 'set -e' to handle errors gracefully
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏗️ Station2290 Infrastructure Deployment${NC}"
echo "===========================================" 

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker/production/docker-compose.infrastructure.yml"
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
}

fatal_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] FATAL ERROR: $1${NC}"
    echo -e "${RED}Deployment failed. Existing services will continue running.${NC}"
    exit 1
}

# Function to check if a service is running
check_service() {
    local service=$1
    if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" ps "$service" 2>/dev/null | grep -q "Up"; then
        return 0
    else
        return 1
    fi
}

# Function to start a service with error handling
start_service() {
    local service=$1
    local description="$2"
    
    log "Starting $description..."
    if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" up -d "$service" 2>/dev/null; then
        log "$description started successfully"
        return 0
    else
        error "Failed to start $description"
        return 1
    fi
}

# Function to start multiple services with error handling
start_services() {
    local services="$1"
    local description="$2"
    
    log "Starting $description..."
    if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" up -d $services 2>/dev/null; then
        log "$description started successfully"
        return 0
    else
        error "Failed to start $description"
        return 1
    fi
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
        fatal_error "Template file not found. Please create $ENV_FILE manually."
    fi
fi

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
    set -a  # Automatically export all variables
    source "$ENV_FILE"
    set +a
    log "Environment variables loaded from $ENV_FILE"
else
    fatal_error "Environment file not found: $ENV_FILE"
fi

# Basic validation
if [[ "$POSTGRES_PASSWORD" == "CHANGE_THIS_SECURE_PASSWORD" ]] || [[ -z "$POSTGRES_PASSWORD" ]]; then
    fatal_error "Please update POSTGRES_PASSWORD in $ENV_FILE"
fi

if [[ "$JWT_SECRET" == "CHANGE_THIS_JWT_SECRET_MIN_32_CHARACTERS" ]] || [[ ${#JWT_SECRET} -lt 32 ]]; then
    fatal_error "Please update JWT_SECRET in $ENV_FILE (min 32 characters)"
fi

log "Environment configuration validated"

# Check Docker
if ! command -v docker &> /dev/null; then
    fatal_error "Docker is not installed"
fi

if ! docker info &> /dev/null; then
    fatal_error "Docker daemon is not running"
fi

# Check Docker Compose file
if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    fatal_error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
fi

log "Docker environment validated"

# Create required directories
log "Creating required directories..."
sudo mkdir -p /opt/station2290/{data,logs,ssl,backups,monitoring}
sudo chown -R $(whoami):docker /opt/station2290 2>/dev/null || true

# Create Docker network
log "Creating Docker network..."
docker network create station2290-network 2>/dev/null || true

# Check for existing running services
log "Checking existing services..."
EXISTING_SERVICES=()
for service in postgres redis nginx prometheus grafana loki certbot healthcheck; do
    if check_service "$service"; then
        EXISTING_SERVICES+=("$service")
        log "Found running service: $service"
    fi
done

if [[ ${#EXISTING_SERVICES[@]} -gt 0 ]]; then
    log "Found ${#EXISTING_SERVICES[@]} existing services running"
    echo -e "${YELLOW}Existing services will be updated gracefully${NC}"
else
    log "No existing services found - fresh deployment"
fi

# Pull images (this is safe and doesn't affect running containers)
log "Pulling Docker images..."
if ! docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" pull; then
    error "Failed to pull images, but continuing with existing images"
fi

# Start database services with error handling
if ! start_services "postgres redis" "database services (PostgreSQL, Redis)"; then
    error "Failed to start database services"
    if [[ ${#EXISTING_SERVICES[@]} -eq 0 ]]; then
        fatal_error "Cannot proceed without database services"
    else
        warn "Continuing with existing database services"
    fi
fi

# Wait for database
log "Waiting for database to be ready..."
sleep 30

# Check if database is ready
DATABASE_READY=false
for i in {1..10}; do
    if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" exec postgres pg_isready -U "${POSTGRES_USER:-station2290_user}" -d "${POSTGRES_DB:-station2290}" &>/dev/null; then
        log "Database is ready"
        DATABASE_READY=true
        break
    fi
    echo "Waiting for database... ($i/10)"
    sleep 5
done

if [[ "$DATABASE_READY" != "true" ]]; then
    warn "Database not responding, but continuing deployment"
fi

# Start monitoring services with error handling
if ! start_services "prometheus grafana loki" "monitoring services"; then
    warn "Some monitoring services failed to start, but continuing"
fi

# Start nginx reverse proxy with error handling
if ! start_service "nginx" "nginx reverse proxy"; then
    warn "Nginx failed to start, but continuing"
fi

# Start additional infrastructure services with error handling
if ! start_services "certbot healthcheck" "additional infrastructure services"; then
    warn "Some additional services failed to start, but continuing"
fi

# Check final service status
log "Checking final service status..."
if ! docker compose -f "$DOCKER_COMPOSE_FILE" --env-file="$ENV_FILE" ps; then
    warn "Could not check service status"
fi

# Generate deployment summary
SUCCESSFUL_SERVICES=()
FAILED_SERVICES=()

for service in postgres redis nginx prometheus grafana loki certbot healthcheck; do
    if check_service "$service"; then
        SUCCESSFUL_SERVICES+=("$service")
    else
        FAILED_SERVICES+=("$service")
    fi
done

echo ""
if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
    echo -e "${GREEN}✅ Infrastructure deployment completed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Infrastructure deployment completed with warnings${NC}"
fi
echo ""

echo "Service Status:"
for service in "${SUCCESSFUL_SERVICES[@]}"; do
    echo -e "  ✅ $service: ${GREEN}Running${NC}"
done

for service in "${FAILED_SERVICES[@]}"; do
    echo -e "  ❌ $service: ${RED}Failed${NC}"
done

echo ""
echo "Infrastructure services:"
if check_service "postgres"; then
    echo "  🗄️  PostgreSQL: localhost:5432"
fi
if check_service "redis"; then
    echo "  🔑 Redis: localhost:6379"
fi
if check_service "prometheus"; then
    echo "  📊 Prometheus: http://localhost:9090"
fi
if check_service "grafana"; then
    echo "  📈 Grafana: http://localhost:3001 (admin:${GRAFANA_ADMIN_PASSWORD:-admin})"
fi
if check_service "nginx"; then
    echo "  🌐 Nginx: http://localhost (reverse proxy ready)"
fi
if check_service "certbot"; then
    echo "  🛡️  Certbot: SSL certificate management"
fi
if check_service "healthcheck"; then
    echo "  ❤️  Health Check: Service monitoring"
fi

echo ""
echo -e "${YELLOW}Application Deployment:${NC}"
echo "  Applications (api, web, bot, adminka, order-panel) are deployed"
echo "  automatically via GitHub Actions when you push to their repositories."
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Push changes to application repositories to trigger deployments"
if check_service "nginx"; then
    echo "  2. Set up SSL certificates: ./ssl/setup-ssl.sh"
else
    echo "  2. Fix nginx issues, then set up SSL certificates"
fi
echo "  3. Monitor infrastructure: docker compose -f $DOCKER_COMPOSE_FILE --env-file=$ENV_FILE logs -f"
if check_service "grafana"; then
    echo "  4. Check Grafana dashboards: http://localhost:3001"
fi

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed services:${NC}"
    for service in "${FAILED_SERVICES[@]}"; do
        echo -e "${RED}  - $service${NC}"
    done
    echo ""
    echo -e "${YELLOW}To troubleshoot failed services:${NC}"
    echo "  docker compose -f $DOCKER_COMPOSE_FILE --env-file=$ENV_FILE logs <service-name>"
    echo "  docker compose -f $DOCKER_COMPOSE_FILE --env-file=$ENV_FILE up -d <service-name>"
fi

echo ""
if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
    echo -e "${BLUE}🎉 Infrastructure is ready! Applications will auto-deploy via GitHub Actions.${NC}"
else
    echo -e "${YELLOW}⚠️  Infrastructure partially deployed. Fix failed services and re-run script.${NC}"
fi