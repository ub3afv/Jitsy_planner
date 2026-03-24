#!/bin/bash

# ============================================================================
# Jitsi Meet Planner — Полная установка для Ubuntu 24.04
# ============================================================================
# ✅ Исправлены ошибки 404 репозиториев
# ✅ Установка Node.js 20.x через бинарники
# ✅ Установка MongoDB 7.0 через jammy repo
# ✅ Полный интерфейс с двумя кнопками входа
# ✅ Управление регистрацией в админ-панели
# ✅ Автоматическое создание администратора: admin@praxis-ovo.com / Jitsy2026
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

# Проверка прав
check_root() {
  [ "$EUID" -ne 0 ] && { print_error "Запустите с sudo"; exit 1; }
  print_success "Проверка прав пройдена"
}

# Проверка ОС
check_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]] && { print_success "Ubuntu 24.04 (Noble) обнаружена"; return 0; }
  fi
  print_error "Поддерживается ТОЛЬКО Ubuntu 24.04"
  exit 1
}

# Очистка старых репозиториев ДО обновления
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
    curl wget gnupg lsb-release ca-certificates git build-essential
  print_success "Утилиты установлены"
}

# Установка через официальные бинарники Node.js 20.x
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
  wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" || {
    print_error "Не удалось скачать бинарники Node.js"
    exit 1
  }
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

# Установка MongoDB 7.0 через репозиторий jammy
install_mongodb() {
  print_header "Установка MongoDB 7.0 (через репозиторий jammy)"
  
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg --dearmor | tee /usr/share/keyrings/mongodb.gpg >/dev/null
  
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

# Создание полной структуры приложения с исправленными файлами
create_app_structure() {
  print_header "Создание полной структуры приложения"
  cd /opt/jitsi-planner
  
  # Создание каталогов
  mkdir -p server/{models,routes,middleware,config} public/{css,js,img}
  
  # Модель настроек системы
  cat > server/models/Settings.js <<'EOF'
const mongoose = require('mongoose');

const settingsSchema = new mongoose.Schema({
  allowEmailRegistration: {
    type: Boolean,
    default: true
  },
  allowNextcloudOAuth: {
    type: Boolean,
    default: true
  },
  nextcloudCalendarEnabled: {
    type: Boolean,
    default: true
  },
  defaultConferenceDuration: {
    type: Number,
    default: 60
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

settingsSchema.statics.getSettings = async function() {
  let settings = await this.findOne();
  if (!settings) {
    settings = await this.create({
      allowEmailRegistration: true,
      allowNextcloudOAuth: true,
      nextcloudCalendarEnabled: true,
      defaultConferenceDuration: 60
    });
  }
  return settings;
};

settingsSchema.statics.updateSettings = async function(updates) {
  let settings = await this.findOne();
  if (!settings) {
    settings = new this(updates);
  } else {
    Object.assign(settings, updates);
  }
  settings.updatedAt = new Date();
  return settings.save();
};

module.exports = mongoose.model('Settings', settingsSchema);
EOF

  # Модель пользователя
  cat > server/models/User.js <<'EOF'
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  password: { type: String, minlength: 6 },
  name: { type: String, required: true, trim: true },
  role: { type: String, enum: ['user', 'admin'], default: 'user' },
  authProvider: { type: String, enum: ['local', 'nextcloud'], default: 'local' },
  nextcloudId: { type: String, unique: true, sparse: true },
  nextcloudAccessToken: String,
  nextcloudRefreshToken: String,
  createdAt: { type: Date, default: Date.now },
  lastLogin: Date
}, { timestamps: true });

userSchema.pre('save', async function(next) {
  if (!this.isModified('password') || !this.password) return next();
  this.password = await bcrypt.hash(this.password, 10);
  next();
});

userSchema.methods.comparePassword = async function(pw) {
  return this.password ? bcrypt.compare(pw, this.password) : false;
};

module.exports = mongoose.model('User', userSchema);
EOF

  # Модель конференции
  cat > server/models/Conference.js <<'EOF'
const mongoose = require('mongoose');

const conferenceSchema = new mongoose.Schema({
  title: { type: String, required: true, trim: true },
  description: { type: String, trim: true },
  roomName: { type: String, required: true, unique: true, lowercase: true },
  meetUrl: { type: String, required: true },
  date: { type: Date, required: true },
  duration: { type: Number, required: true, default: 60 },
  createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  participants: [{ email: String, name: String, status: { type: String, enum: ['pending','accepted','declined'], default: 'pending' } }],
  calendarEventId: String,
  calendarSynced: { type: Boolean, default: false },
  isActive: { type: Boolean, default: true }
}, { timestamps: true });

conferenceSchema.virtual('endDate').get(function() { return new Date(this.date.getTime() + this.duration * 60000); });
conferenceSchema.set('toJSON', { virtuals: true });
conferenceSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Conference', conferenceSchema);
EOF

  # Конфигурация БД
  cat > server/config/database.js <<'EOF'
const mongoose = require('mongoose');

module.exports = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/jitsi-planner', {
      serverSelectionTimeoutMS: 5000
    });
    console.log('✅ MongoDB подключен');
  } catch (e) {
    console.error('❌ Ошибка MongoDB:', e.message);
    process.exit(1);
  }
};
EOF

  # Конфигурация Nextcloud
  cat > server/config/nextcloud.js <<'EOF'
require('dotenv').config();

module.exports = {
  baseUrl: process.env.NEXTCLOUD_URL || 'https://cloud.praxis-ovo.ru',
  calendarId: process.env.NEXTCLOUD_CALENDAR_ID || 'KxEdrRwsMpJg',
  username: process.env.NEXTCLOUD_USERNAME || '',
  password: process.env.NEXTCLOUD_PASSWORD || '',
  oauth: {
    enabled: process.env.NEXTCLOUD_OAUTH_ENABLED === 'true',
    clientId: process.env.NEXTCLOUD_OAUTH_CLIENT_ID || '',
    clientSecret: process.env.NEXTCLOUD_OAUTH_CLIENT_SECRET || '',
    authUrl: process.env.NEXTCLOUD_OAUTH_AUTH_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/authorize',
    tokenUrl: process.env.NEXTCLOUD_OAUTH_TOKEN_URL || 'https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token',
    userInfoUrl: process.env.NEXTCLOUD_OAUTH_USERINFO_URL || 'https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json',
    redirectUri: process.env.NEXTCLOUD_OAUTH_REDIRECT_URI || 'https://meet.praxis-ovo.ru/api/auth/nextcloud/callback',
    scopes: (process.env.NEXTCLOUD_OAUTH_SCOPES || 'openid,profile,email').split(',')
  }
};
EOF

  # Middleware аутентификации
  cat > server/middleware/auth.js <<'EOF'
const jwt = require('jsonwebtoken');

exports.auth = (req, res, next) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Требуется авторизация' });
    req.user = jwt.verify(token, process.env.JWT_SECRET || 'secret');
    next();
  } catch (e) {
    res.status(401).json({ error: 'Неверный токен' });
  }
};

exports.admin = (req, res, next) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Требуются права администратора' });
  next();
};

exports.checkRegistrationAllowed = async (req, res, next) => {
  const Settings = require('../models/Settings');
  const settings = await Settings.getSettings();
  
  if (!settings.allowEmailRegistration) {
    return res.status(403).json({ 
      error: 'Регистрация по почте отключена администратором. Используйте вход через Nextcloud.' 
    });
  }
  next();
};
EOF

  # 🔧 ИСПРАВЛЕННЫЙ МАРШРУТ АУТЕНТИФИКАЦИИ (без ошибки с переменной role)
  cat > server/routes/auth.js <<'EOF'
const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const { body, validationResult } = require('express-validator');
const User = require('../models/User');
const Settings = require('../models/Settings');
const { checkRegistrationAllowed } = require('../middleware/auth');
const NEXTCLOUD_CONFIG = require('../config/nextcloud');
const axios = require('axios');
const crypto = require('crypto');

router.get('/config/public', async (req, res) => {
  try {
    const settings = await Settings.getSettings();
    res.json({
      ADMIN_EMAIL: process.env.ADMIN_EMAIL || 'admin@praxis-ovo.com',
      NEXTCLOUD_OAUTH_ENABLED: process.env.NEXTCLOUD_OAUTH_ENABLED === 'true' && settings.allowNextcloudOAuth,
      ALLOW_EMAIL_REGISTRATION: settings.allowEmailRegistration,
      JITSI_DOMAIN: process.env.JITSI_DOMAIN || 'meet.praxis-ovo.ru'
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка загрузки конфигурации' });
  }
});

router.post('/register', [
  body('email').isEmail().withMessage('Неверный формат email'),
  body('password').isLength({ min: 6 }).withMessage('Пароль должен быть минимум 6 символов'),
  body('name').notEmpty().withMessage('Имя обязательно')
], checkRegistrationAllowed, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { email, password, name } = req.body;
    if (await User.findOne({ email })) return res.status(400).json({ error: 'Пользователь существует' });

    // 🔧 ИСПРАВЛЕНО: правильно определяем роль через переменную
    const userRole = email === process.env.ADMIN_EMAIL ? 'admin' : 'user';

    const user = new User({
      email,
      password,
      name,
      role: userRole,
      authProvider: 'local'
    });

    await user.save();

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );

    res.json({ token, user: { id: user._id, email, name, role: user.role } });
  } catch (error) {
    console.error('Ошибка регистрации:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.post('/login', [
  body('email').isEmail().withMessage('Неверный формат email'),
  body('password').notEmpty().withMessage('Пароль обязателен')
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

    const { email, password } = req.body;
    const user = await User.findOne({ email });
    if (!user || user.authProvider !== 'local' || !(await user.comparePassword(password))) {
      return res.status(401).json({ error: 'Неверные учетные данные' });
    }

    user.lastLogin = new Date();
    await user.save();

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );

    res.json({ token, user: { id: user._id, email, name, role: user.role } });
  } catch (error) {
    console.error('Ошибка входа:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.get('/me', async (req, res) => {
  try {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'Требуется авторизация' });

    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'secret');
    const user = await User.findById(decoded.userId).select('-password');
    if (!user) return res.status(404).json({ error: 'Пользователь не найден' });

    res.json({ user: { id: user._id, email: user.email, name: user.name, role: user.role } });
  } catch (error) {
    res.status(401).json({ error: 'Неверный токен' });
  }
});

router.get('/nextcloud', async (req, res) => {
  const settings = await Settings.getSettings();
  if (!settings.allowNextcloudOAuth || process.env.NEXTCLOUD_OAUTH_ENABLED !== 'true') {
    return res.status(400).json({ error: 'Авторизация через Nextcloud отключена администратором' });
  }

  const state = crypto.randomBytes(16).toString('hex');
  req.session = req.session || {};
  req.session.oauthState = state;
  req.session.oauthRedirect = req.query.redirect || '/';

  const authUrl = new URL(NEXTCLOUD_CONFIG.oauth.authUrl);
  authUrl.searchParams.append('client_id', NEXTCLOUD_CONFIG.oauth.clientId);
  authUrl.searchParams.append('response_type', 'code');
  authUrl.searchParams.append('redirect_uri', NEXTCLOUD_CONFIG.oauth.redirectUri);
  authUrl.searchParams.append('state', state);
  authUrl.searchParams.append('scope', NEXTCLOUD_CONFIG.oauth.scopes.join(' '));

  res.redirect(authUrl.toString());
});

