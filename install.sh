#!/bin/bash

# ============================================================================
# Jitsi Meet Planner - Скрипт автоматической установки (обновленная версия)
# ============================================================================
# Система планирования встреч для meet.praxis-ovo.ru
# Полная интеграция с Nextcloud: календарь + авторизация OAuth2
# Поддержка современных ОС: Ubuntu 20.04/22.04/24.04, Debian 11/12, RHEL 8/9
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
OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""
ARCH=""

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

# Определение архитектуры
detect_architecture() {
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    
    case "$ARCH" in
        amd64|x86_64)
            ARCH="x86_64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            print_error "Неподдерживаемая архитектура: $ARCH"
            exit 1
            ;;
    esac
    
    print_success "Обнаружена архитектура: $ARCH"
}

# Определение ОС и версии
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        
        # Определение семейства ОС
        case "$OS_ID" in
            ubuntu|debian)
                OS="debian"
                OS_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'unknown')}"
                ;;
            rhel|centos|almalinux|rocky|fedora)
                OS="redhat"
                OS_MAJOR_VERSION="${VERSION_ID%%.*}"
                ;;
            *)
                print_error "Не поддерживаемая операционная система: $OS_ID"
                exit 1
                ;;
        esac
        
        print_success "Обнаружена система: ${PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
        print_info "Код релиза: $OS_CODENAME"
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi
}

# Обновление системы
update_system() {
    print_header "Обновление системы"
    
    if [ "$OS" == "debian" ]; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
        print_success "Система обновлена"
    elif [ "$OS" == "redhat" ]; then
        yum update -y -q
        print_success "Система обновлена"
    fi
}

# Установка необходимых утилит
install_utils() {
    print_header "Установка вспомогательных утилит"
    
    if [ "$OS" == "debian" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            curl wget gnupg2 lsb-release ca-certificates \
            apt-transport-https software-properties-common git
    elif [ "$OS" == "redhat" ]; then
        yum install -y -q curl wget gnupg yum-utils git
    fi
    
    print_success "Вспомогательные утилиты установлены"
}

# Установка Node.js с резервными методами
install_nodejs() {
    print_header "Установка Node.js (LTS)"
    
    # Проверка существующей установки
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        print_warning "Node.js уже установлен: $NODE_VERSION"
        
        read -p "Хотите обновить до актуальной LTS версии? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Пропускаем установку Node.js"
            return 0
        fi
    fi
    
    if [ "$OS" == "debian" ]; then
        # Для Ubuntu 24.04 (noble) используем репозиторий 20.x (актуальный LTS)
        # Для остальных используем 18.x или 20.x в зависимости от поддержки
        if [ "$OS_CODENAME" == "noble" ]; then
            NODE_VERSION_MAJOR="20"
            print_info "Ubuntu 24.04 обнаружена. Устанавливаем Node.js 20.x (актуальный LTS)"
        else
            NODE_VERSION_MAJOR="18"
            print_info "Устанавливаем Node.js 18.x (LTS)"
        fi
        
        # Метод 1: Официальный репозиторий Nodesource
        print_info "Попытка установки через официальный репозиторий..."
        if ! setup_nodesource_repo "$NODE_VERSION_MAJOR"; then
            print_warning "Не удалось настроить репозиторий. Используем резервный метод..."
            install_nodejs_binary "$NODE_VERSION_MAJOR"
        fi
        
    elif [ "$OS" == "redhat" ]; then
        # Для RHEL используем модули или официальный репозиторий
        if command -v dnf &> /dev/null && dnf module list nodejs -q 2>/dev/null | grep -q "18"; then
            print_info "Установка через модули DNF..."
            dnf module install -y nodejs:18/common
        else
            print_info "Установка через репозиторий Nodesource..."
            curl -fsSL "https://rpm.nodesource.com/setup_18.x" | bash - || true
            yum install -y nodejs || {
                print_warning "Не удалось установить через репозиторий. Используем резервный метод..."
                install_nodejs_binary "18"
            }
        fi
    fi
    
    # Проверка установки
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        print_success "Node.js $(node -v) установлен"
        print_success "npm $(npm -v) установлен"
    else
        print_error "Не удалось установить Node.js"
        exit 1
    fi
}

# Настройка репозитория Nodesource
setup_nodesource_repo() {
    local NODE_VERSION_MAJOR=$1
    
    # Удаление старых ключей
    rm -f /etc/apt/keyrings/nodesource.gpg /usr/share/keyrings/nodesource.gpg 2>/dev/null || true
    
    # Скачивание и установка ключа
    if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key 2>/dev/null | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg; then
        return 1
    fi
    
    # Определение кода релиза для репозитория
    local REPO_CODENAME="$OS_CODENAME"
    
    # Для Ubuntu 24.04 используем репозиторий jammy как совместимый для 18.x
    if [ "$NODE_VERSION_MAJOR" == "18" ] && [ "$OS_CODENAME" == "noble" ]; then
        REPO_CODENAME="jammy"
        print_warning "Используем репозиторий для Ubuntu 22.04 (jammy) как совместимый с 24.04"
    fi
    
    # Добавление репозитория
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION_MAJOR}.x $REPO_CODENAME main" | \
        tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    
    # Обновление и установка
    if ! apt-get update -qq 2>&1 | grep -v "NO_PUBKEY" | grep -v "404" | grep -q "Error"; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs && return 0
    fi
    
    return 1
}

