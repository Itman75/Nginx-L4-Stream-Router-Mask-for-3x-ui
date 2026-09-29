#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup Monoscript: Hardened Master Engine v3.2 (Single-IP Edition)
# OS Hardening + BBR + Nginx L4 Stream + 3X-UI + Zero-Touch (Production Release)
# Xray v26.7.28 Pinned + Native H2C xHTTP + ML-KEM-768 + XTLS Vision + AGH DoH
# Multi-Tunnel UDP Engine: Hysteria 2 + AWG v3.2 + AWG v2.0 + Native WireGuard RFC
# Full Decoy Shield v4.0 Ultra (3D Canvas Sphere + Live Telemetry + Cluster CLI)
# Pre-flight APT Sanitizer + Smoke Test ACME + Loose rp_filter + umask 022
# ==============================================================================
# Совместимость: Ubuntu 22.04 / 24.04 / 26.04 & Debian 12 / 13
# Режимы: Чистая установка (Clean Install) & Безопасное обновление (Safe Migration)
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

trap 'die "Скрипт аварийно прерван на строке $LINENO"' ERR

clear 2>/dev/null || true
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  Hardened Master Engine v3.2 Universal (Single-IP Ultra Edition)      ${NC}"
echo -e "${CYAN}  Dual-Mode: Clean Setup / Safe Migration + Nginx L4 Native + 3X-UI  ${NC}"
echo -e "${WHITE}  Xray Core v26.7.28 Pinned + Native H2C xHTTP + ML-KEM-768 + Vision  ${NC}"
echo -e "${WHITE}  UDP Stack: Hysteria 2 + AWG v3.2 + AWG v2.0 + Native WireGuard RFC ${NC}"
echo -e "${WHITE}  Decoy Shield v4.0 Ultra: 3D Geodesic Canvas + Sparklines + Web CLI ${NC}"
echo -e "${WHITE}  Поддержка: Ubuntu 22.04/24.04/26.04 & Debian 12/13                  ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

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
        MAJOR_VER=$(echo "$OS_VER_ID" | cut -d. -f1)
        if [[ "$MAJOR_VER" =~ ^[0-9]+$ ]] && [ "$MAJOR_VER" -ge 22 ]; then
            OS_COMPATIBLE=1
        fi
    elif [ "$OS_ID" = "debian" ]; then
        MAJOR_VER=$(echo "$OS_VER_ID" | cut -d. -f1)
        if [[ "$MAJOR_VER" =~ ^[0-9]+$ ]] && [ "$MAJOR_VER" -ge 12 ]; then
            OS_COMPATIBLE=1
        fi
    fi

    if [ "$OS_COMPATIBLE" -ne 1 ]; then
        die "Скрипт оптимизирован строго под ОС Ubuntu (22.04+) и Debian (12+). Текущая ОС: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} не поддерживается."
    fi
    ok "Операционная система валидирована: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME)"
else
    die "Не удалось определить параметры текущего дистрибутива ОС."
fi

log "Первичная подготовка системных утилит..."
apt-get update -q >/dev/null 2>&1 || true
apt-get install -y curl bc bind9-dnsutils iproute2 openssl gawk python3 python3-bcrypt xxd unzip jq sqlite3 bsdextrautils gnupg dirmngr -q >/dev/null 2>&1 || true
ok "Базовые утилиты готовы к работе."

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 22 ] && [ "$1" -le 65535 ]
}

validate_ipv4() {
    local ip="$1"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ "$ip" =~ $rx ]]; then
        local IFS='.'
        read -r -a octets <<< "$ip"
        [ "${octets[0]}" -le 255 ] && [ "${octets[1]}" -le 255 ] && \
        [ "${octets[2]}" -le 255 ] && [ "${octets[3]}" -le 255 ]
    else
        return 1
    fi
}

SSH_ACTIVE_PORT=""
if [ -n "${SSH_CONNECTION:-}" ]; then
    SSH_ACTIVE_PORT=$(echo "$SSH_CONNECTION" | awk '{print $4}')
fi

if [ -z "$SSH_ACTIVE_PORT" ] || ! validate_port "$SSH_ACTIVE_PORT"; then
    SSH_ACTIVE_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | grep -vE '127\.0\.0\.1|::1' | awk '{print $4}' | awk -F: '{print $NF}' | grep -vE '^60[0-9]{2}$' | sort -n | tail -n1 || echo "")
fi
SSH_ACTIVE_PORT="${SSH_ACTIVE_PORT:-22}"

prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val
    read -rp "$(echo -e "${prompt_text} [${GREEN}${default_val}${NC}]: ")" input_val
    declare -g "$var_name=${input_val:-$default_val}"
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_ans="${2:-y}"
    local ans
    while true; do
        if [ "$default_ans" = "y" ]; then
            read -rp "$(echo -e "${prompt_text} [${GREEN}Y/n${NC}]: ")" ans
            ans="${ans:-y}"
        else
            read -rp "$(echo -e "${prompt_text} [${YELLOW}y/N${NC}]: ")" ans
            ans="${ans:-n}"
        fi
        case "${ans,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "Введите 'y' или 'n'." ;;
        esac
    done
}

