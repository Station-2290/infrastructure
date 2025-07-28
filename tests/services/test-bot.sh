#!/bin/bash
# Test Bot Service

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
BOT_HOST="${BOT_HOST:-localhost}"
BOT_PORT="${BOT_PORT:-3001}"
BOT_CONTAINER="station2290_bot"
BOT_BASE_URL="http://$BOT_HOST:$BOT_PORT"

echo "Testing Bot service..."

# Check if Bot container is running
if docker ps --format "table {{.Names}}" | grep -q "$BOT_CONTAINER"; then
    echo -e "${GREEN}✓ Bot container is running${NC}"
else
    echo -e "${RED}✗ Bot container is not running${NC}"
    echo "Checking container status..."
    docker ps -a --filter "name=$BOT_CONTAINER" --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

# Wait for Bot to be ready
echo "Waiting for Bot service to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s -o /dev/null -w "%{http_code}" "$BOT_BASE_URL/health" | grep -q "200"; then
        echo -e "${GREEN}✓ Bot service is ready${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for Bot service... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗ Bot service failed to become ready${NC}"
    docker logs --tail 100 "$BOT_CONTAINER"
    exit 1
fi

# Test health endpoint
echo "Testing Bot health endpoint..."
HEALTH_RESPONSE=$(curl -s "$BOT_BASE_URL/health")
if echo "$HEALTH_RESPONSE" | jq -e '.status == "ok"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health endpoint returns OK status${NC}"
else
    echo -e "${RED}✗ Health endpoint failed${NC}"
    echo "Response: $HEALTH_RESPONSE"
    exit 1
fi

# Test WhatsApp webhook endpoint
echo "Testing WhatsApp webhook endpoint..."
WEBHOOK_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$BOT_BASE_URL/webhook")
if [ "$WEBHOOK_RESPONSE" = "200" ] || [ "$WEBHOOK_RESPONSE" = "405" ]; then
    echo -e "${GREEN}✓ WhatsApp webhook endpoint is accessible${NC}"
else
    echo -e "${YELLOW}⚠ WhatsApp webhook endpoint returned: $WEBHOOK_RESPONSE${NC}"
fi

# Test API connectivity from Bot
echo "Testing API connectivity from Bot..."
API_CHECK=$(docker exec "$BOT_CONTAINER" sh -c 'curl -s -f http://api:3000/health > /dev/null && echo "success"' || echo "failed")
if [ "$API_CHECK" = "success" ]; then
    echo -e "${GREEN}✓ Bot can connect to API service${NC}"
else
    echo -e "${RED}✗ Bot cannot connect to API service${NC}"
    exit 1
fi

# Check Bot configuration
echo "Checking Bot configuration..."

# Check if required environment variables are set in container
REQUIRED_BOT_VARS=("WHATSAPP_BUSINESS_API_URL" "WHATSAPP_PHONE_NUMBER_ID" "API_URL")

for var in "${REQUIRED_BOT_VARS[@]}"; do
    if docker exec "$BOT_CONTAINER" sh -c "test -n \"\${$var:-}\"" 2>/dev/null; then
        echo -e "${GREEN}✓ $var is configured in Bot container${NC}"
    else
        echo -e "${YELLOW}⚠ $var may not be configured in Bot container${NC}"
    fi
done

# Check session directory
echo "Checking Bot session directory..."
if docker exec "$BOT_CONTAINER" test -d "/app/sessions" 2>/dev/null; then
    echo -e "${GREEN}✓ Bot sessions directory is mounted${NC}"
    
    # Check if sessions directory is writable
    if docker exec "$BOT_CONTAINER" test -w "/app/sessions" 2>/dev/null; then
        echo -e "${GREEN}✓ Bot sessions directory is writable${NC}"
    else
        echo -e "${YELLOW}⚠ Bot sessions directory is not writable${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Bot sessions directory not found${NC}"
fi

