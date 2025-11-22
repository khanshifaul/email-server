# Email Server Setup & Management System

A complete, modular email server setup and management system using Docker, docker-mailserver, Nginx, and Let's Encrypt SSL certificates.

## 🚀 Quick Start

### Prerequisites
- Ubuntu 20.04+ or Debian 11+
- Docker and Docker Compose
- Root/sudo access
- Domain name with DNS access

### Installation
```bash
# Make scripts executable
chmod +x setup.sh manage.sh
chmod +x modules/*.sh

# Run interactive setup
./setup.sh

# Or non-interactive mode
./setup.sh --non-interactive \
  --domains "example.com,domain2.com" \
  --users "admin,user1" \
  --passwords "pass1,pass2"
```

### First Run Management
```bash
# Check status
./manage.sh status

# Add users
./manage.sh add-user admin@example.com password123

# Create backup
./manage.sh backup
```

## 📋 Features

### Core Email Server
- **Complete SMTP/IMAP** server using docker-mailserver
- **Multiple Domain Support** - Primary + additional domains
- **Automatic SSL** with Let's Encrypt integration
- **Nginx Reverse Proxy** with proper SSL termination
- **User Management** - Comprehensive account management
- **DNS Configuration** - Automatic record generation

### Security & Protection
- **Spam Protection** - SpamAssassin integration
- **Virus Scanning** - ClamAV anti-virus protection
- **Brute-force Protection** - Fail2Ban integration
- **Email Authentication** - DKIM, DMARC, SPF support
- **SSL/TLS Encryption** for all services

### Management & Monitoring
- **Interactive & Non-Interactive** setup modes
- **JSON Output Support** for automation
- **Real-time Monitoring** of services
- **Comprehensive Logging** and status reporting
- **Backup & Restore** capabilities

## 🏗️ Architecture

```
email-server/
├── setup.sh                          # Main setup script
├── manage.sh                         # Management script
├── modules/                          # Modular components
│   ├── logging.sh                    # Logging utilities
│   ├── prerequisites.sh              # System requirement checks
│   ├── directories.sh                # Directory management
│   ├── docker.sh                     # Docker compose configuration
│   ├── ssl.sh                        # SSL certificate management
│   ├── nginx.sh                      # Nginx configuration
│   ├── dns.sh                        # DNS record generation
│   ├── users.sh                      # User management
│   └── validation.sh                 # Input validation
├── email-server-config/              # Generated during setup
│   ├── docker-compose.yml
│   ├── users.json
│   ├── mailserver-data/
│   │   ├── data/                     # Mail data
│   │   ├── state/                    # Server state
│   │   ├── logs/                     # Server logs
│   │   └── config/                   # Server configuration
│   ├── ssl/                          # SSL certificates
│   ├── renew-ssl.sh                  # SSL renewal script
│   ├── generate-dkim.sh              # DKIM generation
│   ├── add-user.sh                   # User addition script
│   ├── backup.sh                     # Backup script
│   └── backup/                       # Backup storage
├── dns/                              # DNS configuration
│   ├── dns-records.txt               # DNS records
│   └── dkim-record.txt               # DKIM records
└── README.md                         # This file
```

## 🔧 Setup Options

### Interactive Setup
```bash
./setup.sh
```
- Guided configuration with prompts
- Real-time validation
- Visual DNS configuration table
- Confirmation before proceeding

### Non-Interactive Setup
```bash
./setup.sh --non-interactive \
  --domains "example.com,domain2.com" \
  --users "admin,user1" \
  --passwords "pass1,pass2"
```

### JSON Output
```bash
./setup.sh --json
./manage.sh status --json
```

## 📧 Email Configuration

### Client Settings
After setup, use these settings for email clients:

**Incoming (IMAP):**
- Server: `mail.yourdomain.com`
- Port: `993`
- Encryption: `SSL/TLS`
- Authentication: `Normal Password`

**Outgoing (SMTP):**
- Server: `mail.yourdomain.com`
- Port: `587`
- Encryption: `STARTTLS`
- Authentication: `Normal Password`

### DNS Records Required
Configure these DNS records for your domain:

| Record Type | Name/Host | Value/Points To |
|-------------|-----------|-----------------|
| A Record | mail.yourdomain.com | YOUR_SERVER_IP |
| MX Record | yourdomain.com | 10 mail.yourdomain.com |
| TXT (SPF) | yourdomain.com | "v=spf1 mx a ip4:YOUR_SERVER_IP ~all" |
| TXT (DMARC) | _dmarc.yourdomain.com | "v=DMARC1; p=quarantine; rua=mailto:admin@yourdomain.com" |
| TXT (DKIM) | default._domainkey.yourdomain.com | "v=DKIM1; k=rsa; p=DKIM_KEY" |

## 🛠️ Management Commands

### User Management
```bash
# Add new user
./manage.sh add-user user@domain.com password

# Change password
./manage.sh change-password user@domain.com newpassword

# Reset admin password
./manage.sh reset-admin-password

# List all users
./manage.sh list-users

# Show user configuration
./manage.sh user-config user@domain.com

# Add new domain
./manage.sh add-domain newdomain.com
```

