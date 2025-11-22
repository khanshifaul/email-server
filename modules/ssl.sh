#!/bin/bash

setup_ssl_certificates() {
    log_info "Setting up SSL certificates for all subdomains..."

    # Ensure webroot directory exists
    sudo mkdir -p /var/www/html/.well-known/acme-challenge

    # Process primary domain
    setup_domain_ssl "${PRIMARY_DOMAIN}"

    # Process additional domains
    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra ADDL_DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${ADDL_DOMAINS[@]}"; do
            setup_domain_ssl "${domain}"
        done
    fi

    create_ssl_renewal_script
}

setup_domain_ssl() {
    local domain="$1"

    # Check if certificate already exists
    local mail_cert="/etc/letsencrypt/live/mail.${domain}/fullchain.pem"

    if [ -f "$mail_cert" ]; then
        log_info "SSL certificate already exists for mail.${domain}, skipping..."
        return 0
    fi

    log_info "Requesting SSL certificate for mail.${domain}"

    if sudo certbot certonly --webroot -w /var/www/html \
        --email "${SSL_EMAIL}" --agree-tos --no-eff-email \
        -d "mail.${domain}"; then
        log_success "SSL certificate obtained for mail.${domain}"
    else
        log_error "Failed to obtain SSL certificate for mail.${domain}"
        log_info "You may need to configure DNS records first or use DNS validation"
    fi
}

create_ssl_renewal_script() {
    log_info "Creating SSL renewal script..."
    
    cat > "${CONFIG_DIR}/renew-ssl.sh" << 'EOF'
#!/bin/bash
echo "Renewing SSL certificates..."
sudo certbot renew
sudo systemctl reload nginx
echo "SSL certificates renewed"
EOF

    chmod +x "${CONFIG_DIR}/renew-ssl.sh"
    log_success "SSL renewal script created"
}