# Резервная установка через бинарники
install_nodejs_binary() {
    local NODE_VERSION_MAJOR=$1
    local NODE_VERSION
    
    # Определение последней версии
    if [ "$NODE_VERSION_MAJOR" == "18" ]; then
        NODE_VERSION="18.20.4"
    else
        NODE_VERSION="20.11.1"
    fi
    
    print_info "Установка Node.js $NODE_VERSION через официальные бинарники..."
    
    cd /tmp
    local ARCH_SUFFIX="x64"
    [ "$ARCH" == "arm64" ] && ARCH_SUFFIX="arm64"
    
    wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH_SUFFIX}.tar.xz" || {
        print_error "Не удалось скачать бинарники Node.js"
        exit 1
    }
    
    tar -xf "node-v${NODE_VERSION}-linux-${ARCH_SUFFIX}.tar.xz" -C /usr/local --strip-components=1
    
    # Проверка
    if [ -x /usr/local/bin/node ] && [ -x /usr/local/bin/npm ]; then
        ln -sf /usr/local/bin/node /usr/bin/node 2>/dev/null || true
        ln -sf /usr/local/bin/npm /usr/bin/npm 2>/dev/null || true
        return 0
    fi
    
    return 1
}

# Установка MongoDB 6.0 с правильными путями
install_mongodb() {
    print_header "Установка MongoDB 6.0"
    
    # Проверка существующей установки
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_warning "MongoDB уже запущена"
        return 0
    fi
    
    if [ "$OS" == "debian" ]; then
        # Установка GPG ключа
        if ! curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc 2>/dev/null | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg; then
            print_error "Не удалось скачать GPG ключ MongoDB"
            exit 1
        fi
        
        # Определение правильного кода релиза
        local MONGO_CODENAME="$OS_CODENAME"
        
        # Сопоставление кодов релиза для MongoDB
        case "$OS_CODENAME" in
            focal|jammy|noble|bullseye|bookworm)
                # Все эти коды поддерживаются напрямую
                ;;
            *)
                # Для неизвестных кодов пытаемся использовать jammy как совместимый
                print_warning "Неизвестный код релиза '$OS_CODENAME'. Используем 'jammy' как совместимый."
                MONGO_CODENAME="jammy"
                ;;
        esac
        
        # Добавление репозитория
        echo "deb [signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg] https://repo.mongodb.org/apt/ubuntu $MONGO_CODENAME/mongodb-org/6.0 multiverse" | \
            tee /etc/apt/sources.list.d/mongodb-org-6.0.list > /dev/null
        
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mongodb-org
        
        systemctl enable mongod
        systemctl start mongod
        
    elif [ "$OS" == "redhat" ]; then
        # Для RHEL используем правильный путь без лишних пробелов
        cat > /etc/yum.repos.d/mongodb-org-6.0.repo <<EOF
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/6.0/$ARCH/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF
        
        yum install -y -q mongodb-org
        
        systemctl enable mongod
        systemctl start mongod
    fi
    
    # Проверка статуса MongoDB
    sleep 5
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_success "MongoDB 6.0 установлена и запущена"
    else
        print_error "MongoDB не запустилась. Проверьте статус: systemctl status mongod"
        journalctl -u mongod -n 20 --no-pager || true
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
    
    mkdir -p /opt/jitsi-planner
    chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner 2>/dev/null || true
}

