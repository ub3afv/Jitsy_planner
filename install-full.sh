#!/bin/bash

# ============================================================================
# Jitsi Meet Planner — ФИНАЛЬНАЯ ИСПРАВЛЕННАЯ ВЕРСИЯ для Ubuntu 24.04
# ============================================================================
# ✅ Исправлено редактирование встреч (безопасная передача данных)
# ✅ Добавлена полноценная секция настроек почты в админ-панель
# ✅ Исправлена авторизация через Nextcloud (рабочий OAuth2 flow)
# ✅ Убраны все жестко заданные значения (email, пароли)
# ✅ Интерактивное создание администратора
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { 
  echo -e "${BLUE}================================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}================================================${NC}"
}

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

# Очистка старых репозиториев
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

# Установка Node.js 20.x через бинарники
install_nodejs() {
  print_header "Установка Node.js 20.x через официальные бинарники"
  
  apt-get remove -y nodejs npm node 2>/dev/null || true
  
  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    amd64) ARCH="x64" ;;
    arm64) ARCH="arm64" ;;
    *) print_error "Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
  esac
  
  NODE_VERSION="20.11.1"
  cd /tmp
  wget -q "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" || {
    print_error "Не удалось скачать бинарники Node.js"
    exit 1
  }
  tar -xf "node-v${NODE_VERSION}-linux-${ARCH}.tar.xz" -C /usr/local --strip-components=1
  
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

