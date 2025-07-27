# Station2290 Infrastructure Deployment Guide

This comprehensive guide covers the complete deployment process for the Station2290 infrastructure, from initial server setup to production deployment and monitoring.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Server Setup](#server-setup)
3. [Infrastructure Deployment](#infrastructure-deployment)
4. [SSL Configuration](#ssl-configuration)
5. [Monitoring Setup](#monitoring-setup)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Security Configuration](#security-configuration)
8. [Backup and Recovery](#backup-and-recovery)
9. [Troubleshooting](#troubleshooting)

## 🔧 Prerequisites

### Required Infrastructure
- **VPS Server**: Minimum 4GB RAM, 2 CPU cores, 50GB SSD
- **Domain**: `station2290.ru` with DNS configured
- **Subdomains**: `api`, `adminka`, `orders`, `bot`, `monitoring`
- **GitHub Repository**: Access to infrastructure repository

### Required Accounts
- GitHub account with repository access
- Domain registrar account
- VPS provider account (DigitalOcean, Hetzner, etc.)
- Optional: Monitoring service accounts

### Local Development Tools
- Docker and Docker Compose
- Git
- SSH client
- Text editor

## 🖥️ Server Setup

### 1. Initial Server Configuration

```bash
# Connect to your VPS
ssh root@your-server-ip

# Update system
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget git vim htop unzip software-properties-common

# Create application user
useradd -m -s /bin/bash station2290
usermod -aG sudo station2290

# Setup SSH key authentication (recommended)
mkdir -p /home/station2290/.ssh
cp /root/.ssh/authorized_keys /home/station2290/.ssh/
chown -R station2290:station2290 /home/station2290/.ssh
chmod 700 /home/station2290/.ssh
chmod 600 /home/station2290/.ssh/authorized_keys
```

### 2. Docker Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add user to docker group
usermod -aG docker station2290

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

### 3. Directory Structure Setup

```bash
# Switch to application user
su - station2290

# Create directory structure
sudo mkdir -p /opt/station2290/{data,logs,ssl,backups,monitoring}
sudo mkdir -p /opt/station2290/data/{postgres,redis,uploads,bot-sessions}
sudo mkdir -p /opt/station2290/ssl/{certs,challenges}
sudo mkdir -p /opt/station2290/monitoring/{prometheus,grafana,loki}

# Set permissions
sudo chown -R station2290:docker /opt/station2290
sudo chmod -R 755 /opt/station2290
```

## 🚀 Infrastructure Deployment

### 1. Clone Infrastructure Repository

```bash
# Clone the infrastructure repository
cd /opt/station2290
git clone https://github.com/yourusername/station2290-infrastructure.git infrastructure
cd infrastructure

# Verify structure
ls -la
```

### 2. Environment Configuration

```bash
# Copy and configure environment file
cp configs/environment/.env.prod.template configs/environment/.env.prod

# Edit environment configuration
vim configs/environment/.env.prod
```

**Critical environment variables to configure:**
```bash
# Database
POSTGRES_PASSWORD=your-secure-database-password

# Authentication
JWT_SECRET=your-jwt-secret-min-32-chars
JWT_REFRESH_SECRET=your-jwt-refresh-secret-min-32-chars
NEXTAUTH_SECRET=your-nextauth-secret-min-32-chars

# WhatsApp Business API
WHATSAPP_ACCESS_TOKEN=your-whatsapp-token
WHATSAPP_WEBHOOK_VERIFY_TOKEN=your-webhook-verify-token
WHATSAPP_BUSINESS_ACCOUNT_ID=your-account-id
WHATSAPP_PHONE_NUMBER_ID=your-phone-number-id

# Services
OPENAI_API_KEY=your-openai-api-key
COFFEE_SHOP_API_KEY=your-coffee-shop-api-key

# SSL
SSL_EMAIL=admin@station2290.ru
SSL_DOMAINS=station2290.ru,www.station2290.ru,api.station2290.ru,adminka.station2290.ru,orders.station2290.ru,bot.station2290.ru

# Monitoring
GRAFANA_ADMIN_PASSWORD=your-grafana-password
```

### 3. DNS Configuration

Configure your domain DNS records:

```
Type    Name        Value               TTL
A       @           YOUR_SERVER_IP      3600
A       www         YOUR_SERVER_IP      3600
A       api         YOUR_SERVER_IP      3600
A       adminka     YOUR_SERVER_IP      3600
A       orders      YOUR_SERVER_IP      3600
A       bot         YOUR_SERVER_IP      3600
A       monitoring  YOUR_SERVER_IP      3600
```

### 4. Initial Deployment

```bash
# Make deployment scripts executable
chmod +x deployment/scripts/*.sh
chmod +x deployment/ssl/*.sh

# Run the deployment
./deployment/scripts/deploy-production.sh
```

The deployment script will:
- Validate environment configuration
- Create system backups
- Build all Docker services
- Deploy infrastructure services
- Set up monitoring stack
- Run comprehensive health checks

## 🔒 SSL Configuration

### Automatic SSL Setup

The deployment script includes SSL setup, but you can also run it manually:

```bash
# Setup SSL certificates
./deployment/ssl/setup-ssl.sh

# Verify SSL certificates
./deployment/ssl/verify-certificates.sh
```

### Manual SSL Configuration

If automatic setup fails:

```bash
# Stop nginx temporarily
docker-compose -f docker/production/docker-compose.yml stop nginx

# Get certificates manually
certbot certonly --standalone \
  --email admin@station2290.ru \
  --agree-tos \
  --no-eff-email \
  -d station2290.ru \
  -d www.station2290.ru \
  -d api.station2290.ru \
  -d adminka.station2290.ru \
  -d orders.station2290.ru \
  -d bot.station2290.ru

# Copy certificates to Docker volume
cp -r /etc/letsencrypt/* /opt/station2290/ssl/certs/

# Start nginx
docker-compose -f docker/production/docker-compose.yml up -d nginx
```

## 📊 Monitoring Setup

### Access Monitoring Services

After deployment, access monitoring dashboards:

- **Grafana**: https://monitoring.station2290.ru
  - Username: `admin`
  - Password: `${GRAFANA_ADMIN_PASSWORD}`

- **Prometheus**: http://localhost:9090 (internal access only)
- **Loki**: http://localhost:3100 (internal access only)

### Configure Alerting

1. **Slack Integration** (optional):
   ```bash
   # Add Slack webhook URL to environment
   echo "SLACK_WEBHOOK_URL=your-slack-webhook-url" >> configs/environment/.env.prod
   ```

2. **Email Alerts**:
   ```bash
   # Configure SMTP settings in environment file
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=your-email@gmail.com
   SMTP_PASSWORD=your-app-password
   ```

### Custom Dashboards

Import pre-configured dashboards:
```bash
# Copy dashboard configurations
cp monitoring/grafana/dashboards/* /opt/station2290/monitoring/grafana/dashboards/

# Restart Grafana to load dashboards
docker-compose -f docker/production/docker-compose.yml restart grafana
```

## 🔄 CI/CD Pipeline

### GitHub Actions Setup

1. **Add Repository Secrets**:
   ```
   PRODUCTION_SSH_KEY       - SSH private key for server access
   PRODUCTION_HOST          - Server IP or hostname
   PRODUCTION_USER          - SSH username (station2290)
   STAGING_SSH_KEY          - Staging server SSH key (if applicable)
   STAGING_HOST             - Staging server hostname
   STAGING_USER             - Staging SSH username
   SLACK_WEBHOOK_URL        - Slack notifications (optional)
   ```

2. **Copy GitHub Actions Workflow**:
   ```bash
   # Copy to your repository
   mkdir -p .github/workflows
   cp cicd/github-actions/deploy-infrastructure.yml .github/workflows/
   ```

3. **Commit and Push**:
   ```bash
   git add .github/workflows/deploy-infrastructure.yml
   git commit -m "Add infrastructure deployment workflow"
   git push origin main
   ```

### Manual Deployment

For manual deployments without GitHub Actions:

```bash
# Update infrastructure
git pull origin main

# Deploy changes
./deployment/scripts/deploy-production.sh

# Check deployment status
./scripts/health-checks/check-all-services.sh
```

## 🛡️ Security Configuration

### Firewall Setup

```bash
# Configure UFW firewall
sudo ./configs/security/firewall-rules.sh

# Verify firewall status
sudo ufw status verbose
```

### SSL Security

```bash
# Test SSL configuration
./deployment/ssl/test-ssl-security.sh

# Check SSL rating
curl -s "https://api.ssllabs.com/api/v3/analyze?host=station2290.ru&all=done"
```

### Security Monitoring

```bash
# Install security monitoring tools
sudo apt install -y fail2ban logwatch

# Monitor security logs
sudo tail -f /var/log/fail2ban.log
sudo tail -f /var/log/ufw.log
```

## 💾 Backup and Recovery

### Automated Backups

Backups are configured automatically:
- **Database**: Daily at 2:00 AM
- **Application data**: Daily at 2:30 AM
- **Configuration**: Weekly on Sunday
- **SSL certificates**: Weekly on Sunday

### Manual Backup

```bash
# Create manual backup
./deployment/backup/create-backup.sh

# List available backups
ls -la /opt/station2290/backups/
```

### Recovery Process

```bash
# Restore from backup
./deployment/backup/restore-from-backup.sh /opt/station2290/backups/BACKUP_NAME

# Verify restoration
./scripts/health-checks/check-all-services.sh
```

## 🐛 Troubleshooting

### Common Issues

#### 1. Docker Services Won't Start

```bash
# Check Docker status
sudo systemctl status docker

# Check container logs
docker-compose -f docker/production/docker-compose.yml logs api
docker-compose -f docker/production/docker-compose.yml logs bot
docker-compose -f docker/production/docker-compose.yml logs nginx
```

#### 2. SSL Certificate Issues

```bash
# Check certificate status
./deployment/ssl/diagnose-ssl.sh

# Renew certificates manually
sudo certbot renew --force-renewal

# Restart nginx
docker-compose -f docker/production/docker-compose.yml restart nginx
```

#### 3. High Resource Usage

```bash
# Check system resources
htop
docker stats

# Check disk usage
df -h

# Clean up Docker resources
docker system prune -f
```

#### 4. Database Connection Issues

```bash
# Check PostgreSQL logs
docker-compose -f docker/production/docker-compose.yml logs postgres

# Test database connection
docker-compose -f docker/production/docker-compose.yml exec postgres psql -U station2290_user -d station2290

# Check Redis connection
docker-compose -f docker/production/docker-compose.yml exec redis redis-cli ping
```

### Health Check Commands

```bash
# Check all services
./scripts/health-checks/check-all-services.sh

# Check specific service
curl -f https://api.station2290.ru/health
curl -f https://station2290.ru/health

# Check nginx status
curl -f http://localhost:8080/nginx_status
```

### Log Locations

```bash
# Application logs
tail -f /opt/station2290/logs/deployment-*.log

# Nginx logs
tail -f /opt/station2290/logs/nginx/access.log
tail -f /opt/station2290/logs/nginx/error.log

# Docker logs
docker-compose -f docker/production/docker-compose.yml logs -f [service-name]

# System logs
journalctl -u docker
journalctl -f
```

## 📞 Support and Maintenance

### Regular Maintenance Tasks

**Daily:**
- Monitor system resources
- Check service health
- Review error logs

**Weekly:**
- Update system packages
- Review security logs
- Verify backups

**Monthly:**
- Update Docker images
- Review and rotate logs
- Security audit

### Performance Optimization

```bash
# Optimize Docker
echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
sysctl -p

# Optimize PostgreSQL
# Edit configs/postgres/postgresql.conf for your workload

# Clean up logs
find /opt/station2290/logs -name "*.log" -mtime +30 -delete
```

### Scaling Considerations

For high-traffic scenarios:
1. Increase server resources
2. Implement load balancing
3. Use external database services
4. Implement CDN for static assets
5. Consider container orchestration (Kubernetes)

---

## 🎉 Deployment Checklist

- [ ] Server setup and user configuration
- [ ] Docker and Docker Compose installed
- [ ] Directory structure created
- [ ] Infrastructure repository cloned
- [ ] Environment variables configured
- [ ] DNS records configured
- [ ] Initial deployment completed
- [ ] SSL certificates obtained and verified
- [ ] Monitoring dashboards accessible
- [ ] Health checks passing
- [ ] Firewall configured
- [ ] Backups tested
- [ ] CI/CD pipeline configured
- [ ] Documentation reviewed

**Congratulations! Your Station2290 infrastructure is now deployed and ready for production use.**

For additional support, refer to the [troubleshooting guide](troubleshooting.md) or create an issue in the infrastructure repository.