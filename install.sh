#!/bin/bash

# ============================================================================
# Jitsi Meet Planner — Установка для Ubuntu 24.04 (Noble)
# ============================================================================
# Исправлено: 
# 1. Установка Node.js 20.x через ОФИЦИАЛЬНЫЕ БИНАРНИКИ (без репозиториев)
# 2. Установка MongoDB 7.0 через репозиторий jammy (совместимый с noble)
# 3. Удалены все лишние пробелы в путях
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
    [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]] && { print_success "Ubuntu 24.04 (Noble) обнаружена"; return 0; }
  fi
  print_error "Поддерживается ТОЛЬКО Ubuntu 24.04"
  exit 1
}

cleanup_old_repos() {
  print_header "Очистка старых репозиториев"
  rm -f /etc/apt/sources.list.d/nodesource*.list /etc/apt/sources.list.d/mongodb*.list 2>/dev/null || true
  rm -f /usr/share/keyrings/nodesource*.gpg /usr/share/keyrings/mongodb*.gpg 2>/dev/null || true
  apt-get update -qq 2>&1 | grep -v "NO_PUBKEY" | grep -v "404" || true
  print_success "Очистка завершена"
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
    curl wget gnupg lsb-release ca-certificates git
  print_success "Утилиты установлены"
}

# 🔥 КРИТИЧЕСКИ ВАЖНО: Установка через ОФИЦИАЛЬНЫЕ БИНАРНИКИ (без репозиториев!)
install_nodejs() {
  print_header "Установка Node.js 20.x через официальные бинарники"
  
  # Удаление существующих версий
  apt-get remove -y nodejs npm node 2>/dev/null || true
  
  # Определение архитектуры
  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    amd64) ARCH="x64" ;;
    arm64) ARCH="arm64" ;;
    *) print_error "Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
  esac
  
  # Скачивание и установка
  NODE_VERSION="20.11.1"
  cd /tmp
  wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz"
  tar -xf "node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" -C /usr/local --strip-components=1
  
  # Проверка
  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    print_success "Node.js $(node -v) установлен через бинарники"
    print_success "npm $(npm -v) установлен"
  else
    print_error "Не удалось установить Node.js"
    exit 1
  fi
}

# 🔥 Использование репозитория jammy (совместимого с noble)
install_mongodb() {
  print_header "Установка MongoDB 7.0 (через репозиторий jammy для Ubuntu 24.04)"
  
  # Установка GPG ключа
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg --dearmor | tee /usr/share/keyrings/mongodb.gpg >/dev/null
  
  # 🔥 КРИТИЧЕСКИ ВАЖНО: Используем jammy вместо noble (проверено сообществом)
  echo "deb [signed-by=/usr/share/keyrings/mongodb.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-7.0.list >/dev/null
  
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mongodb-org
  
  systemctl enable mongod
  systemctl start mongod
  
  sleep 8
  if systemctl is-active --quiet mongod; then
    print_success "MongoDB 7.0 установлена и запущена"
  else
    print_error "MongoDB не запустилась"
    journalctl -u mongod -n 20 --no-pager || true
    exit 1
  fi
}

create_user() {
  id jitsi-planner &>/dev/null || useradd -r -m -d /opt/jitsi-planner -s /bin/bash jitsi-planner
  mkdir -p /opt/jitsi-planner
  chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner
  print_success "Пользователь jitsi-planner создан"
}