### Service Management
```bash
# Start/stop/restart services
./manage.sh start
./manage.sh stop
./manage.sh restart

# Check status
./manage.sh status

# View logs
./manage.sh logs
./manage.sh logs mailserver
./manage.sh logs nginx

# Real-time monitoring
./manage.sh monitor
```

### SSL & DNS Management
```bash
# Renew SSL certificates
./manage.sh ssl-renew

# Check SSL status
./manage.sh ssl-status

# Generate DKIM keys
./manage.sh dkim

# Show DNS records
./manage.sh dns-records

# Generate DKIM records
./manage.sh generate-dkim
```

### Nginx Management
```bash
# Reload nginx configuration
./manage.sh nginx-reload

# Check nginx status
./manage.sh nginx-status

# View nginx logs
./manage.sh nginx-logs
```

### Backup & Maintenance
```bash
# Create full backup
./manage.sh backup

# Backup includes:
# - Mail data and user accounts
# - Server configuration
# - SSL certificates
# - User database
```

## 🔒 Security Features

### Port Configuration
- **25** - SMTP
- **143** - IMAP
- **587** - SMTP Submission
- **993** - IMAPS
- **4190** - Sieve
- **80/443** - HTTP/HTTPS (Nginx)

### Protection Layers
- **Fail2Ban** - Automatic IP blocking for failed login attempts
- **SpamAssassin** - Advanced spam filtering with Bayesian learning
- **ClamAV** - Real-time virus scanning
- **Postgrey** - Greylisting to reduce spam
- **SSL/TLS** - Encryption for all connections

### Email Authentication
- **DKIM** - Digital signatures for email validation
- **SPF** - Sender Policy Framework
- **DMARC** - Domain-based Message Authentication

## 🐛 Troubleshooting

### Common Issues

**Port Conflicts:**
```bash
# Check what's using mail ports
sudo netstat -tulpn | grep -E ':(25|143|587|993)'

# Stop conflicting services
sudo systemctl stop postfix exim4 sendmail
```

**SSL Certificate Issues:**
```bash
# Test SSL configuration
sudo nginx -t

# Renew certificates manually
sudo certbot renew

# Check certificate status
sudo certbot certificates
```

**Service Issues:**
```bash
# Check container status
docker compose ps

# View service logs
./manage.sh logs mailserver

# Restart services
./manage.sh restart
```

### Log Files
```bash
# Docker container logs
./manage.sh logs mailserver
./manage.sh logs nginx

# System logs
sudo tail -f /var/log/nginx/error.log
sudo journalctl -u nginx -f

# Mail server logs
docker compose logs -f mailserver
```

### DNS Verification
```bash
# Verify DNS records
dig A mail.yourdomain.com
dig MX yourdomain.com
dig TXT yourdomain.com
dig TXT _dmarc.yourdomain.com
```

## 📊 Monitoring

### Real-time Monitoring
```bash
./manage.sh monitor
```
Shows:
- Docker service status
- System resource usage (CPU, Memory)
- Recent service logs
- Connection status

### Status Dashboard
```bash
./manage.sh status
```
Provides comprehensive overview:
- Service status (Docker containers)
- Email account list
- Connection testing
- Nginx status
- SSL certificate status

## 🔄 Backup & Recovery

### Automated Backups
```bash
# Create backup
./manage.sh backup

# Backup includes:
# - /var/mail (email data)
# - Server configuration
# - SSL certificates (/etc/letsencrypt)
# - User database (users.json)
# - Docker configurations
```

### Manual Backup
```bash
cd email-server-config
docker compose stop
tar -czf backup-$(date +%Y%m%d).tar.gz \
    mailserver-data/ \
    users.json \
    docker-compose.yml
docker compose start
```

### Restore Process
1. Stop services: `./manage.sh stop`
2. Extract backup to `email-server-config/`
3. Restore permissions if needed
4. Start services: `./manage.sh start`

## 🚀 Performance Optimization

### Resource Requirements
- **Minimum**: 2GB RAM, 10GB disk space
- **Recommended**: 4GB RAM, 20GB disk space
- **CPU**: 2+ cores for better performance

### Optimization Tips
1. **Enable SSD storage** for mail data
2. **Configure swap space** if RAM is limited
3. **Monitor disk usage** regularly
4. **Set up log rotation** to prevent disk filling
5. **Use monitoring** to track resource usage

## 🤝 Support

### Getting Help
1. **Check Status**: `./manage.sh status`
2. **View Logs**: `./manage.sh logs`
3. **Verify DNS**: Use provided DNS records
4. **Test Connections**: `./manage.sh monitor`

### Common Solutions
- **Emails not sending**: Check DNS records and port 587
- **Emails not receiving**: Verify MX records and port 993
- **SSL errors**: Renew certificates with `./manage.sh ssl-renew`
- **Login issues**: Reset password with `./manage.sh change-password`

### Debug Mode
For detailed debugging, check the generated log files in:
- `email-server-config/mailserver-data/logs/`
- `/var/log/nginx/`
- Docker container logs

## 📝 License

This project is provided as-is for educational and production use. Always backup your data before making significant changes to your email server configuration.

