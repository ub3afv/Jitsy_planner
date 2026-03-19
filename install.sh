#!/bin/bash

# ============================================================================
# Jitsi Meet Planner — Установка для Ubuntu 24.04 (Noble)
# ============================================================================
# Исправлено: полная очистка старых репозиториев ПЕРЕД обновлением системы
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}================================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================================${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_root() {
  [ "$EUID" -ne 0 ] && { print_error "Запустите с sudo"; exit 1; }
  print_success "Проверка прав пройдена"
}

check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]] && { print_success "Ubuntu 24.04 (Noble) поддерживается"; return 0; }
  fi
  print_error "Поддерживается ТОЛЬКО Ubuntu 24.04"
  exit 1
}

# 🔥 КРИТИЧЕСКИ ВАЖНО: Очистка старых репозиториев ДО обновления системы
cleanup_old_repos() {
  print_header "Очистка старых репозиториев NodeSource/MongoDB"
  
  # Удаление ВСЕХ старых репозиториев NodeSource
  rm -f /etc/apt/sources.list.d/nodesource*.list /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
  rm -f /usr/share/keyrings/nodesource*.gpg /etc/apt/keyrings/nodesource*.gpg 2>/dev/null || true
  
  # Удаление старых репозиториев MongoDB
  rm -f /etc/apt/sources.list.d/mongodb*.list 2>/dev/null || true
  rm -f /usr/share/keyrings/mongodb*.gpg 2>/dev/null || true
  
  # Принудительное обновление списка пакетов БЕЗ ошибок
  apt-get update -qq 2>&1 | grep -v "NO_PUBKEY" | grep -v "404" || true
  
  print_success "Старые репозитории удалены"
}

update_system() {
  print_header "Обновление системы"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
  print_success "Система обновлена"
}

install_utils() {
  print_header "Установка утилит"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget gnupg lsb-release ca-certificates apt-transport-https git
  print_success "Утилиты установлены"
}

install_nodejs() {
  print_header "Установка Node.js 20.x (официальная поддержка Ubuntu 24.04)"
  
  # Установка ключа и репозитория 20.x
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
  
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x noble main" | \
    tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  
  apt-get update -qq 2>&1 | grep -v "NO_PUBKEY" || true
  
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
  
  print_success "Node.js $(node -v) установлен"
  print_success "npm $(npm -v) установлен"
}

install_mongodb() {
  print_header "Установка MongoDB 7.0 (официальная поддержка Ubuntu 24.04)"
  
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg --dearmor | tee /usr/share/keyrings/mongodb.gpg >/dev/null
  
  echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/7.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-7.0.list >/dev/null
  
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mongodb-org
  
  systemctl enable mongod
  systemctl start mongod
  
  sleep 5
  systemctl is-active mongod && print_success "MongoDB 7.0 установлена" || {
    print_error "MongoDB не запустилась"
    exit 1
  }
}

create_user() {
  id jitsi-planner &>/dev/null || useradd -r -m -d /opt/jitsi-planner -s /bin/bash jitsi-planner
  mkdir -p /opt/jitsi-planner
  chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner
  print_success "Пользователь создан"
}

