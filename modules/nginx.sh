#!/bin/bash

setup_nginx() {
    log_info "Setting up nginx configuration..."
    
    # Create nginx config directory if it doesn't exist
    sudo mkdir -p /etc/nginx/sites-available
    sudo mkdir -p /etc/nginx/sites-enabled

    # Remove any existing mail server nginx config to avoid conflicts
    cleanup_existing_configs

    # Process primary domain
    setup_domain_nginx "${PRIMARY_DOMAIN}"

    # Process additional domains
    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra ADDL_DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${ADDL_DOMAINS[@]}"; do
            setup_domain_nginx "${domain}"
        done
    fi

    reload_nginx
}

cleanup_existing_configs() {
    sudo rm -f /etc/nginx/sites-enabled/mail-* 2>/dev/null || true
    sudo rm -f /etc/nginx/sites-available/mail-* 2>/dev/null || true
}

setup_domain_nginx() {
    local domain="$1"
    
    create_mail_nginx_block "$domain"
    log_success "Nginx server block created for ${domain}"
}

create_mail_nginx_block() {
    local domain="$1"
    local nginx_config="/etc/nginx/sites-available/mail.${domain}"

    sudo tee "$nginx_config" > /dev/null << EOF
# HTTP to HTTPS redirect for mail.${domain}
server {
    listen 80;
    listen [::]:80;
    server_name mail.${domain};

    # ACME challenge for Certbot
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# Main mail server - mail.${domain}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name mail.${domain};

    ssl_certificate /etc/letsencrypt/live/mail.${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mail.${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    # Email client autoconfig
    location /.well-known/autoconfig/ {
        alias /var/www/autoconfig/;
        default_type application/xml;
        add_header Access-Control-Allow-Origin "*";
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }

    # Serve simple info page
    location / {
        add_header Content-Type text/plain;
        return 200 'Mail Server ${domain}
This server handles email services (SMTP/IMAP).
';
    }
}
EOF

    # Enable the site
    sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/"
}

reload_nginx() {
    if sudo nginx -t; then
        sudo systemctl reload nginx
        log_success "Nginx configuration reloaded"
    else
        log_error "Nginx configuration test failed"
        exit 1
    fi
}
