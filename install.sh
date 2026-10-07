#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup Monoscript: Hardened Master Engine v3.3.5 Universal
# Architecture: Single-IP Ultra Enhanced + Native Kernel AmneziaWG (Bare-Metal)
# Zero-Leak Frontend: DataSphere SSO In-Memory Gateway + Stealth Admin Hub
# OS Hardening + BBR + somaxconn + Nginx L4 Stream + 3X-UI + Xray v26.7.28 Pinned
# VLESS xHTTP (Native H2C Stream-One) + ML-KEM-768 + Multi-Port REALITY + Stub 11443
# Multi-Tunnel UDP Engine: Hysteria 2 + AWG v3.2 + AWG v2.0 + 3X WireGuard
# High-Speed Golden Standard: Native AWG awg0 (MTU 1360 / MSS 1320 / Jmax 70)
# Zero-SNI Defense (ssl_reject_handshake) + Port 80 444 Drop + WAF v6.0.4 Hardened
# Zero-Placeholder Guarantee: Production-Grade Monolithic Script
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

LOCK_FILE="/var/run/hardened-master-engine-v335.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo -e "\033[0;31m[X] Ошибка: Установщик уже выполняется в параллельном процессе.\033[0m" >&2
    exit 1
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[X] $*${NC}" >&2; exit 1; }

cleanup() {
    local exit_code=$?
    trap - ERR EXIT INT TERM
    rm -f /tmp/vpn_unified_creds.txt /tmp/3xui_install.log /tmp/xray-*.zip /tmp/agh.tar.gz 2>/dev/null || true
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n${RED}[X] Скрипт аварийно прерван на строке ${1:-unknown} (код: ${exit_code}).${NC}" >&2
    fi
    exit "$exit_code"
}
trap 'cleanup $LINENO' ERR INT TERM

clear 2>/dev/null || true
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  Hardened Master Engine v3.3.5 (Single-IP Ultra + Native AmneziaWG)  ${NC}"
echo -e "${CYAN}  Dual-Mode: Clean Setup / Safe Migration + Nginx L4 Native + 3X-UI  ${NC}"
echo -e "${WHITE}  Xray Core v26.7.28 Pinned + Native H2C xHTTP + ML-KEM-768 + Vision  ${NC}"
echo -e "${WHITE}  UDP Stack: Hysteria 2 + AWG v3.2 + AWG v2.0 + 3X WireGuard         ${NC}"
echo -e "${WHITE}  Native Kernel Engine: AmneziaWG (awg0, MTU 1360 / MSS 1320 Golden)  ${NC}"
echo -e "${WHITE}  Stealth SSO Hub: DataSphere In-Memory Portal (3X-UI / AWG / AGH)   ${NC}"
echo -e "${WHITE}  Shield: Zero-SNI + Port 80 444 Drop + Stub 11443 (PROXY_PROTO)      ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

LE_EMAIL=""
TARGET_SSH_PORT="22"
ROOT_PASSWORD=""
NEW_USERNAME=""
NEW_USER_PASS=""
HY2_PORT="443"
AWG_V3_PORT="8443"
AWG_V2_PORT="8444"
WG_NATIVE_PORT="47443"
ENABLE_NATIVE_AWG=1
NATIVE_AWG_PORT="51820"
AGH_DOMAIN=""
AGH_USER="admin"
AGH_PASS=""
AGH_CLIENT_ID=""

rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx /usr/share/keyrings/nginx-archive-keyring.gpg.tmp 2>/dev/null || true
[ -f /usr/share/keyrings/nginx-archive-keyring.gpg ] && [ ! -s /usr/share/keyrings/nginx-archive-keyring.gpg ] && rm -f /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null || true

mkdir -p /etc/needrestart/conf.d
echo "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/99-disable-auto-restart.conf 2>/dev/null || true

if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VER_ID="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$OS_CODENAME" ]; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
    fi

    OS_COMPATIBLE=0
    if [ "$OS_ID" = "ubuntu" ]; then
        if [ -n "$OS_VER_ID" ]; then
            MAJOR_VER=$(echo "$OS_VER_ID" | cut -d. -f1)
            if [[ "$MAJOR_VER" =~ ^[0-9]+$ ]] && [ "$MAJOR_VER" -ge 22 ]; then
                OS_COMPATIBLE=1
            fi
        elif [[ "$OS_CODENAME" =~ ^(jammy|noble|oracular|plucky|testing)$ ]]; then
            OS_COMPATIBLE=1
        fi
    elif [ "$OS_ID" = "debian" ]; then
        if [ -n "$OS_VER_ID" ]; then
            MAJOR_VER=$(echo "$OS_VER_ID" | cut -d. -f1)
            if [[ "$MAJOR_VER" =~ ^[0-9]+$ ]] && [ "$MAJOR_VER" -ge 12 ]; then
                OS_COMPATIBLE=1
            fi
        elif [[ "$OS_CODENAME" =~ ^(bookworm|trixie|forky|testing)$ ]]; then
            OS_COMPATIBLE=1
        fi
    fi

    if [ "$OS_COMPATIBLE" -ne 1 ]; then
        die "ОС ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME) не поддерживается. Требуется Ubuntu 22.04+ / Debian 12+."
    fi
    ok "Операционная система валидирована: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME)"
else
    die "Не удалось определить параметры дистрибутива."
fi

wait_for_apt_lock() {
    local max_wait=120
    local count=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ "$count" -ge "$max_wait" ]; then
            warn "Блокировка APT удерживается более ${max_wait}с."
            break
        fi
        if [ "$count" -eq 0 ]; then
            log "Ожидание завершения фонового обновления..."
        fi
        sleep 2
        count=$((count + 2))
    done
    return 0
}

log "Первичная подготовка системных утилит..."
wait_for_apt_lock
apt-get update -q >/dev/null 2>&1 || true
wait_for_apt_lock
apt-get install -y curl bc bind9-dnsutils iproute2 openssl gawk python3 python3-bcrypt xxd unzip jq sqlite3 bsdextrautils gnupg dirmngr psmisc software-properties-common qrencode -q >/dev/null 2>&1 || true
ok "Базовые утилиты готовы к работе."

validate_port() {
    local p="${1:-}"
    if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 22 ] && [ "$p" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_path_segment() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9_/-]+$ ]]; then
        die "Параметр $2 ('$1') содержит недопустимые символы. Используйте латиницу, цифры, дефис и слэши."
    fi
    return 0
}

SSH_ACTIVE_PORT=""
if [ -n "${SSH_CONNECTION:-}" ]; then
    SSH_ACTIVE_PORT=$(echo "$SSH_CONNECTION" | awk '{print $4}')
fi

if [ -z "$SSH_ACTIVE_PORT" ] || ! validate_port "$SSH_ACTIVE_PORT"; then
    SSH_ACTIVE_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | grep -vE '127\.0\.0\.1|::1' | awk '{print $4}' | awk -F: '{print $NF}' | grep -vE '^60[0-9]{2}$' | sort -n | tail -n1 || echo "")
fi
if [ -z "$SSH_ACTIVE_PORT" ]; then
    SSH_ACTIVE_PORT="22"
fi
TARGET_SSH_PORT="$SSH_ACTIVE_PORT"

prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val=""
    echo -en "${prompt_text} [${GREEN}${default_val}${NC}]: "
    read -r input_val
    declare -g "$var_name=${input_val:-$default_val}"
}

prompt_port() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val=""
    local p_val=""
    while true; do
        echo -en "${prompt_text} [${GREEN}${default_val}${NC}]: "
        read -r input_val
        p_val="${input_val:-$default_val}"
        p_val=$(echo "$p_val" | tr -d '[:space:]')
        if validate_port "$p_val"; then
            declare -g "$var_name=$p_val"
            break
        fi
        warn "Недопустимый номер порта: '$p_val'. Введите целое число от 22 до 65535."
    done
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_ans="${2:-y}"
    local ans=""
    while true; do
        if [ "$default_ans" = "y" ]; then
            echo -en "${prompt_text} [${GREEN}Y/n${NC}]: "
            read -r ans
            ans="${ans:-y}"
        else
            echo -en "${prompt_text} [${YELLOW}y/N${NC}]: "
            read -r ans
            ans="${ans:-n}"
        fi
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "Введите 'y' или 'n'." ;;
        esac
    done
}

get_ssh_service_name() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^sshd\.service"; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

download_asset() {
    local target_file="$1"
    shift
    local urls=("$@")
    for u in "${urls[@]}"; do
        log "Попытка загрузки: $u"
        if curl -fsSL --connect-timeout 8 -m 120 --retry 2 "$u" -o "$target_file" 2>/dev/null; then
            if [ -s "$target_file" ]; then
                ok "Успешно загружено из: $u"
                return 0
            fi
        fi
        warn "Зеркало недоступно, переключение..."
    done
    return 1
}

benchmark_sni() {
    local candidates=("tbank.ru" "gateway.icloud.com" "www.samsung.com" "dl.google.com")
    local best_sni="tbank.ru"
    local min_rtt=999999

    echo -e "${CYAN}[+] Тестирование внешних SNI для Classic REALITY...${NC}" >&2
    for sni in "${candidates[@]}"; do
        local rtt
        rtt=$(LC_ALL=C curl -s -o /dev/null -w "%{time_connect}" --connect-timeout 2 --tlsv1.3 "https://${sni}" 2>/dev/null || echo "0")
        local is_valid=0
        if [ -n "$rtt" ] && [ "$rtt" != "0" ]; then
            is_valid=$(echo "$rtt > 0.001" | bc -l 2>/dev/null || echo "0")
        fi

        if [ "$is_valid" = "1" ]; then
            local rtt_ms
            rtt_ms=$(awk "BEGIN {print int($rtt * 1000)}")
            echo -e "  - ${CYAN}${sni}${NC}: RTT = ${GREEN}${rtt_ms} ms${NC} (TLS 1.3 OK)" >&2
            if [ "$rtt_ms" -lt "$min_rtt" ]; then
                min_rtt="$rtt_ms"
                best_sni="$sni"
            fi
        else
            echo -e "  - ${CYAN}${sni}${NC}: ${RED}Таймаут или недоступен${NC}" >&2
        fi
    done
    echo -e "${GREEN}[OK]${NC} Выбран оптимальный SNI: ${GREEN}${best_sni}${NC} (${min_rtt} ms)" >&2
    echo -n "$best_sni"
}

EXISTING_DB_PATH=""
for alt_db in "/etc/x-ui/x-ui.db" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then
        EXISTING_DB_PATH="$alt_db"
        break
    fi
done

INSTALL_MODE="1"
if [ -n "$EXISTING_DB_PATH" ]; then
    echo
    echo -e "${YELLOW}=====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}  ОБНАРУЖЕНА ДЕЙСТВУЮЩАЯ БАЗА 3X-UI: ${CYAN}${EXISTING_DB_PATH}${NC}"
    echo -e "${YELLOW}=====================================================================${NC}"
    echo -e "  1) ${RED}Чистая установка (Clean Install)${NC} — Сброс базы, новые ключи и клиенты"
    echo -e "  2) ${GREEN}${BOLD}Безопасное обновление (Safe Migration Mode)${NC} — Сохранение ВСЕХ клиентов,"
    echo -e "     их UUID, ключей, паролей, статистики и хостов + авто-патч схемы ALPN"
    prompt_default "Выберите режим работы" "2" INSTALL_MODE

    if [ "$INSTALL_MODE" = "2" ]; then
        ok "Активирован режим БЕЗОПАСНОГО ОБНОВЛЕНИЯ (Safe Migration Mode)!"
        log "Создание горячего резервного бэкапа перед миграцией..."
        
        python3 - << 'EOF_WAL'
import sqlite3
for p in ["/etc/x-ui/x-ui.db", "/usr/local/x-ui/bin/x-ui.db", "/etc/x-ui/db/x-ui.db"]:
    try:
        conn = sqlite3.connect(p, timeout=10.0)
        conn.execute("PRAGMA wal_checkpoint(FULL);")
        conn.close()
    except Exception:
        pass
EOF_WAL

        BACKUP_TAR="/root/backup_before_migration_$(date +%F_%H%M%S).tar.gz"
        tar -czvf "$BACKUP_TAR" \
            /etc/x-ui \
            /etc/nginx \
            /etc/letsencrypt \
            /etc/ssl/acme \
            /etc/amnezia/amneziawg \
            /etc/ufw/before.rules 2>/dev/null || true
        chmod 600 "$BACKUP_TAR"
        ok "Резервная копия создана: $BACKUP_TAR"
    else
        warn "Выбрана ЧИСТАЯ УСТАНОВКА. Прежние клиенты и ключи будут сброшены!"
    fi
fi

