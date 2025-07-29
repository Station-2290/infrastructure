# Station2290 Production Makefile
# Comprehensive automation for Docker Compose-based microservices deployment
# Compatible with Ubuntu 22.04+ using 'docker compose' (not docker-compose)

# Colors for better output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Default configuration
COMPOSE_FILE := docker-compose.yml
COMPOSE_INFRA_FILE := docker-compose.infrastructure.yml
PROJECT_NAME := station2290
BACKUP_DATE ?= $(shell date +%Y%m%d_%H%M%S)
REPLICAS ?= 1

# Help target
.PHONY: help
help:
	@echo "$(BLUE)Station2290 Development & Production Automation$(NC)"
	@echo ""
	@echo "$(GREEN)SETUP & ENVIRONMENT:$(NC)"
	@echo "  setup              Create all required directories and networks"
	@echo "  env                Copy and configure environment files"
	@echo "  network            Create Docker networks"
	@echo "  permissions        Fix file and directory permissions"
	@echo ""
	@echo "$(GREEN)INFRASTRUCTURE MANAGEMENT:$(NC)"
	@echo "  infra-up           Start infrastructure services only"
	@echo "  infra-down         Stop infrastructure services"
	@echo "  infra-logs         View infrastructure logs"
	@echo "  infra-status       Show infrastructure service status"
	@echo ""
	@echo "$(GREEN)SSL CERTIFICATE MANAGEMENT:$(NC)"
	@echo "  ssl-init           Initial SSL certificate setup"
	@echo "  ssl-renew          Renew SSL certificates"
	@echo "  ssl-check          Check certificate status"
	@echo "  ssl-test           Test SSL configuration"
	@echo ""
	@echo "$(GREEN)APPLICATION MANAGEMENT:$(NC)"
	@echo "  build              Build all application images"
	@echo "  up                 Start all services"
	@echo "  down               Stop all services"
	@echo "  restart            Restart all services"
	@echo "  status             Show container status"
	@echo ""
	@echo "$(GREEN)DEVELOPMENT TOOLS:$(NC)"
	@echo "  logs               View all logs"
	@echo "  logs-follow        Follow logs in real-time"
	@echo "  shell-api          Access API container shell"
	@echo "  shell-db           Access database shell"
	@echo "  logs-api           View API service logs"
	@echo "  logs-nginx         View Nginx logs"
	@echo ""
	@echo "$(GREEN)MAINTENANCE & BACKUP:$(NC)"
	@echo "  backup             Backup databases and configurations"
	@echo "  restore            Restore from backup (use BACKUP_DATE=...)"
	@echo "  clean              Clean unused Docker resources"
	@echo "  health             Complete health check"
	@echo ""
	@echo "$(GREEN)MONITORING:$(NC)"
	@echo "  monitoring-up      Start monitoring stack"
	@echo "  grafana            Open Grafana dashboard"
	@echo "  prometheus         Open Prometheus dashboard"
	@echo "  monitoring-status  Check monitoring services"
	@echo ""
	@echo "$(GREEN)PRODUCTION:$(NC)"
	@echo "  deploy             Full production deployment"
	@echo "  update             Update all services"
	@echo "  scale-api          Scale API service (use REPLICAS=N)"
	@echo "  nginx-reload       Reload Nginx configuration"
	@echo ""
	@echo "$(GREEN)EMERGENCY & DEBUG:$(NC)"
	@echo "  emergency-stop     Emergency stop all containers"
	@echo "  debug              Show debug information"
	@echo "  reset              Complete environment reset (DESTRUCTIVE)"
	@echo "  version            Show version information"
	@echo "  ports              Show port mappings"

# Setup and Environment
.PHONY: setup
setup:
	@echo "$(GREEN)Setting up Station2290 environment...$(NC)"
	@sudo mkdir -p /opt/station2290/{data/{postgres,redis,uploads,bot-sessions},ssl/{certs,challenges},logs/{nginx,certbot},monitoring/{prometheus,grafana,loki},backups}
	@sudo mkdir -p /tmp/nginx_cache
	@sudo mkdir -p /var/www/certbot
	@$(MAKE) permissions
	@$(MAKE) network
	@echo "$(GREEN)✅ Environment setup complete$(NC)"

