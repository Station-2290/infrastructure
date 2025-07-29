#!/bin/bash

# Nginx Configuration Testing and Validation Script
# Configuration Engineer: Hive Mind Swarm
# Comprehensive nginx configuration testing and performance validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration paths
NGINX_CONF="/etc/nginx/nginx.conf"
PROJECT_DIR="/Users/hrustalq/Projects/station-2290"
TEST_DIR="/tmp/nginx_test"
RESULTS_FILE="/tmp/nginx_test_results.json"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
    ((TESTS_FAILED++))
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
    ((TESTS_WARNINGS++))
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

pass() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] PASS:${NC} $1"
    ((TESTS_PASSED++))
}

# Initialize test environment
init_test() {
    log "Initializing nginx configuration tests..."
    
    mkdir -p "$TEST_DIR"
    
    # Create test results file
    cat > "$RESULTS_FILE" << 'EOF'
{
    "test_run": {
        "timestamp": "",
        "duration": 0,
        "tests_passed": 0,
        "tests_failed": 0,
        "tests_warnings": 0
    },
    "configuration_tests": [],
    "security_tests": [],
    "performance_tests": [],
    "ssl_tests": []
}
EOF
    
    log "Test environment initialized"
}

# Test nginx configuration syntax
test_syntax() {
    log "Testing nginx configuration syntax..."
    
    if nginx -t 2>"$TEST_DIR/syntax_test.log"; then
        pass "Nginx configuration syntax is valid"
        return 0
    else
        error "Nginx configuration syntax errors found:"
        cat "$TEST_DIR/syntax_test.log" >&2
        return 1
    fi
}

# Test nginx configuration structure
test_config_structure() {
    log "Testing nginx configuration structure..."
    
    local config_file="${1:-$NGINX_CONF}"
    
    # Check if main configuration file exists
    if [[ ! -f "$config_file" ]]; then
        error "Main nginx configuration file not found: $config_file"
        return 1
    fi
    pass "Main configuration file exists"
    
    # Check for required sections
    local required_sections=("events" "http" "server")
    for section in "${required_sections[@]}"; do
        if grep -q "^[[:space:]]*${section}[[:space:]]*{" "$config_file"; then
            pass "Configuration contains required section: $section"
        else
            error "Configuration missing required section: $section"
        fi
    done
    
    # Check for security headers
    if grep -q "add_header.*X-Frame-Options" "$config_file" || \
       find /etc/nginx -name "*.conf" -exec grep -l "add_header.*X-Frame-Options" {} \; 2>/dev/null | grep -q .; then
        pass "Security headers are configured"
    else
        warning "Security headers not found in configuration"
    fi
    
    # Check for SSL configuration
    if grep -q "ssl_protocols" "$config_file" || \
       find /etc/nginx -name "*.conf" -exec grep -l "ssl_protocols" {} \; 2>/dev/null | grep -q .; then
        pass "SSL configuration is present"
    else
        warning "SSL configuration not found"
    fi
    
    # Check for rate limiting
    if grep -q "limit_req_zone" "$config_file"; then
        pass "Rate limiting is configured"
    else
        warning "Rate limiting configuration not found"
    fi
}

# Test upstream configurations
test_upstreams() {
    log "Testing upstream configurations..."
    
    local upstreams=("api_backend" "web_backend" "bot_backend" "adminka_backend" "order_panel_backend")
    
    for upstream in "${upstreams[@]}"; do
        if nginx -T 2>/dev/null | grep -q "upstream $upstream"; then
            pass "Upstream configured: $upstream"
            
            # Test upstream connectivity
            local upstream_servers=$(nginx -T 2>/dev/null | sed -n "/upstream $upstream/,/}/p" | grep "server" | awk '{print $2}' | cut -d';' -f1)
            
            while IFS= read -r server; do
                if [[ -n "$server" ]]; then
                    local host=$(echo "$server" | cut -d':' -f1)
                    local port=$(echo "$server" | cut -d':' -f2)
                    
                    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
                        pass "Upstream server reachable: $server"
                    else
                        warning "Upstream server unreachable: $server"
                    fi
                fi
            done <<< "$upstream_servers"
        else
            error "Upstream not configured: $upstream"
        fi
    done
}

