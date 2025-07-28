#!/bin/bash
# Test Environment Variables Configuration

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Testing environment variables configuration..."

# Required environment variables for production
REQUIRED_VARS=(
    "POSTGRES_PASSWORD"
    "JWT_SECRET"
    "JWT_REFRESH_SECRET"
    "GRAFANA_ADMIN_PASSWORD"
)

# Optional but recommended variables
OPTIONAL_VARS=(
    "POSTGRES_DB"
    "POSTGRES_USER"
    "CORS_ORIGIN"
    "SSL_DOMAINS"
    "SSL_EMAIL"
    "WHATSAPP_ACCESS_TOKEN"
    "OPENAI_API_KEY"
)

# Security-sensitive variables that should not have default values
SECURITY_CRITICAL_VARS=(
    "POSTGRES_PASSWORD"
    "JWT_SECRET"
    "JWT_REFRESH_SECRET"
    "GRAFANA_ADMIN_PASSWORD"
    "NEXTAUTH_SECRET"
)

echo "Checking required environment variables..."

for var in "${REQUIRED_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo -e "${GREEN}✓ $var is set${NC}"
        
        # Check if it's a security-critical variable with weak value
        if [[ " ${SECURITY_CRITICAL_VARS[*]} " =~ " $var " ]]; then
            value="${!var}"
            if [ ${#value} -lt 12 ]; then
                echo -e "${YELLOW}  ⚠ Warning: $var is shorter than 12 characters${NC}"
            elif [[ "$value" =~ ^(password|secret|123|test|admin)$ ]]; then
                echo -e "${RED}  ✗ Warning: $var appears to use a weak/default value${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ $var is not set${NC}"
        exit 1
    fi
done

echo "\nChecking optional environment variables..."

for var in "${OPTIONAL_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo -e "${GREEN}✓ $var is set: ${!var}${NC}"
    else
        echo -e "${YELLOW}⚠ $var is not set (using default)${NC}"
    fi
done

# Check for common environment file locations
echo "\nChecking for environment files..."

ENV_FILES=(
    ".env"
    ".env.production"
    "docker/.env"
    "infrastructure/.env"
    "infrastructure/docker/production/.env"
)

for env_file in "${ENV_FILES[@]}"; do
    if [ -f "$env_file" ]; then
        echo -e "${GREEN}✓ Environment file found: $env_file${NC}"
        
        # Check for sensitive data in environment files (they should not be committed)
        if [ -d ".git" ] && git ls-files --error-unmatch "$env_file" >/dev/null 2>&1; then
            echo -e "${RED}  ✗ WARNING: $env_file is tracked by git (security risk!)${NC}"
        fi
        
        # Check for empty values in env file
        if grep -q "^[A-Z_]*=$" "$env_file" 2>/dev/null; then
            echo -e "${YELLOW}  ⚠ Warning: $env_file contains empty values${NC}"
            grep "^[A-Z_]*=$" "$env_file" | head -3
        fi
    else
        echo -e "${YELLOW}⚠ Environment file not found: $env_file${NC}"
    fi
done

# Validate specific variable formats
echo "\nValidating variable formats..."

# Check JWT_EXPIRES_IN format
if [ -n "${JWT_EXPIRES_IN:-}" ]; then
    if [[ "$JWT_EXPIRES_IN" =~ ^[0-9]+[smhd]$ ]]; then
        echo -e "${GREEN}✓ JWT_EXPIRES_IN format is valid: $JWT_EXPIRES_IN${NC}"
    else
        echo -e "${YELLOW}⚠ JWT_EXPIRES_IN format may be invalid: $JWT_EXPIRES_IN${NC}"
    fi
fi

# Check email format
if [ -n "${SSL_EMAIL:-}" ]; then
    if [[ "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${GREEN}✓ SSL_EMAIL format is valid: $SSL_EMAIL${NC}"
    else
        echo -e "${YELLOW}⚠ SSL_EMAIL format may be invalid: $SSL_EMAIL${NC}"
    fi
fi

# Check CORS_ORIGIN format
if [ -n "${CORS_ORIGIN:-}" ]; then
    if [[ "$CORS_ORIGIN" =~ ^https?:// ]]; then
        echo -e "${GREEN}✓ CORS_ORIGIN format is valid: $CORS_ORIGIN${NC}"
    else
        echo -e "${YELLOW}⚠ CORS_ORIGIN should start with http:// or https://: $CORS_ORIGIN${NC}"
    fi
fi

# Check numeric variables
NUMERIC_VARS=("API_RATE_LIMIT" "BOT_RATE_LIMIT")

for var in "${NUMERIC_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        if [[ "${!var}" =~ ^[0-9]+$ ]]; then
            echo -e "${GREEN}✓ $var is a valid number: ${!var}${NC}"
        else
            echo -e "${YELLOW}⚠ $var should be a number: ${!var}${NC}"
        fi
    fi
done

# Check for potential Docker Compose variable substitution issues
echo "\nChecking Docker Compose variable handling..."

if [ -f "infrastructure/docker/production/docker-compose.yml" ]; then
    # Check for variables used in docker-compose that aren't set
    COMPOSE_VARS=$(grep -o '\${[^}]*}' infrastructure/docker/production/docker-compose.yml | sed 's/\${//;s/}//' | sort -u)
    
    for compose_var in $COMPOSE_VARS; do
        # Extract variable name (remove default value part)
        var_name=$(echo "$compose_var" | cut -d: -f1)
        
        if [ -n "${!var_name:-}" ]; then
            echo -e "${GREEN}✓ Docker Compose variable $var_name is set${NC}"
        else
            # Check if it has a default value in docker-compose
            if echo "$compose_var" | grep -q ":"; then
                default_val=$(echo "$compose_var" | cut -d: -f2-)
                echo -e "${YELLOW}⚠ $var_name not set, will use default: $default_val${NC}"
            else
                echo -e "${RED}✗ $var_name is required by Docker Compose but not set${NC}"
            fi
        fi
    done
fi

echo -e "${GREEN}\n✓ Environment variables validation completed${NC}"
exit 0