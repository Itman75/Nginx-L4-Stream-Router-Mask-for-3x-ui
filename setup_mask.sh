#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup: Hardened Engine v6.0 Universal (Native HTTP/2 Edition)
# Nginx L4 Stream + 3X-UI + Unix Sockets + Native proxy_http_version 2 + 5 Decoys 
# ==============================================================================
# Архитектура:
#   1) Nginx Mainline Branch v.1.31.4+ (Официальный репозиторий nginx.org)
#   2) Нативное HTTP/2 (H2C) проксирование к апстримам: proxy_http_version 2
#   3) Steal-Oneself REALITY с защитой от зацикливания (Anti-Loop Fallback 9443)
#   4) Classic External REALITY (Выделение портов для внешних SNI)
#   5) VLESS xHTTP (Stream-One) + VLESSENC + XTLS-Vision + H2 Streaming
#   6) Гибридный SSL-движок: Certbot (HTTP-01) или acme.sh + Cloudflare (DNS-01)
#   7) 5 режимов маскировки (Decoy Front):
#      - 1: Интеллектуальное зеркалирование animesss.com (Anime/Media Portal)
#      - 2: Интеллектуальное зеркалирование stream.is74.ru/0/streaming (Live Video Stream)
#      - 3: Корпоративный IT SaaS (DataSphere Analytics)
#      - 4: Облако CosmosCloud (с эмуляцией API и ассетами)
#      - 5: Стандартная заглушка Nginx (Welcome to nginx)
#   8) Комплексная защита от ботов, сканеров уязвимостей, AI-парсеров (444/404)
#   9) Полный тюнинг ядра Linux (TCP BBR, fq, somaxconn, lowat, IPC /dev/shm)
# ==============================================================================

set -euo pipefail

# ─────────────────────────── Цвета вывода ───────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[X] $*${NC}" >&2; exit 1; }

trap 'die "Скрипт аварийно прерван на строке $LINENO"' ERR

echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN} Nginx xHTTP VLESSENC+VISION Router v6.0 (NATIVE HTTP/2 UPSTREAM)  ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

# ─────────────────────── Системные предусловия ───────────────────────
if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        die "Данный скрипт оптимизирован строго под дистрибутивы семейств Ubuntu и Debian."
    fi
else
    die "Не удалось определить параметры текущего дистрибутива ОС."
fi

log "Проверка и установка базовых системных утилит..."
declare -A pkg_map=(
    [curl]="curl"
    [bash]="bash"
    [systemctl]="systemd"
    [openssl]="openssl"
    [awk]="gawk"
    [lsb_release]="lsb-release"
    [gpg]="gnupg"
    [dig]="dnsutils"
    [socat]="socat"
    [cron]="cron"
)

apt_updated=0
for cmd in "${!pkg_map[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "Утилита '$cmd' не найдена. Установка пакета: ${pkg_map[$cmd]}..."
        if [ "$apt_updated" -eq 0 ]; then
            apt-get update -q
            apt_updated=1
        fi
        apt-get install -y "${pkg_map[$cmd]}" -q || true
    fi
done

prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val
    read -rp "$(echo -e "${prompt_text} [${GREEN}${default_val}${NC}]: ")" input_val
    declare -g "$var_name=${input_val:-$default_val}"
}

validate_path_segment() {
    local val="$1"
    local name="$2"
    if [[ ! "$val" =~ ^[a-zA-Z0-9_/-]+$ ]]; then
        die "Параметр $name ('$val') содержит недопустимые символы. Используйте только латиницу, цифры, дефис, подчеркивание и слэши."
    fi
}