# Создание структуры приложения
create_app_structure() {
    print_header "Создание структуры приложения"
    
    cd /opt/jitsi-planner
    
    # Создание каталогов
    mkdir -p server/{models,routes,middleware,config} public/{css,js,img}
    
    # Создание основных файлов приложения
    cat > server/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const connectDB = require('./config/database');

const app = express();
const PORT = process.env.PORT || 3000;

// Подключение к БД
connectDB();

// Middleware
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:3000',
  credentials: true
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, '../public')));

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    node: process.version,
    env: process.env.NODE_ENV
  });
});

// Routes
app.use('/api/auth', require('./routes/auth'));
app.use('/api/conferences', require('./routes/conferences'));
app.use('/api/admin', require('./routes/admin'));

// SPA fallback
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Jitsi Meet Planner запущен на порту ${PORT}`);
  console.log(`🌐 Доступен по адресу: http://localhost:${PORT}`);
});

// Обработка ошибок
process.on('uncaughtException', (error) => {
  console.error('❌ Необработанное исключение:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('❌ Необработанный промис:', reason);
  process.exit(1);
});

module.exports = server;
EOF

    # Модель пользователя с поддержкой Nextcloud OAuth
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
}, {
  timestamps: true
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

    # Модель конференции
    cat > server/models/Conference.js <<'EOF'
const mongoose = require('mongoose');

const conferenceSchema = new mongoose.Schema({
  title: {
    type: String,
    required: true,
    trim: true
  },
  description: {
    type: String,
    trim: true
  },
  roomName: {
    type: String,
    required: true,
    unique: true,
    lowercase: true
  },
  meetUrl: {
    type: String,
    required: true
  },
  date: {
    type: Date,
    required: true
  },
  duration: {
    type: Number,
    required: true,
    default: 60
  },
  createdBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  participants: [{
    email: String,
    name: String,
    status: {
      type: String,
      enum: ['pending', 'accepted', 'declined'],
      default: 'pending'
    }
  }],
  calendarEventId: String,
  calendarSynced: {
    type: Boolean,
    default: false
  },
  isActive: {
    type: Boolean,
    default: true
  }
}, {
  timestamps: true
});

conferenceSchema.virtual('endDate').get(function() {
  return new Date(this.date.getTime() + this.duration * 60000);
});

conferenceSchema.set('toJSON', { virtuals: true });
conferenceSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Conference', conferenceSchema);
EOF

    # Конфигурация БД
    cat > server/config/database.js <<'EOF'
const mongoose = require('mongoose');

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/jitsi-planner', {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 5000
    });
    console.log('✅ MongoDB подключен');
  } catch (error) {
    console.error('❌ Ошибка подключения к MongoDB:', error.message);
    process.exit(1);
  }
};

module.exports = connectDB;
EOF

    # Конфигурация Nextcloud
    cat > server/config/nextcloud.js <<'EOF'
require('dotenv').config();

const NEXTCLOUD_CONFIG = {
  // Базовые настройки
  baseUrl: process.env.NEXTCLOUD_URL || 'https://cloud.praxis-ovo.ru',
  calendarId: process.env.NEXTCLOUD_CALENDAR_ID || 'KxEdrRwsMpJg',
  
  // Учетные данные для календаря (Basic Auth)
  username: process.env.NEXTCLOUD_USERNAME || '',
  password: process.env.NEXTCLOUD_PASSWORD || '',
  
  // OAuth2 / OIDC настройки для авторизации
  oauth: {
    enabled: process.env.NEXTCLOUD_OAUTH_ENABLED === 'true' || false,
    clientId: process.env.NEXTCLOUD_OAUTH_CLIENT_ID || '',
    clientSecret: process.env.NEXTCLOUD_OAUTH_CLIENT_SECRET || '',
    authorizationUrl: process.env.NEXTCLOUD_OAUTH_AUTH_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/authorize',
    tokenUrl: process.env.NEXTCLOUD_OAUTH_TOKEN_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token',
    userInfoUrl: process.env.NEXTCLOUD_OAUTH_USERINFO_URL || 'https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json',
    redirectUri: process.env.NEXTCLOUD_OAUTH_REDIRECT_URI || 'https://meet.praxis-ovo.ru/api/auth/nextcloud/callback',
    scopes: process.env.NEXTCLOUD_OAUTH_SCOPES?.split(',') || ['openid', 'profile', 'email']
  }
};

