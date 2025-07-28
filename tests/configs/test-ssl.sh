#!/bin/bash
# Test SSL Certificates Configuration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SSL_DIR="/opt/station2290/ssl"
DOMAINS=("station2290.ru" "www.station2290.ru" "api.station2290.ru" "adminka.station2290.ru" "orders.station2290.ru" "bot.station2290.ru")
CERTBOT_CONTAINER="station2290_certbot"

echo "Testing SSL certificates configuration..."

# Function to check if domain certificate exists
check_certificate() {
    local domain="$1"
    local cert_path="$SSL_DIR/live/$domain/fullchain.pem"
    local key_path="$SSL_DIR/live/$domain/privkey.pem"
    
    echo "Checking certificate for $domain..."
    
    # Check if certificate files exist
    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
        echo -e "${GREEN}✓ Certificate files exist for $domain${NC}"
        
        # Check certificate expiration
        EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2 || echo "unknown")
        if [ "$EXPIRY_DATE" != "unknown" ]; then
            EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || echo "0")
            CURRENT_EPOCH=$(date +%s)
            DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
            
            if [ "$DAYS_UNTIL_EXPIRY" -gt 30 ]; then
                echo -e "${GREEN}✓ Certificate valid for $DAYS_UNTIL_EXPIRY days${NC}"
            elif [ "$DAYS_UNTIL_EXPIRY" -gt 7 ]; then
                echo -e "${YELLOW}⚠ Certificate expires in $DAYS_UNTIL_EXPIRY days${NC}"
            else
                echo -e "${RED}✗ Certificate expires in $DAYS_UNTIL_EXPIRY days (critical!)${NC}"
            fi
            
            echo "Expiry date: $EXPIRY_DATE"
        fi
        
        # Check certificate authority
        ISSUER=$(openssl x509 -issuer -noout -in "$cert_path" 2>/dev/null | grep -o "Let's Encrypt\|DigiCert\|Cloudflare" || echo "Unknown")
        echo "Certificate issuer: $ISSUER"
        
        # Check certificate subject alternative names (SAN)
        SANS=$(openssl x509 -text -noout -in "$cert_path" 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/.*DNS://g' | tr ',' '\n' | wc -l || echo "0")
        echo "Subject Alternative Names count: $SANS"
        
        return 0
    else
        echo -e "${RED}✗ Certificate files missing for $domain${NC}"
        return 1
    fi
}

# Check if SSL directory exists
if [ -d "$SSL_DIR" ]; then
    echo -e "${GREEN}✓ SSL directory exists: $SSL_DIR${NC}"
else
    echo -e "${YELLOW}⚠ SSL directory not found: $SSL_DIR${NC}"
    echo "This may be normal if certificates haven't been generated yet."
fi

# Check Certbot container
echo "\nChecking Certbot container..."
if docker ps --format "table {{.Names}}" | grep -q "$CERTBOT_CONTAINER"; then
    echo -e "${GREEN}✓ Certbot container is running${NC}"
    
    # Check Certbot logs
    echo "Recent Certbot activity:"
    docker logs --tail 10 "$CERTBOT_CONTAINER" 2>&1 | head -5
else
    echo -e "${YELLOW}⚠ Certbot container is not running${NC}"
    docker ps -a --filter "name=$CERTBOT_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
fi

# Check certificates for each domain
echo "\n${BLUE}=== Checking certificates for all domains ===${NC}"
CERT_SUCCESS=0
CERT_TOTAL=0

for domain in "${DOMAINS[@]}"; do
    ((CERT_TOTAL++))
    if check_certificate "$domain"; then
        ((CERT_SUCCESS++))
    fi
    echo ""
done

# Check nginx SSL configuration
echo "${BLUE}=== Checking Nginx SSL configuration ===${NC}"
NGINX_SSL_SNIPPET="../../nginx/snippets/ssl-security.conf"

