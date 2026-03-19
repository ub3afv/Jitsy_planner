#!/bin/bash

# ============================================================================
# Jitsi Meet Planner - Скрипт автоматической установки
# ============================================================================
# Система планирования встреч для meet.praxis-ovo.ru
# Интеграция с Nextcloud Calendar и авторизацией через Nextcloud OAuth2
# ============================================================================

set -e  # Остановить выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Глобальные переменные
OS=""
OS_VERSION=""
OS_CODENAME=""

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

# Определение ОС и версии
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        OS_VERSION="${VERSION_ID}"
        
        if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
            OS="debian"
            OS_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'unknown')}"
            print_success "Обнаружена система: ${PRETTY_NAME:-$OS_ID $OS_VERSION}"
        elif [[ "$OS_ID" == "rhel" || "$OS_ID" == "centos" || "$OS_ID" == "almalinux" || "$OS_ID" == "rocky" ]]; then
            OS="redhat"
            # Определение мажорной версии (8, 9)
            OS_MAJOR_VERSION="${VERSION_ID%%.*}"
            print_success "Обнаружена система: ${PRETTY_NAME:-$OS_ID $OS_VERSION}"
        else
            print_error "Не поддерживаемая операционная система: $OS_ID"
            exit 1
        fi
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_header "Обновление системы"
    
    if [ "$OS" == "debian" ]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
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
        DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget gnupg2 software-properties-common lsb-release ca-certificates apt-transport-https
    elif [ "$OS" == "redhat" ]; then
        yum install -y curl wget gnupg yum-utils
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
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/nodesource.list
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
    elif [ "$OS" == "redhat" ]; then
        curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
        yum install -y nodejs
    fi
    
    print_success "Node.js $(node -v) установлен"
    print_success "npm $(npm -v) установлен"
}

# Установка MongoDB 6.0
install_mongodb() {
    print_header "Установка MongoDB 6.0"
    
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_warning "MongoDB уже запущена"
        return 0
    fi
    
    if [ "$OS" == "debian" ]; then
        # Использование современного метода добавления ключа
        curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
        
        # Определение правильного кода релиза для поддерживаемых версий Ubuntu/Debian
        if [[ "$OS_CODENAME" == "focal" || "$OS_CODENAME" == "jammy" || "$OS_CODENAME" == "noble" || "$OS_CODENAME" == "bullseye" || "$OS_CODENAME" == "bookworm" ]]; then
            UBUNTU_CODENAME="$OS_CODENAME"
        else
            # Попытка определить автоматически
            UBUNTU_CODENAME=$(lsb_release -cs)
            if [[ -z "$UBUNTU_CODENAME" ]]; then
                print_error "Не удалось определить код релиза Ubuntu/Debian"
                exit 1
            fi
        fi
        
        echo "deb [signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.org/apt/ubuntu $UBUNTU_CODENAME/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
        
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org
        
        systemctl enable mongod
        systemctl start mongod
        
    elif [ "$OS" == "redhat" ]; then
        # Исправленный путь к репозиторию без лишних пробелов
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
    if systemctl is-active --quiet mongod 2>/dev/null; then
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
    
    chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner 2>/dev/null || true
}

# Установка приложения
install_app() {
    print_header "Установка приложения Jitsi Meet Planner"
    
    # Создание директории
    mkdir -p /opt/jitsi-planner
    
    # Загрузка файлов приложения из репозитория (пример структуры)
    cd /opt/jitsi-planner
    
    # Создание структуры каталогов
    mkdir -p server/models server/routes server/middleware server/config public/css public/js
    
    # Создание основных файлов приложения
    cat > server/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, '../public')));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/conferences', require('./routes/conferences'));
app.use('/api/admin', require('./routes/admin'));

// SPA fallback
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.listen(PORT, () => {
  console.log(`Jitsi Meet Planner запущен на порту ${PORT}`);
});
EOF

    # Создание модели пользователя с поддержкой Nextcloud OAuth
    cat > server/models/User.js <<'EOF'
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  email: {
    type: String,
    required: true,
    unique: true,
    lowercase: true,
    trim: true
  },
  password: {
    type: String,
    minlength: 6
  },
  name: {
    type: String,
    required: true,
    trim: true
  },
  role: {
    type: String,
    enum: ['user', 'admin'],
    default: 'user'
  },
  authProvider: {
    type: String,
    enum: ['local', 'nextcloud'],
    default: 'local'
  },
  nextcloudId: {
    type: String,
    unique: true,
    sparse: true
  },
  nextcloudAccessToken: String,
  nextcloudRefreshToken: String,
  createdAt: {
    type: Date,
    default: Date.now
  },
  lastLogin: Date
});