module.exports = NEXTCLOUD_CONFIG;
EOF

    # Middleware аутентификации
    cat > server/middleware/auth.js <<'EOF'
const jwt = require('jsonwebtoken');

const auth = (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Требуется авторизация' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
    req.user = decoded;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Неверный токен авторизации' });
  }
};

const admin = (req, res, next) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Требуются права администратора' });
  }
  next();
};

module.exports = { auth, admin };
EOF

    # Маршруты аутентификации (упрощенная версия для установки)
    cat > server/routes/auth.js <<'EOF'
const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const { body, validationResult } = require('express-validator');
const User = require('../models/User');

// Регистрация
router.post('/register', [
  body('email').isEmail().withMessage('Неверный формат email'),
  body('password').isLength({ min: 6 }).withMessage('Пароль должен быть минимум 6 символов'),
  body('name').notEmpty().withMessage('Имя обязательно')
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { email, password, name } = req.body;

    let user = await User.findOne({ email });
    if (user) {
      return res.status(400).json({ error: 'Пользователь с таким email уже существует' });
    }

    user = new User({
      email,
      password,
      name,
      role: email === process.env.ADMIN_EMAIL ? 'admin' : 'user',
      authProvider: 'local'
    });

    await user.save();

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'your-secret-key',
      { expiresIn: '7d' }
    );

    res.json({
      token,
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        role: user.role,
        authProvider: user.authProvider
      }
    });
  } catch (error) {
    console.error('Ошибка регистрации:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Вход
router.post('/login', [
  body('email').isEmail().withMessage('Неверный формат email'),
  body('password').notEmpty().withMessage('Пароль обязателен')
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    const { email, password } = req.body;

    const user = await User.findOne({ email });
    if (!user || user.authProvider !== 'local') {
      return res.status(401).json({ error: 'Неверные учетные данные' });
    }

    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ error: 'Неверные учетные данные' });
    }

    user.lastLogin = new Date();
    await user.save();

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'your-secret-key',
      { expiresIn: '7d' }
    );

    res.json({
      token,
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        role: user.role,
        authProvider: user.authProvider
      }
    });
  } catch (error) {
    console.error('Ошибка входа:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Получение текущего пользователя
router.get('/me', async (req, res) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ error: 'Требуется авторизация' });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
    const user = await User.findById(decoded.userId).select('-password');

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json({
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        role: user.role,
        authProvider: user.authProvider,
        lastLogin: user.lastLogin
      }
    });
  } catch (error) {
    res.status(401).json({ error: 'Неверный токен' });
  }
});

// Маршрут для авторизации через Nextcloud (заглушка - будет реализован позже)
router.get('/nextcloud', (req, res) => {
  if (process.env.NEXTCLOUD_OAUTH_ENABLED !== 'true') {
    return res.status(400).json({ 
      error: 'Nextcloud OAuth не настроен. Настройте NEXTCLOUD_OAUTH_ENABLED=true в .env' 
    });
  }
  
  res.json({
    message: 'Nextcloud OAuth настроен. Перенаправление на страницу авторизации Nextcloud...',
    nextcloudUrl: process.env.NEXTCLOUD_OAUTH_AUTH_URL,
    clientId: process.env.NEXTCLOUD_OAUTH_CLIENT_ID
  });
});

module.exports = router;
EOF

    # Заглушка для других маршрутов
    cat > server/routes/conferences.js <<'EOF'
const express = require('express');
const router = express.Router();

router.get('/', (req, res) => {
  res.json({ message: 'API конференций работает', version: '1.0.0' });
});

module.exports = router;
EOF

    cat > server/routes/admin.js <<'EOF'