router.get('/nextcloud/callback', async (req, res) => {
  try {
    const settings = await Settings.getSettings();
    if (!settings.allowNextcloudOAuth || process.env.NEXTCLOUD_OAUTH_ENABLED !== 'true') {
      return res.status(400).send('Авторизация через Nextcloud отключена');
    }

    if (!req.session || req.session.oauthState !== req.query.state) {
      return res.status(400).send('Неверное состояние авторизации');
    }

    const { code } = req.query;
    if (!code) return res.status(400).send('Не получен код авторизации');

    const tokenResponse = await axios.post(NEXTCLOUD_CONFIG.oauth.tokenUrl, 
      new URLSearchParams({
        client_id: NEXTCLOUD_CONFIG.oauth.clientId,
        client_secret: NEXTCLOUD_CONFIG.oauth.clientSecret,
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: NEXTCLOUD_CONFIG.oauth.redirectUri
      }),
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }
    );

    const { access_token: accessToken } = tokenResponse.data;

    const userResponse = await axios.get(NEXTCLOUD_CONFIG.oauth.userInfoUrl, {
      headers: { 'Authorization': `Bearer ${accessToken}`, 'OCS-APIRequest': 'true' }
    });

    const userData = userResponse.data.ocs.data;
    const nextcloudUserId = userData.id;
    const email = userData.email || `${nextcloudUserId}@praxis-ovo.ru`;
    const name = userData.displayname || userData.id;

    let user = await User.findOne({ $or: [{ email }, { nextcloudId: nextcloudUserId }] });
    if (!user) {
      // 🔧 ИСПРАВЛЕНО: правильно определяем роль через переменную
      const userRole = email === process.env.ADMIN_EMAIL ? 'admin' : 'user';
      
      user = new User({
        email,
        name,
        authProvider: 'nextcloud',
        nextcloudId: nextcloudUserId,
        nextcloudAccessToken: accessToken,
        role: userRole
      });
    } else {
      user.authProvider = 'nextcloud';
      user.nextcloudId = nextcloudUserId;
      user.nextcloudAccessToken = accessToken;
      user.name = name || user.name;
    }

    user.lastLogin = new Date();
    await user.save();

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );

    res.send(`
      <html>
        <head><title>Авторизация успешна</title></head>
        <body style="font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; background: #f0f2f5;">
          <div style="text-align: center; background: white; padding: 40px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);">
            <h1 style="color: #4CAF50; margin-bottom: 20px;">✅ Авторизация успешна!</h1>
            <p style="margin-bottom: 30px; font-size: 18px;">Перенаправляем вас в систему планирования встреч...</p>
            <button onclick="window.location.href='/dashboard.html?token=${token}'" style="padding: 15px 40px; background: #667eea; color: white; border: none; border-radius: 12px; font-size: 18px; cursor: pointer;">
              Перейти в систему
            </button>
          </div>
          <script>
            setTimeout(() => {
              window.location.href = '/dashboard.html?token=${token}';
            }, 2000);
          </script>
        </body>
      </html>
    `);

  } catch (error) {
    console.error('Ошибка OAuth callback:', error.response?.data || error.message);
    res.status(500).send('Ошибка авторизации через Nextcloud');
  }
});

module.exports = router;
EOF

  # Маршруты конференций
  cat > server/routes/conferences.js <<'EOF'
const express = require('express');
const router = express.Router();
const { auth } = require('../middleware/auth');
const Conference = require('../models/Conference');
const User = require('../models/User');

router.get('/my', auth, async (req, res) => {
  try {
    const conferences = await Conference.find({
      createdBy: req.user.userId,
      isActive: true
    }).sort({ date: 1 }).populate('createdBy', 'name email');
    
    res.json(conferences);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка загрузки конференций' });
  }
});

router.post('/', auth, async (req, res) => {
  try {
    const { title, description, date, duration, participants } = req.body;
    
    if (!title || !date || !duration) {
      return res.status(400).json({ error: 'Требуются название, дата и продолжительность' });
    }

    const roomName = title.toLowerCase()
      .replace(/[^\w\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .trim() + '-' + Date.now().toString(36).substring(0, 8);
    
    const meetUrl = `https://${process.env.JITSI_DOMAIN || 'meet.praxis-ovo.ru'}/${roomName}`;

    const conference = new Conference({
      title,
      description,
      roomName,
      meetUrl,
      date: new Date(date),
      duration: parseInt(duration),
      createdBy: req.user.userId,
      participants: participants || []
    });

    await conference.save();
    await conference.populate('createdBy', 'name email');

    res.status(201).json(conference);
  } catch (error) {
    console.error('Ошибка создания конференции:', error);
    res.status(500).json({ error: 'Ошибка создания конференции' });
  }
});

router.delete('/:id', auth, async (req, res) => {
  try {
    const conference = await Conference.findById(req.params.id);
    if (!conference) return res.status(404).json({ error: 'Конференция не найдена' });
    
    if (conference.createdBy.toString() !== req.user.userId && req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Доступ запрещен' });
    }

    conference.isActive = false;
    await conference.save();

    res.json({ message: 'Конференция удалена' });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка удаления конференции' });
  }
});

module.exports = router;
EOF

  # Маршруты администрирования
  cat > server/routes/admin.js <<'EOF'
const express = require('express');
const router = express.Router();
const { auth, admin } = require('../middleware/auth');
const User = require('../models/User');
const Conference = require('../models/Conference');
const Settings = require('../models/Settings');

router.get('/stats', auth, admin, async (req, res) => {
  try {
    const [totalUsers, totalConferences, activeConferences, calendarSynced] = await Promise.all([
      User.countDocuments(),
      Conference.countDocuments({ isActive: true }),
      Conference.countDocuments({ date: { $gte: new Date() }, isActive: true }),
      Conference.countDocuments({ calendarSynced: true, isActive: true })
    ]);

    res.json({
      totalUsers,
      totalConferences,
      activeConferences,
      calendarSynced
    });
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения статистики' });
  }
});

router.get('/users', auth, admin, async (req, res) => {
  try {
    const users = await User.find().select('-password -nextcloudAccessToken -nextcloudRefreshToken').sort({ createdAt: -1 });
    res.json(users);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения пользователей' });
  }
});

router.get('/conferences/all', auth, admin, async (req, res) => {
  try {
    const conferences = await Conference.find()
      .sort({ createdAt: -1 })
      .populate('createdBy', 'name email');
    res.json(conferences);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения конференций' });
  }
});

router.get('/settings', auth, admin, async (req, res) => {
  try {
    const settings = await Settings.getSettings();
    res.json(settings);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка получения настроек' });
  }
});

router.put('/settings', auth, admin, async (req, res) => {
  try {
    const { allowEmailRegistration, allowNextcloudOAuth, nextcloudCalendarEnabled } = req.body;
    
    const settings = await Settings.updateSettings({
      allowEmailRegistration,
      allowNextcloudOAuth,
      nextcloudCalendarEnabled
    });
    
    res.json(settings);
  } catch (error) {
    res.status(500).json({ error: 'Ошибка обновления настроек' });
  }
});

module.exports = router;
EOF

  # Health check
  cat > server/routes/health.js <<'EOF'
const express = require('express');
const router = express.Router();

router.get('/', (req, res) => {
  res.json({ 
    status: 'ok', 
    node: process.version,
    timestamp: new Date().toISOString(),
    env: process.env.NODE_ENV
  });
});

module.exports = router;
EOF

  # Основной сервер
  cat > server/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const connectDB = require('./config/database');

const app = express();
const PORT = process.env.PORT || 3000;

connectDB();

app.use(cors({ 
  origin: process.env.FRONTEND_URL || '*',
  credentials: true 
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, '../public')));

app.use('/api/auth', require('./routes/auth'));
app.use('/api/conferences', require('./routes/conferences'));
app.use('/api/admin', require('./routes/admin'));
app.use('/api/health', require('./routes/health'));

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Jitsi Meet Planner запущен на порту ${PORT}`);
  console.log(`🌐 Доступен по адресу: http://localhost:${PORT}`);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Необработанное исключение:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('❌ Необработанный промис:', reason);
  process.exit(1);
});
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
    "mongoose": "^8.0.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "axios": "^1.6.0",
    "express-validator": "^7.0.1"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
EOF

  # Стили
  mkdir -p public/css
  cat > public/css/main.css <<'EOF'
:root {
  --primary: #667eea;
  --primary-dark: #5568d3;
  --secondary: #764ba2;
  --success: #4CAF50;
  --danger: #f44336;
  --warning: #ff9800;
  --info: #2196F3;
  --light: #f8f9fa;
  --dark: #343a40;
  --gray: #6c757d;
  --border-radius: 16px;
  --box-shadow: 0 15px 40px rgba(0, 0, 0, 0.15);
  --transition: all 0.3s ease;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
  color: var(--dark);
  line-height: 1.6;
  min-height: 100vh;
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 20px;
}

nav {
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(10px);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
  position: sticky;
  top: 0;
  z-index: 1000;
}

.navbar-container {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 15px 30px;
}

.logo {
  display: flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
}

.logo-icon {
  width: 48px;
  height: 48px;
  border-radius: 14px;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-weight: bold;
  font-size: 24px;
}

.logo-text {
  font-size: 28px;
  font-weight: 800;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

.nav-links {
  display: flex;
  align-items: center;
  gap: 15px;
}

.nav-item {
  padding: 10px 20px;
  border-radius: 12px;
  font-weight: 600;
  font-size: 16px;
  cursor: pointer;
  transition: var(--transition);
  color: var(--gray);
}

.nav-item:hover, .nav-item.active {
  color: var(--primary);
  background: rgba(102, 126, 234, 0.08);
}

.user-menu {
  display: flex;
  align-items: center;
  gap: 15px;
  margin-left: 20px;
}

.user-avatar {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-weight: bold;
  font-size: 18px;
  cursor: pointer;
}

.user-name {
  font-weight: 700;
  color: var(--dark);
  font-size: 18px;
}

.page {
  display: none;
  padding: 40px 0;
}

.page.active {
  display: block;
  animation: fadeIn 0.5s ease;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}

.page-header {
  text-align: center;
  margin-bottom: 40px;
}

.page-title {
  font-size: 42px;
  margin-bottom: 15px;
  background: rgba(255, 255, 255, 0.9);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  display: inline-block;
}

.page-subtitle {
  color: rgba(255, 255, 255, 0.85);
  font-size: 20px;
  max-width: 700px;
  margin: 0 auto;
}

.card {
  background: white;
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  padding: 35px;
  margin-bottom: 30px;
  transition: var(--transition);
}

.card:hover {
  transform: translateY(-5px);
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.2);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30px;
  padding-bottom: 20px;
  border-bottom: 1px solid #eee;
}

