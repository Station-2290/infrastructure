# Station2290 Infrastructure Repository

This repository contains all infrastructure configurations, deployment scripts, and operational tools for the Station2290 project.

## 🏗️ Architecture Overview

The Station2290 infrastructure follows a microservices architecture with:

- **Nginx Reverse Proxy** - Handles SSL termination, load balancing, and routing
- **Docker Containers** - All services run in containerized environments
- **PostgreSQL Database** - Primary data storage
- **Redis Cache** - Session storage and caching
- **SSL/TLS** - Let's Encrypt certificates with automatic renewal
- **Monitoring** - Grafana, Prometheus, and Loki for observability

## 📁 Repository Structure

```
infrastructure/
├── nginx/                    # Nginx configurations
│   ├── sites-available/      # Available site configurations
│   ├── sites-enabled/        # Enabled site configurations (symlinks)
│   ├── ssl/                  # SSL certificate management
│   └── logs/                 # Nginx logs
├── docker/                   # Docker configurations
│   ├── production/           # Production Docker compose files
│   ├── development/          # Development Docker compose files
│   └── templates/            # Docker configuration templates
├── deployment/               # Deployment automation
│   ├── scripts/              # Deployment scripts
│   ├── ssl/                  # SSL setup and renewal
│   ├── backup/               # Backup scripts and procedures
│   └── monitoring/           # Health check scripts
├── cicd/                     # CI/CD configurations
│   ├── github-actions/       # GitHub Actions workflows
│   └── templates/            # CI/CD templates
├── configs/                  # Configuration files
│   ├── environment/          # Environment variable templates
│   ├── security/             # Security configurations
│   └── logging/              # Logging configurations
├── monitoring/               # Monitoring and observability
│   ├── grafana/              # Grafana dashboards
│   ├── prometheus/           # Prometheus configurations
│   ├── loki/                 # Log aggregation
│   └── alertmanager/         # Alert configurations
├── scripts/                  # Utility scripts
│   ├── health-checks/        # Health check scripts
│   ├── maintenance/          # Maintenance scripts
│   └── automation/           # Automation utilities
└── docs/                     # Documentation
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Domain configured with DNS pointing to your VPS
- Access to VPS server with sudo privileges

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/station2290-infrastructure.git
cd station2290-infrastructure
```

### 2. Configure Environment

```bash
# Copy environment template
cp configs/environment/.env.prod.template configs/environment/.env.prod

# Edit configuration with your values
nano configs/environment/.env.prod
```

### 3. Deploy Infrastructure

```bash
# Run deployment script
./deployment/scripts/deploy-production.sh
```

## 🔧 Configuration

### Environment Variables

All services are configured via environment variables stored in `configs/environment/`:

- `.env.prod.template` - Production environment template
- `.env.dev.template` - Development environment template
- `.env.staging.template` - Staging environment template

### Nginx Configuration

Nginx configurations are modular and located in `nginx/sites-available/`:

- `main.conf` - Main website (station2290.ru)
- `api.conf` - API service (api.station2290.ru)
- `adminka.conf` - Admin panel (adminka.station2290.ru)
- `orders.conf` - Order panel (orders.station2290.ru)
- `bot.conf` - Bot service (bot.station2290.ru)

### SSL/TLS Setup

SSL certificates are managed automatically via Let's Encrypt:

```bash
# Initial SSL setup
./deployment/ssl/setup-ssl.sh

# Manual certificate renewal
./deployment/ssl/renew-certificates.sh
```

## 🐳 Docker Deployment

### Production Deployment

```bash
# Deploy all services
docker compose -f docker/production/docker-compose.yml up -d

# Deploy specific service
docker compose -f docker/production/docker-compose.yml up -d api
```

### Development Environment

```bash
# Start development environment
docker compose -f docker/development/docker-compose.yml up -d
```

## 📊 Monitoring

### Access Monitoring Dashboards

- **Grafana**: https://monitoring.station2290.ru
- **Prometheus**: https://prometheus.station2290.ru
- **Loki**: https://logs.station2290.ru

### Key Metrics

The monitoring stack tracks:

