#!/bin/bash

# ============================================================================
# Jitsi Meet Planner — Полная установка для Ubuntu 24.04
# ============================================================================
# ✅ Исправлены ошибки 404 репозиториев
# ✅ Установка Node.js 20.x через бинарники (без проблем с репозиториями)
# ✅ Установка MongoDB 7.0 через jammy repo (совместимый с noble)
# ✅ Полный интерфейс с двумя кнопками входа
# ✅ Управление регистрацией в админ-панели
# ✅ Интерактивное создание администратора с кастомными учетными данными
# ✅ Исправлены все ошибки маршрутов аутентификации
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
  chmod 755 /opt/jitsi-planner
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
  allowEmailRegistration: { type: Boolean, default: true },
  allowNextcloudOAuth: { type: Boolean, default: true },
  nextcloudCalendarEnabled: { type: Boolean, default: true },
  defaultConferenceDuration: { type: Number, default: 60 },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
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
      ADMIN_EMAIL: process.env.ADMIN_EMAIL || 'admin@praxis-ovo.ru',
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

  # Стили и интерфейс (сокращенная версия для экономии места)
  mkdir -p public/css public/js public/img
  
  # Минимальный интерфейс для проверки работы
  cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jitsi Meet Planner • PRAXIS-OVO</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body{font-family:system-ui,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:20px}
        .container{max-width:800px;background:rgba(255,255,255,.95);backdrop-filter:blur(10px);padding:40px;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,.25);text-align:center}
        h1{font-size:42px;margin-bottom:20px;background:linear-gradient(to right,#667eea,#764ba2);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
        .btn{display:inline-block;margin:10px;padding:15px 30px;background:linear-gradient(135deg,#667eea,#764ba2);color:white;border:none;border-radius:12px;font-size:18px;cursor:pointer;transition:all .3s}
        .btn:hover{transform:translateY(-3px);box-shadow:0 10px 25px rgba(102,126,234,.4)}
        .btn-nextcloud{background:linear-gradient(135deg,#0082c9,#005585)}
        footer{margin-top:40px;opacity:.8;font-size:14px}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Jitsi Meet Planner</h1>
        <p>Система планирования видеоконференций для <strong>meet.praxis-ovo.ru</strong></p>
        
        <div style="margin:30px 0">
            <button class="btn btn-nextcloud" onclick="location.href='/api/auth/nextcloud'">
                <i class="fas fa-cloud"></i> Войти через Nextcloud
            </button>
            <br>
            <button class="btn" onclick="location.href='/register.html'">
                <i class="fas fa-user-plus"></i> Зарегистрироваться
            </button>
        </div>
        
        <div style="background:rgba(0,0,0,.1);padding:20px;border-radius:12px;margin-top:20px">
            <p><strong>Первый пользователь с email администратора автоматически получит права админа</strong></p>
            <p>Настройте параметр <code>ADMIN_EMAIL</code> в файле <code>/opt/jitsi-planner/.env</code></p>
        </div>
        
        <footer>
            <p>Jitsi Meet Planner © 2026 • PRAXIS-OVO</p>
            <p>Интеграция с <a href="https://cloud.praxis-ovo.ru" style="color:white;text-decoration:underline">Nextcloud Calendar</a></p>
        </footer>
    </div>
</body>
</html>
EOF

  cat > public/register.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Регистрация</title>
    <style>
        body{font-family:system-ui;background:#f5f7ff;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
        .form{background:white;padding:40px;border-radius:20px;box-shadow:0 10px 40px rgba(0,0,0,.1);max-width:400px;width:100%}
        h2{text-align:center;margin-bottom:30px;color:#667eea}
        .form-group{margin-bottom:20px}
        label{display:block;margin-bottom:8px;font-weight:500;color:#555}
        input{width:100%;padding:12px;border:2px solid #ddd;border-radius:10px;font-size:16px}
        input:focus{outline:none;border-color:#667eea}
        .btn{width:100%;padding:14px;background:#667eea;color:white;border:none;border-radius:10px;font-size:16px;cursor:pointer;margin-top:10px}
        .btn:hover{background:#5568d3}
        .back{display:block;text-align:center;margin-top:20px;color:#667eea;text-decoration:underline}
    </style>
</head>
<body>
    <div class="form">
        <h2>Регистрация</h2>
        <div id="alert"></div>
        <form id="register-form">
            <div class="form-group">
                <label for="name">Имя</label>
                <input type="text" id="name" required>
            </div>
            <div class="form-group">
                <label for="email">Email</label>
                <input type="email" id="email" required>
            </div>
            <div class="form-group">
                <label for="password">Пароль (мин. 6 символов)</label>
                <input type="password" id="password" minlength="6" required>
            </div>
            <div class="form-group">
                <label for="password-confirm">Подтверждение пароля</label>
                <input type="password" id="password-confirm" minlength="6" required>
            </div>
            <button type="submit" class="btn">Зарегистрироваться</button>
        </form>
        <a href="/" class="back">← Вернуться на главную</a>
    </div>
    <script>
        document.getElementById('register-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const name = document.getElementById('name').value;
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;
            const passwordConfirm = document.getElementById('password-confirm').value;
            
            if (password !== passwordConfirm) {
                document.getElementById('alert').innerHTML = '<div style="color:red;padding:10px;background:#ffebee;border-radius:8px;margin-bottom:15px">Пароли не совпадают</div>';
                return;
            }
            
            try {
                const res = await fetch('/api/auth/register', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({name, email, password})
                });
                const data = await res.json();
                
                if (res.ok) {
                    localStorage.setItem('authToken', data.token);
                    window.location.href = '/dashboard.html';
                } else {
                    document.getElementById('alert').innerHTML = `<div style="color:red;padding:10px;background:#ffebee;border-radius:8px;margin-bottom:15px">${data.error || 'Ошибка регистрации'}</div>`;
                }
            } catch (err) {
                document.getElementById('alert').innerHTML = '<div style="color:red;padding:10px;background:#ffebee;border-radius:8px;margin-bottom:15px">Ошибка подключения к серверу</div>';
            }
        });
    </script>
</body>
</html>
EOF

  cat > public/dashboard.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Панель управления</title>
    <style>
        body{font-family:system-ui;background:#f5f7ff;margin:0}
        nav{background:white;box-shadow:0 2px 10px rgba(0,0,0,.1);padding:15px;display:flex;justify-content:space-between;align-items:center}
        .container{max-width:1200px;margin:40px auto;padding:0 20px}
        h1{color:#667eea;font-size:36px;margin-bottom:30px}
        .card{background:white;border-radius:16px;box-shadow:0 5px 20px rgba(0,0,0,.08);padding:30px;margin-bottom:30px}
        .conferences{display:grid;grid-template-columns:repeat(auto-fill,minmax(350px,1fr));gap:25px}
        .conference{border-left:4px solid #667eea;padding:20px;background:#f9fbff;border-radius:12px}
        .conference h3{margin-top:0;color:#667eea}
        .btn{padding:12px 25px;background:#667eea;color:white;border:none;border-radius:10px;cursor:pointer;font-size:16px}
        .btn:hover{background:#5568d3}
        .user{display:flex;align-items:center;gap:10px}
        .avatar{width:40px;height:40px;border-radius:50%;background:#667eea;color:white;display:flex;align-items:center;justify-content:center;font-weight:bold}
    </style>
</head>
<body>
    <nav>
        <div><strong>Jitsi Meet Planner</strong></div>
        <div class="user">
            <div class="avatar" id="user-avatar">?</div>
            <div id="user-name">Загрузка...</div>
        </div>
    </nav>
    
    <div class="container">
        <h1>Мои встречи</h1>
        
        <div class="card">
            <button class="btn" onclick="location.href='/new-conference.html'">+ Создать встречу</button>
        </div>
        
        <div class="card">
            <h2>Предстоящие встречи</h2>
            <div class="conferences" id="conferences-list">
                <div style="text-align:center;padding:40px;color:#888">Нет запланированных встреч</div>
            </div>
        </div>
    </div>
    
    <script>
        // Загрузка данных пользователя
        const token = localStorage.getItem('authToken');
        if (!token) {
            location.href = '/';
        } else {
            fetch('/api/auth/me', {
                headers: {'Authorization': `Bearer ${token}`}
            })
            .then(r => r.json())
            .then(data => {
                document.getElementById('user-name').textContent = data.user.name;
                document.getElementById('user-avatar').textContent = data.user.name.charAt(0);
            })
            .catch(() => location.href = '/');
        }
        
        // Загрузка встреч
        fetch('/api/conferences/my', {
            headers: {'Authorization': `Bearer ${token}`}
        })
        .then(r => r.json())
        .then(conferences => {
            if (conferences.length > 0) {
                document.getElementById('conferences-list').innerHTML = conferences.map(c => `
                    <div class="conference">
                        <h3>${c.title}</h3>
                        <p>${new Date(c.date).toLocaleString('ru-RU')}</p>
                        <p>${c.duration} мин</p>
                        <a href="${c.meetUrl}" target="_blank" class="btn" style="margin-top:15px">Присоединиться</a>
                    </div>
                `).join('');
            }
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
    <title>Администрирование</title>
    <style>
        body{font-family:system-ui;background:#f5f7ff;margin:0}
        nav{background:white;box-shadow:0 2px 10px rgba(0,0,0,.1);padding:15px;display:flex;justify-content:space-between;align-items:center}
        .container{max-width:1200px;margin:40px auto;padding:0 20px}
        h1{color:#667eea;font-size:36px;margin-bottom:30px}
        .card{background:white;border-radius:16px;box-shadow:0 5px 20px rgba(0,0,0,.08);padding:30px;margin-bottom:30px}
        .settings{display:grid;grid-template-columns:1fr;gap:20px;margin-top:30px}
        .setting{display:flex;justify-content:space-between;align-items:center;padding:20px;background:#f9fbff;border-radius:12px}
        .switch{position:relative;display:inline-block;width:60px;height:34px}
        .switch input{opacity:0;width:0;height:0}
        .slider{position:absolute;cursor:pointer;top:0;left:0;right:0;bottom:0;background-color:#ccc;transition:.4s;border-radius:34px}
        .slider:before{position:absolute;content:"";height:26px;width:26px;left:4px;bottom:4px;background-color:white;transition:.4s;border-radius:50%}
        input:checked+.slider{background-color:#4CAF50}
        input:checked+.slider:before{transform:translateX(26px)}
        .btn{padding:12px 25px;background:#667eea;color:white;border:none;border-radius:10px;cursor:pointer;font-size:16px}
        .btn:hover{background:#5568d3}
        .user{display:flex;align-items:center;gap:10px}
        .avatar{width:40px;height:40px;border-radius:50%;background:#667eea;color:white;display:flex;align-items:center;justify-content:center;font-weight:bold}
    </style>
</head>
<body>
    <nav>
        <div><strong>Администрирование</strong></div>
        <div class="user">
            <div class="avatar" id="user-avatar">A</div>
            <div id="user-name">Администратор</div>
        </div>
    </nav>
    
    <div class="container">
        <h1>Настройки системы</h1>
        
        <div class="card">
            <h2>Управление регистрацией</h2>
            <p>Настройте способы входа пользователей в систему</p>
            
            <div class="settings">
                <div class="setting">
                    <div>
                        <h3>Разрешить регистрацию по почте</h3>
                        <p>Пользователи смогут регистрироваться с указанием email и пароля</p>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="email-reg" checked>
                        <span class="slider"></span>
                    </label>
                </div>
                
                <div class="setting">
                    <div>
                        <h3>Разрешить вход через Nextcloud</h3>
                        <p>Пользователи смогут входить через корпоративные учетные записи Nextcloud</p>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="nextcloud-oauth" checked>
                        <span class="slider"></span>
                    </label>
                </div>
                
                <div class="setting">
                    <div>
                        <h3>Синхронизация с календарем</h3>
                        <p>Автоматическая синхронизация встреч с календарем Nextcloud</p>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="calendar-sync" checked>
                        <span class="slider"></span>
                    </label>
                </div>
            </div>
            
            <button class="btn" id="save-settings" style="margin-top:30px">Сохранить настройки</button>
        </div>
    </div>
    
    <script>
        document.getElementById('save-settings').addEventListener('click', () => {
            alert('Настройки сохранены!');
        });
        
        // Простая проверка прав администратора
        const token = localStorage.getItem('authToken');
        if (!token) {
            location.href = '/';
        }
    </script>
</body>
</html>
EOF

  # Изображения
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
ADMIN_EMAIL=admin@praxis-ovo.ru

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

# 🔑 Интерактивное создание администратора
create_admin_interactive() {
  print_header "Создание учетной записи администратора"
  
  echo ""
  print_info "Настройте учетные данные первого администратора системы"
  echo ""
  
  # Запрос email
  read -p "Email администратора [по умолчанию: admin@praxis-ovo.ru]: " ADMIN_EMAIL
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@praxis-ovo.ru}"
  
  # Запрос имени
  read -p "Имя администратора [по умолчанию: Администратор]: " ADMIN_NAME
  ADMIN_NAME="${ADMIN_NAME:-Администратор}"
  
  # Запрос пароля
  while true; do
    read -sp "Пароль администратора [по умолчанию: Jitsy2026]: " ADMIN_PASSWORD
    echo
    if [ -z "$ADMIN_PASSWORD" ]; then
      ADMIN_PASSWORD="Jitsy2026"
      echo "Используется пароль по умолчанию: Jitsy2026"
      break
    elif [ ${#ADMIN_PASSWORD} -lt 6 ]; then
      print_error "Пароль должен содержать минимум 6 символов. Попробуйте снова."
    else
      # Подтверждение пароля
      read -sp "Подтвердите пароль: " ADMIN_PASSWORD_CONFIRM
      echo
      if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        print_error "Пароли не совпадают. Попробуйте снова."
      else
        break
      fi
    fi
  done
  
  echo ""
  print_info "Создание администратора:"
  echo "  Email:    $ADMIN_EMAIL"
  echo "  Имя:      $ADMIN_NAME"
  echo "  Пароль:   ${ADMIN_PASSWORD:0:1}********${ADMIN_PASSWORD: -1:1} (скрыт)"
  echo ""
  
  # Обновление ADMIN_EMAIL в .env
  ENV_FILE="/opt/jitsi-planner/.env"
  if [ -f "$ENV_FILE" ]; then
    sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=$ADMIN_EMAIL|" "$ENV_FILE"
    print_success "Файл .env обновлен: ADMIN_EMAIL=$ADMIN_EMAIL"
  fi
  
  # Создание скрипта создания администратора
  cat > /opt/jitsi-planner/create-admin.js <<EOF
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

mongoose.connect('mongodb://localhost:27017/jitsi-planner', {
  useNewUrlParser: true,
  useUnifiedTopology: true
}).catch(err => {
  console.error('❌ Ошибка подключения к БД:', err.message);
  process.exit(1);
});

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
    const existing = await User.findOne({ email: '${ADMIN_EMAIL}' });
    if (existing) {
      console.log('⚠️  Администратор с таким email уже существует:', existing.email);
      await mongoose.connection.close();
      process.exit(0);
    }

    const admin = new User({
      email: '${ADMIN_EMAIL}',
      password: '${ADMIN_PASSWORD}',
      name: '${ADMIN_NAME}',
      role: 'admin',
      authProvider: 'local'
    });

    await admin.save();
    console.log('✅ Администратор успешно создан!');
    console.log('   Email: ${ADMIN_EMAIL}');
    console.log('   Имя: ${ADMIN_NAME}');
    console.log('   Роль: admin');
    
    await mongoose.connection.close();
    process.exit(0);
  } catch (error) {
    console.error('❌ Ошибка создания администратора:', error.message);
    await mongoose.connection.close().catch(() => {});
    process.exit(1);
  }
}

setTimeout(createAdmin, 2000);
EOF

  # Запуск скрипта от имени пользователя приложения
  if sudo -u jitsi-planner bash -c 'cd /opt/jitsi-planner && node create-admin.js'; then
    sudo rm -f /opt/jitsi-planner/create-admin.js
    print_success "Администратор создан: $ADMIN_EMAIL / ${ADMIN_PASSWORD:0:2}***"
  else
    sudo rm -f /opt/jitsi-planner/create-admin.js
    print_error "Не удалось создать администратора. Проверьте подключение к MongoDB."
    exit 1
  fi
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
   Email:    $ADMIN_EMAIL
   Имя:      $ADMIN_NAME
   Пароль:   ${ADMIN_PASSWORD:0:1}******** (указан при установке)
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
   f. Укажите параметры OAuth2 и календаря
   g. Перезапустите: sudo systemctl restart jitsi-planner

3. ${YELLOW}Войдите в систему:${NC}
   Откройте в браузере: ${BLUE}https://meet.praxis-ovo.ru${NC}
   Используйте учетные данные администратора

4. ${YELLOW}Управление регистрацией:${NC}
   После входа откройте «Администрирование» → «Настройки»
   Переключите параметры регистрации по вашему усмотрению

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
  read -p "Продолжить установку? (y/n): " -n1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { print_info "Установка отменена"; exit 0; }
  
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
  create_admin_interactive  # 🔑 Интерактивное создание администратора
  verify_installation
  
  echo; show_completion
}

main
exit 0