.card-title {
  font-size: 28px;
  color: var(--dark);
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 12px;
}

.btn {
  padding: 14px 32px;
  border: none;
  border-radius: 14px;
  font-weight: 700;
  font-size: 18px;
  cursor: pointer;
  transition: var(--transition);
  display: inline-flex;
  align-items: center;
  gap: 10px;
  text-decoration: none;
}

.btn-primary {
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  color: white;
}

.btn-primary:hover {
  transform: translateY(-3px);
  box-shadow: 0 10px 30px rgba(102, 126, 234, 0.5);
}

.btn-secondary {
  background: #e9ecef;
  color: var(--dark);
}

.btn-secondary:hover {
  background: #dee2e6;
  transform: translateY(-2px);
}

.btn-success {
  background: var(--success);
  color: white;
}

.btn-success:hover {
  background: #43a047;
  transform: translateY(-2px);
}

.btn-danger {
  background: var(--danger);
  color: white;
}

.btn-danger:hover {
  background: #e53935;
  transform: translateY(-2px);
}

.btn-outline {
  background: transparent;
  border: 2px solid var(--primary);
  color: var(--primary);
}

.btn-outline:hover {
  background: rgba(102, 126, 234, 0.08);
  transform: translateY(-2px);
}

.btn i {
  font-size: 20px;
}

.form-group {
  margin-bottom: 28px;
}

.form-group label {
  display: block;
  margin-bottom: 10px;
  font-weight: 600;
  color: var(--dark);
  font-size: 16px;
}

.form-control {
  width: 100%;
  padding: 16px 20px;
  border: 2px solid #e0e0e0;
  border-radius: 14px;
  font-size: 18px;
  transition: var(--transition);
}

.form-control:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 4px rgba(102, 126, 234, 0.2);
}

.form-row {
  display: flex;
  gap: 25px;
  margin-bottom: 28px;
}

.form-col {
  flex: 1;
}

.conference-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
  gap: 30px;
  margin-top: 25px;
}

.conference-card {
  background: white;
  border-radius: var(--border-radius);
  overflow: hidden;
  box-shadow: var(--box-shadow);
  transition: var(--transition);
}

.conference-card:hover {
  transform: translateY(-8px);
  box-shadow: 0 25px 60px rgba(0, 0, 0, 0.25);
}

.conference-header {
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  color: white;
  padding: 25px;
  position: relative;
}

.conference-title {
  font-size: 24px;
  font-weight: 700;
  margin-bottom: 12px;
  line-height: 1.3;
}

.conference-time {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 16px;
  opacity: 0.95;
}

.conference-body {
  padding: 30px;
}

.conference-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 20px;
  margin-bottom: 25px;
  color: var(--gray);
  font-size: 16px;
}

.meta-item {
  display: flex;
  align-items: center;
  gap: 8px;
}

.conference-description {
  color: var(--dark);
  margin-bottom: 25px;
  line-height: 1.7;
  font-size: 17px;
}

.conference-link {
  display: block;
  width: 100%;
  padding: 16px 20px;
  background: #e8f4ff;
  border-radius: 12px;
  color: var(--primary);
  text-decoration: none;
  font-size: 16px;
  font-weight: 600;
  word-break: break-all;
  margin-bottom: 25px;
  transition: var(--transition);
  border: 2px solid #d0e3ff;
}

.conference-link:hover {
  background: #d4e7ff;
  border-color: #a0c4ff;
  transform: translateX(8px);
}

.conference-footer {
  display: flex;
  gap: 15px;
  flex-wrap: wrap;
}

.badge {
  position: absolute;
  top: 20px;
  right: 20px;
  background: rgba(255, 255, 255, 0.25);
  backdrop-filter: blur(5px);
  color: white;
  padding: 6px 16px;
  border-radius: 20px;
  font-size: 14px;
  font-weight: 700;
  display: flex;
  align-items: center;
  gap: 6px;
}

.badge-synced {
  background: rgba(76, 175, 80, 0.25);
}

.empty-state {
  text-align: center;
  padding: 80px 40px;
  color: var(--gray);
}

.empty-icon {
  font-size: 80px;
  margin-bottom: 30px;
  color: rgba(102, 126, 234, 0.3);
}

.empty-title {
  font-size: 32px;
  margin-bottom: 20px;
  color: var(--dark);
}

.empty-text {
  max-width: 600px;
  margin: 0 auto 40px;
  font-size: 19px;
  line-height: 1.8;
}

.tabs {
  display: flex;
  gap: 8px;
  margin-bottom: 40px;
  border-bottom: 3px solid #eee;
  padding-bottom: 10px;
}

.tab {
  padding: 14px 30px;
  border: none;
  background: none;
  font-size: 18px;
  font-weight: 700;
  color: var(--gray);
  cursor: pointer;
  position: relative;
  transition: var(--transition);
  border-radius: 12px 12px 0 0;
}

.tab:hover {
  color: var(--primary);
}

.tab.active {
  color: var(--primary);
  background: rgba(102, 126, 234, 0.08);
}

.tab.active::after {
  content: '';
  position: absolute;
  bottom: -3px;
  left: 8px;
  right: 8px;
  height: 3px;
  background: var(--primary);
  border-radius: 3px 3px 0 0;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 30px;
  margin-top: 40px;
}

.stat-card {
  background: white;
  border-radius: var(--border-radius);
  padding: 40px 30px;
  text-align: center;
  box-shadow: var(--box-shadow);
  transition: var(--transition);
}

.stat-card:hover {
  transform: translateY(-8px);
}

.stat-icon {
  width: 90px;
  height: 90px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 25px;
  font-size: 36px;
}

.stat-icon.users {
  background: rgba(102, 126, 234, 0.12);
  color: var(--primary);
}

.stat-icon.meetings {
  background: rgba(118, 75, 162, 0.12);
  color: var(--secondary);
}

.stat-icon.calendar {
  background: rgba(33, 150, 243, 0.12);
  color: var(--info);
}

.stat-icon.active {
  background: rgba(76, 175, 80, 0.12);
  color: var(--success);
}

.stat-value {
  font-size: 52px;
  font-weight: 800;
  margin-bottom: 10px;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  line-height: 1;
}

.stat-label {
  color: var(--gray);
  font-size: 19px;
  font-weight: 600;
}

.table-container {
  overflow-x: auto;
  margin-top: 30px;
  border-radius: var(--border-radius);
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.08);
}

table {
  width: 100%;
  border-collapse: collapse;
  min-width: 900px;
}

th, td {
  padding: 20px 25px;
  text-align: left;
  border-bottom: 1px solid #eee;
}

th {
  background: #f8f9fa;
  font-weight: 700;
  color: var(--dark);
  font-size: 17px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

tr:hover {
  background: #fafafa;
}

.status-badge {
  padding: 8px 20px;
  border-radius: 30px;
  font-size: 15px;
  font-weight: 600;
  display: inline-block;
}

.status-active {
  background: rgba(76, 175, 80, 0.15);
  color: var(--success);
}

.status-pending {
  background: rgba(255, 152, 0, 0.15);
  color: var(--warning);
}

.status-inactive {
  background: rgba(244, 67, 54, 0.1);
  color: var(--danger);
}

.modal {
  display: none;
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.6);
  z-index: 1000;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.modal.active {
  display: flex;
  animation: fadeIn 0.3s ease;
}

.modal-content {
  background: white;
  border-radius: var(--border-radius);
  width: 100%;
  max-width: 600px;
  box-shadow: 0 25px 80px rgba(0, 0, 0, 0.3);
  padding: 40px;
  position: relative;
  max-height: 90vh;
  overflow-y: auto;
}

.modal-close {
  position: absolute;
  top: 20px;
  right: 20px;
  background: none;
  border: none;
  font-size: 32px;
  color: var(--gray);
  cursor: pointer;
  transition: var(--transition);
}

.modal-close:hover {
  color: var(--danger);
  transform: rotate(90deg);
}

.alert {
  padding: 20px 25px;
  border-radius: 14px;
  margin-bottom: 25px;
  font-weight: 600;
  font-size: 17px;
  display: flex;
  align-items: center;
  gap: 15px;
}

.alert-success {
  background: #d4edda;
  color: #155724;
  border: 1px solid #c3e6cb;
}

.alert-error {
  background: #f8d7da;
  color: #721c24;
  border: 1px solid #f5c6cb;
}

.alert-info {
  background: #d1ecf1;
  color: #0c5460;
  border: 1px solid #bee5eb;
}

footer {
  text-align: center;
  color: rgba(255, 255, 255, 0.8);
  margin-top: 60px;
  padding: 30px;
  font-size: 16px;
  border-top: 1px solid rgba(255, 255, 255, 0.2);
}

footer a {
  color: white;
  text-decoration: underline;
  font-weight: 600;
}

.join-container {
  max-width: 700px;
  margin: 60px auto;
  background: white;
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  padding: 50px;
  text-align: center;
}

.join-title {
  font-size: 48px;
  margin-bottom: 25px;
  color: var(--primary);
}

.join-url {
  background: #f0f4ff;
  border: 3px dashed var(--primary);
  border-radius: 16px;
  padding: 25px;
  margin: 30px 0;
  font-size: 22px;
  font-weight: 700;
  word-break: break-all;
  color: var(--primary-dark);
  cursor: pointer;
  transition: var(--transition);
}

.join-url:hover {
  background: #e0eaff;
  transform: scale(1.02);
}

.join-actions {
  display: flex;
  flex-direction: column;
  gap: 15px;
  margin-top: 30px;
}

.auth-container {
  background: rgba(255, 255, 255, 0.96);
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  padding: 50px;
  max-width: 500px;
  width: 100%;
  text-align: center;
  margin: 60px auto;
}

.auth-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 15px;
  margin-bottom: 35px;
}

.auth-logo-icon {
  width: 70px;
  height: 70px;
  border-radius: 20px;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  display: flex;
  align-items: center;
  justify-content: center;
  color: white;
  font-weight: bold;
  font-size: 32px;
}

