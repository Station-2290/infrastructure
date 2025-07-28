#!/bin/bash

# VPS Fix Script for Station 2290
# Addresses the issues found on the production VPS

set -e

echo "🔧 Station 2290 VPS Fix Script"
echo "==============================="

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

# 1. Fix Docker network (was deleted during cleanup)
fix_docker_network() {
    print_status "Recreating Docker network..."
    
    if ! docker network ls | grep -q "station2290_network"; then
        docker network create station2290_network --driver bridge --subnet=172.20.0.0/16
        print_success "Docker network recreated"
    else
        print_success "Docker network already exists"
    fi
}

# 2. Create optimized .env for low-memory VPS
create_optimized_env() {
    print_status "Creating optimized environment file for VPS..."
    
    cat > .env << 'EOF'
# Station 2290 VPS Optimized Configuration
# Reduced memory footprint for 1.2GB VPS

# Database Configuration
POSTGRES_DB=station2290
POSTGRES_USER=station2290_user
POSTGRES_PASSWORD=SecureP@ssw0rd2024!

# Redis Configuration  
REDIS_URL=redis://redis:6379

# Application Configuration
NODE_ENV=production
JWT_SECRET=your_jwt_secret_minimum_32_characters_long_secure_key_2024
API_URL=http://85.193.95.44/api
WEB_URL=http://85.193.95.44

# Monitoring Configuration (Reduced)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=Gr@fana2024!

# SSL/TLS Configuration
SSL_CERT_PATH=/opt/station2290/ssl/certs
SSL_KEY_PATH=/opt/station2290/ssl/private
DOMAIN_NAME=85.193.95.44

# Performance Tuning for Low Memory
MAX_CONNECTIONS=20
WORKER_PROCESSES=1
KEEPALIVE_TIMEOUT=30

# Security Configuration
CORS_ORIGIN=http://85.193.95.44
RATE_LIMIT_WINDOW=15
RATE_LIMIT_MAX=50
SESSION_SECRET=your_session_secret_minimum_32_chars

# Logging Configuration
LOG_LEVEL=warn
LOG_PATH=/opt/station2290/logs

# Backup Configuration
BACKUP_SCHEDULE=0 3 * * *
BACKUP_RETENTION_DAYS=7
BACKUP_PATH=/opt/station2290/backups
EOF

    print_success "Optimized .env file created"
    print_warning "Default passwords set - change them for security!"
}

# 3. Create low-memory Docker Compose override
create_memory_optimized_compose() {
    print_status "Creating memory-optimized Docker Compose override..."
    
    mkdir -p docker/production
    
    cat > docker/production/docker-compose.override.yml << 'EOF'
version: '3.8'

# Memory-optimized overrides for low-memory VPS (1.2GB)
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
      - POSTGRES_SHARED_BUFFERS=32MB
      - POSTGRES_EFFECTIVE_CACHE_SIZE=128MB
      - POSTGRES_WORK_MEM=2MB

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
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=""
      - GF_ANALYTICS_REPORTING_ENABLED=false

  loki:
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: 0.3
        reservations:
          memory: 64M

  # Remove healthcheck service to save memory
  healthcheck:
    deploy:
      replicas: 0
EOF

    print_success "Memory-optimized override created"
}

# 4. Create minimal monitoring config for low memory
create_minimal_configs() {
    print_status "Creating minimal monitoring configurations..."
    
    # Minimal Prometheus config
    mkdir -p monitoring/prometheus
    cat > monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 60s
  evaluation_interval: 60s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 120s

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
    scrape_interval: 120s

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
    scrape_interval: 120s

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx:80']
    scrape_interval: 120s
EOF

    # Minimal Loki config
    mkdir -p monitoring/loki
    cat > monitoring/loki/loki-config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  max_transfer_retries: 0

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 24h
  ingestion_rate_mb: 4
  ingestion_burst_size_mb: 6
  max_entries_limit_per_query: 1000

chunk_store_config:
  max_look_back_period: 24h

table_manager:
  retention_deletes_enabled: true
  retention_period: 24h
EOF

    print_success "Minimal monitoring configs created"
}

# 5. Test Docker Compose configuration
test_docker_compose() {
    print_status "Testing Docker Compose configuration..."
    
    cd docker/production
    
    if docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml config > /dev/null 2>&1; then
        print_success "Docker Compose configuration is valid"
        return 0
    else
        print_error "Docker Compose configuration has errors:"
        docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml config
        return 1
    fi
}

# 6. Deploy with memory optimizations
deploy_optimized() {
    print_status "Deploying with memory optimizations..."
    
    cd docker/production
    
    # Stop any existing containers
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml down || true
    
    # Start core services first (database, cache)
    print_status "Starting core services..."
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d postgres redis
    
    sleep 10
    
    # Start web services
    print_status "Starting web services..."
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d nginx
    
    sleep 5
    
    # Start monitoring (optional, can be skipped on very low memory)
    print_status "Starting monitoring services..."
    docker compose -f docker-compose.infrastructure.yml -f docker-compose.override.yml up -d prometheus grafana loki
    
    print_success "Deployment complete"
}

# 7. Check deployment status
check_status() {
    print_status "Checking deployment status..."
    
    echo "=== Container Status ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo -e "\n=== Memory Usage ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"
    
    echo -e "\n=== System Resources ==="
    free -h
    df -h /
}

# Main execution
main() {
    print_status "Starting VPS fix process..."
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    fix_docker_network
    create_optimized_env
    create_memory_optimized_compose
    create_minimal_configs
    
    if test_docker_compose; then
        print_status "Configuration valid. Ready to deploy."
        
        read -p "Deploy optimized infrastructure now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            deploy_optimized
            sleep 10
            check_status
            
            print_success "🎉 VPS deployment complete!"
            print_warning "Memory-optimized for 1.2GB VPS"
            print_status "Access services at:"
            echo "  - Nginx: http://85.193.95.44"
            echo "  - Grafana: http://85.193.95.44:3001"
            echo "  - Prometheus: http://85.193.95.44:9090"
        fi
    else
        print_error "Configuration validation failed. Please check the errors above."
        exit 1
    fi
}

# Run main function
main "$@"