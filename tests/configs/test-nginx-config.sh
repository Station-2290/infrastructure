#!/bin/bash
# Test Nginx Configuration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Paths
NGINX_CONF="../../nginx/nginx.conf"
SITES_AVAILABLE="../../nginx/sites-available"
SITES_ENABLED="../../nginx/sites-enabled"
SNIPPETS="../../nginx/snippets"

echo "Testing Nginx configuration..."

# Check if nginx.conf exists
if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${RED}✗ nginx.conf not found at $NGINX_CONF${NC}"
    exit 1
fi

# Test nginx configuration syntax using docker
echo "Testing nginx configuration syntax..."
if docker run --rm -v "$(pwd)/../../nginx:/etc/nginx:ro" nginx:alpine nginx -t 2>&1; then
    echo -e "${GREEN}✓ Nginx configuration syntax is valid${NC}"
else
    echo -e "${RED}✗ Nginx configuration has syntax errors${NC}"
    exit 1
fi

# Check required site configurations
echo "Checking site configurations..."
REQUIRED_SITES=("api.conf" "adminka.conf" "bot.conf" "main.conf" "orders.conf")

for site in "${REQUIRED_SITES[@]}"; do
    if [ -f "$SITES_AVAILABLE/$site" ]; then
        echo -e "${GREEN}✓ Site configuration found: $site${NC}"
        
        # Check if site is enabled (symlinked)
        if [ -L "$SITES_ENABLED/$site" ]; then
            echo -e "${GREEN}  ✓ Site is enabled${NC}"
        else
            echo -e "${YELLOW}  ⚠ Site is not enabled (no symlink in sites-enabled)${NC}"
        fi
    else
        echo -e "${RED}✗ Site configuration missing: $site${NC}"
        exit 1
    fi
done

# Check SSL configuration
echo "Checking SSL configuration..."
if [ -f "$SNIPPETS/ssl-security.conf" ]; then
    echo -e "${GREEN}✓ SSL security snippet found${NC}"
    
    # Check for strong SSL protocols
    if grep -q "TLSv1.2\|TLSv1.3" "$SNIPPETS/ssl-security.conf"; then
        echo -e "${GREEN}✓ Strong TLS protocols configured${NC}"
    else
        echo -e "${YELLOW}⚠ Weak TLS protocols may be enabled${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SSL security snippet not found${NC}"
fi

# Check security headers
echo "Checking security headers configuration..."
if [ -f "$SNIPPETS/security-headers.conf" ]; then
    echo -e "${GREEN}✓ Security headers snippet found${NC}"
    
    # Check for important security headers
    SECURITY_HEADERS=("X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection" "Referrer-Policy" "Content-Security-Policy")
    
    for header in "${SECURITY_HEADERS[@]}"; do
        if grep -q "$header" "$SNIPPETS/security-headers.conf"; then
            echo -e "${GREEN}  ✓ $header is configured${NC}"
        else
            echo -e "${YELLOW}  ⚠ $header is not configured${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ Security headers snippet not found${NC}"
fi

# Check rate limiting configuration
echo "Checking rate limiting configuration..."
if grep -r "limit_req_zone\|limit_req" "$NGINX_CONF" "$SITES_AVAILABLE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Rate limiting is configured${NC}"
else
    echo -e "${YELLOW}⚠ No rate limiting configuration found${NC}"
fi

# Check gzip configuration
echo "Checking compression configuration..."
if grep -q "gzip on" "$NGINX_CONF"; then
    echo -e "${GREEN}✓ Gzip compression is enabled${NC}"
else
    echo -e "${YELLOW}⚠ Gzip compression is not enabled${NC}"
fi

# Check log configuration
echo "Checking logging configuration..."
if grep -q "access_log\|error_log" "$NGINX_CONF"; then
    echo -e "${GREEN}✓ Logging is configured${NC}"
    
    # Check log format
    if grep -q "log_format" "$NGINX_CONF"; then
        echo -e "${GREEN}  ✓ Custom log format is defined${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Logging configuration not found${NC}"
fi

# Check upstream configurations
echo "Checking upstream configurations..."
UPSTREAMS=("api" "bot" "web" "adminka" "order-panel")

for upstream in "${UPSTREAMS[@]}"; do
    if grep -r "upstream $upstream" "$NGINX_CONF" "$SITES_AVAILABLE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Upstream '$upstream' is defined${NC}"
    else
        # Check if using direct proxy_pass
        if grep -r "proxy_pass.*$upstream:" "$SITES_AVAILABLE" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Service '$upstream' is proxied directly${NC}"
        else
            echo -e "${YELLOW}⚠ No upstream or proxy configuration for '$upstream'${NC}"
        fi
    fi
done

# Check for common misconfigurations
echo "Checking for common misconfigurations..."

# Check for server_tokens
if grep -q "server_tokens off" "$NGINX_CONF"; then
    echo -e "${GREEN}✓ Server tokens are disabled (security best practice)${NC}"
else
    echo -e "${YELLOW}⚠ Server tokens are not disabled${NC}"
fi

# Check for client_max_body_size
if grep -r "client_max_body_size" "$NGINX_CONF" "$SITES_AVAILABLE" > /dev/null 2>&1; then
    MAX_SIZE=$(grep -r "client_max_body_size" "$NGINX_CONF" "$SITES_AVAILABLE" | head -1 | awk '{print $2}')
    echo -e "${GREEN}✓ Client max body size is set to: $MAX_SIZE${NC}"
else
    echo -e "${YELLOW}⚠ Client max body size is not configured${NC}"
fi

echo -e "${GREEN}✓ Nginx configuration validation completed${NC}"
exit 0