.PHONY: env
env:
	@echo "$(YELLOW)Configuring environment files...$(NC)"
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			cp .env.example .env; \
			echo "$(GREEN)✅ Created .env from .env.example$(NC)"; \
		else \
			echo "$(RED)❌ No .env.example found$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)⚠️  .env already exists$(NC)"; \
	fi

.PHONY: network
network:
	@echo "$(YELLOW)Creating Docker networks...$(NC)"
	@docker network create station2290_network --subnet=172.20.0.0/16 --gateway=172.20.0.1 2>/dev/null || echo "$(YELLOW)Network station2290_network already exists$(NC)"
	@docker network create monitoring_network --subnet=172.21.0.0/16 --gateway=172.21.0.1 2>/dev/null || echo "$(YELLOW)Network monitoring_network already exists$(NC)"
	@docker network create database_network --subnet=172.22.0.0/16 --gateway=172.22.0.1 --internal 2>/dev/null || echo "$(YELLOW)Network database_network already exists$(NC)"
	@echo "$(GREEN)✅ Networks configured$(NC)"

.PHONY: permissions
permissions:
	@echo "$(YELLOW)Setting proper permissions...$(NC)"
	@sudo chown -R $$USER:$$USER /opt/station2290 2>/dev/null || true
	@sudo chmod -R 755 /opt/station2290 2>/dev/null || true
	@sudo chown -R $$USER:$$USER /tmp/nginx_cache 2>/dev/null || true
	@sudo chown -R $$USER:$$USER /var/www/certbot 2>/dev/null || true
	@echo "$(GREEN)✅ Permissions set$(NC)"

# Infrastructure Management
.PHONY: infra-up
infra-up:
	@echo "$(GREEN)Starting infrastructure services...$(NC)"
	@docker compose -f $(COMPOSE_INFRA_FILE) up -d
	@echo "$(GREEN)✅ Infrastructure services started$(NC)"

.PHONY: infra-down
infra-down:
	@echo "$(YELLOW)Stopping infrastructure services...$(NC)"
	@docker compose -f $(COMPOSE_INFRA_FILE) down
	@echo "$(GREEN)✅ Infrastructure services stopped$(NC)"

.PHONY: infra-logs
infra-logs:
	@docker compose -f $(COMPOSE_INFRA_FILE) logs --tail=100

.PHONY: infra-status
infra-status:
	@docker compose -f $(COMPOSE_INFRA_FILE) ps

# SSL Certificate Management
.PHONY: ssl-init
ssl-init:
	@echo "$(GREEN)Initializing SSL certificates...$(NC)"
	@docker compose exec certbot certbot certonly \
		--webroot \
		--webroot-path=/var/www/certbot \
		-d station2290.ru \
		-d www.station2290.ru \
		-d api.station2290.ru \
		-d adminka.station2290.ru \
		-d orders.station2290.ru \
		-d bot.station2290.ru \
		--email n1k3f1t@gmail.com \
		--agree-tos \
		--non-interactive
	@echo "$(GREEN)✅ SSL certificates initialized$(NC)"

.PHONY: ssl-renew
ssl-renew:
	@echo "$(YELLOW)Renewing SSL certificates...$(NC)"
	@docker compose exec certbot certbot renew --quiet
	@docker compose restart nginx
	@echo "$(GREEN)✅ SSL certificates renewed$(NC)"

.PHONY: ssl-check
ssl-check:
	@echo "$(BLUE)Checking SSL certificate status...$(NC)"
	@docker compose exec certbot certbot certificates

.PHONY: ssl-test
ssl-test:
	@echo "$(BLUE)Testing SSL configuration...$(NC)"
	@curl -I https://station2290.ru/health || echo "$(RED)SSL test failed$(NC)"

# Application Management
.PHONY: build
build:
	@echo "$(GREEN)Building all application images...$(NC)"
	@docker compose build --parallel
	@echo "$(GREEN)✅ All images built$(NC)"

.PHONY: up
up:
	@echo "$(GREEN)Starting all services...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)✅ All services started$(NC)"
	@$(MAKE) status

.PHONY: down
down:
	@echo "$(YELLOW)Stopping all services...$(NC)"
	@docker compose down
	@echo "$(GREEN)✅ All services stopped$(NC)"

.PHONY: restart
restart:
	@echo "$(YELLOW)Restarting all services...$(NC)"
	@docker compose restart
	@echo "$(GREEN)✅ All services restarted$(NC)"

