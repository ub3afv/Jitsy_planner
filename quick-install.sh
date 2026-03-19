#!/bin/bash

# Быстрая установка Jitsi Meet Planner одной командой
# curl -sSL https://your-domain.com/install.sh | sudo bash

set -e

print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m✗ $1\033[0m"
}

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    print_error "Запустите с sudo: sudo bash quick-install.sh"
    exit 1
fi

print_success "Загрузка полного скрипта установки..."
curl -sSL https://raw.githubusercontent.com/yourusername/jitsi-meet-planner/main/install.sh -o /tmp/install.sh

chmod +x /tmp/install.sh

print_success "Запуск установки..."
bash /tmp/install.sh

print_success "Установка завершена!"
