#!/bin/bash
# Continuous Health Monitoring Script
# This script continuously monitors all services and sends alerts on failures

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"  # seconds
ALERT_THRESHOLD="${ALERT_THRESHOLD:-3}"  # consecutive failures before alert
LOG_DIR="/Users/hrustalq/Projects/station-2290/infrastructure/tests/logs"
MONITORING_LOG="$LOG_DIR/monitoring-$(date +%Y%m%d).log"
FAILURE_COUNTS_FILE="$LOG_DIR/failure-counts"

# Create directories
mkdir -p "$LOG_DIR"

# Initialize failure counts
if [ ! -f "$FAILURE_COUNTS_FILE" ]; then
    touch "$FAILURE_COUNTS_FILE"
fi

# Function to log with timestamp
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp [$level] $message" | tee -a "$MONITORING_LOG"
}

# Function to get failure count for a service
get_failure_count() {
    local service="$1"
    grep "^$service:" "$FAILURE_COUNTS_FILE" 2>/dev/null | cut -d: -f2 || echo "0"
}

# Function to set failure count for a service
set_failure_count() {
    local service="$1"
    local count="$2"
    
    # Remove existing entry
    grep -v "^$service:" "$FAILURE_COUNTS_FILE" > "$FAILURE_COUNTS_FILE.tmp" 2>/dev/null || true
    
    # Add new entry
    echo "$service:$count" >> "$FAILURE_COUNTS_FILE.tmp"
    
    # Replace file
    mv "$FAILURE_COUNTS_FILE.tmp" "$FAILURE_COUNTS_FILE"
}

# Function to send alert (can be extended for email, Slack, etc.)
send_alert() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    local alert_message="ALERT: $service is $status - $message"
    log_message "ALERT" "$alert_message"
    
    # Write to alert file
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $alert_message" >> "$LOG_DIR/alerts.log"
    
    # Here you can add integration with external alerting systems
    # Examples:
    # curl -X POST -H 'Content-type: application/json' --data '{"text":"'$alert_message'"}' YOUR_SLACK_WEBHOOK
    # echo "$alert_message" | mail -s "Station2290 Alert" admin@station2290.ru
}

# Function to check a service health
check_service_health() {
    local service_name="$1"
    local check_command="$2"
    
    if eval "$check_command" > /dev/null 2>&1; then
        # Service is healthy
        local current_failures=$(get_failure_count "$service_name")
        if [ "$current_failures" -gt 0 ]; then
            log_message "INFO" "$service_name recovered from failures"
            send_alert "$service_name" "RECOVERED" "Service is now healthy after $current_failures failures"
        fi
        set_failure_count "$service_name" "0"
        return 0
    else
        # Service is unhealthy
        local current_failures=$(get_failure_count "$service_name")
        local new_failures=$((current_failures + 1))
        set_failure_count "$service_name" "$new_failures"
        
        log_message "WARNING" "$service_name health check failed ($new_failures consecutive failures)"
        
        if [ "$new_failures" -ge "$ALERT_THRESHOLD" ]; then
            send_alert "$service_name" "DOWN" "Service has failed health checks $new_failures times"
        fi
        return 1
    fi
}

# Define health checks for each service
declare -A HEALTH_CHECKS=(
    ["PostgreSQL"]="docker exec station2290_postgres pg_isready -U station2290_user -d station2290"
    ["Redis"]="docker exec station2290_redis redis-cli ping | grep -q PONG"
    ["API"]="curl -s -f http://localhost:3000/health | jq -e '.status == \"ok\"'"
    ["Bot"]="curl -s -f http://localhost:3001/health"
    ["Web"]="curl -s -f http://localhost:3000/api/health"
    ["Nginx"]="curl -s -f http://localhost:80/health || docker exec station2290_nginx nginx -t"
    ["Prometheus"]="curl -s -f http://localhost:9090/-/healthy"
    ["Grafana"]="curl -s -f http://localhost:3001/api/health"
)

