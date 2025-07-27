#!/bin/bash

# Station2290 Firewall Configuration Script
# UFW (Uncomplicated Firewall) rules for production security

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

log "Configuring UFW firewall for Station2290..."

# Reset UFW to defaults
log "Resetting UFW to defaults..."
ufw --force reset

# Set default policies
log "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# Allow SSH (critical - don't lock yourself out!)
log "Allowing SSH access..."
ufw allow 22/tcp comment "SSH"

# Allow HTTP and HTTPS
log "Allowing web traffic..."
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Allow monitoring port (restricted to localhost)
log "Allowing monitoring access..."
ufw allow from 127.0.0.1 to any port 8080 comment "Nginx monitoring"
ufw allow from 127.0.0.1 to any port 9090 comment "Prometheus"
ufw allow from 127.0.0.1 to any port 3001 comment "Grafana"
ufw allow from 127.0.0.1 to any port 3100 comment "Loki"

# Allow database access (localhost only)
log "Configuring database access..."
ufw allow from 127.0.0.1 to any port 5432 comment "PostgreSQL"
ufw allow from 127.0.0.1 to any port 6379 comment "Redis"

# Docker networks
log "Allowing Docker network access..."
ufw allow from 172.20.0.0/16 comment "Station2290 Docker network"
ufw allow from 172.21.0.0/16 comment "Monitoring Docker network"
ufw allow from 172.22.0.0/16 comment "Database Docker network"

# Rate limiting for SSH
log "Setting up rate limiting for SSH..."
ufw limit ssh comment "Rate limit SSH"

# Block common attack ports
log "Blocking common attack ports..."
ufw deny 23/tcp comment "Block Telnet"
ufw deny 135/tcp comment "Block RPC"
ufw deny 139/tcp comment "Block NetBIOS"
ufw deny 445/tcp comment "Block SMB"
ufw deny 1433/tcp comment "Block MS SQL"
ufw deny 3389/tcp comment "Block RDP"

# Allow specific trusted IPs (customize as needed)
# Uncomment and modify these lines for your trusted IPs
# ufw allow from YOUR_OFFICE_IP comment "Office IP"
# ufw allow from YOUR_HOME_IP comment "Home IP"

# Block specific countries (optional)
# This would require additional setup with ipset
# ufw deny from COUNTRY_IP_RANGE comment "Block malicious country"

# Application-specific rules
log "Setting up application-specific rules..."

# WhatsApp webhook (Meta IP ranges)
ufw allow from 31.13.64.0/19 to any port 443 comment "Facebook/Meta IP range 1"
ufw allow from 157.240.0.0/16 to any port 443 comment "Facebook/Meta IP range 2"
ufw allow from 173.252.64.0/19 to any port 443 comment "Facebook/Meta IP range 3"
ufw allow from 69.63.176.0/20 to any port 443 comment "Facebook/Meta IP range 4"

# CDN and legitimate services
ufw allow from 173.245.48.0/20 to any port 80,443 comment "Cloudflare"
ufw allow from 103.21.244.0/22 to any port 80,443 comment "Cloudflare"
ufw allow from 103.22.200.0/22 to any port 80,443 comment "Cloudflare"
ufw allow from 103.31.4.0/22 to any port 80,443 comment "Cloudflare"
ufw allow from 141.101.64.0/18 to any port 80,443 comment "Cloudflare"
ufw allow from 108.162.192.0/18 to any port 80,443 comment "Cloudflare"
ufw allow from 190.93.240.0/20 to any port 80,443 comment "Cloudflare"

# Monitoring and health checks
ufw allow from 0.0.0.0/0 to any port 80,443 comment "Public web access"

# Backup access (if using external backup services)
# ufw allow from BACKUP_SERVICE_IP to any port 22 comment "Backup service"

# Advanced rules
log "Setting up advanced security rules..."

# Drop invalid packets
ufw --force insert 1 deny in on any from any to any log-prefix "[UFW BLOCK INVALID] " drop
ufw --force insert 2 deny out on any from any to any log-prefix "[UFW BLOCK INVALID] " drop

# Rate limiting for HTTP/HTTPS (basic protection)
ufw limit from any to any port 80 proto tcp comment "Rate limit HTTP"
ufw limit from any to any port 443 proto tcp comment "Rate limit HTTPS"