if [ -f "$NGINX_SSL_SNIPPET" ]; then
    echo -e "${GREEN}✓ SSL security snippet found${NC}"
    
    # Check SSL protocols
    if grep -q "ssl_protocols TLSv1.2 TLSv1.3" "$NGINX_SSL_SNIPPET"; then
        echo -e "${GREEN}✓ Strong SSL protocols configured (TLS 1.2/1.3)${NC}"
    else
        echo -e "${YELLOW}⚠ SSL protocols configuration may be weak${NC}"
    fi
    
    # Check SSL ciphers
    if grep -q "ssl_ciphers" "$NGINX_SSL_SNIPPET"; then
        echo -e "${GREEN}✓ SSL ciphers are configured${NC}"
    else
        echo -e "${YELLOW}⚠ SSL ciphers not explicitly configured${NC}"
    fi
    
    # Check HSTS
    if grep -q "Strict-Transport-Security" "$NGINX_SSL_SNIPPET"; then
        echo -e "${GREEN}✓ HSTS (HTTP Strict Transport Security) is enabled${NC}"
    else
        echo -e "${YELLOW}⚠ HSTS is not configured${NC}"
    fi
    
    # Check SSL session settings
    if grep -q "ssl_session_cache" "$NGINX_SSL_SNIPPET"; then
        echo -e "${GREEN}✓ SSL session cache is configured${NC}"
    else
        echo -e "${YELLOW}⚠ SSL session cache not configured${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SSL security snippet not found${NC}"
fi

# Test SSL certificate renewal
echo "\n${BLUE}=== Testing SSL certificate renewal ===${NC}"
if docker ps --format "table {{.Names}}" | grep -q "$CERTBOT_CONTAINER"; then
    echo "Testing Certbot renewal (dry run)..."
    RENEWAL_TEST=$(docker exec "$CERTBOT_CONTAINER" certbot renew --dry-run 2>&1 || echo "failed")
    
    if echo "$RENEWAL_TEST" | grep -q "Congratulations, all renewals succeeded"; then
        echo -e "${GREEN}✓ Certificate renewal test passed${NC}"
    elif echo "$RENEWAL_TEST" | grep -q "no action taken"; then
        echo -e "${GREEN}✓ Certificates are up to date${NC}"
    else
        echo -e "${YELLOW}⚠ Certificate renewal test had issues${NC}"
        echo "Renewal output (last 3 lines):"
        echo "$RENEWAL_TEST" | tail -3
    fi
else
    echo -e "${YELLOW}⚠ Cannot test renewal - Certbot container not running${NC}"
fi

# Check Let's Encrypt rate limits
echo "\n${BLUE}=== Checking certificate issuance information ===${NC}"
for domain in "${DOMAINS[@]}"; do
    cert_path="$SSL_DIR/live/$domain/fullchain.pem"
    if [ -f "$cert_path" ]; then
        ISSUE_DATE=$(openssl x509 -startdate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2 || echo "unknown")
        if [ "$ISSUE_DATE" != "unknown" ]; then
            echo "$domain certificate issued: $ISSUE_DATE"
        fi
    fi
done

# Check for certificate backup
echo "\n${BLUE}=== Checking certificate backup ===${NC}"
BACKUP_DIR="/opt/station2290/backups/ssl"
if [ -d "$BACKUP_DIR" ]; then
    echo -e "${GREEN}✓ SSL backup directory exists${NC}"
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l || echo "0")
    echo "SSL backup files: $BACKUP_COUNT"
else
    echo -e "${YELLOW}⚠ SSL backup directory not found${NC}"
fi

# Test HTTPS connectivity (if certificates exist)
echo "\n${BLUE}=== Testing HTTPS connectivity ===${NC}"
for domain in "${DOMAINS[@]}"; do
    echo -n "Testing HTTPS for $domain: "
    
    # Skip test if it's an internal domain that won't resolve
    if echo "$domain" | grep -q "localhost\|127.0.0.1"; then
        echo -e "${YELLOW}Skipped (localhost)${NC}"
        continue
    fi
    
    HTTPS_TEST=$(curl -s -I --connect-timeout 5 "https://$domain" 2>/dev/null | head -1 || echo "failed")
    if echo "$HTTPS_TEST" | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✓ HTTPS working${NC}"
    else
        echo -e "${YELLOW}⚠ HTTPS test failed (may be expected if not deployed)${NC}"
    fi
done

# Summary
echo "\n${BLUE}=== SSL Configuration Summary ===${NC}"
echo "Certificates checked: $CERT_SUCCESS/$CERT_TOTAL"

if [ "$CERT_SUCCESS" -eq "$CERT_TOTAL" ] && [ "$CERT_TOTAL" -gt 0 ]; then
    echo -e "${GREEN}✓ All SSL certificates are properly configured${NC}"
    exit 0
elif [ "$CERT_TOTAL" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No certificates found (may be expected for new deployment)${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Some SSL certificates need attention${NC}"
    exit 1
fi