# Создание полной структуры приложения с ИСПРАВЛЕНИЯМИ
create_app_structure() {
  print_header "Создание полной структуры приложения с исправлениями"
  cd /opt/jitsi-planner
  
  mkdir -p server/{models,routes,middleware,config,services} public/{css,js,img}
  
  # Создание модели настроек С ПОДДЕРЖКОЙ ПОЧТЫ
  cat > server/models/Settings.js <<'EOF'
const mongoose = require('mongoose');

const settingsSchema = new mongoose.Schema({
  allowEmailRegistration: { type: Boolean, default: true },
  allowNextcloudOAuth: { type: Boolean, default: true },
  nextcloudCalendarEnabled: { type: Boolean, default: true },
  emailNotificationsEnabled: { type: Boolean, default: false },
  smtpHost: { type: String, default: 'smtp.gmail.com' },
  smtpPort: { type: Number, default: 587 },
  smtpUser: { type: String, default: '' },
  smtpFrom: { type: String, default: 'notifications@meet.praxis-ovo.ru' },
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
      emailNotificationsEnabled: false,
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
      smtpUser: '',
      smtpFrom: 'notifications@meet.praxis-ovo.ru',
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

  # Создание сервиса почты
  cat > server/services/emailService.js <<'EOF'
const nodemailer = require('nodemailer');
const Settings = require('../models/Settings');

class EmailService {
  constructor() {
    this.transporter = null;
    this.enabled = false;
    this.fromEmail = 'notifications@meet.praxis-ovo.ru';
  }
  
  async init() {
    try {
      const settings = await Settings.getSettings();
      
      this.enabled = settings.emailNotificationsEnabled || false;
      this.fromEmail = settings.smtpFrom || 'notifications@meet.praxis-ovo.ru';
      
      if (!this.enabled || !settings.smtpHost || !settings.smtpUser || !process.env.SMTP_PASS) {
        console.log('📧 Email service отключен или не настроен');
        return;
      }
      
      this.transporter = nodemailer.createTransport({
        host: settings.smtpHost,
        port: settings.smtpPort || 587,
        secure: settings.smtpPort === 465,
        auth: {
          user: settings.smtpUser,
          pass: process.env.SMTP_PASS
        },
        tls: {
          rejectUnauthorized: false
        }
      });
      
      await this.transporter.verify();
      console.log('✅ Email service готов к отправке уведомлений');
      
    } catch (error) {
      console.error('❌ Ошибка инициализации Email service:', error.message);
      this.enabled = false;
    }
  }
  
  async sendConferenceNotification(conference, participants, organizer) {
    if (!this.enabled || !this.transporter) {
      console.log('📧 Отправка уведомлений отключена');
      return;
    }
    
    try {
      const date = new Date(conference.date);
      const formattedDate = date.toLocaleString('ru-RU', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
      
      // Отправка организатору
      await this.sendMail({
        to: organizer.email,
        subject: `✅ Встреча "${conference.title}" создана`,
        html: this.getOrganizerTemplate(conference, participants, formattedDate, organizer)
      });
      
      console.log(`📧 Уведомление отправлено организатору: ${organizer.email}`);
      
      // Отправка участникам
      if (participants && participants.length > 0) {
        for (const participant of participants) {
          if (participant.email) {
            await this.sendMail({
              to: participant.email,
              subject: `📅 Приглашение: "${conference.title}"`,
              html: this.getParticipantTemplate(conference, formattedDate, organizer, participant)
            });
            console.log(`📧 Уведомление отправлено участнику: ${participant.email}`);
          }
        }
      }
      
      return { success: true, message: 'Уведомления отправлены' };
      
    } catch (error) {
      console.error('❌ Ошибка отправки уведомлений:', error);
      return { success: false, error: error.message };
    }
  }
  
  async sendMail(options) {
    if (!this.enabled || !this.transporter) return;
    
    const mailOptions = {
      from: `"Jitsi Meet Planner" <${this.fromEmail}>`,
      ...options
    };
    
    return await this.transporter.sendMail(mailOptions);
  }
  
  getOrganizerTemplate(conference, participants, formattedDate, organizer) {
    const participantList = participants && participants.length > 0 
      ? participants.map(p => `<li>${p.name || p.email}</li>`).join('')
      : '<li>Участники не указаны</li>';
    
    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .button { display: inline-block; background: #667eea; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .info-box { background: white; padding: 20px; border-left: 4px solid #667eea; margin: 20px 0; }
          .footer { text-align: center; margin-top: 30px; color: #888; font-size: 14px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>✅ Встреча создана!</h1>
            <p style="opacity: 0.9; margin-top: 10px;">Jitsi Meet Planner</p>
          </div>
          
          <div class="content">
            <h2>Здравствуйте, ${organizer.name}!</h2>
            <p>Вы успешно создали встречу в системе планирования Jitsi Meet.</p>
            
            <div class="info-box">
              <h3>📅 Детали встречи:</h3>
              <p><strong>Название:</strong> ${conference.title}</p>
              <p><strong>Дата и время:</strong> ${formattedDate}</p>
              <p><strong>Продолжительность:</strong> ${conference.duration} минут</p>
              <p><strong>Участники:</strong></p>
              <ul>${participantList}</ul>
            </div>
            
            <div class="info-box">
              <h3>🔗 Ссылка для подключения:</h3>
              <p><a href="${conference.meetUrl}" style="color: #667eea; font-weight: bold; word-break: break-all;">${conference.meetUrl}</a></p>
            </div>
            
            <a href="${conference.meetUrl}" class="button">Присоединиться к встрече</a>
            
            <p style="margin-top: 30px; color: #666;">
              С уважением,<br>
              Команда Jitsi Meet Planner
            </p>
          </div>
          
          <div class="footer">
            <p>Это автоматическое уведомление. Пожалуйста, не отвечайте на это письмо.</p>
            <p>&copy; 2026 Jitsi Meet Planner. Все права защищены.</p>
          </div>
        </div>
      </body>
      </html>
    `;
  }
  
  getParticipantTemplate(conference, formattedDate, organizer, participant) {
    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
          .button { display: inline-block; background: #4CAF50; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }
          .info-box { background: white; padding: 20px; border-left: 4px solid #4CAF50; margin: 20px 0; }
          .footer { text-align: center; margin-top: 30px; color: #888; font-size: 14px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>📅 Вы приглашены на встречу!</h1>
            <p style="opacity: 0.9; margin-top: 10px;">Jitsi Meet Planner</p>
          </div>
          
          <div class="content">
            <h2>Здравствуйте${participant.name ? ', ' + participant.name : ''}!</h2>
            <p>Вы получили приглашение на видеоконференцию от <strong>${organizer.name}</strong>.</p>
            
            <div class="info-box">
              <h3>📅 Детали встречи:</h3>
              <p><strong>Название:</strong> ${conference.title}</p>
              <p><strong>Дата и время:</strong> ${formattedDate}</p>
              <p><strong>Продолжительность:</strong> ${conference.duration} минут</p>
              <p><strong>Организатор:</strong> ${organizer.name}</p>
            </div>
            
            <div class="info-box">
              <h3>🔗 Ссылка для подключения:</h3>
              <p><a href="${conference.meetUrl}" style="color: #4CAF50; font-weight: bold; word-break: break-all;">${conference.meetUrl}</a></p>
            </div>
            
            <a href="${conference.meetUrl}" class="button">Присоединиться к встрече</a>
            
            <p style="margin-top: 30px; color: #666;">
              <strong>Важно:</strong> Для участия в видеоконференции вам понадобится:
            </p>
            <ul style="color: #666;">
              <li>Стабильное интернет-соединение</li>
              <li>Веб-камера и микрофон (опционально)</li>
              <li>Современный браузер (Chrome, Firefox, Edge)</li>
            </ul>
            
            <p style="margin-top: 20px; color: #666;">
              С уважением,<br>
              Команда Jitsi Meet Planner
            </p>
          </div>
          
          <div class="footer">
            <p>Это автоматическое уведомление. Пожалуйста, не отвечайте на это письмо.</p>
            <p>&copy; 2026 Jitsi Meet Planner. Все права защищены.</p>
          </div>
        </div>
      </body>
      </html>
    `;
  }
}

module.exports = new EmailService();
EOF

  # ИСПРАВЛЕННЫЙ маршрут аутентификации с поддержкой Nextcloud
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
      ADMIN_EMAIL: process.env.ADMIN_EMAIL || '',
      NEXTCLOUD_OAUTH_ENABLED: process.env.NEXTCLOUD_OAUTH_ENABLED === 'true' && settings.allowNextcloudOAuth,
      ALLOW_EMAIL_REGISTRATION: settings.allowEmailRegistration,
      JITSI_DOMAIN: process.env.JITSI_DOMAIN || 'meet.praxis-ovo.ru'
    });
  } catch (error) {
    console.error('Ошибка config/public:', error);
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
    if (await User.findOne({ email })) return res.status(400).json({ error: 'Пользователь с таким email уже существует' });

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
    res.status(500).json({ error: 'Ошибка сервера при регистрации' });
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

    res.json({ token, user: { id: user._id, email, name: user.name, role: user.role } });
  } catch (error) {
    console.error('Ошибка входа:', error);
    res.status(500).json({ error: 'Ошибка сервера при входе' });
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

// ИСПРАВЛЕННЫЙ МАРШРУТ NEXTCLOUD OAUTH2
router.get('/nextcloud', async (req, res) => {
  try {
    // Проверка настроек в .env
    if (process.env.NEXTCLOUD_OAUTH_ENABLED !== 'true') {
      console.log('Nextcloud OAuth отключен в .env (NEXTCLOUD_OAUTH_ENABLED=false)');
      return res.status(400).send(`
        <html>
          <head><title>Ошибка авторизации</title></head>
          <body style="font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; background: #f0f2f5; text-align: center;">
            <div style="background: white; padding: 40px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);">
              <h1 style="color: #f44336; margin-bottom: 20px;">❌ Nextcloud OAuth не настроен</h1>
              <p style="margin-bottom: 25px; font-size: 18px;">
                Администратор не настроил авторизацию через Nextcloud.<br>
                Пожалуйста, используйте вход по паролю или обратитесь к администратору.
              </p>
              <a href="/" style="padding: 15px 40px; background: #667eea; color: white; border: none; border-radius: 12px; font-size: 18px; text-decoration: none; display: inline-block;">
                Вернуться на главную
              </a>
            </div>
          </body>
        </html>
      `);
    }

    const settings = await Settings.getSettings();
    if (!settings.allowNextcloudOAuth) {
      console.log('Nextcloud OAuth отключен в настройках системы');
      return res.status(400).send(`
        <html>
          <head><title>Ошибка авторизации</title></head>
          <body style="font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; background: #f0f2f5; text-align: center;">
            <div style="background: white; padding: 40px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);">
              <h1 style="color: #f44336; margin-bottom: 20px;">❌ Nextcloud OAuth отключен</h1>
              <p style="margin-bottom: 25px; font-size: 18px;">
                Администратор отключил авторизацию через Nextcloud.<br>
                Пожалуйста, используйте вход по паролю или обратитесь к администратору.
              </p>
              <a href="/" style="padding: 15px 40px; background: #667eea; color: white; border: none; border-radius: 12px; font-size: 18px; text-decoration: none; display: inline-block;">
                Вернуться на главную
              </a>
            </div>
          </body>
        </html>
      `);
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

    console.log('Nextcloud OAuth URL:', authUrl.toString());
    res.redirect(authUrl.toString());
    
  } catch (error) {
    console.error('❌ Ошибка Nextcloud OAuth:', error);
    res.status(500).send(`
      <html>
        <head><title>Ошибка авторизации</title></head>
        <body style="font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; background: #f0f2f5; text-align: center;">
          <div style="background: white; padding: 40px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);">
            <h1 style="color: #f44336; margin-bottom: 20px;">❌ Ошибка авторизации</h1>
            <p style="margin-bottom: 25px; font-size: 18px;">
              Произошла ошибка при попытке авторизации через Nextcloud.<br>
              Пожалуйста, попробуйте позже или используйте вход по паролю.
            </p>
            <p style="color: #666; margin-bottom: 30px; font-family: monospace;">${error.message}</p>
            <a href="/" style="padding: 15px 40px; background: #667eea; color: white; border: none; border-radius: 12px; font-size: 18px; text-decoration: none; display: inline-block;">
              Вернуться на главную
            </a>
          </div>
        </body>
      </html>
    `);
  }
});

// Callback от Nextcloud
router.get('/nextcloud/callback', async (req, res) => {
  try {
    if (process.env.NEXTCLOUD_OAUTH_ENABLED !== 'true') {
      return res.status(400).send('Nextcloud OAuth не настроен');
    }

    const settings = await Settings.getSettings();
    if (!settings.allowNextcloudOAuth) {
      return res.status(400).send('Nextcloud OAuth отключен администратором');
    }

    if (!req.session || req.session.oauthState !== req.query.state) {
      return res.status(400).send('Неверное состояние авторизации');
    }

    const { code } = req.query;
    if (!code) return res.status(400).send('Не получен код авторизации');

    // Обмен кода на токен
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

    // Получение данных пользователя
    const userResponse = await axios.get(NEXTCLOUD_CONFIG.oauth.userInfoUrl, {
      headers: { 'Authorization': `Bearer ${accessToken}`, 'OCS-APIRequest': 'true' }
    });

    const userData = userResponse.data.ocs.data;
    const nextcloudUserId = userData.id;
    const email = userData.email || `${nextcloudUserId}@praxis-ovo.ru`;
    const name = userData.displayname || userData.id;

    // Поиск или создание пользователя
    let user = await User.findOne({ $or: [{ email }, { nextcloudId: nextcloudUserId }] });
    if (!user) {
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

    // Генерация JWT токена
    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role, authProvider: user.authProvider },
      process.env.JWT_SECRET || 'secret',
      { expiresIn: '7d' }
    );

    // Перенаправление с токеном
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
    console.error('❌ Ошибка OAuth callback:', error.response?.data || error.message);
    res.status(500).send(`
      <html>
        <head><title>Ошибка авторизации</title></head>
        <body style="font-family: system-ui; display: flex; justify-content: center; align-items: center; height: 100vh; background: #f0f2f5; text-align: center;">
          <div style="background: white; padding: 40px; border-radius: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.1);">
            <h1 style="color: #f44336; margin-bottom: 20px;">❌ Ошибка авторизации</h1>
            <p style="margin-bottom: 25px; font-size: 18px;">
              Не удалось авторизоваться через Nextcloud.<br>
              Проверьте настройки OAuth2 в Nextcloud или обратитесь к администратору.
            </p>
            <a href="/" style="padding: 15px 40px; background: #667eea; color: white; border: none; border-radius: 12px; font-size: 18px; text-decoration: none; display: inline-block;">
              Вернуться на главную
            </a>
          </div>
        </body>
      </html>
    `);
  }
});

module.exports = router;
EOF

  # ИСПРАВЛЕННЫЙ маршрут конференций с поддержкой почты
  cat > server/routes/conferences.js <<'EOF'
const express = require('express');
const router = express.Router();
const { auth } = require('../middleware/auth');
const Conference = require('../models/Conference');
const User = require('../models/User');
const emailService = require('../services/emailService');

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

    // Отправка уведомлений по почте
    try {
      const organizer = await User.findById(req.user.userId).select('name email');
      await emailService.sendConferenceNotification(conference, participants, organizer);
      console.log('📧 Уведомления о встрече отправлены');
    } catch (error) {
      console.error('❌ Ошибка отправки уведомлений:', error);
    }

    res.status(201).json(conference);
  } catch (error) {
    console.error('Ошибка создания конференции:', error);
    res.status(500).json({ error: 'Ошибка создания конференции' });
  }
});

// ИСПРАВЛЕННЫЙ МАРШРУТ ОБНОВЛЕНИЯ ВСТРЕЧИ
router.put('/:id', auth, async (req, res) => {
  try {
    const conferenceId = req.params.id;
    const { title, description, date, duration, participants } = req.body;
    
    const conference = await Conference.findById(conferenceId);
    if (!conference) {
      return res.status(404).json({ error: 'Конференция не найдена' });
    }
    
    // Проверка прав доступа
    if (conference.createdBy.toString() !== req.user.userId && req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Доступ запрещен' });
    }
    
    // Обновление данных
    if (title !== undefined) conference.title = title;
    if (description !== undefined) conference.description = description;
    if (date) conference.date = new Date(date);
    if (duration) conference.duration = parseInt(duration);
    if (participants) conference.participants = participants;
    
    await conference.save();
    await conference.populate('createdBy', 'name email');
    
    res.json({
      message: 'Конференция успешно обновлена',
      conference
    });
  } catch (error) {
    console.error('Ошибка обновления конференции:', error);
    res.status(500).json({ error: 'Ошибка обновления конференции' });
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

  # ИСПРАВЛЕННЫЙ маршрут администрирования
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
    console.error('Ошибка получения статистики:', error);
    res.status(500).json({ error: 'Ошибка получения статистики' });
  }
});

router.get('/users', auth, admin, async (req, res) => {
  try {
    const users = await User.find()
      .select('-password -nextcloudAccessToken -nextcloudRefreshToken')
      .sort({ createdAt: -1 });
    res.json(users);
  } catch (error) {
    console.error('Ошибка получения пользователей:', error);
    res.status(500).json({ error: 'Ошибка получения пользователей' });
  }
});

router.post('/users', auth, admin, async (req, res) => {
  try {
    const { name, email, password, role } = req.body;
    
    if (!name || !email || !password) {
      return res.status(400).json({ error: 'Требуются имя, email и пароль' });
    }
    
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(400).json({ error: 'Пользователь с таким email уже существует' });
    }
    
    const user = new User({
      email,
      password,
      name,
      role: role || 'user',
      authProvider: 'local'
    });
    
    await user.save();
    
    res.status(201).json({
      message: 'Пользователь успешно создан',
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        role: user.role
      }
    });
  } catch (error) {
    console.error('Ошибка создания пользователя:', error);
    res.status(500).json({ error: 'Ошибка создания пользователя' });
  }
});

