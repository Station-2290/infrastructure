#!/bin/bash

# Station2290 Production Deployment Script
# Comprehensive deployment with health checks, rollback capabilities, and monitoring

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_COMPOSE_FILE="$INFRASTRUCTURE_ROOT/docker/production/docker-compose.yml"
ENV_FILE="$INFRASTRUCTURE_ROOT/configs/environment/.env.prod"
BACKUP_DIR="/opt/station2290/backups/$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/opt/station2290/logs/deployment-$(date +%Y%m%d-%H%M%S).log"
LOCK_FILE="/var/lock/station2290-deploy.lock"

# Deployment configuration
DEPLOYMENT_TIMEOUT=1800  # 30 minutes
HEALTH_CHECK_RETRIES=30
HEALTH_CHECK_INTERVAL=10
ROLLBACK_ON_FAILURE=true
PARALLEL_BUILD=true
SKIP_BACKUP=false

# Service configuration
SERVICES=(
    "postgres:database:5432"
    "redis:cache:6379"
    "api:application:3000"
    "bot:application:3001"
    "web:application:3000"
    "adminka:frontend:80"
    "order-panel:frontend:80"
    "nginx:proxy:80,443"
)

# Monitoring endpoints
HEALTH_ENDPOINTS=(
    "http://localhost:3000/health:API"
    "http://localhost:3001/health:Bot"
    "http://localhost:3000/api/health:Web"
    "http://localhost:8080/nginx_status:Nginx"
)

# External health checks (after SSL setup)
EXTERNAL_ENDPOINTS=(
    "https://station2290.ru/health:Main Site"
    "https://api.station2290.ru/health:API"
    "https://adminka.station2290.ru:Admin Panel"
    "https://orders.station2290.ru:Order Panel"
    "https://bot.station2290.ru/health:Bot"
)

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[${timestamp}] [WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" | tee -a "$LOG_FILE" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${PURPLE}[${timestamp}] [DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
        *) echo -e "${CYAN}[${timestamp}] [$level]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local task="$3"
    local percent=$((current * 100 / total))
    local progress_bar=""
    
    for ((i=0; i<50; i++)); do
        if [[ $i -lt $((percent / 2)) ]]; then
            progress_bar+="█"
        else
            progress_bar+="░"
        fi
    done
    
    echo -ne "\r${CYAN}[$progress_bar] ${percent}% - $task${NC}"
}

# Acquire deployment lock
acquire_lock() {
    log "INFO" "Acquiring deployment lock..."
    
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR" "Another deployment is already running (PID: $lock_pid)"
            exit 1
        else
            log "WARN" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    log "SUCCESS" "Deployment lock acquired"
}

# Release deployment lock
release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "INFO" "Deployment lock released"
    fi
}

# Cleanup function for trap
cleanup() {
    local exit_code=$?
    log "INFO" "Cleaning up deployment..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    release_lock
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code $exit_code"
        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            log "WARN" "Initiating automatic rollback..."
            rollback_deployment
        fi
    fi
    
    exit $exit_code
}

# Setup logging and trap
setup_logging() {
    local log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir"
    touch "$LOG_FILE"
    
    # Set up trap for cleanup
    trap cleanup EXIT INT TERM
    
    log "INFO" "Deployment started - logging to $LOG_FILE"
    log "INFO" "Deployment PID: $$"
}

# System requirements check
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check available disk space (minimum 10GB)
    local available_space=$(df /opt/station2290 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local required_space=$((10 * 1024 * 1024))  # 10GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log "ERROR" "Insufficient disk space. Available: ${available_space}KB, Required: ${required_space}KB"
        exit 1
    fi
    
    # Check available memory (minimum 4GB)
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    if [[ $available_memory -lt 2048 ]]; then
        log "WARN" "Low memory available: ${available_memory}MB. Recommended: 4GB+"
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log "ERROR" "Docker Compose is not installed"
        exit 1
    fi
    
    # Check ports availability
    local ports_to_check=(80 443 5432 6379)
    for port in "${ports_to_check[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log "WARN" "Port $port is already in use"
        fi
    done
    
    log "SUCCESS" "System requirements check passed"
}