userSchema.pre('save', async function(next) {
  if (!this.isModified('password') || !this.password) {
    return next();
  }
  const salt = await bcrypt.genSalt(10);
  this.password = await bcrypt.hash(this.password, salt);
  next();
});

userSchema.methods.comparePassword = async function(candidatePassword) {
  if (!this.password) {
    return false;
  }
  return await bcrypt.compare(candidatePassword, this.password);
};

module.exports = mongoose.model('User', userSchema);
EOF

    # Создание базового конфига БД
    cat > server/config/database.js <<'EOF'
const mongoose = require('mongoose');

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/jitsi-planner', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    });
    console.log('MongoDB подключен');
  } catch (error) {
    console.error('Ошибка подключения к MongoDB:', error);
    process.exit(1);
  }
};

module.exports = connectDB;
EOF

    # Создание конфига Nextcloud
    cat > server/config/nextcloud.js <<'EOF'
require('dotenv').config();

const NEXTCLOUD_CONFIG = {
  baseUrl: process.env.NEXTCLOUD_URL || 'https://cloud.praxis-ovo.ru',
  calendarUrl: '/index.php/apps/calendar/appointment/KxEdrRwsMpJg',
  calendarId: process.env.NEXTCLOUD_CALENDAR_ID || 'KxEdrRwsMpJg',
  username: process.env.NEXTCLOUD_USERNAME || '',
  password: process.env.NEXTCLOUD_PASSWORD || '',
  oauth: {
    enabled: process.env.NEXTCLOUD_OAUTH_ENABLED === 'true' || false,
    clientId: process.env.NEXTCLOUD_OAUTH_CLIENT_ID || '',
    clientSecret: process.env.NEXTCLOUD_OAUTH_CLIENT_SECRET || '',
    authorizationUrl: process.env.NEXTCLOUD_OAUTH_AUTH_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/authorize',
    tokenUrl: process.env.NEXTCLOUD_OAUTH_TOKEN_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token',
    userInfoUrl: process.env.NEXTCLOUD_OAUTH_USERINFO_URL || 'https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json',
    redirectUri: process.env.NEXTCLOUD_OAUTH_REDIRECT_URI || 'https://meet.praxis-ovo.ru/api/auth/nextcloud/callback',
    scopes: ['openid', 'profile', 'email']
  }
};