.PHONY: status
status:
	@echo "$(BLUE)Container Status:$(NC)"
	@docker compose ps
	@echo ""
	@echo "$(BLUE)Network Status:$(NC)"
	@docker network ls | grep station2290

# Development Tools
.PHONY: logs
logs:
	@docker compose logs --tail=100

.PHONY: logs-follow
logs-follow:
	@docker compose logs -f --tail=100

.PHONY: shell-api
shell-api:
	@echo "$(BLUE)Accessing API container shell...$(NC)"
	@docker compose exec api /bin/sh

.PHONY: shell-db
shell-db:
	@echo "$(BLUE)Accessing database shell...$(NC)"
	@docker compose exec postgres psql -U station2290_user -d station2290

.PHONY: logs-api
logs-api:
	@docker compose logs api --tail=100

.PHONY: logs-nginx
logs-nginx:
	@docker compose logs nginx --tail=100

# Maintenance and Backup
.PHONY: backup
backup:
	@echo "$(GREEN)Creating backup...$(NC)"
	@mkdir -p /opt/station2290/backups/$(BACKUP_DATE)
	@docker compose exec postgres pg_dump -U station2290_user station2290 > /opt/station2290/backups/$(BACKUP_DATE)/postgres_$(BACKUP_DATE).sql
	@docker compose exec redis redis-cli BGSAVE
	@sleep 5
	@docker cp $$(docker compose ps -q redis):/data/dump.rdb /opt/station2290/backups/$(BACKUP_DATE)/redis_$(BACKUP_DATE).rdb
	@tar -czf /opt/station2290/backups/$(BACKUP_DATE)/configs_$(BACKUP_DATE).tar.gz infrastructure/
	@echo "$(GREEN)✅ Backup completed: $(BACKUP_DATE)$(NC)"

.PHONY: restore
restore:
	@if [ -z "$(BACKUP_DATE)" ]; then \
		echo "$(RED)❌ Please specify BACKUP_DATE (e.g., make restore BACKUP_DATE=20240101_120000)$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)Restoring from backup: $(BACKUP_DATE)$(NC)"
	@docker compose exec postgres psql -U station2290_user -d station2290 < /opt/station2290/backups/$(BACKUP_DATE)/postgres_$(BACKUP_DATE).sql
	@docker cp /opt/station2290/backups/$(BACKUP_DATE)/redis_$(BACKUP_DATE).rdb $$(docker compose ps -q redis):/data/dump.rdb
	@docker compose restart redis
	@echo "$(GREEN)✅ Restore completed$(NC)"

.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning unused Docker resources...$(NC)"
	@docker system prune -f
	@docker volume prune -f
	@docker network prune -f
	@echo "$(GREEN)✅ Cleanup completed$(NC)"

.PHONY: health
health:
	@echo "$(BLUE)Running comprehensive health checks...$(NC)"
	@echo "$(YELLOW)Checking container health...$(NC)"
	@docker compose ps
	@echo ""
	@echo "$(YELLOW)Checking HTTP endpoints...$(NC)"
	@curl -f -s http://localhost/health && echo "$(GREEN)✅ Web health OK$(NC)" || echo "$(RED)❌ Web health FAIL$(NC)"
	@curl -f -s http://localhost:3000/health && echo "$(GREEN)✅ API health OK$(NC)" || echo "$(RED)❌ API health FAIL$(NC)"
	@echo ""
	@echo "$(YELLOW)Checking database connectivity...$(NC)"
	@docker compose exec postgres pg_isready -U station2290_user && echo "$(GREEN)✅ PostgreSQL OK$(NC)" || echo "$(RED)❌ PostgreSQL FAIL$(NC)"
	@docker compose exec redis redis-cli ping && echo "$(GREEN)✅ Redis OK$(NC)" || echo "$(RED)❌ Redis FAIL$(NC)"

# Monitoring
.PHONY: monitoring-up
monitoring-up:
	@echo "$(GREEN)Starting monitoring stack...$(NC)"
	@docker compose up -d prometheus grafana loki
	@echo "$(GREEN)✅ Monitoring stack started$(NC)"
	@echo "$(BLUE)Grafana: http://localhost:3010$(NC)"
	@echo "$(BLUE)Prometheus: http://localhost:9090$(NC)"