- Application performance and response times
- Database performance and connections
- System resources (CPU, memory, disk)
- SSL certificate expiration
- Service health and uptime
- Error rates and logs

## 🚨 Alerting

Alerts are configured for:

- Service downtime
- High error rates
- Resource exhaustion
- SSL certificate expiration
- Database connectivity issues

Alerts are sent via:
- Email notifications
- Slack integration
- Webhook endpoints

## 🔒 Security

### Security Measures

- SSL/TLS encryption for all services
- Security headers (HSTS, CSP, X-Frame-Options)
- Rate limiting on API endpoints
- Firewall rules and port restrictions
- Regular security updates via Watchtower
- Database access restrictions

### Security Configurations

Security configurations are stored in `configs/security/`:

- `firewall-rules.sh` - UFW firewall configuration
- `ssl-security.conf` - SSL security settings
- `security-headers.conf` - HTTP security headers

## 🔄 CI/CD

### GitHub Actions Workflows

Located in `cicd/github-actions/`:

- `deploy-infrastructure.yml` - Infrastructure deployment
- `ssl-renewal.yml` - Automated SSL certificate renewal
- `backup.yml` - Automated backups
- `monitoring-checks.yml` - Infrastructure health checks

### Deployment Pipeline

1. **Validation** - Syntax and configuration validation
2. **Testing** - Infrastructure tests and security scans
3. **Staging** - Deploy to staging environment
4. **Production** - Deploy to production with health checks
5. **Monitoring** - Post-deployment verification

## 💾 Backup & Recovery

### Automated Backups

Backups are automated via cron jobs and include:

- Database dumps (daily)
- Application data (daily)
- Configuration files (weekly)
- SSL certificates (weekly)

### Backup Scripts

Located in `deployment/backup/`:

- `backup-database.sh` - Database backup automation
- `backup-configs.sh` - Configuration backup
- `backup-ssl.sh` - SSL certificate backup
- `restore-from-backup.sh` - Restoration procedures

### Recovery Procedures

1. **Service Recovery** - Restart failed services
2. **Data Recovery** - Restore from recent backups
3. **SSL Recovery** - Regenerate certificates if needed
4. **Full Recovery** - Complete infrastructure restoration

## 🛠️ Maintenance

### Regular Maintenance Tasks

- **Daily**: Health checks, log rotation
- **Weekly**: Security updates, backup verification
- **Monthly**: SSL certificate checks, performance reviews
- **Quarterly**: Security audits, disaster recovery tests

### Maintenance Scripts

Located in `scripts/maintenance/`:

- `update-system.sh` - System updates
- `cleanup-logs.sh` - Log cleanup and rotation
- `security-scan.sh` - Security vulnerability scanning
- `performance-tune.sh` - Performance optimization

## 📚 Documentation

Detailed documentation is available in the `docs/` directory:

- [Architecture Guide](docs/architecture.md)
- [Deployment Guide](docs/deployment.md)
- [Monitoring Guide](docs/monitoring.md)
- [Security Guide](docs/security.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [Backup & Recovery Guide](docs/backup-recovery.md)

## 🆘 Troubleshooting

### Common Issues

1. **SSL Certificate Issues**
   ```bash
   ./deployment/ssl/diagnose-ssl.sh
   ```

2. **Service Health Issues**
   ```bash
   ./scripts/health-checks/check-all-services.sh
   ```

3. **Database Connection Issues**
   ```bash
   ./scripts/health-checks/check-database.sh
   ```

4. **Nginx Configuration Issues**
   ```bash
   nginx -t
   ./scripts/health-checks/check-nginx.sh
   ```

### Log Locations

- **Nginx Logs**: `/var/log/nginx/`
- **Application Logs**: `/home/station2290/logs/`
- **System Logs**: `/var/log/`
- **Docker Logs**: `docker logs <container_name>`

## 📞 Support

For infrastructure support:

- Create an issue in this repository
- Check the troubleshooting guide
- Review monitoring dashboards
- Contact the infrastructure team

## 📄 License

This infrastructure configuration is proprietary and confidential.

---

**Last Updated**: $(date)
**Version**: 1.0.0
**Maintainer**: Infrastructure Team