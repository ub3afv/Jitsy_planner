#!/bin/bash

# ============================================================================
# Jitsi Meet Planner - Скрипт автоматической установки
# ============================================================================
# Система планирования встреч для meet.praxis-ovo.ru
# Интеграция с Nextcloud Calendar
# ============================================================================

set -e  # Остановить выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции вывода
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Проверка прав суперпользователя
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Скрипт должен запускаться с правами суперпользователя (sudo)"
        exit 1
    fi
    print_success "Проверка прав суперпользователя пройдена"
}

# Проверка ОС
check_os() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
        print_success "Обнаружена система на базе Debian/Ubuntu"
    elif [ -f /etc/redhat-release ]; then
        OS="redhat"
        print_success "Обнаружена система на базе RedHat/CentOS/Fedora"
    else
        print_error "Не поддерживаемая операционная система"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_header "Обновление системы"
    
    if [ "$OS" == "debian" ]; then
        apt-get update
        apt-get upgrade -y
        print_success "Система обновлена"
    elif [ "$OS" == "redhat" ]; then
        yum update -y
        print_success "Система обновлена"
    fi
}

# Установка необходимых утилит
install_utils() {
    print_header "Установка вспомогательных утилит"
    
    if [ "$OS" == "debian" ]; then
        apt-get install -y curl wget gnupg2 software-properties-common
    elif [ "$OS" == "redhat" ]; then
        yum install -y curl wget gnupg
    fi
    
    print_success "Вспомогательные утилиты установлены"
}

