#!/bin/bash
# SSL/TLS Security Testing Script for Station2290
# Tests SSL/TLS configuration security and compliance

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SSL_HOST="${SSL_HOST:-station2290.ru}"
SSL_PORT="${SSL_PORT:-443}"
REPORT_FILE="ssl-security-report.md"

# Security test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Helper functions
log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    ((TOTAL_TESTS++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
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
# SSL/TLS Security Test Report
Generated: $(date)
Target: $SSL_HOST:$SSL_PORT

## Summary
- Total Tests: _TBD_
- Passed: _TBD_
- Failed: _TBD_
- Warnings: _TBD_

## Test Results

EOF
}

# Check dependencies
check_dependencies() {
    echo -e "${CYAN}Checking dependencies...${NC}"
    
    local deps=("openssl" "curl" "nmap")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
        echo "Install missing tools or some tests will be skipped"
        echo ""
    else
        echo -e "${GREEN}All dependencies satisfied${NC}"
    fi
}

# Test SSL certificate validity
test_certificate_validity() {
    echo -e "\n${PURPLE}=== Testing SSL Certificate Validity ===${NC}"
    
    log_test "Certificate validity and chain"
    cert_info=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -servername "$SSL_HOST" < /dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null)
    
    if [ -n "$cert_info" ]; then
        log_pass "SSL certificate is accessible"
        echo "✓ SSL certificate is accessible" >> "$REPORT_FILE"
        
        # Check expiration
        exp_date=$(echo "$cert_info" | grep "Not After" | cut -d: -f2- | xargs)
        if [ -n "$exp_date" ]; then
            exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$exp_date" +%s 2>/dev/null)
            current_timestamp=$(date +%s)
            days_until_exp=$(( (exp_timestamp - current_timestamp) / 86400 ))
            
            if [ "$days_until_exp" -gt 30 ]; then
                log_pass "Certificate expires in $days_until_exp days"
                echo "✓ Certificate expires in $days_until_exp days" >> "$REPORT_FILE"
            elif [ "$days_until_exp" -gt 0 ]; then
                log_warn "Certificate expires in $days_until_exp days (renewal needed soon)"
                echo "⚠ Certificate expires in $days_until_exp days" >> "$REPORT_FILE"
            else
                log_fail "Certificate has expired"
                echo "✗ Certificate has expired" >> "$REPORT_FILE"
            fi
        fi
        
        # Check subject alternative names
        san=$(echo "$cert_info" | grep -A1 "Subject Alternative Name" | tail -1 | grep -o "DNS:[^,]*" | cut -d: -f2)
        if [ -n "$san" ]; then
            log_info "SAN entries: $san"
            echo "  - SAN entries: $san" >> "$REPORT_FILE"
        fi
        
    else
        log_fail "Unable to retrieve SSL certificate"
        echo "✗ Unable to retrieve SSL certificate" >> "$REPORT_FILE"
    fi
}

# Test SSL protocol support
test_ssl_protocols() {
    echo -e "\n${PURPLE}=== Testing SSL/TLS Protocol Support ===${NC}"
    
    # Test protocols
    declare -A protocols=(
        ["SSLv2"]="INSECURE"
        ["SSLv3"]="INSECURE"
        ["TLSv1"]="WEAK"
        ["TLSv1.1"]="WEAK"
        ["TLSv1.2"]="SECURE"
        ["TLSv1.3"]="SECURE"
    )
    
    for protocol in "${!protocols[@]}"; do
        local security_level="${protocols[$protocol]}"
        log_test "$protocol support"
        
        case $protocol in
            "SSLv2"|"SSLv3")
                # These should be disabled
                if openssl s_client -connect "$SSL_HOST:$SSL_PORT" -${protocol,,} < /dev/null &>/dev/null; then
                    log_fail "$protocol is enabled (security risk)"
                    echo "✗ $protocol is enabled (security risk)" >> "$REPORT_FILE"
                else
                    log_pass "$protocol is disabled"
                    echo "✓ $protocol is disabled" >> "$REPORT_FILE"
                fi
                ;;
            "TLSv1"|"TLSv1.1")
                # These should be disabled for security
                if openssl s_client -connect "$SSL_HOST:$SSL_PORT" -${protocol,,} < /dev/null &>/dev/null; then
                    log_warn "$protocol is enabled (consider disabling)"
                    echo "⚠ $protocol is enabled (consider disabling)" >> "$REPORT_FILE"
                else
                    log_pass "$protocol is disabled"
                    echo "✓ $protocol is disabled" >> "$REPORT_FILE"
                fi
                ;;
            "TLSv1.2"|"TLSv1.3")
                # These should be enabled
                if openssl s_client -connect "$SSL_HOST:$SSL_PORT" -${protocol,,} < /dev/null &>/dev/null; then
                    log_pass "$protocol is enabled"
                    echo "✓ $protocol is enabled" >> "$REPORT_FILE"
                else
                    log_fail "$protocol is not available"
                    echo "✗ $protocol is not available" >> "$REPORT_FILE"
                fi
                ;;
        esac
    done
}