# Test SSL configuration
test_ssl_config() {
    log "Testing SSL configuration..."
    
    # Check SSL protocols
    if nginx -T 2>/dev/null | grep -q "ssl_protocols.*TLSv1\.[23]"; then
        pass "Modern SSL protocols configured"
    else
        error "SSL protocols not properly configured"
    fi
    
    # Check SSL ciphers
    if nginx -T 2>/dev/null | grep -q "ssl_ciphers"; then
        pass "SSL ciphers configured"
    else
        warning "SSL ciphers not explicitly configured"
    fi
    
    # Check HSTS
    if nginx -T 2>/dev/null | grep -q "Strict-Transport-Security"; then
        pass "HSTS configured"
    else
        warning "HSTS not configured"
    fi
    
    # Check OCSP stapling
    if nginx -T 2>/dev/null | grep -q "ssl_stapling.*on"; then
        pass "OCSP stapling enabled"
    else
        warning "OCSP stapling not enabled"
    fi
    
    # Test SSL certificate files (if specified)
    local cert_files=$(nginx -T 2>/dev/null | grep "ssl_certificate " | awk '{print $2}' | sed 's/;//g' | sort -u)
    while IFS= read -r cert_file; do
        if [[ -n "$cert_file" && -f "$cert_file" ]]; then
            pass "SSL certificate file exists: $cert_file"
            
            # Check certificate validity
            if openssl x509 -in "$cert_file" -noout -dates 2>/dev/null; then
                local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
                local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                local current_epoch=$(date +%s)
                local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
                
                if [[ $days_until_expiry -gt 30 ]]; then
                    pass "SSL certificate valid for $days_until_expiry days"
                elif [[ $days_until_expiry -gt 0 ]]; then
                    warning "SSL certificate expires in $days_until_expiry days"
                else
                    error "SSL certificate has expired"
                fi
            else
                error "Invalid SSL certificate: $cert_file"
            fi
        else
            warning "SSL certificate file not found: $cert_file"
        fi
    done <<< "$cert_files"
}

# Test security configuration
test_security() {
    log "Testing security configuration..."
    
    # Check server tokens
    if nginx -T 2>/dev/null | grep -q "server_tokens.*off"; then
        pass "Server tokens are hidden"
    else
        warning "Server tokens not hidden"
    fi
    
    # Check security headers
    local security_headers=("X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection" "Referrer-Policy")
    for header in "${security_headers[@]}"; do
        if nginx -T 2>/dev/null | grep -q "add_header.*$header"; then
            pass "Security header configured: $header"
        else
            warning "Security header not configured: $header"
        fi
    done
    
    # Check Content Security Policy
    if nginx -T 2>/dev/null | grep -q "Content-Security-Policy"; then
        pass "Content Security Policy configured"
    else
        warning "Content Security Policy not configured"
    fi
    
    # Check rate limiting zones
    if nginx -T 2>/dev/null | grep -q "limit_req_zone"; then
        pass "Rate limiting zones configured"
        
        # Count rate limiting zones
        local zone_count=$(nginx -T 2>/dev/null | grep -c "limit_req_zone")
        info "Rate limiting zones found: $zone_count"
    else
        error "No rate limiting zones configured"
    fi
    
    # Check connection limiting
    if nginx -T 2>/dev/null | grep -q "limit_conn_zone"; then
        pass "Connection limiting configured"
    else
        warning "Connection limiting not configured"
    fi
}

