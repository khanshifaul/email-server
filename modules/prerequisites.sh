#!/bin/bash

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        missing_tools+=("docker-compose")
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    # Check curl
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    # Check nginx
    if ! command -v nginx &> /dev/null; then
        missing_tools+=("nginx")
    fi

    # Check certbot
    if ! command -v certbot &> /dev/null; then
        missing_tools+=("certbot")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_info "Installing missing tools: ${missing_tools[*]}..."
        sudo apt-get update
        
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "docker")
                    install_docker
                    ;;
                "docker-compose")
                    install_docker_compose
                    ;;
                "jq"|"curl")
                    sudo apt-get install -y "$tool"
                    ;;
                "nginx")
                    sudo apt-get install -y nginx
                    ;;
                "certbot")
                    sudo apt-get install -y certbot python3-certbot-nginx
                    ;;
            esac
        done
    fi

    log_success "All prerequisites are met"
}

install_docker() {
    log_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
}

install_docker_compose() {
    log_info "Installing Docker Compose..."
    sudo apt-get install -y docker-compose-plugin
}

check_port_conflicts() {
    log_info "Checking for mail port conflicts..."
    local ports=("25" "143" "587" "993" "4190")
    local conflicts=()

    for port in "${ports[@]}"; do
        if ss -tulpn | grep ":$port " > /dev/null; then
            local service=$(ss -tulpn | grep ":$port " | awk '{print $6}')
            conflicts+=("Port $port: $service")
        fi
    done

    if [ ${#conflicts[@]} -gt 0 ]; then
        log_warning "Port conflicts detected:"
        for conflict in "${conflicts[@]}"; do
            log_warning "  $conflict"
        done
        handle_port_conflicts "${conflicts[@]}"
    else
        log_success "No mail port conflicts detected"
    fi
}

handle_port_conflicts() {
    local conflicts=("$@")
    
    if [[ " ${conflicts[@]} " =~ "Port 25:" ]]; then
        log_info "Stopping system mail services to free up port 25..."
        sudo systemctl stop postfix 2>/dev/null || true
        sudo systemctl stop sendmail 2>/dev/null || true
        sudo systemctl stop exim4 2>/dev/null || true
        sudo systemctl disable postfix 2>/dev/null || true
        sudo systemctl disable sendmail 2>/dev/null || true
        sudo systemctl disable exim4 2>/dev/null || true
    fi

    sleep 2

    # Check again
    local still_conflicts=()
    for port in "${ports[@]}"; do
        if ss -tulpn | grep ":$port " > /dev/null; then
            still_conflicts+=("$port")
        fi
    done

    if [ ${#still_conflicts[@]} -gt 0 ]; then
        log_error "Mail ports still in use: ${still_conflicts[*]}"
        log_info "You may need to manually stop the services using these ports."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

validate_system_resources() {
    log_info "Checking system resources..."
    
    local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local available_disk=$(df / | awk 'NR==2 {print $4}')
    
    if [ "$total_mem" -lt 2097152 ]; then
        log_warning "Low memory detected (less than 2GB). Email server may perform poorly."
    fi
    
    if [ "$available_disk" -lt 5242880 ]; then
        log_warning "Low disk space (less than 5GB). Consider freeing up space."
    fi
    
    log_success "System resources check completed"
}
