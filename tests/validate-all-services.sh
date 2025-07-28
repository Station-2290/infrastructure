#!/bin/bash
# Station 2290 - Comprehensive Service Validation Script
# This script validates all service configurations, dependencies, and health

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_DIR="/Users/hrustalq/Projects/station-2290/infrastructure/tests/logs"
TEST_RESULTS="$LOG_DIR/test-results-$(date +%Y%m%d-%H%M%S).log"

# Create log directory
mkdir -p "$LOG_DIR"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$TEST_RESULTS"
}

# Function to check command existence
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR" "${RED}Command '$1' not found. Please install it.${NC}"
        return 1
    fi
    return 0
}

# Function to validate a service
validate_service() {
    local service_name=$1
    local test_script=$2
    
    log "INFO" "${BLUE}Validating ${service_name}...${NC}"
    
    if [ -f "$test_script" ]; then
        if bash "$test_script"; then
            log "SUCCESS" "${GREEN}✓ ${service_name} validation passed${NC}"
            return 0
        else
            log "ERROR" "${RED}✗ ${service_name} validation failed${NC}"
            return 1
        fi
    else
        log "WARNING" "${YELLOW}Test script not found: $test_script${NC}"
        return 1
    fi
}

# Main validation function
main() {
    log "INFO" "${BLUE}Starting Station 2290 Service Validation${NC}"
    log "INFO" "Test results will be saved to: $TEST_RESULTS"
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "curl" "jq" "nc" "psql" "redis-cli")
    log "INFO" "Checking required commands..."
    
    for cmd in "${required_commands[@]}"; do
        if check_command "$cmd"; then
            log "SUCCESS" "${GREEN}✓ $cmd is available${NC}"
        else
            log "ERROR" "${RED}✗ $cmd is missing${NC}"
        fi
    done
    
    # Test configuration validation
    log "INFO" "\n${BLUE}=== Configuration Validation ===${NC}"
    validate_service "Docker Compose Config" "./services/test-docker-compose.sh"
    validate_service "Nginx Config" "./configs/test-nginx-config.sh"
    validate_service "Environment Variables" "./configs/test-env-vars.sh"
    
    # Test service startup sequence
    log "INFO" "\n${BLUE}=== Service Startup Validation ===${NC}"
    validate_service "PostgreSQL" "./services/test-postgres.sh"
    validate_service "Redis" "./services/test-redis.sh"
    validate_service "API Service" "./services/test-api.sh"
    validate_service "Bot Service" "./services/test-bot.sh"
    validate_service "Web Service" "./services/test-web.sh"
    validate_service "Admin Panel" "./services/test-adminka.sh"
    validate_service "Order Panel" "./services/test-order-panel.sh"
    validate_service "Nginx" "./services/test-nginx.sh"
    
    # Test monitoring services
    log "INFO" "\n${BLUE}=== Monitoring Services Validation ===${NC}"
    validate_service "Prometheus" "./monitoring/test-prometheus.sh"
    validate_service "Grafana" "./monitoring/test-grafana.sh"
    validate_service "Loki" "./monitoring/test-loki.sh"
    
    # Test health endpoints
    log "INFO" "\n${BLUE}=== Health Endpoint Validation ===${NC}"
    validate_service "Health Checks" "./health/test-all-health-endpoints.sh"
    
    # Test log rotation and permissions
    log "INFO" "\n${BLUE}=== System Configuration Validation ===${NC}"
    validate_service "Log Rotation" "./configs/test-log-rotation.sh"
    validate_service "File Permissions" "./configs/test-permissions.sh"
    validate_service "SSL Certificates" "./configs/test-ssl.sh"
    
    # Summary
    log "INFO" "\n${BLUE}=== Validation Summary ===${NC}"
    local passed=$(grep -c "SUCCESS" "$TEST_RESULTS" || true)
    local failed=$(grep -c "ERROR" "$TEST_RESULTS" || true)
    local warnings=$(grep -c "WARNING" "$TEST_RESULTS" || true)
    
    log "INFO" "${GREEN}Passed: $passed${NC}"
    log "INFO" "${RED}Failed: $failed${NC}"
    log "INFO" "${YELLOW}Warnings: $warnings${NC}"
    
    if [ "$failed" -eq 0 ]; then
        log "SUCCESS" "${GREEN}\n✓ All validations passed successfully!${NC}"
        return 0
    else
        log "ERROR" "${RED}\n✗ Some validations failed. Please check the logs.${NC}"
        return 1
    fi
}

# Run main function
main "$@"