# Test performance configuration
test_performance() {
    log "Testing performance configuration..."
    
    # Check worker processes
    local worker_processes=$(nginx -T 2>/dev/null | grep "worker_processes" | awk '{print $2}' | sed 's/;//g')
    if [[ "$worker_processes" == "auto" ]]; then
        pass "Worker processes set to auto"
    elif [[ "$worker_processes" =~ ^[0-9]+$ && $worker_processes -gt 0 ]]; then
        pass "Worker processes set to: $worker_processes"
    else
        warning "Worker processes not optimally configured"
    fi
    
    # Check worker connections
    local worker_connections=$(nginx -T 2>/dev/null | grep "worker_connections" | awk '{print $2}' | sed 's/;//g')
    if [[ "$worker_connections" =~ ^[0-9]+$ && $worker_connections -ge 1024 ]]; then
        pass "Worker connections configured: $worker_connections"
    else
        warning "Worker connections may be too low: $worker_connections"
    fi
    
    # Check gzip compression
    if nginx -T 2>/dev/null | grep -q "gzip.*on"; then
        pass "Gzip compression enabled"
    else
        warning "Gzip compression not enabled"
    fi
    
    # Check sendfile
    if nginx -T 2>/dev/null | grep -q "sendfile.*on"; then
        pass "Sendfile enabled"
    else
        warning "Sendfile not enabled"
    fi
    
    # Check keepalive
    if nginx -T 2>/dev/null | grep -q "keepalive_timeout"; then
        pass "Keepalive timeout configured"
    else
        warning "Keepalive timeout not configured"
    fi
    
    # Check proxy cache
    if nginx -T 2>/dev/null | grep -q "proxy_cache_path"; then
        pass "Proxy cache configured"
        
        # Check cache directories exist
        local cache_paths=$(nginx -T 2>/dev/null | grep "proxy_cache_path" | awk '{print $2}')
        while IFS= read -r cache_path; do
            if [[ -n "$cache_path" ]]; then
                if [[ -d "$cache_path" ]]; then
                    pass "Cache directory exists: $cache_path"
                else
                    warning "Cache directory not found: $cache_path"
                fi
            fi
        done <<< "$cache_paths"
    else
        warning "Proxy cache not configured"
    fi
}

# Test logging configuration
test_logging() {
    log "Testing logging configuration..."
    
    # Check access log configuration
    if nginx -T 2>/dev/null | grep -q "access_log"; then
        pass "Access logging configured"
    else
        warning "Access logging not configured"
    fi
    
    # Check error log configuration
    if nginx -T 2>/dev/null | grep -q "error_log"; then
        pass "Error logging configured"
    else
        warning "Error logging not configured"
    fi
    
    # Check log directory permissions
    local log_dir="/var/log/nginx"
    if [[ -d "$log_dir" ]]; then
        pass "Log directory exists: $log_dir"
        
        # Check if nginx can write to log directory
        if [[ -w "$log_dir" ]]; then
            pass "Log directory is writable"
        else
            error "Log directory is not writable: $log_dir"
        fi
    else
        error "Log directory not found: $log_dir"
    fi
}

