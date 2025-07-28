#!/bin/bash

# Quick VPS deployment script with correct paths
# Based on the actual repository structure

set -e

echo "🚀 Station 2290 Quick VPS Deployment"
echo "======================================"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check current directory and find docker-compose file
check_environment() {
    print_status "Checking environment..."
    
    # We should be in the infrastructure repo root
    if [[ ! -f "docker/production/docker-compose.infrastructure.yml" ]]; then
        print_error "Docker Compose file not found at expected location"
        print_status "Current directory: $(pwd)"
        print_status "Looking for: docker/production/docker-compose.infrastructure.yml"
        
        # Try to find it
        print_status "Searching for Docker Compose files..."
        find . -name "docker-compose*.yml" -type f
        
        exit 1
    fi
    
    print_success "Found Docker Compose configuration"
}

# Create the docker-compose override for memory optimization
create_override() {
    print_status "Creating memory-optimized override..."
    
    cat > docker/production/docker-compose.override.yml << 'EOF'
version: '3.8'

# Memory-optimized overrides for 1.2GB VPS
services:
  postgres:
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: 0.5
        reservations:
          memory: 128M
    environment:
      POSTGRES_SHARED_BUFFERS: 32MB
      POSTGRES_EFFECTIVE_CACHE_SIZE: 128MB
      POSTGRES_WORK_MEM: 2MB

  redis:
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: 0.2
        reservations:
          memory: 32M
    command: redis-server --maxmemory 48mb --maxmemory-policy allkeys-lru --appendonly yes

  nginx:
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: 0.2
        reservations:
          memory: 32M

  prometheus:
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: 0.3
        reservations:
          memory: 128M
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=24h'
      - '--storage.tsdb.retention.size=200MB'
      - '--web.enable-lifecycle'

  grafana:
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: 0.3
        reservations:
          memory: 64M
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: false
      GF_INSTALL_PLUGINS: ""
      GF_ANALYTICS_REPORTING_ENABLED: false

  loki:
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: 0.3
        reservations:
          memory: 64M

  # Disable healthcheck to save memory
  healthcheck:
    deploy:
      replicas: 0
EOF

    print_success "Override file created"
}

# Test configuration
test_config() {
    print_status "Testing Docker Compose configuration..."
    
    cd docker/production
    
    if docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml config > /dev/null 2>&1; then
        print_success "Configuration is valid"
        return 0
    else
        print_error "Configuration validation failed:"
        docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml config
        return 1
    fi
}

# Deploy services
deploy_services() {
    print_status "Deploying services with memory optimization..."
    
    cd docker/production
    
    # Stop any existing containers
    print_status "Stopping existing containers..."
    docker compose -f docker-compose.infrastructure.yml down || true
    
    # Pull latest images
    print_status "Pulling latest images..."
    docker compose -f docker-compose.infrastructure.yml pull
    
    # Start core services first
    print_status "Starting core services (postgres, redis)..."
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d postgres redis
    
    # Wait for databases to be ready
    print_status "Waiting for databases to initialize..."
    sleep 15
    
    # Start nginx
    print_status "Starting web server (nginx)..."
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d nginx
    
    sleep 5
    
    # Start monitoring services (optional for low memory)
    read -p "Start monitoring services (Grafana, Prometheus, Loki)? Uses ~500MB RAM (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Starting monitoring services..."
        docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d prometheus grafana loki
    else
        print_warning "Monitoring services skipped to save memory"
    fi
    
    print_success "Deployment complete!"
}

# Check status
check_status() {
    print_status "Checking deployment status..."
    
    cd docker/production
    
    echo -e "\n=== Container Status ==="
    docker compose -f docker-compose.infrastructure.yml ps
    
    echo -e "\n=== Memory Usage ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" 2>/dev/null || echo "Docker stats not available"
    
    echo -e "\n=== System Resources ==="
    free -h
    
    echo -e "\n=== Service Access ==="
    print_status "Services should be accessible at:"
    echo "  - Nginx: http://85.193.95.44"
    echo "  - PostgreSQL: localhost:5432 (internal)"
    echo "  - Redis: localhost:6379 (internal)"
    
    if docker compose -f docker-compose.infrastructure.yml ps | grep -q grafana; then
        echo "  - Grafana: http://85.193.95.44:3001"
    fi
    
    if docker compose -f docker-compose.infrastructure.yml ps | grep -q prometheus; then
        echo "  - Prometheus: http://85.193.95.44:9090"
    fi
}

# Main execution
main() {
    print_status "Starting Station 2290 VPS deployment..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker service:"
        echo "  sudo systemctl start docker"
        exit 1
    fi
    
    check_environment
    create_override
    
    if test_config; then
        print_success "✅ Configuration validated successfully"
        
        read -p "Deploy infrastructure now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            deploy_services
            sleep 5
            check_status
            
            print_success "🎉 Station 2290 infrastructure deployed!"
            print_warning "💡 Remember to:"
            echo "  1. Update passwords in .env file"
            echo "  2. Configure proper SSL certificates"
            echo "  3. Set up monitoring alerts"
            
        else
            print_status "Deployment cancelled by user"
        fi
    else
        print_error "❌ Configuration validation failed"
        exit 1
    fi
}

# Run main function
main "$@"