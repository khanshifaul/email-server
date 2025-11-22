#!/bin/bash
set -e

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/email-server-config"
DOCKER_COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
MAILSERVER_DATA_DIR="${CONFIG_DIR}/mailserver-data"
SSL_DIR="${CONFIG_DIR}/ssl"
DNS_CONFIG_DIR="${SCRIPT_DIR}/dns"
CERTS_DIR="/etc/letsencrypt"
USER_DB_FILE="${CONFIG_DIR}/users.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
PRIMARY_DOMAIN=""
ADDITIONAL_DOMAINS=""
EMAIL_ACCOUNTS=()
SSL_EMAIL=""
NON_INTERACTIVE=false
JSON_OUTPUT="false"
DOMAINS=""
USERS=""
PASSWORDS=""

# Source modules
for module in logging prerequisites directories docker ssl nginx dns users validation; do
    if [ -f "${SCRIPT_DIR}/modules/${module}.sh" ]; then
        source "${SCRIPT_DIR}/modules/${module}.sh"
    else
        echo -e "${RED}[ERROR]${NC} Module not found: ${module}.sh"
        exit 1
    fi
done

# Main execution function
main() {
    log_info "Starting Email Server Setup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate environment
    validate_environment
    
    # Get user input
    if [ "$NON_INTERACTIVE" = true ]; then
        setup_non_interactive
    else
        get_user_input
    fi
    
    # Show DNS configuration
    show_dns_configuration
    
    # Setup infrastructure
    setup_infrastructure
    
    # Start services
    start_services
    
    # Final configuration
    finalize_setup
    
    show_summary
    
    log_success "Email server setup completed successfully!"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -y|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -d|--domains)
                DOMAINS="$2"
                shift 2
                ;;
            -u|--users)
                USERS="$2"
                shift 2
                ;;
            -p|--passwords)
                PASSWORDS="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating environment..."
    check_prerequisites
    check_port_conflicts
    validate_system_resources
}

# Get user input interactively
get_user_input() {
    log_info "Gathering email server configuration..."
    get_primary_domain
    get_additional_domains
    get_email_accounts
    show_configuration_summary
}

get_primary_domain() {
    while true; do
        read -p "Primary domain (e.g., example.com): " PRIMARY_DOMAIN
        if [ -z "$PRIMARY_DOMAIN" ]; then
            log_error "Primary domain is required"
            continue
        fi
        if ! validate_domain "$PRIMARY_DOMAIN"; then
            log_warning "Domain format may be invalid: $PRIMARY_DOMAIN"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        break
    done
    SSL_EMAIL="admin@${PRIMARY_DOMAIN}"
    log_info "SSL admin email set to: ${SSL_EMAIL}"
}

get_additional_domains() {
    log_info "Additional domains (comma-separated, leave empty if none):"
    read -p "Additional domains: " ADDITIONAL_DOMAINS
}

get_email_accounts() {
    log_info "Email accounts to create (format: user:password:domain, one per line, empty line to finish):"
    log_info "Example: admin:securepassword:${PRIMARY_DOMAIN}"
    
    while true; do
        read -p "Account (user:password:domain) or empty to finish: " account
        if [ -z "$account" ]; then
            break
        fi
        if validate_account_format "$account"; then
            EMAIL_ACCOUNTS+=("$account")
            log_info "Added account: $account"
        else
            log_error "Invalid format. Use user:password:domain"
        fi
    done
    auto_create_admin_accounts
}

show_configuration_summary() {
    echo
    log_info "Configuration Summary:"
    log_info "  Primary Domain: ${PRIMARY_DOMAIN}"
    log_info "  Additional Domains: ${ADDITIONAL_DOMAINS:-None}"
    log_info "  SSL Email: ${SSL_EMAIL}"
    log_info "  Accounts: ${#EMAIL_ACCOUNTS[@]} accounts configured"
    
    # Default to "yes" when user presses Enter
    read -p "Confirm these settings? (Y/n): " -n 1 -r
    echo
    # If empty (just Enter) or Y/y, continue. Only restart on explicit N/n
    if [[ "$REPLY" =~ ^[Nn]$ ]]; then
        log_info "Restarting configuration..."
        get_user_input
        return
    fi
    # If Y/y or Enter, continue with setup
}

# Non-interactive mode setup
setup_non_interactive() {
    log_info "Running in non-interactive mode"
    
    if [ -z "$DOMAINS" ] || [ -z "$USERS" ] || [ -z "$PASSWORDS" ]; then
        log_error "In non-interactive mode, --domains, --users, and --passwords are required"
        exit 1
    fi

    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    PRIMARY_DOMAIN="${DOMAIN_ARRAY[0]}"
    ADDITIONAL_DOMAINS=$(IFS=','; echo "${DOMAIN_ARRAY[*]:1}")

    IFS=',' read -ra USER_ARRAY <<< "$USERS"
    IFS=',' read -ra PASS_ARRAY <<< "$PASSWORDS"

    if [ ${#USER_ARRAY[@]} -ne ${#PASS_ARRAY[@]} ]; then
        log_error "Number of users and passwords must match"
        exit 1
    fi

    for i in "${!USER_ARRAY[@]}"; do
        EMAIL_ACCOUNTS+=("${USER_ARRAY[i]}:${PASS_ARRAY[i]}:${PRIMARY_DOMAIN}")
    done

    SSL_EMAIL="admin@${PRIMARY_DOMAIN}"
    auto_create_admin_accounts
}

# Setup infrastructure
setup_infrastructure() {
    log_info "Setting up infrastructure..."
    create_directories
    generate_docker_compose
    setup_ssl_certificates
    generate_autoconfig
    generate_dns_config
    setup_nginx
}

# Start and configure services
start_services() {
    log_info "Starting services..."
    start_core_services
    setup_domains_and_accounts
    generate_dkim_keys
}

# Final setup steps
finalize_setup() {
    log_info "Finalizing setup..."
    wait_for_services
    test_services
    create_management_scripts
}

# Show DNS configuration before proceeding
show_dns_configuration() {
    local server_ip
    server_ip=$(get_public_ip)
    show_dns_table "$server_ip"
}

# Display summary
show_summary() {
    local server_ip
    server_ip=$(get_public_ip)

    log_success "Email Server Setup Complete!"
    echo
    show_server_configuration "$server_ip"
    show_accounts_table
    show_client_configuration
    show_services_status
    show_ssl_status
    show_dkim_status
    show_next_steps
}

show_server_configuration() {
    local server_ip="$1"
    log_info "=== SERVER CONFIGURATION ==="
    log_info "Primary Domain: ${PRIMARY_DOMAIN}"
    log_info "Additional Domains: ${ADDITIONAL_DOMAINS:-None}"
    log_info "Server IP: ${server_ip}"
    log_info "SSL Admin Email: ${SSL_EMAIL}"
    echo
}

show_accounts_table() {
    log_info "=== EMAIL ACCOUNTS ==="
    printf "+%-25s+%-25s+%-15s+\n" "-------------------------" "-------------------------" "---------------"
    printf "| %-23s | %-23s | %-13s |\n" "Email Address" "Password" "Domain"
    printf "+%-25s+%-25s+%-15s+\n" "-------------------------" "-------------------------" "---------------"

    for account in "${EMAIL_ACCOUNTS[@]}"; do
        IFS=':' read -r user password domain <<< "$account"
        printf "| %-23s | %-23s | %-13s |\n" "${user}@${domain}" "${password}" "${domain}"
    done

    printf "+%-25s+%-25s+%-15s+\n" "-------------------------" "-------------------------" "---------------"
    echo
}

show_client_configuration() {
    log_info "=== CLIENT CONFIGURATION ==="
    log_info "Incoming (IMAP):"
    log_info "  Server: mail.${PRIMARY_DOMAIN}"
    log_info "  Port: 993"
    log_info "  Encryption: SSL/TLS"
    log_info "  Authentication: Normal Password"
    echo
    log_info "Outgoing (SMTP):"
    log_info "  Server: mail.${PRIMARY_DOMAIN}"
    log_info "  Port: 587"
    log_info "  Encryption: STARTTLS"
    log_info "  Authentication: Normal Password"
    echo
}

show_services_status() {
    log_info "=== SERVICES STATUS ==="
    if docker compose ps mailserver | grep -q "Up"; then
        log_success "Mail Server: ✓ Running"
    else
        log_error "Mail Server: ✗ Not running"
    fi
    if systemctl is-active --quiet nginx; then
        log_success "Nginx: ✓ Running"
    else
        log_error "Nginx: ✗ Not running"
    fi
    echo
}

show_ssl_status() {
    log_info "=== SSL STATUS ==="
    local ssl_domains=("${PRIMARY_DOMAIN}" ${ADDITIONAL_DOMAINS//,/ })
    for domain in "${ssl_domains[@]}"; do
        if [ -f "/etc/letsencrypt/live/mail.${domain}/fullchain.pem" ]; then
            log_success "SSL: Active for mail.${domain}"
        else
            log_warning "SSL: Not configured for mail.${domain}"
        fi
    done
    echo
}

show_dkim_status() {
    log_info "=== DKIM STATUS ==="
    if [ -f "${DNS_CONFIG_DIR}/dkim-record.txt" ]; then
        log_success "DKIM: Generated successfully"
        log_info "DKIM Record saved to: ${DNS_CONFIG_DIR}/dkim-record.txt"
    else
        log_warning "DKIM: Not generated - run ./generate-dkim.sh manually"
    fi
    echo
}

show_next_steps() {
    log_info "=== NEXT STEPS ==="
    log_info "1. Configure DNS records from ${DNS_CONFIG_DIR}/dns-records.txt"
    log_info "2. Configure email clients with the settings above"
    log_info "3. Update DNS with DKIM record"
    log_info "4. Test email sending and receiving"
    echo
    log_info "=== MANAGEMENT COMMANDS ==="
    log_info "Start/Stop: cd ${CONFIG_DIR} && docker compose {start|stop|restart}"
    log_info "SSL Renew: ${CONFIG_DIR}/renew-ssl.sh"
    log_info "Add User: ${CONFIG_DIR}/add-user.sh"
    log_info "View Logs: cd ${CONFIG_DIR} && docker compose logs mailserver"
    echo
    log_warning "IMPORTANT: Save the email account passwords shown above. They won't be displayed again."
    log_info "Configuration directory: ${CONFIG_DIR}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]
Setup a complete email server with docker-mailserver, nginx, and SSL.

OPTIONS:
    -h, --help          Show this help message
    -y, --non-interactive  Run in non-interactive mode
    -d, --domains DOMAINS  Comma-separated list of domains (non-interactive mode)
    -u, --users USERS    Comma-separated list of users (non-interactive mode)
    -p, --passwords PASSWORDS Comma-separated list of passwords (non-interactive mode)
    --json              Output in JSON format

EXAMPLES:
    # Interactive mode
    $0

    # Non-interactive mode
    $0 --non-interactive --domains "example.com,domain2.com" --users "admin,user1" --passwords "pass1,pass2"

FEATURES:
    - Complete email server with docker-mailserver
    - Automatic SSL with Let's Encrypt
    - DNS configuration helper
    - User management system
    - Nginx reverse proxy
EOF
}

# Run main function
main "$@"
