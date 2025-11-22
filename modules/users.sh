#!/bin/bash

init_user_db() {
    if [ ! -f "$USER_DB_FILE" ]; then
        cat > "$USER_DB_FILE" << EOF
{
  "users": {},
  "domains": {},
  "metadata": {
    "encryption_key": "${ENCRYPTION_KEY:-"default-key-change-me"}",
    "created": "$(date -Iseconds)"
  }
}
EOF
    fi
}

add_user_to_db() {
    local email="$1"
    local password="$2"
    local domain="$3"
    local is_admin="${4:-false}"

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
}

auto_create_admin_accounts() {
    log_info "Auto-creating admin accounts for domains..."
    local domains=("$PRIMARY_DOMAIN")

    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra additional_domains <<< "$ADDITIONAL_DOMAINS"
        domains+=("${additional_domains[@]}")
    fi

    for domain in "${domains[@]}"; do
        local has_admin=false

        for account in "${EMAIL_ACCOUNTS[@]}"; do
            IFS=':' read -r user password account_domain <<< "$account"
            if [ "$user" = "admin" ] && [ "$account_domain" = "$domain" ]; then
                has_admin=true
                break
            fi
        done

        if [ "$has_admin" = false ]; then
            local admin_password=$(generate_secure_password 16)
            EMAIL_ACCOUNTS+=("admin:${admin_password}:${domain}")
            log_info "Auto-created admin account for ${domain}: admin@${domain}"
        fi
    done

    if [ ${#EMAIL_ACCOUNTS[@]} -eq 0 ]; then
        log_error "No email accounts configured"
        exit 1
    fi
}

setup_domains_and_accounts() {
    log_info "Configuring domains and mail server accounts..."

    setup_domain "${PRIMARY_DOMAIN}"

    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${DOMAINS[@]}"; do
            setup_domain "${domain}"
        done
    fi

    setup_email_accounts
}

setup_domain() {
    local domain="$1"
    log_info "Setting up domain: ${domain}"
    
    if docker compose exec mailserver setup domain add "${domain}" 2>/dev/null; then
        log_success "Domain configured: ${domain}"
    else
        log_warning "Failed to setup domain ${domain}, but continuing..."
    fi
}

setup_email_accounts() {
    for account in "${EMAIL_ACCOUNTS[@]}"; do
        IFS=':' read -r user password domain <<< "$account"
        local email="${user}@${domain}"
        log_info "Creating account: ${email}"

        if docker compose exec mailserver setup email add "${email}" "${password}" 2>/dev/null; then
            log_success "Created account: ${email}"

            local is_admin="false"
            if [ "$user" = "admin" ]; then
                is_admin="true"
            fi

            add_user_to_db "$email" "$password" "$domain" "$is_admin"
            show_user_configuration "$email" "$password" "$domain"
        else
            log_warning "Failed to create account ${email}, but continuing..."
        fi
    done
}

show_user_configuration() {
    local email="$1"
    local password="$2"
    local domain="$3"

    log_info "=== Configuration for ${email} ==="
    log_info "Email Address: ${email}"
    log_info "Password: ${password}"
    log_info "Incoming Mail Server: mail.${domain}"
    log_info "Outgoing Mail Server: mail.${domain}"
    log_info "IMAP Port: 993 (SSL)"
    log_info "SMTP Port: 587 (STARTTLS)"
    log_info "Username: ${email}"
    log_info "=================================="
}

generate_secure_password() {
    local length=${1:-16}
    openssl rand -base64 $length | tr -d '/+=' | cut -c1-$length
}

create_management_scripts() {
    log_info "Creating management scripts..."
    
    create_add_user_script
    create_backup_script
    
    log_success "Management scripts created"
}

create_add_user_script() {
    cat > "${CONFIG_DIR}/add-user.sh" << 'EOF'
#!/bin/bash
set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <email> <password>"
    exit 1
fi

email="$1"
password="$2"

cd "$(dirname "$0")"

# Extract domain from email
domain=$(echo "$email" | cut -d@ -f2)

# Add domain if it doesn't exist
docker compose exec mailserver setup domain add "$domain" 2>/dev/null || true

# Add user
if docker compose exec mailserver setup email add "$email" "$password"; then
    echo "User $email added successfully"
    
    # Add to user database if it exists
    if [ -f "users.json" ]; then
        jq --arg email "$email" \
           --arg password "$password" \
           --arg domain "$domain" \
           --argjson is_admin "false" \
           --arg created "$(date -Iseconds)" \
           '.users[$email] = {
              "email": $email,
              "password": $password,
              "domain": $domain,
              "is_admin": $is_admin,
              "created": $created,
              "last_modified": $created
            }' "users.json" > "users.json.tmp" && mv "users.json.tmp" "users.json"
    fi
else
    echo "Failed to add user $email"
    exit 1
fi
EOF

    chmod +x "${CONFIG_DIR}/add-user.sh"
}

create_backup_script() {
    cat > "${CONFIG_DIR}/backup.sh" << 'EOF'
#!/bin/bash
set -e

cd "$(dirname "$0")"
BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."
docker compose stop

tar -czf "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz" \
    ./mailserver-data/data \
    ./mailserver-data/state \
    ./mailserver-data/config \
    ./users.json

docker compose start

echo "Backup created: $BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
EOF

    chmod +x "${CONFIG_DIR}/backup.sh"
}
