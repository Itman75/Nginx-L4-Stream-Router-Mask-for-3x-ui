#
# Production AutoSetup (Hardened Hybrid Router & Mask v3.1.1)
# Nginx Stream L4 Hybrid Router for 3X-UI + xHTTP + Multi-Domain SSL Support
# Scenario: Classic REALITY Multi-Port + Isolated HTTPS Mask + Multi-Cert Let's Encrypt
# Supported external ports: 443 (TCP/UDP) and 8443 (TCP/UDP)
# Fully compatible with Ubuntu 20.04+ and Debian 11+
#

set -euo pipefail

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

trap 'die "Скрипт аварийно прерван на строке $LINENO"' ERR

echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}  Nginx L4 Stream Router & Mask v3.1.1 (MULTI-CERT SUPPORT)${NC}"
echo -e "${CYAN}=========================================================${NC}"

# ─────────────────────── Предусловия ─────────────────────────
if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите скрипт от имени root (через sudo)."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        die "Данный скрипт оптимизирован строго под семейства Ubuntu / Debian."
    fi
else
    die "Не удалось определить дистрибутив ОС."
fi

log "Проверка системных утилит..."
declare -A pkg_map=(
    [curl]="curl"
    [bash]="bash"
    [systemctl]="systemd"
    [openssl]="openssl"
    [awk]="gawk"
    [lsb_release]="lsb-release"
    [gpg]="gnupg"
    [dig]="dnsutils"
)

apt_updated=0
for cmd in "${!pkg_map[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "Не найдена утилита: $cmd. Устанавливаем пакет ${pkg_map[$cmd]}..."
        if [ "$apt_updated" -eq 0 ]; then
            apt-get update -q
            apt_updated=1
        fi
        apt-get install -y "${pkg_map[$cmd]}" -q
    fi
done

prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val
    read -rp "$prompt_text [$default_val]: " input_val
    declare -g "$var_name=${input_val:-$default_val}"
}