# Function to check Docker container status
check_container_status() {
    local container_name="$1"
    
    if docker ps --format "{{.Names}}" | grep -q "^$container_name$"; then
        # Check if container is healthy (if health check is configured)
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no_healthcheck")
        
        case "$health_status" in
            "healthy"|"no_healthcheck")
                set_failure_count "Container-$container_name" "0"
                return 0
                ;;
            "unhealthy"|"starting")
                local current_failures=$(get_failure_count "Container-$container_name")
                local new_failures=$((current_failures + 1))
                set_failure_count "Container-$container_name" "$new_failures"
                
                log_message "WARNING" "Container $container_name is $health_status ($new_failures consecutive failures)"
                
                if [ "$new_failures" -ge "$ALERT_THRESHOLD" ]; then
                    send_alert "Container-$container_name" "UNHEALTHY" "Container health status: $health_status"
                fi
                return 1
                ;;
        esac
    else
        local current_failures=$(get_failure_count "Container-$container_name")
        local new_failures=$((current_failures + 1))
        set_failure_count "Container-$container_name" "$new_failures"
        
        log_message "ERROR" "Container $container_name is not running ($new_failures consecutive failures)"
        
        if [ "$new_failures" -ge "$ALERT_THRESHOLD" ]; then
            send_alert "Container-$container_name" "STOPPED" "Container is not running"
        fi
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    local threshold="${DISK_SPACE_THRESHOLD:-85}"  # Alert if disk usage > 85%
    
    local disk_usage=$(df /opt/station2290 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    
    if [ "$disk_usage" -gt "$threshold" ]; then
        local current_failures=$(get_failure_count "DiskSpace")
        local new_failures=$((current_failures + 1))
        set_failure_count "DiskSpace" "$new_failures"
        
        log_message "WARNING" "Disk space usage is ${disk_usage}% (threshold: ${threshold}%)"
        
        if [ "$new_failures" -ge "$ALERT_THRESHOLD" ]; then
            send_alert "DiskSpace" "HIGH" "Disk usage is ${disk_usage}%, threshold is ${threshold}%"
        fi
        return 1
    else
        set_failure_count "DiskSpace" "0"
        return 0
    fi
}

# Function to perform one monitoring cycle
perform_monitoring_cycle() {
    log_message "INFO" "Starting monitoring cycle"
    
    local total_checks=0
    local failed_checks=0
    
    # Check service health endpoints
    for service in "${!HEALTH_CHECKS[@]}"; do
        ((total_checks++))
        if ! check_service_health "$service" "${HEALTH_CHECKS[$service]}"; then
            ((failed_checks++))
        fi
    done
    
    # Check container status
    local containers=("station2290_postgres" "station2290_redis" "station2290_api" "station2290_bot" "station2290_web" "station2290_nginx")
    for container in "${containers[@]}"; do
        ((total_checks++))
        if ! check_container_status "$container"; then
            ((failed_checks++))
        fi
    done
    
    # Check disk space
    ((total_checks++))
    if ! check_disk_space; then
        ((failed_checks++))
    fi
    
    local success_rate=$(( (total_checks - failed_checks) * 100 / total_checks ))
    log_message "INFO" "Monitoring cycle completed: ${success_rate}% success rate ($((total_checks - failed_checks))/$total_checks checks passed)"
    
    return $failed_checks
}

# Function to cleanup old logs
cleanup_old_logs() {
    # Keep logs for 30 days
    find "$LOG_DIR" -name "monitoring-*.log" -mtime +30 -delete 2>/dev/null || true
    find "$LOG_DIR" -name "test-results-*.log" -mtime +30 -delete 2>/dev/null || true
}

# Signal handlers
cleanup() {
    log_message "INFO" "Monitoring script shutting down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main monitoring loop
main() {
    log_message "INFO" "Starting continuous health monitoring (interval: ${CHECK_INTERVAL}s, alert threshold: ${ALERT_THRESHOLD})"
    
    while true; do
        perform_monitoring_cycle
        
        # Cleanup old logs once per day (when hour is 0 and minute is 0)
        if [ "$(date +%H:%M)" = "00:00" ]; then
            cleanup_old_logs
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# If script is run directly, start monitoring
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi