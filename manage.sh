#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/email-server-config"
USER_DB_FILE="${CONFIG_DIR}/users.json"

# Check if config directory exists
if [ ! -d "${CONFIG_DIR}" ]; then
    echo "Error: Configuration directory not found: ${CONFIG_DIR}"
    echo "Please run the setup script first: ./setup.sh"
    exit 1
fi

cd "${CONFIG_DIR}" || {
    echo "Error: Cannot enter configuration directory: ${CONFIG_DIR}"
    exit 1
}

# Get primary domain from docker-compose file
get_primary_domain() {
    if [ -f "docker-compose.yml" ]; then
        grep "domainname:" docker-compose.yml | head -1 | awk '{print $2}' | sed 's/${PRIMARY_DOMAIN:-.*}//g' | sed 's/["]//g'
    fi
}

PRIMARY_DOMAIN=$(get_primary_domain)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if docker compose is available
check_docker_compose() {
    if ! command -v docker > /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    if ! docker compose version > /dev/null 2>&1; then
        log_error "Docker Compose is not available"
        return 1
    fi
    return 0
}

# Password generation
generate_secure_password() {
    local length=${1:-16}
    openssl rand -base64 $length | tr -d '/+=' | cut -c1-$length
}

# User management functions
add_user_with_prompt() {
    local email="$1"
    local password="$2"
    local domain="$3"

    if [ -z "$email" ]; then
        read -p "Enter email address: " email
    fi

    if [ -z "$password" ]; then
        password=$(generate_secure_password 16)
        echo "Generated password: $password"
    fi

    if [ -z "$domain" ]; then
        domain=$(echo "$email" | cut -d@ -f2)
    fi

    log_info "Adding user: $email"

    if docker compose exec mailserver setup email add "$email" "$password" 2>/dev/null; then
        log_success "User $email created successfully"

        # Add to user database
        local is_admin="false"
        if [[ "$email" == admin@* ]]; then
            is_admin="true"
        fi

        # Update user database
        if [ -f "$USER_DB_FILE" ]; then
            jq --arg email "$email" \
               --arg password "$password" \
               --arg domain "$domain" \
               --argjson is_admin "$is_admin" \
               --arg created "$(date -Iseconds)" \
               '.users[$email] = {
                  "email": $email,
                  "password": $password,
                  "domain": $domain,
                  "is_admin": $is_admin,
                  "created": $created,
                  "last_modified": $created
                }' "$USER_DB_FILE" > "${USER_DB_FILE}.tmp" && mv "${USER_DB_FILE}.tmp" "$USER_DB_FILE"
        fi

        show_user_configuration "$email" "$password" "$domain"
    else
        log_error "Failed to create user $email"
        log_info "Make sure the mailserver container is running and the domain is configured"
    fi
}

change_user_password() {
    local email="$1"
    local new_password="$2"

    if [ -z "$email" ]; then
        read -p "Enter email address: " email
    fi

    if [ -z "$new_password" ]; then
        new_password=$(generate_secure_password 16)
        echo "Generated new password: $new_password"
    fi

    log_info "Changing password for: $email"

    if docker compose exec mailserver setup email update "$email" "$new_password" 2>/dev/null; then
        log_success "Password changed for $email"

        # Update user database
        if [ -f "$USER_DB_FILE" ]; then
            jq --arg email "$email" \
               --arg new_password "$new_password" \
               '.users[$email].password = $new_password |
                .users[$email].last_modified = "'$(date -Iseconds)'"' "$USER_DB_FILE" > "${USER_DB_FILE}.tmp" && mv "${USER_DB_FILE}.tmp" "$USER_DB_FILE"
        fi

        show_user_configuration "$email" "$new_password" "$(echo $email | cut -d@ -f2)"
    else
        log_error "Failed to change password for $email"
    fi
}

reset_admin_password() {
    local email="$1"

    if [ -z "$email" ]; then
        echo "Admin users:"
        if [ -f "$USER_DB_FILE" ]; then
            jq -r '.users | to_entries[] | select(.value.is_admin == true) | .key' "$USER_DB_FILE" 2>/dev/null || echo "No admin users found"
        else
            echo "No user database found"
        fi
        read -p "Enter admin email to reset: " email
    fi

    local new_password=$(generate_secure_password 16)

    log_info "Resetting password for admin: $email"

    if docker compose exec mailserver setup email update "$email" "$new_password" 2>/dev/null; then
        log_success "Admin password reset for $email"
        log_info "New password: $new_password"

        # Update user database
        if [ -f "$USER_DB_FILE" ]; then
            jq --arg email "$email" \
               --arg new_password "$new_password" \
               '.users[$email].password = $new_password |
                .users[$email].last_modified = "'$(date -Iseconds)'"' "$USER_DB_FILE" > "${USER_DB_FILE}.tmp" && mv "${USER_DB_FILE}.tmp" "$USER_DB_FILE"
        fi
    else
        log_error "Failed to reset admin password for $email"
    fi
}

show_user_configuration() {
    local email="$1"
    local password="$2"
    local domain="$3"

    echo
    echo "=== Email Client Configuration for $email ==="
    echo "Email Address: $email"
    echo "Password: $password"
    echo "Incoming Mail Server: mail.${domain:-$PRIMARY_DOMAIN}"
    echo "Outgoing Mail Server: mail.${domain:-$PRIMARY_DOMAIN}"
    echo "IMAP Port: 993 (SSL)"
    echo "SMTP Port: 587 (STARTTLS)"
    echo "Username: $email"
    echo "Authentication: Normal Password"
    echo "Autoconfig URL: https://mail.${domain:-$PRIMARY_DOMAIN}/.well-known/autoconfig/mail/config-v1.1.xml"
    echo "=============================================="
    echo
}

# Add domain management
add_domain() {
    local domain="$1"

    if [ -z "$domain" ]; then
        read -p "Enter domain to add: " domain
    fi

    log_info "Adding domain: $domain"

    if docker compose exec mailserver setup config domain add "$domain" 2>/dev/null; then
        log_success "Domain $domain added successfully"

        # Auto-create admin account for new domain
        read -p "Create admin account for $domain? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            add_user_with_prompt "admin@$domain" "" "$domain"
        fi
    else
        log_error "Failed to add domain $domain"
    fi
}

case "$1" in
    start)
        log_info "Starting all services..."
        if check_docker_compose; then
            docker compose up -d
            log_success "Services started"
        else
            log_error "Failed to start services"
            exit 1
        fi
        ;;
    stop)
        log_info "Stopping all services..."
        if check_docker_compose; then
            docker compose down
            log_success "Services stopped"
        else
            log_error "Failed to stop services"
            exit 1
        fi
        ;;
    restart)
        log_info "Restarting all services..."
        if check_docker_compose; then
            docker compose restart
            log_success "Services restarted"
        else
            log_error "Failed to restart services"
            exit 1
        fi
        ;;
    delete)
        echo -e "${RED}================================================${NC}"
        echo -e "${RED}  WARNING: This will DELETE everything!${NC}"
        echo -e "${RED}================================================${NC}"
        echo
        echo "This command will permanently remove:"
        echo "  • All Docker containers and volumes"
        echo "  • Configuration directory (${CONFIG_DIR})"
        echo "  • Nginx server configurations"
        echo "  • DNS configuration files"
        echo "  • All email data and user accounts"
        echo ""
        echo "Note: SSL certificates will NOT be removed."
        echo "      You can manually remove them later if needed."
        echo
        read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
        
        if [ "$confirmation" != "DELETE" ]; then
            log_info "Delete operation cancelled"
            exit 0
        fi
        
        log_info "Starting complete cleanup process..."
        
        # Stop and remove containers and volumes
        if check_docker_compose; then
            log_info "Stopping and removing containers and volumes..."
            if docker compose down -v; then
                log_success "Containers and volumes removed"
            else
                log_error "Failed to remove containers and volumes"
            fi
        fi
        
        # Return to script directory for cleanup
        cd "${SCRIPT_DIR}" || {
            log_error "Cannot return to script directory: ${SCRIPT_DIR}"
            exit 1
        }
        
        # Remove configuration directory
        if [ -d "${CONFIG_DIR}" ]; then
            log_info "Removing configuration directory: ${CONFIG_DIR}"
            if rm -rf "${CONFIG_DIR}"; then
                log_success "Configuration directory removed"
            else
                log_error "Failed to remove configuration directory"
            fi
        else
            log_info "Configuration directory not found, skipping..."
        fi
        
        # Remove nginx server configurations
        log_info "Removing nginx configurations..."
        nginx_config_found=false
        
        # Remove mail domain configs from sites-available and sites-enabled
        if [ -n "$PRIMARY_DOMAIN" ]; then
            for site_config in "/etc/nginx/sites-available/mail.$PRIMARY_DOMAIN" "/etc/nginx/sites-enabled/mail.$PRIMARY_DOMAIN"; do
                if [ -f "$site_config" ]; then
                    if sudo rm -f "$site_config"; then
                        log_success "Removed: $site_config"
                        nginx_config_found=true
                    else
                        log_error "Failed to remove: $site_config"
                    fi
                fi
            done
        fi
        
        # Remove autoconfig file
        autoconfig_file="/var/www/html/.well-known/autoconfig/mail/config-v1.1.xml"
        if [ -f "$autoconfig_file" ]; then
            if sudo rm -f "$autoconfig_file"; then
                log_success "Removed autoconfig file"
                nginx_config_found=true
            else
                log_error "Failed to remove autoconfig file"
            fi
        fi
        
        if [ "$nginx_config_found" = false ]; then
            log_info "No nginx configurations found for cleanup"
        else
            # Test and reload nginx if configs were removed
            if sudo nginx -t >/dev/null 2>&1; then
                sudo systemctl reload nginx 2>/dev/null && log_success "Nginx reloaded" || log_warning "Nginx reload failed"
            fi
        fi
        
        # Remove DNS configuration files
        log_info "Removing DNS configuration files..."
        dns_files_removed=false
        
        # Remove dns directory
        if [ -d "${SCRIPT_DIR}/dns" ]; then
            if rm -rf "${SCRIPT_DIR}/dns"; then
                log_success "DNS directory removed"
                dns_files_removed=true
            else
                log_error "Failed to remove DNS directory"
            fi
        fi
        
        # Remove generate-dkim script
        if [ -f "${SCRIPT_DIR}/generate-dkim.sh" ]; then
            if rm -f "${SCRIPT_DIR}/generate-dkim.sh"; then
                log_success "generate-dkim.sh removed"
                dns_files_removed=true
            else
                log_error "Failed to remove generate-dkim.sh"
            fi
        fi
        
        if [ "$dns_files_removed" = false ]; then
            log_info "No DNS configuration files found for cleanup"
        fi
        
        log_success "Complete cleanup finished! The email server has been fully removed."
        log_info "Note: You may need to manually remove any remaining DNS records from your domain provider."
        ;;
    status)
        echo "=== Docker Services Status ==="
        if check_docker_compose; then
            docker compose ps
        else
            echo "Docker Compose not available"
        fi

        echo ""
        echo "=== Email Accounts ==="
        if check_docker_compose && docker compose ps mailserver | grep -q "Up"; then
            docker compose exec mailserver setup email list 2>/dev/null || echo "Error listing users or mailserver not ready"
        else
            echo "Mailserver not running"
        fi

        echo ""
        echo "=== Connection Status ==="
        echo -n "IMAP (993): "
        nc -z localhost 993 >/dev/null 2>&1 && echo "✓" || echo "✗"

        echo -n "SMTP (587): "
        nc -z localhost 587 >/dev/null 2>&1 && echo "✓" || echo "✗"

        echo ""
        echo "=== Nginx Status ==="
        if systemctl is-active nginx > /dev/null 2>&1; then
            sudo systemctl status nginx --no-pager -l | head -10
        else
            echo "Nginx is not running"
        fi
        ;;
    logs)
        if ! check_docker_compose; then
            log_error "Docker Compose not available"
            exit 1
        fi

        if [ -z "$2" ]; then
            log_info "Showing logs for all services (Ctrl+C to exit)..."
            docker compose logs -f
        else
            log_info "Showing logs for $2 (Ctrl+C to exit)..."
            docker compose logs -f "$2"
        fi
        ;;
    add-user)
        add_user_with_prompt "$2" "$3" "$4"
        ;;

    change-password)
        change_user_password "$2" "$3"
        ;;

    reset-admin-password)
        reset_admin_password "$2"
        ;;

    add-domain)
        add_domain "$2"
        ;;

    list-users)
        echo "=== Email Users ==="
        if [ -f "$USER_DB_FILE" ]; then
            jq -r '.users | to_entries[] | "\(.key): \(.value.domain) [Admin: \(.value.is_admin)] Created: \(.value.created)"' "$USER_DB_FILE" 2>/dev/null || echo "No users found"
        else
            echo "No user database found"
        fi
        ;;

    user-config)
        local email="$2"

        if [ -z "$email" ]; then
            read -p "Enter email address: " email
        fi

        if [ -f "$USER_DB_FILE" ]; then
            local user_data=$(jq -r --arg email "$email" '.users[$email] // empty' "$USER_DB_FILE" 2>/dev/null)
            if [ -n "$user_data" ]; then
                local password=$(echo "$user_data" | jq -r '.password')
                local domain=$(echo "$user_data" | jq -r '.domain')
                show_user_configuration "$email" "$password" "$domain"
            else
                log_error "User $email not found"
            fi
        else
            log_error "User database not found"
        fi
        ;;

    dkim)
        if ! check_docker_compose; then
            log_error "Docker Compose not available"
            exit 1
        fi

        log_info "Generating DKIM keys..."
        docker compose exec mailserver setup config dkim
        log_success "DKIM keys generated"
        ;;

    ssl-renew)
        log_info "Renewing SSL certificates..."
        if sudo certbot renew; then
            sudo systemctl reload nginx 2>/dev/null || log_warning "Failed to reload nginx, but certificates were renewed"
            log_success "SSL certificates renewed"
        else
            log_error "SSL certificate renewal failed"
        fi
        ;;

    ssl-status)
        echo "=== SSL Certificate Status ==="
        sudo certbot certificates 2>/dev/null || echo "No Certbot certificates found or Certbot not installed"
        ;;

    dns-records)
        if [ -f "${SCRIPT_DIR}/dns/dns-records.txt" ]; then
            cat "${SCRIPT_DIR}/dns/dns-records.txt"
        else
            log_warning "DNS records file not found. Run the setup script first."
        fi
        ;;

    generate-dkim)
        if [ -f "./generate-dkim.sh" ]; then
            ./generate-dkim.sh
        else
            log_warning "generate-dkim.sh not found. Run the setup script first."
        fi
        ;;

    nginx-reload)
        log_info "Reloading nginx configuration..."
        if sudo nginx -t; then
            sudo systemctl reload nginx
            log_success "Nginx reloaded successfully"
        else
            log_error "Nginx configuration test failed"
        fi
        ;;

    nginx-status)
        echo "=== Nginx Status ==="
        sudo systemctl status nginx --no-pager -l
        ;;

    nginx-logs)
        log_info "Showing nginx logs (Ctrl+C to exit)..."
        sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
        ;;

    backup)
        BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"
        log_info "Creating backup in: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"

        # Backup mail data
        log_info "Backing up mail data..."
        if check_docker_compose && docker compose ps mailserver | grep -q "Up"; then
            docker compose exec mailserver tar czf - /var/mail > "$BACKUP_DIR/mail-data.tar.gz" 2>/dev/null || log_warning "Could not backup mail data"
        else
            log_warning "Mailserver not running, skipping mail data backup"
        fi

        # Backup configuration
        log_info "Backing up configuration..."
        cp -r ./mailserver-data/config "$BACKUP_DIR/" 2>/dev/null || log_warning "Could not backup configuration"

        # Backup SSL certificates
        log_info "Backing up SSL certificates..."
        sudo tar czf "$BACKUP_DIR/ssl-certs.tar.gz" /etc/letsencrypt 2>/dev/null || log_warning "Could not backup SSL certificates"

        # Backup user database
        log_info "Backing up user database..."
        cp "$USER_DB_FILE" "$BACKUP_DIR/" 2>/dev/null || log_warning "Could not backup user database"

        # Create backup info file
        cat > "$BACKUP_DIR/backup-info.txt" << EOF
