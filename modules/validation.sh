#!/bin/bash

validate_domain() {
    local domain="$1"
    # Basic domain validation regex
    [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_account_format() {
    local account="$1"
    [[ "$account" =~ ^[^:]+:[^:]+:[^:]+$ ]]
}

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_system() {
    log_info "Validating system configuration..."
    
    # Check if we're running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root. It's recommended to run as a regular user with sudo privileges."
    fi
    
    # Check available disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
        log_error "Insufficient disk space. Need at least 1GB free."
        exit 1
    fi
    
    # Check memory
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [ "$total_mem" -lt 1048576 ]; then  # Less than 1GB
        log_warning "Low memory detected. Email server may perform poorly with less than 1GB RAM."
    fi
    
    log_success "System validation completed"
}