validate_path_segment() {
    local val="$1"
    local name="$2"
    if [[ ! "$val" =~ ^[a-zA-Z0-9_/-]+$ ]]; then
        die "Параметр $name ('$val') содержит недопустимые символы. Используйте латиницу, цифры, дефис и слэши."
    fi
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
    echo -e "     их UUID, ключей, паролей, статистики и хостов + обновление стека"
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
            /etc/ufw/before.rules 2>/dev/null || true
        chmod 600 "$BACKUP_TAR"
        ok "Резервная копия создана: $BACKUP_TAR"
    else
        warn "Выбрана ЧИСТАЯ УСТАНОВКА. Прежние клиенты и ключи будут сброшены!"
    fi
fi

DETECTED_COUNTRY=$(curl -s4 --connect-timeout 3 https://ipinfo.io/country 2>/dev/null || echo "")
[ -z "$DETECTED_COUNTRY" ] && DETECTED_COUNTRY=$(curl -s4 --connect-timeout 3 http://ip-api.com/line/?fields=countryCode 2>/dev/null || echo "")

DEFAULT_GEO_PROFILE="2"
if [[ "${DETECTED_COUNTRY^^}" == "RU" ]]; then
    DEFAULT_GEO_PROFILE="1"
    ok "Сервер расположен в РФ (Геолокация: RU). Рекомендуется профиль [1]."
else
    ok "Сервер расположен за пределами РФ (Геолокация: ${DETECTED_COUNTRY:-Unknown}). Рекомендуется профиль [2]."
fi

echo -e "\n${WHITE}${BOLD}--- ВЫБОР СЕТЕВОГО ПРОФИЛЯ РАЗВЁРТЫВАНИЯ ---${NC}"
echo -e "  1) ${GREEN}[RU] Сервер в РФ${NC} (Яндекс DNS 77.88.8.8, CDN-зеркала GitHub, DoH over TCP)"
echo -e "  2) ${GREEN}[EU/World] Зарубежный сервер${NC} (Cloudflare/Google DNS, прямой GitHub/AdGuard, DoQ/QUIC)"
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
if [ "$INSTALL_MODE" = "2" ] && [ -f /etc/nginx/conf.d/01-main.conf ]; then
    DETECTED_MAIN_DOM=$(grep -E 'server_name\s+[^;]+;' /etc/nginx/conf.d/01-main.conf 2>/dev/null | grep -v '_' | awk '{print $2}' | tr -d ';' | head -n1 || echo "")
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
    read -rp "Введите контактный Email (для Let's Encrypt SSL): " LE_EMAIL
    LE_EMAIL=$(echo "$LE_EMAIL" | tr -d '[:space:]')
    if [[ -z "$LE_EMAIL" ]] || [[ "$LE_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат email."
done

echo
echo -e "${WHITE}${BOLD}--- ШАГ 2: Системные настройки и безопасность ОС ---${NC}"
prompt_yes_no "Выполнить полное обновление системы (apt upgrade) и очистку?" "y" && DO_SYS_UPGRADE=1 || DO_SYS_UPGRADE=0
prompt_yes_no "Установить расширенные инструменты мониторинга (htop, btop, jq, tmux)?" "y" && INSTALL_EXTRA_UTILS=1 || INSTALL_EXTRA_UTILS=0
prompt_yes_no "Включить TCP BBR, somaxconn и отключить IPv6?" "y" && ENABLE_BBR_IPV6=1 || ENABLE_BBR_IPV6=0
prompt_yes_no "Блокировать входящие ICMP (Ping) запросы в фаерволе?" "n" && BLOCK_PING=1 || BLOCK_PING=0

echo -e "Текущий активный порт SSH: ${GREEN}${SSH_ACTIVE_PORT}${NC}"
if prompt_yes_no "Сменить порт SSH на нестандартный?" "n"; then
    while true; do
        read -rp "Введите новый порт SSH (1024-65535): " CUSTOM_SSH
        if validate_port "$CUSTOM_SSH"; then
            TARGET_SSH_PORT="$CUSTOM_SSH"
            break
        fi
        warn "Недопустимый порт."
    done
else
    TARGET_SSH_PORT="$SSH_ACTIVE_PORT"
fi

CHANGE_ROOT_PASS=0
ROOT_PASSWORD=""
if [ "$INSTALL_MODE" = "1" ]; then
    if prompt_yes_no "Сменить пароль root?" "n"; then
        CHANGE_ROOT_PASS=1
        read -rsp "Введите новый пароль root: " ROOT_PASSWORD; echo
    fi
fi

CREATE_USER=0
NEW_USERNAME=""
NEW_USER_PASS=""
if [ "$INSTALL_MODE" = "1" ]; then
    if prompt_yes_no "Создать непривилегированного пользователя с sudo?" "n"; then
        CREATE_USER=1
        read -rp "Введите имя пользователя: " NEW_USERNAME
        read -rsp "Введите пароль для $NEW_USERNAME: " NEW_USER_PASS; echo
    fi
fi

prompt_yes_no "Настроить SSH ключи Ed25519?" "$([ "$INSTALL_MODE" = "2" ] && echo "n" || echo "y")" && SETUP_KEYS=1 || SETUP_KEYS=0

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

prompt_default "Внутренний локальный порт панели 3X-UI" "${DETECTED_PANEL_PORT:-10443}" PANEL_PORT
prompt_default "Секретный URI-путь к веб-панели (без слэшей)" "${DETECTED_PANEL_PATH:-my-3x-panel}" RAW_PATH
validate_path_segment "$RAW_PATH" "URI панели"
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_default "Внутренний порт сервера подписок 3X-UI" "${DETECTED_SUB_PORT:-55443}" SUB_PORT
prompt_default "Секретный URI-путь подписок (без слэшей)" "${DETECTED_SUB_PATH:-my-post-key}" RAW_SUB_PATH
validate_path_segment "$RAW_SUB_PATH" "URI подписок"
SUB_PATH="/${RAW_SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"

SUB_JSON_PATH="${SUB_PATH}sub-json/"
SUB_CLASH_PATH="/sub-clash/"

prompt_default "Внутренний порт инбаунда VLESS xHTTP (Native H2 Stream-One)" "50443" XHTTP_STREAM_PORT
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
prompt_yes_no "Включить Steal-Oneself REALITY (Кража у своего поддомена)?" "y" && ENABLE_STEAL=1 || ENABLE_STEAL=0

declare -A STEAL_PORT_DOMAINS
if [ "$ENABLE_STEAL" -eq 1 ]; then
    while true; do
        prompt_default "  Локальный порт Xray для Steal-Oneself" "45443" PORT_VAL
        while [[ ! "$PORT_VAL" =~ ^[0-9]+$ ]] || [ "$PORT_VAL" -le 0 ] || [ "$PORT_VAL" -gt 65535 ]; do
            warn "  Некорректный номер порта."
            prompt_default "  Локальный порт Xray для Steal-Oneself" "45443" PORT_VAL
        done

        if [[ ! " ${STEAL_PORTS_LIST[*]:-} " == *" ${PORT_VAL} "* ]]; then
            STEAL_PORTS_LIST+=("$PORT_VAL")
            ALL_REALITY_PORTS+=("$PORT_VAL")
        fi

        echo -e "${CYAN}  Введите домены для порта $PORT_VAL (для завершения - пусто и Enter):${NC}"
        added_count_for_port=0
        port_doms_str=""
        while true; do
            local_def="cdn.$PRIMARY_DOMAIN"
            [ "$added_count_for_port" -gt 0 ] && local_def=""
            if [ -n "$local_def" ]; then
                prompt_default "    Собственный поддомен для порта $PORT_VAL" "$local_def" S_DOM
            else
                read -rp "    Собственный поддомен для порта $PORT_VAL (Enter для завершения): " S_DOM
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
            ok "    Домен $S_DOM привязан к инбаунд-порту $PORT_VAL"
        done
        STEAL_PORT_DOMAINS["$PORT_VAL"]="$(echo "$port_doms_str" | xargs)"

        prompt_yes_no "  Сконфигурировать еще один порт Steal-Oneself?" "n" || break
    done
fi

prompt_yes_no "Включить Classic External REALITY (Сторонний доверенный SNI)?" "y" && ENABLE_CLASSIC=1 || ENABLE_CLASSIC=0

declare -A CLASSIC_PORT_SNIS
if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    while true; do
        prompt_default "  Локальный порт Xray для Classic REALITY" "46443" PORT_VAL
        while [[ ! "$PORT_VAL" =~ ^[0-9]+$ ]] || [ "$PORT_VAL" -le 0 ] || [ "$PORT_VAL" -gt 65535 ]; do
            warn "  Некорректный номер порта."
            prompt_default "  Локальный порт Xray для Classic REALITY" "46443" PORT_VAL
        done

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
            [ "$added_sni_count" -gt 0 ] && local_def=""
            if [ -n "$local_def" ]; then
                prompt_default "    Внешний SNI маскировки" "$local_def" C_SNI
            else
                read -rp "    Внешний SNI маскировки (Enter для завершения): " C_SNI
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

        prompt_yes_no "  Сконфигурировать еще один порт Classic REALITY?" "n" || break
    done
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 5: Дополнительные SSL-домены ---${NC}"
while true; do
    read -rp "Добавить собственный домен для выпуска SSL-сертификата? (Enter для завершения): " EXTRA_DOM
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
prompt_yes_no "Установить Hysteria 2 (UDP)?" "y" && ENABLE_HY2=1 || ENABLE_HY2=0

ENABLE_HY2_HOP=0
if [ "$ENABLE_HY2" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для Hysteria 2" "443" HY2_PORT
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

prompt_yes_no "Установить AmneziaWG v3.2 (UDP)?" "y" && ENABLE_AWG_V3=1 || ENABLE_AWG_V3=0
if [ "$ENABLE_AWG_V3" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для AmneziaWG v3.2" "8443" AWG_V3_PORT
fi

prompt_yes_no "Установить AmneziaWG v2.0 / Legacy (UDP)?" "y" && ENABLE_AWG_V2=1 || ENABLE_AWG_V2=0
if [ "$ENABLE_AWG_V2" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для AmneziaWG v2.0" "8444" AWG_V2_PORT
fi

prompt_yes_no "Установить чистый Native WireGuard RFC (UDP, MTU 1420 / MSS 1380)?" "y" && ENABLE_WG_NATIVE=1 || ENABLE_WG_NATIVE=0
if [ "$ENABLE_WG_NATIVE" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для Native WireGuard RFC" "47443" WG_NATIVE_PORT
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 7: Приватный DNS AdGuard Home (DoH) ---${NC}"
prompt_yes_no "Установить приватный AdGuard Home DoH со Split-DNS?" "y" && ENABLE_AGH=1 || ENABLE_AGH=0
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
echo -e "${GREEN}  ФАЗА 1: Hardening ОС, TCP BBR, somaxconn и Loose rp_filter         ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx 2>/dev/null || true

log "Обновление пакетных репозиториев..."
apt-get update -q

if [ "${DO_SYS_UPGRADE:-0}" -eq 1 ]; then
    log "Полное обновление пакетов системы..."
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y -q
    apt-get autoclean -y -q
fi

log "Установка системного набора утилит..."
CORE_PKGS=(
    curl wget bash sudo systemd openssl gawk lsb-release gnupg bind9-dnsutils
    socat cron ufw iptables iproute2 tar apache2-utils fail2ban python3 python3-systemd
    python3-bcrypt ca-certificates build-essential jq tmux net-tools bc xxd unzip sqlite3 bsdextrautils dirmngr
)
apt-get install -y "${CORE_PKGS[@]}" -q || true

if [ "${INSTALL_EXTRA_UTILS:-0}" -eq 1 ]; then
    apt-get install -y htop iperf3 iftop tcpdump mtr-tiny ncdu vnstat openssh-client -q || true
    apt-get install -y btop -q 2>/dev/null || true
fi
ok "Системные утилиты установлены."

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
    [ -n "${NEW_USERNAME:-}" ] && TARGET_KEY_USER="$NEW_USERNAME"
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
    [ -z "$resolved_ip" ] && resolved_ip=$(dig +short "$dom" @8.8.8.8 2>/dev/null | tail -n1 || echo "")
    if [ -z "$resolved_ip" ]; then
        warn "Домен $dom пока не резолвится в IP. Убедитесь, что прокси-режим Cloudflare выключен."
        prompt_yes_no "Продолжить установку SSL для $dom?" "y" || die "Установка отменена."
    elif [ -n "$WAN_IP" ] && [ "$resolved_ip" != "$WAN_IP" ]; then
        warn "Несовпадение IP: $dom указывает на $resolved_ip, ожидается: $WAN_IP."
        prompt_yes_no "Продолжить установку SSL для $dom?" "y" || die "Установка отменена."
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
        [ "$OS_ID" = "ubuntu" ] && NGINX_REPO_CODENAME="noble" || NGINX_REPO_CODENAME="bookworm"
    fi

    echo "deb [signed-by=$NGINX_KEYRING] https://nginx.org/packages/mainline/$OS_ID $NGINX_REPO_CODENAME nginx" \
        | tee /etc/apt/sources.list.d/nginx.list >/dev/null

    cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

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
    apt-get update -q
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx libnginx-mod-stream 2>/dev/null || apt-get install -y -q nginx
else
    apt-get update -q
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx
fi

NGINX_USER="nginx"
id -u nginx >/dev/null 2>&1 || NGINX_USER="www-data"

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p "$WEBROOT/assets/css" "$WEBROOT/assets/js" "$WEBROOT/assets/img"
mkdir -p /var/cache/nginx /var/www/mirror /var/www/proxy_temp /etc/nginx/stream.d /etc/nginx/conf.d /etc/nginx/modules-enabled

rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* 2>/dev/null || true
rm -rf /etc/nginx/conf.d/* /etc/nginx/stream.d/* 2>/dev/null || true

chmod 755 /var /var/www "$WEBROOT"
chmod -R 755 "$WEBROOT/.well-known"
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp

cat << 'EOF' > /etc/nginx/conf.d/00-acme.conf
server {
    listen 80 default_server;
    server_name _;
    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF

nginx -t || die "Ошибка конфигурации ACME сервера Nginx."
systemctl restart nginx

log "Локальный Pre-flight Loopback Smoke Test для ACME..."
SMOKE_FILE="$WEBROOT/.well-known/acme-challenge/smoke-test.txt"
echo "acme-smoke-test-payload-ok" > "$SMOKE_FILE"
chmod 644 "$SMOKE_FILE"
chown "$NGINX_USER:$NGINX_USER" "$SMOKE_FILE"

SMOKE_RESPONSE=$(curl -s4 -m 5 "http://127.0.0.1/.well-known/acme-challenge/smoke-test.txt" || echo "FAIL")
rm -f "$SMOKE_FILE"

if [ "$SMOKE_RESPONSE" != "acme-smoke-test-payload-ok" ]; then
    die "Pre-flight тест отдачи ACME токена завершился сбоем (Ответ: '$SMOKE_RESPONSE'). Проверьте порт 80!"
fi
ok "Pre-flight Loopback Smoke Test успешно пройден: Nginx отдает ACME токены."

if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Настройка Certbot через системный APT..."
    apt-get install -y certbot -q

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
        if [ -f "/etc/letsencrypt/live/$dom/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$dom/privkey.pem" ]; then
            ok "Сертификат для $dom уже существует в системе."
            continue
        fi

        log "Выпуск сертификата для $dom..."
        certbot_email_args=("--register-unsafely-without-email")
        [ -n "$LE_EMAIL" ] && certbot_email_args=("--email" "$LE_EMAIL")

        if certbot certonly --webroot -w "$WEBROOT" --cert-name "$dom" --expand --non-interactive --agree-tos "${certbot_email_args[@]}" -d "$dom"; then
            ok "Сертификат для $dom получен."
        else
            warn "Ошибка выпуска SSL для $dom."
            [ "$dom" = "$PRIMARY_DOMAIN" ] && die "Критическая ошибка: SSL главного домена не получен."
        fi
    done

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
    cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true
systemctl reload nginx
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
else
    log "Выпуск SSL через acme.sh..."
    curl -s https://get.acme.sh | sh -s email="${LE_EMAIL:-admin@$PRIMARY_DOMAIN}"
    _ACME="${HOME:-/root}/.acme.sh/acme.sh"
    chmod +x "$_ACME"
    "$_ACME" --register-account -m "${LE_EMAIL:-admin@$PRIMARY_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p /etc/ssl/acme && chmod 755 /etc/ssl /etc/ssl/acme

    for dom in "${ALL_DOMAINS[@]}"; do
        if [ -f "/etc/ssl/acme/$dom/fullchain.pem" ]; then
            ok "Сертификат для $dom уже существует."
            continue
        fi

        if "$_ACME" --issue --dns dns_cf -d "$dom" --server letsencrypt --force; then
            mkdir -p "/etc/ssl/acme/$dom"
            "$_ACME" --install-cert -d "$dom" \
                --key-file "/etc/ssl/acme/$dom/privkey.pem" \
                --fullchain-file "/etc/ssl/acme/$dom/fullchain.pem" \
                --reloadcmd "chmod 755 /etc/ssl/acme/$dom; chmod 644 /etc/ssl/acme/$dom/*; systemctl reload nginx"
            ok "Сертификат для $dom получен."
        fi
    done
fi

chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true

if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    log "Установка AdGuard Home (DoH + Split-DNS)..."
    mkdir -p /etc/systemd/resolved.conf.d
    cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard-disable-stub.conf
[Resolve]
DNSStubListener=no
EOF
    systemctl restart systemd-resolved 2>/dev/null || true

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) AGH_ARCH="amd64" ;;
        aarch64|arm64) AGH_ARCH="arm64" ;;
        armv7l|armhf) AGH_ARCH="armv7" ;;
        *) AGH_ARCH="amd64" ;;
    esac

    AGH_TAR="/tmp/agh.tar.gz"
    rm -f "$AGH_TAR"

    if [ "$GEO_PROFILE" = "1" ]; then
        AGH_URLS=(
            "https://ghfast.top/https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
            "https://ghproxy.net/https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
            "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
        )
    else
        AGH_URLS=(
            "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
            "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
        )
    fi

    download_asset "$AGH_TAR" "${AGH_URLS[@]}" || die "Не удалось загрузить архив AdGuard Home!"
    tar -zxvf "$AGH_TAR" -C /opt/ >/dev/null
    rm -f "$AGH_TAR"

    AGH_PASS_HASH=$(htpasswd -b -n -B -C 10 "" "$AGH_PASS" | tr -d '\n' | cut -d: -f2)

    if [ "$GEO_PROFILE" = "1" ]; then
        AGH_UPSTREAMS="    - \"[/ru/kz/by/su/xn--p1ai/]https://77.88.8.8:443/dns-query\"
    - \"https://common.dot.dns.yandex.net/dns-query\"
    - \"https://dns.google/dns-query\"
    - \"https://cloudflare-dns.com/dns-query\"
    - \"tls://dns.google:853\""
    else
        AGH_UPSTREAMS="    - \"quic://dns.adguard-dns.com\"
    - \"quic://dns.nextdns.io\"
    - \"quic://dns.quad9.net\"
    - \"h3://dns.google/dns-query\"
    - \"h3://cloudflare-dns.com/dns-query\""
    fi

    if [ "$INSTALL_MODE" = "1" ] || [ ! -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
        cat << EOF > /opt/AdGuardHome/AdGuardHome.yaml
http:
  address: 127.0.0.1:3000
  doh:
    insecure_enabled: true
users:
  - name: ${AGH_USER}
    password: "${AGH_PASS_HASH}"
dns:
  bind_hosts:
    - 127.0.0.1
  port: 53
  trusted_proxies:
    - 127.0.0.1
    - 10.8.1.0/24
    - 10.8.2.0/24
    - 10.8.3.0/24
    - ::1
  upstream_dns:
${AGH_UPSTREAMS}
clients:
  runtime_sources:
    whois: false
    dhcp: false
  persistent:
    - name: Home-Router
      ids:
        - ${AGH_CLIENT_ID}
      use_global_settings: true
access:
  allowed_clients:
    - ${AGH_CLIENT_ID}
    - "10.8.1.0/24"
    - "10.8.2.0/24"
    - "10.8.3.0/24"
    - "127.0.0.1"
  disallowed_clients: []
  blocked_hosts: []
tls:
  enabled: false
  allow_unencrypted_doh: true
schema_version: 28
EOF
    else
        ok "Конфигурация AdGuard Home сохранена."
    fi

    /opt/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || true
    systemctl restart AdGuardHome || true
    ok "AdGuard Home DoH активен на 127.0.0.1:53."
fi

# =============================================================
#  ВЕБ-МАСКИРОВКА (DataSphere Enterprise Decoy Shield v4.0 Ultra)
# =============================================================
log "Генерация флагманского комплекса веб-маскировки (DataSphere Decoy Shield v4.0 Ultra)..."

cat << 'EOF' > /var/www/html/assets/img/favicon.svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="sphereGrad" cx="35%" cy="35%" r="65%">
      <stop offset="0%" stop-color="#a8c7fa"/>
      <stop offset="45%" stop-color="#008dd5"/>
      <stop offset="100%" stop-color="#0a192f"/>
    </radialGradient>
    <clipPath id="circleMask"><circle cx="50" cy="50" r="48"/></clipPath>
  </defs>
  <g clip-path="url(#circleMask)">
    <circle cx="50" cy="50" r="48" fill="url(#sphereGrad)"/>
    <g stroke="#ffffff" stroke-width="1.5" stroke-opacity="0.45" fill="none">
      <ellipse cx="50" cy="50" rx="46" ry="18"/>
      <ellipse cx="50" cy="50" rx="46" ry="32"/>
      <ellipse cx="50" cy="50" rx="18" ry="46"/>
      <ellipse cx="50" cy="50" rx="32" ry="46"/>
      <line x1="4" y1="50" x2="96" y2="50"/>
      <line x1="50" y1="4" x2="50" y2="96"/>
    </g>
    <circle cx="50" cy="50" r="6" fill="#81c995"/>
    <circle cx="28" cy="38" r="3.5" fill="#fdd663"/>
    <circle cx="72" cy="62" r="3.5" fill="#c58af9"/>
    <circle cx="70" cy="35" r="3" fill="#a8c7fa"/>
    <circle cx="32" cy="65" r="3" fill="#ffffff"/>
  </g>
  <circle cx="50" cy="50" r="48" fill="none" stroke="#a8c7fa" stroke-width="3" stroke-opacity="0.6"/>
</svg>
EOF
ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.svg
ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.ico

cat << 'EOF' > /var/www/html/robots.txt
User-agent: *
Disallow: /api/
Disallow: /console/
Disallow: /telemetry/
Disallow: /cluster-internal/
Allow: /
EOF

cat << 'EOF' > /var/www/html/assets/css/datasphere.css
:root {
    --bg-base: #0b0d10;
    --bg-surface: #13171d;
    --bg-card: #181d24;
    --border: rgba(255, 255, 255, 0.08);
    --border-hover: rgba(168, 199, 250, 0.35);
    --accent: #a8c7fa;
    --accent-glow: rgba(168, 199, 250, 0.15);
    --accent-purple: #c58af9;
    --text-primary: #e6edf3;
    --text-muted: #8b949e;
    --success: #81c995;
    --warning: #fdd663;
    --error: #f28b82;
    --terminal-bg: #090c10;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Google Sans", sans-serif;
    background-color: var(--bg-base);
    background-image: 
        radial-gradient(circle at 50% -10%, rgba(66, 133, 244, 0.14) 0%, rgba(155, 114, 207, 0.08) 35%, transparent 70%),
        radial-gradient(circle at 100% 100%, rgba(129, 201, 149, 0.04) 0%, transparent 40%),
        var(--bg-base);
    color: var(--text-primary); line-height: 1.6; overflow-x: hidden; min-height: 100vh;
}
header {
    display: flex; justify-content: space-between; align-items: center; padding: 18px 6%;
    border-bottom: 1px solid var(--border); backdrop-filter: blur(20px);
    position: sticky; top: 0; z-index: 50; background: rgba(11, 13, 16, 0.82);
}
.brand { display: flex; align-items: center; gap: 12px; font-size: 20px; font-weight: 700; color: #fff; letter-spacing: -0.4px; }
.btn {
    background: var(--bg-card); border: 1px solid var(--border); color: var(--text-primary);
    padding: 10px 22px; border-radius: 999px; font-size: 14px; font-weight: 600; cursor: pointer;
    transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1); display: inline-flex; align-items: center; gap: 8px;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.2); user-select: none;
}
.btn:hover { transform: translateY(-1px); border-color: var(--border-hover); background: #202630; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4); }
.btn:active { transform: translateY(0); }
.btn-primary { background: #1f3a60; border-color: #388bfd; color: #fff; }
.btn-primary:hover { background: #264a7a; border-color: #58a6ff; }
.hero-split {
    display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 40px; align-items: center;
    max-width: 1240px; margin: 40px auto; padding: 40px 6%;
}
@media (max-width: 900px) { .hero-split { grid-template-columns: 1fr; text-align: center; } }
.hero-text h1 { font-size: clamp(34px, 4.5vw, 52px); font-weight: 700; line-height: 1.15; margin-bottom: 20px; letter-spacing: -0.8px; }
.hero-text p { font-size: 17px; color: var(--text-muted); line-height: 1.65; margin-bottom: 30px; }
.badge {
    display: inline-flex; align-items: center; gap: 8px; padding: 6px 14px; background: var(--bg-card);
    border: 1px solid var(--border); border-radius: 999px; font-size: 13px; font-weight: 500; color: var(--accent); margin-bottom: 20px;
}
.badge-dot { width: 7px; height: 7px; background: var(--success); border-radius: 50%; box-shadow: 0 0 8px var(--success); }
.canvas-wrapper {
    position: relative; width: 100%; aspect-ratio: 1; max-width: 480px; margin: 0 auto;
    display: flex; align-items: center; justify-content: center;
}
#sphereCanvas { width: 100%; height: 100%; border-radius: 50%; filter: drop-shadow(0 0 35px rgba(56, 139, 253, 0.2)); }
.stats-bar { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; max-width: 1140px; margin: 0 auto 50px; padding: 0 6%; }
.stat-card { background: var(--bg-card); border: 1px solid var(--border); padding: 22px; border-radius: 18px; text-align: center; }
.stat-card h3 { font-size: 28px; font-weight: 700; color: #fff; }
.stat-card p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
.features { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 20px; max-width: 1140px; margin: 0 auto 60px; padding: 0 6%; }
.feature-card {
    background: var(--bg-card); border: 1px solid var(--border); padding: 30px 24px; border-radius: 20px;
    cursor: pointer; transition: all 0.25s ease; display: flex; flex-direction: column; justify-content: space-between;
}
.feature-card:hover { transform: translateY(-3px); border-color: var(--border-hover); background: #1c222b; }
.feature-card h3 { font-size: 18px; font-weight: 600; margin-bottom: 10px; color: #fff; }
.feature-card p { font-size: 14px; color: var(--text-muted); line-height: 1.55; }
.card-action { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: var(--accent); margin-top: 16px; }
.telemetry-section { max-width: 1140px; margin: 0 auto 80px; padding: 0 6%; }
.terminal-card {
    background: var(--terminal-bg); border: 1px solid var(--border); border-radius: 20px; overflow: hidden;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
}
.terminal-header {
    background: #161b22; padding: 12px 18px; display: flex; align-items: center; gap: 8px; border-bottom: 1px solid var(--border);
}
.term-dot { width: 11px; height: 11px; border-radius: 50%; display: inline-block; }
.term-dot.r { background: #ff5f56; } .term-dot.y { background: #ffbd2e; } .term-dot.g { background: #27c93f; }
.term-title { font-size: 12px; font-family: monospace; color: var(--text-muted); margin-left: 8px; }
.terminal-body { padding: 20px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; color: #c9d1d9; }
.telemetry-canvas-wrap { width: 100%; height: 160px; margin-bottom: 18px; position: relative; }
#chartCanvas { width: 100%; height: 100%; }
.terminal-logs { max-height: 180px; overflow-y: auto; display: flex; flex-direction: column; gap: 6px; }
.log-line { line-height: 1.4; color: #8b949e; word-break: break-all; }
.log-line span.ts { color: #58a6ff; }
.log-line span.hl { color: #7ee787; font-weight: 600; }
.cli-prompt { display: flex; align-items: center; gap: 8px; margin-top: 14px; padding-top: 12px; border-top: 1px solid rgba(255, 255, 255, 0.05); }
.cli-prompt input {
    background: transparent; border: none; outline: none; color: #fff; font-family: inherit; font-size: 13px; flex: 1;
}
.modal-overlay {
    position: fixed; inset: 0; background: rgba(5, 7, 10, 0.85); backdrop-filter: blur(16px);
    display: flex; align-items: center; justify-content: center; padding: 20px; z-index: 100;
    opacity: 0; visibility: hidden; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}
.modal-overlay.active { opacity: 1; visibility: visible; }
.modal-card {
    background: var(--bg-surface); border: 1px solid var(--border); border-radius: 24px; width: 100%; max-width: 480px;
    padding: 32px; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7); transform: translateY(20px); transition: transform 0.3s ease;
}
.modal-overlay.active .modal-card { transform: translateY(0); }
.modal-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 18px; }
.modal-header h2 { font-size: 20px; font-weight: 700; color: #fff; }
.modal-header p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
.modal-close { background: transparent; border: none; color: var(--text-muted); cursor: pointer; padding: 4px; display: flex; }
.modal-close:hover { color: #fff; }
.form-group { margin-bottom: 16px; }
.form-group label { display: block; font-size: 13px; font-weight: 500; color: #c4c7c5; margin-bottom: 6px; }
.form-control {
    width: 100%; padding: 12px 14px; background: #090c10; border: 1px solid var(--border); border-radius: 12px;
    color: #fff; font-size: 14px; outline: none; transition: all 0.2s ease;
}
.form-control:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(168, 199, 250, 0.2); }
.alert-box {
    background: rgba(239, 68, 68, 0.12); border: 1px solid rgba(239, 68, 68, 0.3); color: #fca5a5;
    padding: 12px 14px; border-radius: 12px; font-size: 13px; margin-bottom: 18px; display: none; align-items: center; gap: 10px;
}
.toast-hud {
    position: fixed; bottom: 30px; right: 30px; background: var(--bg-card); border: 1px solid var(--border-hover);
    border-radius: 16px; padding: 16px 20px; box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6); display: flex; align-items: flex-start; gap: 12px;
    z-index: 200; max-width: 360px; transform: translateY(100px); opacity: 0; visibility: hidden; transition: all 0.3s ease;
}
.toast-hud.active { transform: translateY(0); opacity: 1; visibility: visible; }
.spinner { width: 16px; height: 16px; border: 2px solid rgba(255, 255, 255, 0.3); border-top: 2px solid #fff; border-radius: 50%; animation: spin 0.8s linear infinite; }
footer { text-align: center; padding: 40px 20px; color: var(--text-muted); font-size: 13px; border-top: 1px solid var(--border); }
@keyframes spin { 100% { transform: rotate(360deg); } }
EOF

cat << 'EOF' > /var/www/html/assets/js/datasphere.js
"use strict";

document.addEventListener("DOMContentLoaded", () => {
    // -------------------------------------------------------------
    // 1. 3D TOPOLOGICAL GEODESIC SPHERE CANVAS ENGINE
    // -------------------------------------------------------------
    const sCanvas = document.getElementById("sphereCanvas");
    if (sCanvas) {
        const ctx = sCanvas.getContext("2d");
        let width, height;
        const dpr = window.devicePixelRatio || 1;

        const resizeSphere = () => {
            const rect = sCanvas.getBoundingClientRect();
            width = rect.width;
            height = rect.height;
            sCanvas.width = width * dpr;
            sCanvas.height = height * dpr;
            ctx.scale(dpr, dpr);
        };
        resizeSphere();
        window.addEventListener("resize", resizeSphere);

        const nodesCount = 92;
        const nodes = [];
        const radius = 150;

        for (let i = 0; i < nodesCount; i++) {
            const phi = Math.acos(-1 + (2 * i) / nodesCount);
            const theta = Math.sqrt(nodesCount * Math.PI) * phi;
            nodes.push({
                x: radius * Math.cos(theta) * Math.sin(phi),
                y: radius * Math.sin(theta) * Math.sin(phi),
                z: radius * Math.cos(phi)
            });
        }

        let rotX = 0.003;
        let rotY = 0.005;
        let targetRotX = 0.003;
        let targetRotY = 0.005;

        window.addEventListener("mousemove", (e) => {
            const nx = (e.clientX / window.innerWidth) - 0.5;
            const ny = (e.clientY / window.innerHeight) - 0.5;
            targetRotX = ny * 0.015;
            targetRotY = nx * 0.015;
        });

        let isVisible = true;
        document.addEventListener("visibilitychange", () => {
            isVisible = !document.hidden;
        });

        const project = (p) => {
            const fov = 340;
            const factor = fov / (fov + p.z);
            return {
                x: p.x * factor + width / 2,
                y: p.y * factor + height / 2,
                scale: factor
            };
        };

        const renderSphere = () => {
            if (!isVisible) {
                requestAnimationFrame(renderSphere);
                return;
            }

            rotX += (targetRotX - rotX) * 0.05;
            rotY += (targetRotY - rotY) * 0.05;

            ctx.clearRect(0, 0, width, height);

            const cosX = Math.cos(rotX), sinX = Math.sin(rotX);
            const cosY = Math.cos(rotY), sinY = Math.sin(rotY);

            for (let i = 0; i < nodes.length; i++) {
                let p = nodes[i];
                let y1 = p.y * cosX - p.z * sinX;
                let z1 = p.y * sinX + p.z * cosX;
                let x2 = p.x * cosY + z1 * sinY;
                let z2 = -p.x * sinY + z1 * cosY;
                nodes[i] = { x: x2, y: y1, z: z2 };
            }

            ctx.lineWidth = 0.7;
            for (let i = 0; i < nodes.length; i++) {
                const p1 = project(nodes[i]);
                for (let j = i + 1; j < nodes.length; j++) {
                    const dx = nodes[i].x - nodes[j].x;
                    const dy = nodes[i].y - nodes[j].y;
                    const dz = nodes[i].z - nodes[j].z;
                    const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
                    if (dist < 64) {
                        const p2 = project(nodes[j]);
                        const alpha = (1 - dist / 64) * 0.35 * Math.min(p1.scale, p2.scale);
                        ctx.strokeStyle = `rgba(168, 199, 250, ${alpha})`;
                        ctx.beginPath();
                        ctx.moveTo(p1.x, p1.y);
                        ctx.lineTo(p2.x, p2.y);
                        ctx.stroke();
                    }
                }
            }

            for (let i = 0; i < nodes.length; i++) {
                const p = project(nodes[i]);
                const alpha = Math.max(0.1, (nodes[i].z + radius) / (2 * radius));
                ctx.fillStyle = `rgba(129, 201, 149, ${alpha})`;
                ctx.beginPath();
                ctx.arc(p.x, p.y, 2 * p.scale, 0, Math.PI * 2);
                ctx.fill();
            }

            requestAnimationFrame(renderSphere);
        };
        requestAnimationFrame(renderSphere);
    }

    // -------------------------------------------------------------
    // 2. LIVE THROUGHPUT CANVAS CHART ENGINE (100 Gbps SPARKLINE)
    // -------------------------------------------------------------
    const cCanvas = document.getElementById("chartCanvas");
    if (cCanvas) {
        const cCtx = cCanvas.getContext("2d");
        const pointsCount = 40;
        const dataPoints = Array.from({ length: pointsCount }, () => 80 + Math.random() * 18);

        const renderChart = () => {
            const w = cCanvas.parentElement.clientWidth;
            const h = cCanvas.parentElement.clientHeight;
            cCanvas.width = w * window.devicePixelRatio;
            cCanvas.height = h * window.devicePixelRatio;
            cCtx.scale(window.devicePixelRatio, window.devicePixelRatio);

            cCtx.clearRect(0, 0, w, h);

            cCtx.strokeStyle = "rgba(255, 255, 255, 0.05)";
            cCtx.lineWidth = 1;
            cCtx.beginPath();
            for (let y = 20; y < h; y += 30) {
                cCtx.moveTo(0, y); cCtx.lineTo(w, y);
            }
            cCtx.stroke();

            const step = w / (pointsCount - 1);
            cCtx.beginPath();
            cCtx.moveTo(0, h - (dataPoints[0] / 100) * h);

            for (let i = 0; i < pointsCount - 1; i++) {
                const x0 = i * step;
                const y0 = h - (dataPoints[i] / 100) * (h * 0.85);
                const x1 = (i + 1) * step;
                const y1 = h - (dataPoints[i + 1] / 100) * (h * 0.85);
                const mx = (x0 + x1) / 2;
                cCtx.quadraticCurveTo(x0, y0, mx, (y0 + y1) / 2);
            }

            cCtx.strokeStyle = "#58a6ff";
            cCtx.lineWidth = 2;
            cCtx.stroke();

            cCtx.lineTo(w, h);
            cCtx.lineTo(0, h);
            cCtx.closePath();
            const grad = cCtx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, "rgba(88, 166, 255, 0.25)");
            grad.addColorStop(1, "rgba(88, 166, 255, 0.0)");
            cCtx.fillStyle = grad;
            cCtx.fill();
        };

        renderChart();
        window.addEventListener("resize", renderChart);

        setInterval(() => {
            const randArr = new Uint32Array(1);
            window.crypto.getRandomValues(randArr);
            const delta = (randArr[0] / 0xffffffff - 0.5) * 6;
            let last = dataPoints[dataPoints.length - 1] + delta;
            if (last > 99.8) last = 96.0;
            if (last < 75.0) last = 78.0;
            dataPoints.shift();
            dataPoints.push(last);
            renderChart();
        }, 1200);
    }

    // -------------------------------------------------------------
    // 3. WEB CLI TERMINAL & MODAL DIALOGS
    // -------------------------------------------------------------
    const termLogs = document.getElementById("terminalLogs");
    const cliInput = document.getElementById("cliInput");
    const authModal = document.getElementById("authModal");
    const detailModal = document.getElementById("detailModal");
    const toastHud = document.getElementById("toastHud");

    const showToast = (title, desc) => {
        document.getElementById("toastTitle").innerText = title;
        document.getElementById("toastDesc").innerText = desc;
        toastHud.classList.add("active");
        setTimeout(() => toastHud.classList.remove("active"), 4500);
    };

    const addLog = (msg, hl = false) => {
        if (!termLogs) return;
        const now = new Date().toISOString().split("T")[1].slice(0, 8);
        const div = document.createElement("div");
        div.className = "log-line";
        div.innerHTML = `<span class="ts">[${now}]</span> ${hl ? '<span class="hl">' + msg + '</span>' : msg}`;
        termLogs.appendChild(div);
        termLogs.scrollTop = termLogs.scrollHeight;
    };

    cliInput?.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
            const val = cliInput.value.trim().toLowerCase();
            cliInput.value = "";
            addLog(`$ ${val}`, true);

            if (val === "help") {
                addLog("Доступные команды: status, nodes, crypto, telemetry, clear");
            } else if (val === "status") {
                addLog("Ядро Anycast: ONLINE | Ингресс H2C/TLS: 100 Gbps | Потери: 0.000%");
            } else if (val === "nodes") {
                addLog("Активно узлов: 148 PoP (EU: 62, US: 54, APAC: 32) | Балансировка: FQ/BBR");
            } else if (val === "crypto") {
                addLog("Шифрование сессий: ML-KEM-768 + X25519 (RFC 8446) | Zero-Knowledge");
            } else if (val === "clear") {
                termLogs.innerHTML = "";
            } else {
                addLog(`Команда не найдена: '${val}'. Введите 'help' для справки.`);
            }
        }
    });

    const openAuth = () => { authModal.classList.add("active"); };
    const closeModals = () => {
        authModal.classList.remove("active");
        detailModal.classList.remove("active");
    };

    document.getElementById("headerConsoleBtn")?.addEventListener("click", openAuth);
    document.getElementById("connectNodeBtn")?.addEventListener("click", openAuth);
    document.getElementById("authModalClose")?.addEventListener("click", closeModals);
    document.getElementById("detailModalClose")?.addEventListener("click", closeModals);
    document.getElementById("detailModalOk")?.addEventListener("click", closeModals);

    document.getElementById("netStatusBtn")?.addEventListener("click", () => {
        showToast("Сетевой кластер DataSphere", "Anycast-маршрутизация активна: RTT < 1.2 ms.");
    });

    document.getElementById("authForm")?.addEventListener("submit", (e) => {
        e.preventDefault();
        const submitBtn = document.getElementById("submitBtn");
        submitBtn.innerHTML = '<span class="spinner"></span> Верификация...';
        submitBtn.disabled = true;

        setTimeout(() => {
            document.getElementById("errorMsg").innerText = "Ошибка 401: Доступ отклонен. Ключ узла не сертифицирован.";
            document.getElementById("errorAlert").style.display = "flex";
            submitBtn.innerHTML = "Подключиться к кластеру";
            submitBtn.disabled = false;
        }, 800);
    });

    const details = {
        cardCrypto: {
            title: "Сквозное квантовое шифрование",
            desc: "Аппаратная акселерация ML-KEM-768",
            content: "Сессии терминируются с использованием постквантовой криптографии на базе решеток (ML-KEM-768) в связке с X25519. Срок жизни сессионного ключа строго ограничен 300 секундами."
        },
        cardTelemetry: {
            title: "Распределенная Anycast-телеметрия",
            desc: "Многопоточный конвейер синхронизации",
            content: "Метрики сетевого потока агрегируются в режиме реального времени на границе датацентров. Потери пакетов устранены за счет алгоритмов упреждающей маршрутизации FQ/BBR."
        },
        cardIpc: {
            title: "Изоляция сокетов In-Memory IPC",
            desc: "Zero-Copy архитектура обмена",
            content: "Межсервисный транспорт внутри хоста маршрутизируется через энергонезависимые сокеты в Shared Memory (/dev/shm) без накладных расходов сетевого стека ядра."
        },
        cardOffload: {
            title: "Аппаратная терминация очередей",
            desc: "Масштабирование сокетов somaxconn",
            content: "Сетевой стек оптимизирован под максимальную утилизацию очередей ядра (somaxconn = 65535, rmem/wmem до 64 MB), полностью исключая дропы при пиках входящих соединений."
        }
    };

    Object.keys(details).forEach(id => {
        document.getElementById(id)?.addEventListener("click", () => {
            const item = details[id];
            document.getElementById("detailTitle").innerText = item.title;
            document.getElementById("detailSubtitle").innerText = item.desc;
            document.getElementById("detailContent").innerHTML = `<p style="color:#8b949e; font-size:14px; line-height:1.6;">${item.content}</p>`;
            detailModal.classList.add("active");
        });
    });
});
EOF

cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DataSphere Analytics — Платформа распределенной аналитики данных</title>
    <meta name="description" content="Корпоративная среда распределенной обработки данных с квантово-устойчивым шифрованием ML-KEM-768, аппаратной акселерацией L4/L7 и Anycast-маршрутизацией узлов.">
    <link rel="icon" type="image/svg+xml" href="/assets/img/favicon.svg">
    <link rel="stylesheet" href="/assets/css/datasphere.css">
    <script defer src="/assets/js/datasphere.js"></script>
</head>
<body>
    <header>
        <div class="brand">
            <svg viewBox="0 0 100 100" width="28" height="28" xmlns="http://www.w3.org/2000/svg">
                <circle cx="50" cy="50" r="46" fill="#008dd5"/>
                <ellipse cx="50" cy="50" rx="42" ry="16" fill="none" stroke="#fff" stroke-width="3"/>
                <circle cx="50" cy="50" r="7" fill="#81c995"/>
            </svg>
            DataSphere Analytics
        </div>
        <button type="button" id="headerConsoleBtn" class="btn">Консоль инженера</button>
    </header>

    <main>
        <section class="hero-split">
            <div class="hero-text">
                <div class="badge"><span class="badge-dot"></span><span>DataSphere Core v4.0 — Доступность 99.998%</span></div>
                <h1>Распределенная сеть обработки и защиты корпоративных данных</h1>
                <p>Высоконагруженная инфраструктура с аппаратной изоляцией памяти Zero-Copy, постквантовым обменом ключами ML-KEM-768 и магистральной Anycast-маршрутизацией.</p>
                <div style="display:flex; gap:14px; flex-wrap:wrap;">
                    <button type="button" id="connectNodeBtn" class="btn btn-primary">Подключить вычислительный узел</button>
                    <button type="button" id="netStatusBtn" class="btn">Статус Anycast-магистрали</button>
                </div>
            </div>
            <div class="canvas-wrapper">
                <canvas id="sphereCanvas"></canvas>
            </div>
        </section>

        <section class="stats-bar">
            <div class="stat-card"><h3>&lt; 1.2 ms</h3><p>Задержка магистрали</p></div>
            <div class="stat-card"><h3>100 Gbps</h3><p>Пропускная способность</p></div>
            <div class="stat-card"><h3>ML-KEM-768</h3><p>Постквантовый обмен</p></div>
            <div class="stat-card"><h3>Zero-Copy</h3><p>IPC Shared Memory</p></div>
        </section>

        <section class="features">
            <div class="feature-card" id="cardCrypto">
                <div>
                    <h3>Квантово-стойкое шифрование</h3>
                    <p>Терминация трафика осуществляется на базе криптографических стандартов ML-KEM-768 с ротацией сессионных ключей каждые 300 секунд.</p>
                </div>
                <span class="card-action">Спецификация криптомодуля &rarr;</span>
            </div>
            <div class="feature-card" id="cardTelemetry">
                <div>
                    <h3>Anycast-телеметрия</h3>
                    <p>Автоматическая балансировка потоков между 148 географически распределенными точками присутствия без деградации RTT.</p>
                </div>
                <span class="card-action">Топология узлов &rarr;</span>
            </div>
            <div class="feature-card" id="cardIpc">
                <div>
                    <h3>Изоляция сокетов IPC</h3>
                    <p>Прямая маршрутизация очередей данных через сегменты Shared Memory (/dev/shm) без накладных расходов сетевого стека.</p>
                </div>
                <span class="card-action">Zero-Copy конвейер &rarr;</span>
            </div>
            <div class="feature-card" id="cardOffload">
                <div>
                    <h3>Масштабирование сокетов</h3>
                    <p>Глубокая оптимизация somaxconn и буферов сокетов rmem/wmem до 64 МБ для защиты от сброса сессий при всплесках трафика.</p>
                </div>
                <span class="card-action">Аудит сетевого ядра &rarr;</span>
            </div>
        </section>

        <section class="telemetry-section">
            <div class="terminal-card">
                <div class="terminal-header">
                    <span class="term-dot r"></span>
                    <span class="term-dot y"></span>
                    <span class="term-dot g"></span>
                    <span class="term-title">datasphere-edge-telemetry — 100 Gbps Ingress/Egress Stream Monitor</span>
                </div>
                <div class="terminal-body">
                    <div class="telemetry-canvas-wrap">
                        <canvas id="chartCanvas"></canvas>
                    </div>
                    <div class="terminal-logs" id="terminalLogs">
                        <div class="log-line"><span class="ts">[INIT]</span> Магистральный конвейер BGP Anycast инициализирован. Шлюз активен.</div>
                        <div class="log-line"><span class="ts">[INFO]</span> Криптографический модуль ML-KEM-768 синхронизирован с HSM-кластером.</div>
                        <div class="log-line"><span class="ts">[METRIC]</span> Текущая загрузка буферов ядра: <span class="hl">0.02%</span>. Сессии обслуживаются без задержек.</div>
                    </div>
                    <div class="cli-prompt">
                        <span style="color:#58a6ff;">datasphere@edge:~$</span>
                        <input type="text" id="cliInput" placeholder="Введите команду (help, status, nodes, crypto, clear)..." autocomplete="off">
                    </div>
                </div>
            </div>
        </section>
    </main>

    <div id="authModal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2>Вход в консоль узла</h2>
                    <p>Введите идентификатор для авторизации в кластере</p>
                </div>
                <button type="button" id="authModalClose" class="modal-close">
                    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="errorAlert" class="alert-box">
                <span id="errorMsg">Ошибка доступа</span>
            </div>
            <form id="authForm">
                <div class="form-group">
                    <label for="nodeUser">Идентификатор узла (Node ID)</label>
                    <input type="text" id="nodeUser" class="form-control" placeholder="node-edge-01@datasphere.cloud" required>
                </div>
                <div class="form-group">
                    <label for="nodeKey">Секретный токен API</label>
                    <input type="password" id="nodeKey" class="form-control" placeholder="••••••••••••••••" required>
                </div>
                <button type="submit" id="submitBtn" class="btn btn-primary" style="width:100%; justify-content:center;">Подключиться к кластеру</button>
            </form>
        </div>
    </div>

    <div id="detailModal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="detailTitle">Спецификация</h2>
                    <p id="detailSubtitle">Параметры подсистемы DataSphere</p>
                </div>
                <button type="button" id="detailModalClose" class="modal-close">
                    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="detailContent" style="margin-bottom:20px;"></div>
            <button type="button" id="detailModalOk" class="btn" style="width:100%; justify-content:center;">Понятно</button>
        </div>
    </div>

    <div id="toastHud" class="toast-hud">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="#81c995" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
        <div>
            <div id="toastTitle" style="font-weight:600; font-size:14px; color:#fff;">Оповещение</div>
            <div id="toastDesc" style="font-size:12px; color:#8b949e;">Информация о сети</div>
        </div>
    </div>

    <footer>&copy; 2026 DataSphere Cloud Systems Inc. Платформа распределенной аналитики и защиты данных.</footer>
</body>
</html>
EOF

cat << 'EOF' > /var/www/html/404.html
<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body></html>
EOF

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"
chmod -R 755 "$WEBROOT"

log "Сборка конфигурации Nginx Mainline..."
rm -f /etc/nginx/conf.d/00-acme.conf

MODULE_LOAD_LINE=""
if [ "$USE_OFFICIAL_NGINX_REPO" -eq 0 ] && [ -d /etc/nginx/modules-enabled ]; then
    MODULE_LOAD_LINE="include /etc/nginx/modules-enabled/*.conf;"
fi

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

    log_format main '\$ak_real_ip [\$time_local] "\$request" \$status \$body_bytes_sent "\$http_user_agent"';
    access_log /var/log/nginx/access.log main buffer=32k flush=60s;

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
        ~*(?:sqlmap|nikto|masscan|zgrab|acunetix|nmap|censys|shodan|nuclei|gobuster) 1;
        ~*(?:ahrefs|semrush|mj12bot|dotbot|bytespider) 1;
    }

    map \$request_uri \$is_scan_attempt {
        default 0;
        ~*\.(?:php|asp|aspx|jsp|cgi)\$ 1;
        ~*(\.env|\.git|\.config|\.sql|\.bak|\.ini) 1;
        ~*^/(?:admin|wp-admin|phpmyadmin)/ 1;
    }

    map "\$badbot_raw:\$is_scan_attempt:\$request_uri" \$badbot {
        ~^.*:/robots\.txt(\?|\$) 0;
        ~^.*:/.well-known/ 0;
        ~^1:[01]:/favicon\.(ico|svg)\$ 0;
        ~^1:[01]:/assets/ 0;
        ~^1:[01]:/dns-query 0;
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
    limit_req_status 429;

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
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;"$'\n'
    elif [ "$ENABLE_STEAL" -eq 1 ] && [ -n "${DOMAIN_TO_PORT[$dom]:-}" ]; then
        port="${DOMAIN_TO_PORT[$dom]}"
        STREAM_MAP_RULES+="        ${dom}     reality_backend_${port};"$'\n'
    else
        STREAM_MAP_RULES+="        ${dom}     nginx_http_backend;"$'\n'
    fi
done

if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    for ext_sni in "${!EXT_SNI_TO_PORT[@]}"; do
        port="${EXT_SNI_TO_PORT[$ext_sni]}"
        STREAM_MAP_RULES+="        ${ext_sni}     reality_backend_${port};"$'\n'
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
[ "$ENABLE_CLASSIC" -eq 1 ] && DEFAULT_FALLBACK="reality_backend_${DEFAULT_PORT}" || DEFAULT_FALLBACK="nginx_http_backend"

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
    location ^~ /.well-known/acme-challenge/ { 
        root $WEBROOT; 
        default_type "text/plain";
        try_files \$uri =404;
    }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl default_server proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl default_server proxy_protocol;
    http2 on;
    server_name _;
    
    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        root $WEBROOT;
        try_files /index.html =404;
    }
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
    add_header X-DataSphere-Engine "v4.0.2-enterprise-ultra" always;

    if (\$badbot) { return 404; }

    # ПАНЕЛЬ УПРАВЛЕНИЯ 3X-UI
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

    # СЕРВЕР ПОДПИСОК
    location = ${SUB_PATH%/} { return 301 ${SUB_PATH}; }
    location ^~ ${SUB_PATH} {
        proxy_hide_header Content-Security-Policy;
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location ~* ^/(sub|json|clash)/ {
        proxy_hide_header Content-Security-Policy;
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # VLESS xHTTP (Native H2C Stream-One)
    location ~* ^${BASE_XHTTP_PATH}(/.*)?$ {
        if (\$request_method !~ ^(GET|POST)\$) { return 404; }
        
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

    location ~ ^/(api/v1/datasphere/status|status)\$ {
        default_type application/json;
        return 200 '{"status":"online","cluster":"datasphere-edge-ultra","nodes_active":148,"telemetry_rate":"99.998%","version":"4.0.2"}';
    }

    location = /api/v1/datasphere/auth {
        if (\$request_method = POST) {
            add_header Content-Type "application/json; charset=utf-8" always;
            return 401 '{"status":"error","code":401,"error":"Недействительный токен кластера или ключ авторизации узла. Доступ запрещен."}';
        }
        return 405;
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
#  ФАЗА 3: УСТАНОВКА 3X-UI, ПИННИНГ XRAY v26.7.28 И БАЗА SQLITE
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 3: Оркестрация 3X-UI, Xray Core v26.7.28 и маршрутизация      ${NC}"
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
    [ -f "$XRAY_EXTRACT_DIR/geoip.dat" ] && cp -f "$XRAY_EXTRACT_DIR/geoip.dat" /usr/local/x-ui/bin/
    [ -f "$XRAY_EXTRACT_DIR/geosite.dat" ] && cp -f "$XRAY_EXTRACT_DIR/geosite.dat" /usr/local/x-ui/bin/
    rm -rf "$XRAY_EXTRACT_DIR"
    ok "Ядро Xray ${TARGET_XRAY_VERSION} зафиксировано в /usr/local/x-ui/bin/."
else
    die "Не найден бинарный файл xray!"
fi

XRAY_BIN="/usr/local/x-ui/bin/xray"
[ -x "$XRAY_BIN" ] || XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"

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
    [ -n "$p" ] || continue
    read -r -a doms_arr <<< "${STEAL_PORT_DOMAINS[$p]:-}"
    doms_joined=$(IFS=,; echo "${doms_arr[*]}")
    STEAL_CONFIG_DATA="${STEAL_CONFIG_DATA}${p}=${doms_joined};"
done

CLASSIC_CONFIG_DATA=""
for cp in "${CLASSIC_PORTS_LIST[@]:-}"; do
    [ -n "$cp" ] || continue
    read -r -a snis_arr <<< "${CLASSIC_PORT_SNIS[$cp]:-}"
    snis_joined=$(IFS=,; echo "${snis_arr[*]}")
    CLASSIC_CONFIG_DATA="${CLASSIC_CONFIG_DATA}${cp}=${snis_joined};"
done

STEAL_DOMAINS_STR="${STEAL_DOMAINS[*]:-}"
export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_CONFIG_DATA
export ENABLE_CLASSIC CLASSIC_CONFIG_DATA ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ENABLE_AWG_V2 AWG_V2_PORT ENABLE_WG_NATIVE WG_NATIVE_PORT ADMIN_USER ADMIN_PASS
export SSL_BASE_DIR VLESS_DECRYPTION VLESS_ENCRYPTION
export STEAL_DOMAINS_STR INSTALL_MODE ENABLE_AGH GEO_PROFILE

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
    "subShowInfo": "false",
    "subJsonEnable": "true",
    "subClashEnable": "true",
    "subRemarkModel": "{{INBOUND}}-{{EMAIL}}|\U0001F4CA{{TRAFFIC}}|\u23F3{{EXP_TIME}}",
    "timeLocation": "Europe/Moscow",
    "trafficResetDay": "1",
    "sessionMaxAge": "3600",
    "trustedProxyCIDRs": "127.0.0.1/32,10.8.1.0/24,10.8.2.0/24,10.8.3.0/24",
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
        if install_mode == "1" or k in ["webListen", "subListen", "subPath", "subURI", "subJsonPath", "subJsonURI", "subClashPath", "subClashURI", "trustedProxyCIDRs", "subJsonAlwaysArray", "subClashAutoDetect"]:
            cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

freedom_final_rules = []
if enable_agh:
    freedom_final_rules.append({"action": "allow", "ip": ["127.0.0.1"], "port": "53"})
freedom_final_rules.append({"action": "allow", "ip": ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24"]})
freedom_final_rules.append({"action": "block", "ip": ["geoip:private"]})
freedom_final_rules.append({"action": "allow"})

routing_rules = [
    {"inboundTag": ["api"], "outboundTag": "api", "type": "field"}
]
if enable_agh:
    routing_rules.append({"ip": ["127.0.0.1"], "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
routing_rules.append({"ip": ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24"], "outboundTag": "direct", "type": "field"})
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
                "timeoutMs": 4000,
                "port": 53
            }
        ],
        "queryStrategy": "UseIPv4",
        "disableCache": False,
        "disableFallback": False,
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
    if install_mode == "1":
        cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(tpl_config),))
else:
    cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(tpl_config),))

test_email = "Test"
test_sub_id = "SUB_Test"
test_uuid = str(uuid.uuid4())
test_password = secrets.token_hex(8)
test_auth = secrets.token_hex(8)
reality_hex_sid = secrets.token_hex(8)

def_r_priv, def_r_pub = gen_reality_keypair()
def_wg_s_priv, def_wg_s_pub = gen_wg_keypair()
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
        if proto == "vless" and "decryption" in s_obj_def:
            final_s["decryption"] = s_obj_def["decryption"]
            final_s["encryption"] = s_obj_def.get("encryption", "")
        if "realitySettings" in final_st:
            rs = final_st["realitySettings"]
            rs["minClientVer"] = "1.0.0"
            rs["spiderX"] = "/"
            if not rs.get("shortIds"): rs["shortIds"] = [reality_hex_sid]
        if proto == "amneziawg" and tag == "in-8443-udp" and "server" in final_s:
            final_s["server"]["contentPaddingAddition"] = "0"
            final_s["server"]["mtu"] = 1360
            final_s["server"]["rekeyAfterTime"] = "300-500"
            final_s["server"]["rekeyTimeout"] = "10-15"
            final_s["server"]["rejectAfterTime"] = "600-900"
            final_s["server"]["keepaliveTimeout"] = "20-25"
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
                "show": False, "xver": 1, "target": "127.0.0.1:9443", "dest": "127.0.0.1:9443",
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
        "xPaddingBytes": "100-500", "xPaddingObfsMode": True, "xPaddingKey": "X-Amz-Meta-Trace",
        "xmux": {"maxConcurrency": "0", "maxConnections": "1-3", "cMaxReuseTimes": "300-600", "hMaxRequestTimes": "600-900", "hMaxReusableSecs": "1800-3000", "hKeepAlivePeriod": 600},
        "enableXmux": True
    },
    "security": "none",
    "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "firefox", "alpn": "h2", "remark": "VLESS xHTTP"}]
}
ib3_id = upsert_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS xHTTP", x_obj, xt_obj)

# 4. Hysteria 2
if os.environ.get("ENABLE_HY2") == "1":
    hp = int(os.environ["HY2_PORT"])
    ssl_dir = os.environ["SSL_BASE_DIR"]
    hy_client = dict(client_reality_dict)
    hy_client.pop("flow", None)
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
        "externalProxy": [{"dest": domain, "port": hp, "forceTls": "tls", "alpn": "h3", "remark": "Hysteria 2"}]
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
    
    a3_h1 = str(secrets.randbelow(2147483647))
    a3_h2 = str(secrets.randbelow(2147483647))
    a3_h3 = str(secrets.randbelow(2147483647))
    a3_h4 = str(secrets.randbelow(2147483647))

    a3_obj = {
        "clients": [a3_client],
        "server": {
            "h1": a3_h1, "h2": a3_h2, "h3": a3_h3, "h4": a3_h4,
            "jc": 4, "jmin": 50, "jmax": 160, "s1": 45, "s2": 60, "s3": 24, "s4": 16,
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
            "jc": 4, "jmin": 50, "jmax": 160, "s1": 45, "s2": 60, "s3": 24, "s4": 16, "mtu": 1360,
            "primaryDns": awg3_dns_prim, "secondaryDns": awg3_dns_sec,
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "subnetCidr": 24, "subnetIp": "10.8.2.0"
        }
    }
    a2t_obj = {"externalProxy": [{"dest": domain, "port": a2p, "remark": "AmneziaWG v2"}]}
    ib6_id = upsert_inbound(a2p, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2", a2_obj, a2t_obj, listen="0.0.0.0")

# 7. Native WireGuard RFC (MTU 1420 / MSS 1380)
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
        "externalProxy": [{"dest": domain, "port": wgp, "remark": "WireGuard Native"}]
    }
    ib7_id = upsert_inbound(wgp, "wireguard", "in-wireguard-native", "WireGuard Native", wg_s_obj, wg_st_obj, listen="0.0.0.0")

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
            "auth": test_auth, "flow": "xtls-rprx-vision", "security": "auto", "reverse": "",
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

def add_host_entry(gid, ib_id, remark, addr, port, sec, sni="", alpn="", fp="", sort_order=0):
    col_candidates = {
        "group_id": gid, "groupId": gid,
        "inbound_id": ib_id, "inboundId": ib_id,
        "sort_order": sort_order, "sortOrder": sort_order,
        "remark": remark, "address": addr, "port": port, "security": sec,
        "sni": sni, "host_header": "", "hostHeader": "", "path": "",
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
        add_host_entry(group_xhttp_uuid, ib3_id, "xHTTP_H2", domain, 443, "tls", sni=domain, alpn=alpn_str, fp="firefox", sort_order=2)

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
#  ФАЗА 4: ФИНАЛЬНЫЙ ЗАМОК (L3 FORWARD, NAT, MSS CLAMPING, UFW)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 4: Сетевой шлюз NAT, TCP MSS Clamping и изоляция UFW          ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

DEFAULT_IF=$(ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || echo "")
if [ -z "$DEFAULT_IF" ]; then
    DEFAULT_IF=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || echo "")
fi
[ -z "$DEFAULT_IF" ] && DEFAULT_IF="eth0"
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
    ufw allow "${WG_NATIVE_PORT}/udp" comment 'WireGuard Native' >/dev/null 2>&1 || true
fi

export ENABLE_HY2_HOP HY2_PORT ENABLE_AWG_V3 ENABLE_AWG_V2 ENABLE_WG_NATIVE DEFAULT_IF
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

nat_rules = ["*nat", ":PREROUTING ACCEPT [0:0]", ":POSTROUTING ACCEPT [0:0]", ":OUTPUT ACCEPT [0:0]"]
if enable_hop:
    nat_rules.append(f"-A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports {hy2_p}")
if awg3:
    nat_rules.append(f"-A POSTROUTING -s 10.8.1.0/24 -o {default_if} -j MASQUERADE")
if awg2:
    nat_rules.append(f"-A POSTROUTING -s 10.8.2.0/24 -o {default_if} -j MASQUERADE")
if wg_nat:
    nat_rules.append(f"-A POSTROUTING -s 10.8.3.0/24 -o {default_if} -j MASQUERADE")
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
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
# END HARDENED MANGLE
"""

final_body = nat_part + content + "\n" + mangle_part + "\n"

with open(rules_file, "w") as f:
    f.write(final_body)
EOF_UFW_PYTHON

DENIED_PORTS=(10443 55443 50443 9443 3000)
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
ok "Фаервол UFW настроен. MSS Clamping (1320/1380) активны."

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ДАШБОРД
# =============================================================
HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT}"
if [ "${ENABLE_HY2_HOP:-0}" -eq 1 ]; then
    HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT},20000-50000"
fi

CRED_FILE="/root/vpn_credentials.txt"
cat << EOF > "$CRED_FILE"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА (Monoscript v3.2 Universal Single-IP)
  ОС: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  Ядро Xray-core: ${DETECTED_XRAY_VER} (Pinned)
  Режим:          $([ "$INSTALL_MODE" = "2" ] && echo "Safe Migration" || echo "Clean Setup")
  Дата:           $(date '+%Y-%m-%d %H:%M:%S')
=====================================================================

[ ВЕБ-ПАНЕЛЬ 3X-UI ]
URL панели:            https://${PRIMARY_DOMAIN}${PANEL_PATH}
$([ "$INSTALL_MODE" = "1" ] && echo "Логин администратора:  ${ADMIN_USER}
Пароль администратора: ${ADMIN_PASS}" || echo "Учетные данные админа: Сохранены из прежней базы")
Внутренний сокет:      127.0.0.1:${PANEL_PORT} (Изолирован)

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
$([ "${ENABLE_WG_NATIVE:-0}" -eq 1 ] && echo "[ NATIVE WIREGUARD RFC ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${WG_NATIVE_PORT}
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
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА В РЕЖИМЕ SINGLE-IP (v3.2)!               ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Панель управления 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  Логин: ${WHITE}${ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
fi
echo
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
echo -e "  Панель AdGuard Home:         ${CYAN}https://${AGH_DOMAIN}/${NC}"
echo -e "  Приватный DoH для роутера:   ${GREEN}https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}${NC}"
echo
fi
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Единая ссылка Base64):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (JSON для Sing-box):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}${NC}"
echo
fi
if [ "${ENABLE_WG_NATIVE:-0}" -eq 1 ]; then
echo -e "  ${BOLD}Чистый Native WireGuard RFC (.conf файл):${NC}"
echo -e "  ${GREEN}/root/wireguard-client.conf${NC} (MTU 1420 / MSS 1380)"
echo
fi
echo -e "  ${WHITE}MSS Clamping:${NC}                ${GREEN}AWG: 1320 | WireGuard: 1380${NC}"
echo -e "  ${WHITE}Сайт-маскировка:${NC}             ${GREEN}DataSphere Enterprise Ultra (3D Decoy v4.0)${NC}"
echo
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${YELLOW}---------------------------------------------------------------------${NC}"
echo -e "${YELLOW}${BOLD}ОБЯЗАТЕЛЬНОЕ ДЕЙСТВИЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "${WHITE}1. Откройте ${BOLD}НОВОЕ${NC} окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).${NC}"
echo -e "${WHITE}2. Выполните команду: ${GREEN}${BOLD}reboot${NC}"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
