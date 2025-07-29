#!/bin/bash
# Comprehensive Nginx Validation Suite for Station2290
# Validates all aspects of nginx configuration including syntax, security, SSL/TLS, performance

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration paths
NGINX_CONF_DIR="$(dirname "$0")/../../infrastructure/nginx"
NGINX_MAIN_CONF="$NGINX_CONF_DIR/nginx.conf"
SITES_AVAILABLE="$NGINX_CONF_DIR/sites-available"
SNIPPETS_DIR="$NGINX_CONF_DIR/snippets"
REPORT_FILE="nginx-validation-report.md"

# Validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Test result tracking
declare -A test_results

# Helper functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    test_results["$1"]="PASS"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    test_results["$1"]="FAIL"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Initialize report
init_report() {
    cat > "$REPORT_FILE" << EOF
# Nginx Configuration Validation Report
Generated: $(date)

## Summary
- Total Tests: _TBD_
- Passed: _TBD_
- Failed: _TBD_
- Warnings: _TBD_

## Test Results

EOF
}

# Finalize report
finalize_report() {
    # Update summary
    sed -i.bak "s/_TBD_/$TOTAL_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$PASSED_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$FAILED_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$WARNINGS/1" "$REPORT_FILE"
    rm "$REPORT_FILE.bak"
}