# Test cipher suites
test_cipher_suites() {
    echo -e "\n${PURPLE}=== Testing Cipher Suite Security ===${NC}"
    
    log_test "Cipher suite strength"
    
    # Get supported ciphers
    ciphers=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -cipher 'ALL:!aNULL:!eNULL' < /dev/null 2>/dev/null | grep "Cipher    :" | cut -d: -f2 | xargs)
    
    if [ -n "$ciphers" ]; then
        log_info "Negotiated cipher: $ciphers"
        echo "  - Negotiated cipher: $ciphers" >> "$REPORT_FILE"
        
        # Check for weak ciphers
        weak_patterns=("RC4" "MD5" "DES" "3DES" "NULL")
        weak_found=false
        
        for pattern in "${weak_patterns[@]}"; do
            if echo "$ciphers" | grep -iq "$pattern"; then
                log_fail "Weak cipher detected: $pattern"
                echo "✗ Weak cipher detected: $pattern" >> "$REPORT_FILE"
                weak_found=true
            fi
        done
        
        if ! $weak_found; then
            log_pass "No weak ciphers detected"
            echo "✓ No weak ciphers detected" >> "$REPORT_FILE"
        fi
        
        # Check for strong ciphers
        if echo "$ciphers" | grep -iq "ECDHE"; then
            log_pass "Perfect Forward Secrecy (PFS) is supported"
            echo "✓ Perfect Forward Secrecy (PFS) is supported" >> "$REPORT_FILE"
        else
            log_warn "Perfect Forward Secrecy (PFS) is not supported"
            echo "⚠ Perfect Forward Secrecy (PFS) is not supported" >> "$REPORT_FILE"
        fi
        
        if echo "$ciphers" | grep -iq "GCM\|CHACHA20"; then
            log_pass "Authenticated encryption is supported"
            echo "✓ Authenticated encryption is supported" >> "$REPORT_FILE"
        else
            log_warn "Authenticated encryption is not supported"
            echo "⚠ Authenticated encryption is not supported" >> "$REPORT_FILE"
        fi
    else
        log_fail "Unable to retrieve cipher information"
        echo "✗ Unable to retrieve cipher information" >> "$REPORT_FILE"
    fi
}

# Test security headers
test_security_headers() {
    echo -e "\n${PURPLE}=== Testing Security Headers ===${NC}"
    
    # Get headers
    headers=$(curl -I -s "https://$SSL_HOST" 2>/dev/null)
    
    if [ -n "$headers" ]; then
        # Test HSTS
        log_test "HTTP Strict Transport Security (HSTS)"
        if echo "$headers" | grep -iq "strict-transport-security"; then
            hsts_value=$(echo "$headers" | grep -i "strict-transport-security" | cut -d: -f2- | xargs)
            log_pass "HSTS header is present: $hsts_value"
            echo "✓ HSTS header is present: $hsts_value" >> "$REPORT_FILE"
            
            # Check HSTS duration
            if echo "$hsts_value" | grep -q "max-age="; then
                max_age=$(echo "$hsts_value" | grep -o "max-age=[0-9]*" | cut -d= -f2)
                if [ "$max_age" -ge 31536000 ]; then  # 1 year
                    log_pass "HSTS max-age is sufficient (${max_age}s)"
                    echo "  - HSTS max-age is sufficient (${max_age}s)" >> "$REPORT_FILE"
                else
                    log_warn "HSTS max-age is less than 1 year"
                    echo "  ⚠ HSTS max-age is less than 1 year" >> "$REPORT_FILE"
                fi
            fi
        else
            log_fail "HSTS header is missing"
            echo "✗ HSTS header is missing" >> "$REPORT_FILE"
        fi
        
        # Test other security headers
        declare -A security_headers=(
            ["X-Frame-Options"]="Clickjacking protection"
            ["X-Content-Type-Options"]="MIME type sniffing protection"
            ["X-XSS-Protection"]="XSS protection"
            ["Referrer-Policy"]="Referrer policy"
            ["Content-Security-Policy"]="Content Security Policy"
        )
        
        for header in "${!security_headers[@]}"; do
            local description="${security_headers[$header]}"
            log_test "$description ($header)"
            
            if echo "$headers" | grep -iq "$header"; then
                header_value=$(echo "$headers" | grep -i "$header" | cut -d: -f2- | xargs)
                log_pass "$description is configured: $header_value"
                echo "✓ $description is configured: $header_value" >> "$REPORT_FILE"
            else
                log_warn "$description is not configured"
                echo "⚠ $description is not configured" >> "$REPORT_FILE"
            fi
        done
    else
        log_fail "Unable to retrieve HTTP headers"
        echo "✗ Unable to retrieve HTTP headers" >> "$REPORT_FILE"
    fi
}

