#!/usr/bin/env bash
#
# AutoSetup from ItMan75 (Hardened & Multi-Domain Cosmos-Only Fork v6.4.2)
# 3X-UI + Nginx Mask (Pure CosmosCloud Style - No PHP - Full Frontend restored)
# Official Nginx.org Repo Integration
#

set -uo pipefail

# ─────────────────────────── Цвета ───────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗] $*${NC}" >&2; exit 1; }

# Перехват непредвиденных ошибок Bash
trap 'die "Скрипт аварийно прерван на строке $LINENO"' ERR

echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}AutoSetup: Nginx Official Repo + Cosmos Mask v6.4.2${NC}"
echo -e "${CYAN}=========================================================${NC}"

# ─────────────────────── Предусловия ─────────────────────────
if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите скрипт от имени root (через sudo)."
fi

# Проверка обязательных системных утилит
for cmd in curl bash systemctl ss openssl awk lsb_release gpg; do
    command -v "$cmd" >/dev/null 2>&1 || die "Не найдена обязательная утилита: $cmd"
done

# Функция проверки доступности порта
check_port_free() {
    local port="$1"
    if ss -tlnH "sport = :$port" 2>/dev/null | grep -q .; then
        return 1
    fi
    return 0
}

# ═════════════════════════════════════════════════════════════
# 1. УСТАНОВКА / ОБНОВЛЕНИЕ ПАНЕЛИ 3X-UI
# ═════════════════════════════════════════════════════════════
echo
read -rp "Хотите установить/обновить панель 3X-UI прямо сейчас? [Y/n]: " INSTALL_3XUI
INSTALL_3XUI=${INSTALL_3XUI:-y}

if [[ "$INSTALL_3XUI" =~ ^[YyДд]$ ]]; then
    read -rp "Какую версию 3X-UI установить? (Enter = последняя стабильная): " UI_VERSION
    UI_VERSION="${UI_VERSION:-}"

    if [ -n "$UI_VERSION" ]; then
        export VERSION="$UI_VERSION"
        log "Подготовка к установке версии: $UI_VERSION"
    else
        unset VERSION 2>/dev/null || true
        log "Подготовка к установке последней стабильной версии"
    fi

    log "Запуск тихой установки 3X-UI..."
    set +e
    echo "e" | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
    INSTALL_RC=$?
    set -e

    if ! command -v x-ui >/dev/null 2>&1; then
        die "Установка 3X-UI завершилась ошибкой (rc=$INSTALL_RC). Скрипт остановлен."
    fi
    ok "Панель 3X-UI успешно настроена на сервере."

    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${YELLOW}ВАЖНАЯ ПАУЗА!${NC} Перейдите в консоль сервера, введите команду: ${CYAN}x-ui${NC}"
    echo -e "Обязательно настройте: ВНУТРЕННИЙ порт и СЕКРЕТНЫЙ путь (webBasePath) в режиме HTTP."
    read -rp "После настройки параметров панели нажмите [Enter] для продолжения..."
    echo -e "${CYAN}=========================================================${NC}"
else
    log "Установка 3X-UI пропущена. Переходим к конфигурации Nginx."
fi

# ═════════════════════════════════════════════════════════════
# 2. ИНТЕРАКТИВНЫЙ ВВОД ПАРАМЕТРОВ
# ═════════════════════════════════════════════════════════════
echo
echo -e "${YELLOW}Укажите все домены через ПРОБЕЛ.${NC}"
echo -e "Первый домен будет основным (Primary), остальные добавятся как альтернативные (SAN)."
read -rp "Введите домены: " -a DOMAINS

