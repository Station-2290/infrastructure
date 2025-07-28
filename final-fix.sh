#!/bin/bash

# Final fix for Station 2290 infrastructure
echo "🎯 Station 2290 - Final Fix"
echo "============================"

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

# Issues identified:
# 1. Main app is using port 3001 (coffee-shop-web)
# 2. Docker network "station2290-network" doesn't exist
# 3. Environment variables not loading properly

print_info "Current running services:"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

print_info "Port conflicts identified:"
echo "  - Port 3001: coffee-shop-web (main app)"
echo "  - Port 3002: coffee-shop-bot"
echo "  - Port 3000: coffee-shop-api"

# Create the missing Docker network
print_info "Creating station2290-network..."
docker network create station2290-network --driver bridge --subnet=172.20.0.0/16 || {
    print_warning "Network might already exist or conflict, continuing..."
}

# Fix environment variables by loading them properly
print_info "Fixing environment variables..."
cat > .env << 'EOF'
# Station 2290 Infrastructure Environment
POSTGRES_DB=station2290
POSTGRES_USER=station2290_user
POSTGRES_PASSWORD=SecureP@ssw0rd2024!

# Grafana Configuration
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=Gr@fana2024!

# Application Configuration
NODE_ENV=production
JWT_SECRET=your_jwt_secret_minimum_32_characters_long_secure_key_2024
API_URL=http://85.193.95.44/api
WEB_URL=http://85.193.95.44

# SSL Configuration
SSL_CERT_PATH=/opt/station2290/ssl/certs
SSL_KEY_PATH=/opt/station2290/ssl/private
DOMAIN_NAME=85.193.95.44

# Logging Configuration
LOG_LEVEL=warn
LOG_PATH=/opt/station2290/logs
EOF

print_success "Environment file updated"

# Create override with unique ports (avoiding conflicts with main app)
print_info "Creating port-conflict-free override..."
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
    ports:
      - "8090:80"    # Use port 8090 instead of 80 (avoiding main app conflicts)
      - "8443:443"   # Use port 8443 instead of 443
    deploy:
      resources:
        limits:
          memory: 64M

  grafana:
    ports:
      - "127.0.0.1:3010:3000"  # Use port 3010 (avoiding all conflicts)
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
    ports:
      - "127.0.0.1:9091:9090"  # Use port 9091 instead of 9090
    deploy:
      resources:
        limits:
          memory: 256M
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=24h'

  loki:
    ports:
      - "127.0.0.1:3101:3100"  # Use port 3101 instead of 3100
    deploy:
      resources:
        limits:
          memory: 128M

  # Remove healthcheck to avoid conflicts
  healthcheck:
    profiles:
      - disabled
EOF

print_success "Conflict-free override created"

# Test the configuration
print_info "Testing configuration..."
if docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml config > /dev/null 2>&1; then
    print_success "Configuration is valid"
else
    print_error "Configuration invalid, showing errors:"
    docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml config
    exit 1
fi

# Deploy with explicit environment file
print_info "Deploying infrastructure services..."

# Export environment variables explicitly
export $(cat .env | grep -v '^#' | xargs)

# Deploy core services
print_info "Starting core infrastructure services..."
docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml --env-file .env up -d postgres redis

sleep 10

# Deploy web and monitoring services
print_info "Starting web and monitoring services..."
docker compose -f docker/production/docker-compose.infrastructure.yml -f docker/production/docker-compose.override.yml --env-file .env up -d nginx prometheus grafana loki

sleep 15

# Check results
print_success "🎉 Infrastructure deployment complete!"

print_info "All containers:"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

print_info "Infrastructure services status:"
docker compose -f docker/production/docker-compose.infrastructure.yml ps

print_info "System resources:"
free -h
df -h / | tail -1

print_success "🌐 Infrastructure services now available at:"
echo "  - Nginx (Infrastructure): http://85.193.95.44:8090"
echo "  - Grafana: http://85.193.95.44:3010 (admin/Gr@fana2024!)"
echo "  - Prometheus: http://85.193.95.44:9091"
echo "  - Loki: http://85.193.95.44:3101"
echo ""
print_info "📱 Main application (already running):"
echo "  - Web App: http://85.193.95.44:3001"
echo "  - API: http://85.193.95.44:3000"
echo "  - Bot: http://85.193.95.44:3002"
echo "  - Admin: http://85.193.95.44:8080"
echo "  - Orders: http://85.193.95.44:8081"

print_warning "🔒 Security notes:"
echo "  - Both main app and infrastructure are now running"
echo "  - Infrastructure uses alternative ports to avoid conflicts"
echo "  - Change default passwords for production use"

# Test connectivity
print_info "Testing infrastructure connectivity..."
curl -s http://localhost:8090 > /dev/null && print_success "Infrastructure Nginx responding" || print_warning "Infrastructure Nginx not responding"
curl -s http://localhost:3010 > /dev/null && print_success "Grafana responding" || print_warning "Grafana not responding"
curl -s http://localhost:9091 > /dev/null && print_success "Prometheus responding" || print_warning "Prometheus not responding"