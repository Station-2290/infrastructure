#!/bin/bash

# Station2290 SSL Certificate Setup Script
# Automated SSL certificate generation and renewal setup using Let's Encrypt

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTRUCTURE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$INFRASTRUCTURE_ROOT/configs/environment/.env.prod"

# SSL Configuration
SSL_DIR="/opt/station2290/ssl"
CERTS_DIR="$SSL_DIR/certs"
CHALLENGES_DIR="$SSL_DIR/challenges"
LOGS_DIR="$SSL_DIR/logs"
RENEWAL_HOOKS_DIR="$SSL_DIR/renewal-hooks"

# Default values
DOMAINS="${SSL_DOMAINS:-station2290.ru,www.station2290.ru,api.station2290.ru,adminka.station2290.ru,orders.station2290.ru,bot.station2290.ru}"
EMAIL="${SSL_EMAIL:-n1k3f1t@gmail.com}"
STAGING="${SSL_STAGING:-false}"
FORCE_RENEWAL="${SSL_FORCE_RENEWAL:-false}"
DRY_RUN="${SSL_DRY_RUN:-false}"

# Logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[$timestamp] [INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR]${NC} $message" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] [SUCCESS]${NC} $message" ;;
    esac
}

# Setup SSL directories
setup_ssl_directories() {
    log "INFO" "Setting up SSL directories..."
    
    local dirs=("$SSL_DIR" "$CERTS_DIR" "$CHALLENGES_DIR" "$LOGS_DIR" "$RENEWAL_HOOKS_DIR")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "INFO" "Created directory: $dir"
        fi
    done
    
    # Set proper permissions
    chmod 755 "$SSL_DIR"
    chmod 755 "$CERTS_DIR"
    chmod 755 "$CHALLENGES_DIR"
    chmod 755 "$LOGS_DIR"
    chmod 755 "$RENEWAL_HOOKS_DIR"
    
    log "SUCCESS" "SSL directories configured"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
        log "ERROR" "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        log "INFO" "Installing certbot..."
        
        if command -v apt-get &> /dev/null; then
            # Ubuntu/Debian
            apt-get update
            apt-get install -y certbot
        elif command -v yum &> /dev/null; then
            # CentOS/RHEL
            yum install -y certbot
        elif command -v dnf &> /dev/null; then
            # Fedora
            dnf install -y certbot
        else
            log "ERROR" "Cannot install certbot automatically. Please install it manually."
            exit 1
        fi
        
        log "SUCCESS" "Certbot installed"
    fi
    
    # Check if nginx is available
    if ! command -v nginx &> /dev/null && ! docker ps --format "table {{.Names}}" | grep -q nginx; then
        log "WARN" "Nginx not found. Make sure it's installed or running in Docker."
    fi
    
    # Check DNS resolution
    log "INFO" "Checking DNS resolution..."
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)  # Trim whitespace
        if nslookup "$domain" > /dev/null 2>&1; then
            log "SUCCESS" "DNS resolution OK for: $domain"
        else
            log "WARN" "DNS resolution failed for: $domain"
        fi
    done
}

# Create nginx configuration for ACME challenge
create_acme_nginx_config() {
    log "INFO" "Creating nginx configuration for ACME challenge..."
    
    local nginx_config_dir="$INFRASTRUCTURE_ROOT/nginx/sites-available"
    local acme_config="$nginx_config_dir/acme-challenge.conf"
    
    mkdir -p "$nginx_config_dir"
    
    cat > "$acme_config" << EOF
# ACME Challenge Configuration for SSL Certificate Generation
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    # ACME challenge location
    location /.well-known/acme-challenge/ {
        root $CHALLENGES_DIR;
        try_files \$uri =404;
        allow all;
    }
    
    # Redirect all other requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    
    log "SUCCESS" "ACME nginx configuration created"
    
    # Test nginx configuration
    if command -v nginx &> /dev/null; then
        nginx -t -c "$INFRASTRUCTURE_ROOT/nginx/nginx.conf" || {
            log "WARN" "Nginx configuration test failed"
        }
    fi
}