# Test OCSP stapling
test_ocsp_stapling() {
    echo -e "\n${PURPLE}=== Testing OCSP Stapling ===${NC}"
    
    log_test "OCSP stapling support"
    
    ocsp_status=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -status < /dev/null 2>&1)
    
    if echo "$ocsp_status" | grep -q "OCSP response:"; then
        if echo "$ocsp_status" | grep -q "OCSP Response Status: successful"; then
            log_pass "OCSP stapling is working correctly"
            echo "✓ OCSP stapling is working correctly" >> "$REPORT_FILE"
        else
            log_warn "OCSP stapling is configured but may have issues"
            echo "⚠ OCSP stapling is configured but may have issues" >> "$REPORT_FILE"
        fi
    else
        log_warn "OCSP stapling is not configured"
        echo "⚠ OCSP stapling is not configured" >> "$REPORT_FILE"
    fi
}

# Test certificate transparency
test_certificate_transparency() {
    echo -e "\n${PURPLE}=== Testing Certificate Transparency ===${NC}"
    
    log_test "Certificate Transparency compliance"
    
    cert_info=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -servername "$SSL_HOST" < /dev/null 2>/dev/null | openssl x509 -noout -text 2>/dev/null)
    
    if echo "$cert_info" | grep -q "CT Precertificate SCTs\|CT Certificate SCTs"; then
        sct_count=$(echo "$cert_info" | grep -c "Signed Certificate Timestamp" || echo "0")
        log_pass "Certificate Transparency SCTs present: $sct_count SCTs"
        echo "✓ Certificate Transparency SCTs present: $sct_count SCTs" >> "$REPORT_FILE"
    else
        log_warn "No Certificate Transparency SCTs found"
        echo "⚠ No Certificate Transparency SCTs found" >> "$REPORT_FILE"
    fi
}

# Test session resumption
test_session_resumption() {
    echo -e "\n${PURPLE}=== Testing Session Resumption ===${NC}"
    
    log_test "SSL session resumption"
    
    # First connection
    session_info=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -sess_out /tmp/session.pem < /dev/null 2>&1)
    
    if [ -f /tmp/session.pem ]; then
        # Second connection with session reuse
        reuse_info=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -sess_in /tmp/session.pem < /dev/null 2>&1)
        
        if echo "$reuse_info" | grep -q "Reused.*yes"; then
            log_pass "SSL session resumption is working"
            echo "✓ SSL session resumption is working" >> "$REPORT_FILE"
        else
            log_warn "SSL session resumption is not working"
            echo "⚠ SSL session resumption is not working" >> "$REPORT_FILE"
        fi
        
        rm -f /tmp/session.pem
    else
        log_warn "Unable to test session resumption"
        echo "⚠ Unable to test session resumption" >> "$REPORT_FILE"
    fi
}

# Test vulnerability checks
test_vulnerabilities() {
    echo -e "\n${PURPLE}=== Testing for Known Vulnerabilities ===${NC}"
    
    # Test for Heartbleed
    log_test "Heartbleed vulnerability (CVE-2014-0160)"
    heartbleed_test=$(openssl s_client -connect "$SSL_HOST:$SSL_PORT" -tlsextdebug 2>&1 | grep -i heartbeat || echo "not vulnerable")
    
    if echo "$heartbleed_test" | grep -iq "heartbeat"; then
        log_warn "Heartbeat extension is enabled (potential Heartbleed risk)"
        echo "⚠ Heartbeat extension is enabled" >> "$REPORT_FILE"
    else
        log_pass "Not vulnerable to Heartbleed"
        echo "✓ Not vulnerable to Heartbleed" >> "$REPORT_FILE"
    fi
    
    # Test for POODLE (SSLv3)
    log_test "POODLE vulnerability (SSLv3)"
    if openssl s_client -connect "$SSL_HOST:$SSL_PORT" -ssl3 < /dev/null &>/dev/null; then
        log_fail "SSLv3 is enabled (POODLE vulnerability)"
        echo "✗ SSLv3 is enabled (POODLE vulnerability)" >> "$REPORT_FILE"
    else
        log_pass "SSLv3 is disabled (not vulnerable to POODLE)"
        echo "✓ SSLv3 is disabled (not vulnerable to POODLE)" >> "$REPORT_FILE"
    fi
    
    # Test for BEAST (TLS 1.0)
    log_test "BEAST vulnerability (TLS 1.0)"
    if openssl s_client -connect "$SSL_HOST:$SSL_PORT" -tls1 < /dev/null &>/dev/null; then
        log_warn "TLS 1.0 is enabled (potential BEAST vulnerability)"
        echo "⚠ TLS 1.0 is enabled (potential BEAST vulnerability)" >> "$REPORT_FILE"
    else
        log_pass "TLS 1.0 is disabled (not vulnerable to BEAST)"
        echo "✓ TLS 1.0 is disabled (not vulnerable to BEAST)" >> "$REPORT_FILE"
    fi
}