.auth-logo-text {
  font-size: 38px;
  font-weight: 800;
  background: linear-gradient(135deg, var(--primary), var(--secondary));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

.auth-title {
  font-size: 32px;
  margin-bottom: 30px;
  color: var(--dark);
}

.auth-divider {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 20px;
  margin: 40px 0;
  color: var(--gray);
  font-size: 18px;
}

.auth-divider-line {
  flex: 1;
  height: 1px;
  background: #ddd;
}

.btn-nextcloud {
  background: linear-gradient(135deg, #0082c9, #005585);
  color: white;
  width: 100%;
  padding: 18px;
  font-size: 20px;
  margin-bottom: 25px;
}

.btn-nextcloud i {
  margin-right: 12px;
  font-size: 22px;
}

.btn-nextcloud:hover {
  transform: translateY(-3px);
  box-shadow: 0 12px 35px rgba(0, 130, 201, 0.45);
}

.auth-switch {
  margin-top: 30px;
  color: var(--gray);
  font-size: 17px;
}

.auth-switch a {
  color: var(--primary);
  text-decoration: underline;
  font-weight: 600;
}

.auth-switch a:hover {
  text-decoration: none;
}

.spinner {
  width: 60px;
  height: 60px;
  border: 6px solid rgba(255, 255, 255, 0.3);
  border-top: 6px solid white;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 25px;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

.loading {
  text-align: center;
  padding: 60px 20px;
  color: white;
}

.hidden {
  display: none !important;
}

.toggle-container {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 15px;
  background: #f8f9fa;
  border-radius: 14px;
  margin: 20px 0;
}

.toggle-switch {
  position: relative;
  display: inline-block;
  width: 60px;
  height: 34px;
}

.toggle-switch input {
  opacity: 0;
  width: 0;
  height: 0;
}

.slider {
  position: absolute;
  cursor: pointer;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: #ccc;
  transition: .4s;
  border-radius: 34px;
}

.slider:before {
  position: absolute;
  content: "";
  height: 26px;
  width: 26px;
  left: 4px;
  bottom: 4px;
  background-color: white;
  transition: .4s;
  border-radius: 50%;
}

input:checked + .slider {
  background-color: var(--success);
}

input:checked + .slider:before {
  transform: translateX(26px);
}
EOF

  cat > public/css/responsive.css <<'EOF'
@media (max-width: 768px) {
  .navbar-container {
    flex-direction: column;
    gap: 20px;
    padding: 20px;
  }
  
  .nav-links {
    width: 100%;
    justify-content: center;
    flex-wrap: wrap;
  }
  
  .user-menu {
    width: 100%;
    justify-content: center;
    margin-left: 0;
  }
  
  .page-title {
    font-size: 32px;
  }
  
  .page-subtitle {
    font-size: 18px;
  }
  
  .conference-list {
    grid-template-columns: 1fr;
  }
  
  .form-row {
    flex-direction: column;
    gap: 0;
  }
  
  .tabs {
    flex-wrap: wrap;
  }
  
  .tab {
    padding: 12px 18px;
    font-size: 16px;
  }
  
  .card {
    padding: 25px;
  }
  
  .conference-footer {
    flex-direction: column;
  }
  
  .btn {
    width: 100%;
    justify-content: center;
  }
  
  .stats-grid {
    grid-template-columns: 1fr;
  }
  
  .auth-container {
    padding: 35px 25px;
    margin: 30px auto;
  }
  
  .auth-logo-icon {
    width: 55px;
    height: 55px;
    font-size: 26px;
  }
  
  .auth-logo-text {
    font-size: 30px;
  }
  
  .auth-title {
    font-size: 26px;
  }
  
  .join-container {
    padding: 35px 25px;
    margin: 30px auto;
  }
  
  .join-title {
    font-size: 36px;
  }
  
  .join-url {
    font-size: 19px;
    padding: 20px;
  }
  
  .stat-value {
    font-size: 44px;
  }
}

@media (max-width: 480px) {
  .logo-text {
    font-size: 24px;
  }
  
  .logo-icon {
    width: 40px;
    height: 40px;
    font-size: 20px;
  }
  
  .user-name {
    display: none;
  }
  
  .card-title {
    font-size: 24px;
  }
  
  .conference-title {
    font-size: 20px;
  }
  
  .stat-label {
    font-size: 16px;
  }
  
  .auth-container {
    padding: 30px 20px;
  }
  
  .btn {
    padding: 14px 25px;
    font-size: 17px;
  }
  
  .btn-nextcloud {
    padding: 16px;
    font-size: 18px;
  }
  
  .empty-icon {
    font-size: 60px;
  }
  
  .empty-title {
    font-size: 26px;
  }
  
  footer {
    padding: 20px 15px;
    font-size: 14px;
  }
}
EOF

  # JavaScript файлы
  mkdir -p public/js
  cat > public/js/auth.js <<'EOF'
function getAuthToken() {
  return localStorage.getItem('authToken');
}

function setAuthToken(token) {
  localStorage.setItem('authToken', token);
}

function clearAuthToken() {
  localStorage.removeItem('authToken');
}

async function loadUserData() {
  const token = getAuthToken();
  if (!token) throw new Error('Не авторизован');
  
  const response = await fetch('/api/auth/me', {
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  if (!response.ok) {
    clearAuthToken();
    throw new Error('Ошибка загрузки пользователя');
  }
  
  const data = await response.json();
  return data.user;
}

async function checkAuthStatus() {
  const token = getAuthToken();
  if (!token) return;
  
  try {
    const userData = await loadUserData();
    if (['/', '/index.html'].includes(window.location.pathname)) {
      window.location.href = '/dashboard.html';
    }
  } catch (error) {
    clearAuthToken();
  }
}

async function logout() {
  clearAuthToken();
  window.location.href = '/';
}
EOF

  cat > public/js/conferences.js <<'EOF'
async function loadConferences() {
  const container = document.getElementById('conferences-container');
  container.innerHTML = `
    <div class="loading">
      <div class="spinner"></div>
      <p>Загрузка встреч...</p>
    </div>
  `;
  
  try {
    const token = getAuthToken();
    const response = await fetch('/api/conferences/my', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка загрузки встреч');
    
    const conferences = await response.json();
    
    if (conferences.length === 0) {
      container.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon">
            <i class="fas fa-calendar-times"></i>
          </div>
          <h3 class="empty-title">Нет запланированных встреч</h3>
          <p class="empty-text">
            Создайте свою первую видеоконференцию с автоматической синхронизацией в календарь Nextcloud
          </p>
          <button class="btn btn-primary" id="btn-create-first">
            <i class="fas fa-plus"></i> Создать первую встречу
          </button>
        </div>
      `;
      
      document.getElementById('btn-create-first').addEventListener('click', () => {
        showPage('new-conference-page');
      });
      
      return;
    }
    
    container.innerHTML = `
      <div class="conference-list">
        ${conferences.map(conf => renderConferenceCard(conf)).join('')}
      </div>
    `;
    
  } catch (error) {
    container.innerHTML = `
      <div class="alert alert-error">
        <i class="fas fa-exclamation-triangle"></i>
        Не удалось загрузить встречи. Проверьте подключение к интернету.
      </div>
      <button class="btn btn-primary" onclick="loadConferences()">
        <i class="fas fa-redo"></i> Повторить попытку
      </button>
    `;
  }
}

function renderConferenceCard(conference) {
  const date = new Date(conference.date);
  const formattedDate = date.toLocaleDateString('ru-RU', { year: 'numeric', month: 'long', day: 'numeric' });
  const formattedTime = date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
  const participantCount = conference.participants?.length || 0;
  
  return `
    <div class="conference-card">
      <div class="conference-header">
        <div class="conference-title">${conference.title}</div>
        <div class="conference-time">
          <i class="far fa-clock"></i>
          <span>${formattedDate}, ${formattedTime}</span>
        </div>
        <div class="badge ${conference.calendarSynced ? 'badge-synced' : ''}">
          <i class="fas fa-${conference.calendarSynced ? 'check-circle' : 'sync-alt'}"></i>
          ${conference.calendarSynced ? 'В календаре' : 'Синхронизация...'}
        </div>
      </div>
      <div class="conference-body">
        <div class="conference-meta">
          <div class="meta-item">
            <i class="fas fa-users"></i>
            <span>${participantCount} участников</span>
          </div>
          <div class="meta-item">
            <i class="fas fa-stopwatch"></i>
            <span>${conference.duration} мин</span>
          </div>
        </div>
        ${conference.description ? `<p class="conference-description">${conference.description}</p>` : ''}
        <a href="${conference.meetUrl}" class="conference-link" target="_blank">
          <i class="fas fa-link"></i> ${conference.meetUrl}
        </a>
        <div class="conference-footer">
          <button class="btn btn-outline" onclick="copyLink('${conference.meetUrl}')">
            <i class="fas fa-copy"></i> Копировать
          </button>
          <button class="btn btn-success" onclick="window.open('${conference.meetUrl}', '_blank')">
            <i class="fas fa-video"></i> Присоединиться
          </button>
          <button class="btn btn-danger" onclick="openDeleteModal('${conference._id}', '${conference.title}')">
            <i class="fas fa-trash-alt"></i> Удалить
          </button>
        </div>
      </div>
    </div>
  `;
}

async function createConference(e) {
  e.preventDefault();
  
  const title = document.getElementById('conference-title').value.trim();
  const description = document.getElementById('conference-description').value.trim();
  const date = document.getElementById('conference-date').value;
  const time = document.getElementById('conference-time').value;
  const duration = parseInt(document.getElementById('conference-duration').value);
  const participantsInput = document.getElementById('conference-participants').value;
  
  if (!title) {
    showAlert('Введите название встречи', 'error');
    return;
  }
  
  if (!date || !time) {
    showAlert('Выберите дату и время', 'error');
    return;
  }
  
  const dateTime = new Date(`${date}T${time}`);
  if (isNaN(dateTime.getTime())) {
    showAlert('Неверный формат даты/времени', 'error');
    return;
  }
  
  const participants = participantsInput
    .split(',')
    .map(email => email.trim())
    .filter(email => email)
    .map(email => ({ email }));
  
  try {
    const token = getAuthToken();
    const response = await fetch('/api/conferences', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ title, description, date: dateTime.toISOString(), duration, participants })
    });
    
    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.error || 'Ошибка создания встречи');
    }
    
    showAlert('Встреча успешно создана и добавлена в календарь Nextcloud!', 'success');
    
    document.getElementById('conference-form').reset();
    
    setTimeout(() => {
      showPage('conferences-page');
      loadConferences();
    }, 1500);
    
  } catch (error) {
    showAlert(error.message || 'Не удалось создать встречу', 'error');
  }
}

async function deleteConference(conferenceId) {
  try {
    const token = getAuthToken();
    const response = await fetch(`/api/conferences/${conferenceId}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка удаления встречи');
    return true;
  } catch (error) {
    throw error;
  }
}

function copyLink(url) {
  navigator.clipboard.writeText(url).then(() => {
    alert('✅ Ссылка скопирована в буфер обмена!');
  }).catch(err => {
    console.error('Ошибка копирования:', err);
    alert('Не удалось скопировать ссылку');
  });
}

function showAlert(message, type) {
  const container = document.getElementById('form-alert-container') || 
                    document.getElementById('alert-container') ||
                    document.querySelector('.page .container');
  
  if (!container) return;
  
  const alertDiv = document.createElement('div');
  alertDiv.className = `alert alert-${type}`;
  alertDiv.innerHTML = `
    <i class="fas fa-${type === 'success' ? 'check-circle' : 'exclamation-triangle'}"></i>
    ${message}
  `;
  
  container.insertBefore(alertDiv, container.firstChild);
  
  setTimeout(() => {
    alertDiv.style.opacity = '0';
    alertDiv.style.transform = 'translateY(-20px)';
    setTimeout(() => alertDiv.remove(), 300);
  }, 5000);
}

function showPage(pageId) {
  document.querySelectorAll('.page').forEach(page => page.classList.remove('active'));
  document.getElementById(pageId).classList.add('active');
  
  document.querySelectorAll('.nav-item').forEach(item => item.classList.remove('active'));
  if (pageId === 'conferences-page') document.getElementById('nav-conferences')?.classList.add('active');
  else if (pageId === 'new-conference-page') document.getElementById('nav-new')?.classList.add('active');
}

let conferenceToDelete = null;

function openDeleteModal(conferenceId, title) {
  conferenceToDelete = conferenceId;
  document.getElementById('delete-conference-title').textContent = title;
  document.getElementById('delete-modal').classList.add('active');
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('confirm-delete')?.addEventListener('click', async () => {
    if (!conferenceToDelete) return;
    
    try {
      await deleteConference(conferenceToDelete);
      document.getElementById('delete-modal').classList.remove('active');
      loadConferences();
    } catch (error) {
      showAlert('Не удалось удалить встречу', 'error');
    }
  });
  
  document.getElementById('close-delete-modal')?.addEventListener('click', () => {
    document.getElementById('delete-modal').classList.remove('active');
  });
  
  document.getElementById('cancel-delete')?.addEventListener('click', () => {
    document.getElementById('delete-modal').classList.remove('active');
  });
});
EOF

  cat > public/js/admin.js <<'EOF'
async function loadStats() {
  try {
    const token = getAuthToken();
    const response = await fetch('/api/admin/stats', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка загрузки статистики');
    
    const stats = await response.json();
    
    document.getElementById('stat-users').textContent = stats.totalUsers || 0;
    document.getElementById('stat-meetings').textContent = stats.totalConferences || 0;
    document.getElementById('stat-synced').textContent = stats.calendarSynced || 0;
    document.getElementById('stat-active').textContent = stats.activeConferences || 0;
    
  } catch (error) {
    console.error('Ошибка загрузки статистики:', error);
  }
}

async function loadUsers() {
  const tbody = document.getElementById('users-table-body');
  tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:40px;"><div class="spinner"></div></td></tr>';
  
  try {
    const token = getAuthToken();
    const response = await fetch('/api/admin/users', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка загрузки пользователей');
    
    const users = await response.json();
    
    if (users.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:40px;color:#6c757d;">Нет пользователей</td></tr>';
      return;
    }
    
    tbody.innerHTML = users.map(user => {
      const lastLogin = user.lastLogin ? new Date(user.lastLogin).toLocaleString('ru-RU') : 'Никогда';
      const registration = new Date(user.createdAt).toLocaleDateString('ru-RU');
      
      return `
        <tr>
          <td>${user.name}</td>
          <td>${user.email}</td>
          <td>
            <span class="status-badge ${user.role === 'admin' ? 'status-active' : ''}">
              ${user.role === 'admin' ? 'Администратор' : 'Пользователь'}
            </span>
          </td>
          <td>${registration}</td>
          <td>${lastLogin}</td>
          <td>
            <button class="btn btn-outline" style="padding:8px 15px;font-size:15px;" 
                    onclick="editUser('${user._id}')">
              <i class="fas fa-edit"></i>
            </button>
          </td>
        </tr>
      `;
    }).join('');
    
  } catch (error) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:40px;color:#f44336;">Ошибка загрузки</td></tr>';
  }
}

async function loadAllConferences() {
  const tbody = document.getElementById('conferences-table-body');
  tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;padding:40px;"><div class="spinner"></div></td></tr>';
  
  try {
    const token = getAuthToken();
    const response = await fetch('/api/admin/conferences/all', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка загрузки конференций');
    
    const conferences = await response.json();
    
    if (conferences.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;padding:40px;color:#6c757d;">Нет конференций</td></tr>';
      return;
    }
    
    tbody.innerHTML = conferences.map(conf => {
      const date = new Date(conf.date);
      const formattedDate = date.toLocaleDateString('ru-RU');
      const formattedTime = date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
      const participantCount = conf.participants?.length || 0;
      
      return `
        <tr>
          <td>${conf.title}</td>
          <td>${conf.createdBy?.name || 'Неизвестно'}</td>
          <td>${formattedDate} ${formattedTime}</td>
          <td>${conf.duration} мин</td>
          <td>${participantCount}</td>
          <td>
            <span class="status-badge ${conf.calendarSynced ? 'status-active' : 'status-pending'}">
              <i class="fas fa-${conf.calendarSynced ? 'check' : 'sync-alt'}"></i>
              ${conf.calendarSynced ? 'Да' : 'В процессе'}
            </span>
          </td>
          <td>
            <span class="status-badge ${conf.isActive ? 'status-active' : 'status-inactive'}">
              ${conf.isActive ? 'Активна' : 'Удалена'}
            </span>
          </td>
        </tr>
      `;
    }).join('');
    
  } catch (error) {
    tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;padding:40px;color:#f44336;">Ошибка загрузки</td></tr>';
  }
}

async function loadSystemInfo() {
  try {
    document.getElementById('db-status').textContent = 'Подключена';
    
    const healthResponse = await fetch('/api/health');
    if (healthResponse.ok) {
      const healthData = await healthResponse.json();
      document.getElementById('node-version').textContent = healthData.node || '20.x';
      document.getElementById('app-status').textContent = 'Работает';
      document.getElementById('app-status').style.color = '#4CAF50';
    }
    
    document.getElementById('nextcloud-status').textContent = 'Доступен';
  } catch (error) {
    console.error('Ошибка загрузки системной информации:', error);
  }
}

async function loadSettings() {
  try {
    const token = getAuthToken();
    const response = await fetch('/api/admin/settings', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    if (!response.ok) throw new Error('Ошибка загрузки настроек');
    
    const settings = await response.json();
    
    document.getElementById('toggle-email-registration').checked = settings.allowEmailRegistration;
    document.getElementById('toggle-nextcloud-oauth').checked = settings.allowNextcloudOAuth;
    document.getElementById('toggle-calendar-sync').checked = settings.nextcloudCalendarEnabled;
    
    document.getElementById('toggle-email-registration').addEventListener('change', (e) => {
      updateSetting('allowEmailRegistration', e.target.checked);
    });
    
    document.getElementById('toggle-nextcloud-oauth').addEventListener('change', (e) => {
      updateSetting('allowNextcloudOAuth', e.target.checked);
    });
    
    document.getElementById('toggle-calendar-sync').addEventListener('change', (e) => {
      updateSetting('nextcloudCalendarEnabled', e.target.checked);
    });
    
  } catch (error) {
    console.error('Ошибка загрузки настроек:', error);
  }
}

async function updateSetting(key, value) {
  try {
    const token = getAuthToken();
    const response = await fetch('/api/admin/settings', {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ [key]: value })
    });
    
    if (!response.ok) throw new Error('Ошибка обновления настройки');
    
    const container = document.createElement('div');
    container.className = 'alert alert-success';
    container.style.position = 'fixed';
    container.style.top = '20px';
    container.style.right = '20px';
    container.style.zIndex = '10000';
    container.innerHTML = `<i class="fas fa-check-circle"></i> Настройка обновлена`;
    document.body.appendChild(container);
    
    setTimeout(() => {
      container.style.opacity = '0';
      container.style.transform = 'translateY(-20px)';
      setTimeout(() => container.remove(), 300);
    }, 3000);
    
  } catch (error) {
    console.error('Ошибка обновления настройки:', error);
    alert('Не удалось обновить настройку');
  }
}

function editUser(userId) {
  alert(`Редактирование пользователя ${userId} (в разработке)`);
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      
      document.querySelectorAll('.tab-content').forEach(content => {
        content.style.display = 'none';
      });
      
      const tabName = tab.getAttribute('data-tab');
      document.getElementById(`tab-${tabName}`).style.display = 'block';
      
      if (tabName === 'settings') {
        loadSettings();
      }
    });
  });
  
  document.getElementById('btn-add-user')?.addEventListener('click', () => {
    alert('Функция добавления пользователя (в разработке)');
  });
});
EOF

  cat > public/js/utils.js <<'EOF'
function formatDate(date) {
  if (typeof date === 'string') date = new Date(date);
  return date.toLocaleDateString('ru-RU', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

function formatDuration(minutes) {
  if (minutes < 60) return `${minutes} мин`;
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return mins > 0 ? `${hours} ч ${mins} мин` : `${hours} ч`;
}

function generateRoomName(title) {
  return title.toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .trim() + '-' + Date.now().toString(36).substring(0, 8);
}

function isValidEmail(email) {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email);
}

function showNotification(message, type = 'info') {
  const notification = document.createElement('div');
  notification.className = `notification notification-${type}`;
  notification.innerHTML = `
    <div class="notification-content">
      <i class="fas fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-triangle' : 'info-circle'}"></i>
      <span>${message}</span>
    </div>
  `;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.style.opacity = '0';
    notification.style.transform = 'translateY(-20px)';
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

function debounce(func, delay) {
  let timeoutId;
  return (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => func.apply(this, args), delay);
  };
}
EOF

  # HTML страницы
  cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jitsi Meet Planner • PRAXIS-OVO</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/css/main.css">
    <link rel="stylesheet" href="/css/responsive.css">
    <link rel="icon" href="/img/logo.svg">
</head>
<body>
    <div class="auth-container">
        <div class="auth-logo">
            <div class="auth-logo-icon">
                <i class="fas fa-video"></i>
            </div>
            <div class="auth-logo-text">Jitsi Meet Planner</div>
        </div>
        
        <h1 class="auth-title">Вход в систему планирования встреч</h1>
        
        <button class="btn btn-nextcloud" id="btn-nextcloud">
            <i class="fas fa-cloud"></i> Войти через Nextcloud
        </button>
        
        <div class="auth-divider">
            <div class="auth-divider-line"></div>
            <div>или</div>
            <div class="auth-divider-line"></div>
        </div>
        
        <button class="btn btn-secondary" id="btn-register">
            <i class="fas fa-user-plus"></i> Зарегистрироваться
        </button>
        
        <button class="btn btn-outline" id="btn-login">
            <i class="fas fa-sign-in-alt"></i> Войти по паролю
        </button>
        
        <p class="auth-switch" id="registration-hint">
            Первый пользователь с email администратора автоматически получит права админа
        </p>
    </div>

    <footer>
        <div class="container">
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO</p>
            <p>Интеграция с <a href="https://cloud.praxis-ovo.ru" target="_blank">Nextcloud Calendar</a></p>
        </div>
    </footer>

    <script src="/js/auth.js"></script>
    <script>
        document.getElementById('btn-nextcloud').addEventListener('click', () => {
            window.location.href = '/api/auth/nextcloud';
        });
        
        document.getElementById('btn-register').addEventListener('click', () => {
            window.location.href = '/register.html';
        });
        
        document.getElementById('btn-login').addEventListener('click', () => {
            alert('Функция входа по паролю будет доступна после регистрации первого пользователя');
            window.location.href = '/register.html';
        });
        
        fetch('/api/auth/config/public')
          .then(response => response.json())
          .then(data => {
            if (!data.ALLOW_EMAIL_REGISTRATION) {
              document.getElementById('btn-register').disabled = true;
              document.getElementById('btn-register').title = 'Регистрация по почте отключена администратором';
              document.getElementById('registration-hint').innerHTML = 
                '<span style="color: #f44336; font-weight: bold;">⚠ Регистрация по почте отключена администратором</span><br>Используйте вход через Nextcloud';
            }
          })
          .catch(() => {});
        
        checkAuthStatus();
    </script>
</body>
</html>
EOF

  cat > public/register.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Регистрация • Jitsi Meet Planner</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/css/main.css">
    <link rel="stylesheet" href="/css/responsive.css">
    <link rel="icon" href="/img/logo.svg">
</head>
<body>
    <div class="container">
        <div style="text-align: center; margin: 40px 0;">
            <div class="auth-logo">
                <div class="auth-logo-icon">
                    <i class="fas fa-video"></i>
                </div>
                <div class="auth-logo-text">Jitsi Meet Planner</div>
            </div>
        </div>
        
        <div class="card">
            <div class="card-header">
                <h2 class="card-title">
                    <i class="fas fa-user-plus"></i> Регистрация нового пользователя
                </h2>
            </div>
            
            <div id="alert-container"></div>
            
            <form id="register-form">
                <div class="form-group">
                    <label for="name">
                        <i class="fas fa-user"></i> Имя и фамилия *
                    </label>
                    <input type="text" id="name" class="form-control" placeholder="Иван Петров" required>
                </div>
                
                <div class="form-group">
                    <label for="email">
                        <i class="fas fa-envelope"></i> Email *
                    </label>
                    <input type="email" id="email" class="form-control" placeholder="ivan@example.com" required>
                    <small id="admin-hint" style="display: block; margin-top: 8px; color: var(--primary); font-weight: 500;">
                        Первый пользователь с этим email станет администратором системы
                    </small>
                </div>
                
                <div class="form-group">
                    <label for="password">
                        <i class="fas fa-lock"></i> Пароль (минимум 6 символов) *
                    </label>
                    <input type="password" id="password" class="form-control" minlength="6" required>
                </div>
                
                <div class="form-group">
                    <label for="password-confirm">
                        <i class="fas fa-lock"></i> Подтверждение пароля *
                    </label>
                    <input type="password" id="password-confirm" class="form-control" minlength="6" required>
                </div>
                
                <div class="form-actions" style="display: flex; gap: 15px; margin-top: 10px;">
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-user-check"></i> Зарегистрироваться
                    </button>
                    <a href="/" class="btn btn-secondary">
                        <i class="fas fa-arrow-left"></i> Отмена
                    </a>
                </div>
            </form>
        </div>
    </div>

    <footer>
        <div class="container">
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO</p>
        </div>
    </footer>

    <script src="/js/auth.js"></script>
    <script src="/js/utils.js"></script>
    <script>
        fetch('/api/auth/config/public')
          .then(response => response.json())
          .then(data => {
            document.getElementById('admin-hint').innerHTML = 
              `Первый пользователь с email <strong>${data.ADMIN_EMAIL}</strong> станет администратором системы`;
              
            if (!data.ALLOW_EMAIL_REGISTRATION) {
              document.getElementById('register-form').innerHTML = `
                <div class="alert alert-error">
                  <i class="fas fa-ban"></i> Регистрация по почте отключена администратором
                </div>
                <p style="margin: 20px 0; font-size: 18px;">
                  Для входа в систему используйте <strong>авторизацию через Nextcloud</strong>.
                </p>
                <div style="text-align: center;">
                  <button class="btn btn-nextcloud" onclick="window.location.href='/api/auth/nextcloud'">
                    <i class="fas fa-cloud"></i> Войти через Nextcloud
                  </button>
                </div>
              `;
            }
          })
          .catch(() => {});
        
        document.getElementById('register-form').addEventListener('submit', async (e) => {
          e.preventDefault();
          
          const name = document.getElementById('name').value.trim();
          const email = document.getElementById('email').value.trim();
          const password = document.getElementById('password').value;
          const passwordConfirm = document.getElementById('password-confirm').value;
          
          if (password !== passwordConfirm) {
            showAlert('Пароли не совпадают', 'error');
            return;
          }
          
          try {
            const response = await fetch('/api/auth/register', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ name, email, password })
            });
            
            const data = await response.json();
            
            if (response.ok) {
              localStorage.setItem('authToken', data.token);
              showAlert('Регистрация успешна! Перенаправляем в систему...', 'success');
              
              setTimeout(() => {
                window.location.href = '/dashboard.html';
              }, 1500);
            } else {
              showAlert(data.error || 'Ошибка регистрации', 'error');
            }
          } catch (error) {
            showAlert('Ошибка подключения к серверу', 'error');
            console.error('Ошибка регистрации:', error);
          }
        });
        
        function showAlert(message, type) {
          const container = document.getElementById('alert-container');
          container.innerHTML = `
            <div class="alert alert-${type}">
              <i class="fas fa-${type === 'success' ? 'check-circle' : 'exclamation-triangle'}"></i>
              ${message}
            </div>
          `;
          
          if (type === 'success') {
            setTimeout(() => container.innerHTML = '', 5000);
          }
        }
    </script>
