#!/bin/bash

generate_docker_compose() {
    log_info "Creating Docker Compose configuration..."
    
    cat > "${DOCKER_COMPOSE_FILE}" << EOF
services:
  mailserver:
    image: docker.io/mailserver/docker-mailserver:latest
    container_name: mailserver
    hostname: mail
    domainname: ${PRIMARY_DOMAIN}
    restart: always
    stop_grace_period: 1m
    ports:
      - "25:25"    # SMTP
      - "143:143"  # IMAP
      - "587:587"  # Submission
      - "993:993"  # IMAPS
      - "4190:4190" # Sieve
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_FAIL2BAN=1
      - ENABLE_POSTGREY=1
      - ENABLE_SASLAUTHD=0
      - ONE_DIR=1
      - DMS_DEBUG=0
      - SSL_TYPE=letsencrypt
      - TLS_LEVEL=intermediate
      - PERMIT_DOCKER=host
      - ENABLE_MANAGESIEVE=1
      - SIEVE_PORT=4190
    volumes:
      - ./mailserver-data/data:/var/mail
      - ./mailserver-data/state:/var/mail-state
      - ./mailserver-data/logs:/var/log/mail
      - ./mailserver-data/config/:/tmp/docker-mailserver/
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - mail-network
    cap_add:
      - NET_ADMIN
      - SYS_PTRACE

networks:
  mail-network:
    driver: bridge
EOF

    log_success "Docker Compose file created (Docker will auto-assign subnet)"
}

start_core_services() {
    log_info "Starting core email server services..."
    cd "${CONFIG_DIR}"

    init_user_db

    log_info "Pulling Docker images..."
    docker compose pull

    log_info "Starting mailserver..."
    docker compose up -d mailserver

    log_success "Core services started successfully"
}

wait_for_services() {
    log_info "Waiting for services to be ready..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker compose ps mailserver | grep -q "Up" && \
           docker compose exec mailserver echo "Ready" > /dev/null 2>&1; then
            log_success "Mailserver is ready"
            return 0
        fi
        log_info "Waiting for services to start... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done

    log_warning "Services are taking longer than expected to start. Continuing anyway..."
    return 1
}

test_services() {
    log_info "Testing services..."
    
    # Test mailserver container
    if docker compose exec mailserver echo "Container responsive" > /dev/null 2>&1; then
        log_success "Mailserver container: ✓ Responsive"
    else
        log_error "Mailserver container: ✗ Not responsive"
    fi
    
    # Removed Postfix and Dovecot service checks as these services run inside
    # the Docker mailserver container and shouldn't be checked at the system level
}

generate_dkim_keys() {
    log_info "Generating DKIM keys..."
    
    # Wait for mailserver to be ready
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec mailserver echo "Ready" > /dev/null 2>&1; then
            break
        fi
        log_info "Waiting for mailserver to be ready for DKIM generation... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    if docker compose exec mailserver setup config dkim; then
        log_success "DKIM keys generated successfully"
        extract_dkim_records
    else
        log_warning "DKIM generation failed. You can generate it later with: ./manage.sh dkim"
    fi
}

extract_dkim_records() {
    log_info "Extracting DKIM records..."
    local domain="${PRIMARY_DOMAIN}"
    local dkim_file="./mailserver-data/config/opendkim/keys/${domain}/mail.txt"
    
    if [ ! -f "$dkim_file" ]; then
        dkim_file="./mailserver-data/config/opendkim/keys/${domain}/default.txt"
    fi
    
    if [ -f "$dkim_file" ]; then
        local DKIM_KEY=$(grep -o 'p=[^;)]*' "$dkim_file" | head -1 | sed 's/p=//g' | tr -d '\n\r" ' | sed 's/\\//g')
        
        if [ -n "$DKIM_KEY" ]; then
            mkdir -p "${DNS_CONFIG_DIR}"
            cat > "${DNS_CONFIG_DIR}/dkim-record.txt" << EOF
=== DKIM Record for ${domain} ===
Name: default._domainkey.${domain}.
Type: TXT
Value: "v=DKIM1; k=rsa; p=$DKIM_KEY"

DNS Record:
default._domainkey.${domain}. IN TXT "v=DKIM1; k=rsa; p=$DKIM_KEY"
EOF
            log_success "DKIM record saved to: ${DNS_CONFIG_DIR}/dkim-record.txt"
        else
            log_warning "Could not extract DKIM key from file"
        fi
    else
        log_warning "DKIM key file not found"
    fi
}
