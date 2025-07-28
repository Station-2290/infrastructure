#!/bin/bash
# Test Log Rotation Configuration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
LOG_DIR="/opt/station2290/logs"
CONTAINERS=("station2290_postgres" "station2290_redis" "station2290_api" "station2290_bot" "station2290_web" "station2290_nginx")

echo "Testing log rotation and log management configuration..."

# Check log directories
echo "${BLUE}=== Checking log directories ===${NC}"
LOG_SUBDIRS=("nginx" "postgres" "api" "bot" "web" "monitoring")

for subdir in "${LOG_SUBDIRS[@]}"; do
    LOG_PATH="$LOG_DIR/$subdir"
    if [ -d "$LOG_PATH" ]; then
        echo -e "${GREEN}✓ Log directory exists: $LOG_PATH${NC}"
        
        # Check directory permissions
        PERMS=$(stat -c "%a" "$LOG_PATH" 2>/dev/null || echo "unknown")
        if [ "$PERMS" = "755" ] || [ "$PERMS" = "775" ]; then
            echo -e "${GREEN}  ✓ Permissions OK: $PERMS${NC}"
        else
            echo -e "${YELLOW}  ⚠ Permissions: $PERMS (may need adjustment)${NC}"
        fi
        
        # Check disk usage
        USAGE=$(du -sh "$LOG_PATH" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  Size: $USAGE"
        
        # Count log files
        LOG_COUNT=$(find "$LOG_PATH" -name "*.log" -o -name "*.log.*" 2>/dev/null | wc -l || echo "0")
        echo "  Log files: $LOG_COUNT"
    else
        echo -e "${YELLOW}⚠ Log directory missing: $LOG_PATH${NC}"
    fi
done

# Check Docker container logging configuration
echo "\n${BLUE}=== Checking Docker container logging ===${NC}"
for container in "${CONTAINERS[@]}"; do
    echo "Checking logging for $container..."
    
    if docker ps --format "table {{.Names}}" | grep -q "$container"; then
        # Get logging driver
        LOG_DRIVER=$(docker inspect "$container" --format='{{.HostConfig.LogConfig.Type}}' 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ Log driver: $LOG_DRIVER${NC}"
        
        # Get log options
        MAX_SIZE=$(docker inspect "$container" --format='{{index .HostConfig.LogConfig.Config "max-size"}}' 2>/dev/null || echo "not_set")
        MAX_FILE=$(docker inspect "$container" --format='{{index .HostConfig.LogConfig.Config "max-file"}}' 2>/dev/null || echo "not_set")
        
        if [ "$MAX_SIZE" != "not_set" ] && [ "$MAX_SIZE" != "<no value>" ]; then
            echo -e "${GREEN}  ✓ Max log size: $MAX_SIZE${NC}"
        else
            echo -e "${YELLOW}  ⚠ Max log size not configured${NC}"
        fi
        
        if [ "$MAX_FILE" != "not_set" ] && [ "$MAX_FILE" != "<no value>" ]; then
            echo -e "${GREEN}  ✓ Max log files: $MAX_FILE${NC}"
        else
            echo -e "${YELLOW}  ⚠ Max log files not configured${NC}"
        fi
        
        # Check actual log file size
        LOG_PATH=$(docker inspect "$container" --format='{{.LogPath}}' 2>/dev/null || echo "unknown")
        if [ "$LOG_PATH" != "unknown" ] && [ -f "$LOG_PATH" ]; then
            LOG_SIZE=$(du -h "$LOG_PATH" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  Current log size: $LOG_SIZE"
            
            # Check if log is too large (> 100MB)
            LOG_SIZE_BYTES=$(stat -c%s "$LOG_PATH" 2>/dev/null || echo "0")
            if [ "$LOG_SIZE_BYTES" -gt 104857600 ]; then  # 100MB
                echo -e "${YELLOW}  ⚠ Log file is large (>100MB)${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Container not running: $container${NC}"
    fi
    echo ""
done

# Check nginx log rotation specifically
echo "${BLUE}=== Checking Nginx log rotation ===${NC}"
NGINX_LOG_DIR="$LOG_DIR/nginx"
if [ -d "$NGINX_LOG_DIR" ]; then
    # Check for access and error logs
    if [ -f "$NGINX_LOG_DIR/access.log" ]; then
        ACCESS_SIZE=$(du -h "$NGINX_LOG_DIR/access.log" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${GREEN}✓ Access log exists: $ACCESS_SIZE${NC}"
    fi
    
    if [ -f "$NGINX_LOG_DIR/error.log" ]; then
        ERROR_SIZE=$(du -h "$NGINX_LOG_DIR/error.log" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "${GREEN}✓ Error log exists: $ERROR_SIZE${NC}"
    fi
    
    # Check for rotated logs
    ROTATED_LOGS=$(find "$NGINX_LOG_DIR" -name "*.log.*" -o -name "*.gz" 2>/dev/null | wc -l || echo "0")
    if [ "$ROTATED_LOGS" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $ROTATED_LOGS rotated log files${NC}"
    else
        echo -e "${YELLOW}⚠ No rotated log files found${NC}"
    fi
fi

# Check system logrotate configuration
echo "\n${BLUE}=== Checking system logrotate ===${NC}"
if command -v logrotate &> /dev/null; then
    echo -e "${GREEN}✓ logrotate is available${NC}"
    
    # Check if custom logrotate config exists
    LOGROTATE_CONFIGS=("/etc/logrotate.d/station2290" "/etc/logrotate.d/nginx" "/etc/logrotate.d/docker")
    
    for config in "${LOGROTATE_CONFIGS[@]}"; do
        if [ -f "$config" ]; then
            echo -e "${GREEN}✓ Logrotate config found: $config${NC}"
        else
            echo -e "${YELLOW}⚠ Logrotate config not found: $config${NC}"
        fi
    done
    
    # Test logrotate configuration (dry run)
    if logrotate -d /etc/logrotate.conf > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Logrotate configuration is valid${NC}"
    else
        echo -e "${YELLOW}⚠ Logrotate configuration may have issues${NC}"
    fi
else
    echo -e "${YELLOW}⚠ logrotate not available on system${NC}"
fi

# Check application-specific log rotation
echo "\n${BLUE}=== Checking application log rotation ===${NC}"

# Check if applications handle their own log rotation
CONTAINERS_WITH_INTERNAL_ROTATION=("station2290_api" "station2290_bot")

for container in "${CONTAINERS_WITH_INTERNAL_ROTATION[@]}"; do
    if docker ps --format "table {{.Names}}" | grep -q "$container"; then
        echo "Checking internal log rotation for $container..."
        
        # Check if Winston or similar logging library is configured with rotation
        LOG_CONFIG_CHECK=$(docker exec "$container" find /app -name "*winston*" -o -name "*log*config*" 2>/dev/null | head -3 || echo "")
        if [ -n "$LOG_CONFIG_CHECK" ]; then
            echo -e "${GREEN}✓ Found logging configuration files${NC}"
            echo "$LOG_CONFIG_CHECK"
        else
            echo -e "${YELLOW}⚠ No specific logging configuration found${NC}"
        fi
    fi
done

# Check log cleanup scripts
echo "\n${BLUE}=== Checking log cleanup automation ===${NC}"
CLEANUP_SCRIPTS=(
    "../../scripts/maintenance/cleanup-logs.sh"
    "/opt/station2290/scripts/log-cleanup.sh"
    "./scripts/log-cleanup.sh"
)

for script in "${CLEANUP_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo -e "${GREEN}✓ Log cleanup script found: $script${NC}"
        
        if [ -x "$script" ]; then
            echo -e "${GREEN}  ✓ Script is executable${NC}"
        else
            echo -e "${YELLOW}  ⚠ Script is not executable${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Log cleanup script not found: $script${NC}"
    fi
done

# Check cron jobs for log rotation
echo "\n${BLUE}=== Checking automated log rotation jobs ===${NC}"
if command -v crontab &> /dev/null; then
    CRON_JOBS=$(crontab -l 2>/dev/null | grep -i "log\|rotate" || echo "")
    if [ -n "$CRON_JOBS" ]; then
        echo -e "${GREEN}✓ Found log-related cron jobs:${NC}"
        echo "$CRON_JOBS"
    else
        echo -e "${YELLOW}⚠ No log-related cron jobs found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ cron not available${NC}"
fi

# Check disk space and log growth
echo "\n${BLUE}=== Checking disk space and log growth ===${NC}"
if [ -d "$LOG_DIR" ]; then
    TOTAL_LOG_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    echo "Total log directory size: $TOTAL_LOG_SIZE"
    
    # Check available disk space
    AVAILABLE_SPACE=$(df -h "$LOG_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
    echo "Available disk space: $AVAILABLE_SPACE"
    
    # Check disk usage percentage
    DISK_USAGE=$(df "$LOG_DIR" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
    if [ "$DISK_USAGE" -gt 80 ]; then
        echo -e "${RED}✗ Disk usage is high: ${DISK_USAGE}%${NC}"
    elif [ "$DISK_USAGE" -gt 60 ]; then
        echo -e "${YELLOW}⚠ Disk usage: ${DISK_USAGE}%${NC}"
    else
        echo -e "${GREEN}✓ Disk usage: ${DISK_USAGE}%${NC}"
    fi
fi

# Find largest log files
echo "\n${BLUE}=== Largest log files ===${NC}"
if [ -d "$LOG_DIR" ]; then
    echo "Top 5 largest log files:"
    find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.*" \) -exec du -h {} + 2>/dev/null | sort -hr | head -5 || echo "No log files found"
fi

echo -e "\n${GREEN}✓ Log rotation configuration check completed${NC}"
exit 0