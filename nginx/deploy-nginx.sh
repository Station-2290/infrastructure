#!/bin/bash

# Nginx Deployment and Management Script
# Configuration Engineer: Hive Mind Swarm
# Comprehensive nginx deployment with security, monitoring, and optimization

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NGINX_CONF_DIR="/etc/nginx"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SSL_DIR="/etc/nginx/ssl"
NGINX_CACHE_DIR="/var/cache/nginx"
NGINX_LOG_DIR="/var/log/nginx"
BACKUP_DIR="/opt/nginx_backups"
PROJECT_DIR="/Users/hrustalq/Projects/station-2290"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Check if nginx is installed
check_nginx() {
    if ! command -v nginx &> /dev/null; then
        error "Nginx is not installed. Please install nginx first."
        exit 1
    fi
    log "Nginx is installed: $(nginx -v 2>&1)"
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    mkdir -p "$NGINX_SSL_DIR"
    mkdir -p "$NGINX_CACHE_DIR"/{app,static,api,fastcgi}
    mkdir -p "$NGINX_LOG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$NGINX_CONF_DIR"/{conf.d,snippets}
    
    # Set proper permissions
    chown -R nginx:nginx "$NGINX_CACHE_DIR" 2>/dev/null || chown -R www-data:www-data "$NGINX_CACHE_DIR"
    chmod -R 755 "$NGINX_CACHE_DIR"
    chmod -R 755 "$NGINX_LOG_DIR"
    chmod -R 700 "$NGINX_SSL_DIR"
    
    log "Directories created successfully"
}

# Backup current configuration
backup_config() {
    local backup_name="nginx_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Creating backup of current nginx configuration..."
    
    mkdir -p "$backup_path"
    
    # Backup nginx configuration
    if [[ -d "$NGINX_CONF_DIR" ]]; then
        cp -r "$NGINX_CONF_DIR" "$backup_path/"
        log "Configuration backed up to: $backup_path"
    else
        warning "No existing nginx configuration found"
    fi
    
    # Create backup info file
    cat > "$backup_path/backup_info.txt" << EOF
Backup Date: $(date)
Nginx Version: $(nginx -v 2>&1)
System: $(uname -a)
User: $(whoami)
Backup Path: $backup_path
EOF
}

# Install enhanced nginx configuration
install_config() {
    log "Installing enhanced nginx configuration..."
    
    # Copy main configuration
    if [[ -f "$PROJECT_DIR/infrastructure/nginx/nginx-optimized.conf" ]]; then
        cp "$PROJECT_DIR/infrastructure/nginx/nginx-optimized.conf" "$NGINX_CONF_DIR/nginx.conf"
        log "Main nginx configuration installed"
    else
        error "Optimized nginx configuration not found"
        exit 1
    fi
    
    # Copy snippets
    if [[ -d "$PROJECT_DIR/infrastructure/nginx/snippets" ]]; then
        cp -r "$PROJECT_DIR/infrastructure/nginx/snippets"/* "$NGINX_CONF_DIR/snippets/"
        log "Security and SSL snippets installed"
    fi
    
    # Copy site configurations
    if [[ -d "$PROJECT_DIR/infrastructure/nginx/sites-available" ]]; then
        cp -r "$PROJECT_DIR/infrastructure/nginx/sites-available"/* "$NGINX_SITES_AVAILABLE/"
        log "Site configurations installed"
    fi
    
    # Enable sites
    ln -sf "$NGINX_SITES_AVAILABLE/station2290.conf" "$NGINX_SITES_ENABLED/"
    log "Site configurations enabled"
}

# Generate DH parameters for SSL
generate_dhparam() {
    log "Generating DH parameters for SSL (this may take a while)..."
    
    if [[ ! -f "$NGINX_SSL_DIR/dhparam.pem" ]]; then
        openssl dhparam -out "$NGINX_SSL_DIR/dhparam.pem" 2048
        chmod 600 "$NGINX_SSL_DIR/dhparam.pem"
        log "DH parameters generated"
    else
        info "DH parameters already exist"
    fi
}

# Generate self-signed certificate for testing
generate_self_signed_cert() {
    log "Generating self-signed SSL certificate for testing..."
    
    if [[ ! -f "$NGINX_SSL_DIR/default.crt" ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$NGINX_SSL_DIR/default.key" \
            -out "$NGINX_SSL_DIR/default.crt" \
            -subj "/C=RU/ST=Moscow/L=Moscow/O=Station2290/CN=station2290.ru"
        
        chmod 600 "$NGINX_SSL_DIR/default.key"
        chmod 644 "$NGINX_SSL_DIR/default.crt"
        log "Self-signed certificate generated"
    else
        info "Self-signed certificate already exists"
    fi
}

# Test nginx configuration
test_config() {
    log "Testing nginx configuration..."
    
    if nginx -t; then
        log "Nginx configuration test passed"
        return 0
    else
        error "Nginx configuration test failed"
        return 1
    fi
}

# Start nginx service
start_nginx() {
    log "Starting nginx service..."
    
    if systemctl is-active --quiet nginx; then
        log "Reloading nginx configuration..."
        systemctl reload nginx
    else
        log "Starting nginx service..."
        systemctl start nginx
    fi
    
    systemctl enable nginx
    log "Nginx service started and enabled"
}

# Setup log rotation
setup_logrotate() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/nginx-enhanced << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 0640 nginx adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}

/var/log/nginx/ssl_access.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 nginx adm
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF
    
    log "Log rotation configured"
}

# Setup monitoring
setup_monitoring() {
    log "Setting up nginx monitoring..."
    
    # Create monitoring script
    cat > /usr/local/bin/nginx-monitor.sh << 'EOF'
#!/bin/bash

# Nginx Monitoring Script
# Checks nginx status and key metrics

LOG_FILE="/var/log/nginx/monitor.log"
ALERT_EMAIL="admin@station2290.ru"

log_message() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_nginx_status() {
    if ! systemctl is-active --quiet nginx; then
        log_message "ALERT: Nginx is not running"
        echo "Nginx service is down on $(hostname)" | mail -s "Nginx Alert" "$ALERT_EMAIL" 2>/dev/null || true
        return 1
    fi
    return 0
}

check_disk_space() {
    local cache_usage=$(df /var/cache/nginx | awk 'NR==2 {print $5}' | sed 's/%//')
    local log_usage=$(df /var/log/nginx | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $cache_usage -gt 80 ]]; then
        log_message "WARNING: Cache directory usage is ${cache_usage}%"
    fi
    
    if [[ $log_usage -gt 80 ]]; then
        log_message "WARNING: Log directory usage is ${log_usage}%"
    fi
}

check_connection_count() {
    local connections=$(ss -tln | grep -E ':80|:443' | wc -l)
    log_message "INFO: Active connections: $connections"
    
    if [[ $connections -gt 1000 ]]; then
        log_message "WARNING: High connection count: $connections"
    fi
}

# Run checks
check_nginx_status
check_disk_space
check_connection_count

log_message "Monitor check completed"
EOF
    
    chmod +x /usr/local/bin/nginx-monitor.sh
    
    # Setup cron job for monitoring
    echo "*/5 * * * * root /usr/local/bin/nginx-monitor.sh" > /etc/cron.d/nginx-monitor
    
    log "Nginx monitoring setup completed"
}