</body>
</html>
EOF

  cat > public/dashboard.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Мои встречи • Jitsi Meet Planner</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/css/main.css">
    <link rel="stylesheet" href="/css/responsive.css">
    <link rel="icon" href="/img/logo.svg">
</head>
<body>
    <nav>
        <div class="navbar-container">
            <a href="/dashboard.html" class="logo">
                <div class="logo-icon">
                    <i class="fas fa-video"></i>
                </div>
                <div class="logo-text">Jitsi Meet Planner</div>
            </a>
            <div class="nav-links">
                <div class="nav-item active" id="nav-conferences">
                    <i class="fas fa-calendar-alt"></i> Мои встречи
                </div>
                <div class="nav-item" id="nav-new">
                    <i class="fas fa-plus-circle"></i> Новая встреча
                </div>
                <div class="nav-item" id="nav-admin" style="display: none;">
                    <i class="fas fa-shield-alt"></i> Администрирование
                </div>
            </div>
            <div class="user-menu">
                <div class="user-name" id="user-name">Загрузка...</div>
                <div class="user-avatar" id="user-avatar">?</div>
            </div>
        </div>
    </nav>

    <div id="conferences-page" class="page active">
        <div class="container">
            <div class="page-header">
                <h1 class="page-title">Запланированные встречи</h1>
                <p class="page-subtitle">Управляйте своими видеоконференциями и синхронизируйте их с календарем Nextcloud</p>
            </div>

            <div class="card">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-calendar-check"></i> Предстоящие встречи
                    </div>
                    <button class="btn btn-primary" id="btn-create-conference">
                        <i class="fas fa-plus"></i> Создать встречу
                    </button>
                </div>

                <div id="conferences-container">
                    <div class="loading">
                        <div class="spinner"></div>
                        <p>Загрузка встреч...</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div id="new-conference-page" class="page">
        <div class="container">
            <div class="page-header">
                <h1 class="page-title">Создание новой встречи</h1>
                <p class="page-subtitle">Заполните данные для планирования видеоконференции. Ссылка будет автоматически сгенерирована и добавлена в календарь Nextcloud.</p>
            </div>

            <div class="card">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-plus-circle"></i> Детали встречи
                    </div>
                </div>

                <div id="form-alert-container"></div>

                <form id="conference-form">
                    <div class="form-group">
                        <label for="conference-title">
                            <i class="fas fa-heading"></i> Название встречи <span style="color: var(--danger);">*</span>
                        </label>
                        <input type="text" id="conference-title" class="form-control" placeholder="Например: Еженедельный стендап команды" required>
                    </div>

                    <div class="form-group">
                        <label for="conference-description">
                            <i class="fas fa-sticky-note"></i> Описание (опционально)
                        </label>
                        <textarea id="conference-description" class="form-control" rows="4" placeholder="Добавьте повестку дня или важную информацию для участников"></textarea>
                    </div>

                    <div class="form-row">
                        <div class="form-col">
                            <div class="form-group">
                                <label for="conference-date">
                                    <i class="fas fa-calendar-day"></i> Дата <span style="color: var(--danger);">*</span>
                                </label>
                                <input type="date" id="conference-date" class="form-control" required>
                            </div>
                        </div>
                        <div class="form-col">
                            <div class="form-group">
                                <label for="conference-time">
                                    <i class="far fa-clock"></i> Время <span style="color: var(--danger);">*</span>
                                </label>
                                <input type="time" id="conference-time" class="form-control" required>
                            </div>
                        </div>
                    </div>

                    <div class="form-group">
                        <label for="conference-duration">
                            <i class="fas fa-stopwatch"></i> Продолжительность <span style="color: var(--danger);">*</span>
                        </label>
                        <select id="conference-duration" class="form-control" required>
                            <option value="15">15 минут</option>
                            <option value="30" selected>30 минут</option>
                            <option value="45">45 минут</option>
                            <option value="60">1 час</option>
                            <option value="90">1.5 часа</option>
                            <option value="120">2 часа</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label for="conference-participants">
                            <i class="fas fa-user-friends"></i> Участники (email через запятую)
                        </label>
                        <input type="text" id="conference-participants" class="form-control" placeholder="ivan@example.com, maria@example.com">
                        <small style="color: var(--gray); display: block; margin-top: 8px;">
                            Участники получат приглашение по электронной почте со ссылкой на встречу
                        </small>
                    </div>

                    <div class="form-group">
                        <div style="display: flex; align-items: center; gap: 15px; background: #e8f4ff; padding: 20px; border-radius: var(--border-radius);">
                            <i class="fas fa-calendar-check" style="font-size: 28px; color: var(--primary);"></i>
                            <div>
                                <strong style="color: var(--primary); font-size: 18px;">Автоматическая синхронизация</strong>
                                <p style="margin: 8px 0 0 0; color: var(--gray); font-size: 16px;">
                                    Встреча будет автоматически добавлена в календарь Nextcloud: 
                                    <strong>cloud.praxis-ovo.ru</strong>
                                </p>
                            </div>
                        </div>
                    </div>

                    <div style="display: flex; gap: 15px; margin-top: 20px;">
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-calendar-plus"></i> Создать встречу
                        </button>
                        <button type="button" class="btn btn-secondary" id="btn-cancel">
                            <i class="fas fa-times"></i> Отмена
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <div id="delete-modal" class="modal">
        <div class="modal-content">
            <button class="modal-close" id="close-delete-modal">&times;</button>
            <h2 style="font-size: 28px; margin-bottom: 25px; color: var(--danger);">
                <i class="fas fa-trash-alt"></i> Удалить встречу?
            </h2>
            <p style="font-size: 19px; margin-bottom: 35px; line-height: 1.7;">
                Вы уверены, что хотите удалить встречу "<span id="delete-conference-title"></span>"? 
                Это действие также удалит событие из календаря Nextcloud.
            </p>
            <div style="display: flex; gap: 15px;">
                <button class="btn btn-danger" id="confirm-delete">
                    <i class="fas fa-trash-alt"></i> Удалить
                </button>
                <button class="btn btn-secondary" id="cancel-delete">
                    <i class="fas fa-times"></i> Отмена
                </button>
            </div>
        </div>
    </div>

    <footer>
        <div class="container">
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO • <a href="https://meet.praxis-ovo.ru" target="_blank">meet.praxis-ovo.ru</a></p>
            <p style="margin-top: 8px;">
                Интеграция с <strong>Nextcloud Calendar</strong>: 
                <a href="https://cloud.praxis-ovo.ru" target="_blank">cloud.praxis-ovo.ru</a>
            </p>
        </div>
    </footer>

    <script src="/js/auth.js"></script>
    <script src="/js/conferences.js"></script>
    <script src="/js/utils.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', async () => {
          const token = getAuthToken();
          if (!token) {
            window.location.href = '/';
            return;
          }
          
          try {
            const userData = await loadUserData();
            document.getElementById('user-name').textContent = userData.name;
            document.getElementById('user-avatar').textContent = userData.name.charAt(0);
            
            if (userData.role === 'admin') {
              document.getElementById('nav-admin').style.display = 'block';
            }
          } catch (error) {
            window.location.href = '/';
          }
          
          loadConferences();
          
          const tomorrow = new Date();
          tomorrow.setDate(tomorrow.getDate() + 1);
          document.getElementById('conference-date').valueAsDate = tomorrow;
          document.getElementById('conference-time').value = '10:00';
          
          document.getElementById('nav-conferences').addEventListener('click', () => showPage('conferences-page'));
          document.getElementById('nav-new').addEventListener('click', () => showPage('new-conference-page'));
          document.getElementById('nav-admin').addEventListener('click', () => window.location.href = '/admin.html');
          document.getElementById('btn-create-conference').addEventListener('click', () => showPage('new-conference-page'));
          document.getElementById('btn-cancel').addEventListener('click', () => showPage('conferences-page'));
          document.getElementById('conference-form').addEventListener('submit', createConference);
        });
    </script>