# Check OpenAI API configuration (if TTS is enabled)
echo "Checking AI/TTS configuration..."
if docker exec "$BOT_CONTAINER" sh -c 'test -n "${OPENAI_API_KEY:-}"' 2>/dev/null; then
    echo -e "${GREEN}✓ OpenAI API key is configured${NC}"
    
    # Check TTS settings
    TTS_ENABLED=$(docker exec "$BOT_CONTAINER" sh -c 'echo ${TTS_ENABLED:-false}' 2>/dev/null || echo "false")
    echo "TTS enabled: $TTS_ENABLED"
    
    if [ "$TTS_ENABLED" = "true" ]; then
        TTS_MODEL=$(docker exec "$BOT_CONTAINER" sh -c 'echo ${TTS_MODEL_ID:-not_set}' 2>/dev/null || echo "not_set")
        echo "TTS model: $TTS_MODEL"
    fi
else
    echo -e "${YELLOW}⚠ OpenAI API key is not configured${NC}"
fi

# Check Bot logs for errors
echo "Checking Bot logs for recent errors..."
ERROR_COUNT=$(docker logs --tail 1000 "$BOT_CONTAINER" 2>&1 | grep -i "error" | grep -v "DeprecationWarning" | wc -l || echo "0")
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ No errors found in recent logs${NC}"
else
    echo -e "${YELLOW}⚠ Found $ERROR_COUNT error entries in recent logs${NC}"
    echo "Recent errors (excluding deprecation warnings):"
    docker logs --tail 1000 "$BOT_CONTAINER" 2>&1 | grep -i "error" | grep -v "DeprecationWarning" | tail -5
fi

# Check WhatsApp webhook verification
echo "Testing WhatsApp webhook verification..."
if [ -n "${WHATSAPP_WEBHOOK_VERIFY_TOKEN:-}" ]; then
    VERIFY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        "$BOT_BASE_URL/webhook?hub.mode=subscribe&hub.challenge=test&hub.verify_token=$WHATSAPP_WEBHOOK_VERIFY_TOKEN")
    
    if [ "$VERIFY_RESPONSE" = "200" ]; then
        echo -e "${GREEN}✓ WhatsApp webhook verification works${NC}"
    else
        echo -e "${YELLOW}⚠ WhatsApp webhook verification returned: $VERIFY_RESPONSE${NC}"
    fi
else
    echo -e "${YELLOW}⚠ WHATSAPP_WEBHOOK_VERIFY_TOKEN not set, skipping verification test${NC}"
fi

# Test rate limiting
echo "Testing Bot rate limiting..."
RATE_LIMIT_HEADER=$(curl -s -I "$BOT_BASE_URL/health" | grep -i "x-ratelimit-limit" || echo "")
if [ -n "$RATE_LIMIT_HEADER" ]; then
    echo -e "${GREEN}✓ Rate limiting is enabled${NC}"
    echo "Rate limit header: $RATE_LIMIT_HEADER"
else
    echo -e "${YELLOW}⚠ Rate limiting headers not found${NC}"
fi

# Check memory usage
echo "Checking Bot container resource usage..."
BOT_STATS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$BOT_CONTAINER" 2>/dev/null || echo "")
if [ -n "$BOT_STATS" ]; then
    echo "Resource usage:"
    echo "$BOT_STATS"
fi

# Check if Bot is processing messages (look for webhook activity in logs)
echo "Checking recent Bot activity..."
RECENT_ACTIVITY=$(docker logs --tail 100 "$BOT_CONTAINER" 2>&1 | grep -c "webhook\|message\|WhatsApp" || echo "0")
if [ "$RECENT_ACTIVITY" -gt 0 ]; then
    echo -e "${GREEN}✓ Bot shows recent activity ($RECENT_ACTIVITY log entries)${NC}"
else
    echo -e "${YELLOW}⚠ No recent Bot activity detected${NC}"
fi

echo -e "${GREEN}✓ Bot service validation completed${NC}"
exit 0