# Установка Node.js
install_nodejs() {
    print_header "Установка Node.js 18.x"
    
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        print_warning "Node.js уже установлен: $NODE_VERSION"
        
        read -p "Хотите обновить до последней версии 18.x? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Пропускаем установку Node.js"
            return 0
        fi
    fi
    
    if [ "$OS" == "debian" ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
    elif [ "$OS" == "redhat" ]; then
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        yum install -y nodejs
    fi
    
    print_success "Node.js $(node -v) установлен"
    print_success "npm $(npm -v) установлен"
}

# Установка MongoDB
install_mongodb() {
    print_header "Установка MongoDB 6.0"
    
    if systemctl is-active --quiet mongod; then
        print_warning "MongoDB уже запущена"
        return 0
    fi
    
    if [ "$OS" == "debian" ]; then
        wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
        
        echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
        
        apt-get update
        apt-get install -y mongodb-org
        
        systemctl enable mongod
        systemctl start mongod
        
    elif [ "$OS" == "redhat" ]; then
        cat > /etc/yum.repos.d/mongodb-org-6.0.repo <<EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF
        
        yum install -y mongodb-org
        
        systemctl enable mongod
        systemctl start mongod
    fi
    
    # Проверка статуса MongoDB
    if systemctl is-active --quiet mongod; then
        print_success "MongoDB 6.0 установлена и запущена"
    else
        print_error "MongoDB не запустилась. Проверьте статус: systemctl status mongod"
        exit 1
    fi
}

# Создание пользователя и группы
create_user() {
    print_header "Создание пользователя для приложения"
    
    if id "jitsi-planner" &>/dev/null; then
        print_warning "Пользователь jitsi-planner уже существует"
    else
        useradd -r -m -d /opt/jitsi-planner -s /bin/bash jitsi-planner
        print_success "Пользователь jitsi-planner создан"
    fi
    
    chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner
}

# Установка приложения
install_app() {
    print_header "Установка приложения Jitsi Meet Planner"
    
    # Создание директории
    mkdir -p /opt/jitsi-planner
    
    # Копирование файлов (если запускается из директории проекта)
    if [ -f "server/server.js" ]; then
        cp -r . /opt/jitsi-planner/
        print_info "Файлы приложения скопированы в /opt/jitsi-planner"
    else
        print_warning "Локальные файлы не найдены. Пожалуйста, скопируйте файлы приложения в /opt/jitsi-planner вручную"
        print_info "Или клонируйте репозиторий:"
        echo "  cd /opt/jitsi-planner"
        echo "  git clone <your-repo-url> ."
    fi
    
    # Установка зависимостей
    cd /opt/jitsi-planner
    sudo -u jitsi-planner npm install
    
    print_success "Зависимости npm установлены"
}

# Создание конфигурационного файла .env
create_env_file() {
    print_header "Настройка конфигурации приложения"
    
    ENV_FILE="/opt/jitsi-planner/.env"
    
    if [ -f "$ENV_FILE" ]; then
        print_warning "Файл .env уже существует. Пропускаем создание."
        print_info "Отредактируйте файл вручную: $ENV_FILE"
        return 0
    fi
    
    cat > "$ENV_FILE" <<EOF
# ============================================================================
# Конфигурация Jitsi Meet Planner
# ============================================================================
# Настройки сервера
PORT=3000
NODE_ENV=production

# База данных MongoDB
MONGODB_URI=mongodb://localhost:27017/jitsi-planner

# JWT Secret (ИЗМЕНИТЕ НА СВОЙ СЕКРЕТНЫЙ КЛЮЧ!)
JWT_SECRET=$(openssl rand -hex 32)

# Nextcloud Calendar Integration
NEXTCLOUD_USERNAME=
NEXTCLOUD_PASSWORD=
NEXTCLOUD_CALENDAR_ID=KxEdrRwsMpJg

# Администратор по умолчанию
ADMIN_EMAIL=admin@praxis-ovo.ru

# Настройки Jitsi Meet
JITSI_DOMAIN=meet.praxis-ovo.ru
EOF
    
    chown jitsi-planner:jitsi-planner "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    print_success "Файл конфигурации создан: $ENV_FILE"
    print_warning "НЕ ЗАБУДЬТЕ:"
    echo "  1. Указать учетные данные Nextcloud в $ENV_FILE"
    echo "  2. Изменить JWT_SECRET на свой уникальный ключ"
    echo "  3. Указать правильный email администратора"
}

# Настройка systemd сервиса
setup_systemd_service() {
    print_header "Настройка systemd сервиса"
    
    cat > /etc/systemd/system/jitsi-planner.service <<EOF
[Unit]
Description=Jitsi Meet Planner Service
After=network.target mongod.service
Requires=mongod.service

[Service]
Type=exec
User=jitsi-planner
Group=jitsi-planner
WorkingDirectory=/opt/jitsi-planner
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node /opt/jitsi-planner/server/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=jitsi-planner

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable jitsi-planner
    systemctl start jitsi-planner
    
    if systemctl is-active --quiet jitsi-planner; then
        print_success "Сервис jitsi-planner настроен и запущен"
    else
        print_error "Сервис не запустился. Проверьте логи: journalctl -u jitsi-planner -f"
        exit 1
    fi
}

# Настройка Nginx (опционально)
setup_nginx() {
    print_header "Настройка Nginx (опционально)"
    
    if ! command -v nginx &> /dev/null; then
        print_warning "Nginx не установлен. Пропускаем настройку."
        print_info "Для установки Nginx выполните:"
        if [ "$OS" == "debian" ]; then
            echo "  apt-get install -y nginx"
        else
            echo "  yum install -y nginx"
        fi
        return 0
    fi
    
    read -p "Настроить Nginx как обратный прокси? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Пропускаем настройку Nginx"
        return 0
    fi
    
    cat > /etc/nginx/sites-available/jitsi-planner <<EOF
server {
    listen 80;
    server_name meet.praxis-ovo.ru;

    # Увеличение лимитов для загрузки файлов
    client_max_body_size 10M;

    # Логи
    access_log /var/log/nginx/jitsi-planner-access.log;
    error_log /var/log/nginx/jitsi-planner-error.log;

    # Статические файлы
    location / {
        root /opt/jitsi-planner/public;
        try_files \$uri \$uri/ @backend;
    }

    # Backend API
    location @backend {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    # API endpoints
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
    
    # Активация конфигурации
    ln -sf /etc/nginx/sites-available/jitsi-planner /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Проверка конфигурации и перезапуск
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx настроен как обратный прокси"
    print_warning "НЕ ЗАБУДЬТЕ настроить SSL сертификат!"
    echo "  Рекомендуется использовать Let's Encrypt:"
    echo "  certbot --nginx -d meet.praxis-ovo.ru"
}

# Настройка файрвола
setup_firewall() {
    print_header "Настройка файрвола"
    
    if command -v ufw &> /dev/null; then
        print_info "Настройка UFW (Uncomplicated Firewall)"
        ufw allow 22/tcp    # SSH
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        ufw allow 3000/tcp  # Node.js (если не используется Nginx)
        
        # Включить файрвол, если он выключен
        if ! ufw status | grep -q "Status: active"; then
            print_warning "Файрвол UFW выключен. Включить?"
            read -p "Включить UFW? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ufw enable
                print_success "UFW включен"
            fi
        else
            print_success "Правила UFW настроены"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        print_info "Настройка firewalld"
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=3000/tcp
        firewall-cmd --reload
        print_success "firewalld настроен"
    else
        print_warning "Файрвол не обнаружен. Настройте его вручную."
    fi
}

# Создание первого администратора
create_admin_user() {
    print_header "Создание первого администратора"
    
    print_info "Первый пользователь с email ADMIN_EMAIL будет автоматически назначен администратором"
    print_info "Зарегистрируйтесь на сайте после запуска приложения"
    echo ""
    print_warning "ADMIN_EMAIL из .env: $(grep ADMIN_EMAIL /opt/jitsi-planner/.env | cut -d'=' -f2)"
}

# Проверка установки
verify_installation() {
    print_header "Проверка установки"
    
    echo "1. MongoDB статус:"
    if systemctl is-active --quiet mongod; then
        print_success "MongoDB запущена"
    else
        print_error "MongoDB не запущена"
    fi
    
    echo "2. Сервис jitsi-planner статус:"
    if systemctl is-active --quiet jitsi-planner; then
        print_success "Сервис jitsi-planner запущен"
    else
        print_error "Сервис jitsi-planner не запущен"
    fi
    
    echo "3. Проверка портов:"
    if ss -tuln | grep -q ":3000"; then
        print_success "Порт 3000 (Node.js) слушается"
    else
        print_warning "Порт 3000 не слушается"
    fi
    
    if ss -tuln | grep -q ":80"; then
        print_success "Порт 80 (HTTP) слушается"
    fi
    
    echo "4. Логи последних событий:"
    journalctl -u jitsi-planner -n 20 --no-pager
}

# Отображение информации о завершении
show_completion_info() {
    print_header "Установка завершена!"
    
    cat <<EOF

${GREEN}================================================${NC}
${GREEN}  Установка успешно завершена!${NC}
${GREEN}================================================${NC}

${BLUE}📋 Дальнейшие шаги:${NC}

1. ${YELLOW}Настройте конфигурацию:${NC}
   nano /opt/jitsi-planner/.env
   - Укажите учетные данные Nextcloud
   - Измените JWT_SECRET
   - Укажите правильный ADMIN_EMAIL

2. ${YELLOW}Перезапустите сервис:${NC}
   systemctl restart jitsi-planner

3. ${YELLOW}Проверьте логи:${NC}
   journalctl -u jitsi-planner -f

4. ${YELLOW}Настройте SSL (рекомендуется):${NC}
   certbot --nginx -d meet.praxis-ovo.ru

5. ${YELLOW}Зарегистрируйте первого администратора:${NC}
   Откройте в браузере: http://meet.praxis-ovo.ru
   Зарегистрируйтесь с email: $(grep ADMIN_EMAIL /opt/jitsi-planner/.env | cut -d'=' -f2)

${BLUE}📝 Полезные команды:${NC}

   # Просмотр статуса сервиса
   systemctl status jitsi-planner

   # Перезапуск сервиса
   systemctl restart jitsi-planner

   # Просмотр логов в реальном времени
   journalctl -u jitsi-planner -f

   # Остановка сервиса
   systemctl stop jitsi-planner

   # Запуск сервиса
   systemctl start jitsi-planner

${BLUE}📁 Расположение файлов:${NC}
   Приложение:      /opt/jitsi-planner/
   Конфигурация:    /opt/jitsi-planner/.env
   Логи приложения: journalctl -u jitsi-planner
   Логи Nginx:      /var/log/nginx/jitsi-planner-*.log

${GREEN}🎉 Система готова к использованию!${NC}

EOF
}

# Основная функция установки
main() {
    clear
    print_header "Jitsi Meet Planner - Установка"
    
    # Проверка прав и ОС
    check_root
    check_os
    
    echo ""
    print_warning "Внимание! Этот скрипт установит:"
    echo "  - Node.js 18.x"
    echo "  - MongoDB 6.0"
    echo "  - Nginx (опционально)"
    echo "  - Зависимости приложения"
    echo ""
    
    read -p "Продолжить установку? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Установка отменена"
        exit 0
    fi
    
    # Последовательная установка компонентов
    update_system
    install_utils
    install_nodejs
    install_mongodb
    create_user
    install_app
    create_env_file
    setup_systemd_service
    setup_nginx
    setup_firewall
    create_admin_user
    verify_installation
    
    # Завершение
    show_completion_info
}

# Запуск установки
main

exit 0