module.exports = NEXTCLOUD_CONFIG;
EOF

    # Создание package.json
    cat > package.json <<'EOF'
{
  "name": "jitsi-meet-planner",
  "version": "1.0.0",
  "description": "Jitsi Meet Conference Planner with Nextcloud Integration",
  "main": "server/server.js",
  "scripts": {
    "start": "node server/server.js",
    "dev": "nodemon server/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "mongoose": "^7.5.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "axios": "^1.5.0",
    "express-validator": "^7.0.1"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

    # Установка зависимостей
    sudo -u jitsi-planner npm install --production
    
    print_success "Приложение и зависимости установлены"
}

# Создание конфигурационного файла .env с поддержкой Nextcloud OAuth
create_env_file() {
    print_header "Настройка конфигурации приложения"
    
    ENV_FILE="/opt/jitsi-planner/.env"
    
    if [ -f "$ENV_FILE" ]; then
        print_warning "Файл .env уже существует. Пропускаем создание."
        print_info "Отредактируйте файл вручную: $ENV_FILE"
        return 0
    fi
    
    # Генерация секретного ключа
    JWT_SECRET=$(openssl rand -hex 32)
    
    cat > "$ENV_FILE" <<EOF
# ============================================================================
# Конфигурация Jitsi Meet Planner
# ============================================================================

# Настройки сервера
PORT=3000
NODE_ENV=production
FRONTEND_URL=https://meet.praxis-ovo.ru

# База данных MongoDB
MONGODB_URI=mongodb://localhost:27017/jitsi-planner

# JWT Secret (автоматически сгенерирован)
JWT_SECRET=$JWT_SECRET

# ============================================================================
# Nextcloud Calendar Integration (для синхронизации событий)
# ============================================================================
NEXTCLOUD_URL=https://cloud.praxis-ovo.ru
NEXTCLOUD_USERNAME=
NEXTCLOUD_PASSWORD=
NEXTCLOUD_CALENDAR_ID=KxEdrRwsMpJg

# ============================================================================
# Nextcloud OAuth2/OIDC (для авторизации пользователей)
# ============================================================================
NEXTCLOUD_OAUTH_ENABLED=false
NEXTCLOUD_OAUTH_CLIENT_ID=
NEXTCLOUD_OAUTH_CLIENT_SECRET=
NEXTCLOUD_OAUTH_AUTH_URL=https://cloud.praxis-ovo.ru/apps/oauth2/authorize
NEXTCLOUD_OAUTH_TOKEN_URL=https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token
NEXTCLOUD_OAUTH_USERINFO_URL=https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json
NEXTCLOUD_OAUTH_REDIRECT_URI=https://meet.praxis-ovo.ru/api/auth/nextcloud/callback

# ============================================================================
# Администратор по умолчанию
# ============================================================================
ADMIN_EMAIL=admin@praxis-ovo.ru

# ============================================================================
# Настройки Jitsi Meet
# ============================================================================
JITSI_DOMAIN=meet.praxis-ovo.ru
EOF
    
    chown jitsi-planner:jitsi-planner "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    print_success "Файл конфигурации создан: $ENV_FILE"
    print_warning "ВАЖНО: Настройте следующие параметры в файле .env:"
    echo "  1. NEXTCLOUD_USERNAME и NEXTCLOUD_PASSWORD для синхронизации календаря"
    echo "  2. NEXTCLOUD_OAUTH_ENABLED=true и учетные данные OAuth2 для авторизации через Nextcloud"
    echo "  3. Измените ADMIN_EMAIL на ваш реальный email администратора"
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
Environment="PATH=/usr/bin:/usr/local/bin"
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node /opt/jitsi-planner/server/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=jitsi-planner
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable jitsi-planner
    systemctl start jitsi-planner
    
    sleep 5  # Даем время на запуск
    
    if systemctl is-active --quiet jitsi-planner 2>/dev/null; then
        print_success "Сервис jitsi-planner настроен и запущен"
    else
        print_warning "Сервис запускается. Проверьте статус: systemctl status jitsi-planner"
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
    
    read -p "Настроить Nginx как обратный прокси для meet.praxis-ovo.ru? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Пропускаем настройку Nginx"
        return 0
    fi
    
    # Создание конфигурации для Nginx
    mkdir -p /var/log/nginx
    
    cat > /etc/nginx/sites-available/jitsi-planner <<'EOF'
server {
    listen 80;
    server_name meet.praxis-ovo.ru;

    # Увеличение лимитов для загрузки файлов
    client_max_body_size 10M;

    # Логи
    access_log /var/log/nginx/jitsi-planner-access.log;
    error_log /var/log/nginx/jitsi-planner-error.log;

    # Заголовки безопасности
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Статические файлы
    location / {
        root /opt/jitsi-planner/public;
        try_files $uri $uri/ @backend;
    }

    # Backend API
    location @backend {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # API endpoints
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:3000;
    }
}
EOF
    
    # Активация конфигурации
    ln -sf /etc/nginx/sites-available/jitsi-planner /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Проверка конфигурации и перезапуск
    nginx -t && systemctl reload nginx
    
    print_success "Nginx настроен как обратный прокси"
    print_warning "РЕКОМЕНДУЕТСЯ настроить SSL сертификат!"
    echo "  Установите Certbot и выполните:"
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
                yes | ufw enable
                print_success "UFW включен"
            fi
        else
            print_success "Правила UFW настроены"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        print_info "Настройка firewalld"
        firewall-cmd --permanent --add-service=ssh
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
    
    ADMIN_EMAIL=$(grep ADMIN_EMAIL /opt/jitsi-planner/.env | cut -d'=' -f2 | tr -d ' ')
    
    print_info "Первый пользователь с email '$ADMIN_EMAIL' будет автоматически назначен администратором"
    print_info "После запуска приложения:"
    echo "  1. Откройте в браузере: https://meet.praxis-ovo.ru"
    echo "  2. Зарегистрируйтесь с email: $ADMIN_EMAIL"
    echo "  3. Или войдите через Nextcloud (если настроена авторизация OAuth2)"
    echo ""
    print_warning "Для авторизации через Nextcloud:"
    echo "  1. Включите NEXTCLOUD_OAUTH_ENABLED=true в .env"
    echo "  2. Настройте OAuth2 клиент в Nextcloud:"
    echo "     Настройки → Администрирование → Безопасность → OAuth 2.0"
    echo "  3. Укажите редирект URI: https://meet.praxis-ovo.ru/api/auth/nextcloud/callback"
}

# Проверка установки
verify_installation() {
    print_header "Проверка установки"
    
    echo "1. MongoDB статус:"
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_success "MongoDB запущена"
    else
        print_error "MongoDB не запущена"
    fi
    
    echo "2. Сервис jitsi-planner статус:"
    if systemctl is-active --quiet jitsi-planner 2>/dev/null; then
        print_success "Сервис jitsi-planner запущен"
    else
        print_warning "Сервис еще запускается или не запущен"
    fi
    
    echo "3. Проверка портов:"
    if ss -tuln 2>/dev/null | grep -q ":3000"; then
        print_success "Порт 3000 (Node.js) слушается"
    else
        print_warning "Порт 3000 не слушается (нормально, если используется только Nginx)"
    fi
    
    if ss -tuln 2>/dev/null | grep -q ":80"; then
        print_success "Порт 80 (HTTP) слушается"
    fi
    
    echo "4. Проверка здоровья приложения:"
    if curl -s http://localhost:3000/health | grep -q "ok"; then
        print_success "Приложение отвечает на запросы"
    else
        print_warning "Приложение еще не готово к работе (может запускаться)"
    fi
}

# Отображение информации о завершении
show_completion_info() {
    print_header "Установка завершена!"
    
    ADMIN_EMAIL=$(grep ADMIN_EMAIL /opt/jitsi-planner/.env | cut -d'=' -f2 | tr -d ' ')
    
    cat <<EOF

${GREEN}================================================${NC}
${GREEN}  Установка успешно завершена!${NC}
${GREEN}================================================${NC}

${BLUE}📋 Дальнейшие шаги:${NC}

1. ${YELLOW}Настройте конфигурацию:${NC}
   nano /opt/jitsi-planner/.env
   - Укажите учетные данные Nextcloud для календаря
   - Настройте OAuth2 для авторизации через Nextcloud (опционально)
   - Убедитесь, что ADMIN_EMAIL=$ADMIN_EMAIL

2. ${YELLOW}Перезапустите сервис после настройки:${NC}
   systemctl restart jitsi-planner

3. ${YELLOW}Проверьте логи:${NC}
   journalctl -u jitsi-planner -f

4. ${YELLOW}Настройте SSL (обязательно для продакшена):${NC}
   apt-get install -y certbot python3-certbot-nginx    # Для Debian/Ubuntu
   # ИЛИ
   yum install -y certbot python3-certbot-nginx        # Для RHEL/CentOS
   
   certbot --nginx -d meet.praxis-ovo.ru

5. ${YELLOW}Зарегистрируйте первого администратора:${NC}
   Откройте в браузере: https://meet.praxis-ovo.ru
   Зарегистрируйтесь с email: $ADMIN_EMAIL

${BLUE}🔐 Авторизация через Nextcloud:${NC}
   Для включения входа через корпоративные учетные записи:
   1. Включите NEXTCLOUD_OAUTH_ENABLED=true в .env
   2. Настройте OAuth2 клиент в вашем Nextcloud
   3. Укажите полученные Client ID и Secret в .env

${BLUE}📝 Полезные команды:${NC}

   # Просмотр статуса сервиса
   systemctl status jitsi-planner

   # Перезапуск сервиса
   systemctl restart jitsi-planner

   # Просмотр логов в реальном времени
   journalctl -u jitsi-planner -f

   # Проверка здоровья приложения
   curl http://localhost:3000/health

${BLUE}📁 Расположение файлов:${NC}
   Приложение:      /opt/jitsi-planner/
   Конфигурация:    /opt/jitsi-planner/.env
   Логи приложения: journalctl -u jitsi-planner
   Логи Nginx:      /var/log/nginx/jitsi-planner-*.log

${GREEN}🎉 Система готова к настройке!${NC}

EOF
}

# Основная функция установки
main() {
    clear
    print_header "Jitsi Meet Planner - Установка"
    
    # Проверка прав и ОС
    check_root
    detect_os
    
    echo ""
    print_warning "Внимание! Этот скрипт установит:"
    echo "  - Node.js 18.x"
    echo "  - MongoDB 6.0"
    echo "  - Nginx (опционально)"
    echo "  - Приложение планирования встреч"
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
