#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup: Hardened Engine v6.0.2 Universal (Native HTTP/2 Edition)
# Nginx L4 Stream + 3X-UI + Unix Sockets + Native proxy_http_version 2 + 5 Decoys 
# ==============================================================================
# Архитектура:
#   1) Nginx Mainline Branch v.1.31.4+ (Официальный репозиторий nginx.org)
#   2) Steal-Oneself REALITY с защитой от зацикливания (Anti-Loop Fallback 9443)
#   3) Classic External REALITY (Выделение портов для внешних SNI)
#   4) VLESS xHTTP (Stream-One) + VLESSENC + XTLS-Vision + H2 Streaming
#   5) Гибридный SSL-движок: Certbot (HTTP-01) или acme.sh + Cloudflare (DNS-01)
#   6) 5 режимов маскировки (Decoy Front):
#      - 1: Интеллектуальное зеркалирование animesss.com (Anime/Media Portal)
#      - 2: Интеллектуальное зеркалирование stream.is74.ru/0/streaming (Live Video Stream)
#      - 3: Корпоративный IT SaaS (DataSphere Analytics)
#      - 4: Облако CosmosCloud (с эмуляцией API и ассетами)
#      - 5: Стандартная заглушка Nginx (Welcome to nginx)
#   7) Комплексная защита от ботов, сканеров уязвимостей, AI-парсеров (444/404)
#   8) Полный тюнинг ядра Linux (TCP BBR, fq, somaxconn, lowat, IPC /dev/shm)
# ==============================================================================

set -euo pipefail

# --------------------------- Цвета вывода ---------------------------
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

# ----------------------- Системные предусловия -----------------------
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

# =============================================================
#  ИНТЕРАКТИВНАЯ КОНФИГУРАЦИЯ И СЦЕНАРИИ МАРШРУТИЗАЦИИ
# =============================================================
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
    prompt_default "Хост внешнего медиа-портала для зеркалирования" "animesss.com" MIRROR_TARGET_HOST
    prompt_default "Бренд для подмены в HTML-шапках" "AnimeSSS" MIRROR_BRAND
elif [ "$DECOY_MODE" = "2" ]; then
    prompt_default "Хост внешнего медиа-сервера для зеркалирования" "stream.is74.ru" MIRROR_TARGET_HOST
    prompt_default "Путь видеотрансляции / видеопотока" "/0/streaming" MIRROR_TARGET_URI
    prompt_default "Бренд для подмены в HTML-шапках" "Интерсвязь" MIRROR_BRAND
fi

# Защита от указания собственного домена в качестве внешнего источника зеркала
if [[ "$DECOY_MODE" = "1" || "$DECOY_MODE" = "2" ]]; then
    if [ "$MIRROR_TARGET_HOST" = "$PRIMARY_DOMAIN" ] || [[ " ${ALL_DOMAINS[*]} " == *" ${MIRROR_TARGET_HOST} "* ]]; then
        warn "Обнаружено совпадение хоста зеркалирования с собственным доменом сервера ($MIRROR_TARGET_HOST)!"
        warn "Во избежание петли запросов хост автоматически сброшен на внешний источник по умолчанию."
        if [ "$DECOY_MODE" = "1" ]; then
            MIRROR_TARGET_HOST="animesss.com"
        else
            MIRROR_TARGET_HOST="stream.is74.ru"
        fi
    fi
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
        [ -n "${CF_Account_ID:-}" ] && export CF_Account_ID="$CF_Account_ID"
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

# =============================================================
#  ТЮНИНГ ЯДРА LINUX (SYSCT
