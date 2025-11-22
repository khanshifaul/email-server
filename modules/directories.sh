#!/bin/bash

create_directories() {
    log_info "Creating configuration directories..."
    
    local directories=(
        "${CONFIG_DIR}"
        "${MAILSERVER_DATA_DIR}"
        "${MAILSERVER_DATA_DIR}/data"
        "${MAILSERVER_DATA_DIR}/state"
        "${MAILSERVER_DATA_DIR}/logs"
        "${MAILSERVER_DATA_DIR}/config"
        "${SSL_DIR}"
        "${DNS_CONFIG_DIR}"
        "/var/www/autoconfig/mail"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done

    log_success "Directories created"
}
