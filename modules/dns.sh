#!/bin/bash

get_public_ip() {
    curl -s -4 ifconfig.me || echo "YOUR_SERVER_IP"
}

show_dns_table() {
    local server_ip="$1"
    
    log_info "DNS Configuration Required"
    echo
    echo "Before proceeding, configure these DNS records:"
    echo
    printf "+%-25s+%-30s+%-50s+\n" "-------------------------" "------------------------------" "--------------------------------------------------"
    printf "| %-23s | %-28s | %-48s |\n" "Record Type" "Name/Host" "Value/Points To"
    printf "+%-25s+%-30s+%-50s+\n" "-------------------------" "------------------------------" "--------------------------------------------------"
    
    # Primary domain records
    printf "| %-23s | %-28s | %-48s |\n" "A Record" "mail.${PRIMARY_DOMAIN}" "${server_ip}"
    printf "| %-23s | %-28s | %-48s |\n" "MX Record" "${PRIMARY_DOMAIN}" "10 mail.${PRIMARY_DOMAIN}"
    printf "| %-23s | %-28s | %-48s |\n" "TXT Record (SPF)" "${PRIMARY_DOMAIN}" "\"v=spf1 mx a ip4:${server_ip} ~all\""
    printf "| %-23s | %-28s | %-48s |\n" "TXT Record (DMARC)" "_dmarc.${PRIMARY_DOMAIN}" "\"v=DMARC1; p=quarantine; rua=mailto:admin@${PRIMARY_DOMAIN}\""
    printf "| %-23s | %-28s | %-48s |\n" "TXT Record (DKIM)" "default._domainkey.${PRIMARY_DOMAIN}" "\"v=DKIM1; k=rsa; p=[DKIM_KEY]\""
    
    # Additional domains
    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra ADDL_DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${ADDL_DOMAINS[@]}"; do
            printf "| %-23s | %-28s | %-48s |\n" "CNAME Record" "mail.${domain}" "mail.${PRIMARY_DOMAIN}."
            printf "| %-23s | %-28s | %-48s |\n" "MX Record" "${domain}" "10 mail.${PRIMARY_DOMAIN}."
            printf "| %-23s | %-28s | %-48s |\n" "TXT Record (SPF)" "${domain}" "\"v=spf1 mx a include:${PRIMARY_DOMAIN} ~all\""
        done
    fi
    
    printf "+%-25s+%-30s+%-50s+\n" "-------------------------" "------------------------------" "--------------------------------------------------"
    echo
    
    if [ "$NON_INTERACTIVE" = false ]; then
        # Default to "yes" when user presses Enter
        read -p "Continue with setup? (Y/n): " -n 1 -r
        echo
        # If empty (just Enter) or Y/y, continue. Only exit on explicit N/n
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z "$REPLY" ]]; then
            log_info "Setup cancelled by user."
            exit 0
        fi
    fi
}

generate_dns_config() {
    log_info "Generating DNS configuration..."
    local server_ip
    server_ip=$(get_public_ip)

    cat > "${DNS_CONFIG_DIR}/dns-records.txt" << EOF
=== DNS Configuration for ${PRIMARY_DOMAIN} ===
Server IP: ${server_ip}

A Records (Required):
mail.${PRIMARY_DOMAIN}.     IN  A     ${server_ip}

MX Record (Required):
${PRIMARY_DOMAIN}.          IN  MX    10 mail.${PRIMARY_DOMAIN}.

TXT Records (Required):
# SPF Record
${PRIMARY_DOMAIN}.          IN  TXT   "v=spf1 mx a ip4:${server_ip} ~all"

# DMARC Record
_dmarc.${PRIMARY_DOMAIN}.   IN  TXT   "v=DMARC1; p=quarantine; rua=mailto:admin@${PRIMARY_DOMAIN}"

# DKIM Record (To be generated after setup)
default._domainkey.${PRIMARY_DOMAIN}. IN TXT "v=DKIM1; k=rsa; p=YOUR_DKIM_KEY_HERE"
EOF

    # Additional domains
    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        echo "" >> "${DNS_CONFIG_DIR}/dns-records.txt"
        echo "=== Additional Domains ===" >> "${DNS_CONFIG_DIR}/dns-records.txt"
        IFS=',' read -ra DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${DOMAINS[@]}"; do
            cat >> "${DNS_CONFIG_DIR}/dns-records.txt" << EOF
Domain: ${domain}
CNAME Records:
mail.${domain}.      IN  CNAME mail.${PRIMARY_DOMAIN}.
MX Record:
${domain}.           IN  MX    10 mail.${PRIMARY_DOMAIN}.
TXT Records:
${domain}.           IN  TXT   "v=spf1 mx a include:${PRIMARY_DOMAIN} ~all"
_dmarc.${domain}.    IN  TXT   "v=DMARC1; p=quarantine; rua=mailto:admin@${PRIMARY_DOMAIN}"
EOF
        done
    fi

    create_dkim_generation_script
    log_success "DNS configuration generated"
}