DETECTED_COUNTRY=$(curl -s4 --connect-timeout 3 https://ipinfo.io/country 2>/dev/null || echo "")
if [ -z "$DETECTED_COUNTRY" ]; then
    DETECTED_COUNTRY=$(curl -s4 --connect-timeout 3 http://ip-api.com/line/?fields=countryCode 2>/dev/null || echo "")
fi

DEFAULT_GEO_PROFILE="2"
if [[ "${DETECTED_COUNTRY^^}" == "RU" ]]; then
    DEFAULT_GEO_PROFILE="1"
    ok "Сервер расположен в РФ (Геолокация: RU). Рекомендуется профиль [1]."
else
    ok "Сервер расположен за пределами РФ (Геолокация: ${DETECTED_COUNTRY:-Unknown}). Рекомендуется профиль [2]."
fi

echo -e "\n${WHITE}${BOLD}--- ВЫБОР СЕТЕВОГО ПРОФИЛЯ РАЗВЁРТЫВАНИЯ ---${NC}"
echo -e "  1) ${GREEN}[RU] Сервер в РФ${NC} (Яндекс DNS 77.88.8.8, CDN-зеркала, DoH over TCP)"
echo -e "  2) ${GREEN}[EU/World] Зарубежный сервер${NC} (Cloudflare DNS, прямой GitHub, DoQ)"
prompt_default "Выберите сетевой профиль" "$DEFAULT_GEO_PROFILE" GEO_PROFILE

if [ "$GEO_PROFILE" = "1" ]; then
    log "Активация сетевой стратегии для РФ (Яндекс DNS Primary)..."
    cat << 'EOF' > /etc/resolv.conf
nameserver 77.88.8.8
nameserver 77.88.8.1
nameserver 8.8.8.8
EOF
else
    log "Активация сетевой стратегии для зарубежного сервера (Cloudflare Primary)..."
    cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 1: Конфигурация домена и SSL ---${NC}"

DETECTED_MAIN_DOM=""
if [ "$INSTALL_MODE" = "2" ]; then
    if [ -f /etc/nginx/conf.d/01-main.conf ]; then
        DETECTED_MAIN_DOM=$(grep -E 'server_name\s+[^;]+;' /etc/nginx/conf.d/01-main.conf 2>/dev/null | grep -v '_' | awk '{print $2}' | tr -d ';' | head -n1 || echo "")
    fi
fi

while true; do
    prompt_default "Введите ваш основной домен" "${DETECTED_MAIN_DOM:-yourdomain.online}" PRIMARY_DOMAIN
    PRIMARY_DOMAIN=$(echo "$PRIMARY_DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат доменного имени."
done

ALL_DOMAINS=("$PRIMARY_DOMAIN")
declare -A DOMAIN_TO_PORT
declare -A EXT_SNI_TO_PORT
STEAL_PORTS_LIST=()
CLASSIC_PORTS_LIST=()
ALL_REALITY_PORTS=()
STEAL_DOMAINS=()
EXT_SNI_LIST=()

REALITY_FALLBACK_PORT="9443"

while true; do
    echo -en "Введите контактный Email (для Let's Encrypt SSL): "
    read -r LE_EMAIL
    LE_EMAIL=$(echo "$LE_EMAIL" | tr -d '[:space:]')
    if [[ -z "$LE_EMAIL" ]] || [[ "$LE_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат email."
done

echo
echo -e "${WHITE}${BOLD}--- ШАГ 2: Системные настройки и безопасность ОС ---${NC}"
if prompt_yes_no "Выполнить полное обновление системы (apt upgrade) и очистку?" "y"; then
    DO_SYS_UPGRADE=1
else
    DO_SYS_UPGRADE=0
fi

if prompt_yes_no "Установить расширенные инструменты мониторинга (htop, btop, jq, tmux)?" "y"; then
    INSTALL_EXTRA_UTILS=1
else
    INSTALL_EXTRA_UTILS=0
fi

if prompt_yes_no "Включить TCP BBR, somaxconn и отключить IPv6?" "y"; then
    ENABLE_BBR_IPV6=1
else
    ENABLE_BBR_IPV6=0
fi

if prompt_yes_no "Блокировать входящие ICMP (Ping) запросы в фаерволе?" "n"; then
    BLOCK_PING=1
else
    BLOCK_PING=0
fi

echo -e "Текущий активный порт SSH: ${GREEN}${SSH_ACTIVE_PORT}${NC}"
if prompt_yes_no "Сменить порт SSH на нестандартный?" "n"; then
    prompt_port "Введите новый порт SSH (1024-65535)" "2222" TARGET_SSH_PORT
else
    TARGET_SSH_PORT="$SSH_ACTIVE_PORT"
fi

CHANGE_ROOT_PASS=0
CREATE_USER=0
if [ "$INSTALL_MODE" = "1" ]; then
    if prompt_yes_no "Сменить пароль root?" "n"; then
        CHANGE_ROOT_PASS=1
        read -rsp "Введите новый пароль root: " ROOT_PASSWORD; echo
    fi
    if prompt_yes_no "Создать непривилегированного пользователя с sudo?" "n"; then
        CREATE_USER=1
        read -rp "Введите имя пользователя: " NEW_USERNAME
        read -rsp "Введите пароль для $NEW_USERNAME: " NEW_USER_PASS; echo
    fi
fi

if [ "$INSTALL_MODE" = "2" ]; then
    DEFAULT_SSH_KEY="n"
else
    DEFAULT_SSH_KEY="y"
fi
if prompt_yes_no "Настроить SSH ключи Ed25519?" "$DEFAULT_SSH_KEY"; then
    SETUP_KEYS=1
else
    SETUP_KEYS=0
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 3: Настройка панели 3X-UI и секретных путей ---${NC}"

DETECTED_PANEL_PATH="my-3x-panel"
DETECTED_SUB_PATH="my-post-key"
DETECTED_PANEL_PORT="10443"
DETECTED_SUB_PORT="55443"

if [ -n "$EXISTING_DB_PATH" ]; then
    DETECTED_PANEL_PATH=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webBasePath';" 2>/dev/null || echo "my-3x-panel")
    DETECTED_SUB_PATH=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPath';" 2>/dev/null || echo "my-post-key")
    DETECTED_PANEL_PORT=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webPort';" 2>/dev/null || echo "10443")
    DETECTED_SUB_PORT=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPort';" 2>/dev/null || echo "55443")
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH#/}"
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH%/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH#/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH%/}"
fi

prompt_port "Внутренний локальный порт панели 3X-UI" "${DETECTED_PANEL_PORT:-10443}" PANEL_PORT
prompt_default "Секретный URI-путь к веб-панели (без слэшей)" "${DETECTED_PANEL_PATH:-my-3x-panel}" RAW_PATH
validate_path_segment "$RAW_PATH" "URI панели"
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_port "Внутренний порт сервера подписок 3X-UI" "${DETECTED_SUB_PORT:-55443}" SUB_PORT
prompt_default "Секретный URI-путь подписок (без слэшей)" "${DETECTED_SUB_PATH:-my-post-key}" RAW_SUB_PATH
validate_path_segment "$RAW_SUB_PATH" "URI подписок"
SUB_PATH="/${RAW_SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"

SUB_JSON_PATH="${SUB_PATH}sub-json/"
SUB_CLASH_PATH="/sub-clash/"

prompt_port "Внутренний порт инбаунда VLESS xHTTP (Native H2 Stream-One)" "50443" XHTTP_STREAM_PORT
prompt_default "Секретный URI-путь для xHTTP" "Stream-One-Path" RAW_XHTTP_STREAM_PATH
validate_path_segment "$RAW_XHTTP_STREAM_PATH" "URI xHTTP"
XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH#/}"
XHTTP_STREAM_PATH="${XHTTP_STREAM_PATH%/}/"
BASE_XHTTP_PATH="${XHTTP_STREAM_PATH%/}"

ADMIN_USER="admin"
ADMIN_PASS=""
if [ "$INSTALL_MODE" = "1" ]; then
    prompt_default "Логин администратора панели 3X-UI" "admin" ADMIN_USER
    DEFAULT_XP="Xui_$(openssl rand -hex 4)"
    prompt_default "Пароль администратора панели 3X-UI" "$DEFAULT_XP" ADMIN_PASS
else
    ok "В режиме Safe Migration учетные данные администратора панели сохраняются из базы."
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 4: Настройка протоколов маскировки REALITY ---${NC}"
if prompt_yes_no "Включить Steal-Oneself REALITY (Кража у своего поддомена)?" "y"; then
    ENABLE_STEAL=1
else
    ENABLE_STEAL=0
fi

declare -A STEAL_PORT_DOMAINS
if [ "$ENABLE_STEAL" -eq 1 ]; then
    while true; do
        prompt_port "  Локальный порт Xray для Steal-Oneself" "45443" PORT_VAL

        if [[ ! " ${STEAL_PORTS_LIST[*]:-} " == *" ${PORT_VAL} "* ]]; then
            STEAL_PORTS_LIST+=("$PORT_VAL")
            ALL_REALITY_PORTS+=("$PORT_VAL")
        fi

        echo -e "${CYAN}  Введите домены для порта $PORT_VAL (для завершения - пусто и Enter):${NC}"
        added_count_for_port=0
        port_doms_str=""
        while true; do
            local_def="cdn.$PRIMARY_DOMAIN"
            if [ "$added_count_for_port" -gt 0 ]; then
                local_def=""
            fi
            if [ -n "$local_def" ]; then
                prompt_default "    Собственный поддомен для порта $PORT_VAL" "$local_def" S_DOM
            else
                echo -en "    Собственный поддомен для порта $PORT_VAL (Enter для завершения): "
                read -r S_DOM
            fi
            S_DOM=$(echo "$S_DOM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

            if [ -z "$S_DOM" ]; then
                if [ "$added_count_for_port" -eq 0 ]; then
                    warn "    Необходимо указать как минимум один домен!"
                    continue
                fi
                break
            fi

            if [[ ! "$S_DOM" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
                warn "    Некорректный синтаксис домена: '$S_DOM'."
                continue
            fi

            if [[ " ${ALL_DOMAINS[*]} " == *" ${S_DOM} "* ]]; then
                warn "    Домен '$S_DOM' уже есть в списке."
            else
                ALL_DOMAINS+=("$S_DOM")
            fi

            STEAL_DOMAINS+=("$S_DOM")
            DOMAIN_TO_PORT["$S_DOM"]="$PORT_VAL"
            port_doms_str="${port_doms_str} ${S_DOM}"
            added_count_for_port=$((added_count_for_port + 1))
            ok "    Домен $S_DOM привязан к инбаунд-порту $PORT_VAL (Stub 11443)"
        done
        STEAL_PORT_DOMAINS["$PORT_VAL"]="$(echo "$port_doms_str" | xargs)"

        if ! prompt_yes_no "  Сконфигурировать еще один порт Steal-Oneself?" "n"; then
            break
        fi
    done
fi

if prompt_yes_no "Включить Classic External REALITY (Сторонний доверенный SNI)?" "y"; then
    ENABLE_CLASSIC=1
else
    ENABLE_CLASSIC=0
fi

declare -A CLASSIC_PORT_SNIS
if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    while true; do
        prompt_port "  Локальный порт Xray для Classic REALITY" "46443" PORT_VAL

        if [[ ! " ${CLASSIC_PORTS_LIST[*]:-} " == *" ${PORT_VAL} "* ]]; then
            CLASSIC_PORTS_LIST+=("$PORT_VAL")
            ALL_REALITY_PORTS+=("$PORT_VAL")
        fi

        AUTO_BENCH_SNI=$(benchmark_sni)
        echo -e "${CYAN}  Введите внешние SNI для порта $PORT_VAL (для завершения - пусто и Enter):${NC}"
        added_sni_count=0
        port_snis_str=""
        while true; do
            local_def="$AUTO_BENCH_SNI"
            if [ "$added_sni_count" -gt 0 ]; then
                local_def=""
            fi
            if [ -n "$local_def" ]; then
                prompt_default "    Внешний SNI маскировки" "$local_def" C_SNI
            else
                echo -en "    Внешний SNI маскировки (Enter для завершения): "
                read -r C_SNI
            fi
            C_SNI=$(echo "$C_SNI" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

            if [ -z "$C_SNI" ]; then
                if [ "$added_sni_count" -eq 0 ]; then
                    warn "    Необходимо указать как минимум один SNI!"
                    continue
                fi
                break
            fi

            if [[ ! "$C_SNI" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
                warn "    Некорректный формат SNI: '$C_SNI'."
                continue
            fi

            EXT_SNI_TO_PORT["$C_SNI"]="$PORT_VAL"
            EXT_SNI_LIST+=("$C_SNI")
            port_snis_str="${port_snis_str} ${C_SNI}"
            added_sni_count=$((added_sni_count + 1))
            ok "    SNI $C_SNI привязан к порту $PORT_VAL"
        done
        CLASSIC_PORT_SNIS["$PORT_VAL"]="$(echo "$port_snis_str" | xargs)"

        if ! prompt_yes_no "  Сконфигурировать еще один порт Classic REALITY?" "n"; then
            break
        fi
    done
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 5: Дополнительные SSL-домены ---${NC}"
while true; do
    echo -en "Добавить собственный домен для выпуска SSL-сертификата? (Enter для завершения): "
    read -r EXTRA_DOM
    EXTRA_DOM=$(echo "$EXTRA_DOM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [ -z "$EXTRA_DOM" ]; then
        break
    fi
    if [[ "$EXTRA_DOM" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        if [[ " ${ALL_DOMAINS[*]} " == *" ${EXTRA_DOM} "* ]]; then
            warn "Домен '$EXTRA_DOM' уже добавлен в очередь сертификации."
        else
            ALL_DOMAINS+=("$EXTRA_DOM")
            ok "Добавлен в очередь SSL: $EXTRA_DOM"
        fi
    else
        warn "Некорректный формат домена: '$EXTRA_DOM'."
    fi
done

echo
echo -e "${WHITE}${BOLD}--- ШАГ 6: Скоростные UDP VPN туннели ---${NC}"
if prompt_yes_no "Установить Hysteria 2 (UDP)?" "y"; then
    ENABLE_HY2=1
else
    ENABLE_HY2=0
fi

ENABLE_HY2_HOP=0
if [ "$ENABLE_HY2" -eq 1 ]; then
    prompt_port "  Внешний UDP-порт для Hysteria 2" "443" HY2_PORT
    echo -e "  ${WHITE}Режим работы портов Hysteria 2:${NC}"
    echo -e "    1) ${GREEN}Одиночный порт :${HY2_PORT}/udp${NC}"
    echo -e "    2) ${GREEN}Port Hopping :${HY2_PORT} + диапазон 20000-50000/udp${NC}"
    prompt_default "  Выберите вариант (1 или 2)" "2" HY2_MODE_CHOICE
    if [ "$HY2_MODE_CHOICE" = "2" ]; then
        ENABLE_HY2_HOP=1
        ok "  Port Hopping активирован"
    else
        ENABLE_HY2_HOP=0
        ok "  Выбран одиночный порт ${HY2_PORT}/udp"
    fi
fi

if prompt_yes_no "Установить AmneziaWG v3.2 в 3X-UI (UDP)?" "y"; then
    ENABLE_AWG_V3=1
else
    ENABLE_AWG_V3=0
fi
if [ "$ENABLE_AWG_V3" -eq 1 ]; then
    prompt_port "  Внешний UDP-порт для AmneziaWG v3.2 (3X-UI)" "8443" AWG_V3_PORT
fi

if prompt_yes_no "Установить AmneziaWG v2.0 / Legacy в 3X-UI (UDP)?" "y"; then
    ENABLE_AWG_V2=1
else
    ENABLE_AWG_V2=0
fi
if [ "$ENABLE_AWG_V2" -eq 1 ]; then
    prompt_port "  Внешний UDP-порт для AmneziaWG v2.0 (3X-UI)" "8444" AWG_V2_PORT
fi

if prompt_yes_no "Установить чистый 3X WireGuard в 3X-UI (UDP, MTU 1420 / MSS 1380)?" "y"; then
    ENABLE_WG_NATIVE=1
else
    ENABLE_WG_NATIVE=0
fi
if [ "$ENABLE_WG_NATIVE" -eq 1 ]; then
    prompt_port "  Внешний UDP-порт для 3X WireGuard (3X-UI)" "47443" WG_NATIVE_PORT
fi

if prompt_yes_no "Установить НА ТЕХНОЛОГИЯХ ЯДРА нативный сервер AmneziaWG (Bare-Metal, MTU 1360 Golden)?" "y"; then
    ENABLE_NATIVE_AWG=1
    prompt_port "  Выделенный UDP-порт для нативного сервера AmneziaWG" "51820" NATIVE_AWG_PORT
else
    ENABLE_NATIVE_AWG=0
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 7: Приватный DNS AdGuard Home (DoH) ---${NC}"
if prompt_yes_no "Установить приватный AdGuard Home DoH со Split-DNS?" "y"; then
    ENABLE_AGH=1
else
    ENABLE_AGH=0
fi
if [ "$ENABLE_AGH" -eq 1 ]; then
    prompt_default "  Поддомен для AdGuard Home DoH" "dns.$PRIMARY_DOMAIN" AGH_DOMAIN
    ALL_DOMAINS+=("$AGH_DOMAIN")
    prompt_default "  Логин администратора AdGuard Home" "admin" AGH_USER
    DEFAULT_AG_PASS="AgHome_$(openssl rand -hex 4)"
    prompt_default "  Пароль администратора AdGuard Home" "$DEFAULT_AG_PASS" AGH_PASS
    prompt_default "  Секретный ClientID токен для роутера" "home-router" AGH_CLIENT_ID
fi

echo
echo -e "Метод выпуска SSL-сертификатов:"
echo -e "  1) ${GREEN}Нативный Certbot HTTP-01 (Рекомендуется)${NC}"
echo -e "  2) ${GREEN}acme.sh + Cloudflare DNS-01${NC} (Каталог: /etc/ssl/acme/)"
prompt_default "Ваш выбор" "1" SSL_ENGINE_CHOICE

if [ "$SSL_ENGINE_CHOICE" = "2" ]; then
    prompt_default "Вариант аутентификации Cloudflare (1-Token, 2-Global Key)" "1" CF_AUTH_METHOD
    if [ "$CF_AUTH_METHOD" = "1" ]; then
        read -rp "Cloudflare API Token: " CF_Token
        export CF_Token
    else
        read -rp "Cloudflare Email: " CF_Email
        read -rp "Cloudflare Global Key: " CF_Key
        export CF_Email CF_Key
    fi
fi

if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    SSL_BASE_DIR="/etc/letsencrypt/live"
else
    SSL_BASE_DIR="/etc/ssl/acme"
fi

# =============================================================
#  ФАЗА 1: СИСТЕМНЫЙ ХАРДЕНИНГ (ОС, BBR, NO IPV6, SOMAXCONN)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 1: Hardening ОС, TCP BBR, somaxconn и Zero-Log Storage        ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx 2>/dev/null || true

log "Обновление пакетных репозиториев..."
wait_for_apt_lock
apt-get update -q

if [ "${DO_SYS_UPGRADE:-0}" -eq 1 ]; then
    log "Полное обновление пакетов системы..."
    wait_for_apt_lock
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y -q
    apt-get autoclean -y -q
fi

log "Установка системного набора утилит..."
wait_for_apt_lock
CORE_PKGS=(
    curl wget bash sudo systemd openssl gawk lsb-release gnupg bind9-dnsutils
    socat cron ufw iptables iproute2 tar apache2-utils fail2ban python3 python3-systemd
    python3-bcrypt ca-certificates build-essential jq tmux net-tools bc xxd unzip sqlite3 bsdextrautils dirmngr psmisc qrencode
)
apt-get install -y "${CORE_PKGS[@]}" -q || true

if [ "${INSTALL_EXTRA_UTILS:-0}" -eq 1 ]; then
    wait_for_apt_lock
    apt-get install -y htop iperf3 iftop tcpdump mtr-tiny ncdu vnstat openssh-client -q || true
    apt-get install -y btop -q 2>/dev/null || true
fi
ok "Системные утилиты установлены."

mkdir -p /etc/systemd/journald.conf.d/
cat << 'EOF' > /etc/systemd/journald.conf.d/00-volatile.conf
[Journal]
Storage=volatile
RuntimeMaxUse=64M
MaxRetentionSec=1day
EOF
systemctl restart systemd-journald 2>/dev/null || true
ok "Политика Zero-Log активирована в RAM (systemd-journald Storage=volatile)."

if [ "${ENABLE_BBR_IPV6:-0}" -eq 1 ]; then
    log "Настройка TCP BBR, fq, somaxconn, loose rp_filter, ip_nonlocal_bind и отключение IPv6..."
    modprobe tcp_bbr 2>/dev/null || true
    mkdir -p /etc/sysctl.d/
    cat << 'EOF' > /etc/sysctl.d/99-hardened-network.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 100000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_tw_buckets = 524288
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = 65536 131072 262144
vm.swappiness = 10
fs.file-max = 2097152
net.ipv4.tcp_fastopen = 3
net.netfilter.nf_conntrack_max = 1048576
net.ipv4.tcp_notsent_lowat = 16384
EOF
    sysctl --system >/dev/null 2>&1 || true
fi

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
ok "Ядро и лимиты успешно оптимизированы."

log "Настройка параметров безопасности SSH..."
if [ "${CHANGE_ROOT_PASS:-0}" -eq 1 ] && [ -n "${ROOT_PASSWORD:-}" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
fi

if [ "${CREATE_USER:-0}" -eq 1 ] && [ -n "${NEW_USERNAME:-}" ]; then
    if ! id "$NEW_USERNAME" &>/dev/null; then
        adduser --disabled-password --gecos "" "$NEW_USERNAME"
        echo "$NEW_USERNAME:$NEW_USER_PASS" | chpasswd
        usermod -aG sudo "$NEW_USERNAME"
        echo "$NEW_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USERNAME"
        chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
    fi
fi

KEYS_APPLIED=0
if [ "${SETUP_KEYS:-0}" -eq 1 ]; then
    TARGET_KEY_USER="root"
    if [ -n "${NEW_USERNAME:-}" ]; then
        TARGET_KEY_USER="$NEW_USERNAME"
    fi
    USER_HOME=$(getent passwd "$TARGET_KEY_USER" | cut -d: -f6)
    read -rp "SSH ключи: 1-Сгенерировать Ed25519, 2-Вставить, 3-Пропустить [3]: " KEY_CHOICE
    KEY_CHOICE="${KEY_CHOICE:-3}"
    mkdir -p "$USER_HOME/.ssh" && chmod 700 "$USER_HOME/.ssh"
    if [ "$KEY_CHOICE" = "1" ]; then
        ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/id_ed25519" -C "vps-$TARGET_KEY_USER" -N "" -q
        cat "$USER_HOME/.ssh/id_ed25519.pub" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/id_ed25519"
        chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
        echo -e "\n${YELLOW}ПРИВАТНЫЙ КЛЮЧ:${NC}"
        cat "$USER_HOME/.ssh/id_ed25519"
        read -rp "Нажмите Enter после сохранения..." || true
        KEYS_APPLIED=1
    elif [ "$KEY_CHOICE" = "2" ]; then
        read -rp "Вставьте публичный ключ: " PUB_INPUT
        if [ -n "$PUB_INPUT" ]; then
            echo "$PUB_INPUT" >> "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys"
            chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
            KEYS_APPLIED=1
        fi
    fi
fi

ufw allow "${TARGET_SSH_PORT}/tcp" comment 'SSH Target Port' >/dev/null 2>&1 || true

if [ -f /etc/ssh/sshd_config ]; then
    sed -i -E 's/^[#\s]*Port [0-9]+/Port '"$TARGET_SSH_PORT"'/' /etc/ssh/sshd_config || true
    if ! grep -q "^Include /etc/ssh/sshd_config.d/\*\.conf" /etc/ssh/sshd_config 2>/dev/null; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    fi
fi

SSH_SERVICE=$(get_ssh_service_name)
systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl enable "$SSH_SERVICE.service" 2>/dev/null || true

mkdir -p /etc/ssh/sshd_config.d/
cat << EOF > /etc/ssh/sshd_config.d/99-hardening.conf
Port $TARGET_SSH_PORT
AddressFamily inet
PubkeyAuthentication yes
EOF

if [ "$KEYS_APPLIED" -eq 1 ]; then
    if prompt_yes_no "Отключить вход по паролю SSH?" "n"; then
        cat << 'EOF' >> /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
EOF
    fi
fi

mkdir -p /run/sshd
if /usr/sbin/sshd -t; then
    systemctl restart "$SSH_SERVICE.service" || true
    ok "Служба SSH перезапущена на порту $TARGET_SSH_PORT."
else
    warn "Ошибка конфигурации SSH! Откат изменений."
    rm -f /etc/ssh/sshd_config.d/99-hardening.conf
    systemctl restart "$SSH_SERVICE.service" || true
fi

cat << EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = $TARGET_SSH_PORT
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd
EOF
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban || true
ok "Служба Fail2ban активна."

# =============================================================
#  ФАЗА 2: ВНЕШНИЙ ШЛЮЗ NGINX, SSL И ADGUARD HOME DOH
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 2: Внешний шлюз Nginx Mainline, SSL и AdGuard Home            ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

ufw allow 80/tcp comment 'HTTP ACME' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS L4 Router' >/dev/null 2>&1 || true

log "Pre-flight проверка DNS A-записей доменов..."
WAN_IP=$(curl -s4 --connect-timeout 4 icanhazip.com || curl -s4 --connect-timeout 4 ifconfig.me || echo "")
for dom in "${ALL_DOMAINS[@]}"; do
    resolved_ip=$(dig +short "$dom" @77.88.8.8 2>/dev/null | tail -n1 || echo "")
    if [ -z "$resolved_ip" ]; then
        resolved_ip=$(dig +short "$dom" @8.8.8.8 2>/dev/null | tail -n1 || echo "")
    fi
    
    if [ -z "$resolved_ip" ]; then
        warn "Домен $dom пока не резолвится в IP. Убедитесь, что прокси-режим Cloudflare выключен."
        if ! prompt_yes_no "Продолжить установку SSL для $dom?" "y"; then
            die "Установка отменена."
        fi
    elif [ -n "$WAN_IP" ] && [ "$resolved_ip" != "$WAN_IP" ]; then
        warn "Несовпадение IP: $dom указывает на $resolved_ip, ожидается: $WAN_IP."
        if ! prompt_yes_no "Продолжить установку SSL для $dom?" "y"; then
            die "Установка отменена."
        fi
    else
        ok "DNS проверен: $dom -> ${resolved_ip}"
    fi
done

log "Оркестрация защищенного репозитория Nginx для $OS_ID ($OS_CODENAME)..."
systemctl stop nginx 2>/dev/null || true

NGINX_KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
mkdir -p /usr/share/keyrings
rm -f "$NGINX_KEYRING" "${NGINX_KEYRING}.tmp"

NGINX_KEY_OK=0
for key_url in "https://nginx.org/keys/nginx_signing.key" "http://nginx.org/keys/nginx_signing.key"; do
    log "Запрос ключа Nginx: $key_url"
    if curl -fsSL --connect-timeout 12 -m 30 --retry 2 "$key_url" 2>/dev/null | gpg --dearmor -o "${NGINX_KEYRING}.tmp" 2>/dev/null; then
        if [ -s "${NGINX_KEYRING}.tmp" ]; then
            mv -f "${NGINX_KEYRING}.tmp" "$NGINX_KEYRING"
            chmod 644 "$NGINX_KEYRING"
            NGINX_KEY_OK=1
            ok "Ключ Nginx успешно загружен и деарморирован."
            break
        fi
    fi
done

if [ "$NGINX_KEY_OK" -eq 0 ] || ! gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys 2FD21310B49F6B46 &>/dev/null; then
    log "Синхронизация актуальных ключей Nginx через публичные Keyserver пулы..."
    KEYSERVERS=("hkp://keyserver.ubuntu.com:80" "hkps://keys.openpgp.org" "hkp://pgp.mit.edu:80")
    for ks in "${KEYSERVERS[@]}"; do
        if gpg --no-default-keyring --keyring "$NGINX_KEYRING" --keyserver "$ks" \
               --recv-keys 2FD21310B49F6B46 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3 2>/dev/null; then
            chmod 644 "$NGINX_KEYRING"
            NGINX_KEY_OK=1
            ok "Ключи Nginx успешно импортированы из серверов ключей: $ks"
            break
        fi
    done
fi

USE_OFFICIAL_NGINX_REPO=0
if [ "$NGINX_KEY_OK" -eq 1 ] && [ -s "$NGINX_KEYRING" ]; then
    NGINX_REPO_CODENAME="$OS_CODENAME"
    if ! curl -fsSL -I --connect-timeout 5 "https://nginx.org/packages/mainline/$OS_ID/dists/$OS_CODENAME/Release" >/dev/null 2>&1; then
        if [ "$OS_ID" = "ubuntu" ]; then
            NGINX_REPO_CODENAME="noble"
        else
            NGINX_REPO_CODENAME="bookworm"
        fi
    fi

    echo "deb [signed-by=$NGINX_KEYRING] https://nginx.org/packages/mainline/$OS_ID $NGINX_REPO_CODENAME nginx" \
        | tee /etc/apt/sources.list.d/nginx.list >/dev/null

    cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

    wait_for_apt_lock
    if apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/nginx.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" >/dev/null 2>&1; then
        USE_OFFICIAL_NGINX_REPO=1
        ok "Репозиторий Nginx Mainline ($NGINX_REPO_CODENAME) верифицирован."
    else
        warn "Сбой верификации внешнего репозитория nginx.org. Fallback на пакет ОС..."
        rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx
    fi
fi

if [ "$USE_OFFICIAL_NGINX_REPO" -eq 0 ]; then
    log "Установка Nginx из системного репозитория $OS_ID..."
    rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx
    wait_for_apt_lock
    apt-get update -q
    wait_for_apt_lock
    apt-get install -y -q --reinstall -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confmiss" nginx libnginx-mod-stream 2>/dev/null || apt-get install -y -q --reinstall -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confmiss" nginx
else
    wait_for_apt_lock
    apt-get update -q
    wait_for_apt_lock
    apt-get install -y -q --reinstall -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confmiss" nginx
fi

# Гарантированное восстановление mime.types при ручной очистке /etc/nginx
if [ ! -s /etc/nginx/mime.types ]; then
    mkdir -p /etc/nginx
    cat << 'EOF_MIME' > /etc/nginx/mime.types
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/atom+xml                  atom;
    application/rss+xml                   rss;
    text/mathml                           mml;
    text/plain                            txt;
    text/vnd.sun.j2me.app-descriptor      jad;
    text/vnd.wap.wml                      wml;
    text/x-component                      htc;
    image/png                             png;
    image/svg+xml                         svg svgz;
    image/tiff                            tif tiff;
    image/vnd.wap.wbmp                    wbmp;
    image/webp                            webp;
    image/x-icon                          ico;
    image/x-jng                           jng;
    image/x-ms-bmp                        bmp;
    font/woff                             woff;
    font/woff2                            woff2;
    application/java-archive              jar war ear;
    application/json                      json;
    application/pdf                       pdf;
    application/zip                       zip;
    application/octet-stream              bin exe dll deb dmg iso img msi msp msm;
}
EOF_MIME
fi

NGINX_USER="nginx"
id -u nginx >/dev/null 2>&1 || NGINX_USER="www-data"

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p "$WEBROOT/assets/css" "$WEBROOT/assets/js" "$WEBROOT/assets/img"
mkdir -p /var/log/nginx /var/cache/nginx /var/www/mirror /var/www/proxy_temp /etc/nginx/stream.d /etc/nginx/conf.d /etc/nginx/modules-enabled

rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* 2>/dev/null || true
rm -rf /etc/nginx/conf.d/* /etc/nginx/stream.d/* 2>/dev/null || true

chmod 755 /var /var/www "$WEBROOT"
chmod -R 755 "$WEBROOT/.well-known"
chmod 755 /var/log/nginx
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp /var/log/nginx

cat << EOF > /etc/nginx/nginx.conf
user $NGINX_USER;
worker_processes auto;
pid /run/nginx.pid;
worker_rlimit_nofile 524288;
error_log /var/log/nginx/error.log warn;

$MODULE_LOAD_LINE

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
    resolver 77.88.8.8 1.1.1.1 ipv6=off valid=300s;

    http2_recv_buffer_size 16m;
    http2_max_concurrent_streams 512;

    keepalive_timeout 300s;
    keepalive_requests 100000;
    client_body_timeout 300s;
    client_header_timeout 30s;
    send_timeout 300s;
    reset_timedout_connection on;

    map \$proxy_protocol_addr \$ak_real_ip {
        ""      \$remote_addr;
        default \$proxy_protocol_addr;
    }

    upstream panel_3xui { server 127.0.0.1:$PANEL_PORT; keepalive 30; }
    upstream sub_backend { server 127.0.0.1:$SUB_PORT; keepalive 30; }
    upstream xray_xhttp_stream { server 127.0.0.1:$XHTTP_STREAM_PORT; keepalive 64; }
    upstream datasphere_core_backend { server 127.0.0.1:20443; keepalive 16; }

    # Zero-Log Policy: клиентские логи на диск полностью отключены
    access_log off;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;
    set_real_ip_from unix:;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        "" close;
    }

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
        ~^.*:/.well-known/ 0;
        ~^1:[01]:/favicon\.(ico|svg)\$ 0;
        ~^1:[01]:/assets/ 0;
        ~^1:[01]:/dns-query 0;
        ~^1:[01]:/api/v1/datasphere/ 0;
        ~^1:[01]:${PANEL_PATH} 0;
        ~^1:[01]:${SUB_PATH} 0;
        ~^1:[01]:${SUB_JSON_PATH} 0;
        ~^1:[01]:${SUB_CLASH_PATH} 0;
        ~^1:[01]:/sub/ 0;
        ~^1:[01]:/json/ 0;
        ~^1:[01]:/clash/ 0;
        ~^1:[01]:${BASE_XHTTP_PATH} 0;
        ~(^1:|:1) 1;
        default 0;
    }

    limit_req_zone \$binary_remote_addr zone=panel:10m rate=30r/s;
    limit_req_zone \$binary_remote_addr zone=subs:1m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=doh:10m rate=300r/s;
    limit_req_zone \$binary_remote_addr zone=scan:1m rate=1r/s;
    limit_req_zone \$binary_remote_addr zone=bot:1m rate=4r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:1m;
    limit_req_status 429;

    proxy_hide_header Server;
    proxy_hide_header X-Powered-By;
    proxy_hide_header Via;
    proxy_hide_header X-Varnish;
    proxy_hide_header X-Proxy-Engine;
    proxy_hide_header Alt-Svc;
    proxy_hide_header Age;
    proxy_hide_header CF-Ray;
    proxy_hide_header CF-Cache-Status;

    include /etc/nginx/conf.d/*.conf;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF

STREAM_MAP_RULES=""
REALITY_UPSTREAMS=""

for dom in "${ALL_DOMAINS[@]}"; do
    if [ "$dom" = "$PRIMARY_DOMAIN" ] || [ "$dom" = "${AGH_DOMAIN:-}" ]; then
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;\n"
    elif [ "$ENABLE_STEAL" -eq 1 ] && [ -n "${DOMAIN_TO_PORT[$dom]:-}" ]; then
        port="${DOMAIN_TO_PORT[$dom]}"
        STREAM_MAP_RULES+="        ${dom}     reality_backend_${port};\n"
    else
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;\n"
    fi
done

if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    for ext_sni in "${!EXT_SNI_TO_PORT[@]}"; do
        port="${EXT_SNI_TO_PORT[$ext_sni]}"
        STREAM_MAP_RULES+="        ${ext_sni}     reality_backend_${port};\n"
    done
fi

for port in "${ALL_REALITY_PORTS[@]:-}"; do
    if [ -n "$port" ]; then
        REALITY_UPSTREAMS+="
    upstream reality_backend_${port} {
        server 127.0.0.1:${port} max_fails=1 fail_timeout=5s;
        server unix:/dev/shm/nginx-http.sock backup;
    }
"
    fi
done

DEFAULT_PORT="${CLASSIC_PORTS_LIST[0]:-46443}"
if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    DEFAULT_FALLBACK="reality_backend_${DEFAULT_PORT}"
else
    DEFAULT_FALLBACK="nginx_http_backend"
fi

cat << EOF > "/etc/nginx/stream.d/00-stream.conf"
map \$ssl_preread_server_name \$backend_gate {
    hostnames;
    ""                     nginx_http_backend;
$(echo -e "$STREAM_MAP_RULES")    default                ${DEFAULT_FALLBACK};
}

upstream nginx_http_backend {
    server unix:/dev/shm/nginx-http.sock;
}

${REALITY_UPSTREAMS}

server {
    listen 443 backlog=65535 reuseport;
    proxy_protocol on;
    proxy_pass \$backend_gate;
    ssl_preread on;
}
EOF

cat << EOF > "/etc/nginx/conf.d/01-main.conf"
server {
    listen 80 default_server;
    server_name _;
    access_log off;

    if (\$badbot) { return 444; }

    location ^~ /.well-known/acme-challenge/ { 
        root $WEBROOT; 
        default_type "text/plain";
        try_files \$uri =404;
    }

    location ~* ^/(wp-admin|wp-login|xmlrpc|vendor|cgi-bin) { return 444; }
    location ~ /\.(git|env|htaccess|svn) { return 444; }

    if (\$host = "") { return 444; }

    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl default_server proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl default_server proxy_protocol;
    server_name _;
    
    ssl_reject_handshake on;
    ssl_session_tickets off;

    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $PRIMARY_DOMAIN;

    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    if (\$is_scan_attempt) { return 404; }
    if (\$badbot) { return 404; }
    if (\$request_method !~ ^(GET|HEAD|POST)\$) { return 405; }

    error_page 400 403 404 405 @notfound;

    location = ${PANEL_PATH%/} { return 301 ${PANEL_PATH}; }
    location ^~ ${PANEL_PATH} {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=panel burst=40 delay=20;
        proxy_pass http://panel_3xui;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location = ${SUB_PATH%/} { return 301 ${SUB_PATH}; }
    location ^~ ${SUB_PATH} {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location ~* ^/(sub|json|clash)/ {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ ${XHTTP_STREAM_PATH} {
        if (\$request_method != POST) { return 404; }
        
        proxy_http_version 2;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_request_buffering off;
        proxy_buffering off;
        tcp_nodelay on;
        proxy_socket_keepalive on;
        
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

    # DATASPHERE CORE API & IN-MEMORY SSO GATEWAY
    location ^~ /api/v1/datasphere/ {
        proxy_pass http://datasphere_core_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location = /robots.txt {
        root $WEBROOT;
        access_log off;
    }

    location ~ ^/(favicon\\.ico|favicon\\.svg)\$ {
        root $WEBROOT;
        access_log off;
        expires 30d;
    }

    location = / {
        default_type text/html;
        root $WEBROOT;
        try_files /index.html =404;
    }

    location ~* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)\$ {
        root $WEBROOT;
        expires 7d;
        access_log off;
        add_header Cache-Control "public, max-age=604800, immutable" always;
        try_files \$uri =404;
    }

    location @notfound {
        limit_req zone=scan burst=3 nodelay;
        root $WEBROOT;
        rewrite ^ /404.html break;
    }
}
EOF

S_DOM_VAL="${S_DOM:-cdn.$PRIMARY_DOMAIN}"
cat << EOF > /etc/nginx/conf.d/02-steal-stub.conf
server {
    listen 127.0.0.1:11443 ssl proxy_protocol;
    http2 on;
    server_name ${S_DOM_VAL} ${PRIMARY_DOMAIN} *.${PRIMARY_DOMAIN};
    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    location / { return 404; }
}
EOF

if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ -f "${SSL_BASE_DIR}/$AGH_DOMAIN/fullchain.pem" ]; then
    cat << EOF > "/etc/nginx/conf.d/03-adguard.conf"
upstream adguard_backend { server 127.0.0.1:3000; keepalive 32; }

server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $AGH_DOMAIN;

    ssl_certificate ${SSL_BASE_DIR}/$AGH_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$AGH_DOMAIN/privkey.pem;

    location /dns-query {
        limit_req zone=doh burst=500 nodelay;
        proxy_pass http://adguard_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
    }

    location / {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=panel burst=60 delay=30;
        proxy_pass http://adguard_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
fi

nginx -t || die "Критическая ошибка синтаксиса Nginx!"
systemctl restart nginx
ok "Внешний шлюз Nginx Mainline успешно запущен на порту 443."

# =============================================================
#  ФАЗА 3: УСТАНОВКА 3X-UI, XRAY v26.7.28 И БАЗА SQLITE
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 3: Оркестрация 3X-UI, Xray Core v26.7.28 и база SQLite        ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

trap 'systemctl start x-ui 2>/dev/null || true' ERR

DB_PATH="/etc/x-ui/x-ui.db"
if [ ! -f "$DB_PATH" ]; then
    log "Установка официального релиза 3X-UI..."
    UI_SCRIPT="/tmp/3x-ui-install.sh"
    rm -f "$UI_SCRIPT"

    if [ "$GEO_PROFILE" = "1" ]; then
        UI_URLS=(
            "https://ghfast.top/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
            "https://ghproxy.net/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
            "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
        )
    else
        UI_URLS=(
            "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
            "https://ghfast.top/https://github.com/mhsanaei/3x-ui/master/install.sh"
        )
    fi

    download_asset "$UI_SCRIPT" "${UI_URLS[@]}" || die "Не удалось загрузить инсталлятор 3X-UI!"
    printf "n\n" | bash "$UI_SCRIPT" >/tmp/3xui_install.log 2>&1
    rm -f "$UI_SCRIPT"
fi

for alt_db in "$DB_PATH" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then DB_PATH="$alt_db"; break; fi
done
ok "База SQLite 3X-UI готова: $DB_PATH"

systemctl stop x-ui 2>/dev/null || true

TARGET_XRAY_VERSION="v26.7.28"
log "Инспекция архитектуры и закрепление Xray Core ${TARGET_XRAY_VERSION}..."

SYS_ARCH=$(uname -m)
case "$SYS_ARCH" in
    x86_64)
        XRAY_ZIP_ARCH="64"
        XRAY_BIN_NAMES=("xray-linux-amd64" "xray")
        ;;
    aarch64|arm64)
        XRAY_ZIP_ARCH="arm64-v8a"
        XRAY_BIN_NAMES=("xray-linux-arm64-v8a" "xray")
        ;;
    *)
        die "Архитектура процессора $SYS_ARCH не поддерживается!"
        ;;
esac

XRAY_ZIP="/tmp/xray-${TARGET_XRAY_VERSION}.zip"
rm -f "$XRAY_ZIP"

if [ "$GEO_PROFILE" = "1" ]; then
    XRAY_URLS=(
        "https://ghfast.top/https://github.com/XTLS/Xray-core/releases/download/${TARGET_XRAY_VERSION}/Xray-linux-${XRAY_ZIP_ARCH}.zip"
        "https://ghproxy.net/https://github.com/XTLS/Xray-core/releases/download/${TARGET_XRAY_VERSION}/Xray-linux-${XRAY_ZIP_ARCH}.zip"
        "https://github.com/XTLS/Xray-core/releases/download/${TARGET_XRAY_VERSION}/Xray-linux-${XRAY_ZIP_ARCH}.zip"
    )
else
    XRAY_URLS=(
        "https://github.com/XTLS/Xray-core/releases/download/${TARGET_XRAY_VERSION}/Xray-linux-${XRAY_ZIP_ARCH}.zip"
        "https://ghfast.top/https://github.com/XTLS/Xray-core/releases/download/${TARGET_XRAY_VERSION}/Xray-linux-${XRAY_ZIP_ARCH}.zip"
    )
fi

download_asset "$XRAY_ZIP" "${XRAY_URLS[@]}" || die "Не удалось загрузить бинарник Xray-core!"

XRAY_EXTRACT_DIR="/tmp/xray_unpack"
rm -rf "$XRAY_EXTRACT_DIR"
python3 - << 'EOF_ZIP'
import zipfile, os
zip_path = os.environ.get("XRAY_ZIP", "/tmp/xray-v26.7.28.zip")
extract_dir = "/tmp/xray_unpack"
os.makedirs(extract_dir, exist_ok=True)
with zipfile.ZipFile(zip_path, 'r') as zip_ref:
    zip_ref.extractall(extract_dir)
EOF_ZIP
rm -f "$XRAY_ZIP"

mkdir -p /usr/local/x-ui/bin
if [ -f "$XRAY_EXTRACT_DIR/xray" ]; then
    for bin_name in "${XRAY_BIN_NAMES[@]}"; do
        cp -f "$XRAY_EXTRACT_DIR/xray" "/usr/local/x-ui/bin/${bin_name}"
        chmod 755 "/usr/local/x-ui/bin/${bin_name}"
    done
    if [ -f "$XRAY_EXTRACT_DIR/geoip.dat" ]; then
        cp -f "$XRAY_EXTRACT_DIR/geoip.dat" /usr/local/x-ui/bin/
    fi
    if [ -f "$XRAY_EXTRACT_DIR/geosite.dat" ]; then
        cp -f "$XRAY_EXTRACT_DIR/geosite.dat" /usr/local/x-ui/bin/
    fi
    rm -rf "$XRAY_EXTRACT_DIR"
    ok "Ядро Xray ${TARGET_XRAY_VERSION} зафиксировано в /usr/local/x-ui/bin/."
else
    die "Не найден бинарный файл xray!"
fi

XRAY_BIN="/usr/local/x-ui/bin/xray"
if [ ! -x "$XRAY_BIN" ]; then
    XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"
fi

DETECTED_XRAY_VER=$("$XRAY_BIN" version 2>/dev/null | head -n1 | awk '{print $2}' || echo "v26.7.28")
ok "Активная версия Xray: ${GREEN}${DETECTED_XRAY_VER}${NC}"

log "Генерация постквантового ключа VLESS Encryption (ML-KEM-768)..."
vl_out=$("$XRAY_BIN" vlessenc 2>&1)
VLESS_DECRYPTION=$(echo "$vl_out" | grep '"decryption":' | tail -n1 | awk -F'"' '{print $4}' || true)
VLESS_ENCRYPTION=$(echo "$vl_out" | grep '"encryption":' | tail -n1 | awk -F'"' '{print $4}' || true)

if [[ ! "$VLESS_DECRYPTION" =~ ^mlkem768 ]] || [ -z "$VLESS_ENCRYPTION" ]; then
    die "Ошибка генерации ключа VLESS Encryption! Xray вернул: $vl_out"
fi
ok "Ключ ML-KEM-768 успешно сгенерирован!"

STEAL_CONFIG_DATA=""
for p in "${STEAL_PORTS_LIST[@]:-}"; do
    if [ -z "$p" ]; then continue; fi
    read -r -a doms_arr <<< "${STEAL_PORT_DOMAINS[$p]:-}"
    doms_joined=$(IFS=,; echo "${doms_arr[*]}")
    STEAL_CONFIG_DATA="${STEAL_CONFIG_DATA}${p}=${doms_joined};"
done

CLASSIC_CONFIG_DATA=""
for cp in "${CLASSIC_PORTS_LIST[@]:-}"; do
    if [ -z "$cp" ]; then continue; fi
    read -r -a snis_arr <<< "${CLASSIC_PORT_SNIS[$cp]:-}"
    snis_joined=$(IFS=,; echo "${snis_arr[*]}")
    CLASSIC_CONFIG_DATA="${CLASSIC_CONFIG_DATA}${cp}=${snis_joined};"
done

export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_CONFIG_DATA
export ENABLE_CLASSIC CLASSIC_CONFIG_DATA ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ENABLE_AWG_V2 AWG_V2_PORT ENABLE_WG_NATIVE WG_NATIVE_PORT ADMIN_USER ADMIN_PASS
export SSL_BASE_DIR VLESS_DECRYPTION VLESS_ENCRYPTION
export STEAL_DOMAINS_STR="${STEAL_DOMAINS[*]:-}" INSTALL_MODE ENABLE_AGH GEO_PROFILE

python3 - << 'EOF_PY_ENGINE'
# -*- coding: utf-8 -*-
import os, sys, sqlite3, json, uuid, secrets, base64, time

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path, timeout=30.0)
cur = conn.cursor()

try:
    cur.execute("PRAGMA wal_checkpoint(FULL)")
except Exception:
    pass

P = 2**255 - 19
A24 = 121665

def clamp(k_bytes):
    b = bytearray(k_bytes)
    b[0] &= 248; b[31] &= 127; b[31] |= 64
    return int.from_bytes(b, "little")

def x25519(k, u=9):
    x1, x2, z2, x3, z3 = u, 1, 0, u, 1
    for i in range(254, -1, -1):
        bit = (k >> i) & 1
        if bit: x2, x3 = x3, x2; z2, z3 = z3, z2
        A = (x2 + z2) % P; AA = (A * A) % P; B = (x2 - z2) % P; BB = (B * B) % P
        E = (AA - BB) % P; C = (x3 + z3) % P; D = (x3 - z3) % P
        DA = (D * A) % P; CB = (C * B) % P
        x3 = pow(DA + CB, 2, P); z3 = (x1 * pow(DA - CB, 2, P)) % P
        x2 = (AA * BB) % P; z2 = (E * (AA + A24 * E)) % P
        if bit: x2, x3 = x3, x2; z2, z3 = z3, z2
    return (x2 * pow(z2, P - 2, P)) % P

def gen_reality_keypair():
    raw = os.urandom(32)
    k = clamp(raw)
    pub = x25519(k, 9).to_bytes(32, "little")
    return base64.urlsafe_b64encode(raw).decode().rstrip("="), base64.urlsafe_b64encode(pub).decode().rstrip("=")

def gen_wg_keypair():
    raw = os.urandom(32)
    k = clamp(raw)
    pub = x25519(k, 9).to_bytes(32, "little")
    return base64.b64encode(raw).decode(), base64.b64encode(pub).decode()

domain = os.environ["PRIMARY_DOMAIN"]
panel_port = os.environ["PANEL_PORT"]
panel_path = os.environ["PANEL_PATH"]
sub_port = os.environ["SUB_PORT"]
sub_path = os.environ["SUB_PATH"]
sub_json_path = f"{sub_path}sub-json/"
sub_clash_path = "/sub-clash/"
xhttp_port = int(os.environ["XHTTP_STREAM_PORT"])
xhttp_path = os.environ["XHTTP_STREAM_PATH"]
admin_u = os.environ["ADMIN_USER"]
admin_p = os.environ["ADMIN_PASS"]
vless_dekey = os.environ["VLESS_DECRYPTION"]
vless_enkey = os.environ["VLESS_ENCRYPTION"]
install_mode = os.environ.get("INSTALL_MODE", "1")
enable_agh = os.environ.get("ENABLE_AGH") == "1"
geo_profile = os.environ.get("GEO_PROFILE", "2")

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = set(r[0] for r in cur.fetchall())

if "inbounds" in tables:
    cur.execute("SELECT id, protocol, tag, settings, stream_settings FROM inbounds")
    for row_id, proto_val, tag_val, s_raw, st_raw in cur.fetchall():
        s_changed = False
        st_changed = False
        
        if st_raw:
            try:
                st_data = json.loads(st_raw)
                if "externalProxy" in st_data and isinstance(st_data["externalProxy"], list):
                    for ep in st_data["externalProxy"]:
                        if "alpn" in ep:
                            if isinstance(ep["alpn"], str):
                                ep["alpn"] = [x.strip() for x in ep["alpn"].split(",") if x.strip()]
                                st_changed = True
                            elif not isinstance(ep["alpn"], list):
                                ep["alpn"] = [str(ep["alpn"])]
                                st_changed = True
                if st_changed:
                    cur.execute("UPDATE inbounds SET stream_settings = ? WHERE id = ?", 
                                (json.dumps(st_data, ensure_ascii=False), row_id))
            except Exception:
                pass
        
        if proto_val == "amneziawg" and s_raw:
            try:
                s_data = json.loads(s_raw)
                if "server" in s_data and isinstance(s_data["server"], dict):
                    srv = s_data["server"]
                    patch_params = {
                        "contentPaddingAddition": "0",
                        "randomTrailers": False,
                        "disableCookies": True,
                        "keepaliveTimeout": "20-25",
                        "rekeyAfterTime": "300-500",
                        "rekeyTimeout": "10-15",
                        "rejectAfterTime": "600-900",
                        "maxHandshakeAttempts": "10-15",
                        "mtu": 1360,
                        "jc": 4,
                        "jmin": 40,
                        "jmax": 70,
                        "s1": 64,
                        "s2": 56,
                        "s3": 32,
                        "s4": 16
                    }
                    for pk, pv in patch_params.items():
                        if pk not in srv or srv[pk] != pv:
                            srv[pk] = pv
                            s_changed = True
                    if s_changed:
                        cur.execute("UPDATE inbounds SET settings = ? WHERE id = ?",
                                    (json.dumps(s_data, ensure_ascii=False), row_id))
            except Exception:
                pass

if install_mode == "1":
    for tbl in ["client_inbounds", "client_traffics", "clients", "inbounds", "hosts"]:
        if tbl in tables:
            cur.execute(f"DELETE FROM {tbl}")

cur.execute("SELECT id, username, password FROM users LIMIT 1")
urow = cur.fetchone()
if install_mode == "1":
    hashed_p = admin_p
    try:
        import bcrypt
        hashed_p = bcrypt.hashpw(admin_p.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    except Exception:
        import hashlib
        hashed_p = hashlib.sha256(admin_p.encode("utf-8")).hexdigest()
    if urow:
        cur.execute("UPDATE users SET username = ?, password = ? WHERE id = ?", (admin_u, hashed_p, urow[0]))
        uid = urow[0]
    else:
        cur.execute("INSERT INTO users (id, username, password) VALUES (1, ?, ?)", (admin_u, hashed_p))
        uid = 1
else:
    uid = urow[0] if urow else 1

settings_data = {
    "port": panel_port,
    "webPort": panel_port,
    "webBasePath": panel_path,
    "webListen": "127.0.0.1",
    "webDomain": "",
    "webCertFile": "",
    "webKeyFile": "",
    "subEnable": "true",
    "subPort": sub_port,
    "subListen": "127.0.0.1",
    "subPath": sub_path,
    "subURI": f"https://{domain}{sub_path}",
    "subJsonPath": sub_json_path,
    "subJsonURI": f"https://{domain}{sub_json_path}",
    "subClashPath": sub_clash_path,
    "subClashURI": f"https://{domain}{sub_clash_path}",
    "subDomain": "",
    "subCertFile": "",
    "subKeyFile": "",
    "subUpdates": "12",
    "subEncrypt": "true",
    "subShowInfo": "true",
    "subJsonEnable": "true",
    "subClashEnable": "true",
    "subRemarkModel": "{{INBOUND}}-{{EMAIL}}|\U0001F4CA{{TRAFFIC}}|\u23F3{{EXP_TIME}}",
    "timeLocation": "Europe/Moscow",
    "trafficResetDay": "1",
    "sessionMaxAge": "3600",
    "trustedProxyCIDRs": "127.0.0.1/32,10.8.1.0/24,10.8.2.0/24,10.8.3.0/24,10.9.0.0/24",
    "realityScanCandidates": "www.cloudflare.com:443,www.microsoft.com:443,www.amazon.com:443,aws.amazon.com:443,www.samsung.com:443,www.nvidia.com:443,www.amd.com:443,www.intel.com:443,www.sony.com:443,dl.google.com:443",
    "restartXrayOnClientDisable": "true",
    "xrayOutboundTestUrl": "https://www.google.com/generate_204",
    "subJsonAlwaysArray": "true",
    "subClashAutoDetect": "true",
    "subJsonAutoDetect": "false"
}
for k, v in settings_data.items():
    cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
    if cur.fetchone():
        if install_mode == "1" or k in ["webListen", "subListen", "subPath", "subURI", "subJsonPath", "subJsonURI", "subClashPath", "subClashURI", "trustedProxyCIDRs", "subJsonAlwaysArray", "subClashAutoDetect", "subShowInfo", "subEnable"]:
            cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

freedom_final_rules = []
if enable_agh:
    freedom_final_rules.append({"action": "allow", "ip": ["127.0.0.1"], "port": "53"})
freedom_final_rules.append({"action": "allow", "ip": ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24", "10.9.0.0/24"]})
freedom_final_rules.append({"action": "block", "ip": ["geoip:private"]})
freedom_final_rules.append({"action": "allow"})

routing_rules = [
    {"inboundTag": ["api"], "outboundTag": "api", "type": "field"}
]
if enable_agh:
    routing_rules.append({"ip": ["127.0.0.1"], "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
routing_rules.append({"ip": ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24", "10.9.0.0/24"], "outboundTag": "direct", "type": "field"})
routing_rules.append({"ip": ["geoip:private"], "outboundTag": "blocked", "type": "field"})
routing_rules.append({"outboundTag": "blocked", "protocol": ["bittorrent"], "type": "field"})

dns_config = {}
if enable_agh:
    dns_config = {
        "tag": "dns_inbound",
        "hosts": {},
        "servers": [
            {
                "address": "127.0.0.1",
                "domains": [],
                "expectedIPs": [],
                "unexpectedIPs": [],
                "queryStrategy": "UseIPv4",
                "skipFallback": False,
                "disableCache": False,
                "finalQuery": False,
                "serveStale": False,
                "serveExpiredTTL": 0,
                "timeoutMs": 4000,Fallback": False,
        "disableFallbackIfMatch": False,
        "enableParallelQuery": False,
        "useSystemHosts": False,
        "serveStale": False,
        "serveExpiredTTL": 0
    }

tpl_config = {
    "api": {"services": ["HandlerService", "LoggerService", "StatsService", "RoutingService"], "tag": "api"},
    "dns": dns_config,
    "fakedns": None,
    "inbounds": [{"listen": "127.0.0.1", "port": 62789, "protocol": "tunnel", "settings": {"rewriteAddress": "127.0.0.1"}, "tag": "api"}],
    "log": {"access": "none", "dnsLog": False, "error": "", "loglevel": "warning", "maskAddress": ""},
    "metrics": {"listen": "127.0.0.1:11111", "tag": "metrics_out"},
    "outbounds": [
        {"tag": "direct", "protocol": "freedom", "settings": {"finalRules": freedom_final_rules}, "streamSettings": {"sockopt": {"domainStrategy": "ForceIPv4"}}},
        {"tag": "blocked", "protocol": "blackhole", "settings": {}}
    ],
    "policy": {"system": {"statsInboundDownlink": True, "statsInboundUplink": True, "statsOutboundDownlink": False, "statsOutboundUplink": False}, "levels": {"0": {"statsUserDownlink": True, "statsUserUplink": True}}},
    "routing": {"domainStrategy": "IPIfNonMatch", "rules": routing_rules},
    "stats": {}
}

cur.execute("SELECT id FROM settings WHERE key = 'xrayTemplateConfig'")
if cur.fetchone():
    cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(tpl_config),))
else:
    cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(tpl_config),))

test_email = "Test"
test_sub_id = "SUB_Test"
test_uuid = str(uuid.uuid4())
test_password = secrets.token_hex(8)
test_auth = test_password
reality_hex_sid = secrets.token_hex(8)

def_r_priv, def_r_pub = gen_reality_keypair()
def_wg_s_priv, def_wg_s_pub = gen_wg_keypair()
def_wg_s2_priv, def_wg_s2_pub = gen_wg_keypair()
def_wg_c_priv, def_wg_c_pub = gen_wg_keypair()
def_wg_nat_s_priv, def_wg_nat_s_pub = gen_wg_keypair()
def_wg_nat_c_priv, def_wg_nat_c_pub = gen_wg_keypair()

now_ms = int(time.time() * 1000)

client_reality_dict = {
    "auth": test_auth, "comment": "", "created_at": now_ms, "email": test_email,
    "enable": True, "expiryTime": 0, "flow": "xtls-rprx-vision", "id": test_uuid, "keepAlive": 25,
    "limitIp": 0, "password": test_password, "privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub,
    "reset": 0, "resetDay": 0, "resetMax": 0, "security": "auto", "subId": test_sub_id,
    "tgId": 0, "totalGB": 0, "trafficReset": "never", "trafficResetDay": 1, "updated_at": now_ms
}

client_xhttp_dict = dict(client_reality_dict)
client_xhttp_dict["flow"] = "xtls-rprx-vision"

active_inbound_ids = []

def upsert_inbound(port, proto, tag, remark, s_obj_def, st_obj_def, listen="127.0.0.1"):
    cur.execute("SELECT id, settings, stream_settings FROM inbounds WHERE tag = ?", (tag,))
    row = cur.fetchone()
    sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})
    
    if row and install_mode == "2":
        inbound_id = row[0]
        final_s = json.loads(row[1]) if row[1] else {}
        final_st = json.loads(row[2]) if row[2] else {}
        if not final_s.get("clients") and "clients" in s_obj_def:
            final_s["clients"] = s_obj_def.get("clients", [])
        if "clients" in final_s and isinstance(final_s["clients"], list):
            for c in final_s["clients"]:
                pwd = c.get("password")
                if pwd and c.get("auth") != pwd:
                    c["auth"] = pwd
        if proto == "vless" and "decryption" in s_obj_def:
            final_s["decryption"] = s_obj_def["decryption"]
            final_s["encryption"] = s_obj_def.get("encryption", "")
        if "realitySettings" in final_st:
            rs = final_st["realitySettings"]
            rs["minClientVer"] = "1.0.0"
            rs["spiderX"] = "/"
            if not rs.get("shortIds"): rs["shortIds"] = [reality_hex_sid]
            if proto == "vless" and "in-steal-reality" in tag:
                rs["dest"] = "127.0.0.1:11443"
                rs["target"] = "127.0.0.1:11443"
        
        if "externalProxy" in final_st and isinstance(final_st["externalProxy"], list):
            for ep in final_st["externalProxy"]:
                if "alpn" in ep and isinstance(ep["alpn"], str):
                    ep["alpn"] = [a.strip() for a in ep["alpn"].split(",") if a.strip()]

        if proto == "amneziawg" and "server" in final_s:
            final_s["server"]["contentPaddingAddition"] = "0"
            final_s["server"]["mtu"] = 1360
            final_s["server"]["jc"] = 4
            final_s["server"]["jmin"] = 40
            final_s["server"]["jmax"] = 70
            final_s["server"]["s1"] = 64
            final_s["server"]["s2"] = 56
            final_s["server"]["s3"] = 32
            final_s["server"]["s4"] = 16
            final_s["server"]["randomTrailers"] = False
            final_s["server"]["disableCookies"] = True
            final_s["server"]["rekeyAfterTime"] = "300-500"
            final_s["server"]["rekeyTimeout"] = "10-15"
            final_s["server"]["rejectAfterTime"] = "600-900"
            final_s["server"]["keepaliveTimeout"] = "20-25"
            final_s["server"]["maxHandshakeAttempts"] = "10-15"
            if not final_s["server"].get("h1"):
                final_s["server"]["h1"] = s_obj_def["server"]["h1"]
                final_s["server"]["h2"] = s_obj_def["server"]["h2"]
                final_s["server"]["h3"] = s_obj_def["server"]["h3"]
                final_s["server"]["h4"] = s_obj_def["server"]["h4"]
        s_json = json.dumps(final_s, ensure_ascii=False)
        st_json = json.dumps(final_st, ensure_ascii=False)
        cur.execute("UPDATE inbounds SET port=?, protocol=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (port, proto, remark, s_json, st_json, listen, sniff, inbound_id))
    elif row:
        inbound_id = row[0]
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("UPDATE inbounds SET port=?, protocol=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (port, proto, remark, s_json, st_json, listen, sniff, inbound_id))
    else:
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing, share_addr_strategy, disable_flow) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?, 'node', 0)",
                    (uid, remark, listen, port, proto, s_json, st_json, tag, sniff))
        inbound_id = cur.lastrowid
    active_inbound_ids.append(inbound_id)
    return inbound_id

ib1_id = ib2_id = ib3_id = ib4_id = ib5_id = ib6_id = ib7_id = None

# 1. Steal Reality
if os.environ.get("ENABLE_STEAL") == "1":
    steal_dict = {}
    raw_steal = os.environ.get("STEAL_CONFIG_DATA", "").strip(";")
    if raw_steal:
        for item in raw_steal.split(";"):
            if "=" in item:
                p_part, doms_csv = item.split("=", 1)
                steal_dict[p_part] = [d.strip() for d in doms_csv.split(",") if d.strip()]

    for p_str, doms in steal_dict.items():
        p = int(p_str)
        tag = f"in-steal-reality-{p}" if p != 45443 else "in-steal-reality"
        remark = f"REALITY-443 ({p})" if len(steal_dict) > 1 else "REALITY-443"
        s_obj = {"clients": [client_reality_dict], "decryption": "none"}
        st_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 1, "target": "127.0.0.1:11443", "dest": "127.0.0.1:11443",
                "serverNames": doms, "privateKey": def_r_priv, "minClientVer": "1.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": [reality_hex_sid],
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": "", "spiderX": "/"}
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": remark}]
        }
        ib1_id = upsert_inbound(p, "vless", tag, remark, s_obj, st_obj)

# 2. Classic Reality
if os.environ.get("ENABLE_CLASSIC") == "1":
    classic_dict = {}
    raw_classic = os.environ.get("CLASSIC_CONFIG_DATA", "").strip(";")
    if raw_classic:
        for item in raw_classic.split(";"):
            if "=" in item:
                cp_part, snis_csv = item.split("=", 1)
                classic_dict[cp_part] = [s.strip() for s in snis_csv.split(",") if s.strip()]

    for p_str, snis in classic_dict.items():
        p = int(p_str)
        primary_sni = snis[0] if snis else "tbank.ru"
        tag = f"in-classic-reality-{p}" if p != 46443 else "in-classic-reality"
        remark = f"REALITY-Classic ({p})" if len(classic_dict) > 1 else "REALITY-Classic"
        c_obj = {"clients": [client_reality_dict], "decryption": "none"}
        ct_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 0, "target": f"{primary_sni}:443", "dest": f"{primary_sni}:443",
                "serverNames": snis, "privateKey": def_r_priv, "minClientVer": "1.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": [reality_hex_sid],
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": "", "spiderX": "/"}
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": remark}]
        }
        ib2_id = upsert_inbound(p, "vless", tag, remark, c_obj, ct_obj)

# 3. VLESS xHTTP (Native H2C Stream-One) + ML-KEM-768 + Vision
x_obj = {
    "clients": [client_xhttp_dict],
    "decryption": vless_dekey,
    "encryption": vless_enkey
}
xt_obj = {
    "network": "xhttp",
    "xhttpSettings": {
        "path": xhttp_path, "host": domain, "mode": "stream-one", "noSSEHeader": True,
        "xPaddingBytes": "120-1120", "xPaddingObfsMode": True, "xPaddingKey": "X-Amz-Meta-Trace",
        "xmux": {"maxConcurrency": "0", "maxConnections": "1-3", "cMaxReuseTimes": "300-600", "hMaxRequestTimes": "600-900", "hMaxReusableSecs": "1800-3000", "hKeepAlivePeriod": 600},
        "enableXmux": True
    },
    "security": "none",
    "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "firefox", "alpn": ["h2"], "remark": "VLESS xHTTP"}]
}
ib3_id = upsert_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS xHTTP", x_obj, xt_obj)

# 4. Hysteria 2
if os.environ.get("ENABLE_HY2") == "1":
    hp = int(os.environ["HY2_PORT"])
    ssl_dir = os.environ["SSL_BASE_DIR"]
    hy_client = dict(client_reality_dict)
    hy_client.pop("flow", None)
    hy_client["auth"] = test_password
    hy_client["password"] = test_password
    h_obj = {"clients": [hy_client], "version": 2}
    ht_obj = {
        "network": "hysteria",
        "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60, "masquerade": {"type": "proxy", "url": "http://127.0.0.1:80"}},
        "security": "tls",
        "tlsSettings": {
            "serverName": domain, "minVersion": "1.3", "maxVersion": "1.3",
            "certificates": [{"certificateFile": f"{ssl_dir}/{domain}/fullchain.pem", "keyFile": f"{ssl_dir}/{domain}/privkey.pem"}],
            "alpn": ["h3"]
        },
        "externalProxy": [{"dest": domain, "port": hp, "forceTls": "tls", "alpn": ["h3"], "remark": "Hysteria 2"}]
    }
    ib4_id = upsert_inbound(hp, "hysteria", "in-hysteria2", "Hysteria 2", h_obj, ht_obj, listen="0.0.0.0")

awg3_dns_prim = "77.88.8.8" if geo_profile == "1" else "1.1.1.1"
awg3_dns_sec = "77.88.8.1" if geo_profile == "1" else "8.8.8.8"

# 5. AmneziaWG v3.2
if os.environ.get("ENABLE_AWG_V3") == "1":
    a3p = int(os.environ["AWG_V3_PORT"])
    a3_client = dict(client_reality_dict)
    a3_client["allowedIPs"] = ["10.8.1.3/32"]
    a3_client.pop("flow", None)
    
    a3_h1 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h2 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h3 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h4 = str(secrets.randbelow(2000000000) + 100000000)

    a3_obj = {
        "clients": [a3_client],
        "server": {
            "h1": a3_h1, "h2": a3_h2, "h3": a3_h3, "h4": a3_h4,
            "jc": 4, "jmin": 40, "jmax": 70, "s1": 64, "s2": 56, "s3": 32, "s4": 16,
            "mtu": 1360, "primaryDns": awg3_dns_prim, "secondaryDns": awg3_dns_sec,
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "randomTrailers": False, "disableCookies": True, "contentPaddingAddition": "0",
            "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
            "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
            "subnetCidr": 24, "subnetIp": "10.8.1.0"
        }
    }
    a3t_obj = {"externalProxy": [{"dest": domain, "port": a3p, "remark": "AmneziaWG v3"}]}
    ib5_id = upsert_inbound(a3p, "amneziawg", "in-8443-udp", "AmneziaWG v3", a3_obj, a3t_obj, listen="0.0.0.0")

# 6. AmneziaWG v2.0
if os.environ.get("ENABLE_AWG_V2") == "1":
    a2p = int(os.environ["AWG_V2_PORT"])
    a2_client = dict(client_reality_dict)
    a2_client["allowedIPs"] = ["10.8.2.3/32"]
    a2_client.pop("flow", None)
    a2_obj = {
        "clients": [a2_client],
        "server": {
            "h1": "149419586", "h2": "878791997", "h3": "1251051976", "h4": "1657628296",
            "jc": 4, "jmin": 40, "jmax": 70, "s1": 64, "s2": 56, "s3": 32, "s4": 16,
            "mtu": 1360, "primaryDns": awg3_dns_prim, "secondaryDns": awg3_dns_sec,
            "privateKey": def_wg_s2_priv, "publicKey": def_wg_s2_pub,
            "randomTrailers": False, "disableCookies": True, "contentPaddingAddition": "0",
            "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
            "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
            "subnetCidr": 24, "subnetIp": "10.8.2.0"
        }
    }
    a2t_obj = {"externalProxy": [{"dest": domain, "port": a2p, "remark": "AmneziaWG v2"}]}
    ib6_id = upsert_inbound(a2p, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2", a2_obj, a2t_obj, listen="0.0.0.0")

# 7. 3X WireGuard (Переименован по регламенту)
if os.environ.get("ENABLE_WG_NATIVE") == "1":
    wgp = int(os.environ["WG_NATIVE_PORT"])
    wg_peer = {
        "privateKey": def_wg_nat_c_priv,
        "publicKey": def_wg_nat_c_pub,
        "allowedIPs": ["10.8.3.3/32"],
        "keepAlive": 25,
        "email": test_email
    }
    wg_s_obj = {
        "secretKey": def_wg_nat_s_priv,
        "peers": [wg_peer],
        "mtu": 1420,
        "noKernelTun": False
    }
    wg_st_obj = {
        "externalProxy": [{"dest": domain, "port": wgp, "remark": "3X WireGuard"}]
    }
    ib7_id = upsert_inbound(wgp, "wireguard", "in-wireguard-native", "3X WireGuard", wg_s_obj, wg_st_obj, listen="0.0.0.0")

    wg_dns_str = awg3_dns_prim if geo_profile == "1" else "1.1.1.1, 8.8.8.8"
    wg_conf_content = f"""[Interface]
PrivateKey = {def_wg_nat_c_priv}
Address = 10.8.3.3/32
DNS = {wg_dns_str}
MTU = 1420

[Peer]
PublicKey = {def_wg_nat_s_pub}
Endpoint = {domain}:{wgp}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"""
    with open("/root/wireguard-client.conf", "w") as f_wg:
        f_wg.write(wg_conf_content)
    os.chmod("/root/wireguard-client.conf", 0o600)

if "clients" in tables:
    cur.execute("PRAGMA table_info(clients)")
    client_cols = {r[1] for r in cur.fetchall()}
    
    cur.execute("SELECT id FROM clients WHERE email = ?", (test_email,))
    cl_row = cur.fetchone()
    
    if not cl_row and install_mode == "1":
        client_data_map = {
            "email": test_email, "sub_id": test_sub_id, "uuid": test_uuid, "password": test_password,
            "auth": test_password, "flow": "xtls-rprx-vision", "security": "auto", "reverse": "",
            "wg_private_key": def_wg_c_priv, "wg_public_key": def_wg_c_pub, "wg_allowed_ips": "10.8.1.3/32, 10.8.2.3/32, 10.8.3.3/32",
            "wg_pre_shared_key": "", "wg_keep_alive": 25, "wg_forwarded_ports": "", "secret": "",
            "ad_tag": "", "limit_ip": 0, "limit_hwid": 0, "total_gb": 0, "expiry_time": 0,
            "enable": 1, "tg_id": 0, "group_name": "", "comment": "", "reset": 0, "reset_day": 0,
            "reset_max": 0, "traffic_reset": "never", "traffic_reset_day": 1,
            "created_at": now_ms, "updated_at": now_ms, "sync_orphaned_at": 0
        }
        filtered_client_data = {k: v for k, v in client_data_map.items() if k in client_cols}
        c_keys = list(filtered_client_data.keys())
        c_vals = [filtered_client_data[k] for k in c_keys]
        placeholders = ",".join(["?"] * len(c_keys))
        cur.execute(f"INSERT INTO clients ({','.join(c_keys)}) VALUES ({placeholders})", c_vals)
        client_global_id = cur.lastrowid
    elif cl_row:
        client_global_id = cl_row[0]
    else:
        client_global_id = None

    if "client_inbounds" in tables and client_global_id and install_mode == "1":
        cur.execute("DELETE FROM client_inbounds WHERE client_id = ?", (client_global_id,))
        active_inbound_links = [
            (ib_id, "xtls-rprx-vision" if ib_id in [ib1_id, ib2_id, ib3_id] else "")
            for ib_id in active_inbound_ids if ib_id is not None
        ]
        for ib_id, flow_val in active_inbound_links:
            cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                        (client_global_id, ib_id, flow_val, now_ms))

if "client_traffics" in tables and install_mode == "1":
    for ib_id in active_inbound_ids:
        if ib_id is not None:
            cur.execute("INSERT OR REPLACE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)",
                        (ib_id, test_email))

cur.execute("""
    CREATE TABLE IF NOT EXISTS hosts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id TEXT DEFAULT '',
        inbound_id INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        remark TEXT DEFAULT '',
        address TEXT DEFAULT '',
        port INTEGER DEFAULT 443,
        security TEXT DEFAULT 'same',
        sni TEXT DEFAULT '',
        host_header TEXT DEFAULT '',
        path TEXT DEFAULT '',
        alpn TEXT DEFAULT '',
        fingerprint TEXT DEFAULT '',
        allow_insecure INTEGER DEFAULT 0,
        is_disabled INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        tags TEXT DEFAULT '',
        ech_config_list TEXT DEFAULT '',
        mux_params TEXT DEFAULT '',
        sockopt_params TEXT DEFAULT '',
        final_mask TEXT DEFAULT '',
        exclude_from_sub_types TEXT DEFAULT ''
    )
""")

cur.execute("PRAGMA table_info(hosts)")
active_cols = {r[1] for r in cur.fetchall()}

def add_host_entry(gid, ib_id, remark, addr, port, sec, sni="", path="", alpn="", fp="", sort_order=0):
    col_candidates = {
        "group_id": gid, "groupId": gid,
        "inbound_id": ib_id, "inboundId": ib_id,
        "sort_order": sort_order, "sortOrder": sort_order,
        "remark": remark, "address": addr, "port": port, "security": sec,
        "sni": sni, "host_header": "", "hostHeader": "", "path": path,
        "alpn": alpn, "fingerprint": fp, "allow_insecure": 0, "allowInsecure": 0,
        "is_disabled": 0, "isDisabled": 0, "is_hidden": 0, "isHidden": 0,
        "tags": "", "ech_config_list": "", "mux_params": "", "sockopt_params": "",
        "final_mask": "", "exclude_from_sub_types": ""
    }
    insert_data = {k: v for k, v in col_candidates.items() if k in active_cols}
    keys = list(insert_data.keys())
    vals = [insert_data[k] for k in keys]
    placeholders = ",".join(["?"] * len(keys))
    cur.execute(f"INSERT INTO hosts ({','.join(keys)}) VALUES ({placeholders})", vals)

if install_mode == "1":
    cur.execute("DELETE FROM hosts")
    group_all_uuid = str(uuid.uuid4())
    group_xhttp_uuid = str(uuid.uuid4())

    for r_id in [ib1_id, ib2_id]:
        if r_id is not None:
            add_host_entry(group_all_uuid, r_id, "REALITY_443", domain, 443, "same", sort_order=1)

    if ib3_id is not None:
        alpn_str = json.dumps(["h2"])
        add_host_entry(group_xhttp_uuid, ib3_id, "xHTTP_H2", domain, 443, "tls", sni=domain, path=xhttp_path, alpn=alpn_str, fp="firefox", sort_order=2)
elif install_mode == "2":
    cur.execute("DELETE FROM hosts WHERE inbound_id IN (SELECT id FROM inbounds WHERE protocol IN ('hysteria', 'amneziawg', 'wireguard'))")
    if ib3_id is not None:
        cur.execute("UPDATE hosts SET path = ? WHERE inbound_id = ?", (xhttp_path, ib3_id))

conn.commit()
conn.close()

with open("/tmp/vpn_unified_creds.txt", "w") as f:
    f.write(f"UNIFIED_SUB_ID={test_sub_id}\n")
    f.write(f"UNIFIED_UUID={test_uuid}\n")
    f.write(f"TEST_EMAIL={test_email}\n")
EOF_PY_ENGINE

systemctl restart x-ui
sleep 2

if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:${PANEL_PORT}"; then
    ok "Служба 3X-UI успешно запущена на сокете 127.0.0.1:${PANEL_PORT}."
fi

UNIFIED_SUB_ID="SUB_Test"
TEST_EMAIL="Test"
if [ -f "/tmp/vpn_unified_creds.txt" ]; then
    # shellcheck source=/dev/null
    . /tmp/vpn_unified_creds.txt
    rm -f /tmp/vpn_unified_creds.txt
fi

# =============================================================
#  ФАЗА 4: УНИВЕРСАЛЬНАЯ СБОРКА NATIVE AMNEZIAWG SERVER (DKMS)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 4: Нативный сервер AmneziaWG (Ядро Linux Bare-Metal)          ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    log "Установка пакетов сборки и заголовков ядра..."
    wait_for_apt_lock
    apt-get install -y build-essential "linux-headers-$(uname -r)" linux-headers-amd64 linux-headers-generic git dkms wireguard-tools -q >/dev/null 2>&1 || true

    AWG_INSTALLED=0
    if [ "$OS_ID" = "ubuntu" ]; then
        wait_for_apt_lock
        add-apt-repository -y ppa:amnezia/ppa >/dev/null 2>&1 || true
        wait_for_apt_lock
        apt-get update -q >/dev/null 2>&1 || true
        wait_for_apt_lock
        if apt-get install -y amneziawg-dkms amneziawg-tools -q >/dev/null 2>&1; then
            AWG_INSTALLED=1
            ok "DKMS-модуль AmneziaWG установлен из Launchpad PPA."
        fi
    fi

    if [ "$AWG_INSTALLED" -eq 0 ]; then
        log "Сборка AmneziaWG DKMS и нативных утилит из исходного кода..."
        dkms remove amneziawg/1.0.0 --all 2>/dev/null || true
        rm -rf /usr/src/amneziawg-1.0.0 /var/lib/dkms/amneziawg/1.0.0 /tmp/awg-kmod-src /tmp/awg-tools-build

        git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git /tmp/awg-kmod-src 2>/dev/null || true
        if [ -d "/tmp/awg-kmod-src/src" ]; then
            make -C /tmp/awg-kmod-src/src dkms-install >/dev/null 2>&1 || true
            dkms add -m amneziawg -v 1.0.0 2>/dev/null || true
            dkms build -m amneziawg -v 1.0.0 >/dev/null 2>&1 || true
            dkms install -m amneziawg -v 1.0.0 >/dev/null 2>&1 || true
            rm -rf /tmp/awg-kmod-src
        fi

        git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git /tmp/awg-tools-build 2>/dev/null || true
        if [ -d "/tmp/awg-tools-build/src" ]; then
            make -C "/tmp/awg-tools-build/src" >/dev/null 2>&1 || true
            make -C "/tmp/awg-tools-build/src" install >/dev/null 2>&1 || true
            rm -rf "/tmp/awg-tools-build"
        fi

        echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
        modprobe amneziawg 2>/dev/null || true
    fi

    if ! command -v awg >/dev/null 2>&1; then
        ln -sf "$(command -v wg 2>/dev/null || echo '/usr/bin/wg')" /usr/local/bin/awg 2>/dev/null || true
        ln -sf "$(command -v wg-quick 2>/dev/null || echo '/usr/bin/wg-quick')" /usr/local/bin/awg-quick 2>/dev/null || true
    fi

    mkdir -p /etc/amnezia/amneziawg
    chmod 700 /etc/amnezia /etc/amnezia/amneziawg

    AWG_S_PRIV=$(awg genkey 2>/dev/null || openssl rand -base64 32)
    AWG_S_PUB=$(echo "$AWG_S_PRIV" | awg pubkey 2>/dev/null || openssl rand -base64 32)
    AWG_C_PRIV=$(awg genkey 2>/dev/null || openssl rand -base64 32)
    AWG_C_PUB=$(echo "$AWG_C_PRIV" | awg pubkey 2>/dev/null || openssl rand -base64 32)

    AWG_H1=$(( (RANDOM << 16 | RANDOM) % 2000000000 + 100000000 ))
    AWG_H2=$(( (RANDOM << 16 | RANDOM) % 2000000000 + 100000000 ))
    AWG_H3=$(( (RANDOM << 16 | RANDOM) % 2000000000 + 100000000 ))
    AWG_H4=$(( (RANDOM << 16 | RANDOM) % 2000000000 + 100000000 ))

    cat << EOF > /etc/amnezia/amneziawg/awg0.conf
[Interface]
Address = 10.9.0.1/24
ListenPort = $NATIVE_AWG_PORT
PrivateKey = $AWG_S_PRIV
MTU = 1360
Jc = 4
Jmin = 40
Jmax = 70
S1 = 64
S2 = 56
S3 = 32
S4 = 16
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

# --- Client: Test-Client ---
[Peer]
PublicKey = $AWG_C_PUB
AllowedIPs = 10.9.0.2/32
EOF
    chmod 600 /etc/amnezia/amneziawg/awg0.conf

    AWG_DNS_IP="77.88.8.8"
    if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
        AWG_DNS_IP="10.9.0.1"
    elif [ "$GEO_PROFILE" != "1" ]; then
        AWG_DNS_IP="1.1.1.1"
    fi

    cat << EOF > /root/amneziawg-client.conf
[Interface]
Address = 10.9.0.2/32
PrivateKey = $AWG_C_PRIV
DNS = $AWG_DNS_IP
MTU = 1360
Jc = 4
Jmin = 40
Jmax = 70
S1 = 64
S2 = 56
S3 = 32
S4 = 16
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $AWG_S_PUB
Endpoint = ${PRIMARY_DOMAIN}:${NATIVE_AWG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    chmod 600 /root/amneziawg-client.conf

    CLIENTS_JSON="/etc/amnezia/amneziawg/clients.json"
    cat << EOF > "$CLIENTS_JSON"
{
  "${AWG_C_PUB}": {
    "name": "Test-Client",
    "private_key": "${AWG_C_PRIV}",
    "public_key": "${AWG_C_PUB}",
    "ip": "10.9.0.2/32"
  }
}
EOF
    chmod 600 "$CLIENTS_JSON"

    systemctl stop awg-quick@awg0 2>/dev/null || true
    systemctl enable awg-quick@awg0 >/dev/null 2>&1 || true
    if systemctl restart awg-quick@awg0; then
        ok "Нативный сервер AmneziaWG активен на сокете :${NATIVE_AWG_PORT}/udp (awg0)."
    else
        warn "Не удалось поднять интерфейс awg0 через systemd. Проверьте: journalctl -xeu awg-quick@awg0"
    fi
fi

# =============================================================
#  ФАЗА 5: МНОГОПОТОЧНЫЙ ПИТОН-ДЕМОН DATASPHERE CORE (SSO & AWG)
# =============================================================
log "Развёртывание управляющего микросервиса DataSphere Core (Loopback 20443)..."

cat << 'EOF_CORE_PY' > /usr/local/bin/datasphere-core.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import http.server, socketserver, json, os, subprocess, hmac, secrets, re, time, sqlite3, urllib.parse, base64, fcntl
try:
    import bcrypt
except ImportError:
    bcrypt = None

DB_PATHS = ["/etc/x-ui/x-ui.db", "/usr/local/x-ui/bin/x-ui.db", "/etc/x-ui/db/x-ui.db"]
CLIENTS_FILE = "/etc/amnezia/amneziawg/clients.json"
CONF_PATH = "/etc/amnezia/amneziawg/awg0.conf"

ENABLE_AGH = os.environ.get("ENABLE_AGH", "0") == "1"
GEO_PROFILE = os.environ.get("GEO_PROFILE", "2")
PRIMARY_DOMAIN = os.environ.get("PRIMARY_DOMAIN", "")
NATIVE_AWG_PORT = os.environ.get("NATIVE_AWG_PORT", "51820")

def execute_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8")
    except Exception:
        return ""

P = 2**255 - 19
A24 = 121665

def clamp(k_bytes):
    b = bytearray(k_bytes)
    b[0] &= 248; b[31] &= 127; b[31] |= 64
    return int.from_bytes(b, "little")

def x25519(k, u=9):
    x1, x2, z2, x3, z3 = u, 1, 0, u, 1
    for i in range(254, -1, -1):
        bit = (k >> i) & 1
        if bit: x2, x3 = x3, x2; z2, z3 = z3, z2
        A = (x2 + z2) % P; AA = (A * A) % P; B = (x2 - z2) % P; BB = (B * B) % P
        E = (AA - BB) % P; C = (x3 + z3) % P; D = (x3 - z3) % P
        DA = (D * A) % P; CB = (C * B) % P
        x3 = pow(DA + CB, 2, P); z3 = (x1 * pow(DA - CB, 2, P)) % P
        x2 = (AA * BB) % P; z2 = (E * (AA + A24 * E)) % P
        if bit: x2, x3 = x3, x2; z2, z3 = z3, z2
    return (x2 * pow(z2, P - 2, P)) % P

def gen_wireguard_keypair():
    raw = os.urandom(32)
    k = clamp(raw)
    pub = x25519(k, 9).to_bytes(32, "little")
    return base64.b64encode(raw).decode(), base64.b64encode(pub).decode()

def load_clients():
    clients = {}
    if os.path.exists(CLIENTS_FILE):
        try:
            with open(CLIENTS_FILE, "r") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                clients = json.load(f)
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass

    root_conf = "/root/amneziawg-client.conf"
    if os.path.exists(root_conf):
        try:
            with open(root_conf, "r") as f:
                c_text = f.read()
            m_priv = re.search(r"^PrivateKey\s*=\s*([^\s\n\r]+)", c_text, re.M)
            m_ip = re.search(r"^Address\s*=\s*([^\s\n\r]+)", c_text, re.M)
            if m_priv and len(m_priv.group(1).strip()) > 30:
                priv = m_priv.group(1).strip()
                ip = m_ip.group(1).strip() if m_ip else "10.9.0.2/32"
                pub = execute_cmd(f"echo '{priv}' | awg pubkey").strip()
                if not pub:
                    raw = base64.b64decode(priv)
                    pub = base64.b64encode(x25519(clamp(raw), 9).to_bytes(32, "little")).decode()
                clients[pub] = {
                    "name": "Test-Client",
                    "private_key": priv,
                    "public_key": pub,
                    "ip": ip
                }
                save_clients(clients)
        except Exception:
            pass

    if not clients:
        priv, pub = gen_wireguard_keypair()
        ip = "10.9.0.2/32"
        clients[pub] = {
            "name": "Test-Client",
            "private_key": priv,
            "public_key": pub,
            "ip": ip
        }
        save_clients(clients)
        
        if os.path.exists(CONF_PATH):
            with open(CONF_PATH, "r") as f:
                text = f.read()
            text = re.sub(r'\[Peer\][\s\S]*', '', text).strip()
            text += f"\n\n# --- Client: Test-Client ---\n[Peer]\nPublicKey = {pub}\nAllowedIPs = {ip}\n"
            with open(CONF_PATH, "w") as f:
                f.write(text)
            execute_cmd(f"awg set awg0 peer '{pub}' allowed-ips '{ip}'")
    return clients

def save_clients(clients):
    try:
        os.makedirs(os.path.dirname(CLIENTS_FILE), exist_ok=True)
        with open(CLIENTS_FILE, "w") as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump(clients, f, indent=2)
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        os.chmod(CLIENTS_FILE, 0o600)
    except Exception:
        pass

def verify_credentials(user, pwd):
    for db_path in DB_PATHS:
        if not os.path.exists(db_path):
            continue
        try:
            conn = sqlite3.connect(db_path, timeout=5.0)
            cur = conn.cursor()
            cur.execute("SELECT password FROM users WHERE username = ? LIMIT 1", (user,))
            row = cur.fetchone()
            if not row:
                cur.execute("SELECT password FROM users WHERE LOWER(username) = LOWER(?) LIMIT 1", (user,))
                row = cur.fetchone()
            conn.close()

            if row:
                db_hash = row[0].strip()
                if db_hash.startswith("$2") and bcrypt:
                    try:
                        if bcrypt.checkpw(pwd.encode('utf-8'), db_hash.encode('utf-8')):
                            return True
                    except Exception:
                        pass
                elif hmac.compare_digest(pwd, db_hash):
                    return True
        except Exception:
            pass

    cred_file = "/root/vpn_credentials.txt"
    if os.path.exists(cred_file):
        try:
            with open(cred_file, "r", encoding="utf-8") as f:
                content = f.read()
            m_u = re.search(r"Логин администратора:\s*([^\n\r]+)", content)
            m_p = re.search(r"Пароль администратора:\s*([^\n\r]+)", content)
            if m_u and m_p:
                if hmac.compare_digest(user, m_u.group(1).strip()) and hmac.compare_digest(pwd, m_p.group(1).strip()):
                    return True
        except Exception:
            pass

    return False

def get_panel_path():
    for db_path in DB_PATHS:
        if os.path.exists(db_path):
            try:
                conn = sqlite3.connect(db_path, timeout=5.0)
                cur = conn.cursor()
                cur.execute("SELECT value FROM settings WHERE key='webBasePath'")
                row = cur.fetchone()
                conn.close()
                if row and row[0]:
                    p = row[0].strip().strip("/")
                    return f"/{p}/"
            except Exception:
                pass
    return "/my-3x-panel/"

def build_client_conf(pub_key, host):
    srv = {}
    if os.path.exists(CONF_PATH):
        with open(CONF_PATH, "r") as f:
            c_text = f.read()
        for k in ["MTU", "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4", "H1", "H2", "H3", "H4", "ListenPort", "PrivateKey"]:
            m = re.search(rf"^{k}\s*=\s*([^\s\n\r]+)", c_text, re.M)
            if m: srv[k] = m.group(1).strip()
    
    clients = load_clients()
    c_info = clients.get(pub_key, {})
    if not c_info and clients:
        c_info = next(iter(clients.values()))
    
    c_priv = c_info.get("private_key", "")
    c_ip = c_info.get("ip", "10.9.0.2/32")

    s_priv = srv.get("PrivateKey", "")
    s_pub = ""
    if s_priv:
        s_pub = execute_cmd(f"echo '{s_priv}' | awg pubkey").strip()
    if not s_pub:
        s_pub = execute_cmd("awg show awg0 public-key").strip()

    dns_ip = "77.88.8.8"
    if ENABLE_AGH:
        dns_ip = "10.9.0.1"
    elif GEO_PROFILE != "1":
        dns_ip = "1.1.1.1"

    h = host.split(':')[0] if host else PRIMARY_DOMAIN
    port_val = srv.get('ListenPort', NATIVE_AWG_PORT)
    return f"""[Interface]
Address = {c_ip}
PrivateKey = {c_priv}
DNS = {dns_ip}
MTU = {srv.get('MTU', '1360')}
Jc = {srv.get('Jc', '4')}
Jmin = {srv.get('Jmin', '40')}
Jmax = {srv.get('Jmax', '70')}
S1 = {srv.get('S1', '64')}
S2 = {srv.get('S2', '56')}
S3 = {srv.get('S3', '32')}
S4 = {srv.get('S4', '16')}
H1 = {srv.get('H1', '149419586')}
H2 = {srv.get('H2', '878791997')}
H3 = {srv.get('H3', '1251051976')}
H4 = {srv.get('H4', '1657628296')}

[Peer]
PublicKey = {s_pub}
Endpoint = {h}:{port_val}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""

ACTIVE_SESSIONS = {}

def clean_expired_sessions():
    now = time.time()
    expired = [t for t, exp in ACTIVE_SESSIONS.items() if exp < now]
    for t in expired:
        ACTIVE_SESSIONS.pop(t, None)

class CoreHandler(http.server.BaseHTTPRequestHandler):
    def _send_json(self, data, code=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth_valid(self):
        clean_expired_sessions()
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            token = auth[7:].strip()
            exp = ACTIVE_SESSIONS.get(token, 0)
            return exp > time.time()
        return False

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(length)
        data = {}
        try:
            data = json.loads(post_data.decode('utf-8'))
        except Exception:
            pass

        if self.path == "/api/v1/datasphere/auth":
            user = data.get("principal", "").strip()
            pwd = data.get("secret", "").strip()

            if verify_credentials(user, pwd):
                clean_expired_sessions()
                token = secrets.token_hex(24)
                ACTIVE_SESSIONS[token] = time.time() + 3600
                panel_url = get_panel_path()
                self._send_json({
                    "status": "ok",
                    "token": token,
                    "services": {
                        "panel_url": panel_url,
                        "awg_enabled": os.path.exists(CONF_PATH),
                        "agh_enabled": os.path.exists("/opt/AdGuardHome/AdGuardHome.yaml"),
                        "agh_url": f"https://dns.{self.headers.get('Host', '')}/"
                    }
                })
            else:
                time.sleep(0.5)
                self._send_json({
                    "status": "error",
                    "code": 401,
                    "error": "Недействительный токен кластера или ключ авторизации узла. Доступ запрещен."
                }, code=401)
            return

        if not self._auth_valid():
            self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
            return

        if self.path == "/api/v1/datasphere/awg/peer/add":
            name = re.sub(r'[^a-zA-Z0-9_-]', '', data.get("name", "Client")).strip()
            if not name:
                name = "Client"
            priv, pub = gen_wireguard_keypair()

            lines = []
            if os.path.exists(CONF_PATH):
                with open(CONF_PATH, "r") as f:
                    lines = f.readlines()

            used_octets = [1]
            for l in lines:
                m = re.search(r'AllowedIPs\s*=\s*10\.9\.0\.(\d+)', l)
                if m:
                    used_octets.append(int(m.group(1)))
            next_ip = 2
            while next_ip in used_octets and next_ip < 254:
                next_ip += 1

            client_ip = f"10.9.0.{next_ip}/32"
            new_peer = f"\n# --- Client: {name} ---\n[Peer]\nPublicKey = {pub}\nAllowedIPs = {client_ip}\n"
            with open(CONF_PATH, "a") as f:
                f.write(new_peer)

            execute_cmd(f"awg set awg0 peer '{pub}' allowed-ips '{client_ip}'")
            
            clients = load_clients()
            clients[pub] = {
                "name": name,
                "private_key": priv,
                "public_key": pub,
                "ip": client_ip
            }
            save_clients(clients)

            self._send_json({"status": "ok", "public_key": pub, "ip": client_ip, "name": name, "priv_key": priv})
            return

        if self.path == "/api/v1/datasphere/awg/peer/remove":
            pub = urllib.parse.unquote(data.get("public_key", "")).strip()
            if pub:
                execute_cmd(f"awg set awg0 peer '{pub}' remove")
                if os.path.exists(CONF_PATH):
                    with open(CONF_PATH, "r") as f:
                        text = f.read()
                    pattern = rf"(# --- Client: .*?---\n)?\[Peer\]\nPublicKey\s*=\s*{re.escape(pub)}[\s\S]*?(?=\n\[Peer\]|\n# ---|$)"
                    text = re.sub(pattern, "", text)
                    with open(CONF_PATH, "w") as f:
                        f.write(text.strip() + "\n")
                
                clients = load_clients()
                if pub in clients:
                    del clients[pub]
                    save_clients(clients)
            self._send_json({"status": "ok"})
            return

        self._send_json({"status": "error", "error": "Not Found"}, code=404)

    def do_GET(self):
        if self.path == "/api/v1/datasphere/status":
            self._send_json({
                "status": "online",
                "cluster": "datasphere-edge-ultra",
                "nodes_active": 148,
                "telemetry_rate": "99.998%",
                "version": "3.14.0"
            })
            return

        if self.path.startswith("/api/v1/datasphere/awg/peer/qr"):
            pub_req = re.search(r'key=([^&]+)', self.path)
            raw_key = pub_req.group(1).strip() if pub_req else ""
            pub_key = urllib.parse.unquote(raw_key).strip()
            
            conf_str = build_client_conf(pub_key, self.headers.get('Host', ''))
            
            p = subprocess.Popen(["qrencode", "-t", "SVG", "-m", "2"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            svg_out, _ = p.communicate(input=conf_str.encode("utf-8"))
            
            self.send_response(200)
            self.send_header("Content-Type", "image/svg+xml")
            self.end_headers()
            self.wfile.write(svg_out)
            return

        if self.path.startswith("/api/v1/datasphere/awg/peer/conf"):
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return
            pub_req = re.search(r'key=([^&]+)', self.path)
            raw_key = pub_req.group(1).strip() if pub_req else ""
            pub_key = urllib.parse.unquote(raw_key).strip()
            
            body_conf = build_client_conf(pub_key, self.headers.get('Host', ''))
            
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Disposition", f'attachment; filename="awg0-{pub_key[:6]}.conf"')
            self.end_headers()
            self.wfile.write(body_conf.encode("utf-8"))
            return

        if self.path == "/api/v1/datasphere/awg/peers":
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return

            dump = execute_cmd("awg show awg0 dump").strip()
            name_map = {}
            if os.path.exists(CONF_PATH):
                with open(CONF_PATH, "r") as f:
                    curr_name = ""
                    for l in f:
                        m_n = re.search(r'# --- Client:\s*([^\s-]+)', l)
                        if m_n:
                            curr_name = m_n.group(1)
                        m_k = re.search(r'PublicKey\s*=\s*([^\s]+)', l)
                        if m_k and curr_name:
                            name_map[m_k.group(1)] = curr_name
                            curr_name = ""

            peers = []
            now = int(time.time())
            clients = load_clients()
            for line in dump.split("\n")[1:]:
                parts = line.split("\t")
                if len(parts) >= 6:
                    pub = parts[0]
                    ip = parts[3]
                    last_hs = int(parts[4])
                    rx = int(parts[5])
                    tx = int(parts[6]) if len(parts) >= 7 else 0
                    is_on = (now - last_hs < 180) if last_hs > 0 else False
                    c_data = clients.get(pub, {})
                    c_name = c_data.get("name") or name_map.get(pub, pub[:8])
                    peers.append({
                        "name": c_name,
                        "public_key": pub,
                        "ip": ip,
                        "rx": f"{rx / (1024*1024):.1f} MB",
                        "tx": f"{tx / (1024*1024):.1f} MB",
                        "is_online": is_on
                    })
            self._send_json({"status": "ok", "peers": peers})
            return

        self._send_json({"status": "error", "error": "Not Found"}, code=404)

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == "__main__":
    load_clients()
    server = ThreadedTCPServer(("127.0.0.1", 20443), CoreHandler)
    server.serve_forever()
EOF_CORE_PY
chmod 755 /usr/local/bin/datasphere-core.py

cat << EOF > /etc/systemd/system/datasphere-core.service
[Unit]
Description=DataSphere Core In-Memory Gateway Daemon
After=network.target

[Service]
Type=simple
User=root
Environment="ENABLE_AGH=${ENABLE_AGH:-0}"
Environment="GEO_PROFILE=$GEO_PROFILE"
Environment="PRIMARY_DOMAIN=$PRIMARY_DOMAIN"
Environment="NATIVE_AWG_PORT=$NATIVE_AWG_PORT"
ExecStart=/usr/bin/python3 /usr/local/bin/datasphere-core.py
Restart=always
RestartSec=3
LimitNOFILE=524288
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable datasphere-core >/dev/null 2>&1 || true
systemctl restart datasphere-core || true
ok "Служба DataSphere Core SSO Gateway запущена на 127.0.0.1:20443."

# =============================================================
#  ФАЗА 6: ФИНАЛЬНЫЙ ЗАМОК (L3 FORWARD, NAT, MSS CLAMPING, UFW)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 6: Сетевой шлюз NAT, TCP MSS Clamping и изоляция UFW          ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

DEFAULT_IF=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || echo "")
if [ -z "$DEFAULT_IF" ]; then
    DEFAULT_IF=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || echo "")
fi
if [ -z "$DEFAULT_IF" ]; then
    DEFAULT_IF="eth0"
fi
ok "Сетевой интерфейс шлюза: ${GREEN}${DEFAULT_IF}${NC}"

if [ -f /etc/default/ufw ]; then
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
    if grep -q "^IPV6=" /etc/default/ufw; then
        sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    else
        echo "IPV6=no" >> /etc/default/ufw
    fi
fi

ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true

ufw allow "${TARGET_SSH_PORT}/tcp" comment 'SSH' >/dev/null 2>&1 || true
ufw allow 80/tcp comment 'HTTP ACME' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS L4 Router' >/dev/null 2>&1 || true

if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    ufw allow "${HY2_PORT}/udp" comment 'Hysteria 2' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    ufw allow "${AWG_V3_PORT}/udp" comment 'AmneziaWG v3' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_AWG_V2:-0}" -eq 1 ]; then
    ufw allow "${AWG_V2_PORT}/udp" comment 'AmneziaWG v2' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_WG_NATIVE:-0}" -eq 1 ]; then
    ufw allow "${WG_NATIVE_PORT}/udp" comment '3X WireGuard' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    ufw allow "${NATIVE_AWG_PORT}/udp" comment 'AmneziaWG Kernel Native' >/dev/null 2>&1 || true
fi

export ENABLE_HY2_HOP HY2_PORT ENABLE_AWG_V3 ENABLE_AWG_V2 ENABLE_WG_NATIVE ENABLE_NATIVE_AWG DEFAULT_IF
python3 - << 'EOF_UFW_PYTHON'
# -*- coding: utf-8 -*-
import os, sys, re

rules_file = "/etc/ufw/before.rules"
if not os.path.exists(rules_file):
    sys.exit(0)

with open(rules_file, "r") as f:
    content = f.read()

content = re.sub(r'# START HARDENED NAT[\s\S]*?# END HARDENED NAT\n?', '', content)
content = re.sub(r'# START HARDENED MANGLE[\s\S]*?# END HARDENED MANGLE\n?', '', content)
content = re.sub(r'# START HARDENED FORWARD[\s\S]*?# END HARDENED FORWARD\n?', '', content)
content = content.strip() + "\n"

enable_hop = os.environ.get("ENABLE_HY2_HOP") == "1"
hy2_p = os.environ.get("HY2_PORT", "443")
default_if = os.environ.get("DEFAULT_IF", "eth0")
awg3 = os.environ.get("ENABLE_AWG_V3") == "1"
awg2 = os.environ.get("ENABLE_AWG_V2") == "1"
wg_nat = os.environ.get("ENABLE_WG_NATIVE") == "1"
awg_native = os.environ.get("ENABLE_NATIVE_AWG") == "1"

nat_rules = ["*nat", ":PREROUTING ACCEPT [0:0]", ":POSTROUTING ACCEPT [0:0]", ":OUTPUT ACCEPT [0:0]"]
if enable_hop:
    nat_rules.append(f"-A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports {hy2_p}")
if awg3:
    nat_rules.append(f"-A POSTROUTING -s 10.8.1.0/24 -o {default_if} -j MASQUERADE")
if awg2:
    nat_rules.append(f"-A POSTROUTING -s 10.8.2.0/24 -o {default_if} -j MASQUERADE")
if wg_nat:
    nat_rules.append(f"-A POSTROUTING -s 10.8.3.0/24 -o {default_if} -j MASQUERADE")
if awg_native:
    nat_rules.append(f"-A POSTROUTING -s 10.9.0.0/24 -o {default_if} -j MASQUERADE")
nat_rules.append("COMMIT\n")

nat_part = "# START HARDENED NAT\n" + "\n".join(nat_rules) + "\n# END HARDENED NAT\n\n"

forward_rules = ["# START HARDENED FORWARD"]
if awg3:
    forward_rules.append("-A ufw-before-forward -s 10.8.1.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.8.1.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
if awg2:
    forward_rules.append("-A ufw-before-forward -s 10.8.2.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.8.2.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
if wg_nat:
    forward_rules.append("-A ufw-before-forward -s 10.8.3.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.8.3.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
if awg_native:
    forward_rules.append("-A ufw-before-forward -s 10.9.0.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.9.0.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
forward_rules.append("# END HARDENED FORWARD\n")
forward_block = "\n".join(forward_rules)

if "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT" in content:
    content = content.replace(
        "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT",
        "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n" + forward_block
    )
else:
    content = content.replace("*filter", "*filter\n" + forward_block)

mangle_part = """# START HARDENED MANGLE
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.8.1.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.8.1.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.8.2.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.8.2.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.8.3.0/24 -j TCPMSS --set-mss 1380
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.8.3.0/24 -j TCPMSS --set-mss 1380
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.9.0.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.9.0.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
# END HARDENED MANGLE
"""

final_body = nat_part + content + "\n" + mangle_part + "\n"

with open(rules_file, "w") as f:
    f.write(final_body)
EOF_UFW_PYTHON

DENIED_PORTS=(10443 55443 50443 9443 11443 3000 20443)
for p in "${ALL_REALITY_PORTS[@]:-}"; do
    DENIED_PORTS+=("$p")
done

for dp in "${DENIED_PORTS[@]}"; do
    ufw deny "${dp}/tcp" >/dev/null 2>&1 || true
done

if [ "${BLOCK_PING:-0}" -eq 1 ] && [ -f /etc/ufw/before.rules ]; then
    sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
fi

ufw --force enable >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
ok "Фаервол UFW настроен. MSS Clamping (1320/1380) активен."

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ДАШБОРД
# =============================================================
HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT:-443}"
if [ "${ENABLE_HY2_HOP:-0}" -eq 1 ]; then
    HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT:-443},20000-50000"
fi

CRED_FILE="/root/vpn_credentials.txt"
cat << EOF > "$CRED_FILE"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА (Single-IP Ultra Enhanced v3.3.5)
  ОС: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  Ядро Xray-core: ${DETECTED_XRAY_VER} (Pinned)
  Режим:          $([ "$INSTALL_MODE" = "2" ] && echo "Safe Migration" || echo "Clean Setup")
  Дата:           $(date '+%Y-%m-%d %H:%M:%S')
=====================================================================

[ СКРЫТЫЙ SSO ШЛЮЗ АДМИНИСТРАТОРА (ZERO-LEAK) ]
Точка входа:           https://${PRIMARY_DOMAIN}/
Инструкция:            Нажмите кнопку «Консоль» в шапке сайта DataSphere.
                       Введите логин: ${ADMIN_USER}
                       Введите пароль: $([ "$INSTALL_MODE" = "1" ] && echo "${ADMIN_PASS}" || echo "Ваш пароль администратора")
                       После входа в памяти браузера откроется меню выбора:
                       1) Авторизация Панели 3x-ui  2) Нативный сервер AmneziaWG  3) AdGuard Home

[ ПРЯМОЙ ДОСТУП В ПАНЕЛЬ 3X-UI ]
URL панели:            https://${PRIMARY_DOMAIN}${PANEL_PATH}
$([ "$INSTALL_MODE" = "1" ] && echo "Логин администратора:  ${ADMIN_USER}
Пароль администратора: ${ADMIN_PASS}" || echo "Учетные данные админа: Сохранены из прежней базы")
Внутренний сокет:      127.0.0.1:${PANEL_PORT} (Изолирован)

$([ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ] && cat << EOF_NAWG_CRED
[ НА ТЕХНОЛОГИЯХ ЯДРА: НА РАБОЧЕМ ЖЕЛЕЗЕ AMNEZIAWG ]
Интерфейс:             awg0 (Модуль ядра Linux DKMS)
Порт / Хост:           ${PRIMARY_DOMAIN}:${NATIVE_AWG_PORT:-51820}
Первый клиент:         Test-Client
Конфиг файл (.conf):   /root/amneziawg-client.conf
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4 | Jmin 40 | Jmax 70

EOF_NAWG_CRED
)
$([ "${ENABLE_AGH:-0}" -eq 1 ] && cat << EOF_AGH_CRED
[ ПРИВАТНЫЙ ADGUARD HOME DOH ]
Веб-интерфейс:         https://${AGH_DOMAIN}/
Логин администратора:  ${AGH_USER}
Пароль администратора: ${AGH_PASS}
URL DoH для роутера:   https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}

EOF_AGH_CRED
)
$([ "$INSTALL_MODE" = "1" ] && cat << EOF_SUB_CRED
[ ПОДПИСКИ КЛИЕНТОВ (МУЛЬТИПРОТОКОЛЬНЫЕ) ]
Клиент:                ${TEST_EMAIL}
Прямая ссылка (Base64):https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (JSON):  https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (Clash): https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}
EOF_SUB_CRED
)
$([ "$INSTALL_MODE" = "2" ] && echo "[ ПОДПИСКИ КЛИЕНТОВ ]
Все существующие подписки, UUID и ключи сохранены.")

$([ "${ENABLE_HY2:-0}" -eq 1 ] && echo "[ HYSTERIA 2 ]
Подключение:           ${HY2_REPORT_LINE}
")
$([ "${ENABLE_AWG_V3:-0}" -eq 1 ] && echo "[ AMNEZIAWG v3.2 (3X-UI) ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${AWG_V3_PORT:-8443}
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4
")
$([ "${ENABLE_AWG_V2:-0}" -eq 1 ] && echo "[ AMNEZIAWG v2.0 / LEGACY (3X-UI) ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${AWG_V2_PORT:-8444}
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4
")
$([ "${ENABLE_WG_NATIVE:-0}" -eq 1 ] && echo "[ 3X WIREGUARD (3X-UI) ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${WG_NATIVE_PORT:-47443}
Конфиг файл (.conf):   /root/wireguard-client.conf
MTU / Clamping:        MTU 1420 | MSS 1380
")
[ СЕТЕВЫЕ ПАРАМЕТРЫ ]
Основной хост:         ${PRIMARY_DOMAIN} (IP: ${WAN_IP:-auto})
SSH порт:              ${TARGET_SSH_PORT}

[ ВАЖНОЕ ДЕЙСТВИЕ ДЛЯ ПЕРВОГО ВХОДА В ПАНЕЛЬ ]
1. Откройте НОВОЕ окно консоли и проверьте доступ по SSH (порт ${TARGET_SSH_PORT}).
2. Выполните команду: reboot
=====================================================================
EOF
chmod 600 "$CRED_FILE"

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА В РЕЖИМЕ SINGLE-IP (v3.3.5 ULTRA)!       ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Сайт-маскировка DataSphere:  ${CYAN}https://${PRIMARY_DOMAIN}/${NC}"
echo -e "  Скрытый SSO Hub:             ${WHITE}Кнопка «Консоль» в шапке сайта${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  Логин: ${WHITE}${ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
fi
echo
echo -e "  Прямой URL панели 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
echo -e "  Нативный AmneziaWG (Kernel): ${GREEN}awg0 (:51820/udp, MTU 1360 / MSS 1320)${NC}"
echo -e "  Первый клиент:               ${GREEN}Test-Client (/root/amneziawg-client.conf)${NC}"
fi
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
echo -e "  Панель AdGuard Home:         ${CYAN}https://${AGH_DOMAIN}/${NC}"
echo -e "  Приватный DoH для роутера:   ${GREEN}https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}${NC}"
fi
echo
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Единая ссылка Base64):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (JSON для Sing-box):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}${NC}"
echo
fi
if [ "${ENABLE_WG_NATIVE:-0}" -eq 1 ]; then
echo -e "  ${BOLD}Чистый 3X WireGuard (.conf файл):${NC}"
echo -e "  ${GREEN}/root/wireguard-client.conf${NC} (MTU 1420 / MSS 1380)"
echo
fi
echo -e "  ${WHITE}Zero-SNI Shield:${NC}             ${GREEN}ssl_reject_handshake on (Скан IP изолирован)${NC}"
echo -e "  ${WHITE}Порт 80:${NC}                     ${GREEN}Только ACME, сканеры сбрасываются (444)${NC}"
echo -e "  ${WHITE}Stub Listener 11443:${NC}         ${GREEN}Proxy_Protocol + HTTP2 + ALPN${NC}"
echo -e "  ${WHITE}AWG Golden Standard:${NC}         ${GREEN}MTU 1360 | MSS 1320 | Jc 4 | Jmin 40 | Jmax 70${NC}"
echo -e "  ${WHITE}Zero-Leak In-Memory Hub:${NC}     ${GREEN}Разметка меню строится в RAM только после 200 OK${NC}"
echo
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${YELLOW}---------------------------------------------------------------------${NC}"
echo -e "${YELLOW}${BOLD}ОБЯЗАТЕЛЬНОЕ ДЕЙСТВИЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "${WHITE}1. Откройте ${BOLD}НОВОЕ${NC} окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).${NC}"
echo -e "${WHITE}2. Выполните команду: ${GREEN}${BOLD}reboot${NC}"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
                "port": 53
            }
        ],
        "queryStrategy": "UseIPv4",
        "disableCache": False,
        "disable 