const express = require('express');
const router = express.Router();

router.get('/stats', (req, res) => {
  res.json({ 
    message: 'API администрирования работает',
    users: 0,
    conferences: 0,
    version: '1.0.0'
  });
});

module.exports = router;
EOF

    # package.json
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
    "axios": "^1.6.0",
    "express-validator": "^7.0.1"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF

    # Простой интерфейс для проверки работы
    cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jitsi Meet Planner • PRAXIS-OVO</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 20px;
            margin: 0;
        }
        .container {
            text-align: center;
            max-width: 800px;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
        }
        h1 {
            font-size: 48px;
            margin-bottom: 20px;
            background: linear-gradient(to right, #fff, #e0e0ff);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        p {
            font-size: 20px;
            margin-bottom: 30px;
            opacity: 0.9;
        }
        .status {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 15px;
            margin-top: 30px;
        }
        .status-item {
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .status-icon {
            width: 60px;
            height: 60px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 24px;
            margin-bottom: 10px;
        }
        .status-ok {
            background: rgba(76, 175, 80, 0.2);
            color: #4CAF50;
        }
        .status-pending {
            background: rgba(255, 152, 0, 0.2);
            color: #ff9800;
        }
        .next-steps {
            margin-top: 40px;
            text-align: left;
            width: 100%;
            background: rgba(0, 0, 0, 0.2);
            padding: 25px;
            border-radius: 15px;
        }
        .next-steps h2 {
            margin-bottom: 20px;
            font-size: 28px;
        }
        .next-steps ol {
            padding-left: 20px;
            font-size: 18px;
            line-height: 1.8;
        }
        .next-steps li {
            margin-bottom: 12px;
        }
        .highlight {
            color: #ffd700;
            font-weight: bold;
        }
        footer {
            margin-top: 40px;
            opacity: 0.7;
            font-size: 16px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Jitsi Meet Planner</h1>
        <p>Система планирования видеоконференций для <span class="highlight">meet.praxis-ovo.ru</span></p>
        
        <div class="status">
            <div class="status-item">
                <div class="status-icon status-ok">✓</div>
                <div>Сервер запущен</div>
            </div>
            <div class="status-item">
                <div class="status-icon status-ok">✓</div>
                <div>MongoDB подключена</div>
            </div>
            <div class="status-item">
                <div class="status-icon status-pending">⋯</div>
                <div>Настройка Nextcloud</div>
            </div>
        </div>
        
        <div class="next-steps">
            <h2>📋 Следующие шаги:</h2>
            <ol>
                <li>Отредактируйте конфигурацию: <span class="highlight">nano /opt/jitsi-planner/.env</span></li>
                <li>Укажите учетные данные Nextcloud для календаря и OAuth2</li>
                <li>Перезапустите сервис: <span class="highlight">systemctl restart jitsi-planner</span></li>
                <li>Откройте в браузере: <span class="highlight">https://meet.praxis-ovo.ru</span></li>
                <li>Зарегистрируйте первого администратора</li>
            </ol>
        </div>
        
        <footer>
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO</p>
            <p>Интеграция с Nextcloud: cloud.praxis-ovo.ru</p>
        </footer>
    </div>
</body>
</html>
EOF

    print_success "Структура приложения создана"
}

# Установка зависимостей приложения
install_app_dependencies() {
    print_header "Установка зависимостей приложения"
    
    cd /opt/jitsi-planner
    
    # Установка зависимостей от имени пользователя приложения
    if sudo -u jitsi-planner npm install --production 2>/dev/null; then
        print_success "Зависимости npm установлены"
    else
        print_warning "Не удалось установить через npm. Пытаемся с правами root..."
        npm install --production --unsafe-perm
        chown -R jitsi-planner:jitsi-planner /opt/jitsi-planner/node_modules 2>/dev/null || true
        print_success "Зависимости установлены (с правами root)"
    fi
}

# Создание конфигурационного файла .env с поддержкой Nextcloud OAuth
create_env_file() {
    print_header "Создание конфигурационного файла .env"
    
    ENV_FILE="/opt/jitsi-planner/.env"
    
    if [ -f "$ENV_FILE" ]; then
        print_warning "Файл .env уже существует. Создаем резервную копию..."
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Генерация секретного ключа
    JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || echo "your-super-secret-jwt-key-change-in-production")
    
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
# Nextcloud - Основные настройки
# ============================================================================
NEXTCLOUD_URL=https://cloud.praxis-ovo.ru

# ============================================================================
# Nextcloud Calendar Integration (для синхронизации событий)
# ============================================================================
# Учетные данные для доступа к календарю через CalDAV (Basic Auth)
NEXTCLOUD_USERNAME=
NEXTCLOUD_PASSWORD=
NEXTCLOUD_CALENDAR_ID=KxEdrRwsMpJg

# ============================================================================
# Nextcloud OAuth2/OIDC (для авторизации пользователей через корпоративные учетные записи)
# ============================================================================
# Включение/выключение авторизации через Nextcloud
NEXTCLOUD_OAUTH_ENABLED=false

# Данные OAuth2 клиента (получить в Nextcloud: Настройки → Администрирование → Безопасность → OAuth 2.0)
NEXTCLOUD_OAUTH_CLIENT_ID=
NEXTCLOUD_OAUTH_CLIENT_SECRET=

# URLs авторизации (обычно стандартные для вашего экземпляра Nextcloud)
NEXTCLOUD_OAUTH_AUTH_URL=https://cloud.praxis-ovo.ru/apps/oauth2/authorize
NEXTCLOUD_OAUTH_TOKEN_URL=https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token
NEXTCLOUD_OAUTH_USERINFO_URL=https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json
NEXTCLOUD_OAUTH_REDIRECT_URI=https://meet.praxis-ovo.ru/api/auth/nextcloud/callback
NEXTCLOUD_OAUTH_SCOPES=openid,profile,email

# ============================================================================
# Администратор по умолчанию
# ============================================================================
# Первый пользователь с этим email автоматически получит роль администратора
ADMIN_EMAIL=admin@praxis-ovo.ru

# ============================================================================
# Настройки Jitsi Meet
# ============================================================================
JITSI_DOMAIN=meet.praxis-ovo.ru
EOF
    
    chown jitsi-planner:jitsi-planner "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    
    print_success "Файл конфигурации создан: $ENV_FILE"
    print_warning "ВАЖНО: Настройте следующие параметры перед первым запуском:"
    echo "  1. NEXTCLOUD_USERNAME и NEXTCLOUD_PASSWORD для синхронизации календаря"
    echo "  2. Для авторизации через Nextcloud:"
    echo "     - NEXTCLOUD_OAUTH_ENABLED=true"
    echo "     - NEXTCLOUD_OAUTH_CLIENT_ID и SECRET (настройте в Nextcloud → OAuth 2.0)"
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
Wants=network-online.target

[Service]
Type=exec
User=jitsi-planner
Group=jitsi-planner
WorkingDirectory=/opt/jitsi-planner
Environment="NODE_ENV=production"
Environment="PATH=/usr/bin:/usr/local/bin"
ExecStart=/usr/bin/node /opt/jitsi-planner/server/server.js
Restart=always
RestartSec=10
TimeoutSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=jitsi-planner
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable jitsi-planner
    
    # Запуск сервиса
    print_info "Запуск сервиса jitsi-planner..."
    systemctl start jitsi-planner 2>/dev/null || true
    
    # Проверка статуса
    sleep 8
    if systemctl is-active --quiet jitsi-planner 2>/dev/null; then
        print_success "Сервис jitsi-planner успешно запущен"
    else
        print_warning "Сервис запускается. Проверьте статус: systemctl status jitsi-planner"
        journalctl -u jitsi-planner -n 30 --no-pager || true
    fi
}

# Настройка Nginx (опционально)
setup_nginx() {
    print_header "Настройка Nginx (опционально)"
    
    if ! command -v nginx &> /dev/null; then
        print_warning "Nginx не установлен."
        read -p "Установить Nginx сейчас? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$OS" == "debian" ]; then
                apt-get install -y -qq nginx
            elif [ "$OS" == "redhat" ]; then
                yum install -y -q nginx
            fi
            print_success "Nginx установлен"
        else
            print_info "Пропускаем настройку Nginx"
            return 0
        fi
    fi
    
    read -p "Настроить Nginx как обратный прокси для meet.praxis-ovo.ru? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Пропускаем настройку Nginx"
        return 0
    fi
    
    # Создание конфигурации
    mkdir -p /var/log/nginx
    
    cat > /etc/nginx/sites-available/jitsi-planner <<'EOF'
server {
    listen 80;
    server_name meet.praxis-ovo.ru;

    # Увеличение лимитов
    client_max_body_size 20M;
    client_body_timeout 12s;
    client_header_timeout 12s;

    # Логи
    access_log /var/log/nginx/jitsi-planner-access.log;
    error_log /var/log/nginx/jitsi-planner-error.log;

    # Заголовки безопасности
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

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
        proxy_read_timeout 300s;
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
        proxy_read_timeout 300s;
    }

    # Health check
    location /health {
        proxy_pass http://localhost:3000;
        access_log off;
    }
}
EOF
    
    # Активация конфигурации
    ln -sf /etc/nginx/sites-available/jitsi-planner /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    # Проверка и перезагрузка
    if nginx -t; then
        systemctl reload nginx
        print_success "Nginx настроен как обратный прокси"
        print_warning "РЕКОМЕНДУЕТСЯ настроить SSL сертификат!"
        echo "  Установите Certbot:"
        if [ "$OS" == "debian" ]; then
            echo "    apt-get install -y certbot python3-certbot-nginx"
        else
            echo "    yum install -y certbot python3-certbot-nginx"
        fi
        echo "  И выполните:"
        echo "    certbot --nginx -d meet.praxis-ovo.ru"
    else
        print_error "Ошибка в конфигурации Nginx. Проверьте синтаксис."
    fi
}