# 1. Syntax Validation Tests
test_nginx_syntax() {
    echo -e "\n${PURPLE}=== Testing Nginx Configuration Syntax ===${NC}"
    
    log_test "Main nginx.conf syntax"
    if docker run --rm -v "$NGINX_CONF_DIR:/etc/nginx:ro" nginx:alpine nginx -t 2>&1 | grep -q "syntax is ok"; then
        log_pass "Main configuration syntax is valid"
        echo "✓ Main configuration syntax is valid" >> "$REPORT_FILE"
    else
        log_fail "Main configuration has syntax errors"
        echo "✗ Main configuration has syntax errors" >> "$REPORT_FILE"
        docker run --rm -v "$NGINX_CONF_DIR:/etc/nginx:ro" nginx:alpine nginx -t 2>&1 >> "$REPORT_FILE"
    fi
    
    # Test individual site configurations
    for conf in "$SITES_AVAILABLE"/*.conf; do
        if [ -f "$conf" ]; then
            site_name=$(basename "$conf")
            log_test "Syntax check for $site_name"
            
            # Create temporary test config
            temp_conf="/tmp/nginx-test-$site_name"
            cat > "$temp_conf" << EOF
events {
    worker_connections 1024;
}
http {
    include $(realpath "$conf");
}
EOF
            
            if docker run --rm -v "$temp_conf:/etc/nginx/nginx.conf:ro" -v "$NGINX_CONF_DIR:/etc/nginx:ro" nginx:alpine nginx -t 2>&1 | grep -q "syntax is ok"; then
                log_pass "Site configuration $site_name syntax is valid"
                echo "✓ Site configuration $site_name syntax is valid" >> "$REPORT_FILE"
            else
                log_fail "Site configuration $site_name has syntax errors"
                echo "✗ Site configuration $site_name has syntax errors" >> "$REPORT_FILE"
            fi
            
            rm -f "$temp_conf"
        fi
    done
}

# 2. SSL/TLS Configuration Tests
test_ssl_configuration() {
    echo -e "\n${PURPLE}=== Testing SSL/TLS Configuration ===${NC}"
    
    log_test "SSL protocols configuration"
    if grep -q "ssl_protocols.*TLSv1.2.*TLSv1.3" "$NGINX_MAIN_CONF" || grep -q "ssl_protocols.*TLSv1.2.*TLSv1.3" "$SNIPPETS_DIR"/*.conf 2>/dev/null; then
        log_pass "Strong TLS protocols (1.2 and 1.3) are configured"
        echo "✓ Strong TLS protocols (1.2 and 1.3) are configured" >> "$REPORT_FILE"
    else
        log_fail "Weak or missing TLS protocol configuration"
        echo "✗ Weak or missing TLS protocol configuration" >> "$REPORT_FILE"
    fi
    
    log_test "SSL cipher strength"
    if grep -E "ssl_ciphers.*ECDHE.*GCM.*SHA256" "$NGINX_MAIN_CONF" || grep -E "ssl_ciphers.*ECDHE.*GCM.*SHA256" "$SNIPPETS_DIR"/*.conf 2>/dev/null; then
        log_pass "Strong SSL ciphers are configured"
        echo "✓ Strong SSL ciphers are configured" >> "$REPORT_FILE"
    else
        log_warn "SSL ciphers may need strengthening"
        echo "⚠ SSL ciphers may need strengthening" >> "$REPORT_FILE"
    fi
    
    log_test "HSTS (HTTP Strict Transport Security)"
    if grep -q "Strict-Transport-Security" "$SNIPPETS_DIR"/*.conf 2>/dev/null || grep -q "Strict-Transport-Security" "$NGINX_MAIN_CONF"; then
        log_pass "HSTS header is configured"
        echo "✓ HSTS header is configured" >> "$REPORT_FILE"
    else
        log_fail "HSTS header is not configured"
        echo "✗ HSTS header is not configured" >> "$REPORT_FILE"
    fi
    
    log_test "SSL session cache"
    if grep -q "ssl_session_cache" "$NGINX_MAIN_CONF" || grep -q "ssl_session_cache" "$SNIPPETS_DIR"/*.conf 2>/dev/null; then
        log_pass "SSL session cache is configured"
        echo "✓ SSL session cache is configured" >> "$REPORT_FILE"
    else
        log_warn "SSL session cache is not configured"
        echo "⚠ SSL session cache is not configured" >> "$REPORT_FILE"
    fi
    
    log_test "OCSP stapling"
    if grep -q "ssl_stapling on" "$NGINX_MAIN_CONF" || grep -q "ssl_stapling on" "$SNIPPETS_DIR"/*.conf 2>/dev/null; then
        log_pass "OCSP stapling is enabled"
        echo "✓ OCSP stapling is enabled" >> "$REPORT_FILE"
    else
        log_warn "OCSP stapling is not enabled"
        echo "⚠ OCSP stapling is not enabled" >> "$REPORT_FILE"
    fi
}

# 3. Security Headers Tests
test_security_headers() {
    echo -e "\n${PURPLE}=== Testing Security Headers ===${NC}"
    
    SECURITY_HEADERS=(
        "X-Frame-Options:SAMEORIGIN protection"
        "X-Content-Type-Options:MIME type sniffing protection"
        "X-XSS-Protection:XSS protection"
        "Referrer-Policy:Referrer policy"
        "Content-Security-Policy:Content Security Policy"
    )
    
    for header_config in "${SECURITY_HEADERS[@]}"; do
        IFS=':' read -r header description <<< "$header_config"
        log_test "$description ($header)"
        
        if grep -r "add_header $header" "$NGINX_CONF_DIR" > /dev/null 2>&1; then
            log_pass "$description is configured"
            echo "✓ $description is configured" >> "$REPORT_FILE"
        else
            log_fail "$description is missing"
            echo "✗ $description is missing" >> "$REPORT_FILE"
        fi
    done
    
    log_test "Server tokens disclosure"
    if grep -q "server_tokens off" "$NGINX_MAIN_CONF"; then
        log_pass "Server tokens are disabled (security best practice)"
        echo "✓ Server tokens are disabled" >> "$REPORT_FILE"
    else
        log_fail "Server tokens are not disabled"
        echo "✗ Server tokens are not disabled" >> "$REPORT_FILE"
    fi
}

# 4. Rate Limiting Tests
test_rate_limiting() {
    echo -e "\n${PURPLE}=== Testing Rate Limiting Configuration ===${NC}"
    
    log_test "Rate limiting zones"
    rate_zones=$(grep -c "limit_req_zone" "$NGINX_MAIN_CONF" 2>/dev/null || echo 0)
    if [ "$rate_zones" -gt 0 ]; then
        log_pass "Rate limiting zones configured: $rate_zones zones"
        echo "✓ Rate limiting zones configured: $rate_zones zones" >> "$REPORT_FILE"
        
        # Check for specific zones
        zones=("api" "general" "bot" "auth" "upload")
        for zone in "${zones[@]}"; do
            if grep -q "zone=$zone:" "$NGINX_MAIN_CONF"; then
                log_info "  - Zone '$zone' is configured"
                echo "  - Zone '$zone' is configured" >> "$REPORT_FILE"
            fi
        done
    else
        log_fail "No rate limiting zones configured"
        echo "✗ No rate limiting zones configured" >> "$REPORT_FILE"
    fi
    
    log_test "Connection limiting zones"
    conn_zones=$(grep -c "limit_conn_zone" "$NGINX_MAIN_CONF" 2>/dev/null || echo 0)
    if [ "$conn_zones" -gt 0 ]; then
        log_pass "Connection limiting zones configured: $conn_zones zones"
        echo "✓ Connection limiting zones configured: $conn_zones zones" >> "$REPORT_FILE"
    else
        log_warn "No connection limiting zones configured"
        echo "⚠ No connection limiting zones configured" >> "$REPORT_FILE"
    fi
}

# 5. Performance Configuration Tests
test_performance_config() {
    echo -e "\n${PURPLE}=== Testing Performance Configuration ===${NC}"
    
    log_test "Gzip compression"
    if grep -q "gzip on" "$NGINX_MAIN_CONF"; then
        log_pass "Gzip compression is enabled"
        echo "✓ Gzip compression is enabled" >> "$REPORT_FILE"
        
        # Check compression level
        comp_level=$(grep "gzip_comp_level" "$NGINX_MAIN_CONF" | awk '{print $2}' | tr -d ';')
        if [ -n "$comp_level" ]; then
            log_info "  - Compression level: $comp_level"
            echo "  - Compression level: $comp_level" >> "$REPORT_FILE"
        fi
    else
        log_fail "Gzip compression is not enabled"
        echo "✗ Gzip compression is not enabled" >> "$REPORT_FILE"
    fi
    
    log_test "Worker processes configuration"
    if grep -q "worker_processes auto" "$NGINX_MAIN_CONF"; then
        log_pass "Worker processes set to auto (optimal)"
        echo "✓ Worker processes set to auto" >> "$REPORT_FILE"
    else
        log_warn "Worker processes not set to auto"
        echo "⚠ Worker processes not set to auto" >> "$REPORT_FILE"
    fi
    
    log_test "Worker connections"
    worker_conn=$(grep "worker_connections" "$NGINX_MAIN_CONF" | awk '{print $2}' | tr -d ';')
    if [ -n "$worker_conn" ] && [ "$worker_conn" -ge 1024 ]; then
        log_pass "Worker connections: $worker_conn"
        echo "✓ Worker connections: $worker_conn" >> "$REPORT_FILE"
    else
        log_warn "Worker connections may be too low"
        echo "⚠ Worker connections may be too low" >> "$REPORT_FILE"
    fi
    
    log_test "Keepalive configuration"
    if grep -q "keepalive_timeout" "$NGINX_MAIN_CONF"; then
        timeout=$(grep "keepalive_timeout" "$NGINX_MAIN_CONF" | awk '{print $2}' | tr -d 's;')
        log_pass "Keepalive timeout configured: ${timeout}s"
        echo "✓ Keepalive timeout configured: ${timeout}s" >> "$REPORT_FILE"
    else
        log_warn "Keepalive timeout not configured"
        echo "⚠ Keepalive timeout not configured" >> "$REPORT_FILE"
    fi
    
    log_test "Proxy cache configuration"
    if grep -q "proxy_cache_path" "$NGINX_MAIN_CONF"; then
        log_pass "Proxy cache is configured"
        echo "✓ Proxy cache is configured" >> "$REPORT_FILE"
    else
        log_info "Proxy cache is not configured (may not be needed)"
        echo "ℹ Proxy cache is not configured" >> "$REPORT_FILE"
    fi
}

# 6. Health Check Endpoints Test
test_health_endpoints() {
    echo -e "\n${PURPLE}=== Testing Health Check Endpoints ===${NC}"
    
    log_test "Main health check endpoint"
    if grep -r "/nginx-health\|/health" "$NGINX_CONF_DIR" > /dev/null 2>&1; then
        log_pass "Health check endpoints are configured"
        echo "✓ Health check endpoints are configured" >> "$REPORT_FILE"
        
        # List all health endpoints
        health_endpoints=$(grep -r "location.*health" "$NGINX_CONF_DIR" 2>/dev/null | cut -d: -f2- | grep -o '/[^ ]*')
        for endpoint in $health_endpoints; do
            log_info "  - Health endpoint: $endpoint"
            echo "  - Health endpoint: $endpoint" >> "$REPORT_FILE"
        done
    else
        log_fail "No health check endpoints found"
        echo "✗ No health check endpoints found" >> "$REPORT_FILE"
    fi
    
    log_test "Monitoring endpoint (stub_status)"
    if grep -r "stub_status" "$NGINX_CONF_DIR" > /dev/null 2>&1; then
        log_pass "Nginx status monitoring is configured"
        echo "✓ Nginx status monitoring is configured" >> "$REPORT_FILE"
    else
        log_warn "Nginx status monitoring is not configured"
        echo "⚠ Nginx status monitoring is not configured" >> "$REPORT_FILE"
    fi
}

# 7. Upstream Configuration Tests
test_upstream_config() {
    echo -e "\n${PURPLE}=== Testing Upstream Configuration ===${NC}"
    
    upstreams=$(grep -c "upstream " "$NGINX_MAIN_CONF" 2>/dev/null || echo 0)
    if [ "$upstreams" -gt 0 ]; then
        log_pass "Upstream blocks configured: $upstreams"
        echo "✓ Upstream blocks configured: $upstreams" >> "$REPORT_FILE"
        
        # Test each upstream
        grep "upstream " "$NGINX_MAIN_CONF" | awk '{print $2}' | while read -r upstream_name; do
            log_test "Upstream: $upstream_name"
            
            # Check for keepalive
            if grep -A 10 "upstream $upstream_name" "$NGINX_MAIN_CONF" | grep -q "keepalive"; then
                log_info "  - Keepalive is configured for $upstream_name"
                echo "  - Keepalive is configured for $upstream_name" >> "$REPORT_FILE"
            fi
            
            # Check for load balancing method
            if grep -A 10 "upstream $upstream_name" "$NGINX_MAIN_CONF" | grep -q "least_conn\|ip_hash\|fair"; then
                log_info "  - Load balancing method configured for $upstream_name"
                echo "  - Load balancing method configured for $upstream_name" >> "$REPORT_FILE"
            fi
        done
    else
        log_warn "No upstream blocks configured"
        echo "⚠ No upstream blocks configured" >> "$REPORT_FILE"
    fi
}

# 8. Logging Configuration Tests
test_logging_config() {
    echo -e "\n${PURPLE}=== Testing Logging Configuration ===${NC}"
    
    log_test "Access log configuration"
    if grep -q "access_log" "$NGINX_MAIN_CONF"; then
        log_pass "Access logging is configured"
        echo "✓ Access logging is configured" >> "$REPORT_FILE"
        
        # Check for custom log format
        if grep -q "log_format" "$NGINX_MAIN_CONF"; then
            formats=$(grep -c "log_format" "$NGINX_MAIN_CONF")
            log_info "  - Custom log formats defined: $formats"
            echo "  - Custom log formats defined: $formats" >> "$REPORT_FILE"
        fi
    else
        log_fail "Access logging is not configured"
        echo "✗ Access logging is not configured" >> "$REPORT_FILE"
    fi
    
    log_test "Error log configuration"
    if grep -q "error_log" "$NGINX_MAIN_CONF"; then
        log_pass "Error logging is configured"
        echo "✓ Error logging is configured" >> "$REPORT_FILE"
    else
        log_fail "Error logging is not configured"
        echo "✗ Error logging is not configured" >> "$REPORT_FILE"
    fi
    
    log_test "Log buffering"
    if grep -q "access_log.*buffer=" "$NGINX_MAIN_CONF"; then
        log_pass "Log buffering is configured (performance optimization)"
        echo "✓ Log buffering is configured" >> "$REPORT_FILE"
    else
        log_info "Log buffering is not configured"
        echo "ℹ Log buffering is not configured" >> "$REPORT_FILE"
    fi
}

# Main execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Station2290 Nginx Configuration Validation Suite    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Initialize report
    init_report
    
    # Run all tests
    test_nginx_syntax
    test_ssl_configuration
    test_security_headers
    test_rate_limiting
    test_performance_config
    test_health_endpoints
    test_upstream_config
    test_logging_config
    
    # Summary
    echo -e "\n${PURPLE}=== Validation Summary ===${NC}"
    echo -e "Total Tests: ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo -e "${YELLOW}Warnings: ${WARNINGS}${NC}"
    
    # Add summary to report
    echo -e "\n## Validation Summary" >> "$REPORT_FILE"
    echo "- Total Tests: ${TOTAL_TESTS}" >> "$REPORT_FILE"
    echo "- Passed: ${PASSED_TESTS}" >> "$REPORT_FILE"
    echo "- Failed: ${FAILED_TESTS}" >> "$REPORT_FILE"
    echo "- Warnings: ${WARNINGS}" >> "$REPORT_FILE"
    
    # Finalize report
    finalize_report
    
    echo -e "\n${CYAN}Full report saved to: ${REPORT_FILE}${NC}"
    
    # Exit with appropriate code
    if [ "$FAILED_TESTS" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"