#!/bin/bash

# Fix port conflicts and deploy
echo "🔧 Station 2290 - Fix & Deploy"
echo "==============================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check what's using port 3001
print_info "Checking what's using port 3001..."
netstat -tulpn | grep 3001 || echo "Nothing found on port 3001"
lsof -i :3001 || echo "lsof: Nothing on port 3001"

# Check for any station2290 containers
print_info "Checking for existing station2290 containers..."
docker ps -a | grep station2290 || echo "No station2290 containers found"

# Stop all station2290 containers
print_info "Stopping all station2290 containers..."
docker ps -a --format "{{.Names}}" | grep station2290 | xargs -r docker rm -f

# Clean up Docker networks
print_info "Cleaning up Docker networks..."
docker network prune -f

# Fix environment variables in .env
print_info "Updating environment variables..."
if [[ -f .env ]]; then
    # Make sure passwords are set
    if ! grep -q "POSTGRES_PASSWORD=.*[^[:space:]]" .env; then
        echo "POSTGRES_PASSWORD=SecureP@ssw0rd2024!" >> .env
    fi
    if ! grep -q "GRAFANA_ADMIN_PASSWORD=.*[^[:space:]]" .env; then
        echo "GRAFANA_ADMIN_PASSWORD=Gr@fana2024!" >> .env
    fi
    print_success "Environment variables updated"
else
    print_warning "No .env file found, creating one..."
    cat > .env << 'EOF'
POSTGRES_DB=station2290
POSTGRES_USER=station2290_user
POSTGRES_PASSWORD=SecureP@ssw0rd2024!
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=Gr@fana2024!
NODE_ENV=production
JWT_SECRET=your_jwt_secret_minimum_32_characters_long_secure_key_2024
EOF
    print_success "Environment file created"
fi

# Create updated override with alternative port for Grafana
print_info "Creating updated Docker override..."
cat > docker/production/docker-compose.override.yml << 'EOF'
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
    ports:
      - "127.0.0.1:3002:3000"  # Use port 3002 instead of 3001
    deploy:
      resources:
        limits:
          memory: 128M
    environment:
      GF_SECURITY_ADMIN_USER: ${GRAFANA_ADMIN_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: false
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

print_success "Updated override created (Grafana on port 3002)"

# Test configuration
print_info "Testing Docker Compose configuration..."
if docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml config > /dev/null 2>&1; then
    print_success "Configuration is valid"
else
    print_error "Configuration is invalid"
    docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml config
    exit 1
fi

# Deploy with fixed configuration
print_info "Deploying with fixed configuration..."

# Start core services
print_info "Starting core services..."
docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml up -d postgres redis nginx

sleep 15

# Start monitoring services
print_info "Starting monitoring services..."
docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml up -d prometheus loki grafana

sleep 10

# Check status
print_success "🎉 Deployment complete!"

print_info "Container status:"
docker compose -f docker/production/docker-compose.infrastructure.yml ps

print_info "System resources:"
free -h
echo "Disk usage:"
df -h /

print_info "Memory usage by containers:"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" 2>/dev/null || echo "Docker stats not available"

print_success "🌐 Services available at:"
echo "  - Nginx: http://85.193.95.44"
echo "  - Grafana: http://85.193.95.44:3002 (admin/Gr@fana2024!)"
echo "  - Prometheus: http://85.193.95.44:9090"
echo "  - Loki: http://85.193.95.44:3100"

print_warning "🔒 Security reminders:"
echo "  - Change default passwords in .env file"
echo "  - Set up proper SSL certificates"
echo "  - Configure firewall rules"

# Test basic connectivity
print_info "Testing basic connectivity..."
curl -s http://localhost > /dev/null && print_success "Nginx responding" || print_warning "Nginx not responding"
curl -s http://localhost:3002 > /dev/null && print_success "Grafana responding" || print_warning "Grafana not responding"
curl -s http://localhost:9090 > /dev/null && print_success "Prometheus responding" || print_warning "Prometheus not responding"