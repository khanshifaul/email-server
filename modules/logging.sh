#!/bin/bash

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# JSON output function
json_output() {
    local type="$1"
    local message="$2"
    local data="$3"
    if [ "$JSON_OUTPUT" = "true" ]; then
        if [ -n "$data" ]; then
            echo "{\"type\":\"$type\",\"message\":\"$message\",\"data\":$data}"
        else
            echo "{\"type\":\"$type\",\"message\":\"$message\"}"
        fi
    else
        case $type in
            "info") log_info "$message" ;;
            "success") log_success "$message" ;;
            "warning") log_warning "$message" ;;
            "error") log_error "$message" ;;
        esac
    fi
}