# Generate security recommendations
generate_recommendations() {
    echo -e "\n${PURPLE}=== Generating Security Recommendations ===${NC}"
    
    cat >> "$REPORT_FILE" << 'EOF'

## Security Recommendations

Based on the SSL/TLS security assessment, consider implementing the following improvements:

### 1. Protocol Configuration
- Disable SSLv2, SSLv3, TLS 1.0, and TLS 1.1
- Enable only TLS 1.2 and TLS 1.3
- Set `ssl_prefer_server_ciphers off;` for TLS 1.3 compatibility

### 2. Cipher Suite Optimization
- Use only strong cipher suites with Perfect Forward Secrecy (PFS)
- Prefer ECDHE key exchange and AEAD ciphers (GCM, CHACHA20-POLY1305)
- Remove weak ciphers (RC4, DES, 3DES, MD5)

### 3. Security Headers
- Implement HSTS with `max-age` of at least 1 year
- Add `includeSubDomains` and `preload` to HSTS
- Configure Content Security Policy (CSP)
- Ensure all security headers are properly set

### 4. Certificate Management
- Use certificates from trusted Certificate Authorities
- Enable Certificate Transparency (CT) monitoring
- Set up automated certificate renewal
- Monitor certificate expiration dates

### 5. Performance Optimizations
- Enable OCSP stapling to reduce handshake time
- Configure SSL session caching
- Optimize SSL buffer sizes
- Consider HTTP/2 implementation

### 6. Monitoring and Maintenance
- Regular security scans and vulnerability assessments
- Monitor SSL/TLS configuration changes
- Keep OpenSSL and nginx updated
- Implement certificate transparency monitoring

EOF
}

# Generate security score
calculate_security_score() {
    local score=100
    
    # Deduct points for failures
    score=$((score - (FAILED_TESTS * 10)))
    
    # Deduct points for warnings (less severe)
    score=$((score - (WARNINGS * 3)))
    
    # Ensure score doesn't go below 0
    if [ $score -lt 0 ]; then
        score=0
    fi
    
    echo "### Security Score: $score/100" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ $score -ge 90 ]; then
        echo -e "${GREEN}Excellent security configuration (Score: $score/100)${NC}"
    elif [ $score -ge 75 ]; then
        echo -e "${YELLOW}Good security configuration with room for improvement (Score: $score/100)${NC}"
    elif [ $score -ge 50 ]; then
        echo -e "${YELLOW}Fair security configuration, improvements needed (Score: $score/100)${NC}"
    else
        echo -e "${RED}Poor security configuration, immediate attention required (Score: $score/100)${NC}"
    fi
}

# Finalize report
finalize_report() {
    # Update summary
    sed -i.bak "s/_TBD_/$TOTAL_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$PASSED_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$FAILED_TESTS/1" "$REPORT_FILE"
    sed -i.bak "s/_TBD_/$WARNINGS/1" "$REPORT_FILE"
    rm -f "$REPORT_FILE.bak"
}

# Main execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Station2290 SSL/TLS Security Test Suite          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Initialize report
    init_report
    
    # Run all tests
    test_certificate_validity
    test_ssl_protocols
    test_cipher_suites
    test_security_headers
    test_ocsp_stapling
    test_certificate_transparency
    test_session_resumption
    test_vulnerabilities
    
    # Generate recommendations
    generate_recommendations
    
    # Calculate security score
    calculate_security_score
    
    # Summary
    echo -e "\n${PURPLE}=== SSL/TLS Security Test Summary ===${NC}"
    echo -e "Total Tests: ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo -e "${YELLOW}Warnings: ${WARNINGS}${NC}"
    
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