# ═════════════════════════════════════════════════════════════
#  ИНТЕРАКТИВНАЯ КОНФИГУРАЦИЯ И СЦЕНАРИИ МАРШРУТИЗАЦИИ
# ═════════════════════════════════════════════════════════════
echo
echo -e "${YELLOW}Шаг 1: Конфигурация Главного домена (PRIMARY_DOMAIN)${NC}"
echo -e "${CYAN}Этот домен используется для входа в 3X-UI, подписок, xHTTP (VLESSENC) и Маски.${NC}"
read -rp "Введите ваш основной домен (например, yourdomain.online): " PRIMARY_DOMAIN
[[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] \
    || die "Некорректный формат доменного имени: $PRIMARY_DOMAIN"

ALL_DOMAINS=("$PRIMARY_DOMAIN")
declare -A DOMAIN_TO_PORT
declare -A EXT_SNI_TO_PORT
STEAL_PORTS_LIST=()
CLASSIC_PORTS_LIST=()
ALL_REALITY_PORTS=()
STEAL_DOMAINS=()
EXT_SNI_LIST=()

# Выделенный порт внутреннего Fallback для Steal-Oneself REALITY (Защита от зацикливания)
REALITY_FALLBACK_PORT="9443"

# Проверка алиаса www
if [[ ! "$PRIMARY_DOMAIN" =~ ^www\. ]]; then
    echo
    echo -e "${YELLOW}Защита от ошибок SSL (Certificate Name Mismatch):${NC}"
    read -rp "Добавить алиас 'www.$PRIMARY_DOMAIN' для выпуска SSL и привязки к Nginx? [Y/n]: " ADD_WWW_INPUT
    ADD_WWW_INPUT="${ADD_WWW_INPUT:-y}"
    if [[ "${ADD_WWW_INPUT,,}" == "y" ]]; then
        ALL_DOMAINS+=("www.$PRIMARY_DOMAIN")
        ok "Алиас www.$PRIMARY_DOMAIN добавлен в сертификационный стек."
    fi
fi

echo
echo -e "${YELLOW}Шаг 2: Настройка Steal-Oneself REALITY (Кража у самого себя)${NC}"
echo -e "${CYAN}SSL-сертификаты выпускаются на ваши домены, трафик которых Nginx перенаправляет на порты REALITY.${NC}"
read -rp "Включить Steal-Oneself REALITY? [Y/n]: " ENABLE_STEAL_INPUT
ENABLE_STEAL_INPUT="${ENABLE_STEAL_INPUT:-y}"

if [[ "${ENABLE_STEAL_INPUT,,}" == "y" ]]; then
    STEAL_ENABLED=1
    while true; do
        read -rp "  Введите локальный порт Xray для Steal-Oneself [45443]: " PORT_INPUT
        PORT_VAL="${PORT_INPUT:-45443}"
        if [[ ! "$PORT_VAL" =~ ^[0-9]+$ ]] || [ "$PORT_VAL" -le 0 ] || [ "$PORT_VAL" -gt 65535 ]; then
            warn "  Некорректный номер порта. Назначен порт по умолчанию: 45443."
            PORT_VAL="45443"
        fi

        if [[ ! " ${STEAL_PORTS_LIST[*]:-} " == *" ${PORT_VAL} "* ]]; then
            STEAL_PORTS_LIST+=("$PORT_VAL")
            if [[ ! " ${ALL_REALITY_PORTS[*]:-} " == *" ${PORT_VAL} "* ]]; then
                ALL_REALITY_PORTS+=("$PORT_VAL")
            fi
        fi

        echo -e "${CYAN}  Введите домены для порта $PORT_VAL (для пропуска настройки Steal-Oneself - пусто и Enter):${NC}"
        added_count_for_port=0
        while true; do
            read -rp "    Собственный домен для порта $PORT_VAL: " STEAL_DOM
            if [ -z "$STEAL_DOM" ]; then
                if [ "$added_count_for_port" -eq 0 ]; then
                    warn "    Необходимо добавить как минимум один домен для порта $PORT_VAL!"
                    continue
                fi
                break
            fi

            if [[ ! "$STEAL_DOM" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
                warn "    Некорректный синтаксис домена '$STEAL_DOM'."
                continue
            fi

            if [[ " ${ALL_DOMAINS[*]} " == *" ${STEAL_DOM} "* ]]; then
                warn "    Домен '$STEAL_DOM' уже присутствует в списке."
                continue
            fi

            ALL_DOMAINS+=("$STEAL_DOM")
            STEAL_DOMAINS+=("$STEAL_DOM")
            DOMAIN_TO_PORT["$STEAL_DOM"]="$PORT_VAL"
            added_count_for_port=$((added_count_for_port + 1))
            ok "    Домен $STEAL_DOM привязан к инбаунду $PORT_VAL"
        done

        read -rp "  Сконфигурировать еще один порт Steal-Oneself? [y/N]: " ADD_MORE_STEAL
        [[ "${ADD_MORE_STEAL,,}" == "y" ]] || break
    done
else
    STEAL_ENABLED=0
    log "Сценарий Steal-Oneself REALITY отключен."
fi

echo
echo -e "${YELLOW}Шаг 3: Настройка Classic External REALITY (Сторонние SNI маскировки)${NC}"
echo -e "${CYAN}В этом режиме трафик с внешними SNI (Microsoft, Apple, Samsung и др.) пересылается на локальные порты Xray.${NC}"
read -rp "Включить Classic External REALITY? [Y/n]: " ENABLE_CLASSIC_INPUT
ENABLE_CLASSIC_INPUT="${ENABLE_CLASSIC_INPUT:-y}"

if [[ "${ENABLE_CLASSIC_INPUT,,}" == "y" ]]; then
    CLASSIC_ENABLED=1
    while true; do
        read -rp "  Введите локальный порт Xray для Classic REALITY [46443]: " PORT_INPUT
        PORT_VAL="${PORT_INPUT:-46443}"
        if [[ ! "$PORT_VAL" =~ ^[0-9]+$ ]] || [ "$PORT_VAL" -le 0 ] || [ "$PORT_VAL" -gt 65535 ]; then
            warn "  Некорректный номер порта. Назначен порт по умолчанию: 46443."
            PORT_VAL="46443"
        fi

        if [[ ! " ${CLASSIC_PORTS_LIST[*]:-} " == *" ${PORT_VAL} "* ]]; then
            CLASSIC_PORTS_LIST+=("$PORT_VAL")
            if [[ ! " ${ALL_REALITY_PORTS[*]:-} " == *" ${PORT_VAL} "* ]]; then
                ALL_REALITY_PORTS+=("$PORT_VAL")
            fi
        fi

        echo -e "${CYAN}  Введите внешние SNI для порта $PORT_VAL (нажмите Enter на пустой строке для завершения):${NC}"
        added_sni_count=0
        while true; do
            read -rp "    Внешний SNI (например, swdist.microsoft.com): " EXT_SNI
            if [ -z "$EXT_SNI" ]; then
                if [ "$added_sni_count" -eq 0 ]; then
                    warn "    Порт $PORT_VAL зарегистрирован для обработки fallback-трафика."
                fi
                break
            fi

            if [[ ! "$EXT_SNI" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
                warn "    Некорректный формат SNI: '$EXT_SNI'."
                continue
            fi

            EXT_SNI_TO_PORT["$EXT_SNI"]="$PORT_VAL"
            EXT_SNI_LIST+=("$EXT_SNI")
            added_sni_count=$((added_sni_count + 1))
            ok "    SNI $EXT_SNI привязан к порту $PORT_VAL"
        done

        read -rp "  Сконфигурировать еще один порт Classic REALITY? [y/N]: " ADD_MORE_CLASSIC
        [[ "${ADD_MORE_CLASSIC,,}" == "y" ]] || break
    done
else
    CLASSIC_ENABLED=0
    log "Сценарий Classic External REALITY отключен."
fi

echo
echo -e "${YELLOW}Шаг 4: Дополнительные SSL-домены (Direct TLS / Hysteria 2 / Trojan)${NC}"
while true; do
    read -rp "Добавить собственный домен привязанный к ip сервера для выпуска SSL-сертификата? (Enter для пропуска): " EXTRA_DOM
    if [ -z "$EXTRA_DOM" ]; then
        break
    fi
    if [[ "$EXTRA_DOM" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        if [[ " ${ALL_DOMAINS[*]} " == *" ${EXTRA_DOM} "* ]]; then
            warn "Домен '$EXTRA_DOM' уже присутствует в очереди."
        else
            ALL_DOMAINS+=("$EXTRA_DOM")
            ok "Добавлен SSL-домен: $EXTRA_DOM"
        fi
    else
        warn "Некорректный формат доменного имени: '$EXTRA_DOM'."
    fi
done

echo
echo -e "${YELLOW}Шаг 5: Привязка внутренних портов 3X-UI и HTTP/2 xHTTP (Stream-One)${NC}"
prompt_default "Внутренний порт панели 3X-UI" "10443" PANEL_PORT
prompt_default "Секретный URI-путь к веб-панели (без слэшей)" "my-3x-panel" RAW_PATH
validate_path_segment "$RAW_PATH" "URI панели"
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_default "Внутренний порт сервера подписок 3X-UI" "55443" SUB_PORT
prompt_default "Секретный URI-путь подписок (без слэшей)" "my-post-key" RAW_SUB_PATH
validate_path_segment "$RAW_SUB_PATH" "URI подписок"
SUB_PATH="/${RAW_SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"

prompt_default "Внутренний порт инбаунда VLESS xHTTP (HTTP/2 Stream-One)" "50443" XHTTP_STREAM_PORT
prompt_default "URI-путь для xHTTP Stream-One" "Stream-One-Path" RAW_XHTTP_STREAM_PATH
validate_path_segment "$RAW_XHTTP_STREAM_PATH" "URI xHTTP"
XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH#/}"
XHTTP_STREAM_PATH="${XHTTP_STREAM_PATH%/}/"

echo
echo -e "${YELLOW}Шаг 6: Параметры сайта-маскировки (1 и 2 - Streaming Mirror, 3-4-5 сайты-заглушки)${NC}"
echo -e " 1) ${GREEN}Интеллектуальное зеркалирование animesss.com${NC}"
echo -e " 2) ${GREEN}Интеллектуальное зеркалирование stream.is74.ru/0/streaming (Live Video Stream)${NC}"
echo -e " 3) Корпоративный IT SaaS (Локальная посадочная страница DataSphere Analytics)"
echo -e " 4) Облако CosmosCloud"
echo -e " 5) Стандартная заглушка Nginx (Welcome to nginx)"
prompt_default "Выберите вариант маскировки (1, 2, 3, 4 или 5)" "1" DECOY_MODE

MIRROR_TARGET_HOST="animesss.com"
MIRROR_TARGET_URI=""
MIRROR_BRAND="AnimeSSS"

if [ "$DECOY_MODE" = "1" ]; then
    prompt_default "Хост медиа-портала для зеркалирования" "animesss.com" MIRROR_TARGET_HOST
    prompt_default "Бренд для подмены в HTML-шапках" "AnimeSSS" MIRROR_BRAND
elif [ "$DECOY_MODE" = "2" ]; then
    prompt_default "Хост медиа-сервера для зеркалирования" "stream.is74.ru" MIRROR_TARGET_HOST
    prompt_default "Путь видеотрансляции / видеопотока" "/0/streaming" MIRROR_TARGET_URI
    prompt_default "Бренд для подмены в HTML-шапках" "Интерсвязь" MIRROR_BRAND
fi

echo
echo -e "${YELLOW}Шаг 7: Выбор архитектуры выпуска SSL-сертификатов${NC}"
echo -e " 1) ${GREEN}Классический Certbot (HTTP-01)${NC} - Порт 80, прямое направление A-записей на сервер."
echo -e " 2) ${GREEN}acme.sh + Cloudflare DNS-01${NC} - Выпуск сертификатов через Cloudflare API (включая Wildcard)."
prompt_default "Выберите метод сертификации (1 или 2)" "1" SSL_ENGINE_CHOICE

prompt_default "Email для Let's Encrypt уведомлений (Enter - без почты)" "" LE_EMAIL

CF_AUTH_METHOD="1"
if [ "$SSL_ENGINE_CHOICE" = "2" ]; then
    echo
    echo -e "${YELLOW}Шаг 7.1: Аутентификация в Cloudflare API (acme.sh)${NC}"
    echo -e " 1) ${GREEN}API Token${NC} (Рекомендуется: Zone.DNS:Edit, Zone.Zone:Read)"
    echo -e " 2) ${GREEN}Global API Key${NC} (Полный доступ: Email + Global Key)"
    prompt_default "Выберите вариант (1 или 2)" "1" CF_AUTH_METHOD

    if [ "$CF_AUTH_METHOD" = "1" ]; then
        read -rp "Введите Cloudflare API Token: " CF_Token
        [ -n "$CF_Token" ] || die "API Token не может быть пустым."
        read -rp "Введите Cloudflare Account ID (Enter для пропуска): " CF_Account_ID
        export CF_Token
        [ -n "${CF_Account_ID:-}" ] && export CF_Account_ID
    else
        read -rp "Введите ваш Cloudflare Email: " CF_Email
        [ -n "$CF_Email" ] || die "Email не может быть пустым."
        read -rp "Введите Cloudflare Global API Key: " CF_Key
        [ -n "$CF_Key" ] || die "Global API Key не может быть пустым."
        export CF_Email
        export CF_Key
    fi
fi

# Проверка DNS-записей
log "Проверка A-записей для всех собственных доменов..."
WAN_IP=$(curl -s4 --connect-timeout 5 icanhazip.com || curl -s4 --connect-timeout 5 ifconfig.me || echo "")
if [ -n "$WAN_IP" ]; then
    for dom in "${ALL_DOMAINS[@]}"; do
        resolved_ip=$(dig +short "$dom" @1.1.1.1 2>/dev/null | tail -n1 || echo "")
        if [ -z "$resolved_ip" ]; then
            resolved_ip=$(getent ahosts "$dom" 2>/dev/null | awk '{print $1}' | head -n1 || echo "")
        fi

        if [ -z "$resolved_ip" ]; then
            warn "Домен $dom не разрешается в IP-адрес. Проверьте DNS A-запись."
            read -rp "Продолжить установку? [y/N]: " dns_ans
            [[ "${dns_ans,,}" == "y" ]] || die "Установка отменена пользователем."
        elif [ "$resolved_ip" != "$WAN_IP" ]; then
            warn "Несовпадение IP: $dom указывает на $resolved_ip, IP сервера: $WAN_IP."
            read -rp "Продолжить установку? [y/N]: " dns_ans
            [[ "${dns_ans,,}" == "y" ]] || die "Установка отменена пользователем."
        else
            ok "DNS проверен: $dom -> $WAN_IP"
        fi
    done
fi

# ═════════════════════════════════════════════════════════════
#  ТЮНИНГ ЯДРА LINUX (SYSCTL BBR, SOMAXCONN & BUFFERS)
# ═════════════════════════════════════════════════════════════
log "Применение расширенного тюнинга сетевого стека и ядра Linux..."

cat << 'EOF' > /etc/sysctl.d/99-vless-tuning.conf
# ====================================================================
# БАЗОВЫЕ НАСТРОЙКИ СЕТИ И СИСТЕМЫ
# ====================================================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
vm.swappiness = 10

# ====================================================================
# XRAY / NGINX ОПТИМИЗАЦИИ И ТЮНИНГ ОЧЕРЕДЕЙ
# ====================================================================
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Тайм-ауты сокетов и управление состояниями
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_tw_buckets = 524288
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_orphan_retries = 2
net.ipv4.tcp_slow_start_after_idle = 0

# Оптимизация буферов TCP/UDP под видео-стриминг и туннели
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 212992
net.core.wmem_default = 212992
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 131072 16777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# Тюнинг подсистемы виртуальной памяти
vm.dirty_ratio = 6
vm.dirty_background_ratio = 3

# Автоматическое определение оптимального MTU
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_mtu_probe_floor = 1024

# Дескрипторы и IPC сокеты
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
net.ipv4.tcp_notsent_lowat = 16384
EOF

sysctl --system >/dev/null 2>&1 || true
ok "Параметры ядра BBR, fq и оптимизации сокетов успешно применены."

# Увеличение лимитов безопасности для системы и служб
cat << 'EOF' > /etc/security/limits.d/99-proxy-limits.conf
* soft nofile 524288
* hard nofile 524288
root soft nofile 524288
root hard nofile 524288
www-data soft nofile 524288
www-data hard nofile 524288
nginx soft nofile 524288
nginx hard nofile 524288
EOF

# ═════════════════════════════════════════════════════════════
#  ПОДКЛЮЧЕНИЕ REPO NGINX MAINLINE И УСТАНОВКА
# ═════════════════════════════════════════════════════════════
log "Подключение официального репозитория Nginx Mainline..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install gnupg ca-certificates lsb-release openssl -y -q

mkdir -p /usr/share/keyrings
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes

OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
OS_CODENAME=$(lsb_release -cs)

# Подключение официальной ветки MAINLINE
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/$OS_ID $OS_CODENAME nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

log "Установка Nginx Mainline с поддержкой Stream L4, HTTP/2 Upstream и Unix Sockets..."
apt-get update -q
apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx -y -q

NGINX_USER="nginx"
if ! id -u nginx >/dev/null 2>&1; then
    NGINX_USER="www-data"
fi

mkdir -p /etc/systemd/system/nginx.service.d
cat << 'EOF' > /etc/systemd/system/nginx.service.d/override.conf
[Service]
LimitNOFILE=524288
LimitNPROC=524288
EOF

systemctl daemon-reload

log "Инициализация файловой структуры веб-сервера и кэша..."
WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p /var/cache/nginx/img_cache
mkdir -p /var/cache/nginx/html_cache
mkdir -p /var/cache/nginx/video_cache
mkdir -p /var/www/mirror
mkdir -p /var/www/proxy_temp
mkdir -p /etc/nginx/stream.d
mkdir -p /etc/nginx/conf.d

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp
chmod 755 "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp

# Очистка устаревших конфигурационных файлов
rm -rf /etc/nginx/sites-enabled/* \
       /etc/nginx/sites-available/* \
       /etc/nginx/conf.d/* \
       /etc/nginx/stream.d/*

NGINX_80_SERVER_NAMES="${ALL_DOMAINS[*]}"

log "Создание стартового HTTP-сервера для верификации ACME..."
cat << EOF > "/etc/nginx/conf.d/00-acme.conf"
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

nginx -t || die "Ошибка синтаксиса начальной конфигурации Nginx."
systemctl restart nginx || systemctl start nginx

# ═════════════════════════════════════════════════════════════
#  ВЫПУСК SSL-СЕРТИФИКАТОВ (CERTBOT ИЛИ ACME.SH)
# ═════════════════════════════════════════════════════════════
if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Инициализация подсистемы Certbot через Snap..."
    apt-get install snapd -y -q
    apt-get purge -y certbot || true
    systemctl start snapd.socket || true
    systemctl enable snapd.socket || true

    for i in {1..15}; do
        if snap version >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    snap install core || true
    snap refresh core || true
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot

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

    for dom in "${ALL_DOMAINS[@]}"; do
        log "Выпуск сертификата Let's Encrypt для домена: $dom..."
        if certbot certonly --webroot -w "$WEBROOT" --expand -d "$dom"; then
            ok "Сертификат для $dom успешно получен."
        else
            warn "Не удалось выпустить сертификат для $dom."
            if [ "$dom" = "$PRIMARY_DOMAIN" ]; then
                die "Критическая ошибка: Выпуск сертификата для Главного домена $PRIMARY_DOMAIN провален."
            fi
        fi
    done

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
    cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 755 /etc/letsencrypt/archive/* 2>/dev/null || true
chmod 755 /etc/letsencrypt/live/* 2>/dev/null || true
chmod 644 /etc/letsencrypt/archive/*/* 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true
systemctl reload nginx
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh

else
    log "Инициализация acme.sh через Cloudflare DNS API..."
    apt-get install -y cron socat -q

    ACME_EMAIL="${LE_EMAIL:-}"
    if [ -z "$ACME_EMAIL" ]; then
        ACME_EMAIL="admin@$PRIMARY_DOMAIN"
    fi

    curl -s https://get.acme.sh | sh -s email="$ACME_EMAIL"
    _ACME="${HOME:-/root}/.acme.sh/acme.sh"
    chmod +x "$_ACME"

    "$_ACME" --register-account -m "$ACME_EMAIL" --server letsencrypt

    if [ "$CF_AUTH_METHOD" = "1" ]; then
        export CF_Token="$CF_Token"
        [ -n "${CF_Account_ID:-}" ] && export CF_Account_ID="$CF_Account_ID"
    else
        export CF_Email="$CF_Email"
        export CF_Key="$CF_Key"
    fi

    mkdir -p /etc/letsencrypt/live

    for dom in "${ALL_DOMAINS[@]}"; do
        log "Выпуск SSL для домена: $dom через DNS-01 Cloudflare..."
        if "$_ACME" --issue --dns dns_cf -d "$dom" --server letsencrypt --force; then
            ok "Сертификат для $dom сгенерирован!"
            mkdir -p "/etc/letsencrypt/live/$dom"
            if "$_ACME" --install-cert -d "$dom" \
                --key-file       "/etc/letsencrypt/live/$dom/privkey.pem" \
                --fullchain-file "/etc/letsencrypt/live/$dom/fullchain.pem" \
                --reloadcmd     "chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true; chmod 755 /etc/letsencrypt/live/* 2>/dev/null || true; chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true; systemctl reload nginx"; then
                ok "Сертификат для $dom успешно установлен."
            else
                die "Ошибка установки сертификата $dom в /etc/letsencrypt/live."
            fi
        else
            warn "Ошибка при выпуске сертификата для $dom."
            if [ "$dom" = "$PRIMARY_DOMAIN" ]; then
                die "Критическая ошибка: Выпуск сертификата для Главного домена $PRIMARY_DOMAIN провален."
            fi
        fi
    done
fi

chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
for dom in "${ALL_DOMAINS[@]}"; do
    if [ -d "/etc/letsencrypt/live/$dom" ]; then
        chmod 755 "/etc/letsencrypt/live/$dom" 2>/dev/null || true
        chmod 644 /etc/letsencrypt/live/"$dom"/* 2>/dev/null || true
    fi
done

# ═════════════════════════════════════════════════════════════
#  ГЕНЕРАЦИЯ СТАТИЧЕСКИХ МАСКИРОВОЧНЫХ СТРАНИЦ
# ═════════════════════════════════════════════════════════════
log "Формирование маскировочного контента..."

if [ "$DECOY_MODE" = "3" ]; then
    # 3) DataSphere Analytics
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DataSphere - Платформа облачной аналитики</title>
    <style>
        :root { --primary: #3b82f6; --primary-hover: #2563eb; --bg: #0f172a; --surface: #1e293b; --text: #f8fafc; --text-muted: #94a3b8; }
        body { margin: 0; font-family: 'Inter', system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); overflow-x: hidden; }
        header { display: flex; justify-content: space-between; align-items: center; padding: 24px 5%; border-bottom: 1px solid rgba(255,255,255,0.05); }
        .logo { font-size: 22px; font-weight: 700; display: flex; align-items: center; gap: 10px; letter-spacing: -0.5px; }
        .btn { background: var(--primary); color: #fff; border: none; padding: 12px 24px; border-radius: 8px; font-size: 15px; font-weight: 600; cursor: pointer; transition: background 0.2s; }
        .hero { text-align: center; padding: 120px 20px; max-width: 800px; margin: 0 auto; }
        .hero h1 { font-size: 56px; line-height: 1.1; margin-bottom: 24px; letter-spacing: -1.5px; }
        .hero p { font-size: 20px; color: var(--text-muted); margin: 0 auto 40px; line-height: 1.6; }
        .features { display: flex; gap: 30px; justify-content: center; padding: 60px 5%; flex-wrap: wrap; background: rgba(0,0,0,0.2); border-top: 1px solid rgba(255,255,255,0.02); }
        .feature-card { background: var(--surface); padding: 40px; border-radius: 16px; flex: 1; min-width: 280px; max-width: 380px; border: 1px solid rgba(255,255,255,0.05); text-align: left; }
        .feature-card h3 { font-size: 20px; margin: 20px 0 10px; }
        .feature-card p { color: var(--text-muted); line-height: 1.5; font-size: 15px; }
        .icon { width: 40px; height: 40px; color: var(--primary); }
        footer { text-align: center; padding: 40px; color: var(--text-muted); font-size: 14px; border-top: 1px solid rgba(255,255,255,0.05); }
    </style>
</head>
<body>
    <header>
        <div class="logo">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="28" height="28"><path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
            DataSphere
        </div>
        <button class="btn">Консоль</button>
    </header>
    <section class="hero">
        <h1>Инфраструктура данных нового поколения</h1>
        <p>Высоконадежное корпоративное облако для распределенных вычислений и аналитики больших данных с непрерывным мониторингом доступности.</p>
        <button class="btn" style="padding: 16px 32px; font-size: 18px;">Подключить узел</button>
    </section>
    <section class="features">
        <div class="feature-card">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            <h3>Сквозное шифрование</h3>
            <p>Передача сетевых пакетов осуществляется с аппаратным ускорением TLS 1.3 / AES-GCM.</p>
        </div>
        <div class="feature-card">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
            <h3>Отказоустойчивость</h3>
            <p>Распределенный кластер на базе Anycast DNS обеспечивает SLA доступности 99.99%.</p>
        </div>
    </section>
    <footer>&copy; 2026 DataSphere Cloud Systems. All rights reserved.</footer>
</body>
</html>
EOF

elif [ "$DECOY_MODE" = "4" ]; then
    # 4) CosmosCloud
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

    if [ -f "$WEBROOT/logo.webp" ]; then
        magic_riff=$(head -c 4 "$WEBROOT/logo.webp" | tr -d '\0' || true)
        magic_webp=$(dd if="$WEBROOT/logo.webp" bs=1 skip=8 count=4 status=none 2>/dev/null | tr -d '\0' || true)
        if [[ "$magic_riff" != "RIFF" || "$magic_webp" != "WEBP" ]]; then
            warn "Файл logo.webp имеет неверный формат. Удаление поврежденного файла..."
            rm -f "$WEBROOT/logo.webp"
        else
            ok "Файл logo.webp успешно верифицирован по сигнатуре формата."
        fi
    fi

else
    # 1, 2 и 5: Welcome to nginx
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title><style>body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }</style></head>
<body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working.</p></body>
</html>
EOF
fi

cat << 'EOF' > /var/www/html/404.html
<!DOCTYPE html>
<html>
<head><title>404 Not Found</title></head>
<body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body>
</html>
EOF

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"
chmod 644 "$WEBROOT/index.html" "$WEBROOT/404.html"

# ═════════════════════════════════════════════════════════════
#  ПОЛНАЯ КОНФИГУРАЦИЯ NGINX (STREAM + HTTP CORE + ANTI-BOT)
# ═════════════════════════════════════════════════════════════
log "Сборка конфигурации Nginx Mainline (Stream L4 + HTTP/2 Upstream Engine)..."

UPSTREAM_DECOY_BLOCK=""
if [ "$DECOY_MODE" = "1" ]; then
    UPSTREAM_DECOY_BLOCK="
    upstream mirror_backend {
        server $MIRROR_TARGET_HOST:443;
        keepalive 32;
    }
"
elif [ "$DECOY_MODE" = "2" ]; then
    UPSTREAM_DECOY_BLOCK="
    upstream video_stream_backend {
        server $MIRROR_TARGET_HOST:80;
        keepalive 32;
    }
"
fi

# 1. Глобальный файл конфигурации /etc/nginx/nginx.conf
cat << EOF > /etc/nginx/nginx.conf
user $NGINX_USER;
worker_processes auto;
pid /run/nginx.pid;
worker_rlimit_nofile 524288;

error_log /var/log/nginx/error.log warn;

events {
    worker_connections 65535;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    etag off;
    charset utf-8;
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;
    resolver_timeout 5s;

    # Оптимизация буфера приёма HTTP/2 на воркер
    http2_recv_buffer_size 4m;

    # Получение реального IP клиента из PROXY Protocol
    map \$proxy_protocol_addr \$ak_real_ip {
        ""      \$remote_addr;
        default \$proxy_protocol_addr;
    }

    # Upstream пулы для 3X-UI и нативного HTTP/2 xHTTP (Stream-One via proxy_http_version 2)
    upstream panel_3xui {
        server 127.0.0.1:$PANEL_PORT;
        keepalive 30;
    }

    upstream sub_backend {
        server 127.0.0.1:$SUB_PORT;
        keepalive 30;
    }

    upstream xray_xhttp_stream {
        server 127.0.0.1:$XHTTP_STREAM_PORT;
        keepalive 64;
    }

    $UPSTREAM_DECOY_BLOCK

    proxy_cache_path /var/cache/nginx/img_cache levels=1:2 keys_zone=img_zone:10m max_size=1g inactive=7d use_temp_path=off;
    proxy_cache_path /var/cache/nginx/html_cache levels=1:2 keys_zone=html_zone:20m max_size=500m inactive=30d use_temp_path=off;

    log_format main '\$ak_real_ip [\$time_local] "\$request" \$status \$body_bytes_sent "\$http_user_agent"';
    access_log /var/log/nginx/access.log main buffer=32k flush=60s;

    keepalive_timeout 300s;
    keepalive_requests 100000;
    client_body_timeout 300s;
    client_header_timeout 30s;
    send_timeout 300s;
    reset_timedout_connection on;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;
    set_real_ip_from unix:;

    client_max_body_size 64m;
    client_body_buffer_size 128k;
    large_client_header_buffers 4 16k;
    client_header_buffer_size 1k;

    open_file_cache max=2000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;

    gzip on;
    gzip_vary on;
    gzip_comp_level 2;
    gzip_min_length 512;
    gzip_proxied any;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        "" close;
    }

    # Матрица фильтрации ботов, сканеров уязвимостей и AI скрейперов
    map \$http_user_agent \$badbot_raw {
        default 0;
        "" 1;
        ~*(?:httpclient|lwp-request|axios|fetch|insomnia|postman|libwww-perl|java|php|ruby|nuclei|httpx|ffuf|dirsearch|gobuster) 1;
        ~*(?:sqlmap|nikto|masscan|zgrab|zmap|acunetix|dirbuster|wpscan|nmap|hydra|bfexam|censys|shodan|dirb|feroxbuster|katana) 1;
        ~*(?:ahrefs|semrush|mj12bot|dotbot|rogerbot|exabot|sogou|bytespider|yandexbot|pinterest|baidu|duckduckgo|bingbot|googlebot) 1;
        ~*(?:gptbot|claudebot|chatgpt|cohere|omgili|anthropic|google-extended|applebot-extended|meta-externalagent|ccbot|perplexity|openai|perplexities|gemini|bard|anthropic-ai|commoncrawl|diffbot|weborama|bytespider-ai) 1;
        ~*(?:facebookexternalhit|twitterbot|linkedinbot|slackbot|discordbot) 1;
    }

    map \$request_uri \$is_scan_attempt {
        default 0;
        ~^/(?:pages|public)/(pages|catalog|schedule|random|public|donate|team|login|cp)\.php\$ 0;
        ~*\.(?:php|php5|phtml|asp|aspx|jsp|do|action|cgi|pl|py|rb)\$ 1;
        ~*(\.env|\.git|\.config|\.htaccess|\.sql|\.bak|\.old|\.swp|\.ini|config\.php|web\.config|settings\.py)\$ 1;
        ~*^/(?:admin|administrator|wp-admin|wp-login|phpmyadmin|sqladmin|setup|install|dashboard|manager|controlpanel|config|auth|backend|logs)/ 1;
        ~*(\.\./|\.\.\\|/etc/passwd|/boot/|/windows/|/proc/) 1;
        ~*^/(?:graphql|swagger-ui|api-docs|redoc)/ 1;
        ~*\.(?:zip|tar\.gz|rar|7z)\$ 1;
        ~*(?:\.git/|wp-json|xmlrpc|/\.env|config\.bak|debug\.log|test\.php) 1;
    }

    map "\$badbot_raw:\$is_scan_attempt:\$request_uri" \$badbot {
        ~^.*:/robots\.txt(\?|\$) 0;
        ~^.*:/.well-known/security\.txt(\?|\$) 0;
        ~^1:[01]:${PANEL_PATH} 0;
        ~^1:[01]:${SUB_PATH} 0;
        ~^1:[01]:/sub/ 0;
        ~^1:[01]:${XHTTP_STREAM_PATH} 0;
        ~(^1:|:1) 1;
        default 0;
    }

    limit_req_zone \$binary_remote_addr zone=bot:1m rate=4r/s;
    limit_req_zone \$binary_remote_addr zone=panel:10m rate=30r/s;
    limit_req_zone \$binary_remote_addr zone=subs:1m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=scan:1m rate=1r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:1m;
    limit_req_zone \$binary_remote_addr zone=assets:1m rate=150r/s;
    limit_req_status 429;

    proxy_hide_header X-Proxy-Engine;
    proxy_hide_header X-Original-URL;
    proxy_hide_header X-RateLimit-Remaining;
    proxy_hide_header Server;
    proxy_hide_header X-Powered-By;
    proxy_hide_header Via;
    proxy_hide_header X-Varnish;
    proxy_hide_header X-Varnish-Cache;
    proxy_hide_header Age;
    proxy_hide_header CF-Ray;
    proxy_hide_header CF-Cache-Status;
    proxy_hide_header Alt-Svc;
    proxy_hide_header X-Cache-Status;

    include /etc/nginx/conf.d/*.conf;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF

# 2. Карта SNI для Stream L4
STREAM_MAP_RULES=""
REALITY_UPSTREAMS=""

for dom in "${ALL_DOMAINS[@]}"; do
    if [ "$dom" = "$PRIMARY_DOMAIN" ] || [ "$dom" = "www.$PRIMARY_DOMAIN" ]; then
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;"$'\n'
    elif [ "$STEAL_ENABLED" -eq 1 ] && [ -n "${DOMAIN_TO_PORT[$dom]:-}" ]; then
        port="${DOMAIN_TO_PORT[$dom]}"
        STREAM_MAP_RULES+="        ${dom}     reality_backend_${port};"$'\n'
    else
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;"$'\n'
    fi
done

if [ "$CLASSIC_ENABLED" -eq 1 ]; then
    for ext_sni in "${!EXT_SNI_TO_PORT[@]}"; do
        port="${EXT_SNI_TO_PORT[$ext_sni]}"
        STREAM_MAP_RULES+="        ${ext_sni}     reality_backend_${port};"$'\n'
    done
fi

for port in "${ALL_REALITY_PORTS[@]:-}"; do
    if [ -n "$port" ]; then
        REALITY_UPSTREAMS+="
    upstream reality_backend_${port} {
        server 127.0.0.1:${port};
    }
"
    fi
done

if [ "$CLASSIC_ENABLED" -eq 1 ]; then
    DEFAULT_PORT="${CLASSIC_PORTS_LIST[0]:-46443}"
    DEFAULT_FALLBACK="reality_backend_${DEFAULT_PORT}"
else
    DEFAULT_FALLBACK="nginx_http_backend"
fi

cat << EOF > "/etc/nginx/stream.d/00-stream.conf"
map \$ssl_preread_server_name \$backend_gate {
    hostnames;
    ""                     nginx_http_backend;
${STREAM_MAP_RULES}    default                ${DEFAULT_FALLBACK};
}

upstream nginx_http_backend {
    server unix:/dev/shm/nginx-http.sock;
}

${REALITY_UPSTREAMS}

server {
    listen 443 backlog=65535 reuseport;
    listen [::]:443 backlog=65535 reuseport;

    proxy_protocol on;
    proxy_pass \$backend_gate;
    ssl_preread on;
}

server {
    listen 8443 backlog=65535 reuseport;
    listen [::]:8443 backlog=65535 reuseport;

    proxy_protocol on;
    proxy_pass \$backend_gate;
    ssl_preread on;
}
EOF

# 3. Конфигурация локаций маскировки / стрима
DECOY_LOCATION_BLOCKS=""

if [ "$DECOY_MODE" = "1" ]; then
    # Режим 1: Зеркалирование animesss.com
    DECOY_LOCATION_BLOCKS="
        location ~* ^/(uploads|public|engine|templates)/ {
            root /var/www/mirror;
            try_files \$uri @store_static;
            access_log off;
            expires 365d;
        }

        location @store_static {
            internal;
            proxy_pass https://mirror_backend;
            proxy_store_access user:rw group:rw all:r;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;
            proxy_set_header User-Agent \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36\";
            proxy_ssl_server_name on;
            proxy_ssl_name $MIRROR_TARGET_HOST;
            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_set_header Accept-Encoding \"\";
            proxy_http_version 1.1;
            proxy_set_header Connection \"\";
            proxy_store on;
            root /var/www/mirror;
            proxy_temp_path /var/www/proxy_temp;
        }

        location ~ ^/(assets|cdn|aniserials|api|player)/ {
            access_log off;
            limit_req zone=assets burst=150 nodelay;

            rewrite ^/(.*)($PRIMARY_DOMAIN)(.*)\$ /\$1$MIRROR_TARGET_HOST\$3 break;

            proxy_pass https://mirror_backend;
            proxy_ssl_server_name on;
            proxy_ssl_name $MIRROR_TARGET_HOST;
            proxy_http_version 1.1;

            proxy_buffering on;
            proxy_request_buffering on;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;
            proxy_cache img_zone;
            proxy_cache_valid 200 206 304 3d;
            proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
            proxy_ssl_session_reuse on;

            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_cookie_domain $MIRROR_TARGET_HOST \$host;
            proxy_set_header Referer https://$MIRROR_TARGET_HOST/;
            proxy_set_header Origin https://$MIRROR_TARGET_HOST;
            proxy_set_header User-Agent \$http_user_agent;
            proxy_set_header Accept-Language \$http_accept_language;
            proxy_set_header Accept-Encoding \"\";

            proxy_set_header X-Real-IP \"\";
            proxy_set_header X-Forwarded-For \"\";
            proxy_set_header Forwarded \"\";

            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;

            sub_filter 'https://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter 'http://$MIRROR_TARGET_HOST' 'http://\$host';
            sub_filter '//$MIRROR_TARGET_HOST' '//\$host';
            sub_filter '$MIRROR_BRAND' '$PRIMARY_DOMAIN';
            sub_filter_once off;
            sub_filter_types text/xml text/plain;
        }

        location ^~ /cdn-cgi/ {
            default_type application/javascript;
            return 200 \"\";
            access_log off;
            error_log off;
        }

        location / {
            limit_req zone=bot burst=20 nodelay;
            limit_conn addr 20;

            proxy_pass https://mirror_backend;
            proxy_ssl_server_name on;
            proxy_ssl_name $MIRROR_TARGET_HOST;
            proxy_http_version 1.1;

            proxy_buffering on;
            proxy_request_buffering on;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;
            proxy_ssl_session_reuse on;

            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_cookie_domain $MIRROR_TARGET_HOST \$host;
            proxy_set_header User-Agent \$http_user_agent;
            proxy_set_header Referer https://$MIRROR_TARGET_HOST/;
            proxy_set_header Accept-Encoding \"\";
            proxy_set_header Connection \"\";
            proxy_cache html_zone;
            proxy_cache_key \"\$scheme\$proxy_host\$request_uri\";

            proxy_cache_valid 200 7d;
            proxy_cache_valid 301 302 1d;
            proxy_cache_valid 404 10m;

            proxy_cache_lock on;
            proxy_cache_background_update on;
            proxy_cache_revalidate on;
            proxy_cache_use_stale updating error timeout invalid_header http_500 http_502 http_503 http_504;

            proxy_set_header X-Real-IP \"\";
            proxy_set_header X-Forwarded-For \"\";
            proxy_set_header Forwarded \"\";
            proxy_set_header X-Forwarded-Proto \"\";

            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;

            sub_filter 'https://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter 'http://$MIRROR_TARGET_HOST' 'http://\$host';
            sub_filter '//$MIRROR_TARGET_HOST' '//\$host';
            sub_filter '$MIRROR_BRAND' '$PRIMARY_DOMAIN';
            sub_filter_once off;
            sub_filter_types text/xml text/plain;
        }
"
elif [ "$DECOY_MODE" = "2" ]; then
    # Режим 2: Зеркалирование stream.is74.ru/0/streaming
    DECOY_LOCATION_BLOCKS="
        location ~* ^/0/(streaming|live|hls|playlist|chunks|segments|video)/ {
            access_log off;
            limit_req zone=assets burst=200 nodelay;

            proxy_pass http://video_stream_backend;
            proxy_http_version 1.1;

            proxy_buffering off;
            proxy_request_buffering off;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;

            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_set_header Origin http://$MIRROR_TARGET_HOST;
            proxy_set_header Referer http://$MIRROR_TARGET_HOST/;
            proxy_set_header User-Agent \$http_user_agent;
            proxy_set_header Accept-Encoding \"\";

            proxy_set_header X-Real-IP \"\";
            proxy_set_header X-Forwarded-For \"\";
            proxy_set_header Forwarded \"\";

            proxy_read_timeout 600s;
            proxy_send_timeout 600s;

            sub_filter 'http://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter 'https://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter '//$MIRROR_TARGET_HOST' '//\$host';
            sub_filter '$MIRROR_BRAND' '$PRIMARY_DOMAIN';
            sub_filter_once off;
            sub_filter_types application/vnd.apple.mpegurl application/x-mpegURL text/xml;
        }

        location ~* ^/(static|assets|css|js|images|fonts|player)/ {
            root /var/www/mirror;
            try_files \$uri @store_static;
            access_log off;
            expires 365d;
        }

        location @store_static {
            internal;
            proxy_pass http://video_stream_backend;
            proxy_store_access user:rw group:rw all:r;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;
            proxy_set_header User-Agent \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36\";
            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_set_header Accept-Encoding \"\";
            proxy_http_version 1.1;
            proxy_set_header Connection \"\";
            proxy_store on;
            root /var/www/mirror;
            proxy_temp_path /var/www/proxy_temp;
        }

        location ^~ /cdn-cgi/ {
            default_type application/javascript;
            return 200 \"\";
            access_log off;
            error_log off;
        }

        location / {
            limit_req zone=bot burst=30 nodelay;
            limit_conn addr 30;

            proxy_pass http://video_stream_backend$MIRROR_TARGET_URI;
            proxy_http_version 1.1;

            proxy_buffering on;
            proxy_request_buffering on;
            proxy_ignore_headers Cache-Control Expires Set-Cookie;

            proxy_set_header Host $MIRROR_TARGET_HOST;
            proxy_set_header Origin http://$MIRROR_TARGET_HOST;
            proxy_set_header Referer http://$MIRROR_TARGET_HOST/;
            proxy_set_header User-Agent \$http_user_agent;
            proxy_set_header Accept-Encoding \"\";
            proxy_set_header Connection \"\";

            proxy_cache html_zone;
            proxy_cache_key \"\$scheme\$proxy_host\$request_uri\";
            proxy_cache_valid 200 1d;
            proxy_cache_valid 301 302 1h;
            proxy_cache_valid 404 5m;
            proxy_cache_use_stale updating error timeout invalid_header http_500 http_502 http_503 http_504;

            proxy_set_header X-Real-IP \"\";
            proxy_set_header X-Forwarded-For \"\";
            proxy_set_header Forwarded \"\";
            proxy_set_header X-Forwarded-Proto \"\";

            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;

            sub_filter 'http://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter 'https://$MIRROR_TARGET_HOST' 'https://\$host';
            sub_filter '//$MIRROR_TARGET_HOST' '//\$host';
            sub_filter '$MIRROR_BRAND' '$PRIMARY_DOMAIN';
            sub_filter_once off;
            sub_filter_types text/xml text/plain;
        }
"
elif [ "$DECOY_MODE" = "4" ]; then
    # Режим 4: CosmosCloud
    DECOY_LOCATION_BLOCKS="
        add_header X-Cosmoscloud-Version \"0.22.18\" always;

        location ~ ^/(api/v1/status|status)\$ {
            default_type application/json;
            return 200 '{\"installed\":true,\"maintenance\":false,\"version\":\"0.22.18\",\"productname\":\"CosmosCloud\"}';
        }

        location = /api/v1/auth/login {
            if (\$request_method = POST) {
                add_header Content-Type \"application/json\" always;
                return 401 '{\"error\":\"Wrong nickname or password. Try again or try resetting your password\",\"code\":401}';
            }
            return 405;
        }

        location = / {
            default_type text/html;
            root $WEBROOT;
            try_files /index.html =404;
        }

        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)\$ {
            root $WEBROOT;
            expires 7d;
            access_log off;
            try_files \$uri =404;
        }

        location / {
            return 404;
        }
"
else
    # Режимы 3 и 5: Локальный HTML (DataSphere или Welcome to nginx)
    DECOY_LOCATION_BLOCKS="
        location = / {
            default_type text/html;
            root $WEBROOT;
            try_files /index.html =404;
        }

        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)\$ {
            root $WEBROOT;
            expires 7d;
            access_log off;
            try_files \$uri =404;
        }

        location / {
            return 404;
        }
"
fi

# 4. Основной виртуальный хост (Главный домен) в /etc/nginx/conf.d/01-main.conf
cat << EOF > "/etc/nginx/conf.d/01-main.conf"
# HTTP Порт 80 (Проверка ACME и редирект на HTTPS)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    access_log off;

    if (\$badbot) { return 444; }

    location ^~ /.well-known/acme-challenge/ {
        root $WEBROOT;
    }

    location ~* ^/(wp-admin|wp-login|xmlrpc|vendor|cgi-bin) { return 444; }
    location ~ /\.(git|env|htaccess|svn) { return 444; }

    if (\$host = "") { return 444; }

    location / {
        return 301 https://\$host\$request_uri;
    }

    error_page 400 403 404 405 =404 /dev/null;
}

# HTTPS SSL-Reject сервер для перехвата невалидных SNI и сканеров по IP
server {
    listen unix:/dev/shm/nginx-http.sock ssl default_server proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl default_server proxy_protocol;
    server_name _;

    ssl_reject_handshake on;
    ssl_session_tickets off;

    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;
}

# HTTPS Основной рабочий сервер (Главный домен)
server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $PRIMARY_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    ssl_buffer_size 4k;
    ssl_session_tickets on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    if (\$is_scan_attempt) { return 404; }
    if (\$badbot) { return 404; }
    if (\$request_method !~ ^(GET|HEAD|POST)\$) { return 405; }

    error_page 400 403 404 405 @notfound;

    # ─── ЛОКАЦИЯ 1: ПАНЕЛЬ 3X-UI ───
    location = ${PANEL_PATH%/} {
        return 301 ${PANEL_PATH};
    }

    location ^~ ${PANEL_PATH} {
        limit_req zone=panel burst=40 delay=20;
        proxy_pass http://panel_3xui;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        access_log off;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # ─── ЛОКАЦИЯ 2: ПОДПИСКИ КЛИЕНТОВ ───
    location ^~ /sub/ {
        limit_req zone=subs burst=20 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 8 512k;
        proxy_busy_buffers_size 1024k;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    location ^~ ${SUB_PATH} {
        limit_req zone=subs burst=20 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host localhost;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering on;
        proxy_set_header Accept-Encoding "";
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
    }

    # ─── ЛОКАЦИЯ 3: VLESS xHTTP (Native HTTP/2 Stream-One + VLESSENC + VISION) ───
    location ^~ ${XHTTP_STREAM_PATH} {
        if (\$request_method != POST) {
            return 404;
        }

        proxy_http_version 2;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_request_buffering off;
        proxy_buffering off;

        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
        client_body_timeout 1h;
        send_timeout 1h;

        client_max_body_size 0;

        access_log off;
        error_log off;
        gzip off;

        proxy_pass http://xray_xhttp_stream;
    }

    # ─── ЛОКАЦИЯ 4: ДЕКОЙ САЙТ / МАСКИРОВКА ───
    $DECOY_LOCATION_BLOCKS

    # ─── СЛУЖЕБНЫЕ ЛОКАЦИИ ───
    location = /robots.txt {
        default_type text/plain;
        access_log off;
        return 200 "User-agent: *\nDisallow: /\n";
    }

    location = /favicon.ico {
        root $WEBROOT;
        expires 30d;
        access_log off;
    }

    location = /.well-known/security.txt {
        default_type text/plain;
        access_log off;
        return 200 "Contact: mailto:admin@$PRIMARY_DOMAIN\nPreferred-Languages: ru,en\n";
    }

    location @notfound {
        limit_req zone=scan burst=3 nodelay;
        root $WEBROOT;
        rewrite ^ /404.html break;
    }
}
EOF

# 5. Генерация виртуальных хостов для дополнительных SSL-доменов и Steal-доменов
for ((i=1; i<${#ALL_DOMAINS[@]}; i++)); do
    ext_dom="${ALL_DOMAINS[$i]}"
    if [ "$ext_dom" != "$PRIMARY_DOMAIN" ] && [ -f "/etc/letsencrypt/live/$ext_dom/fullchain.pem" ]; then
        cat << EOF > "/etc/nginx/conf.d/02-${ext_dom}.conf"
server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $ext_dom;

    ssl_certificate /etc/letsencrypt/live/$ext_dom/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$ext_dom/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    root $WEBROOT;
    index index.html;

    $DECOY_LOCATION_BLOCKS

    location @notfound {
        root $WEBROOT;
        rewrite ^ /404.html break;
    }
}
EOF
    fi
done

log "Тестирование собранной конфигурации Nginx Mainline..."
nginx -t || die "Критическая ошибка синтаксиса собранной конфигурации Nginx!"

systemctl unmask nginx || true
systemctl enable nginx || true
systemctl restart nginx

# ═════════════════════════════════════════════════════════════
#  ФОРМИРОВАНИЕ ИТОГОВ И ИНСТРУКЦИИ ДЛЯ 3X-UI
# ═════════════════════════════════════════════════════════════
UFW_DENY_LIST=""
for port in "${ALL_REALITY_PORTS[@]:-}"; do
    if [ -n "$port" ]; then
        UFW_DENY_LIST="${UFW_DENY_LIST} && ufw deny ${port}/tcp"
    fi
done

SSL_CERT_REPORT=""
for dom in "${ALL_DOMAINS[@]}"; do
    if [ -f "/etc/letsencrypt/live/$dom/fullchain.pem" ]; then
        SSL_CERT_REPORT+="  - Домен: ${CYAN}${dom}${NC}\n"
        SSL_CERT_REPORT+="    Cert: ${GREEN}/etc/letsencrypt/live/${dom}/fullchain.pem${NC}\n"
        SSL_CERT_REPORT+="    Key:  ${GREEN}/etc/letsencrypt/live/${dom}/privkey.pem${NC}\n\n"
    fi
done

REALITY_INBOUNDS_REPORT=""
if [ "$STEAL_ENABLED" -eq 1 ]; then
    REALITY_INBOUNDS_REPORT+="\n  ${BOLD}[Сценарий 1: Steal-Oneself (Кража у самого себя с защитой Anti-Loop)]${NC}\n"
    for port in "${STEAL_PORTS_LIST[@]}"; do
        p_doms=()
        for s_dom in "${STEAL_DOMAINS[@]:-}"; do
            if [ "${DOMAIN_TO_PORT[$s_dom]:-}" = "$port" ]; then
                p_doms+=("$s_dom")
            fi
        done
        [ ${#p_doms[@]} -gt 0 ] || continue

        REALITY_INBOUNDS_REPORT+="    - Инбаунд для порта ${GREEN}${port}${NC} (Домены: ${CYAN}${p_doms[*]}${NC}):
      * ${YELLOW}Протокол:${NC} ${GREEN}vless${NC} | ${YELLOW}Транспорт:${NC} ${GREEN}tcp${NC}
      * ${YELLOW}Порт:${NC} ${GREEN}${port}${NC} | ${YELLOW}Listen IP:${NC} ${GREEN}127.0.0.1${NC}
      * ${YELLOW}Accept Proxy Protocol (xver):${NC} ${GREEN}1 (Включить)${NC}
      * ${YELLOW}Flow:${NC} ${GREEN}xtls-rprx-vision${NC} (Для клиентов с поддержкой Vision)
      * ${YELLOW}Безопасность:${NC} ${GREEN}reality${NC}
      * ${YELLOW}Dest (Anti-Loop Fallback Port):${NC} ${GREEN}127.0.0.1:${REALITY_FALLBACK_PORT}${NC}
      * ${YELLOW}Proxy Protocol для Dest (xver):${NC} ${GREEN}1 (Включить)${NC}
      * ${YELLOW}Server Names (SNI):${NC} ${CYAN}${p_doms[*]}${NC}\n\n"
    done
fi

if [ "$CLASSIC_ENABLED" -eq 1 ]; then
    REALITY_INBOUNDS_REPORT+="\n  ${BOLD}[Сценарий 2: Classic External REALITY]${NC}\n"
    for port in "${CLASSIC_PORTS_LIST[@]}"; do
        p_snis=()
        for ext_sni in "${!EXT_SNI_TO_PORT[@]}"; do
            if [ "${EXT_SNI_TO_PORT[$ext_sni]:-}" = "$port" ]; then
                p_snis+=("$ext_sni")
            fi
        done
        [ ${#p_snis[@]} -gt 0 ] || p_snis=("swdist.microsoft.com")
        primary_ext="${p_snis[0]}"

        REALITY_INBOUNDS_REPORT+="    - Инбаунд для порта ${GREEN}${port}${NC} (SNI: ${CYAN}${p_snis[*]}${NC}):
      * ${YELLOW}Протокол:${NC} ${GREEN}vless${NC} | ${YELLOW}Транспорт:${NC} ${GREEN}tcp${NC}
      * ${YELLOW}Порт:${NC} ${GREEN}${port}${NC} | ${YELLOW}Listen IP:${NC} ${GREEN}127.0.0.1${NC}
      * ${YELLOW}Accept Proxy Protocol (xver):${NC} ${GREEN}1 (Включить)${NC}
      * ${YELLOW}Flow:${NC} ${GREEN}xtls-rprx-vision${NC}
      * ${YELLOW}Безопасность:${NC} ${GREEN}reality${NC}
      * ${YELLOW}Dest (Target):${NC} ${CYAN}${primary_ext}:443${NC}
      * ${YELLOW}Proxy Protocol для Dest (xver):${NC} ${RED}0 (Выключить)${NC}
      * ${YELLOW}Server Names (SNI):${NC} ${CYAN}${p_snis[*]}${NC}\n\n"
    done
fi

DECOY_NAME="Локальный Front"
if [ "$DECOY_MODE" = "1" ]; then
    DECOY_NAME="Animesss Mirror (https://${MIRROR_TARGET_HOST})"
elif [ "$DECOY_MODE" = "2" ]; then
    DECOY_NAME="IS74 Stream Mirror (http://${MIRROR_TARGET_HOST}${MIRROR_TARGET_URI})"
elif [ "$DECOY_MODE" = "3" ]; then
    DECOY_NAME="DataSphere IT SaaS"
elif [ "$DECOY_MODE" = "4" ]; then
    DECOY_NAME="CosmosCloud Front"
elif [ "$DECOY_MODE" = "5" ]; then
    DECOY_NAME="Default Nginx Stub"
fi

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "   ИНФРАСТРУКТУРА УСПЕШНО РАЗВЕРНУТА (v6.0 NATIVE HTTP/2 EDITION)!   "
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Маска-Фронтенд:              ${CYAN}https://${PRIMARY_DOMAIN}${NC} (${DECOY_NAME})"
echo -e "  Вход в панель 3X-UI:         ${GREEN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
echo -e "  Канал подписок:              ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${NC}"
echo

echo -e "${YELLOW}[SSL] ВЫПУЩЕННЫЕ СЕРТИФИКАТЫ:${NC}"
echo -e "$SSL_CERT_REPORT"

echo -e "${YELLOW}ШАГ 1: Настройка файервола UFW (Защита локальных сокетов):${NC}"
echo -e "  ${CYAN}ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp && ufw allow 8443/tcp && ufw allow 8443/udp${NC}"
echo -e "  ${RED}ufw deny $PANEL_PORT/tcp && ufw deny $SUB_PORT/tcp && ufw deny $XHTTP_STREAM_PORT/tcp && ufw deny $REALITY_FALLBACK_PORT/tcp${UFW_DENY_LIST}${NC}"
echo

echo -e "${YELLOW}ШАГ 2: Инбаунды VLESS REALITY (3X-UI):${NC}"
echo -e "$REALITY_INBOUNDS_REPORT"

echo -e "${YELLOW}ШАГ 3: Инбаунд VLESS xHTTP (Stream-One + VLESSENC + VISION via H2):${NC}"
echo -e "  - ${YELLOW}Протокол:${NC} ${GREEN}vless${NC} | ${YELLOW}Транспорт:${NC} ${GREEN}xhttp${NC}"
echo -e "  - ${YELLOW}Порт:${NC} ${GREEN}$XHTTP_STREAM_PORT${NC} | ${YELLOW}Listen IP:${NC} ${GREEN}127.0.0.1${NC}"
echo -e "  - ${YELLOW}Безопасность (Security):${NC} ${RED}none${NC} (SSL терминирует Nginx)"
echo -e "  - ${YELLOW}Accept Proxy Protocol:${NC} ${RED}0 (Выключить)${NC}"
echo -e "  - ${YELLOW}Stream Settings (Raw JSON в настройках Inbound 3X-UI):${NC}"
echo -e "${CYAN}{
  \"network\": \"xhttp\",
  \"xhttpSettings\": {
    \"path\": \"$XHTTP_STREAM_PATH\",
    \"host\": \"$PRIMARY_DOMAIN\",
    \"mode\": \"stream-one\",
    \"xPaddingBytes\": \"120-1120\",
    \"xPaddingObfsMode\": true,
    \"xPaddingKey\": \"X-Amz-Meta-Trace\"
  }
}${NC}"
echo -e "  - ${YELLOW}В настройках клиента (3X-UI Client Settings):${NC}"
echo -e "    * ${YELLOW}Flow:${NC} ${GREEN}xtls-rprx-vision${NC} (${CYAN}Для клиентов с ядром Xray 24.9.27+ / 25.x / 26.x${NC})"
echo -e "    * ${YELLOW}Decryption:${NC} Ключ ${GREEN}vlessenc${NC} (${CYAN}xray vlessenc${NC})"
echo -e "    * ${YELLOW}SNI / Host:${NC} ${CYAN}$PRIMARY_DOMAIN${NC}"
echo -e "    * ${YELLOW}Path:${NC} ${CYAN}$XHTTP_STREAM_PATH${NC}"
echo

echo -e "${YELLOW}ШАГ 4: Прямые SSL-инбаунды (Hysteria 2 / Trojan / Direct TLS):${NC}"
echo -e "  - ${YELLOW}Протокол:${NC} ${GREEN}hysteria2${NC} (UDP) | ${YELLOW}Порт:${NC} ${GREEN}443${NC} (или 8443) | ${YELLOW}Listen IP:${NC} ${GREEN}0.0.0.0${NC}"
echo -e "  - ${YELLOW}Certificate Path:${NC} ${CYAN}/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem${NC}"
echo -e "  - ${YELLOW}Private Key Path:${NC} ${CYAN}/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem${NC}"
echo

echo -e "${YELLOW}ШАГ 5: Настройки Подписок и Хостов (Hosts) 3X-UI:${NC}"
echo -e "  - ${YELLOW}Subscription Port:${NC} ${GREEN}$SUB_PORT${NC}"
echo -e "  - ${YELLOW}Subscription Path:${NC} ${GREEN}$SUB_PATH${NC}"
echo -e "  - ${YELLOW}Subscription URL (Sub URL):${NC} ${CYAN}https://${PRIMARY_DOMAIN}${SUB_PATH}${NC}"
echo -e "  - ${YELLOW}В разделе «Хосты» (Hosts 🌐) добавьте 2 правила:${NC}"
echo -e "    1) ${BOLD}MAIN_SAME_443:${NC} Инбаунды: ${CYAN}REALITY + Hysteria 2${NC} -> Порт: ${GREEN}443${NC} | Безопасность: ${GREEN}same${NC}"
echo -e "    2) ${BOLD}XHTTP_TLS_443:${NC} Инбаунд: ${CYAN}VLESS_XHTTP${NC} -> Порт: ${GREEN}443${NC} | Безопасность: ${GREEN}tls${NC} (SNI: ${CYAN}$PRIMARY_DOMAIN${NC})"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