if [ ${#DOMAINS[@]} -eq 0 ]; then
    die "Список доменов не может быть пустым."
fi

PRIMARY_DOMAIN="${DOMAINS[0]}"

# Валидация формата главного домена
[[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] \
    || die "Некорректный формат главного домена: $PRIMARY_DOMAIN"

read -rp "Введите секретный путь панели (например, dashboard): " RAW_PATH
[ -n "$RAW_PATH" ] || die "Секретный путь панели не может быть пустым."

read -rp "Введите внутренний порт панели 3X-UI (например, 10443): " PANEL_PORT
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] && [ "$PANEL_PORT" -ge 1 ] && [ "$PANEL_PORT" -le 65535 ] \
    || die "Недопустимый числовой порт: $PANEL_PORT"

read -rp "Email для Let's Encrypt (Enter = без уведомлений): " LE_EMAIL

# Нормализация формата путей панели (строго /путь/)
PANEL_PATH=$(echo "/${RAW_PATH}/" | tr -s '/')

# ───────────────── Предполётные проверки ────────────────────
log "Проверка доступности локального порта 80..."
if ! check_port_free 80; then
    HOLDER=$(ss -tlnpH "sport = :80" 2>/dev/null | head -1 | awk '{print $6}')
    warn "Порт 80 занят сторонним процессом: $HOLDER"
    read -rp "Всё равно продолжить? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || die "Освободите порт 80 и запустите скрипт повторно."
fi

# ═════════════════════════════════════════════════════════════
# 3. ПОДКЛЮЧЕНИЕ ОФИЦИАЛЬНОГО REPO NGINX И УСТАНОВКА
# ═════════════════════════════════════════════════════════════
log "Подготовка окружения и добавление репозитория Nginx.org..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install curl gnupg2 ca-certificates lsb-release ubuntu-keyring certbot openssl -y -q

# Импорт ключа подписи
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes

# Определение версии дистрибутива
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_CODENAME=$(lsb_release -cs)

# Добавление репозитория
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/$OS_ID $OS_CODENAME nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

# Настройка приоритетов apt (pinning)
cat << EOF > /etc/apt/preferences.d/99nginx
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

log "Установка официальной сборки Nginx..."
apt-get update -q
apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx -y -q

log "Конфигурация директорий веб-корня..."
WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
chown -R www-data:www-data "$WEBROOT"

# Полная зачистка старых ссылок старых пакетов Ubuntu во избежание конфликтов
rm -f /etc/nginx/sites-enabled/default \
      /etc/nginx/sites-available/default \
      /etc/nginx/sites-enabled/*host74* \
      "/etc/nginx/sites-enabled/$PRIMARY_DOMAIN" \
      "/etc/nginx/sites-available/$PRIMARY_DOMAIN"

# Отключение стандартной конфигурации Nginx.org
if [ -f /etc/nginx/conf.d/default.conf ]; then
    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
fi

NGINX_SERVER_NAMES="${DOMAINS[*]}"

# Временный HTTP-сервер для прохождения проверки Certbot
log "Создание временного виртуального хоста Nginx для верификации..."
cat << EOF > "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
server {
    listen 80;
    server_name $NGINX_SERVER_NAMES;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        root $WEBROOT;
        try_files \$uri =404;
    }
    location / { return 404; }
}
EOF

nginx -t || die "Ошибка в структуре временной конфигурации Nginx."
systemctl restart nginx || systemctl start nginx

# ═════════════════════════════════════════════════════════════
# 4. ВЫПУСК МУЛЬТИДОМЕННОГО СЕРТИФИКАТА И ХАРДЕНИНГ
# ═════════════════════════════════════════════════════════════
log "Сборка аргументов для выпуска единого SSL-сертификата..."
CERTBOT_ARGS=(certonly --webroot -w "$WEBROOT" --agree-tos -n --expand)

for d in "${DOMAINS[@]}"; do
    CERTBOT_ARGS+=(-d "$d")
done

if [ -n "$LE_EMAIL" ]; then
    CERTBOT_ARGS+=(--email "$LE_EMAIL")
else
    CERTBOT_ARGS+=(--register-unsafely-without-email)
fi

log "Запрос сертификатов в Let's Encrypt для всех поддоменов..."
set +e
certbot "${CERTBOT_ARGS[@]}"
CERTBOT_RC=$?
set -e

if [ ! -d "/etc/letsencrypt/live/$PRIMARY_DOMAIN" ]; then
    die "Не удалось получить SSL-сертификат (rc=$CERTBOT_RC)."
fi

chmod 755 /etc/letsencrypt/archive
chmod 755 /etc/letsencrypt/live

DH_PARAM="/etc/nginx/dhparam.pem"
if [ ! -f "$DH_PARAM" ]; then
    log "Генерация параметров Диффи-Хеллмана (2048 бит)..."
    openssl dhparam -out "$DH_PARAM" 2048 2>/dev/null
fi

# ═════════════════════════════════════════════════════════════
# 5. ГЕНЕРАЦИЯ СТРАНИЦЫ АВТОРИЗАЦИИ
# ═════════════════════════════════════════════════════════════
log "Создание оригинальной frontend-страницы с часами и logo.webp..."
cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>My Cloud</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0">
    <style>
        body { margin:0; padding:20px; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background-color:#cbcae0; background-image:linear-gradient(135deg,#e2e1ec 0%,#bcbbcb 100%); display:flex; flex-direction:column; align-items:center; justify-content:center; min-height:100vh; color:#333; box-sizing:border-box; }
        .page-wrapper { width:100%; max-width:420px; display:flex; flex-direction:column; align-items:center; box-shadow:0 15px 35px rgba(0,0,0,0.15); border-radius:12px; overflow:hidden; }
        .banner-img { width:100%; height:auto; display:block; }
        .login-container { background:#fff; width:100%; text-align:center; padding:35px 30px; box-sizing:border-box; }
        .header-title { font-size:20px; color:#4a4557; margin-bottom:25px; font-weight:400; }
        .input-group { position:relative; margin-bottom:14px; }
        input { width:100%; padding:12px 15px; border:1px solid #ccc; border-radius:6px; box-sizing:border-box; font-size:15px; outline:none; transition:border-color .2s,box-shadow .2s; background:#fdfdfd; }
        input:focus { border-color:#735b8c; box-shadow:0 0 0 3px rgba(115,91,140,.15); background:#fff; }
        button { width:100%; padding:12px; background:#735b8c; color:#fff; border:none; border-radius:6px; font-size:16px; font-weight:600; cursor:pointer; margin-top:10px; transition:background .2s,opacity .2s; display:flex; justify-content:center; align-items:center; height:44px; }
        button:hover { background:#5d4874; }
        button:disabled { opacity:.7; cursor:not-allowed; }
        .message-box { background:#e74c3c; color:#fff; padding:11px; border-radius:6px; margin-bottom:20px; font-size:14px; text-align:left; display:none; animation:fadeIn .3s ease; }
        .spinner { display:inline-block; width:18px; height:18px; border:2px solid rgba(255,255,255,.3); border-top:2px solid #fff; border-radius:50%; animation:spin .8s linear infinite; }
        .footer-text { margin-top:25px; color:rgba(60,55,70,.6); font-size:13px; text-align:center; width:100%; }
        .footer-text a { color:#735b8c; text-decoration:none; font-weight:500; }
        .footer-text a:hover { text-decoration:underline; }
        @keyframes spin { 100% { transform:rotate(360deg); } }
        @keyframes fadeIn { from { opacity:0; transform:translateY(-5px); } to { opacity:1; transform:translateY(0); } }
    </style>
</head>
<body>
    <div class="page-wrapper">
        <img class="banner-img" src="logo.webp" alt="Cloud Header" onerror="this.style.display='none'">
        <div class="login-container">
            <div class="header-title">Вход в облако</div>
            <div id="errorBox" class="message-box"></div>
            <form id="loginForm" onsubmit="fakeLogin(event)">
                <div class="input-group"><input id="user" type="text" placeholder="Имя пользователя или email" autocomplete="username" required></div>
                <div class="input-group"><input id="pass" type="password" placeholder="Пароль" autocomplete="current-password" required></div>
                <button type="submit" id="loginBtn">Войти</button>
            </form>
        </div>
    </div>
    <div class="footer-text">
        <a href="#">Cosmos Cloud</a> – безопасный дом для ваших данных<br>
        <span id="server-time"></span>
    </div>
    <script>
        function setFakeCookie() { document.cookie = "cosmos_session=" + Math.random().toString(36).substring(2) + "; path=/; Secure; SameSite=Lax"; }
        function fakeLogin(e) {
            e.preventDefault();
            const btn = document.getElementById("loginBtn"), errBox = document.getElementById("errorBox");
            errBox.style.display = "none"; btn.disabled = true; btn.innerHTML = '<div class="spinner"></div>';
            setTimeout(() => {
                btn.disabled = false; btn.innerHTML = 'Войти';
                errBox.innerText = "Неверное имя пользователя или указанный пароль.";
                errBox.style.display = "block";
                document.getElementById("pass").value = ""; document.getElementById("pass").focus();
            }, 1500);
        }
        function updateServerTime() { const t = document.getElementById("server-time"); if (t) t.innerText = "Время сервера: " + new Date().toLocaleTimeString(); }
        setInterval(updateServerTime, 1000); updateServerTime(); setFakeCookie();
    </script>
</body>
</html>
EOF
chown www-data:www-data "$WEBROOT/index.html"

# ═════════════════════════════════════════════════════════════
# 6. СБОРКА И ПРИМЕНЕНИЕ КОНФИГУРАЦИИ NGINX
# ═════════════════════════════════════════════════════════════
log "Создание глобальной конфигурации WebSocket-карт..."
cat << 'EOF' > /etc/nginx/conf.d/00-maps.conf
# Глобальная карта апгрейда соединений WebSocket (защита от дублирования при мультидоменности)
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

log "Сборка финальной замаскированной конфигурации веб-сервера..."

cat << 'EOF' > "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
########################################
# 1. HTTP -> HTTPS REDIRECT (ALL DOMAINS)
########################################
server {
    listen 80;
    server_name __NGINX_SERVER_NAMES__;
    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root __WEBROOT__;
        try_files $uri =404;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}

########################################
# 2. MAIN HTTPS MASK: PRODUCTION (COSMOS ONLY)
########################################
server {
    listen 443 ssl;
    http2 on;
    
    server_name __NGINX_SERVER_NAMES__;

    ssl_certificate     /etc/letsencrypt/live/__PRIMARY_DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__PRIMARY_DOMAIN__/privkey.pem;
    ssl_dhparam         __DH_PARAM__;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root __WEBROOT__;
    index index.html;
    server_tokens off;

    # Имитационные заголовки чистого CosmosCloud (Строго без PHP)
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-Cosmoscloud-Version "0.22.18" always;
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    client_max_body_size 50m;

    ########################################
    # REVERSE PROXY НА ПАНЕЛЬ 3X-UI
    ########################################
    location ^~ __PANEL_PATH__ {
        proxy_pass http://127.0.0.1:__PANEL_PORT__;

        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_hide_header X-Cosmoscloud-Version;
        proxy_hide_header X-Frame-Options;

        proxy_intercept_errors off;
    }

    ########################################
    # API-ЗАГЛУШКИ COSMOSCLOUD
    ########################################
    location ~ ^/(api/v1/status|status)$ {
        default_type application/json;
        return 200 '{"installed":true,"maintenance":false,"version":"0.22.18","productname":"CosmosCloud"}\n';
    }

    location = /api/v1/auth/login {
        if ($request_method = POST) {
            add_header Set-Cookie "cosmos_session=$request_id; path=/; Secure; HttpOnly; SameSite=Lax" always;
            return 200 '{"status":"OK","message":"Authenticated"}\n';
        }
        return 405;
    }

    location = / {
        try_files /index.html =404;
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)$ {
        expires 7d;
        access_log off;
        add_header Cache-Control "public";
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header X-Cosmoscloud-Version "0.22.18" always;
        try_files $uri =404;
    }

    location = /robots.txt {
        add_header Content-Type text/plain;
        return 200 "User-agent: *\nDisallow: /\n";
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location / {
        return 404;
    }
}
EOF

# Безопасная подстановка переменных динамического окружения
sed -i "s|__NGINX_SERVER_NAMES__|$NGINX_SERVER_NAMES|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
sed -i "s|__WEBROOT__|$WEBROOT|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
sed -i "s|__PRIMARY_DOMAIN__|$PRIMARY_DOMAIN|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
sed -i "s|__DH_PARAM__|$DH_PARAM|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
sed -i "s|__PANEL_PATH__|$PANEL_PATH|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
sed -i "s|__PANEL_PORT__|$PANEL_PORT|g" "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"

log "Проверка конфигурации Nginx..."
nginx -t || die "Ошибка в итоговой конфигурации Nginx."

systemctl restart nginx
ok "Конфигурация с современным HTTP/2 успешно перезапущена!"

# ═════════════════════════════════════════════════════════════
# 7. АВТОПРОДЛЕНИЕ И КРОН-ХУКИ
# ═════════════════════════════════════════════════════════════
mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
systemctl reload nginx
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh

echo
echo -e "${GREEN}=========================================================${NC}"
echo -e "        ОБНОВЛЕННЫЙ СКРИПТ УСПЕШНО ОТРАБОТАЛ!${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo -e "Домены в маске:  ${CYAN}${DOMAINS[*]}${NC}"
echo -e "Nginx ветка:     ${GREEN}Официальный Repo Nginx.org (1.25.1+)${NC}"
echo -e "HTTP/2 статус:   ${GREEN}ВКЛЮЧЕН (директива 'http2 on;' активна)${NC}"
echo -e "Логотип:         ${GREEN}В коде восстановлена оригинальная ссылка на logo.webp${NC}"
echo

exit 0