# Setup firewall rules
setup_firewall() {
    log "Setting up firewall rules..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 8080/tcp  # Monitoring port
        log "UFW firewall rules added"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --reload
        log "Firewalld rules added"
    else
        warning "No supported firewall found. Please configure manually."
    fi
}

# Performance tuning
tune_system() {
    log "Applying system performance tuning..."
    
    # Kernel parameters for high-performance nginx
    cat >> /etc/sysctl.conf << 'EOF'

# Nginx Performance Tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 65535
fs.nr_open = 65535
EOF
    
    # Apply sysctl changes
    sysctl -p
    
    # Increase nginx worker limits
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/override.conf << 'EOF'
[Service]
LimitNOFILE=65535
LimitNPROC=65535
EOF
    
    systemctl daemon-reload
    
    log "System performance tuning applied"
}

# Main deployment function
deploy() {
    log "Starting nginx deployment..."
    
    check_root
    check_nginx
    backup_config
    create_directories
    install_config
    generate_dhparam
    generate_self_signed_cert
    
    if test_config; then
        start_nginx
        setup_logrotate
        setup_monitoring
        setup_firewall
        tune_system
        
        log "Nginx deployment completed successfully!"
        log "Access nginx status at: http://localhost:8080/nginx_status"
        log "Health check at: http://localhost/health"
        
        # Display status
        info "Nginx Status:"
        systemctl status nginx --no-pager -l
        
        info "Listening Ports:"
        ss -tlnp | grep nginx || true
        
    else
        error "Deployment failed due to configuration errors"
        exit 1
    fi
}

# Rollback function
rollback() {
    log "Rolling back nginx configuration..."
    
    local latest_backup=$(ls -t "$BACKUP_DIR" | head -n 1)
    if [[ -n "$latest_backup" && -d "$BACKUP_DIR/$latest_backup/etc/nginx" ]]; then
        cp -r "$BACKUP_DIR/$latest_backup/etc/nginx"/* "$NGINX_CONF_DIR/"
        
        if test_config; then
            systemctl reload nginx
            log "Rollback completed successfully"
        else
            error "Rollback failed - configuration invalid"
            exit 1
        fi
    else
        error "No backup found for rollback"
        exit 1
    fi
}

# Status check function
status() {
    log "Checking nginx status..."
    
    systemctl status nginx --no-pager -l
    echo
    info "Configuration test:"
    nginx -t
    echo
    info "Listening ports:"
    ss -tlnp | grep nginx || true
    echo
    info "Worker processes:"
    ps aux | grep nginx | grep -v grep
    echo
    info "Cache usage:"
    du -sh "$NGINX_CACHE_DIR"/* 2>/dev/null || echo "No cache data"
}

# Usage information
usage() {
    echo "Usage: $0 {deploy|rollback|status|test}"
    echo
    echo "Commands:"
    echo "  deploy   - Deploy nginx with enhanced configuration"
    echo "  rollback - Rollback to previous configuration"
    echo "  status   - Show nginx status and configuration"
    echo "  test     - Test nginx configuration only"
    echo
    exit 1
}

# Main script logic
case "${1:-}" in
    deploy)
        deploy
        ;;
    rollback)
        rollback
        ;;
    status)
        status
        ;;
    test)
        test_config
        ;;
    *)
        usage
        ;;
esac