</body>
</html>
EOF

  cat > public/admin.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Администрирование • Jitsi Meet Planner</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="/css/main.css">
    <link rel="stylesheet" href="/css/responsive.css">
    <link rel="icon" href="/img/logo.svg">
</head>
<body>
    <nav>
        <div class="navbar-container">
            <a href="/dashboard.html" class="logo">
                <div class="logo-icon">
                    <i class="fas fa-video"></i>
                </div>
                <div class="logo-text">Jitsi Meet Planner</div>
            </a>
            <div class="nav-links">
                <div class="nav-item" onclick="window.location.href='/dashboard.html'">
                    <i class="fas fa-calendar-alt"></i> Мои встречи
                </div>
                <div class="nav-item" onclick="window.location.href='/new-conference.html'">
                    <i class="fas fa-plus-circle"></i> Новая встреча
                </div>
                <div class="nav-item active">
                    <i class="fas fa-shield-alt"></i> Администрирование
                </div>
            </div>
            <div class="user-menu">
                <div class="user-name" id="user-name">Загрузка...</div>
                <div class="user-avatar" id="user-avatar">?</div>
            </div>
        </div>
    </nav>

    <div class="container" style="padding: 40px 0;">
        <div class="page-header">
            <h1 class="page-title">Административная панель</h1>
            <p class="page-subtitle">Мониторинг системы, управление пользователями и настройками</p>
        </div>

        <div class="tabs">
            <button class="tab active" data-tab="stats">Статистика</button>
            <button class="tab" data-tab="users">Пользователи</button>
            <button class="tab" data-tab="conferences">Все конференции</button>
            <button class="tab" data-tab="settings">Настройки</button>
        </div>

        <div id="tab-stats" class="tab-content">
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-icon users">
                        <i class="fas fa-users"></i>
                    </div>
                    <div class="stat-value" id="stat-users">0</div>
                    <div class="stat-label">Всего пользователей</div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon meetings">
                        <i class="fas fa-video"></i>
                    </div>
                    <div class="stat-value" id="stat-meetings">0</div>
                    <div class="stat-label">Всего встреч</div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon calendar">
                        <i class="fas fa-calendar-alt"></i>
                    </div>
                    <div class="stat-value" id="stat-synced">0</div>
                    <div class="stat-label">Синхронизировано</div>
                </div>
                <div class="stat-card">
                    <div class="stat-icon active">
                        <i class="fas fa-bullseye"></i>
                    </div>
                    <div class="stat-value" id="stat-active">0</div>
                    <div class="stat-label">Активных встреч</div>
                </div>
            </div>

            <div class="card" style="margin-top: 40px;">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-server"></i> Системная информация
                    </div>
                </div>
                <div style="padding: 30px;">
                    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 25px;">
                        <div>
                            <h3 style="font-size: 20px; margin-bottom: 15px; color: var(--dark);"><i class="fas fa-database"></i> База данных</h3>
                            <p><strong>MongoDB:</strong> <span id="db-status">Проверка...</span></p>
                            <p><strong>Версия:</strong> <span id="db-version">-</span></p>
                        </div>
                        <div>
                            <h3 style="font-size: 20px; margin-bottom: 15px; color: var(--dark);"><i class="fas fa-code"></i> Приложение</h3>
                            <p><strong>Node.js:</strong> <span id="node-version">-</span></p>
                            <p><strong>Статус:</strong> <span id="app-status" style="color: var(--success); font-weight: bold;">Работает</span></p>
                        </div>
                        <div>
                            <h3 style="font-size: 20px; margin-bottom: 15px; color: var(--dark);"><i class="fas fa-cloud"></i> Nextcloud</h3>
                            <p><strong>Статус:</strong> <span id="nextcloud-status">Проверка...</span></p>
                            <p><strong>OAuth2:</strong> <span id="oauth-status">-</span></p>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div id="tab-users" class="tab-content" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-users-cog"></i> Управление пользователями
                    </div>
                    <button class="btn btn-primary" id="btn-add-user">
                        <i class="fas fa-user-plus"></i> Добавить пользователя
                    </button>
                </div>
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th><i class="fas fa-user"></i> Имя</th>
                                <th><i class="fas fa-envelope"></i> Email</th>
                                <th><i class="fas fa-id-badge"></i> Роль</th>
                                <th><i class="fas fa-calendar"></i> Регистрация</th>
                                <th><i class="fas fa-clock"></i> Последний вход</th>
                                <th><i class="fas fa-cog"></i> Действия</th>
                            </tr>
                        </thead>
                        <tbody id="users-table-body">
                            <tr>
                                <td colspan="6" style="text-align: center; padding: 40px;">
                                    <div class="spinner"></div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-conferences" class="tab-content" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-th-list"></i> Все конференции
                    </div>
                </div>
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th><i class="fas fa-heading"></i> Название</th>
                                <th><i class="fas fa-user"></i> Организатор</th>
                                <th><i class="fas fa-calendar"></i> Дата и время</th>
                                <th><i class="fas fa-stopwatch"></i> Длительность</th>
                                <th><i class="fas fa-users"></i> Участники</th>
                                <th><i class="fas fa-sync"></i> Календарь</th>
                                <th><i class="fas fa-cog"></i> Статус</th>
                            </tr>
                        </thead>
                        <tbody id="conferences-table-body">
                            <tr>
                                <td colspan="7" style="text-align: center; padding: 40px;">
                                    <div class="spinner"></div>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-settings" class="tab-content" style="display: none;">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">
                        <i class="fas fa-cog"></i> Настройки системы
                    </div>
                </div>
                
                <div class="toggle-container">
                    <div style="flex: 1;">
                        <h3 style="font-size: 20px; margin-bottom: 8px;">Разрешить регистрацию по почте</h3>
                        <p style="color: var(--gray); font-size: 16px;">
                            Когда отключено, пользователи могут входить только через Nextcloud OAuth2
                        </p>
                    </div>
                    <label class="toggle-switch">
                        <input type="checkbox" id="toggle-email-registration">
                        <span class="slider"></span>
                    </label>
                </div>
                
                <div class="toggle-container">
                    <div style="flex: 1;">
                        <h3 style="font-size: 20px; margin-bottom: 8px;">Разрешить вход через Nextcloud</h3>
                        <p style="color: var(--gray); font-size: 16px;">
                            Включение/отключение авторизации через корпоративные учетные записи Nextcloud
                        </p>
                    </div>
                    <label class="toggle-switch">
                        <input type="checkbox" id="toggle-nextcloud-oauth">
                        <span class="slider"></span>
                    </label>
                </div>
                
                <div class="toggle-container">
                    <div style="flex: 1;">
                        <h3 style="font-size: 20px; margin-bottom: 8px;">Синхронизация с календарем</h3>
                        <p style="color: var(--gray); font-size: 16px;">
                            Автоматическая синхронизация встреч с календарем Nextcloud
                        </p>
                    </div>
                    <label class="toggle-switch">
                        <input type="checkbox" id="toggle-calendar-sync">
                        <span class="slider"></span>
                    </label>
                </div>
                
                <div class="alert alert-info" style="margin-top: 30px;">
                    <i class="fas fa-info-circle"></i>
                    <strong>Важно:</strong> Изменения применяются немедленно. Отключение регистрации по почте не влияет на уже зарегистрированных пользователей.
                </div>
            </div>
        </div>
    </div>

    <footer>
        <div class="container">
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO • Административная панель</p>
        </div>
    </footer>

    <script src="/js/auth.js"></script>
    <script src="/js/admin.js"></script>
    <script src="/js/utils.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', async () => {
          const token = getAuthToken();
          if (!token) {
            window.location.href = '/';
            return;
          }
          
          try {
            const userData = await loadUserData();
            if (userData.role !== 'admin') {
              alert('У вас нет прав администратора');
              window.location.href = '/dashboard.html';
              return;
            }
            
            document.getElementById('user-name').textContent = userData.name;
            document.getElementById('user-avatar').textContent = userData.name.charAt(0);
            
            loadStats();
            loadUsers();
            loadAllConferences();
            loadSystemInfo();
            loadSettings();
            
          } catch (error) {
            window.location.href = '/';
          }
          
          document.querySelectorAll('.tab').forEach(tab => {
            tab.addEventListener('click', () => {
              document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
              tab.classList.add('active');
              
              document.querySelectorAll('.tab-content').forEach(content => {
                content.style.display = 'none';
              });
              
              const tabName = tab.getAttribute('data-tab');
              document.getElementById(`tab-${tabName}`).style.display = 'block';
              
              if (tabName === 'settings') loadSettings();
            });
          });
        });
    </script>
