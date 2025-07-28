# SSL Setup Commands Using Existing Certbot Container

## Prerequisites
1. Domain `station2290.com` should point to your server IP (85.193.95.44)
2. Ports 80 and 443 should be accessible from the internet
3. Infrastructure should be running with `docker compose up -d`

## Step 1: Enable SSL challenge configuration
```bash
# Enable the SSL challenge site temporarily
ln -sf /opt/station2290/repos/infrastructure/nginx/sites-available/ssl-challenge.conf /opt/station2290/repos/infrastructure/nginx/sites-enabled/ssl-challenge.conf

# Disable the main site temporarily to avoid conflicts
rm -f /opt/station2290/repos/infrastructure/nginx/sites-enabled/station2290.conf

# Restart nginx to enable ACME challenge
docker restart station2290-nginx
```

## Step 2: Create required directories
```bash
# Create webroot for certbot ACME challenge
sudo mkdir -p /var/www/certbot
sudo chown -R www-data:www-data /var/www/certbot

# Create SSL directories
sudo mkdir -p /opt/station2290/ssl/{certs,private}
sudo mkdir -p /opt/station2290/logs/certbot
```

## Step 3: Obtain SSL certificates using existing certbot container
```bash
# Stop the current certbot renewal service
docker stop station2290-certbot

# Use certbot container to obtain certificates
docker run --rm \
  -v /opt/station2290/ssl:/etc/letsencrypt \
  -v /var/www/certbot:/var/www/certbot \
  -v /opt/station2290/logs/certbot:/var/log/letsencrypt \
  --network station2290-network \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email admin@station2290.com \
  --agree-tos \
  --no-eff-email \
  --domains station2290.com \
  --domains www.station2290.com
```

## Step 4: Create certificate symlinks for nginx
```bash
# Create symlinks to Let's Encrypt certificates
sudo ln -sf /opt/station2290/ssl/live/station2290.com/fullchain.pem /opt/station2290/ssl/certs/station2290.crt
sudo ln -sf /opt/station2290/ssl/live/station2290.com/privkey.pem /opt/station2290/ssl/private/station2290.key
```

## Step 5: Enable full site configuration with SSL
```bash
# Remove challenge config and enable full SSL config
rm -f /opt/station2290/repos/infrastructure/nginx/sites-enabled/ssl-challenge.conf
ln -sf /opt/station2290/repos/infrastructure/nginx/sites-available/station2290.conf /opt/station2290/repos/infrastructure/nginx/sites-enabled/station2290.conf

# Restart nginx with full SSL configuration
docker restart station2290-nginx

# Start certbot renewal service
docker start station2290-certbot
```

## Step 6: Test SSL configuration
```bash
# Test SSL configuration
docker exec station2290-nginx nginx -t

# Test HTTPS access
curl -k https://station2290.com/health

# Check certificate information
openssl x509 -in /opt/station2290/ssl/live/station2290.com/cert.pem -text -noout | grep -E "(Subject:|Not After:|DNS:)"
```

## Troubleshooting
If certificate generation fails:
1. Check domain DNS: `nslookup station2290.com`
2. Check port 80 accessibility: `curl http://station2290.com/.well-known/acme-challenge/test`
3. Check nginx logs: `docker logs station2290-nginx`
4. Check certbot logs: `cat /opt/station2290/logs/certbot/letsencrypt.log`

## Automatic Renewal
The certbot container is already configured to renew certificates every 12 hours automatically. No additional setup needed!