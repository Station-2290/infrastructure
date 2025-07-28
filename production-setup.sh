#!/bin/bash

# Station 2290 Production Infrastructure Setup Script
# This script prepares the production environment for Docker deployment

set -e

echo "🚀 Station 2290 Production Infrastructure Setup"
echo "=============================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Consider using sudo for specific commands instead."
    fi
}

# Create production directory structure
create_directory_structure() {
    print_status "Creating production directory structure..."
    
    sudo mkdir -p /opt/station2290/{data,logs,ssl,monitoring,backups}
    sudo mkdir -p /opt/station2290/data/{postgres,redis}
    sudo mkdir -p /opt/station2290/logs/{nginx,certbot}
    sudo mkdir -p /opt/station2290/ssl/{certs,private}
    
    # Set proper ownership
    sudo chown -R $USER:$USER /opt/station2290
    sudo chmod -R 755 /opt/station2290
    
    print_success "Directory structure created successfully"
}

# Create Docker network
create_docker_network() {
    print_status "Creating Docker network..."
    
    if ! docker network ls | grep -q "station2290_network"; then
        docker network create station2290_network --driver bridge --subnet=172.20.0.0/16
        print_success "Docker network 'station2290_network' created"
    else
        print_warning "Docker network 'station2290_network' already exists"
    fi
}

# Setup environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    if [[ ! -f .env ]]; then
        if [[ -f .env.prod.template ]]; then
            cp .env.prod.template .env
            print_warning "Environment file created from template. Please update the following variables:"
            echo "  - POSTGRES_PASSWORD"
            echo "  - GRAFANA_ADMIN_PASSWORD"
            echo "  - JWT_SECRET"
            echo "  - OPENAI_API_KEY (if applicable)"
            echo ""
            echo "Edit .env file with: nano .env"
        else
            print_error ".env.prod.template not found. Creating basic .env file..."
            cat > .env << 'EOF'
# Database Configuration
POSTGRES_DB=station2290
POSTGRES_USER=station2290_user
POSTGRES_PASSWORD=your_secure_password_here

# Grafana Configuration
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=your_admin_password_here

# Application Configuration
NODE_ENV=production
JWT_SECRET=your_jwt_secret_here

# Optional: OpenAI API Key
OPENAI_API_KEY=your_openai_key_here
EOF
            print_warning "Basic .env file created. Please update all password fields!"
        fi
    else
        print_success "Environment file already exists"
    fi
}

# Clean Docker resources
clean_docker_resources() {
    print_status "Cleaning Docker resources to free up space..."
    
    # Remove unused images, containers, networks, and volumes
    docker system prune -a --volumes -f
    
    print_success "Docker resources cleaned"
}

# Check system resources
check_system_resources() {
    print_status "Checking system resources..."
    
    # Check available memory
    AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%.1f", $7/1024}')
    REQUIRED_MEM=6.5
    
    if (( $(echo "$AVAILABLE_MEM < $REQUIRED_MEM" | bc -l) )); then
        print_warning "Available memory: ${AVAILABLE_MEM}GB. Required: ${REQUIRED_MEM}GB"
        print_warning "Consider stopping other services or adding more RAM"
    else
        print_success "Memory check passed: ${AVAILABLE_MEM}GB available"
    fi
    
    # Check disk space
    AVAILABLE_DISK=$(df -BG /opt 2>/dev/null | awk 'NR==2{print $4}' | sed 's/G//' || echo "10")
    REQUIRED_DISK=20
    
    if [[ $AVAILABLE_DISK -lt $REQUIRED_DISK ]]; then
        print_warning "Available disk space: ${AVAILABLE_DISK}GB. Required: ${REQUIRED_DISK}GB"
    else
        print_success "Disk space check passed: ${AVAILABLE_DISK}GB available"
    fi
}

# Generate SSL certificate placeholder
setup_ssl_placeholder() {
    print_status "Setting up SSL certificate placeholder..."
    
    # Create self-signed certificate for initial testing
    if [[ ! -f /opt/station2290/ssl/certs/station2290.crt ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /opt/station2290/ssl/private/station2290.key \
            -out /opt/station2290/ssl/certs/station2290.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
        
        chmod 600 /opt/station2290/ssl/private/station2290.key
        chmod 644 /opt/station2290/ssl/certs/station2290.crt
        
        print_success "Self-signed SSL certificate created for testing"
        print_warning "Replace with proper SSL certificates for production use"
    else
        print_success "SSL certificates already exist"
    fi
}

# Validate configuration files
validate_configurations() {
    print_status "Validating configuration files..."
    
    # Check Docker Compose file
    if docker-compose -f infrastructure/docker/production/docker-compose.infrastructure.yml config > /dev/null 2>&1; then
        print_success "Docker Compose configuration is valid"
    else
        print_error "Docker Compose configuration has errors"
        return 1
    fi
    
    # Check Nginx configuration
    if [[ -f infrastructure/nginx/nginx.conf ]]; then
        print_success "Nginx configuration found"
    else
        print_error "Nginx configuration not found"
        return 1
    fi
    
    # Check monitoring configurations
    if [[ -f infrastructure/monitoring/prometheus/prometheus.yml ]]; then
        print_success "Prometheus configuration found"
    else
        print_warning "Prometheus configuration not found"
    fi
    
    if [[ -f infrastructure/monitoring/loki/loki-config.yaml ]]; then
        print_success "Loki configuration found"
    else
        print_warning "Loki configuration not found"
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure stack..."
    
    cd infrastructure/docker/production
    
    # Pull latest images
    docker-compose -f docker-compose.infrastructure.yml pull
    
    # Start services
    docker-compose -f docker-compose.infrastructure.yml up -d
    
    print_success "Infrastructure deployment initiated"
    
    # Wait for services to start
    print_status "Waiting for services to start..."
    sleep 30
    
    # Check service status
    docker-compose -f docker-compose.infrastructure.yml ps
}

# Health check
run_health_check() {
    print_status "Running health checks..."
    
    cd ../../../tests
    if [[ -f validate-all-services.sh ]]; then
        ./validate-all-services.sh
    else
        print_warning "Health check script not found"
        
        # Basic manual health check
        print_status "Performing basic health checks..."
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    fi
}

# Main execution
main() {
    print_status "Starting Station 2290 production setup..."
    
    check_permissions
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    create_directory_structure
    create_docker_network
    setup_environment
    clean_docker_resources
    check_system_resources
    setup_ssl_placeholder
    validate_configurations
    
    print_status "Pre-deployment setup complete!"
    print_warning "Before deploying, please:"
    echo "  1. Update passwords in .env file"
    echo "  2. Configure proper SSL certificates"
    echo "  3. Review and adjust resource limits if needed"
    echo ""
    
    read -p "Do you want to deploy the infrastructure now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_infrastructure
        run_health_check
        
        print_success "🎉 Station 2290 infrastructure deployment complete!"
        print_status "Access services at:"
        echo "  - Nginx: http://localhost (80) / https://localhost (443)"
        echo "  - Grafana: http://localhost:3001"
        echo "  - Prometheus: http://localhost:9090"
        echo "  - Loki: http://localhost:3100"
    else
        print_status "Deployment skipped. Run this script again when ready."
        print_status "To deploy manually, run:"
        echo "  cd infrastructure/docker/production"
        echo "  docker-compose -f docker-compose.infrastructure.yml up -d"
    fi
}

# Run main function
main "$@"