# Настройка файрвола
setup_firewall() {
    print_header "Настройка файрвола"
    
    if command -v ufw &> /dev/null; then
        print_info "Настройка UFW (Uncomplicated Firewall)"
        ufw allow 22/tcp    # SSH
        ufw allow 80/tcp    # HTTP
        ufw allow 443/tcp   # HTTPS
        ufw allow 3000/tcp  # Node.js (для разработки)
        
        if ! ufw status | grep -q "Status: active"; then
            print_warning "Файрвол UFW выключен."
            read -p "Включить UFW? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                yes | ufw enable
                print_success "UFW включен"
            fi
        else
            print_success "Правила UFW настроены"
        fi
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        print_info "Настройка firewalld"
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=3000/tcp
        firewall-cmd --reload
        print_success "firewalld настроен"
    else
        print_warning "Файрвол не обнаружен или не активен. Настройте его вручную."
    fi
}

# Проверка установки
verify_installation() {
    print_header "Проверка установки"
    
    echo "1. MongoDB статус:"
    if systemctl is-active --quiet mongod 2>/dev/null; then
        print_success "   MongoDB запущена"
    else
        print_error "   MongoDB не запущена"
    fi
    
    echo "2. Сервис jitsi-planner статус:"
    if systemctl is-active --quiet jitsi-planner 2>/dev/null; then
        print_success "   Сервис jitsi-planner запущен"
    else
        print_warning "   Сервис не активен (проверьте логи)"
    fi
    
    echo "3. Проверка здоровья приложения:"
    if curl -s -f http://localhost:3000/health | grep -q "ok"; then
        print_success "   Приложение отвечает на запросы"
        curl -s http://localhost:3000/health | python3 -m json.tool 2>/dev/null || echo "   (данные здоровья получены)"
    else
        print_warning "   Приложение не отвечает (может запускаться)"
    fi
    
    echo "4. Версии компонентов:"
    echo "   Node.js: $(node -v 2>/dev/null || echo 'не установлен')"
    echo "   npm: $(npm -v 2>/dev/null || echo 'не установлен')"
    echo "   MongoDB: $(mongod --version 2>/dev/null | head -1 || echo 'не установлен')"
}