# Test HTTP/2 configuration
test_http2() {
    log "Testing HTTP/2 configuration..."
    
    if nginx -T 2>/dev/null | grep -q "listen.*443.*http2"; then
        pass "HTTP/2 enabled for HTTPS"
    else
        warning "HTTP/2 not enabled for HTTPS"
    fi
    
    # Check nginx version for HTTP/2 support
    local nginx_version=$(nginx -v 2>&1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    if dpkg --compare-versions "$nginx_version" "ge" "1.9.5"; then
        pass "Nginx version supports HTTP/2: $nginx_version"
    else
        warning "Nginx version may not fully support HTTP/2: $nginx_version"
    fi
}

# Performance benchmark test
test_performance_benchmark() {
    log "Running performance benchmark tests..."
    
    # Check if nginx is running
    if ! pgrep nginx > /dev/null; then
        warning "Nginx is not running - skipping performance tests"
        return 0
    fi
    
    # Simple response time test
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" http://localhost/health 2>/dev/null || echo "999")
    if (( $(echo "$response_time < 1.0" | bc -l) )); then
        pass "Health endpoint response time: ${response_time}s"
    else
        warning "Health endpoint response time high: ${response_time}s"
    fi
    
    # Test gzip compression
    local gzip_test=$(curl -H "Accept-Encoding: gzip" -s -I http://localhost/ 2>/dev/null | grep -i "content-encoding: gzip" || echo "")
    if [[ -n "$gzip_test" ]]; then
        pass "Gzip compression working"
    else
        warning "Gzip compression not working"
    fi
}

# Generate test report
generate_report() {
    log "Generating test report..."
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNINGS))
    local success_rate=0
    
    if [[ $total_tests -gt 0 ]]; then
        success_rate=$(( (TESTS_PASSED * 100) / total_tests ))
    fi
    
    # Update results file
    local end_time=$(date +%s)
    local duration=$((end_time - ${TEST_START_TIME:-$end_time}))
    
    cat > "$RESULTS_FILE" << EOF
{
    "test_run": {
        "timestamp": "$(date -Iseconds)",
        "duration": $duration,
        "tests_passed": $TESTS_PASSED,
        "tests_failed": $TESTS_FAILED,
        "tests_warnings": $TESTS_WARNINGS,
        "total_tests": $total_tests,
        "success_rate": $success_rate
    },
    "summary": {
        "overall_status": "$(if [[ $TESTS_FAILED -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi)",
        "configuration_valid": $(if [[ $TESTS_FAILED -eq 0 ]]; then echo "true"; else echo "false"; fi),
        "security_score": $((100 - (TESTS_WARNINGS * 10))),
        "performance_score": $((100 - (TESTS_WARNINGS * 5)))
    }
}
EOF
    
    # Display summary
    echo
    log "=== NGINX CONFIGURATION TEST SUMMARY ==="
    echo -e "Total Tests: $total_tests"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Warnings: $TESTS_WARNINGS${NC}"
    echo -e "Success Rate: $success_rate%"
    echo -e "Duration: ${duration}s"
    echo -e "Results saved to: $RESULTS_FILE"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log "All tests passed! Configuration is ready for production."
        return 0
    else
        error "Some tests failed. Please review the configuration."
        return 1
    fi
}

# Main test execution
run_all_tests() {
    local TEST_START_TIME=$(date +%s)
    
    log "Starting comprehensive nginx configuration tests..."
    
    init_test
    
    # Run all test suites
    test_syntax
    test_config_structure
    test_upstreams
    test_ssl_config
    test_security
    test_performance
    test_logging
    test_http2
    test_performance_benchmark
    
    generate_report
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] [TEST_SUITE]"
    echo
    echo "Options:"
    echo "  --config FILE    Use specific nginx config file"
    echo "  --project DIR    Use specific project directory"
    echo "  --help          Show this help message"
    echo
    echo "Test Suites:"
    echo "  all            Run all tests (default)"
    echo "  syntax         Test configuration syntax only"
    echo "  security       Test security configuration"
    echo "  performance    Test performance configuration"
    echo "  ssl            Test SSL configuration"
    echo "  upstreams      Test upstream configurations"
    echo
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            NGINX_CONF="$2"
            shift 2
            ;;
        --project)
            PROJECT_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        syntax)
            test_syntax
            exit $?
            ;;
        security)
            init_test
            test_security
            generate_report
            exit $?
            ;;
        performance)
            init_test
            test_performance
            generate_report
            exit $?
            ;;
        ssl)
            init_test
            test_ssl_config
            generate_report
            exit $?
            ;;
        upstreams)
            init_test
            test_upstreams
            generate_report
            exit $?
            ;;
        all|*)
            run_all_tests
            exit $?
            ;;
    esac
done

# Default: run all tests
run_all_tests