# Block specific known bad IPs (customize based on your logs)
# ufw deny from BAD_IP_1 comment "Known attacker"
# ufw deny from BAD_IP_2 comment "Known attacker"

# Geo-blocking (requires additional setup)
# This would need GeoIP database and custom rules
# Example for blocking specific countries:
# ufw deny from $(curl -s https://www.ipdeny.com/ipblocks/data/countries/cn.zone) comment "Block China"

# Enable logging
log "Enabling UFW logging..."
ufw logging on

# Enable UFW
log "Enabling UFW firewall..."
ufw --force enable

# Show status
log "UFW configuration completed. Current status:"
ufw status verbose

# Create fail2ban integration
log "Setting up fail2ban integration..."

# Install fail2ban if not present
if ! command -v fail2ban-client &> /dev/null; then
    log "Installing fail2ban..."
    apt-get update
    apt-get install -y fail2ban
fi

# Create custom fail2ban configuration
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban IP for 1 hour
bantime = 3600
# Check for failures in last 10 minutes
findtime = 600
# Ban after 5 failures
maxretry = 5
# Use UFW for banning
banaction = ufw
# Email notifications
destemail = admin@station2290.ru
sender = fail2ban@station2290.ru
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /opt/station2290/logs/nginx/*error*.log
maxretry = 3

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /opt/station2290/logs/nginx/*access*.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /opt/station2290/logs/nginx/*access*.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /opt/station2290/logs/nginx/*access*.log
maxretry = 2

[station2290-api]
enabled = true
port = 443
filter = station2290-api
logpath = /opt/station2290/logs/nginx/api_error.log
maxretry = 5
bantime = 1800
EOF

# Create custom filters for Station2290
mkdir -p /etc/fail2ban/filter.d

cat > /etc/fail2ban/filter.d/station2290-api.conf << 'EOF'
[Definition]
failregex = ^.*\[error\].*client: <HOST>.*
            ^.*\[warn\].*client: <HOST>.*"[A-Z]+ .*" (4[0-9][0-9]|5[0-9][0-9])
ignoreregex =
EOF

# Restart fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

success "Firewall configuration completed successfully!"

# Display summary
cat << EOF

🔒 Station2290 Firewall Configuration Summary

Allowed Services:
• SSH (22/tcp) - Rate limited
• HTTP (80/tcp) - Public access
• HTTPS (443/tcp) - Public access
• Monitoring (8080,9090,3001,3100/tcp) - Localhost only
• Database (5432,6379/tcp) - Localhost only

Security Features:
• Default deny incoming policy
• Rate limiting on SSH, HTTP, HTTPS
• Docker network isolation
• WhatsApp webhook IP allowlist
• Fail2ban integration for attack mitigation
• Logging enabled for security monitoring

Next Steps:
1. Monitor logs: journalctl -u ufw
2. Check fail2ban status: fail2ban-client status
3. Review firewall rules: ufw status numbered
4. Test access from authorized IPs only

Important: Make sure you can access SSH before disconnecting!

EOF

# Test SSH access warning
warn "IMPORTANT: Test SSH access from your location before disconnecting!"
warn "If you get locked out, you'll need console access to fix the firewall."

# Create firewall monitoring script
cat > /opt/station2290/scripts/monitor-firewall.sh << 'EOF'
#!/bin/bash
# Firewall monitoring script for Station2290

# Check UFW status
echo "=== UFW Status ==="
ufw status

# Check fail2ban status
echo "=== Fail2ban Status ==="
fail2ban-client status

# Show recent blocks
echo "=== Recent UFW Blocks ==="
grep "UFW BLOCK" /var/log/ufw.log | tail -20

# Show fail2ban recent bans
echo "=== Recent Fail2ban Bans ==="
grep "Ban " /var/log/fail2ban.log | tail -20

# Check iptables rules count
echo "=== IPTables Rules Count ==="
iptables -L | wc -l
EOF

chmod +x /opt/station2290/scripts/monitor-firewall.sh

log "Firewall monitoring script created at /opt/station2290/scripts/monitor-firewall.sh"
success "Station2290 firewall setup completed successfully!"