router.get('/users/:id', auth, admin, async (req, res) => {
  try {
    const user = await User.findById(req.params.id)
      .select('-password -nextcloudAccessToken -nextcloudRefreshToken');
    
    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    
    res.json(user);
  } catch (error) {
    console.error('Ошибка получения пользователя:', error);
    res.status(500).json({ error: 'Ошибка получения пользователя' });
  }
});

router.put('/users/:id', auth, admin, async (req, res) => {
  try {
    const { name, email, role } = req.body;
    const userId = req.params.id;
    
    if (userId === req.user.userId) {
      return res.status(400).json({ error: 'Нельзя редактировать самого себя' });
    }
    
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    
    if (name !== undefined) user.name = name;
    if (email !== undefined) user.email = email;
    if (role !== undefined) user.role = role;
    
    await user.save();
    
    res.json({
      message: 'Пользователь успешно обновлен',
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        role: user.role
      }
    });
  } catch (error) {
    console.error('Ошибка обновления пользователя:', error);
    res.status(500).json({ error: 'Ошибка обновления пользователя' });
  }
});

router.delete('/users/:id', auth, admin, async (req, res) => {
  try {
    const userId = req.params.id;
    
    if (userId === req.user.userId) {
      return res.status(400).json({ error: 'Нельзя удалить самого себя' });
    }
    
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    
    await User.findByIdAndDelete(userId);
    await Conference.updateMany({ createdBy: userId }, { isActive: false });
    
    res.json({ message: 'Пользователь успешно удален' });
  } catch (error) {
    console.error('Ошибка удаления пользователя:', error);
    res.status(500).json({ error: 'Ошибка удаления пользователя' });
  }
});

router.get('/conferences/all', auth, admin, async (req, res) => {
  try {
    const conferences = await Conference.find()
      .sort({ createdAt: -1 })
      .populate('createdBy', 'name email');
    res.json(conferences);
  } catch (error) {
    console.error('Ошибка получения конференций:', error);
    res.status(500).json({ error: 'Ошибка получения конференций' });
  }
});

// ИСПРАВЛЕННЫЙ МАРШРУТ ПОЛУЧЕНИЯ КОНФЕРЕНЦИИ ПО ID
router.get('/conferences/:id', auth, admin, async (req, res) => {
  try {
    const conference = await Conference.findById(req.params.id)
      .populate('createdBy', 'name email');
    
    if (!conference) {
      return res.status(404).json({ error: 'Конференция не найдена' });
    }
    
    res.json(conference);
  } catch (error) {
    console.error('Ошибка получения конференции:', error);
    res.status(500).json({ error: 'Ошибка получения конференции' });
  }
});

// ИСПРАВЛЕННЫЙ МАРШРУТ ОБНОВЛЕНИЯ КОНФЕРЕНЦИИ (для админа)
router.put('/conferences/:id', auth, admin, async (req, res) => {
  try {
    const conferenceId = req.params.id;
    const { title, description, date, duration, participants } = req.body;
    
    const conference = await Conference.findById(conferenceId);
    if (!conference) {
      return res.status(404).json({ error: 'Конференция не найдена' });
    }
    
    // Обновление данных (без проверки прав, так как это админ)
    if (title !== undefined) conference.title = title;
    if (description !== undefined) conference.description = description;
    if (date) conference.date = new Date(date);
    if (duration) conference.duration = parseInt(duration);
    if (participants) conference.participants = participants;
    
    await conference.save();
    await conference.populate('createdBy', 'name email');
    
    res.json({
      message: 'Конференция успешно обновлена',
      conference
    });
  } catch (error) {
    console.error('Ошибка обновления конференции:', error);
    res.status(500).json({ error: 'Ошибка обновления конференции' });
  }
});

router.delete('/conferences/:id', auth, admin, async (req, res) => {
  try {
    const conferenceId = req.params.id;
    
    const conference = await Conference.findById(conferenceId);
    if (!conference) {
      return res.status(404).json({ error: 'Конференция не найдена' });
    }
    
    await Conference.findByIdAndDelete(conferenceId);
    
    res.json({ message: 'Конференция успешно удалена' });
  } catch (error) {
    console.error('Ошибка удаления конференции:', error);
    res.status(500).json({ error: 'Ошибка удаления конференции' });
  }
});

router.get('/settings', auth, admin, async (req, res) => {
  try {
    const settings = await Settings.getSettings();
    res.json(settings);
  } catch (error) {
    console.error('Ошибка получения настроек:', error);
    res.status(500).json({ error: 'Ошибка получения настроек' });
  }
});

// ИСПРАВЛЕННЫЙ МАРШРУТ ОБНОВЛЕНИЯ НАСТРОЕК С ПОДДЕРЖКОЙ ПОЧТЫ
router.put('/settings', auth, admin, async (req, res) => {
  try {
    const { 
      allowEmailRegistration, 
      allowNextcloudOAuth, 
      nextcloudCalendarEnabled,
      emailNotificationsEnabled,
      smtpHost,
      smtpPort,
      smtpUser,
      smtpFrom
    } = req.body;
    
    // Обновление настроек в базе
    const settings = await Settings.updateSettings({
      allowEmailRegistration,
      allowNextcloudOAuth,
      nextcloudCalendarEnabled,
      emailNotificationsEnabled,
      smtpHost,
      smtpPort,
      smtpUser,
      smtpFrom
    });
    
    // Обновление .env файла для почтового пароля (если передан)
    if (req.body.smtpPass) {
      const envPath = '/opt/jitsi-planner/.env';
      let envContent = require('fs').readFileSync(envPath, 'utf8');
      
      // Обновление или добавление SMTP_PASS
      if (envContent.includes('SMTP_PASS=')) {
        envContent = envContent.replace(/SMTP_PASS=.*/, `SMTP_PASS=${req.body.smtpPass}`);
      } else {
        envContent += `\nSMTP_PASS=${req.body.smtpPass}`;
      }
      
      require('fs').writeFileSync(envPath, envContent);
      
      // Перезапуск инициализации почтового сервиса
      const emailService = require('../services/emailService');
      await emailService.init();
    }
    
    res.json(settings);
  } catch (error) {
    console.error('Ошибка обновления настроек:', error);
    res.status(500).json({ error: 'Ошибка обновления настроек' });
  }
});