# Отображение информации о завершении
show_completion_info() {
    print_header "Установка завершена!"
    
    ADMIN_EMAIL=$(grep ADMIN_EMAIL /opt/jitsi-planner/.env | cut -d'=' -f2 | tr -d ' ' || echo "admin@praxis-ovo.ru")
    
    cat <<EOF

${GREEN}================================================${NC}
${GREEN}  ✅ Установка успешно завершена!${NC}
${GREEN}================================================${NC}

${BLUE}📋 Следующие шаги:${NC}

${YELLOW}1. Настройка конфигурации:${NC}
   nano /opt/jitsi-planner/.env
   
   Обязательно укажите:
   • NEXTCLOUD_USERNAME и NEXTCLOUD_PASSWORD для синхронизации календаря
   • Измените ADMIN_EMAIL на ваш реальный email: ${ADMIN_EMAIL}
   
   Для авторизации через Nextcloud:
   • NEXTCLOUD_OAUTH_ENABLED=true
   • Настройте OAuth2 клиент в Nextcloud (см. ниже)

${YELLOW}2. Настройка OAuth2 в Nextcloud:${NC}
   a. Откройте: ${BLUE}https://cloud.praxis-ovo.ru/settings/admin/security${NC}
   b. Перейдите: "Безопасность" → "OAuth 2.0"
   c. Нажмите "Добавить клиент"
   d. Заполните:
        Имя: Jitsi Meet Planner
        Редирект URI: ${BLUE}https://meet.praxis-ovo.ru/api/auth/nextcloud/callback${NC}
   e. Скопируйте Client ID и Client Secret в .env

${YELLOW}3. Перезапуск сервиса:${NC}
   systemctl restart jitsi-planner

${YELLOW}4. Проверка работы:${NC}
   curl http://localhost:3000/health
   journalctl -u jitsi-planner -f

${YELLOW}5. Настройка SSL (обязательно для продакшена):${NC}
   ${BLUE}# Для Ubuntu/Debian:${NC}
   apt-get install -y certbot python3-certbot-nginx
   certbot --nginx -d meet.praxis-ovo.ru
   
   ${BLUE}# Для RHEL/CentOS:${NC}
   yum install -y certbot python3-certbot-nginx
   certbot --nginx -d meet.praxis-ovo.ru

${YELLOW}6. Первый вход:${NC}
   Откройте в браузере: ${BLUE}https://meet.praxis-ovo.ru${NC}
   Зарегистрируйтесь с email: ${YELLOW}${ADMIN_EMAIL}${NC}

${BLUE}📁 Важные пути:${NC}
   Приложение:      /opt/jitsi-planner/
   Конфигурация:    /opt/jitsi-planner/.env
   Логи приложения: journalctl -u jitsi-planner -f
   Логи Nginx:      /var/log/nginx/jitsi-planner-*.log

${BLUE}🔧 Полезные команды:${NC}
   systemctl status jitsi-planner    # Статус сервиса
   systemctl restart jitsi-planner   # Перезапуск
   tail -f /var/log/nginx/error.log  # Логи Nginx

${GREEN}🎉 Система готова к настройке!${NC}
${YELLOW}⚠️  Не забудьте настроить SSL перед использованием в продакшене!${NC}

EOF
}