</body>
</html>
EOF

  # Изображения
  mkdir -p public/img
  cat > public/img/logo.svg <<'EOF'
<svg width="48" height="48" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="48" height="48" rx="12" fill="url(#paint0_linear_1_2)"/>
  <path d="M18 16L30 24L18 32V16Z" fill="white"/>
  <defs>
    <linearGradient id="paint0_linear_1_2" x1="0" y1="0" x2="48" y2="48" gradientUnits="userSpaceOnUse">
      <stop stop-color="#667EEA"/>
      <stop offset="1" stop-color="#764BA2"/>
    </linearGradient>
  </defs>
</svg>
EOF

  cat > public/img/nextcloud.svg <<'EOF'
<svg width="32" height="32" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M16 2C8.268 2 2 8.268 2 16C2 23.732 8.268 30 16 30C23.732 30 30 23.732 30 16C30 8.268 23.732 2 16 2Z" fill="#0082C9"/>
  <path d="M16 8C12.134 8 9 11.134 9 15C9 18.866 12.134 22 16 22C19.866 22 23 18.866 23 15C23 11.134 19.866 8 16 8Z" fill="white"/>
</svg>
EOF

  print_success "Полная структура приложения создана"
}

install_dependencies() {
  print_header "Установка зависимостей приложения"
  cd /opt/jitsi-planner
  sudo -u jitsi-planner npm install --production 2>/dev/null || {
    print_warning "Установка через npm не удалась, пробуем с правами root...";
    npm install --production --unsafe-perm
    chown -R jitsi-planner:jitsi-planner node_modules 2>/dev/null || true
  }
  print_success "Зависимости установлены"
}

