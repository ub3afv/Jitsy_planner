#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Проверка прав
if [ "$EUID" -ne 0 ]; then 
    print_error "Запустите с sudo"
    exit 1
fi

clear
echo -e "${RED}========================================${NC}"
echo -e "${RED}  УДАЛЕНИЕ Jitsi Meet Planner${NC}"
echo -e "${RED}========================================${NC}"
echo ""

print_warning "Внимание! Это удалит:"
echo "  - Сервис jitsi-planner"
echo "  - Пользователя jitsi-planner"
echo "  - Файлы приложения (/opt/jitsi-planner)"
echo "  - Конфигурацию Nginx"
echo "  - Базу данных MongoDB (jitsi-planner)"
echo ""
print_warning "Данные будут УДАЛЕНЫ безвозвратно!"

read -p "Продолжить удаление? (YES чтобы подтвердить): " -r
if [[ ! $REPLY =~ ^YES$ ]]; then
    print_warning "Удаление отменено"
    exit 0
fi

echo ""
echo "Остановка сервисов..."

# Остановка сервиса
if systemctl is-active --quiet jitsi-planner; then
    systemctl stop jitsi-planner
    systemctl disable jitsi-planner
    print_success "Сервис остановлен"
fi

# Удаление конфигурации Nginx
if [ -f /etc/nginx/sites-available/jitsi-planner ]; then
    rm -f /etc/nginx/sites-available/jitsi-planner
    rm -f /etc/nginx/sites-enabled/jitsi-planner
    systemctl reload nginx 2>/dev/null || true
    print_success "Конфигурация Nginx удалена"
fi

# Удаление сервиса systemd
if [ -f /etc/systemd/system/jitsi-planner.service ]; then
    rm -f /etc/systemd/system/jitsi-planner.service
    systemctl daemon-reload
    print_success "Сервис systemd удален"
fi

# Удаление пользователя
if id "jitsi-planner" &>/dev/null; then
    userdel -r jitsi-planner 2>/dev/null || true
    print_success "Пользователь jitsi-planner удален"
fi

# Удаление файлов приложения
if [ -d /opt/jitsi-planner ]; then
    rm -rf /opt/jitsi-planner
    print_success "Файлы приложения удалены"
fi

# Удаление базы данных MongoDB
print_warning "Удаление базы данных MongoDB..."
mongo jitsi-planner --eval "db.dropDatabase()" 2>/dev/null || true
print_success "База данных удалена"

# Удаление логов
rm -f /var/log/nginx/jitsi-planner-*.log
print_success "Логи удалены"

# Удаление правил файрвола
if command -v ufw &> /dev/null; then
    ufw delete allow 3000/tcp 2>/dev/null || true
    print_success "Правила UFW удалены"
fi

if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --remove-port=3000/tcp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    print_success "Правила firewalld удалены"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Удаление завершено!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
print_warning "Если вы хотите полностью удалить MongoDB и Node.js,"
print_warning "выполните это вручную."
echo ""