create_dkim_generation_script() {
    cat > "${CONFIG_DIR}/generate-dkim.sh" << 'EOF'
#!/bin/bash
set -e

cd "$(dirname "$0")"
echo "Generating DKIM keys..."

# Wait for mailserver to be ready
wait_for_mailserver() {
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec mailserver echo "Ready" > /dev/null 2>&1; then
            echo "Mailserver is ready"
            return 0
        fi
        echo "Waiting for mailserver to start... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    echo "Warning: Mailserver is taking longer than expected to start. Continuing anyway..."
    return 0
}

wait_for_mailserver

# Generate DKIM keys
echo "Running DKIM key generation..."
docker compose exec mailserver setup config dkim

if [ $? -eq 0 ]; then
    echo "DKIM keys generated successfully!"
    extract_dkim_key
else
    echo "DKIM generation failed. Please check the mailserver logs."
    exit 1
fi

extract_dkim_key() {
    local primary_domain=$(grep "domainname:" docker-compose.yml | awk '{print $2}' | sed 's/["${}]//g')
    local domain="${primary_domain}"
    local dkim_file="./mailserver-data/config/opendkim/keys/${domain}/mail.txt"

    if [ ! -f "$dkim_file" ]; then
        dkim_file="./mailserver-data/config/opendkim/keys/${domain}/default.txt"
    fi

    if [ -f "$dkim_file" ]; then
        local DKIM_KEY=$(grep -o 'p=[^;)]*' "$dkim_file" | head -1 | sed 's/p=//g' | tr -d '\n\r" ' | sed 's/\\//g')

        if [ -n "$DKIM_KEY" ]; then
            echo "Extracted DKIM key (length: ${#DKIM_KEY} characters)"
            mkdir -p "../dns"

            cat > "../dns/dkim-record.txt" << DKIMEOF
=== DKIM Record for ${domain} ===
Name: default._domainkey.${domain}.
Type: TXT
Value: "v=DKIM1; k=rsa; p=$DKIM_KEY"

DNS Record:
default._domainkey.${domain}. IN TXT "v=DKIM1; k=rsa; p=$DKIM_KEY"
DKIMEOF

            echo "DKIM record saved to: ../dns/dkim-record.txt"
        else
            echo "Error: Could not extract DKIM key from file"
            exit 1
        fi
    else
        echo "Error: DKIM key file not found"
        exit 1
    fi
}
EOF

    chmod +x "${CONFIG_DIR}/generate-dkim.sh"
}

generate_autoconfig() {
    log_info "Generating email client autoconfiguration..."
    sudo mkdir -p /var/www/autoconfig/mail

    local server_ip
    server_ip=$(get_public_ip)

    generate_domain_autoconfig "${PRIMARY_DOMAIN}" "$server_ip"

    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        IFS=',' read -ra ADDL_DOMAINS <<< "$ADDITIONAL_DOMAINS"
        for domain in "${ADDL_DOMAINS[@]}"; do
            generate_domain_autoconfig "${domain}" "$server_ip"
        done
    fi

    log_success "Email client autoconfiguration generated"
}

generate_domain_autoconfig() {
    local domain="$1"
    local server_ip="$2"
    local autoconfig_file="/var/www/autoconfig/mail/config-v1.1.xml"

    sudo tee "$autoconfig_file" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<clientConfig version="1.1">
  <emailProvider id="${domain}">
    <domain>${domain}</domain>
    <displayName>${domain} Mail Server</displayName>
    <displayShortName>${domain}</displayShortName>
    <incomingServer type="imap">
      <hostname>mail.${domain}</hostname>
      <port>143</port>
      <socketType>STARTTLS</socketType>
      <username>%EMAILADDRESS%</username>
      <authentication>password-cleartext</authentication>
    </incomingServer>
    <incomingServer type="imap">
      <hostname>mail.${domain}</hostname>
      <port>993</port>
      <socketType>SSL</socketType>
      <username>%EMAILADDRESS%</username>
      <authentication>password-cleartext</authentication>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>mail.${domain}</hostname>
      <port>587</port>
      <socketType>STARTTLS</socketType>
      <username>%EMAILADDRESS%</username>
      <authentication>password-cleartext</authentication>
    </outgoingServer>
    <outgoingServer type="smtp">
      <hostname>mail.${domain}</hostname>
      <port>465</port>
      <socketType>SSL</socketType>
      <username>%EMAILADDRESS%</username>
      <authentication>password-cleartext</authentication>
    </outgoingServer>
  </emailProvider>
</clientConfig>
EOF

    sudo cp "$autoconfig_file" "/var/www/autoconfig/mail/config-v1.1.xml.${domain}"
}