create_env_file() {
  print_header "Создание файла конфигурации .env"
  
  ENV_FILE="/opt/jitsi-planner/.env"
  [ -f "$ENV_FILE" ] && {
    print_warning "Файл .env существует. Создаем резервную копию...";
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)";
  }
  
  JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || echo "change-this-in-production")
  
  cat > "$ENV_FILE" <<EOF
# ============================================================================
# Jitsi Meet Planner — Конфигурация для Ubuntu 24.04
# ============================================================================

# Сервер
PORT=3000
NODE_ENV=production
FRONTEND_URL=https://meet.praxis-ovo.ru

# База данных
MONGODB_URI=mongodb://localhost:27017/jitsi-planner
JWT_SECRET=$JWT_SECRET

# Nextcloud - основные настройки
NEXTCLOUD_URL=https://cloud.praxis-ovo.ru

# Nextcloud Calendar (CalDAV)
NEXTCLOUD_USERNAME=
NEXTCLOUD_PASSWORD=
NEXTCLOUD_CALENDAR_ID=KxEdrRwsMpJg

# Nextcloud OAuth2 (авторизация через корпоративные учетные записи)
NEXTCLOUD_OAUTH_ENABLED=false
NEXTCLOUD_OAUTH_CLIENT_ID=
NEXTCLOUD_OAUTH_CLIENT_SECRET=
NEXTCLOUD_OAUTH_AUTH_URL=https://cloud.praxis-ovo.ru/apps/oauth2/authorize
NEXTCLOUD_OAUTH_TOKEN_URL=https://cloud.praxis-ovo.ru/apps/oauth2/api/v1/token
NEXTCLOUD_OAUTH_USERINFO_URL=https://cloud.praxis-ovo.ru/ocs/v2.php/cloud/user?format=json
NEXTCLOUD_OAUTH_REDIRECT_URI=https://meet.praxis-ovo.ru/api/auth/nextcloud/callback
NEXTCLOUD_OAUTH_SCOPES=openid,profile,email

# Администратор
ADMIN_EMAIL=admin@praxis-ovo.com

# Jitsi Meet
JITSI_DOMAIN=meet.praxis-ovo.ru
EOF
  
  chown jitsi-planner:jitsi-planner "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  print_success "Файл .env создан: $ENV_FILE"
}

setup_systemd() {
  print_header "Настройка systemd сервиса"
  
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
TimeoutSec=300
StandardOutput=journal
StandardError=journal
SyslogIdentifier=jitsi-planner

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable jitsi-planner
  systemctl start jitsi-planner
  
  sleep 8
  if systemctl is-active --quiet jitsi-planner; then
    print_success "Сервис запущен"
  else
    print_warning "Сервис запускается. Проверьте: systemctl status jitsi-planner"
  fi
}

setup_nginx() {
  print_header "Настройка Nginx"
  
  if ! command -v nginx &>/dev/null; then
    read -p "Установить Nginx? (y/n): " -n1 -r; echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { print_info "Пропускаем Nginx"; return 0; }
    apt-get install -y -qq nginx
  fi
  
  cat > /etc/nginx/sites-available/jitsi-planner <<'EOF'
server {
    listen 80;
    server_name meet.praxis-ovo.ru;

    client_max_body_size 20M;
    access_log /var/log/nginx/jitsi-planner-access.log;
    error_log /var/log/nginx/jitsi-planner-error.log;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        root /opt/jitsi-planner/public;
        try_files $uri $uri/ @backend;
    }

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
}
EOF
  
  ln -sf /etc/nginx/sites-available/jitsi-planner /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx -t && systemctl reload nginx && print_success "Nginx настроен"
}

# 🔑 Создание администратора с учетными данными admin / Jitsy2026
create_admin_user() {
  print_header "Создание администратора: admin@praxis-ovo.com / Jitsy2026"
  
  cat > /tmp/create-admin.js <<'EOF'
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

// Подключение к БД
mongoose.connect('mongodb://localhost:27017/jitsi-planner', {
  useNewUrlParser: true,
  useUnifiedTopology: true
});

// Модель пользователя
const userSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  password: { type: String, minlength: 6 },
  name: { type: String, required: true, trim: true },
  role: { type: String, enum: ['user', 'admin'], default: 'user' },
  authProvider: { type: String, enum: ['local', 'nextcloud'], default: 'local' }
});

userSchema.pre('save', async function(next) {
  if (!this.isModified('password') || !this.password) return next();
  this.password = await bcrypt.hash(this.password, 10);
  next();
});

const User = mongoose.model('User', userSchema);

async function createAdmin() {
  try {
    // Проверка существующего администратора
    const existingAdmin = await User.findOne({ email: 'admin@praxis-ovo.com' });
    if (existingAdmin) {
      console.log('⚠ Администратор уже существует:', existingAdmin.email);
      process.exit(0);
    }
    
    // Создание администратора
    const admin = new User({
      email: 'admin@praxis-ovo.com',
      password: 'Jitsy2026',
      name: 'Администратор',
      role: 'admin',
      authProvider: 'local'
    });
    
    await admin.save();
    console.log('✅ Администратор успешно создан:');
    console.log('   Email: admin@praxis-ovo.com');
    console.log('   Пароль: Jitsy2026');
    console.log('   Роль: admin');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Ошибка создания администратора:', error.message);
    process.exit(1);
  }
}

createAdmin();
EOF

  # Запуск скрипта создания администратора
  cd /opt/jitsi-planner
  sudo -u jitsi-planner node /tmp/create-admin.js || {
    print_error "Не удалось создать администратора. Проверьте логи MongoDB."
    exit 1
  }
  
  rm -f /tmp/create-admin.js
  print_success "Администратор создан: admin@praxis-ovo.com / Jitsy2026"
}

verify_installation() {
  print_header "Проверка установки"
  
  echo "MongoDB: $(systemctl is-active mongod 2>/dev/null || echo 'не активна')"
  echo "Сервис: $(systemctl is-active jitsi-planner 2>/dev/null || echo 'не активен')"
  echo "Node.js: $(node -v 2>/dev/null || echo 'не установлен')"
  echo "Health: $(curl -s http://localhost:3000/api/health | grep -o 'ok' || echo 'не отвечает')"
}

show_completion() {
  cat <<EOF

${GREEN}================================================${NC}
${GREEN}✅ Установка для Ubuntu 24.04 завершена!${NC}
${GREEN}================================================${NC}

${YELLOW}🔑 Учетные данные администратора:${NC}
   Email:    admin@praxis-ovo.com
   Пароль:   Jitsy2026
   Роль:     Администратор системы

${YELLOW}📋 Следующие шаги:${NC}

1. ${YELLOW}Настройте SSL сертификат (обязательно!):${NC}
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d meet.praxis-ovo.ru

2. ${YELLOW}Настройте интеграцию с Nextcloud (опционально):${NC}
   a. Откройте: https://cloud.praxis-ovo.ru/settings/admin/security
   b. Перейдите: «Безопасность» → «OAuth 2.0»
   c. Добавьте клиент:
        Имя: Jitsi Meet Planner
        Редирект: https://meet.praxis-ovo.ru/api/auth/nextcloud/callback
   d. Скопируйте Client ID и Secret
   e. Откройте: sudo nano /opt/jitsi-planner/.env
   f. Укажите:
        NEXTCLOUD_OAUTH_ENABLED=true
        NEXTCLOUD_OAUTH_CLIENT_ID=ваш_client_id
        NEXTCLOUD_OAUTH_CLIENT_SECRET=ваш_client_secret
   g. Перезапустите: sudo systemctl restart jitsi-planner

3. ${YELLOW}Войдите в систему:${NC}
   Откройте в браузере: ${BLUE}https://meet.praxis-ovo.ru${NC}
   Используйте учетные данные администратора:
      Email: admin@praxis-ovo.com
      Пароль: Jitsy2026

4. ${YELLOW}Управление регистрацией:${NC}
   После входа откройте «Администрирование» → «Настройки»
   Переключите «Разрешить регистрацию по почте» ВКЛ/ВЫКЛ

${BLUE}📁 Важные пути:${NC}
   Приложение:      /opt/jitsi-planner/
   Конфигурация:    /opt/jitsi-planner/.env
   Логи приложения: sudo journalctl -u jitsi-planner -f
   Логи Nginx:      /var/log/nginx/jitsi-planner-*.log

${GREEN}🎉 Система готова к использованию!${NC}

EOF
}

main() {
  clear
  print_header "Jitsi Meet Planner — Полная установка для Ubuntu 24.04"
  
  check_root
  check_os
  
  echo; print_warning "Установка: Node.js 20.x, MongoDB 7.0, полный интерфейс"; echo
  read -p "Продолжить? (y/n): " -n1 -r; echo; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
  
  echo; print_info "Начинаем установку..."; echo
  
  cleanup_old_repos
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
  create_admin_user  # 🔑 Автоматическое создание администратора
  verify_installation
  
  echo; show_completion
}

main
exit 0