Backup created: $(date)
Primary Domain: ${PRIMARY_DOMAIN:-Unknown}
Services: $(docker compose ps --services 2>/dev/null | tr '\n' ' ' || echo "unknown")
EOF

        log_success "Backup completed: $BACKUP_DIR"
        ;;

    monitor)
        log_info "Monitoring services (Ctrl+C to exit)..."
        if ! command -v watch > /dev/null; then
            log_error "watch command not found. Install with: sudo apt-get install procps"
            exit 1
        fi
        watch -n 5 '
            echo "=== Docker Services ==="
            docker compose ps 2>/dev/null || echo "Docker Compose not available"
            echo ""
            echo "=== System Resources ==="
            echo "CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk "{print 100 - \$1}")% | Memory: $(free -h | grep Mem | awk "{print \$3 \" / \" \$2}")"
            echo ""
            echo "=== Recent Logs ==="
            docker compose logs --tail=5 mailserver 2>/dev/null | tail -5 || echo "Cannot get logs"
        '
        ;;

    *)
        echo "Email Server Management"
        echo "Usage: $0 {command} [options]"
        echo ""
        echo "USER MANAGEMENT:"
        echo "  $0 add-user [email] [password] [domain]"
        echo "  $0 change-password [email] [new-password]"
        echo "  $0 reset-admin-password [email]"
        echo "  $0 list-users"
        echo "  $0 user-config [email]"
        echo "  $0 add-domain [domain]"
        echo ""
        echo "SERVICE MANAGEMENT:"
        echo "  $0 start                    # Start all services"
        echo "  $0 stop                     # Stop all services"
        echo "  $0 restart                  # Restart all services"
        echo "  $0 delete                   # COMPLETE CLEANUP (dangerous!)"
        echo "  $0 status                   # Show service status"
        echo "  $0 logs [service]           # Show service logs"
        echo "  $0 monitor                  # Monitor services in real-time"
        echo ""
        echo "MAINTENANCE:"
        echo "  $0 dkim                     # Generate DKIM keys"
        echo "  $0 ssl-renew               # Renew SSL certificates"
        echo "  $0 ssl-status              # Show SSL status"
        echo "  $0 dns-records             # Show DNS records"
        echo "  $0 generate-dkim           # Generate DKIM"
        echo "  $0 nginx-reload            # Reload nginx"
        echo "  $0 nginx-status            # Show nginx status"
        echo "  $0 nginx-logs              # Show nginx logs"
        echo "  $0 backup                  # Backup all data"
        echo ""
        echo "EXAMPLES:"
        echo "  $0 status                          # Show status"
        echo "  $0 add-user admin@domain.com pass123  # Add user"
        echo "  $0 backup                         # Create backup"
        echo "  $0 delete                         # WARNING: Complete cleanup"
        exit 1
        ;;
esac