validate_path() {
    local val="$1"
    local name="$2"
    if [[ ! "$val" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        die "Критическая ошибка: Параметр $name ('$val') должен содержать только латинские буквы, цифры, дефис или подчеркивание."
    fi
}

# ═════════════════════════════════════════════════════════════
#  ИНТЕРАКТИВНЫЙ ВВОД ПАРАМЕТРОВ
# ═════════════════════════════════════════════════════════════
echo
echo -e "${YELLOW}Шаг 1: Настройка Доменов и SSL-сертификатов${NC}"
echo -e "${CYAN}Укажите ваш Главный домен (для Маски, Панели, Подписок и xHTTP).${NC}"
read -rp "Введите ваш основной домен (например, my-proxy-hub.com): " PRIMARY_DOMAIN
[[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] \
    || die "Некорректный формат главного домена: $PRIMARY_DOMAIN"

ALL_DOMAINS=("$PRIMARY_DOMAIN")

echo
echo -e "${CYAN}Вы можете добавить дополнительные домены для выпуска независимых SSL (например, для Hysteria 2, Trojan или других инбаундов).${NC}"
while true; do
    read -rp "Добавить еще один домен для выпуска SSL? (Введите домен или нажмите Enter для завершения): " ADD_DOM
    if [ -z "$ADD_DOM" ]; then
        break
    fi
    if [[ "$ADD_DOM" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        if [[ " ${ALL_DOMAINS[*]} " =~ " ${ADD_DOM} " ]]; then
            warn "Домен '$ADD_DOM' уже есть в списке."
        else
            ALL_DOMAINS+=("$ADD_DOM")
            ok "Добавлен домен: $ADD_DOM"
        fi
    else
        warn "Некорректный формат домена '$ADD_DOM'. Пропускаем."
    fi
done

log "Итоговый список доменов для выпуска SSL: ${ALL_DOMAINS[*]}"

echo
echo -e "${YELLOW}Шаг 2: Привязка технических портов 3X-UI и xHTTP${NC}"

REALITY_PORTS=()
prompt_default "Введите первый внутренний порт VLESS REALITY в 3X-UI" "45443" FIRST_REALITY_PORT
if [[ ! "$FIRST_REALITY_PORT" =~ ^[0-9]+$ ]] || [ "$FIRST_REALITY_PORT" -le 0 ] || [ "$FIRST_REALITY_PORT" -gt 65535 ]; then
    die "Некорректный порт REALITY: $FIRST_REALITY_PORT."
fi
REALITY_PORTS+=("$FIRST_REALITY_PORT")

while true; do
    read -rp "Добавить еще один порт для REALITY? (Введите порт или нажмите Enter для завершения): " ADD_PORT
    if [ -z "$ADD_PORT" ]; then
        break
    fi
    if [[ ! "$ADD_PORT" =~ ^[0-9]+$ ]] || [ "$ADD_PORT" -le 0 ] || [ "$ADD_PORT" -gt 65535 ]; then
        warn "Некорректный номер порта '$ADD_PORT'. Пропускаем."
    else
        REALITY_PORTS+=("$ADD_PORT")
        ok "Добавлен порт REALITY: $ADD_PORT"
    fi
done

log "Итоговый список портов REALITY: ${REALITY_PORTS[*]}"

echo
prompt_default "Внутренний порт вашей веб-панели 3X-UI" "10443" PANEL_PORT
prompt_default "Секретный пул-путь к веб-панели (без слэшей)" "3x-dashboard" RAW_PATH
validate_path "$RAW_PATH" "RAW_PATH"
PANEL_PATH="/${RAW_PATH}/"

prompt_default "Выделенный внутренний порт подписок 3X-UI" "55443" SUB_PORT
prompt_default "Секретный путь для подписок (без слэшей)" "postkey" RAW_SUB_PATH
validate_path "$RAW_SUB_PATH" "RAW_SUB_PATH"
SUB_PATH="/${RAW_SUB_PATH}/"

prompt_default "Внутренний порт для инбаунда VLESS xHTTP" "50443" XHTTP_PORT
prompt_default "Секретный путь для xHTTP (без слэшей)" "xhttp-stream" RAW_XHTTP_PATH
validate_path "$RAW_XHTTP_PATH" "RAW_XHTTP_PATH"
XHTTP_PATH="/${RAW_XHTTP_PATH}"

echo
echo -e "${YELLOW}Шаг 3: Выбор архитектурного режима xHTTP (xHTTP Proxy Mode)${NC}"
echo -e " 1) ${GREEN}stream-one (Высокоскоростной, HTTP/2 h2c gRPC-Tunnel)${NC} - Минимальный оверхед и задержка при прямом подключении"
echo -e " 2) ${GREEN}stream-up / packet-up (Универсальный, HTTP/1.1 Chunked)${NC} - Идеально для CDN (Cloudflare), обхода блокировок"
prompt_default "Выберите режим xHTTP (1 или 2)" "1" XHTTP_MODE_CHOICE

if [[ ! "$PANEL_PORT" =~ ^[0-9]+$ ]] || [ "$PANEL_PORT" -le 0 ] || [ "$PANEL_PORT" -gt 65535 ]; then
    die "Некорректный порт панели: $PANEL_PORT."
fi
if [[ ! "$SUB_PORT" =~ ^[0-9]+$ ]] || [ "$SUB_PORT" -le 0 ] || [ "$SUB_PORT" -gt 65535 ]; then
    die "Некорректный порт подписок: $SUB_PORT."
fi
if [[ ! "$XHTTP_PORT" =~ ^[0-9]+$ ]] || [ "$XHTTP_PORT" -le 0 ] || [ "$XHTTP_PORT" -gt 65535 ]; then
    die "Некорректный порт xHTTP: $XHTTP_PORT."
fi

if [ "$PANEL_PORT" -eq "$SUB_PORT" ] || [ "$PANEL_PORT" -eq "$XHTTP_PORT" ] || [ "$SUB_PORT" -eq "$XHTTP_PORT" ]; then
    die "Конфликт: Порты панели, подписок и xHTTP должны различаться!"
fi

echo
echo -e "${YELLOW}Шаг 4: Выбор визуального камуфляжа (Decoy Front)${NC}"
echo -e " 1) Точная копия CosmosCloud (Страница входа, имитация API-запросов)"
echo -e " 2) Стандартная заглушка Nginx (Классический 'Welcome to nginx!')"
prompt_default "Выберите вариант (1 или 2)" "1" DECOY_TEMPLATE

echo
echo -e "${YELLOW}Шаг 5: Служебные параметры Certbot${NC}"
prompt_default "Email для уведомлений Let's Encrypt (Оставьте пустым для отмены)" "" LE_EMAIL

# Проверка DNS для ВСЕХ доменов
log "Сканирование DNS-записей для всех указанных доменов..."
WAN_IP=$(curl -s4 --connect-timeout 5 icanhazip.com || curl -s4 --connect-timeout 5 ifconfig.me || echo "")
if [ -n "$WAN_IP" ]; then
    for dom in "${ALL_DOMAINS[@]}"; do
        resolved_ip=$(dig +short "$dom" @8.8.8.8 | tail -n1 || echo "")
        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(getent ahosts "$dom" | awk '{print $1}' | head -n1 || echo "")
        fi
        
        if [ -z "$resolved_ip" ]; then
            warn "Домен $dom не указывает ни на один IP. Проверьте A-запись."
            read -rp "Продолжить несмотря на проблему с DNS для $dom? [y/N]: " dns_ans
            [[ "${dns_ans,,}" == "y" ]] || die "Установка прервана пользователем."
        elif [ "$resolved_ip" != "$WAN_IP" ]; then
            warn "Несовпадение: домен $dom ведет на $resolved_ip, а сервер имеет IP $WAN_IP."
            read -rp "Продолжить несмотря на несовпадение? [y/N]: " dns_ans
            [[ "${dns_ans,,}" == "y" ]] || die "Установка прервана пользователем."
        else
            ok "DNS-запись подтверждена: $dom -> $WAN_IP"
        fi
    done
fi

# ═════════════════════════════════════════════════════════════
#  ПОДКЛЮЧЕНИЕ REPO NGINX И УСТАНОВКА СЛУЖБ
# ═════════════════════════════════════════════════════════════
log "Интеграция официального репозитория Nginx.org..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install gnupg ca-certificates lsb-release openssl snapd -y -q

mkdir -p /usr/share/keyrings
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes

OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_CODENAME=$(lsb_release -cs)

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/$OS_ID $OS_CODENAME nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

log "Установка Nginx..."
apt-get update -q
apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx -y -q

NGINX_USER="nginx"
if ! id -u nginx >/dev/null 2>&1; then
    NGINX_USER="www-data"
fi

log "Развертывание веб-структуры..."
WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"

rm -f /etc/nginx/sites-enabled/default \
      /etc/nginx/sites-available/default \
      "/etc/nginx/sites-enabled/$PRIMARY_DOMAIN" \
      "/etc/nginx/sites-available/$PRIMARY_DOMAIN"

if [ -f /etc/nginx/conf.d/default.conf ]; then
    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
fi

mkdir -p /etc/nginx/stream.d
rm -f "/etc/nginx/stream.d/$PRIMARY_DOMAIN.conf"

NGINX_80_SERVER_NAMES="${ALL_DOMAINS[*]}"

log "Конфигурация HTTP-порта 80 для ACME-проверок всех доменов..."
cat << EOF > "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
server {
    listen 80;
    server_name $NGINX_80_SERVER_NAMES;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        root $WEBROOT;
        try_files \$uri =404;
    }
    location / { return 301 https://\$host\$request_uri; }
}
EOF

nginx -t || die "Ошибка валидации базовых конфигов Nginx."
systemctl restart nginx || systemctl start nginx

# ═════════════════════════════════════════════════════════════
#  УСТАНОВКА CERTBOT ЧЕРЕЗ SNAP
# ═════════════════════════════════════════════════════════════
log "Инициализация подсистемы Snapd..."
apt-get purge -y certbot || true
systemctl start snapd.socket || true
systemctl enable snapd.socket || true

for i in {1..15}; do
    if snap version >/dev/null 2>&1; then
        log "Демон snapd успешно активирован."
        break
    fi
    sleep 2
done

log "Установка Certbot..."
snap install core || true
snap refresh core || true
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# ═════════════════════════════════════════════════════════════
#  НАСТРОЙКА КЛИЕНТА CERTBOT И ВЫПУСК СЕРТИФИКАТОВ
# ═════════════════════════════════════════════════════════════
mkdir -p /etc/letsencrypt
if [ -n "$LE_EMAIL" ]; then
    cat << EOF > /etc/letsencrypt/cli.ini
email = $LE_EMAIL
agree-tos = true
non-interactive = true
EOF
else
    cat << EOF > /etc/letsencrypt/cli.ini
register-unsafely-without-email = true
agree-tos = true
non-interactive = true
EOF
fi

# Выпуск независимого сертификата для КАЖДОГО домена в списке
for dom in "${ALL_DOMAINS[@]}"; do
    log "Генерация SSL-сертификата для домена: $dom..."
    if certbot certonly --webroot -w "$WEBROOT" --expand -d "$dom"; then
        ok "Сертификат для $dom успешно выпущен!"
    else
        warn "Не удалось выпустить сертификат для $dom. Проверьте A-запись."
        if [ "$dom" = "$PRIMARY_DOMAIN" ]; then
            die "Критическая ошибка: Выпуск сертификата для Главного домена $PRIMARY_DOMAIN провален."
        fi
    fi
done

# Корректировка прав доступа ко всем сертификатам (чтобы Xray и Hysteria2 могли их читать)
chmod 755 /etc/letsencrypt/archive 2>/dev/null || true
chmod 755 /etc/letsencrypt/live 2>/dev/null || true

for dom in "${ALL_DOMAINS[@]}"; do
    if [ -d "/etc/letsencrypt/live/$dom" ]; then
        chmod 755 /etc/letsencrypt/archive/"$dom" 2>/dev/null || true
        chmod 755 /etc/letsencrypt/live/"$dom" 2>/dev/null || true
        chmod 644 /etc/letsencrypt/archive/"$dom"/* 2>/dev/null || true
    fi
done

# ═════════════════════════════════════════════════════════════
#  ГЕНЕРАЦИЯ СТРАНИЦЫ МАСКИРОВКИ
# ═════════════════════════════════════════════════════════════
log "Развертывание маскировочного фронтенда..."
if [ "$DECOY_TEMPLATE" = "1" ]; then
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
            <form id="loginForm" onsubmit="handleLogin(event)">
                <div class="input-group"><input id="user" type="text" placeholder="Имя пользователя или email" autocomplete="username" required></div>
                <div class="input-group"><input id="pass" type="password" placeholder="Пароль" autocomplete="current-password" required></div>
                <button type="submit" id="loginBtn">Войти</button>
            </form>
        </div>
    </div>
    <div class="footer-text">
        <a href="#">Cosmos Cloud</a> – безопасный дом для ваших данных
    </div>
    <script>
        function setFakeCookie() { document.cookie = "cosmos_session=" + Math.random().toString(36).substring(2) + "; path=/; Secure; SameSite=Lax"; }
        async function handleLogin(e) {
            e.preventDefault();
            const btn = document.getElementById("loginBtn"), errBox = document.getElementById("errorBox");
            errBox.style.display = "none"; btn.disabled = true; btn.innerHTML = '<div class="spinner"></div>';
            try {
                const response = await fetch("/api/v1/auth/login", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        user: document.getElementById("user").value,
                        pass: document.getElementById("pass").value
                    })
                });
                const data = await response.json();
                errBox.innerText = data.error || "Wrong nickname or password.";
                errBox.style.display = "block";
            } catch (err) {
                errBox.innerText = "Ошибка сетевого соединения с облаком.";
                errBox.style.display = "block";
            } finally {
                btn.disabled = false; btn.innerHTML = 'Войти';
            }
        }
        setFakeCookie();
    </script>
</body>
</html>
EOF

    log "Загрузка оригинальных графических ассетов Cosmos Cloud..."
    if curl -fsSL --connect-timeout 10 "https://raw.githubusercontent.com/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui/main/logo.webp" -o "$WEBROOT/logo.webp" 2>/dev/null; then
        ok "Логотип успешно загружен из основного репозитория GitHub."
    else
        warn "Прямое подключение к GitHub не удалось. Переключаемся на резервное зеркало..."
        if curl -fsSL --connect-timeout 10 "https://cdn.jsdelivr.net/gh/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui@main/logo.webp" -o "$WEBROOT/logo.webp" 2>/dev/null; then
            ok "Логотип успешно загружен из резервного зеркала CDN (jsDelivr)."
        else
            warn "Не удалось загрузить логотип. Веб-маска будет работать в режиме текстовой заглушки."
        fi
    fi

    # Валидация формата WebP по сигнатуре (магическим байтам)
    if [ -f "$WEBROOT/logo.webp" ]; then
        magic_riff=$(head -c 4 "$WEBROOT/logo.webp" | tr -d '\0')
        magic_webp=$(dd if="$WEBROOT/logo.webp" bs=1 skip=8 count=4 status=none | tr -d '\0')
        if [[ "$magic_riff" != "RIFF" || "$magic_webp" != "WEBP" ]]; then
            warn "Файл logo.webp имеет неверный формат или поврежден. Удаление во избежание проблем..."
            rm -f "$WEBROOT/logo.webp"
        else
            ok "Файл logo.webp успешно верифицирован по сигнатуре формата."
        fi
    fi
else
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title><style>body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }</style></head>
<body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working.</p></body>
</html>
EOF
fi

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"
chmod 644 "$WEBROOT/index.html"

# ═════════════════════════════════════════════════════════════
#  НАСТРОЙКА NGINX CONFIGS (STREAM + HTTP)
# ═════════════════════════════════════════════════════════════
log "Обновление глобальной конфигурации веб-сервера..."
[ -f /etc/nginx/nginx.conf ] && cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

cat << EOF > /etc/nginx/nginx.conf
user $NGINX_USER;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 10240;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" \$status \$body_bytes_sent';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF

cat << 'EOF' > /etc/nginx/conf.d/00-maps.conf
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

cat << 'EOF' > /etc/nginx/conf.d/00-ratelimit.conf
limit_req_zone $binary_remote_addr zone=panel_login:10m rate=15r/m;
limit_req_zone $binary_remote_addr zone=panel_interface:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=sub_limit:10m rate=30r/s;
EOF

log "Генерация upstream списка для REALITY..."
REALITY_UPSTREAM_SERVERS=""
for port in "${REALITY_PORTS[@]}"; do
    REALITY_UPSTREAM_SERVERS+="    server 127.0.0.1:${port};"$'\n'
done

STREAM_DOMAINS_MAP=""
for dom in "${ALL_DOMAINS[@]}"; do
    STREAM_DOMAINS_MAP+="    ${dom}     nginx_http_backend;"$'\n'
done

log "Сборка L4 STREAM HYBRID маршрутизатора..."
cat << EOF > "/etc/nginx/stream.d/$PRIMARY_DOMAIN.conf"
map \$ssl_preread_server_name \$backend_gate {
    ""                 nginx_http_backend; # Без SNI -> на маску
${STREAM_DOMAINS_MAP}    default             xray_reality_backend; # Любые внешние SNI (Microsoft/Apple) -> в Xray REALITY
}

upstream nginx_http_backend {
    server 127.0.0.1:9443;
}

upstream xray_reality_backend {
${REALITY_UPSTREAM_SERVERS}}

server {
    listen 443;
    listen 8443; 
    ssl_preread on;
    proxy_protocol on; # Передаем реальный IP клиента в Xray и HTTP
    proxy_pass \$backend_gate;
    proxy_connect_timeout 5s;
    proxy_timeout 1h;
}
EOF

COSMOS_HEADER=""
COSMOS_MOCK_API=""
if [ "$DECOY_TEMPLATE" = "1" ]; then
  COSMOS_HEADER='add_header X-Cosmoscloud-Version "0.22.18" always;'
  COSMOS_MOCK_API='
    location ~ ^/(api/v1/status|status)$ {
        default_type application/json;
        return 200 '\''{"installed":true,"maintenance":false,"version":"0.22.18","productname":"CosmosCloud"}'\'';
    }
    location = /api/v1/auth/login {
        if ($request_method = POST) {
            add_header Content-Type "application/json" always;
            return 401 '\''{"error":"Wrong nickname or password. Try again or try resetting your password","code":401}'\'';
        }
        return 405;
    }'
fi

# Подготовка конфигурации xHTTP в зависимости от выбранного режима
if [ "$XHTTP_MODE_CHOICE" = "2" ]; then
    log "Конфигурация xHTTP: Режим stream-up / packet-up (HTTP/1.1 Chunked Proxy)..."
    XHTTP_LOCATION_BLOCK="
    # Шлюз VLESS xHTTP (Mode: stream-up / packet-up / auto)
    location ^~ $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 1h;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_pass http://127.0.0.1:$XHTTP_PORT;
    }"
    XHTTP_UI_MODE_TEXT="stream-up (или packet-up / auto)"
else
    log "Конфигурация xHTTP: Режим stream-one (gRPC h2c Tunneling)..."
    XHTTP_LOCATION_BLOCK="
    # Шлюз VLESS xHTTP (Mode: stream-one / gRPC h2c)
    location ^~ $XHTTP_PATH {
        client_max_body_size 0;
        client_body_timeout 1h;
        grpc_read_timeout 1h;
        grpc_send_timeout 1h;
        grpc_buffer_size 32k;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:$XHTTP_PORT;
    }"
    XHTTP_UI_MODE_TEXT="stream-one"
fi

EXTRA_HTTPS_SERVERS=""
for ((i=1; i<${#ALL_DOMAINS[@]}; i++)); do
    ext_dom="${ALL_DOMAINS[$i]}"
    if [ -d "/etc/letsencrypt/live/$ext_dom" ]; then
        EXTRA_HTTPS_SERVERS+="
server {
    listen 127.0.0.1:9443 ssl proxy_protocol;
    http2 on;
    server_name $ext_dom;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    ssl_certificate     /etc/letsencrypt/live/$ext_dom/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$ext_dom/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    root $WEBROOT;
    index index.html;
    server_tokens off;

    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    $COSMOS_HEADER
    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;

    $XHTTP_LOCATION_BLOCK

    location ^~ $PANEL_PATH {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location ^~ $SUB_PATH {
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    $COSMOS_MOCK_API

    location = / { try_files /index.html =404; }
    location / { return 404; }
}
"
    fi
done

log "Сборка основного HTTP/HTTPS ядра Nginx..."
cat << EOF > "/etc/nginx/conf.d/$PRIMARY_DOMAIN.conf"
server {
    listen 80;
    server_name $NGINX_80_SERVER_NAMES;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ {
        root $WEBROOT;
        try_files \$uri =404;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 127.0.0.1:9443 ssl proxy_protocol;
    http2 on;
    server_name $PRIMARY_DOMAIN;

    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    ssl_certificate     /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    root $WEBROOT;
    index index.html;
    server_tokens off;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    $COSMOS_HEADER
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;

    $XHTTP_LOCATION_BLOCK

    # Вход в Панель 3X-UI
    location ^~ $PANEL_PATH {
        limit_req zone=panel_interface burst=40 delay=20;
        limit_req_status 429;

        location ~* ^${PANEL_PATH}login\$ {
            limit_req zone=panel_login burst=5 nodelay;
            limit_req_status 429;
            proxy_pass http://127.0.0.1:$PANEL_PORT;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host \$http_host;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_hide_header X-Cosmoscloud-Version;
            proxy_hide_header X-Frame-Options;
        }

        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_hide_header X-Cosmoscloud-Version;
        proxy_hide_header X-Frame-Options;
        proxy_intercept_errors off;
    }

    # Подписки 3X-UI
    location ^~ $SUB_PATH {
        limit_req zone=sub_limit burst=60 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_hide_header X-Cosmoscloud-Version;
        proxy_hide_header X-Frame-Options;
    }

    $COSMOS_MOCK_API

    location = / {
        default_type text/html;
        root $WEBROOT;
        try_files /index.html =404; 
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)$ {
        expires 7d;
        access_log off;
        try_files \$uri =404;
    }

    location / { return 404; }
}

$EXTRA_HTTPS_SERVERS
EOF

log "Тестирование и перезапуск веб-сервера..."
nginx -t || die "Критическая ошибка синтаксиса собранной конфигурации Nginx."

mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
systemctl reload nginx
chmod 755 /etc/letsencrypt/archive/* 2>/dev/null || true
chmod 755 /etc/letsencrypt/live/* 2>/dev/null || true
chmod 644 /etc/letsencrypt/archive/*/* 2>/dev/null || true
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh

systemctl unmask nginx || true
systemctl enable nginx || true
systemctl restart nginx

# Подготовка списка команд UFW
UFW_REALITY_DENY=""
for port in "${REALITY_PORTS[@]}"; do
    UFW_REALITY_DENY="${UFW_REALITY_DENY} && ufw deny ${port}/tcp"
done

# Динамическое формирование блока вывода всех сертификатов
SSL_DOMAINS_OUTPUT=""
for dom in "${ALL_DOMAINS[@]}"; do
    if [ -f "/etc/letsencrypt/live/$dom/fullchain.pem" ]; then
        SSL_DOMAINS_OUTPUT+="  • Домен: ${CYAN}${dom}${NC}\n"
        SSL_DOMAINS_OUTPUT+="    Cert: ${GREEN}/etc/letsencrypt/live/${dom}/fullchain.pem${NC}\n"
        SSL_DOMAINS_OUTPUT+="    Key:  ${GREEN}/etc/letsencrypt/live/${dom}/privkey.pem${NC}\n\n"
    fi
done

# ═════════════════════════════════════════════════════════════
#  ФИНАЛЬНЫЙ ВЫВОД И ИНСТРУКЦИЯ
# ═════════════════════════════════════════════════════════════
echo
echo -e "${GREEN}=========================================================${NC}"
echo -e "   ГИБРИДНЫЙ СЦЕНАРИЙ УСПЕШНО НАСТРОЕН (v3.1.1 MULTI-CERT)!"
echo -e "${GREEN}=========================================================${NC}"
echo -e "  Главная Маска-Облако:   ${CYAN}https://${PRIMARY_DOMAIN}${NC}"
echo -e "  Вход в панель 3X-UI:     ${GREEN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
echo -e "  Базовый путь подписок:  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${NC}"
echo

echo -e "${YELLOW}🔑 ГОТОВЫЕ SSL-СЕРТИФИКАТЫ ДЛЯ ИНБАУНДОВ (Права 644 настроены):${NC}"
echo -e "$SSL_DOMAINS_OUTPUT"

echo -e "${YELLOW}🛡️ ШАГ 1: Настройка файервола (UFW)${NC}"
echo -e "Выполните в терминале для защиты внутренних портов и открытия TCP/UDP:"
echo -e "  ${CYAN}ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp && ufw allow 8443/tcp && ufw allow 8443/udp${NC}"
echo -e "  ${RED}ufw deny $PANEL_PORT/tcp && ufw deny $SUB_PORT/tcp && ufw deny $XHTTP_PORT/tcp${UFW_REALITY_DENY}${NC}"
echo

echo -e "${YELLOW}📌 ШАГ 2: Инбаунд VLESS REALITY + TCP + VISION (Классический):${NC}"
echo -e "Создайте Inbound в 3X-UI для любого из портов REALITY [ ${REALITY_PORTS[*]} ]:"
echo -e "  • ${YELLOW}Протокол:${NC} ${GREEN}vless${NC} | ${YELLOW}Транспорт:${NC} ${GREEN}tcp${NC}"
echo -e "  • ${YELLOW}Порт:${NC} ${GREEN}<один из портов: ${REALITY_PORTS[*]}>${NC} | ${YELLOW}Listen IP:${NC} ${GREEN}127.0.0.1${NC}"
echo -e "  • ${YELLOW}Accept Proxy Protocol (xver):${NC} ${GREEN}1 (Включить)${NC} ⚠️ ОБЯЗАТЕЛЬНО!"
echo -e "  • ${YELLOW}Flow:${NC} ${GREEN}xtls-rprx-vision${NC}"
echo -e "  • ${YELLOW}Безопасность:${NC} ${GREEN}reality${NC}"
echo -e "  • ${YELLOW}Dest (Target):${NC} ${CYAN}swdist.microsoft.com:443${NC} (или www.apple.com:443)"
echo -e "  • ${YELLOW}Proxy Protocol для Dest:${NC} ${RED}0 (Выключить)${NC}"
echo -e "  • ${YELLOW}Server Names (SNI):${NC} ${CYAN}swdist.microsoft.com${NC}"
echo -e "  • ${YELLOW}Keys / Short ID:${NC} Нажмите ${GREEN}Get New Keys${NC} в панели"
echo

echo -e "${YELLOW}📌 ШАГ 3: Инбаунд VLESS xHTTP (Защищен SSL Nginx + grpc_pass):${NC}"
echo -e "Создайте Inbound в 3X-UI для xHTTP (используется сертификат любого вашего домена):"
echo -e "  • ${YELLOW}Протокол:${NC} ${GREEN}vless${NC} | ${YELLOW}Транспорт (Transmission):${NC} ${GREEN}xhttp${NC}"
echo -e "  • ${YELLOW}Порт:${NC} ${GREEN}$XHTTP_PORT${NC} | ${YELLOW}Listen IP:${NC} ${GREEN}127.0.0.1${NC}"
echo -e "  • ${YELLOW}Path (Путь):${NC} ${CYAN}$XHTTP_PATH${NC} | ${YELLOW}Mode:${NC} ${GREEN}$XHTTP_UI_MODE_TEXT${NC}"
echo -e "  • ${YELLOW}Безопасность (Security):${NC} ${RED}none${NC} (SSL терминирует Nginx на порту 9443)"
echo -e "  • ${YELLOW}Accept Proxy Protocol:${NC} ${RED}0 (Выключить)${NC} ⚠️ ОБЯЗАТЕЛЬНО!"
echo -e "  • ${YELLOW}Decryption (в пользователе):${NC} Ключ ${GREEN}vlessenc${NC} (Сгенерируйте в панели командой: ${CYAN}xray vlessenc${NC})"
echo -e "  • ${YELLOW}Flow (в пользователе):${NC} ${GREEN}xtls-rprx-vision${NC} *(С vlessenc в Xray 26+ это работает!)*"
echo

echo -e "${YELLOW}📌 ШАГ 4: Инбаунды с прямым SSL (Hysteria 2, Trojan, VLESS-TLS):${NC}"
echo -e "Для Hysteria 2 (UDP) или классического VLESS/Trojan SSL используйте пути к ЛЮБОМУ из выпущенных сертификатов выше:"
echo -e "  • ${YELLOW}Протокол:${NC} ${GREEN}hysteria2${NC} | ${YELLOW}Транспорт:${NC} ${GREEN}udp${NC}"
echo -e "  • ${YELLOW}Порт:${NC} ${GREEN}443${NC} (или 8443) | ${YELLOW}Listen IP:${NC} ${GREEN}0.0.0.0${NC}"
echo -e "  • ${YELLOW}Путь к сертификату:${NC} ${CYAN}/etc/letsencrypt/live/<выбранный_домен>/fullchain.pem${NC}"
echo -e "  • ${YELLOW}Путь к ключу:${NC}       ${CYAN}/etc/letsencrypt/live/<выбранный_домен>/privkey.pem${NC}"
echo

echo -e "${YELLOW}📌 ШАГ 5: Настройка Подписок (3X-UI Panel Settings):${NC}"
echo -e "Перейдите в ${CYAN}Настройки панели (Panel Settings) -> Настройки подписок (Subscription)${NC}:"
echo -e "  • ${YELLOW}Порт подписки:${NC} ${GREEN}$SUB_PORT${NC}"
echo -e "  • ${YELLOW}Путь подписки:${NC} ${GREEN}$SUB_PATH${NC}"
echo -e "  • ${YELLOW}URL обратного прокси:${NC} ${CYAN}https://${PRIMARY_DOMAIN}${SUB_PATH}${NC}"
echo -e "${GREEN}=========================================================${NC}"
exit 0