create_app_structure() {
  cd /opt/jitsi-planner
  
  mkdir -p server/{models,routes,middleware,config} public/{css,js}
  
  # Минимальный рабочий сервер
  cat > server/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors({ origin: process.env.FRONTEND_URL || '*', credentials: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

app.get('/health', (req, res) => res.json({ status: 'ok', node: process.version }));

app.listen(PORT, '0.0.0.0', () => console.log(`Jitsi Meet Planner запущен на порту ${PORT}`));
EOF

  # package.json
  cat > package.json <<'EOF'
{
  "name": "jitsi-meet-planner",
  "version": "1.0.0",
  "scripts": { "start": "node server/server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  }
}
EOF

  # Простая главная страница
  mkdir -p public
  cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Jitsi Meet Planner</title></head>
<body style="font-family: sans-serif; text-align: center; padding: 50px;">
  <h1>✅ Jitsi Meet Planner установлен</h1>
  <p>Ubuntu 24.04 • Node.js 20.x • MongoDB 7.0</p>
  <p>Настройте /opt/jitsi-planner/.env и перезапустите сервис</p>
</body>
</html>
EOF

  print_success "Структура приложения создана"
}

install_dependencies() {
  cd /opt/jitsi-planner
  sudo -u jitsi-planner npm install --production
  print_success "Зависимости установлены"
}

create_env_file() {
  ENV_FILE="/opt/jitsi-planner/.env"
  [ -f "$ENV_FILE" ] && cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
  
  cat > "$ENV_FILE" <<EOF
PORT=3000
NODE_ENV=production
FRONTEND_URL=https://meet.praxis-ovo.ru
MONGODB_URI=mongodb://localhost:27017/jitsi-planner
JWT_SECRET=$(openssl rand -hex 32)
NEXTCLOUD_URL=https://cloud.praxis-ovo.ru
NEXTCLOUD_CALENDAR_ID=KxEdrRwsMpJg
NEXTCLOUD_OAUTH_ENABLED=false
ADMIN_EMAIL=admin@praxis-ovo.ru
JITSI_DOMAIN=meet.praxis-ovo.ru
EOF
  
  chown jitsi-planner:jitsi-planner "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  print_success "Файл .env создан"
}

setup_systemd() {
  cat > /etc/systemd/system/jitsi-planner.service <<EOF
[Unit]
Description=Jitsi Meet Planner
After=network.target mongod.service
Requires=mongod.service

[Service]
User=jitsi-planner
WorkingDirectory=/opt/jitsi-planner
ExecStart=/usr/bin/node server/server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable jitsi-planner
  systemctl start jitsi-planner
  
  sleep 5
  systemctl is-active jitsi-planner && print_success "Сервис запущен" || \
    print_warning "Сервис запускается (проверьте: systemctl status jitsi-planner)"
}

setup_nginx() {
  if ! command -v nginx &>/dev/null; then
    read -p "Установить Nginx? (y/n): " -n1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
    apt-get install -y -qq nginx
  fi
  
  cat > /etc/nginx/sites-available/jitsi-planner <<'EOF'
server {
    listen 80;
    server_name meet.praxis-ovo.ru;
    location / {
        root /opt/jitsi-planner/public;
        try_files $uri $uri/ @backend;
    }
    location @backend {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
  
  ln -sf /etc/nginx/sites-available/jitsi-planner /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx -t && systemctl reload nginx && print_success "Nginx настроен"
}

main() {
  clear
  print_header "Jitsi Meet Planner — Установка для Ubuntu 24.04"
  
  check_root
  check_os
  
  echo; print_warning "Установка: Node.js 20.x, MongoDB 7.0, приложение"; echo
  read -p "Продолжить? (y/n): " -n1 -r; echo; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
  
  echo; print_info "Очистка системы от старых репозиториев..."; echo
  
  cleanup_old_repos    # 🔥 КРИТИЧЕСКИ ВАЖНО: сначала очистка!
  update_system
  install_utils
  install_nodejs
  install_mongodb
  create_user
  create_app_structure
  install_dependencies
  create_env_file
  setup_systemd
  setup_nginx
  
  echo; print_header "✅ Установка завершена!"; echo
  echo "1. Настройте конфигурацию:"
  echo "   nano /opt/jitsi-planner/.env"
  echo ""
  echo "2. Перезапустите сервис:"
  echo "   systemctl restart jitsi-planner"
  echo ""
  echo "3. Проверьте работу:"
  echo "   curl http://localhost:3000/health"
  echo ""
  echo "4. Настройте SSL (обязательно!):"
  echo "   apt-get install -y certbot python3-certbot-nginx"
  echo "   certbot --nginx -d meet.praxis-ovo.ru"
}

main
exit 0