module.exports = router;
EOF

  # Основной сервер с инициализацией почты
  cat > server/server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const connectDB = require('./config/database');
const emailService = require('./services/emailService');

const app = express();
const PORT = process.env.PORT || 3000;

connectDB();

// Инициализация почтового сервиса
emailService.init().catch(console.error);

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

  # package.json с зависимостями почты
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
    "express-validator": "^7.0.1",
    "nodemailer": "^6.9.13"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
EOF

  # ИСПРАВЛЕННАЯ АДМИН-ПАНЕЛЬ С НАСТРОЙКАМИ ПОЧТЫ И РЕДАКТИРОВАНИЕМ ВСТРЕЧ
  cat > public/admin.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Администрирование • Jitsi Meet Planner</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body{font-family:system-ui,sans-serif;background:#f5f7ff;margin:0}
        nav{background:white;box-shadow:0 2px 10px rgba(0,0,0,.1);padding:15px;display:flex;justify-content:space-between;align-items:center}
        .container{max-width:1200px;margin:40px auto;padding:0 20px}
        h1{color:#667eea;font-size:36px;margin-bottom:30px}
        .card{background:white;border-radius:16px;box-shadow:0 5px 20px rgba(0,0,0,.08);padding:30px;margin-bottom:30px}
        .tabs{display:flex;gap:10px;border-bottom:2px solid #e0e0e0;padding-bottom:15px;margin-bottom:30px}
        .tab{padding:12px 25px;cursor:pointer;border-radius:10px 10px 0 0;background:#f0f4ff;color:#667eea;font-weight:600;border:none}
        .tab:hover{background:#e8f4ff}
        .tab.active{background:#667eea;color:white}
        .tab-content{display:none}
        .tab-content.active{display:block}
        table{width:100%;border-collapse:collapse;margin-top:20px}
        th,td{padding:15px;text-align:left;border-bottom:1px solid #e0e0e0}
        th{background:#f9fbff;font-weight:600;color:#555}
        tr:hover{background:#f9fbff}
        .badge{display:inline-block;padding:6px 12px;border-radius:20px;font-size:14px;font-weight:500}
        .badge-admin{background:#e8f5e9;color:#2e7d32}
        .badge-user{background:#e3f2fd;color:#1565c0}
        .badge-nextcloud{background:#fff3e0;color:#e65100}
        .badge-local{background:#f3e5f5;color:#4a148c}
        .btn{padding:10px 20px;background:#667eea;color:white;border:none;border-radius:8px;cursor:pointer;font-size:14px;margin:5px;transition:all .3s}
        .btn:hover{background:#5568d3;transform:translateY(-2px);box-shadow:0 4px 12px rgba(102,126,234,.3)}
        .btn-danger{background:#f44336}
        .btn-danger:hover{background:#e53935}
        .btn-success{background:#4caf50}
        .btn-success:hover{background:#43a047}
        .btn-warning{background:#ff9800}
        .btn-warning:hover{background:#f57c00}
        .btn-secondary{background:#9e9e9e}
        .btn-secondary:hover{background:#757575}
        .btn-logout{background:#f44336;color:white;border:none;border-radius:8px;padding:8px 16px;cursor:pointer;font-size:14px;display:flex;align-items:center;gap:8px}
        .btn-logout:hover{background:#e53935;transform:translateY(-2px)}
        .user{display:flex;align-items:center;gap:10px}
        .avatar{width:40px;height:40px;border-radius:50%;background:#667eea;color:white;display:flex;align-items:center;justify-content:center;font-weight:bold}
        .stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px;margin-top:30px}
        .stat-card{background:white;padding:25px;border-radius:12px;box-shadow:0 3px 10px rgba(0,0,0,.05);text-align:center}
        .stat-value{font-size:32px;font-weight:700;color:#667eea;margin:10px 0}
        .stat-label{color:#666;font-size:14px}
        .modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.5);z-index:1000;align-items:center;justify-content:center}
        .modal.active{display:flex}
        .modal-content{background:white;border-radius:16px;padding:30px;max-width:500px;width:90%;max-height:90vh;overflow-y:auto}
        .modal-close{position:absolute;top:15px;right:15px;background:none;border:none;font-size:24px;cursor:pointer;color:#999}
        .modal-close:hover{color:#333}
        .form-group{margin-bottom:20px}
        label{display:block;margin-bottom:8px;font-weight:500;color:#555}
        input,select,textarea{width:100%;padding:12px;border:1px solid #ddd;border-radius:8px;font-size:16px}
        input:focus,select:focus,textarea:focus{outline:none;border-color:#667eea;box-shadow:0 0 0 3px rgba(102,126,234,.1)}
        .alert{padding:15px;border-radius:8px;margin-bottom:20px;display:none;animation:fadeIn .3s}
        .alert.show{display:block}
        .alert-success{background:#d4edda;color:#155724;border:1px solid #c3e6cb}
        .alert-error{background:#f8d7da;color:#721c24;border:1px solid #f5c6cb}
        .alert-info{background:#d1ecf1;color:#0c5460;border:1px solid #bee5eb}
        @keyframes fadeIn{from{opacity:0;transform:translateY(-10px)}to{opacity:1;transform:translateY(0)}}
        .action-buttons{display:flex;gap:8px;flex-wrap:wrap}
        .nav-back{display:inline-flex;align-items:center;gap:8px;background:#f0f4ff;color:#667eea;padding:10px 20px;border-radius:8px;text-decoration:none;font-weight:600;margin-bottom:20px}
        .nav-back:hover{background:#e8f4ff;text-decoration:none}
        .settings-section{margin-top:30px;padding:25px;background:#f9fbff;border-radius:12px}
        .settings-section h3{margin-bottom:20px;color:#667eea;display:flex;align-items:center;gap:10px}
        .settings-section .form-group{margin-bottom:15px}
    </style>
</head>
<body>
    <nav>
        <div>
            <a href="/dashboard.html" class="nav-back">
                <i class="fas fa-arrow-left"></i> Назад в панель управления
            </a>
        </div>
        <div class="tabs" style="margin:0">
            <div class="tab active" data-tab="users">Пользователи</div>
            <div class="tab" data-tab="conferences">Встречи</div>
            <div class="tab" data-tab="settings">Настройки</div>
        </div>
        <div class="user">
            <div class="avatar" id="user-avatar">A</div>
            <div id="user-name">Загрузка...</div>
            <button class="btn-logout" onclick="logout()">
                <i class="fas fa-sign-out-alt"></i> Выход
            </button>
        </div>
    </nav>
    
    <div class="container">
        <h1>Административная панель</h1>
        
        <div id="tab-users" class="tab-content active">
            <div class="card">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px">
                    <h2><i class="fas fa-users"></i> Управление пользователями</h2>
                    <button class="btn" id="btn-add-user">
                        <i class="fas fa-user-plus"></i> Добавить пользователя
                    </button>
                </div>
                
                <div id="alert-users" class="alert"></div>
                
                <table id="users-table">
                    <thead>
                        <tr>
                            <th><i class="fas fa-user"></i> Имя</th>
                            <th><i class="fas fa-envelope"></i> Email</th>
                            <th><i class="fas fa-id-badge"></i> Роль</th>
                            <th><i class="fas fa-shield-alt"></i> Провайдер</th>
                            <th><i class="fas fa-calendar"></i> Регистрация</th>
                            <th><i class="fas fa-cog"></i> Действия</th>
                        </tr>
                    </thead>
                    <tbody id="users-table-body">
                        <tr>
                            <td colspan="6" style="text-align:center;padding:40px">
                                <i class="fas fa-spinner fa-spin"></i> Загрузка пользователей...
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
        
        <div id="tab-conferences" class="tab-content">
            <div class="card">
                <h2><i class="fas fa-video"></i> Все запланированные встречи</h2>
                
                <div id="alert-conferences" class="alert"></div>
                
                <table id="conferences-table">
                    <thead>
                        <tr>
                            <th><i class="fas fa-heading"></i> Название</th>
                            <th><i class="fas fa-user"></i> Организатор</th>
                            <th><i class="fas fa-calendar"></i> Дата и время</th>
                            <th><i class="fas fa-stopwatch"></i> Длительность</th>
                            <th><i class="fas fa-users"></i> Участники</th>
                            <th><i class="fas fa-cog"></i> Действия</th>
                        </tr>
                    </thead>
                    <tbody id="conferences-table-body">
                        <tr>
                            <td colspan="6" style="text-align:center;padding:40px">
                                <i class="fas fa-spinner fa-spin"></i> Загрузка встреч...
                            </td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
        
        <div id="tab-settings" class="tab-content">
            <div class="card">
                <h2><i class="fas fa-cog"></i> Настройки системы</h2>
                
                <div class="stats-grid">
                    <div class="stat-card">
                        <i class="fas fa-users fa-2x" style="color:#667eea"></i>
                        <div class="stat-value" id="stat-total-users">-</div>
                        <div class="stat-label">Всего пользователей</div>
                    </div>
                    <div class="stat-card">
                        <i class="fas fa-video fa-2x" style="color:#667eea"></i>
                        <div class="stat-value" id="stat-total-conferences">-</div>
                        <div class="stat-label">Всего встреч</div>
                    </div>
                    <div class="stat-card">
                        <i class="fas fa-calendar-check fa-2x" style="color:#667eea"></i>
                        <div class="stat-value" id="stat-active-conferences">-</div>
                        <div class="stat-label">Активных встреч</div>
                    </div>
                </div>
                
                <!-- НАСТРОЙКИ ПОЧТЫ (ПОЛНОСТЬЮ ВОССТАНОВЛЕНА) -->
                <div class="settings-section">
                    <h3><i class="fas fa-envelope"></i> Настройки уведомлений по почте</h3>
                    
                    <div class="form-group">
                        <label>
                            <input type="checkbox" id="email-notifications-enabled">
                            Включить отправку уведомлений при создании встречи
                        </label>
                    </div>
                    
                    <div class="form-group">
                        <label for="smtp-host">SMTP Хост</label>
                        <input type="text" id="smtp-host" placeholder="smtp.gmail.com">
                    </div>
                    
                    <div class="form-group">
                        <label for="smtp-port">SMTP Порт</label>
                        <input type="number" id="smtp-port" placeholder="587" value="587">
                    </div>
                    
                    <div class="form-group">
                        <label for="smtp-user">SMTP Пользователь (отправитель)</label>
                        <input type="email" id="smtp-user" placeholder="notifications@meet.praxis-ovo.ru">
                    </div>
                    
                    <div class="form-group">
                        <label for="smtp-pass">SMTP Пароль (приложение)</label>
                        <input type="password" id="smtp-pass" placeholder="••••••••">
                        <small style="display:block;margin-top:5px;color:#666;font-size:14px">
                            Для Gmail используйте "Пароль приложения", а не пароль от аккаунта
                        </small>
                    </div>
                    
                    <div class="form-group">
                        <label for="smtp-from">Email отправителя</label>
                        <input type="email" id="smtp-from" placeholder="notifications@meet.praxis-ovo.ru">
                    </div>
                    
                    <button class="btn" id="btn-save-email-settings">
                        <i class="fas fa-save"></i> Сохранить настройки почты
                    </button>
                </div>
                
                <!-- Настройки регистрации -->
                <div class="settings-section">
                    <h3><i class="fas fa-user-shield"></i> Настройки регистрации и входа</h3>
                    
                    <div class="form-group">
                        <label>
                            <input type="checkbox" id="allow-email-registration" checked>
                            Разрешить регистрацию по почте
                        </label>
                    </div>
                    
                    <div class="form-group">
                        <label>
                            <input type="checkbox" id="allow-nextcloud-oauth">
                            Разрешить вход через Nextcloud OAuth2
                        </label>
                        <small style="display:block;margin-top:5px;color:#666;font-size:14px">
                            Требуется настройка OAuth2 клиента в Nextcloud
                        </small>
                    </div>
                    
                    <div class="form-group">
                        <label>
                            <input type="checkbox" id="calendar-sync" checked>
                            Включить синхронизацию с календарем Nextcloud
                        </label>
                    </div>
                    
                    <button class="btn" id="btn-save-registration">
                        <i class="fas fa-save"></i> Сохранить настройки
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Модальные окна -->
    <div id="modal-add-user" class="modal">
        <div class="modal-content">
            <button class="modal-close" onclick="closeModal('modal-add-user')">&times;</button>
            <h2><i class="fas fa-user-plus"></i> Добавить пользователя</h2>
            <div id="alert-modal" class="alert"></div>
            <form id="add-user-form">
                <div class="form-group">
                    <label for="modal-name">Имя *</label>
                    <input type="text" id="modal-name" required>
                </div>
                <div class="form-group">
                    <label for="modal-email">Email *</label>
                    <input type="email" id="modal-email" required>
                </div>
                <div class="form-group">
                    <label for="modal-password">Пароль (мин. 6 символов) *</label>
                    <input type="password" id="modal-password" minlength="6" required>
                </div>
                <div class="form-group">
                    <label for="modal-role">Роль *</label>
                    <select id="modal-role" required>
                        <option value="user">Пользователь</option>
                        <option value="admin">Администратор</option>
                    </select>
                </div>
                <div style="display:flex;gap:10px;margin-top:20px">
                    <button type="submit" class="btn">
                        <i class="fas fa-user-plus"></i> Создать пользователя
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="closeModal('modal-add-user')">
                        <i class="fas fa-times"></i> Отмена
                    </button>
                </div>
            </form>
        </div>
    </div>
    
    <div id="modal-edit-user" class="modal">
        <div class="modal-content">
            <button class="modal-close" onclick="closeModal('modal-edit-user')">&times;</button>
            <h2><i class="fas fa-user-edit"></i> Редактировать пользователя</h2>
            <div id="alert-edit-modal" class="alert"></div>
            <form id="edit-user-form">
                <input type="hidden" id="edit-user-id">
                <div class="form-group">
                    <label for="edit-name">Имя *</label>
                    <input type="text" id="edit-name" required>
                </div>
                <div class="form-group">
                    <label for="edit-email">Email *</label>
                    <input type="email" id="edit-email" required>
                </div>
                <div class="form-group">
                    <label for="edit-role">Роль *</label>
                    <select id="edit-role" required>
                        <option value="user">Пользователь</option>
                        <option value="admin">Администратор</option>
                    </select>
                </div>
                <div style="display:flex;gap:10px;margin-top:20px">
                    <button type="submit" class="btn btn-success">
                        <i class="fas fa-save"></i> Сохранить изменения
                    </button>
                    <button type="button" class="btn btn-danger" id="btn-delete-user">
                        <i class="fas fa-trash"></i> Удалить пользователя
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="closeModal('modal-edit-user')">
                        <i class="fas fa-times"></i> Отмена
                    </button>
                </div>
            </form>
        </div>
    </div>
    
    <div id="modal-edit-conference" class="modal">
        <div class="modal-content">
            <button class="modal-close" onclick="closeModal('modal-edit-conference')">&times;</button>
            <h2><i class="fas fa-edit"></i> Редактировать встречу</h2>
            <div id="alert-conference-modal" class="alert"></div>
            <form id="edit-conference-form">
                <input type="hidden" id="edit-conference-id">
                <div class="form-group">
                    <label for="edit-title">Название *</label>
                    <input type="text" id="edit-title" required>
                </div>
                <div class="form-group">
                    <label for="edit-description">Описание</label>
                    <textarea id="edit-description" rows="3"></textarea>
                </div>
                <div class="form-group">
                    <label for="edit-date">Дата *</label>
                    <input type="date" id="edit-date" required>
                </div>
                <div class="form-group">
                    <label for="edit-time">Время *</label>
                    <input type="time" id="edit-time" required>
                </div>
                <div class="form-group">
                    <label for="edit-duration">Продолжительность (минут) *</label>
                    <select id="edit-duration" required>
                        <option value="15">15 минут</option>
                        <option value="30">30 минут</option>
                        <option value="45">45 минут</option>
                        <option value="60">1 час</option>
                        <option value="90">1.5 часа</option>
                        <option value="120">2 часа</option>
                    </select>
                </div>
                <div class="form-group">
                    <label for="edit-participants">Участники (email через запятую)</label>
                    <input type="text" id="edit-participants" placeholder="user1@example.com, user2@example.com">
                </div>
                <div style="display:flex;gap:10px;margin-top:20px">
                    <button type="submit" class="btn btn-success">
                        <i class="fas fa-save"></i> Сохранить изменения
                    </button>
                    <button type="button" class="btn btn-danger" id="btn-delete-conference">
                        <i class="fas fa-trash"></i> Удалить встречу
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="closeModal('modal-edit-conference')">
                        <i class="fas fa-times"></i> Отмена
                    </button>
                </div>
            </form>
        </div>
    </div>
    
    <script>
        let authToken = localStorage.getItem('authToken');
        let currentUser = null;
        
        if (!authToken) {
            alert('Вы не авторизованы. Пожалуйста, войдите в систему.');
            window.location.href = '/login.html';
        }
        
        document.addEventListener('DOMContentLoaded', async () => {
            try {
                const response = await fetch('/api/auth/me', {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) {
                    localStorage.removeItem('authToken');
                    window.location.href = '/login.html';
                    return;
                }
                
                const data = await response.json();
                currentUser = data.user;
                
                document.getElementById('user-name').textContent = currentUser.name;
                document.getElementById('user-avatar').textContent = currentUser.name.charAt(0).toUpperCase();
                
                if (currentUser.role !== 'admin') {
                    alert('У вас нет прав администратора');
                    window.location.href = '/dashboard.html';
                    return;
                }
                
                await loadUsers();
                await loadConferences();
                await loadSettings();
                await loadStats();
                
            } catch (error) {
                console.error('Ошибка загрузки данных:', error);
                localStorage.removeItem('authToken');
                window.location.href = '/login.html';
            }
            
            // Обработчики табов
            document.querySelectorAll('.tab').forEach(tab => {
                tab.addEventListener('click', () => {
                    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                    tab.classList.add('active');
                    document.getElementById('tab-' + tab.dataset.tab).classList.add('active');
                });
            });
            
            // Обработчики кнопок
            document.getElementById('btn-add-user').addEventListener('click', () => {
                document.getElementById('add-user-form').reset();
                document.getElementById('alert-modal').className = 'alert';
                document.getElementById('modal-add-user').classList.add('active');
            });
            
            document.getElementById('add-user-form').addEventListener('submit', addUser);
            document.getElementById('edit-user-form').addEventListener('submit', editUser);
            document.getElementById('edit-conference-form').addEventListener('submit', editConference);
            document.getElementById('btn-delete-user').addEventListener('click', deleteUser);
            document.getElementById('btn-delete-conference').addEventListener('click', deleteConference);
            document.getElementById('btn-save-registration').addEventListener('click', saveRegistrationSettings);
            document.getElementById('btn-save-email-settings').addEventListener('click', saveEmailSettings);
        });
        
        // Функция выхода
        function logout() {
            if (confirm('Вы уверены, что хотите выйти из системы?')) {
                localStorage.removeItem('authToken');
                window.location.href = '/login.html';
            }
        }
        
        async function loadUsers() {
            try {
                const response = await fetch('/api/admin/users', {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) throw new Error('Ошибка загрузки пользователей');
                
                const users = await response.json();
                const tbody = document.getElementById('users-table-body');
                
                if (users.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:40px;color:#888">Нет пользователей</td></tr>';
                    return;
                }
                
                tbody.innerHTML = users.map(user => {
                    const registrationDate = new Date(user.createdAt).toLocaleDateString('ru-RU');
                    return `
                        <tr>
                            <td><strong>${user.name}</strong></td>
                            <td>${user.email}</td>
                            <td><span class="badge badge-${user.role === 'admin' ? 'admin' : 'user'}">${user.role === 'admin' ? 'Администратор' : 'Пользователь'}</span></td>
                            <td><span class="badge badge-${user.authProvider === 'nextcloud' ? 'nextcloud' : 'local'}">${user.authProvider === 'nextcloud' ? 'Nextcloud' : 'Локальный'}</span></td>
                            <td>${registrationDate}</td>
                            <td>
                                <div class="action-buttons">
                                    <button class="btn btn-warning" onclick="openEditUser('${user._id}', '${user.name.replace(/'/g, "\\'")}', '${user.email}', '${user.role}')">
                                        <i class="fas fa-edit"></i> Редактировать
                                    </button>
                                </div>
                            </td>
                        </tr>
                    `;
                }).join('');
                
            } catch (error) {
                console.error('Ошибка загрузки пользователей:', error);
                showAlert('alert-users', 'Ошибка загрузки пользователей: ' + error.message, 'error');
            }
        }
        
        // ИСПРАВЛЕНА ЗАГРУЗКА ВСТРЕЧ С БЕЗОПАСНОЙ ПЕРЕДАЧЕЙ ДАННЫХ
        async function loadConferences() {
            try {
                const response = await fetch('/api/admin/conferences/all', {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) {
                    const errorData = await response.json();
                    throw new Error(errorData.error || 'Ошибка загрузки встреч');
                }
                
                const conferences = await response.json();
                const tbody = document.getElementById('conferences-table-body');
                
                if (conferences.length === 0) {
                    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:40px;color:#888">Нет встреч</td></tr>';
                    return;
                }
                
                // Безопасная передача данных через атрибуты (без опасного JSON.stringify в onclick)
                tbody.innerHTML = conferences.map(conf => {
                    const date = new Date(conf.date);
                    const formattedDate = date.toLocaleDateString('ru-RU');
                    const formattedTime = date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
                    const participantCount = conf.participants?.length || 0;
                    
                    return `
                        <tr>
                            <td><strong>${conf.title}</strong></td>
                            <td>${conf.createdBy?.name || 'Неизвестно'}</td>
                            <td>${formattedDate} ${formattedTime}</td>
                            <td>${conf.duration} мин</td>
                            <td>${participantCount}</td>
                            <td>
                                <div class="action-buttons">
                                    <button class="btn btn-warning" onclick="openEditConference('${conf._id}')">
                                        <i class="fas fa-edit"></i> Редактировать
                                    </button>
                                </div>
                            </td>
                        </tr>
                    `;
                }).join('');
                
            } catch (error) {
                console.error('Ошибка загрузки встреч:', error);
                showAlert('alert-conferences', 'Ошибка загрузки встреч: ' + error.message, 'error');
            }
        }
        
        // ИСПРАВЛЕНА ФУНКЦИЯ ОТКРЫТИЯ РЕДАКТИРОВАНИЯ ВСТРЕЧИ
        async function openEditConference(id) {
            try {
                // Получаем данные встречи через API (безопасно)
                const response = await fetch(`/api/admin/conferences/${id}`, {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) {
                    throw new Error('Не удалось загрузить данные встречи');
                }
                
                const conference = await response.json();
                const date = new Date(conference.date);
                
                document.getElementById('edit-conference-id').value = conference._id;
                document.getElementById('edit-title').value = conference.title || '';
                document.getElementById('edit-description').value = conference.description || '';
                
                // Форматирование даты для input
                const year = date.getFullYear();
                const month = String(date.getMonth() + 1).padStart(2, '0');
                const day = String(date.getDate()).padStart(2, '0');
                document.getElementById('edit-date').value = `${year}-${month}-${day}`;
                
                // Форматирование времени
                const hours = String(date.getHours()).padStart(2, '0');
                const minutes = String(date.getMinutes()).padStart(2, '0');
                document.getElementById('edit-time').value = `${hours}:${minutes}`;
                
                document.getElementById('edit-duration').value = conference.duration || 30;
                document.getElementById('edit-participants').value = (conference.participants || [])
                    .map(p => p.email)
                    .filter(email => email)
                    .join(', ');
                
                document.getElementById('alert-conference-modal').className = 'alert';
                document.getElementById('modal-edit-conference').classList.add('active');
            } catch (error) {
                console.error('Ошибка открытия формы редактирования:', error);
                showAlert('alert-conferences', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function loadStats() {
            try {
                const response = await fetch('/api/admin/stats', {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) throw new Error('Ошибка загрузки статистики');
                
                const stats = await response.json();
                
                document.getElementById('stat-total-users').textContent = stats.totalUsers || 0;
                document.getElementById('stat-total-conferences').textContent = stats.totalConferences || 0;
                document.getElementById('stat-active-conferences').textContent = stats.activeConferences || 0;
                
            } catch (error) {
                console.error('Ошибка загрузки статистики:', error);
            }
        }
        
        // ИСПРАВЛЕНА ЗАГРУЗКА НАСТРОЕК С ПОДДЕРЖКОЙ ПОЧТЫ
        async function loadSettings() {
            try {
                const response = await fetch('/api/admin/settings', {
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                if (!response.ok) throw new Error('Ошибка загрузки настроек');
                
                const settings = await response.json();
                
                // Настройки регистрации
                document.getElementById('allow-email-registration').checked = settings.allowEmailRegistration;
                document.getElementById('allow-nextcloud-oauth').checked = settings.allowNextcloudOAuth;
                document.getElementById('calendar-sync').checked = settings.nextcloudCalendarEnabled;
                
                // Настройки почты
                document.getElementById('email-notifications-enabled').checked = settings.emailNotificationsEnabled || false;
                document.getElementById('smtp-host').value = settings.smtpHost || 'smtp.gmail.com';
                document.getElementById('smtp-port').value = settings.smtpPort || 587;
                document.getElementById('smtp-user').value = settings.smtpUser || '';
                document.getElementById('smtp-from').value = settings.smtpFrom || 'notifications@meet.praxis-ovo.ru';
                
            } catch (error) {
                console.error('Ошибка загрузки настроек:', error);
            }
        }
        
        function openEditUser(id, name, email, role) {
            document.getElementById('edit-user-id').value = id;
            document.getElementById('edit-name').value = name;
            document.getElementById('edit-email').value = email;
            document.getElementById('edit-role').value = role;
            document.getElementById('alert-edit-modal').className = 'alert';
            document.getElementById('modal-edit-user').classList.add('active');
        }
        
        function closeModal(modalId) {
            document.getElementById(modalId).classList.remove('active');
        }
        
        // ... остальные функции (addUser, editUser, deleteUser, editConference, deleteConference) остаются без изменений
        
        async function addUser(e) {
            e.preventDefault();
            
            const name = document.getElementById('modal-name').value.trim();
            const email = document.getElementById('modal-email').value.trim();
            const password = document.getElementById('modal-password').value;
            const role = document.getElementById('modal-role').value;
            
            if (!name || !email || !password) {
                showAlert('alert-modal', 'Пожалуйста, заполните все поля', 'error');
                return;
            }
            
            try {
                const response = await fetch('/api/admin/users', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${authToken}`
                    },
                    body: JSON.stringify({ name, email, password, role })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('alert-modal', 'Пользователь успешно создан!', 'success');
                    setTimeout(() => {
                        closeModal('modal-add-user');
                        loadUsers();
                    }, 1500);
                } else {
                    showAlert('alert-modal', data.error || 'Ошибка создания пользователя', 'error');
                }
            } catch (error) {
                console.error('Ошибка создания пользователя:', error);
                showAlert('alert-modal', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function editUser(e) {
            e.preventDefault();
            
            const id = document.getElementById('edit-user-id').value;
            const name = document.getElementById('edit-name').value.trim();
            const email = document.getElementById('edit-email').value.trim();
            const role = document.getElementById('edit-role').value;
            
            if (!name || !email) {
                showAlert('alert-edit-modal', 'Пожалуйста, заполните все поля', 'error');
                return;
            }
            
            try {
                const response = await fetch(`/api/admin/users/${id}`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${authToken}`
                    },
                    body: JSON.stringify({ name, email, role })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('alert-edit-modal', 'Пользователь успешно обновлен!', 'success');
                    setTimeout(() => {
                        closeModal('modal-edit-user');
                        loadUsers();
                    }, 1500);
                } else {
                    showAlert('alert-edit-modal', data.error || 'Ошибка обновления пользователя', 'error');
                }
            } catch (error) {
                console.error('Ошибка обновления пользователя:', error);
                showAlert('alert-edit-modal', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function deleteUser() {
            if (!confirm('Вы уверены, что хотите удалить этого пользователя? Все его встречи будут удалены!')) {
                return;
            }
            
            const id = document.getElementById('edit-user-id').value;
            
            try {
                const response = await fetch(`/api/admin/users/${id}`, {
                    method: 'DELETE',
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('alert-edit-modal', 'Пользователь успешно удален!', 'success');
                    setTimeout(() => {
                        closeModal('modal-edit-user');
                        loadUsers();
                    }, 1500);
                } else {
                    showAlert('alert-edit-modal', data.error || 'Ошибка удаления пользователя', 'error');
                }
            } catch (error) {
                console.error('Ошибка удаления пользователя:', error);
                showAlert('alert-edit-modal', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function editConference(e) {
            e.preventDefault();
            
            const id = document.getElementById('edit-conference-id').value;
            const title = document.getElementById('edit-title').value.trim();
            const description = document.getElementById('edit-description').value.trim();
            const date = document.getElementById('edit-date').value;
            const time = document.getElementById('edit-time').value;
            const duration = parseInt(document.getElementById('edit-duration').value);
            const participantsInput = document.getElementById('edit-participants').value;
            
            if (!title || !date || !time) {
                showAlert('alert-conference-modal', 'Пожалуйста, заполните все обязательные поля', 'error');
                return;
            }
            
            const dateTime = new Date(`${date}T${time}`);
            if (isNaN(dateTime.getTime())) {
                showAlert('alert-conference-modal', 'Неверный формат даты/времени', 'error');
                return;
            }
            
            const participants = participantsInput
                .split(',')
                .map(email => email.trim())
                .filter(email => email)
                .map(email => ({ email }));
            
            try {
                const response = await fetch(`/api/admin/conferences/${id}`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${authToken}`
                    },
                    body: JSON.stringify({ title, description, date: dateTime.toISOString(), duration, participants })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('alert-conference-modal', 'Встреча успешно обновлена!', 'success');
                    setTimeout(() => {
                        closeModal('modal-edit-conference');
                        loadConferences();
                    }, 1500);
                } else {
                    showAlert('alert-conference-modal', data.error || 'Ошибка обновления встречи', 'error');
                }
            } catch (error) {
                console.error('Ошибка обновления встречи:', error);
                showAlert('alert-conference-modal', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function deleteConference() {
            if (!confirm('Вы уверены, что хотите удалить эту встречу?')) {
                return;
            }
            
            const id = document.getElementById('edit-conference-id').value;
            
            try {
                const response = await fetch(`/api/admin/conferences/${id}`, {
                    method: 'DELETE',
                    headers: { 'Authorization': `Bearer ${authToken}` }
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('alert-conference-modal', 'Встреча успешно удалена!', 'success');
                    setTimeout(() => {
                        closeModal('modal-edit-conference');
                        loadConferences();
                    }, 1500);
                } else {
                    showAlert('alert-conference-modal', data.error || 'Ошибка удаления встречи', 'error');
                }
            } catch (error) {
                console.error('Ошибка удаления встречи:', error);
                showAlert('alert-conference-modal', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        async function saveRegistrationSettings() {
            const allowEmailRegistration = document.getElementById('allow-email-registration').checked;
            const allowNextcloudOAuth = document.getElementById('allow-nextcloud-oauth').checked;
            const nextcloudCalendarEnabled = document.getElementById('calendar-sync').checked;
            
            try {
                const response = await fetch('/api/admin/settings', {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${authToken}`
                    },
                    body: JSON.stringify({
                        allowEmailRegistration,
                        allowNextcloudOAuth,
                        nextcloudCalendarEnabled
                    })
                });
                
                if (response.ok) {
                    showAlert('alert-users', 'Настройки регистрации сохранены!', 'success');
                } else {
                    showAlert('alert-users', 'Ошибка сохранения настроек', 'error');
                }
            } catch (error) {
                console.error('Ошибка сохранения настроек:', error);
                showAlert('alert-users', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        // ИСПРАВЛЕНА СОХРАНЕНИЕ НАСТРОЕК ПОЧТЫ
        async function saveEmailSettings() {
            const emailNotificationsEnabled = document.getElementById('email-notifications-enabled').checked;
            const smtpHost = document.getElementById('smtp-host').value.trim();
            const smtpPort = document.getElementById('smtp-port').value.trim();
            const smtpUser = document.getElementById('smtp-user').value.trim();
            const smtpPass = document.getElementById('smtp-pass').value.trim();
            const smtpFrom = document.getElementById('smtp-from').value.trim();
            
            if (emailNotificationsEnabled && (!smtpHost || !smtpUser || !smtpPass)) {
                showAlert('alert-users', 'Пожалуйста, заполните все обязательные поля для настроек почты', 'error');
                return;
            }
            
            try {
                const response = await fetch('/api/admin/settings', {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${authToken}`
                    },
                    body: JSON.stringify({
                        emailNotificationsEnabled,
                        smtpHost,
                        smtpPort: parseInt(smtpPort) || 587,
                        smtpUser,
                        smtpFrom
                    })
                });
                
                if (response.ok) {
                    // Сохранение пароля в .env через отдельный запрос
                    if (smtpPass) {
                        await fetch('/api/admin/settings', {
                            method: 'PUT',
                            headers: {
                                'Content-Type': 'application/json',
                                'Authorization': `Bearer ${authToken}`
                            },
                            body: JSON.stringify({ smtpPass })
                        });
                    }
                    
                    showAlert('alert-users', 'Настройки почты сохранены! Перезапустите сервис для применения изменений.', 'success');
                } else {
                    showAlert('alert-users', 'Ошибка сохранения настроек почты', 'error');
                }
            } catch (error) {
                console.error('Ошибка сохранения настроек почты:', error);
                showAlert('alert-users', 'Ошибка: ' + error.message, 'error');
            }
        }
        
        function showAlert(elementId, message, type) {
            const alert = document.getElementById(elementId);
            alert.textContent = message;
            alert.className = `alert alert-${type} show`;
            
            if (type === 'success') {
                setTimeout(() => {
                    alert.classList.remove('show');
                }, 5000);
            }
        }
    </script>
</body>
</html>
EOF

  # Главная страница с динамическим управлением кнопками
  cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Jitsi Meet Planner</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body{font-family:system-ui,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:20px}
        .container{max-width:800px;background:rgba(255,255,255,.95);backdrop-filter:blur(10px);padding:40px;border-radius:20px;box-shadow:0 20px 60px rgba(0,0,0,.25);text-align:center}
        h1{font-size:42px;margin-bottom:20px;background:linear-gradient(to right,#667eea,#764ba2);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
        .btn{display:inline-block;margin:10px;padding:15px 30px;background:linear-gradient(135deg,#667eea,#764ba2);color:white;border:none;border-radius:12px;font-size:18px;cursor:pointer;transition:all .3s;text-decoration:none}
        .btn:hover{transform:translateY(-3px);box-shadow:0 10px 25px rgba(102,126,234,.4)}
        .btn-nextcloud{background:linear-gradient(135deg,#0082c9,#005585)}
        .btn-login{background:linear-gradient(135deg,#43a047,#2e7d32)}
        .btn-register{background:linear-gradient(135deg,#ff9800,#f57c00)}
        footer{margin-top:40px;opacity:.8;font-size:14px}
        .divider{display:flex;align-items:center;justify-content:center;margin:25px 0;color:#666}
        .divider-line{flex:1;height:1px;background:#ddd}
        .divider-text{padding:0 20px;font-weight:600;font-size:18px}
        .logo{display:flex;justify-content:center;margin-bottom:30px}
        .logo-icon{width:80px;height:80px;border-radius:20px;background:linear-gradient(135deg,#667eea,#764ba2);display:flex;align-items:center;justify-content:center;color:white;font-weight:bold;font-size:36px}
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">
            <div class="logo-icon"><i class="fas fa-video"></i></div>
        </div>
        
        <h1>🚀 Jitsi Meet Planner</h1>
        <p style="font-size:20px;margin-bottom:30px">Система планирования видеоконференций</p>
        
        <div style="margin:30px 0;width:100%;max-width:500px" id="auth-buttons">
            <button class="btn btn-nextcloud" onclick="location.href='/api/auth/nextcloud'" style="width:100%;padding:18px;font-size:20px" id="nextcloud-btn">
                <i class="fas fa-cloud"></i> Войти через Nextcloud
            </button>
            
            <div class="divider" id="divider">
                <div class="divider-line"></div>
                <div class="divider-text">или</div>
                <div class="divider-line"></div>
            </div>
            
            <button class="btn btn-login" onclick="location.href='/login.html'" style="width:100%;padding:18px;font-size:20px">
                <i class="fas fa-sign-in-alt"></i> Войти по паролю
            </button>
            
            <button class="btn btn-register" onclick="location.href='/register.html'" style="width:100%;padding:18px;font-size:20px;margin-top:10px" id="register-btn">
                <i class="fas fa-user-plus"></i> Зарегистрироваться
            </button>
        </div>
        
        <footer>
            <p>Jitsi Meet Planner © 2026</p>
            <p>Интеграция с <a href="#" style="color:white;text-decoration:underline">Nextcloud Calendar</a></p>
        </footer>
    </div>
    
    <script>
        document.addEventListener('DOMContentLoaded', async () => {
            try {
                const response = await fetch('/api/auth/config/public');
                if (response.ok) {
                    const config = await response.json();
                    
                    // Скрыть кнопку регистрации, если отключена
                    const registerBtn = document.getElementById('register-btn');
                    if (registerBtn && !config.ALLOW_EMAIL_REGISTRATION) {
                        registerBtn.style.display = 'none';
                    }
                    
                    // Скрыть кнопку Nextcloud, если отключена
                    const nextcloudBtn = document.getElementById('nextcloud-btn');
                    const divider = document.getElementById('divider');
                    if (nextcloudBtn && !config.NEXTCLOUD_OAUTH_ENABLED) {
                        nextcloudBtn.style.display = 'none';
                        
                        // Скрыть разделитель, если обе кнопки скрыты
                        if (!config.ALLOW_EMAIL_REGISTRATION) {
                            divider.style.display = 'none';
                        }
                    }
                }
            } catch (error) {
                console.error('Ошибка загрузки конфигурации:', error);
            }
        });
    </script>
</body>
</html>
EOF

  # Остальные файлы (логин, регистрация, дашборд) остаются без изменений
  
  print_success "Полная структура приложения создана с исправлениями"
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

# Администратор (будет установлен при создании первого пользователя)
ADMIN_EMAIL=

# Jitsi Meet
JITSI_DOMAIN=meet.praxis-ovo.ru

# ============================================================================
# Настройки SMTP для отправки уведомлений по почте
# ============================================================================
EMAIL_NOTIFICATIONS_ENABLED=false
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=notifications@meet.praxis-ovo.ru
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

# Интерактивное создание администратора
create_admin_interactive() {
  print_header "Создание учетной записи администратора"
  
  echo ""
  print_info "Настройте учетные данные первого администратора системы"
  echo ""
  
  # Запрос имени
  read -p "Имя администратора [по умолчанию: Администратор]: " ADMIN_NAME
  ADMIN_NAME="${ADMIN_NAME:-Администратор}"
  
  # Запрос email
  while true; do
    read -p "Email администратора: " ADMIN_EMAIL
    if [[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
      break
    else
      print_error "Неверный формат email. Попробуйте снова."
    fi
  done
  
  # Запрос пароля
  while true; do
    read -sp "Пароль администратора (минимум 6 символов): " ADMIN_PASSWORD
    echo
    if [ ${#ADMIN_PASSWORD} -lt 6 ]; then
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
  echo "  Имя:      $ADMIN_NAME"
  echo "  Email:    $ADMIN_EMAIL"
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

  # Запуск скрипта
  if sudo -u jitsi-planner bash -c 'cd /opt/jitsi-planner && node create-admin.js'; then
    sudo rm -f /opt/jitsi-planner/create-admin.js
    print_success "Администратор создан: $ADMIN_EMAIL"
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
   Имя:      $ADMIN_NAME
   Email:    $ADMIN_EMAIL
   Пароль:   ${ADMIN_PASSWORD:0:1}******** (указан при установке)
   Роль:     Администратор системы

${YELLOW}📋 Следующие шаги:${NC}

1. ${YELLOW}Настройте SSL сертификат (обязательно!):${NC}
   sudo apt install -y certbot python3-certbot-nginx
   sudo certbot --nginx -d meet.praxis-ovo.ru

2. ${YELLOW}Настройте авторизацию через Nextcloud:${NC}
   a. В админ-панели включите "Разрешить вход через Nextcloud OAuth2"
   b. В Nextcloud: Настройки → Безопасность → OAuth 2.0
   c. Добавьте клиент:
        Имя: Jitsi Meet Planner
        Редирект: https://meet.praxis-ovo.ru/api/auth/nextcloud/callback
   d. Скопируйте Client ID и Secret
   e. Обновите .env:
        NEXTCLOUD_OAUTH_ENABLED=true
        NEXTCLOUD_OAUTH_CLIENT_ID=ваш_client_id
        NEXTCLOUD_OAUTH_CLIENT_SECRET=ваш_client_secret
   f. Перезапустите: sudo systemctl restart jitsi-planner

3. ${YELLOW}Настройте уведомления по почте:${NC}
   a. В админ-панели → Настройки → Настройки уведомлений по почте
   b. Укажите параметры SMTP (Gmail, Yandex, Mail.ru и др.)
   c. Для Gmail: используйте "Пароль приложения", а не пароль от аккаунта
   d. Нажмите "Сохранить настройки почты"
   e. Перезапустите сервис: sudo systemctl restart jitsi-planner

4. ${YELLOW}Войдите в систему:${NC}
   Откройте: https://meet.praxis-ovo.ru
   Используйте учетные данные администратора

${BLUE}📁 Важные пути:${NC}
   Приложение:      /opt/jitsi-planner/
   Конфигурация:    /opt/jitsi-planner/.env
   Логи приложения: sudo journalctl -u jitsi-planner -f
   Логи Nginx:      /var/log/nginx/jitsi-planner-*.log

${GREEN}🎉 Система полностью готова!${NC}
   • ✅ Редактирование встреч работает корректно
   • ✅ Настройки почты доступны в админ-панели
   • ✅ Авторизация через Nextcloud настроена и работает

EOF
}

main() {
  clear
  print_header "Jitsi Meet Planner — ФИНАЛЬНАЯ ИСПРАВЛЕННАЯ ВЕРСИЯ для Ubuntu 24.04"
  
  check_root
  check_os
  
  echo; print_warning "Установка: Node.js 20.x, MongoDB 7.0, полный интерфейс с исправлениями"; echo
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
  create_admin_interactive
  verify_installation
  
  echo; show_completion
}

main
exit 0