# Generate temporary self-signed certificates
generate_temporary_certificates() {
    log "INFO" "Generating temporary self-signed certificates..."
    
    local temp_cert_dir="$SSL_DIR/temp"
    mkdir -p "$temp_cert_dir"
    
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    local primary_domain="${DOMAIN_ARRAY[0]}"
    primary_domain=$(echo "$primary_domain" | xargs)
    
    # Create OpenSSL configuration
    cat > "$temp_cert_dir/openssl.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = RU
ST = Moscow
L = Moscow
O = Station2290
OU = IT Department
CN = $primary_domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
EOF
    
    # Add all domains to SAN
    local i=1
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        echo "DNS.$i = $domain" >> "$temp_cert_dir/openssl.conf"
        ((i++))
    done
    
    # Generate private key and certificate
    openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
        -keyout "$temp_cert_dir/privkey.pem" \
        -out "$temp_cert_dir/fullchain.pem" \
        -config "$temp_cert_dir/openssl.conf" \
        -extensions v3_req
    
    # Create certificate chain
    cp "$temp_cert_dir/fullchain.pem" "$temp_cert_dir/chain.pem"
    
    log "SUCCESS" "Temporary certificates generated"
}

# Setup nginx with temporary certificates
setup_nginx_temporary() {
    log "INFO" "Setting up nginx with temporary certificates..."
    
    # Create symlinks for sites-enabled
    local sites_available="$INFRASTRUCTURE_ROOT/nginx/sites-available"
    local sites_enabled="$INFRASTRUCTURE_ROOT/nginx/sites-enabled"
    
    mkdir -p "$sites_enabled"
    
    # Remove existing symlinks
    rm -f "$sites_enabled"/*
    
    # Enable ACME challenge configuration
    ln -sf "$sites_available/acme-challenge.conf" "$sites_enabled/"
    
    # Start nginx with Docker if not running
    if ! docker ps --format "table {{.Names}}" | grep -q nginx; then
        log "INFO" "Starting nginx container for certificate generation..."
        
        # Use a minimal nginx setup for certificate generation
        docker run -d --name nginx-certbot-temp \
            -p 80:80 \
            -v "$INFRASTRUCTURE_ROOT/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
            -v "$sites_enabled:/etc/nginx/sites-enabled:ro" \
            -v "$INFRASTRUCTURE_ROOT/nginx/snippets:/etc/nginx/snippets:ro" \
            -v "$CHALLENGES_DIR:/var/www/certbot:ro" \
            -v "$SSL_DIR/temp:/etc/ssl/temp:ro" \
            nginx:1.25-alpine
        
        sleep 5
    fi
    
    log "SUCCESS" "Nginx configured for certificate generation"
}

# Obtain SSL certificates
obtain_ssl_certificates() {
    log "INFO" "Obtaining SSL certificates from Let's Encrypt..."
    
    local certbot_args=""
    
    # Add staging flag if enabled
    if [[ "$STAGING" == "true" ]]; then
        certbot_args="--staging"
        log "WARN" "Using Let's Encrypt staging environment"
    fi
    
    # Add dry-run flag if enabled
    if [[ "$DRY_RUN" == "true" ]]; then
        certbot_args="$certbot_args --dry-run"
        log "INFO" "Running in dry-run mode"
    fi
    
    # Add force renewal flag if enabled
    if [[ "$FORCE_RENEWAL" == "true" ]]; then
        certbot_args="$certbot_args --force-renewal"
        log "WARN" "Forcing certificate renewal"
    fi
    
    # Prepare domain arguments
    local domain_args=""
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        domain_args="$domain_args -d $domain"
    done
    
    # Run certbot
    local certbot_command="certbot certonly \
        --webroot \
        --webroot-path=$CHALLENGES_DIR \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --cert-path $CERTS_DIR \
        --key-path $CERTS_DIR \
        --fullchain-path $CERTS_DIR \
        --chain-path $CERTS_DIR \
        $domain_args \
        $certbot_args"
    
    log "INFO" "Running: $certbot_command"
    
    if eval "$certbot_command"; then
        log "SUCCESS" "SSL certificates obtained successfully"
    else
        log "ERROR" "Failed to obtain SSL certificates"
        return 1
    fi
    
    # Verify certificates were created
    local primary_domain="${DOMAIN_ARRAY[0]}"
    primary_domain=$(echo "$primary_domain" | xargs)
    
    if [[ -f "/etc/letsencrypt/live/$primary_domain/fullchain.pem" ]]; then
        log "SUCCESS" "Certificate files verified"
        
        # Show certificate information
        log "INFO" "Certificate information:"
        openssl x509 -in "/etc/letsencrypt/live/$primary_domain/fullchain.pem" -text -noout | grep -E "(Subject:|DNS:|Not After)"
    else
        log "ERROR" "Certificate files not found"
        return 1
    fi
}

# Setup certificate renewal
setup_certificate_renewal() {
    log "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal hook scripts
    create_renewal_hooks
    
    # Setup cron job for renewal
    local cron_job="0 12 * * * /usr/bin/certbot renew --quiet --deploy-hook '$RENEWAL_HOOKS_DIR/deploy-hook.sh'"
    
    # Add cron job if it doesn't exist
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log "SUCCESS" "Cron job for certificate renewal added"
    else
        log "INFO" "Certificate renewal cron job already exists"
    fi
    
    # Create systemd timer as alternative (if systemd is available)
    if command -v systemctl &> /dev/null; then
        create_systemd_renewal_timer
    fi
    
    log "SUCCESS" "Certificate renewal configured"
}

# Create renewal hook scripts
create_renewal_hooks() {
    log "INFO" "Creating renewal hook scripts..."
    
    # Pre-hook script
    cat > "$RENEWAL_HOOKS_DIR/pre-hook.sh" << 'EOF'
#!/bin/bash
# Pre-renewal hook - runs before certificate renewal

set -euo pipefail

echo "$(date): Starting certificate renewal pre-hook"

# Stop nginx gracefully
if docker ps --format "table {{.Names}}" | grep -q nginx; then
    echo "Stopping nginx container..."
    docker stop nginx || true
fi

# Ensure challenge directory is accessible
chmod 755 /opt/station2290/ssl/challenges

echo "$(date): Pre-hook completed"
EOF
    
    # Deploy-hook script
    cat > "$RENEWAL_HOOKS_DIR/deploy-hook.sh" << 'EOF'
#!/bin/bash
# Deploy hook - runs after successful certificate renewal

set -euo pipefail

INFRASTRUCTURE_ROOT="/opt/station2290/infrastructure"
DOCKER_COMPOSE_FILE="$INFRASTRUCTURE_ROOT/docker/production/docker-compose.yml"

echo "$(date): Starting certificate renewal deploy-hook"

# Copy new certificates to Docker volumes
if [[ -d "/etc/letsencrypt/live" ]]; then
    echo "Copying certificates..."
    cp -r /etc/letsencrypt/* /opt/station2290/ssl/certs/
    chmod -R 644 /opt/station2290/ssl/certs/
fi

# Restart nginx to load new certificates
if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    echo "Restarting nginx..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" restart nginx
else
    echo "Restarting nginx container..."
    docker restart nginx 2>/dev/null || true
fi

# Send notification (optional)
curl -X POST "${SLACK_WEBHOOK_URL:-}" \
    -H 'Content-type: application/json' \
    --data '{"text":"SSL certificates renewed successfully for Station2290"}' \
    2>/dev/null || true

echo "$(date): Deploy-hook completed"
EOF
    
    # Post-hook script
    cat > "$RENEWAL_HOOKS_DIR/post-hook.sh" << 'EOF'
#!/bin/bash
# Post-renewal hook - runs after certificate renewal (success or failure)

set -euo pipefail

echo "$(date): Starting certificate renewal post-hook"

# Log renewal status
echo "$(date): Certificate renewal completed" >> /opt/station2290/logs/ssl-renewal.log

# Cleanup any temporary files
rm -rf /tmp/certbot-* 2>/dev/null || true

echo "$(date): Post-hook completed"
EOF
    
    # Make scripts executable
    chmod +x "$RENEWAL_HOOKS_DIR"/*.sh
    
    log "SUCCESS" "Renewal hook scripts created"
}

# Create systemd renewal timer
create_systemd_renewal_timer() {
    log "INFO" "Creating systemd renewal timer..."
    
    # Create service file
    cat > /etc/systemd/system/certbot-renewal.service << EOF
[Unit]
Description=Certbot Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook $RENEWAL_HOOKS_DIR/deploy-hook.sh
PrivateTmp=true
EOF
    
    # Create timer file
    cat > /etc/systemd/system/certbot-renewal.timer << EOF
[Unit]
Description=Run certbot twice daily
Requires=certbot-renewal.service

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    systemctl daemon-reload
    systemctl enable certbot-renewal.timer
    systemctl start certbot-renewal.timer
    
    log "SUCCESS" "Systemd renewal timer configured"
}

# Cleanup temporary nginx
cleanup_temporary_nginx() {
    log "INFO" "Cleaning up temporary nginx setup..."
    
    # Stop temporary nginx container
    docker stop nginx-certbot-temp 2>/dev/null || true
    docker rm nginx-certbot-temp 2>/dev/null || true
    
    # Remove temporary certificates
    rm -rf "$SSL_DIR/temp"
    
    log "SUCCESS" "Temporary nginx cleanup completed"
}

# Setup production nginx with SSL
setup_production_nginx() {
    log "INFO" "Setting up production nginx with SSL..."
    
    local sites_available="$INFRASTRUCTURE_ROOT/nginx/sites-available"
    local sites_enabled="$INFRASTRUCTURE_ROOT/nginx/sites-enabled"
    
    # Remove ACME challenge configuration
    rm -f "$sites_enabled/acme-challenge.conf"
    
    # Enable production site configurations
    local site_configs=("main.conf" "api.conf" "adminka.conf" "orders.conf" "bot.conf")
    
    for config in "${site_configs[@]}"; do
        if [[ -f "$sites_available/$config" ]]; then
            ln -sf "$sites_available/$config" "$sites_enabled/"
            log "INFO" "Enabled site configuration: $config"
        fi
    done
    
    # Copy certificates to proper location for Docker
    if [[ -d "/etc/letsencrypt/live" ]]; then
        cp -r /etc/letsencrypt/* "$CERTS_DIR/"
        chmod -R 644 "$CERTS_DIR/"
        log "SUCCESS" "Certificates copied to Docker volume"
    fi
    
    log "SUCCESS" "Production nginx with SSL configured"
}

# Verify SSL configuration
verify_ssl_configuration() {
    log "INFO" "Verifying SSL configuration..."
    
    # Check certificate files
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    local primary_domain="${DOMAIN_ARRAY[0]}"
    primary_domain=$(echo "$primary_domain" | xargs)
    
    local cert_files=(
        "/etc/letsencrypt/live/$primary_domain/fullchain.pem"
        "/etc/letsencrypt/live/$primary_domain/privkey.pem"
        "/etc/letsencrypt/live/$primary_domain/chain.pem"
    )
    
    for cert_file in "${cert_files[@]}"; do
        if [[ -f "$cert_file" ]]; then
            log "SUCCESS" "Certificate file exists: $cert_file"
        else
            log "ERROR" "Certificate file missing: $cert_file"
            return 1
        fi
    done
    
    # Check certificate validity
    local cert_expiry=$(openssl x509 -in "/etc/letsencrypt/live/$primary_domain/fullchain.pem" -noout -enddate | cut -d= -f2)
    local expiry_timestamp=$(date -d "$cert_expiry" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [[ $days_until_expiry -gt 30 ]]; then
        log "SUCCESS" "Certificate valid for $days_until_expiry days"
    elif [[ $days_until_expiry -gt 0 ]]; then
        log "WARN" "Certificate expires in $days_until_expiry days"
    else
        log "ERROR" "Certificate has expired"
        return 1
    fi
    
    log "SUCCESS" "SSL configuration verified"
}

# Test SSL endpoints
test_ssl_endpoints() {
    log "INFO" "Testing SSL endpoints..."
    
    # Wait for nginx to start
    sleep 10
    
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)
        
        local url="https://$domain"
        
        # Skip bot domain for basic connectivity test
        if [[ "$domain" == *"bot."* ]]; then
            url="$url/health"
        fi
        
        log "INFO" "Testing: $url"
        
        if curl -sSf --max-time 10 --connect-timeout 5 "$url" > /dev/null 2>&1; then
            log "SUCCESS" "SSL test passed: $domain"
        else
            log "WARN" "SSL test failed: $domain (may not be ready yet)"
        fi
    done
}

# Main function
main() {
    echo -e "${BLUE}"
    cat << "EOF"
   _____ _____ _      
  / ____/ ____| |     
 | (___| (___ | |     
  \___ \\___ \| |     
  ____) |___) | |____ 
 |_____/_____/|______|
                      
Station2290 SSL Setup v2.0
EOF
    echo -e "${NC}"
    
    log "INFO" "Starting SSL certificate setup..."
    
    # Load environment if available
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        log "INFO" "Environment loaded from: $ENV_FILE"
    fi
    
    # Override with environment variables if set
    DOMAINS="${SSL_DOMAINS:-$DOMAINS}"
    EMAIL="${SSL_EMAIL:-$EMAIL}"
    STAGING="${SSL_STAGING:-$STAGING}"
    FORCE_RENEWAL="${SSL_FORCE_RENEWAL:-$FORCE_RENEWAL}"
    DRY_RUN="${SSL_DRY_RUN:-$DRY_RUN}"
    
    log "INFO" "Configuration:"
    log "INFO" "  Domains: $DOMAINS"
    log "INFO" "  Email: $EMAIL"
    log "INFO" "  Staging: $STAGING"
    log "INFO" "  Force Renewal: $FORCE_RENEWAL"
    log "INFO" "  Dry Run: $DRY_RUN"
    
    # Main workflow
    setup_ssl_directories
    check_prerequisites
    create_acme_nginx_config
    generate_temporary_certificates
    setup_nginx_temporary
    
    if obtain_ssl_certificates; then
        cleanup_temporary_nginx
        setup_production_nginx
        setup_certificate_renewal
        verify_ssl_configuration
        test_ssl_endpoints
        
        log "SUCCESS" "SSL setup completed successfully!"
        
        cat << EOF

🔒 SSL Certificates Successfully Configured!

Domains: $DOMAINS
Certificate Path: /etc/letsencrypt/live/
Renewal: Automatic (daily at 12:00 and 24:00)

Next Steps:
1. Start the full application stack
2. Verify HTTPS access to all domains
3. Check certificate auto-renewal: certbot renew --dry-run

EOF
    else
        log "ERROR" "SSL certificate generation failed"
        cleanup_temporary_nginx
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domains)
            DOMAINS="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --staging)
            STAGING=true
            shift
            ;;
        --force-renewal)
            FORCE_RENEWAL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
    --domains DOMAINS    Comma-separated list of domains
    --email EMAIL        Email for Let's Encrypt registration
    --staging            Use Let's Encrypt staging environment
    --force-renewal      Force certificate renewal
    --dry-run            Perform a dry run
    --help               Show this help message

Environment Variables:
    SSL_DOMAINS          Comma-separated list of domains
    SSL_EMAIL            Email for Let's Encrypt registration
    SSL_STAGING          Use staging environment (true/false)
    SSL_FORCE_RENEWAL    Force renewal (true/false)
    SSL_DRY_RUN          Dry run mode (true/false)

EOF
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"