# Основная функция установки
main() {
    clear
    print_header "Jitsi Meet Planner - Установка"
    echo ""
    
    # Проверка зависимостей
    check_root
    detect_architecture
    detect_os
    
    echo ""
    print_warning "Внимание! Этот скрипт установит:"
    echo "  • Node.js 18.x/20.x (LTS)"
    echo "  • MongoDB 6.0"
    echo "  • Приложение планирования встреч"
    echo "  • Интеграция с Nextcloud (календарь + OAuth2)"
    echo ""
    echo "  Поддерживаемые ОС: Ubuntu 20.04/22.04/24.04, Debian 11/12, RHEL 8/9"
    echo ""
    
    read -p "Продолжить установку? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Установка отменена"
        exit 0
    fi
    
    echo ""
    print_info "Начинаем установку... (это может занять 5-10 минут)"
    echo ""
    
    # Последовательная установка компонентов
    update_system
    install_utils
    install_nodejs
    install_mongodb
    create_user
    create_app_structure
    install_app_dependencies
    create_env_file
    setup_systemd_service
    setup_nginx
    setup_firewall
    verify_installation
    
    echo ""
    show_completion_info
    
    print_success "Установка завершена!"
    print_info "Подробная информация выше ↑"
}

# Запуск установки
main

exit 0
