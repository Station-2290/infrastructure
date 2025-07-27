# Station2290 Infrastructure

This repository contains the infrastructure configuration for the Station2290 coffee shop management system. It manages core infrastructure services while applications are deployed separately via GitHub Actions.

## 🏗️ Infrastructure Overview

This repository deploys **infrastructure services only**:
- **PostgreSQL** - Primary database
- **Redis** - Caching and session storage  
- **Nginx** - Reverse proxy and load balancer
- **Prometheus** - Metrics collection
- **Grafana** - Monitoring dashboards
- **Loki** - Log aggregation
- **Certbot** - SSL certificate management
- **Health Check** - Service monitoring

## 🚀 Application Deployment Model

**Infrastructure vs Applications:**
- **Infrastructure** (this repo) → Deploys shared services (database, cache, proxy, monitoring)
- **Applications** (separate repos) → Deploy via GitHub Actions to the same VPS server

### Application Repositories:
1. [Station2290-API](https://github.com/Station-2290/api) - REST API backend
2. [Station2290-Web](https://github.com/Station-2290/web) - Customer web interface  
3. [Station2290-Bot](https://github.com/Station-2290/bot) - WhatsApp bot service
4. [Station2290-Adminka](https://github.com/Station-2290/adminka) - Admin panel
5. [Station2290-Order-Panel](https://github.com/Station-2290/order-panel) - Order management

## 📋 Prerequisites

- **VPS Server** with Docker and Docker Compose installed
- **Domain name** with DNS pointing to your VPS IP
- **GitHub repositories** set up with proper secrets

## 🔧 Quick Start

### 1. Clone Infrastructure Repository

```bash
# On your VPS server
cd /opt
sudo mkdir station2290
sudo chown $USER:docker station2290
cd station2290
git clone https://github.com/Station-2290/infrastructure.git
cd infrastructure
```

### 2. Configure Environment

```bash
# Copy and edit environment configuration
cp configs/environment/.env.prod.template configs/environment/.env.prod
nano configs/environment/.env.prod
```

**Required environment variables:**
```bash
# Database
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_USER=station2290_user
POSTGRES_DB=station2290

# JWT Secrets (min 32 characters each)
JWT_SECRET=your_jwt_secret_32_chars_minimum
JWT_REFRESH_SECRET=your_refresh_secret_32_chars_minimum

# Monitoring
GRAFANA_ADMIN_PASSWORD=your_grafana_password

# SSL
SSL_EMAIL=your-email@domain.com
SSL_DOMAINS=station2290.ru,www.station2290.ru,api.station2290.ru,adminka.station2290.ru,orders.station2290.ru,bot.station2290.ru
```

### 3. Deploy Infrastructure

```bash
# Deploy infrastructure services
./quick-deploy.sh
```

### 4. Set Up SSL Certificates

```bash
# Set up SSL certificates for your domains
./ssl/setup-ssl.sh
```

### 5. Deploy Applications

Applications deploy automatically when you push to their GitHub repositories. Each repository has GitHub Actions configured to:
1. Build Docker images
2. Push to GitHub Container Registry
3. Deploy directly to your VPS server

## 📁 Repository Structure

```
infrastructure/
├── quick-deploy.sh              # Infrastructure deployment script
├── docker/
│   └── production/
│       ├── docker-compose.infrastructure.yml  # Infrastructure-only services
│       └── docker-compose.yml                 # Full system (reference)
├── configs/
│   ├── environment/
│   │   ├── .env.prod.template   # Environment template
│   │   └── .env.prod           # Your production config (create this)
│   ├── nginx/                  # Nginx configurations
│   ├── postgres/               # PostgreSQL configurations
│   └── redis/                  # Redis configurations
├── monitoring/
│   ├── prometheus/             # Prometheus configuration
│   ├── grafana/               # Grafana dashboards
│   └── loki/                  # Loki log configuration
└── ssl/
    └── setup-ssl.sh           # SSL certificate setup
```

## 🔄 Deployment Workflow

### Infrastructure Deployment (This Repository)
1. **Manual Deployment**: Run `./quick-deploy.sh` when infrastructure changes
2. **Updates**: Pull latest infrastructure changes and re-run deployment script
3. **Monitoring**: Use Grafana dashboards to monitor infrastructure health

### Application Deployment (Automatic)
1. **Push to Repository**: Commit changes to any application repository
2. **GitHub Actions**: Automatically builds and deploys the application
3. **Health Checks**: Applications include health checks for monitoring
4. **Zero Downtime**: Rolling deployments with health validation

## 🌐 Service URLs

After deployment, services are available at:

### Public URLs (through Nginx reverse proxy):
- **Main Website**: https://station2290.ru
- **API**: https://api.station2290.ru
- **Admin Panel**: https://adminka.station2290.ru  
- **Order Panel**: https://orders.station2290.ru
- **Bot Webhook**: https://bot.station2290.ru

### Internal Services (localhost only):
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379
- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3001

## 📊 Monitoring & Logging

### Grafana Dashboards
Access monitoring at http://localhost:3001:
- **System Overview**: Server resources and health
- **Application Metrics**: Performance and usage statistics
- **Database Monitoring**: PostgreSQL performance
- **Nginx Analytics**: Traffic and response times

### Log Management
```bash
# View infrastructure logs
docker compose -f docker/production/docker-compose.infrastructure.yml logs -f

# View specific service logs
docker compose -f docker/production/docker-compose.infrastructure.yml logs -f postgres
docker compose -f docker/production/docker-compose.infrastructure.yml logs -f nginx

# View application logs (deployed by GitHub Actions)
docker logs coffee-shop-api -f
docker logs coffee-shop-web -f
docker logs coffee-shop-bot -f
```

## 🔒 Security Features

- **SSL/TLS**: Automatic certificate management with Let's Encrypt
- **Firewall**: Nginx configured with security headers
- **Network Isolation**: Services communicate through internal Docker networks
- **Secret Management**: Environment variables for sensitive data
- **Health Checks**: Automatic service health monitoring
- **Backup System**: Automated PostgreSQL backups

## 🛠️ Maintenance

### Infrastructure Updates
```bash
# Update infrastructure repository
git pull origin main

# Redeploy infrastructure services
./quick-deploy.sh
```

### SSL Certificate Renewal
```bash
# Certificates auto-renew, but manual renewal if needed:
docker compose -f docker/production/docker-compose.infrastructure.yml exec certbot certbot renew
```

### Database Backup
```bash
# Manual backup
docker compose -f docker/production/docker-compose.infrastructure.yml exec postgres pg_dump -U station2290_user station2290 > backup.sql

# Automated backups run daily at 2 AM (configured in docker-compose)
```

### Application Updates
Applications update automatically when you push to their repositories. No manual intervention needed.

## 🚨 Troubleshooting

### Infrastructure Services Not Starting
```bash
# Check service status
docker compose -f docker/production/docker-compose.infrastructure.yml ps

# View logs for failed services
docker compose -f docker/production/docker-compose.infrastructure.yml logs service-name

# Restart specific service
docker compose -f docker/production/docker-compose.infrastructure.yml restart service-name
```

### Application Deployment Issues
1. Check GitHub Actions logs in the application repository
2. Verify VPS server has sufficient resources
3. Check application logs: `docker logs coffee-shop-{service-name}`

### SSL Certificate Issues
```bash
# Check certificate status
docker compose -f docker/production/docker-compose.infrastructure.yml exec certbot certbot certificates

# Manually request certificates
docker compose -f docker/production/docker-compose.infrastructure.yml exec certbot certbot --webroot -w /var/www/certbot -d your-domain.com
```

### Database Connection Issues
```bash
# Test database connection
docker compose -f docker/production/docker-compose.infrastructure.yml exec postgres pg_isready -U station2290_user -d station2290

# Connect to database
docker compose -f docker/production/docker-compose.infrastructure.yml exec postgres psql -U station2290_user -d station2290
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test infrastructure changes in a development environment
4. Submit a pull request with detailed description

## 📞 Support

For issues with:
- **Infrastructure**: Create an issue in this repository
- **Applications**: Create issues in the respective application repositories
- **Deployment**: Check GitHub Actions logs in application repositories

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Infrastructure Status**: ✅ Ready for production  
**Last Updated**: January 2025  
**Maintained by**: Station2290 Development Team