#!/bin/bash

# Simple one-command deployment for VPS
# Run from infrastructure repo root

set -e

echo "🚀 Station 2290 - Deploy Now!"
echo "=============================="

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Debug: Show current directory and files
print_info "Current directory: $(pwd)"
print_info "Directory contents:"
ls -la

print_info "Looking for Docker files:"
find . -name "docker-compose*.yml" -type f || echo "No Docker Compose files found"

# Check if we can see the Docker directory
if [[ -d "docker" ]]; then
    print_success "Found docker/ directory"
    ls -la docker/
    
    if [[ -d "docker/production" ]]; then
        print_success "Found docker/production/ directory"
        ls -la docker/production/
    else
        print_error "docker/production/ directory not found"
    fi
else
    print_error "docker/ directory not found in $(pwd)"
fi

# If Docker Compose file exists, deploy directly without cd
COMPOSE_FILE="docker/production/docker-compose.infrastructure.yml"

if [[ -f "$COMPOSE_FILE" ]]; then
    print_success "Found Docker Compose file: $COMPOSE_FILE"
    
    # Create simple override in the same directory
    cat > docker/production/docker-compose.override.yml << 'EOF'
version: '3.8'
services:
  postgres:
    deploy:
      resources:
        limits:
          memory: 256M
    environment:
      POSTGRES_SHARED_BUFFERS: 32MB
  redis:
    deploy:
      resources:
        limits:
          memory: 64M
    command: redis-server --maxmemory 48mb --maxmemory-policy allkeys-lru --appendonly yes
  nginx:
    deploy:
      resources:
        limits:
          memory: 64M
  grafana:
    deploy:
      resources:
        limits:
          memory: 128M
    environment:
      GF_INSTALL_PLUGINS: ""
  prometheus:
    deploy:
      resources:
        limits:
          memory: 256M
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=24h'
  loki:
    deploy:
      resources:
        limits:
          memory: 128M
EOF
    
    print_success "Created memory override"
    
    # Test configuration
    print_info "Testing configuration..."
    if docker compose -f "$COMPOSE_FILE" -f docker/production/docker-compose.override.yml config > /dev/null 2>&1; then
        print_success "Configuration valid"
    else
        print_error "Configuration invalid"
    fi
    
    # Deploy
    print_info "Stopping existing containers..."
    docker compose -f "$COMPOSE_FILE" down || true
    
    print_info "Starting core services..."
    docker compose -f "$COMPOSE_FILE" -f docker/production/docker-compose.override.yml up -d postgres redis nginx
    
    sleep 10
    
    print_info "Starting monitoring..."
    docker compose -f "$COMPOSE_FILE" -f docker/production/docker-compose.override.yml up -d prometheus grafana loki
    
    print_success "🎉 Deployment complete!"
    
    # Show status
    print_info "Container status:"
    docker compose -f "$COMPOSE_FILE" ps
    
    print_info "Memory usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}" 2>/dev/null || echo "Stats not available"
    
    print_success "Services available at:"
    echo "  - Nginx: http://85.193.95.44"
    echo "  - Grafana: http://85.193.95.44:3001 (admin/Gr@fana2024!)"
    echo "  - Prometheus: http://85.193.95.44:9090"
    
else
    print_error "Docker Compose file not found: $COMPOSE_FILE"
fi