.PHONY: grafana
grafana:
	@echo "$(BLUE)Opening Grafana dashboard...$(NC)"
	@echo "$(BLUE)URL: http://localhost:3010$(NC)"
	@echo "$(BLUE)Default credentials: admin/admin$(NC)"

.PHONY: prometheus
prometheus:
	@echo "$(BLUE)Opening Prometheus dashboard...$(NC)"
	@echo "$(BLUE)URL: http://localhost:9090$(NC)"

.PHONY: monitoring-status
monitoring-status:
	@echo "$(BLUE)Monitoring Services Status:$(NC)"
	@docker compose ps prometheus grafana loki

# Production
.PHONY: deploy
deploy: setup build ssl-init up monitoring-up
	@echo "$(GREEN)🚀 Full production deployment completed!$(NC)"
	@$(MAKE) health

.PHONY: update
update:
	@echo "$(YELLOW)Updating all services...$(NC)"
	@docker compose pull
	@docker compose up -d
	@echo "$(GREEN)✅ All services updated$(NC)"

.PHONY: scale-api
scale-api:
	@echo "$(YELLOW)Scaling API service to $(REPLICAS) replicas...$(NC)"
	@docker compose up -d --scale api=$(REPLICAS)
	@echo "$(GREEN)✅ API scaled to $(REPLICAS) replicas$(NC)"

.PHONY: nginx-reload
nginx-reload:
	@echo "$(YELLOW)Reloading Nginx configuration...$(NC)"
	@docker compose exec nginx nginx -s reload
	@echo "$(GREEN)✅ Nginx configuration reloaded$(NC)"

# Emergency and Debug
.PHONY: emergency-stop
emergency-stop:
	@echo "$(RED)🚨 EMERGENCY STOP - Stopping all containers immediately$(NC)"
	@docker stop $$(docker ps -q) 2>/dev/null || true
	@echo "$(GREEN)✅ All containers stopped$(NC)"

.PHONY: debug
debug:
	@echo "$(BLUE)=== STATION2290 DEBUG INFORMATION ===$(NC)"
	@echo "$(YELLOW)Docker Version:$(NC)"
	@docker --version
	@docker compose version
	@echo ""
	@echo "$(YELLOW)System Resources:$(NC)"
	@df -h | head -5
	@free -h
	@echo ""
	@echo "$(YELLOW)Docker Resources:$(NC)"
	@docker system df
	@echo ""
	@echo "$(YELLOW)Running Containers:$(NC)"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "$(YELLOW)Docker Networks:$(NC)"
	@docker network ls | grep station2290
	@echo ""
	@echo "$(YELLOW)Recent Logs (last 10 lines):$(NC)"
	@docker compose logs --tail=10

.PHONY: reset
reset:
	@echo "$(RED)⚠️  WARNING: This will destroy all data and containers!$(NC)"
	@echo "$(RED)Press Ctrl+C to cancel, or wait 10 seconds to continue...$(NC)"
	@sleep 10
	@docker compose down -v --remove-orphans
	@docker system prune -a -f --volumes
	@sudo rm -rf /opt/station2290/data/*
	@echo "$(GREEN)✅ Environment reset completed$(NC)"

.PHONY: version
version:
	@echo "$(BLUE)Station2290 Automation v1.0.0$(NC)"
	@echo "$(BLUE)Docker Compose deployment automation$(NC)"
	@echo "$(BLUE)Compatible with Ubuntu 22.04+ (docker compose)$(NC)"

.PHONY: ports
ports:
	@echo "$(BLUE)=== PORT MAPPINGS ===$(NC)"
	@echo "$(YELLOW)Web Application:$(NC)     http://localhost (80)"
	@echo "$(YELLOW)HTTPS:$(NC)              https://localhost (443)"
	@echo "$(YELLOW)API:$(NC)                http://localhost:3000"
	@echo "$(YELLOW)Grafana:$(NC)            http://localhost:3010"
	@echo "$(YELLOW)Prometheus:$(NC)         http://localhost:9090"
	@echo "$(YELLOW)Loki:$(NC)               http://localhost:3100"
	@echo "$(YELLOW)PostgreSQL:$(NC)         localhost:5432"
	@echo "$(YELLOW)Redis:$(NC)              localhost:6379"
	@echo "$(YELLOW)Admin Panel:$(NC)        http://localhost:8080"
	@echo "$(YELLOW)Order Panel:$(NC)        http://localhost:8081"

# Default target
.DEFAULT_GOAL := help