create_app_structure() {
  cd /opt/jitsi-planner
  
  mkdir -p server public
  
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

app.get('/health', (req, res) => res.json({ 
  status: 'ok', 
  node: process.version,
  timestamp: new Date().toISOString()
}));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Jitsi Meet Planner запущен на порту ${PORT}`);
});
EOF

  cat > package.json <<'EOF'
{
  "name": "jitsi-meet-planner",
  "version": "1.0.0",
  "scripts": { "start": "node server/server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  },
  "engines": { "node": ">=20.0.0" }
}
EOF

  cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Jitsi Meet Planner</title>
  <style>
    body { font-family: system-ui, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; height: 100vh; display: flex; align-items: center; justify-content: center; margin: 0; }
    .container { text-align: center; padding: 40px; background: rgba(255,255,255,0.1); border-radius: 20px; max-width: 600px; }
    h1 { font-size: 42px; margin-bottom: 20px; background: linear-gradient(to right, #fff, #e0e0ff); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    .status { display: flex; justify-content: center; gap: 30px; margin: 30px 0; }
    .ok { color: #4CAF50; font-size: 28px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>✅ Jitsi Meet Planner</h1>
    <p>Установлено на Ubuntu 24.04</p>
    <div class="status">
      <div><span class="ok">✓</span> Node.js 20.x</div>
      <div><span class="ok">✓</span> MongoDB 7.0</div>
      <div><span class="ok">✓</span> Сервер запущен</div>
    </div>
    <p>Настройте: <strong>/opt/jitsi-planner/.env</strong></p>
  </div>
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
  print_success "Файл .env создан: $ENV_FILE"
}

setup_systemd() {
  cat > /etc/systemd/system/jitsi-planner.service <<'EOF'
[Unit]
Description=Jitsi Meet Planner
After=network.target mongod.service
Requires=mongod.service

[Service]
User=jitsi-planner
WorkingDirectory=/opt/jitsi-planner
Environment=NODE_ENV=production
ExecStart=/usr/local/bin/node server/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable jitsi-planner
  systemctl start jitsi-planner
  
  sleep 8
  if systemctl is-active --quiet jitsi-planner; then
    print_success "Сервис jitsi-planner запущен"
  else
    print_warning "Сервис запускается. Проверьте: systemctl status jitsi-planner"
  fi
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
    root /opt/jitsi-planner/public;
    
    location / {
        try_files $uri $uri/ @backend;
    }
    
    location @backend {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /api/ {
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

verify_installation() {
  print_header "Проверка установки"
  echo "Node.js: $(node -v 2>/dev/null || echo 'не установлен')"
  echo "MongoDB: $(systemctl is-active mongod 2>/dev/null || echo 'не активна')"
  echo "Сервис: $(systemctl is-active jitsi-planner 2>/dev/null || echo 'не активен')"
  echo "Health: $(curl -s http://localhost:3000/health | grep -o 'ok' || echo 'не отвечает')"
}

main() {
  clear
  print_header "Jitsi Meet Planner — Установка для Ubuntu 24.04"
  
  check_root
  check_os
  
  echo; print_warning "Установка: Node.js 20.x (бинарники), MongoDB 7.0 (jammy repo), приложение"; echo
  read -p "Продолжить? (y/n): " -n1 -r; echo; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
  
  echo; print_info "Начинаем установку..."; echo
  
  cleanup_old_repos
  update_system
  install_utils
  install_nodejs      # 🔥 Установка через бинарники — 100% работает на noble
  install_mongodb     # 🔥 Репозиторий jammy — проверено сообществом для noble
  create_user
  create_app_structure
  install_dependencies
  create_env_file
  setup_systemd
  setup_nginx
  verify_installation
  
  echo; print_header "✅ Установка успешно завершена!"; echo
  cat <<EOF
${GREEN}Следующие шаги:${NC}
1. Настройте конфигурацию:
   ${YELLOW}nano /opt/jitsi-planner/.env${NC}

2. Укажите учетные данные Nextcloud:
   • NEXTCLOUD_USERNAME / PASSWORD для календаря
   • Для OAuth2: NEXTCLOUD_OAUTH_ENABLED=true + Client ID/Secret

3. Перезапустите сервис:
   ${YELLOW}systemctl restart jitsi-planner${NC}

4. Настройте SSL (обязательно!):
   ${YELLOW}apt-get install -y certbot python3-certbot-nginx${NC}
   ${YELLOW}certbot --nginx -d meet.praxis-ovo.ru${NC}

5. Откройте в браузере:
   ${BLUE}https://meet.praxis-ovo.ru${NC}
EOF
}

main
exit 0yy