# Pre-deployment validation
pre_deployment_checks() {
    log "INFO" "Running pre-deployment checks..."
    
    # Check if environment file exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log "ERROR" "Environment file not found: $ENV_FILE"
        log "INFO" "Please create it from the template and configure all values"
        exit 1
    fi
    
    # Load environment variables
    source "$ENV_FILE"
    
    # Validate critical environment variables
    local required_vars=(
        "POSTGRES_PASSWORD"
        "JWT_SECRET"
        "JWT_REFRESH_SECRET"
        "WHATSAPP_ACCESS_TOKEN"
        "WHATSAPP_WEBHOOK_VERIFY_TOKEN"
        "SSL_EMAIL"
        "GRAFANA_ADMIN_PASSWORD"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]] || [[ "${!var}" == *"change-this"* ]] || [[ "${!var}" == *"your-"* ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing or invalid environment variables:"
        for var in "${missing_vars[@]}"; do
            log "ERROR" "  - $var"
        done
        exit 1
    fi
    
    # Validate Docker Compose file
    if ! docker-compose -f "$DOCKER_COMPOSE_FILE" config > /dev/null; then
        log "ERROR" "Docker Compose file validation failed"
        exit 1
    fi
    
    # Check if required directories exist
    local required_dirs=(
        "/opt/station2290"
        "/opt/station2290/data"
        "/opt/station2290/logs"
        "/opt/station2290/ssl"
        "/opt/station2290/backups"
        "/opt/station2290/monitoring"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "INFO" "Creating directory: $dir"
            mkdir -p "$dir"
            chown -R $(whoami):docker "$dir" 2>/dev/null || true
        fi
    done
    
    log "SUCCESS" "Pre-deployment checks passed"
}

# Create backup of current deployment
create_backup() {
    if [[ "$SKIP_BACKUP" == "true" ]]; then
        log "INFO" "Skipping backup creation (SKIP_BACKUP=true)"
        return 0
    fi
    
    log "INFO" "Creating backup of current deployment..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup environment file
    if [[ -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "$BACKUP_DIR/"
        log "DEBUG" "Environment file backed up"
    fi
    
    # Backup configuration files
    if [[ -d "$INFRASTRUCTURE_ROOT/configs" ]]; then
        cp -r "$INFRASTRUCTURE_ROOT/configs" "$BACKUP_DIR/"
        log "DEBUG" "Configuration files backed up"
    fi
    
    # Backup database if running
    if docker-compose -f "$DOCKER_COMPOSE_FILE" ps postgres | grep -q "Up"; then
        log "INFO" "Creating database backup..."
        local db_backup_file="$BACKUP_DIR/database-$(date +%Y%m%d-%H%M%S).sql"
        
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres \
            pg_dump -U "${POSTGRES_USER:-station2290_user}" "${POSTGRES_DB:-station2290}" \
            > "$db_backup_file" 2>/dev/null || {
            log "WARN" "Database backup failed, but continuing deployment"
        }
        
        if [[ -f "$db_backup_file" ]] && [[ -s "$db_backup_file" ]]; then
            log "SUCCESS" "Database backup created: $db_backup_file"
        fi
    fi
    
    # Backup Docker images
    log "INFO" "Backing up current Docker images..."
    local images_backup_dir="$BACKUP_DIR/images"
    mkdir -p "$images_backup_dir"
    
    docker-compose -f "$DOCKER_COMPOSE_FILE" config --services | while read service; do
        local image=$(docker-compose -f "$DOCKER_COMPOSE_FILE" images -q "$service" 2>/dev/null | head -1)
        if [[ -n "$image" ]]; then
            log "DEBUG" "Backing up image for service: $service"
            docker save "$image" | gzip > "$images_backup_dir/${service}-image.tar.gz" &
        fi
    done
    
    # Wait for image backups to complete
    wait
    
    # Create backup metadata
    cat > "$BACKUP_DIR/metadata.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "deployment_version": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
    "environment": "production",
    "services": $(docker-compose -f "$DOCKER_COMPOSE_FILE" config --services | jq -R . | jq -s .),
    "backup_size": "$(du -sh "$BACKUP_DIR" | cut -f1)"
}
EOF
    
    log "SUCCESS" "Backup created: $BACKUP_DIR"
}

# Build services with parallel execution
build_services() {
    log "INFO" "Building all services..."
    
    local build_start=$(date +%s)
    
    # Pull base images first
    log "INFO" "Pulling base images..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" pull postgres redis nginx certbot prometheus grafana loki
    
    # Build custom services
    if [[ "$PARALLEL_BUILD" == "true" ]]; then
        log "INFO" "Building services in parallel..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" build --parallel --no-cache
    else
        log "INFO" "Building services sequentially..."
        docker-compose -f "$DOCKER_COMPOSE_FILE" build --no-cache
    fi
    
    local build_end=$(date +%s)
    local build_duration=$((build_end - build_start))
    
    log "SUCCESS" "All services built successfully in ${build_duration}s"
}

# Health check function with retry logic
check_service_health() {
    local service="$1"
    local url="$2"
    local retries="${3:-$HEALTH_CHECK_RETRIES}"
    local interval="${4:-$HEALTH_CHECK_INTERVAL}"
    
    log "INFO" "Checking health of $service..."
    
    for ((attempt=1; attempt<=retries; attempt++)); do
        show_progress "$attempt" "$retries" "Health check: $service"
        
        if curl -sSf --max-time 10 "$url" > /dev/null 2>&1; then
            echo  # New line after progress bar
            log "SUCCESS" "$service is healthy (attempt $attempt/$retries)"
            return 0
        fi
        
        if [[ $attempt -lt $retries ]]; then
            sleep "$interval"
        fi
    done
    
    echo  # New line after progress bar
    log "ERROR" "$service failed health check after $retries attempts"
    return 1
}

# Deploy services with rolling update strategy
deploy_services() {
    log "INFO" "Starting rolling deployment..."
    
    local deployment_start=$(date +%s)
    
    # Phase 1: Infrastructure services
    log "INFO" "Phase 1: Deploying infrastructure services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres redis
    
    # Wait for database to be ready
    log "INFO" "Waiting for database to be ready..."
    sleep 30
    
    if ! check_service_health "PostgreSQL" "localhost:5432" 10 5; then
        # Use pg_isready as fallback
        for ((i=1; i<=10; i++)); do
            if docker-compose -f "$DOCKER_COMPOSE_FILE" exec postgres pg_isready -U "${POSTGRES_USER:-station2290_user}" -d "${POSTGRES_DB:-station2290}" &>/dev/null; then
                log "SUCCESS" "PostgreSQL is ready"
                break
            fi
            sleep 5
        done
    fi
    
    # Check Redis
    if ! check_service_health "Redis" "localhost:6379" 10 3; then
        log "WARN" "Redis health check failed, but continuing..."
    fi
    
    # Phase 2: Application services
    log "INFO" "Phase 2: Deploying application services..."
    
    # Deploy API first (core service)
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d api
    if ! check_service_health "API" "http://localhost:3000/health" 20 10; then
        log "ERROR" "API service failed to start"
        return 1
    fi
    
    # Deploy Bot service
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d bot
    if ! check_service_health "Bot" "http://localhost:3001/health" 15 10; then
        log "WARN" "Bot service health check failed, but continuing..."
    fi
    
    # Deploy frontend services
    log "INFO" "Deploying frontend services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d web adminka order-panel
    
    # Phase 3: Proxy and monitoring
    log "INFO" "Phase 3: Deploying proxy and monitoring..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d nginx certbot
    
    # Deploy monitoring stack
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d prometheus grafana loki
    
    # Deploy backup and health check services
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d backup healthcheck
    
    local deployment_end=$(date +%s)
    local deployment_duration=$((deployment_end - deployment_start))
    
    log "SUCCESS" "Rolling deployment completed in ${deployment_duration}s"
}

# Comprehensive health checks
comprehensive_health_checks() {
    log "INFO" "Running comprehensive health checks..."
    
    local all_healthy=true
    local failed_services=()
    
    # Check internal health endpoints
    for endpoint_info in "${HEALTH_ENDPOINTS[@]}"; do
        IFS=':' read -r url service <<< "$endpoint_info"
        if ! check_service_health "$service" "$url" 5 5; then
            all_healthy=false
            failed_services+=("$service")
        fi
    done
    
    # Check container status
    log "INFO" "Checking container status..."
    local services=(postgres redis api bot web adminka order-panel nginx)
    
    for service in "${services[@]}"; do
        local status=$(docker-compose -f "$DOCKER_COMPOSE_FILE" ps -q "$service" | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
        
        if [[ "$status" == "running" ]]; then
            log "SUCCESS" "Container $service is running"
        else
            log "ERROR" "Container $service is not running (status: $status)"
            all_healthy=false
            failed_services+=("$service")
        fi
    done
    
    # Check external endpoints (if SSL is configured)
    if [[ -f "/opt/station2290/ssl/certs/live/station2290.ru/fullchain.pem" ]]; then
        log "INFO" "Testing external HTTPS connectivity..."
        
        for endpoint_info in "${EXTERNAL_ENDPOINTS[@]}"; do
            IFS=':' read -r url service <<< "$endpoint_info"
            if curl -sSf --max-time 10 "$url" > /dev/null 2>&1; then
                log "SUCCESS" "External connectivity test passed for $service"
            else
                log "WARN" "External connectivity test failed for $service"
            fi
        done
    fi
    
    # Check resource usage
    log "INFO" "Checking resource usage..."
    local memory_usage=$(free | awk 'NR==2{printf "%.2f%%", $3*100/$2}')
    local disk_usage=$(df /opt/station2290 | awk 'NR==2{print $5}')
    local load_average=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    log "INFO" "System resources - Memory: $memory_usage, Disk: $disk_usage, Load: $load_average"
    
    if [[ $all_healthy == true ]]; then
        log "SUCCESS" "All health checks passed"
        return 0
    else
        log "ERROR" "Health checks failed for services: ${failed_services[*]}"
        return 1
    fi
}

# Rollback function
rollback_deployment() {
    log "WARN" "Initiating deployment rollback..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "ERROR" "No backup found for rollback"
        return 1
    fi
    
    # Stop current services
    log "INFO" "Stopping current services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans
    
    # Restore environment file
    if [[ -f "$BACKUP_DIR/.env.prod" ]]; then
        cp "$BACKUP_DIR/.env.prod" "$ENV_FILE"
        log "INFO" "Environment file restored"
    fi
    
    # Restore configuration files
    if [[ -d "$BACKUP_DIR/configs" ]]; then
        cp -r "$BACKUP_DIR/configs/"* "$INFRASTRUCTURE_ROOT/configs/"
        log "INFO" "Configuration files restored"
    fi
    
    # Restore database if backup exists
    if [[ -f "$BACKUP_DIR/database-"*.sql ]]; then
        log "INFO" "Restoring database..."
        local db_backup=$(ls "$BACKUP_DIR"/database-*.sql | head -1)
        
        # Start only postgres for restore
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres
        sleep 15
        
        # Restore database
        docker-compose -f "$DOCKER_COMPOSE_FILE" exec -T postgres \
            psql -U "${POSTGRES_USER:-station2290_user}" -d "${POSTGRES_DB:-station2290}" \
            < "$db_backup" || log "WARN" "Database restore failed"
    fi
    
    # Restore Docker images
    if [[ -d "$BACKUP_DIR/images" ]]; then
        log "INFO" "Restoring Docker images..."
        for image_file in "$BACKUP_DIR/images"/*.tar.gz; do
            if [[ -f "$image_file" ]]; then
                gunzip -c "$image_file" | docker load
            fi
        done
    fi
    
    # Start services with old images
    log "INFO" "Starting services with restored configuration..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    
    # Wait for services to start
    sleep 60
    
    # Verify rollback
    if comprehensive_health_checks; then
        log "SUCCESS" "Rollback completed successfully"
    else
        log "ERROR" "Rollback failed - manual intervention required"
        return 1
    fi
}

# Post-deployment tasks
post_deployment_tasks() {
    log "INFO" "Running post-deployment tasks..."
    
    # Run database migrations
    log "INFO" "Running database migrations..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" exec api npm run db:migrate:prod || {
        log "WARN" "Database migrations failed or not applicable"
    }
    
    # Warm up services
    log "INFO" "Warming up services..."
    local warmup_urls=(
        "http://localhost:3000/health"
        "http://localhost:3001/health"
        "http://localhost:8080/nginx_status"
    )
    
    for url in "${warmup_urls[@]}"; do
        curl -sSf "$url" > /dev/null 2>&1 || true
    done
    
    # Setup log rotation
    log "INFO" "Setting up log rotation..."
    cat > /etc/logrotate.d/station2290 << 'EOF'
/opt/station2290/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su root root
}
EOF
    
    # Setup system monitoring cron jobs
    log "INFO" "Setting up monitoring cron jobs..."
    cat > /tmp/station2290-cron << EOF
# Station2290 monitoring and maintenance
0 2 * * * $SCRIPT_DIR/backup-system.sh
0 3 * * 0 $SCRIPT_DIR/cleanup-logs.sh
*/5 * * * * $SCRIPT_DIR/../health-checks/check-all-services.sh
0 4 * * * docker system prune -f
EOF
    
    crontab /tmp/station2290-cron
    rm /tmp/station2290-cron
    
    # Clean up old Docker resources
    log "INFO" "Cleaning up old Docker resources..."
    docker image prune -f
    docker volume prune -f
    docker network prune -f
    
    # Set up firewall rules (if ufw is available)
    if command -v ufw &> /dev/null; then
        log "INFO" "Configuring firewall rules..."
        ufw --force enable
        ufw allow 22/tcp    # SSH
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        ufw reload
    fi
    
    log "SUCCESS" "Post-deployment tasks completed"
}

# Generate deployment report
generate_deployment_report() {
    local status="$1"
    local report_file="/opt/station2290/logs/deployment-report-$(date +%Y%m%d-%H%M%S).json"
    
    log "INFO" "Generating deployment report..."
    
    local deployment_end=$(date +%s)
    local total_duration=$((deployment_end - DEPLOYMENT_START))
    
    # Collect system information
    local system_info=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "$status",
    "duration": $total_duration,
    "backup_location": "$BACKUP_DIR",
    "deployment": {
        "version": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
        "environment": "production",
        "user": "$(whoami)",
        "hostname": "$(hostname)"
    },
    "services": $(docker-compose -f "$DOCKER_COMPOSE_FILE" ps --format json 2>/dev/null | jq -s . || echo '[]'),
    "images": $(docker-compose -f "$DOCKER_COMPOSE_FILE" images --format json 2>/dev/null | jq -s . || echo '[]'),
    "system": {
        "memory_usage": "$(free | awk 'NR==2{printf "%.2f%%", $3*100/$2}')",
        "disk_usage": "$(df /opt/station2290 | awk 'NR==2{print $5}')",
        "load_average": "$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')",
        "docker_info": $(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | tail -n +2 | jq -R -s 'split("\n")[:-1] | map(split("\t")) | map({"type": .[0], "count": .[1], "size": .[2]})' || echo '[]')
    }
}
EOF
)
    
    echo "$system_info" > "$report_file"
    
    if [[ "$status" == "SUCCESS" ]]; then
        log "SUCCESS" "Deployment completed successfully!"
        cat << EOF

🎉 Station2290 Production Deployment Complete!

Services Available:
• Main Website: https://station2290.ru
• API Service: https://api.station2290.ru/health
• Admin Panel: https://adminka.station2290.ru
• Order Panel: https://orders.station2290.ru
• Bot Service: https://bot.station2290.ru/health
• Monitoring: https://monitoring.station2290.ru (admin:${GRAFANA_ADMIN_PASSWORD})

Duration: ${total_duration}s
Report: $report_file
Backup: $BACKUP_DIR

Next Steps:
1. Monitor logs: docker-compose -f $DOCKER_COMPOSE_FILE logs -f
2. Check health endpoints
3. Verify SSL certificates
4. Test all functionality

EOF
    else
        log "ERROR" "Deployment failed!"
        cat << EOF

❌ Station2290 Deployment Failed

Status: $status
Duration: ${total_duration}s
Report: $report_file
Backup: $BACKUP_DIR

Troubleshooting:
1. Check logs: docker-compose -f $DOCKER_COMPOSE_FILE logs
2. Verify environment configuration
3. Check system resources
4. Review health checks

EOF
    fi
    
    log "INFO" "Deployment report saved: $report_file"
}

# Main deployment flow
main() {
    local DEPLOYMENT_START=$(date +%s)
    
    echo -e "${BLUE}"
    cat << "EOF"
   _____ _        _   _             ___   ___   ___   ___  
  / ____| |      | | (_)           |__ \ |__ \ / _ \ / _ \ 
 | (___ | |_ __ _| |_ _  ___  _ __     ) |   ) | (_) | | | |
  \___ \| __/ _` | __| |/ _ \| '_ \   / /   / / \__, | | | |
  ____) | || (_| | |_| | (_) | | | | / /_  / /_   / /| |_| |
 |_____/ \__\__,_|\__|_|\___/|_| |_||____||____|/_/  \___/ 
                                                          
Production Deployment Script v2.0
EOF
    echo -e "${NC}"
    
    log "INFO" "Starting Station2290 production deployment..."
    
    # Setup
    setup_logging
    acquire_lock
    
    # Pre-deployment
    check_system_requirements
    pre_deployment_checks
    
    # Deployment phases
    create_backup
    build_services
    deploy_services
    
    # Wait for services to stabilize
    log "INFO" "Waiting for services to stabilize..."
    sleep 60
    
    # Validation
    if comprehensive_health_checks; then
        post_deployment_tasks
        generate_deployment_report "SUCCESS"
        exit 0
    else
        log "ERROR" "Health checks failed"
        generate_deployment_report "FAILED"
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --no-rollback)
            ROLLBACK_ON_FAILURE=false
            shift
            ;;
        --sequential-build)
            PARALLEL_BUILD=false
            shift
            ;;
        --timeout)
            DEPLOYMENT_TIMEOUT="$2"
            shift 2
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
    --skip-backup       Skip backup creation
    --no-rollback       Disable automatic rollback on failure
    --sequential-build  Build services sequentially instead of parallel
    --timeout SECONDS   Set deployment timeout (default: 1800)
    --help              Show this help message

Environment Variables:
    SKIP_BACKUP         Skip backup creation (true/false)
    ROLLBACK_ON_FAILURE Automatic rollback on failure (true/false)
    PARALLEL_BUILD      Build services in parallel (true/false)
    
EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set timeout
timeout "$DEPLOYMENT_TIMEOUT" bash -c "$(declare -f main); main" || {
    log "ERROR" "Deployment timed out after ${DEPLOYMENT_TIMEOUT}s"
    exit 1
}