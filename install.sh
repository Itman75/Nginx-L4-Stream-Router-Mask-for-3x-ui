#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup Monoscript: Hardened Master Engine v2.1 Universal
# OS Hardening + BBR + Nginx L4 Stream + 3X-UI + Zero-Touch (Production Release)
# Xray v26.7.28 Pinned + Native H2C xHTTP + ML-KEM-768 + Dynamic AGH & DNS
# Smart Situational Flow Preservation + Adaptive Clash/JSON Subscriptions
# ==============================================================================
# Совместимость: Ubuntu 22.04 / 24.04 / 26.04 & Debian 12 / 13
# Режимы: Чистая установка (Clean Install) & Безопасное обновление (Safe Migration)
# ==============================================================================

set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# --------------------------- Цветовая палитра ---------------------------
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[X] $*${NC}" >&2; exit 1; }

trap 'die "Скрипт аварийно прерван на строке $LINENO"' ERR

clear 2>/dev/null || true
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  Hardened Master Engine v2.1 Universal (Production Release)          ${NC}"
echo -e "${CYAN}  Dual-Mode: Clean Setup / Safe Migration + Nginx L4 Native + 3X-UI  ${NC}"
echo -e "${WHITE}  Xray Core v26.7.28 Pinned + Native H2C xHTTP + Smart DNS / Flow     ${NC}"
echo -e "${WHITE}  Поддержка: Ubuntu 22.04/24.04/26.04 & Debian 12/13                  ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

if [ -f /etc/os-release ]; then
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
        die "Скрипт оптимизирован строго под дистрибутивы с поддержкой Nginx Mainline L4 Stream: Ubuntu (22.04+) и Debian (12+). Текущая ОС: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} не поддерживается."
    fi
    ok "Операционная система валидирована: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME)"
else
    die "Не удалось определить параметры текущего дистрибутива ОС."
fi

if [ -d /etc/needrestart/conf.d ]; then
    echo '$nrconf{restart} = "l";' > /etc/needrestart/conf.d/99-disable-auto-restart.conf 2>/dev/null || true
fi

EARLY_TOOLS_MISSING=0
for tool in curl bc dig ip openssl gawk python3 xxd unzip jq sqlite3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        EARLY_TOOLS_MISSING=1
        break
    fi
done

if [ "$EARLY_TOOLS_MISSING" -eq 1 ]; then
    log "Первичная подготовка системных утилит (включая sqlite3 CLI)..."
    apt-get update -q >/dev/null 2>&1 || true
    apt-get install -y curl bc dnsutils bind9-dnsutils iproute2 openssl gawk python3 python3-bcrypt xxd unzip jq sqlite3 bsdextrautils -q >/dev/null 2>&1 || true
    ok "Базовые утилиты готовы к работе."
fi

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 22 ] && [ "$1" -le 65535 ]
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
        if curl -fsSL --connect-timeout 5 -m 120 --retry 1 "$u" -o "$target_file" 2>/dev/null; then
            if [ -s "$target_file" ]; then
                ok "Успешно загружено из: $u"
                return 0
            fi
        fi
        warn "Зеркало недоступно или прервано, переключение на следующее..."
    done
    return 1
}

benchmark_sni() {
    local candidates=("tbank.ru" "gateway.icloud.com" "www.samsung.com" "dl.google.com")
    local best_sni="tbank.ru"
    local min_rtt=999999

    echo -e "${CYAN}[+] Тестирование пула внешних SNI для Classic REALITY...${NC}" >&2
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
    echo -e "${GREEN}[OK]${NC} Выбран оптимальный внешний SNI: ${GREEN}${best_sni}${NC} (${min_rtt} ms)" >&2
    echo -n "$best_sni"
}

# =============================================================
#  ПРОВЕРКА СУЩЕСТВОВАНИЯ БАЗЫ 3X-UI: ВЫБОР РЕЖИМА УСТАНОВКИ
# =============================================================
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
    echo -e "     их UUID, ключей, паролей, статистики и хостов + обновление сетевого стека"
    prompt_default "Выберите режим работы" "2" INSTALL_MODE

    if [ "$INSTALL_MODE" = "2" ]; then
        ok "Активирован режим БЕЗОПАСНОГО ОБНОВЛЕНИЯ (Safe Migration Mode)!"
        log "Создание аварийного бэкапа перед миграцией..."
        systemctl stop x-ui 2>/dev/null || true
        BACKUP_TAR="/root/backup_before_migration_$(date +%F_%H%M%S).tar.gz"
        tar -czvf "$BACKUP_TAR" \
            /etc/x-ui \
            /etc/nginx \
            /etc/letsencrypt \
            /etc/ssl/acme \
            /etc/ufw/before.rules 2>/dev/null || true
        ok "Резервная копия создана: $BACKUP_TAR"
    else
        warn "Выбрана ЧИСТАЯ УСТАНОВКА. Прежние клиенты и ключи будут сброшены!"
    fi
fi

# =============================================================
#  ФАЗА 0: ДЕТЕКЦИЯ СЕТЕВОГО ГЕО-ПРОФИЛЯ СЕРВЕРА
# =============================================================
echo
log "Определение сетевого окружения и геолокации сервера..."
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
echo -e "  1) ${GREEN}[RU] Сервер в РФ${NC} (Яндекс DNS 77.88.8.8, CDN-зеркала GitHub, обход ТСПУ/РКН, DoH over TCP)"
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

# =============================================================
#  ПОШАГОВЫЙ ИНТЕРАКТИВНЫЙ ОПРОСНИК ПАРАМЕТРОВ
# =============================================================
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
    warn "Некорректный формат доменного имени. Попробуйте снова."
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
    read -rp "Введите контактный Email (для регистрации SSL Let's Encrypt): " LE_EMAIL
    LE_EMAIL=$(echo "$LE_EMAIL" | tr -d '[:space:]')
    if [[ -z "$LE_EMAIL" ]] || [[ "$LE_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат email. Введите валидный адрес или нажмите Enter."
done

echo
echo -e "${WHITE}${BOLD}--- ШАГ 2: Системные настройки и безопасность ОС ---${NC}"
prompt_yes_no "Выполнить полное обновление системы (apt upgrade) и очистку?" "y" && DO_SYS_UPGRADE=1 || DO_SYS_UPGRADE=0
prompt_yes_no "Установить расширенные инструменты мониторинга (htop, btop, jq, tmux)?" "y" && INSTALL_EXTRA_UTILS=1 || INSTALL_EXTRA_UTILS=0
prompt_yes_no "Включить TCP BBR и полностью отключить IPv6 (защита от утечек)?" "y" && ENABLE_BBR_IPV6=1 || ENABLE_BBR_IPV6=0
prompt_yes_no "Блокировать входящие ICMP (Ping) запросы в фаерволе?" "n" && BLOCK_PING=1 || BLOCK_PING=0

echo -e "Текущий активный порт SSH: ${GREEN}${SSH_ACTIVE_PORT}${NC}"
if prompt_yes_no "Сменить порт SSH на нестандартный?" "n"; then
    while true; do
        read -rp "Введите новый порт SSH (1024-65535): " CUSTOM_SSH
        if validate_port "$CUSTOM_SSH"; then
            TARGET_SSH_PORT="$CUSTOM_SSH"
            break
        fi
        warn "Недопустимый порт. Введите число в диапазоне 1024-65535."
    done
else
    TARGET_SSH_PORT="$SSH_ACTIVE_PORT"
fi

CHANGE_ROOT_PASS=0
ROOT_PASSWORD=""
if [ "$INSTALL_MODE" = "1" ]; then
    prompt_yes_no "Сменить пароль root?" "n" && CHANGE_ROOT_PASS=1 || CHANGE_ROOT_PASS=0
    if [ "$CHANGE_ROOT_PASS" -eq 1 ]; then
        read -rsp "Введите новый пароль root: " ROOT_PASSWORD; echo
    fi
fi

CREATE_USER=0
NEW_USERNAME=""
NEW_USER_PASS=""
if [ "$INSTALL_MODE" = "1" ]; then
    prompt_yes_no "Создать непривилегированного пользователя с sudo?" "n" && CREATE_USER=1 || CREATE_USER=0
    if [ "$CREATE_USER" -eq 1 ]; then
        read -rp "Введите имя пользователя: " NEW_USERNAME
        read -rsp "Введите пароль для $NEW_USERNAME: " NEW_USER_PASS; echo
    fi
fi

prompt_yes_no "Настроить SSH ключи Ed25519?" "$([ "$INSTALL_MODE" = "2" ] && echo "n" || echo "y")" && SETUP_KEYS=1 || SETUP_KEYS=0

echo
echo -e "${WHITE}${BOLD}--- ШАГ 3: Настройка панели 3X-UI и секретных путей ---${NC}"
prompt_default "Внутренний локальный порт панели 3X-UI" "10443" PANEL_PORT
prompt_default "Секретный URI-путь к веб-панели (без слэшей)" "my-3x-panel" RAW_PATH
validate_path_segment "$RAW_PATH" "URI панели"
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_default "Внутренний порт сервера подписок 3X-UI" "55443" SUB_PORT
prompt_default "Секретный URI-путь подписок (без слэшей)" "my-post-key" RAW_SUB_PATH
validate_path_segment "$RAW_SUB_PATH" "URI подписок"
SUB_PATH="/${RAW_SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"

# Точная динамическая привязка путей подписок из эталонного дампа
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
    ok "В режиме Safe Migration учетные данные администратора панели сохраняются из действующей базы."
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
                    warn "    Необходимо указать как минимум один домен для порта $PORT_VAL!"
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
                    warn "    Необходимо указать как минимум один SNI для порта $PORT_VAL!"
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
        warn "Некорректный формат домена: '$EXTRA_DOM'. Попробуйте снова."
    fi
done

echo
echo -e "${WHITE}${BOLD}--- ШАГ 6: Скоростные UDP VPN туннели ---${NC}"
prompt_yes_no "Установить Hysteria 2 (UDP)?" "y" && ENABLE_HY2=1 || ENABLE_HY2=0
ENABLE_HY2_HOP=0
if [ "$ENABLE_HY2" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для Hysteria 2" "443" HY2_PORT
    echo -e "  ${WHITE}Режим работы портов Hysteria 2:${NC}"
    echo -e "    1) ${GREEN}Одиночный порт :${HY2_PORT}/udp (Классика)${NC}"
    echo -e "    2) ${GREEN}Port Hopping :${HY2_PORT} + диапазон 20000-50000/udp (Защита от троттлинга)${NC}"
    prompt_default "  Выберите вариант (1 или 2)" "2" HY2_MODE_CHOICE
    if [ "$HY2_MODE_CHOICE" = "2" ]; then
        ENABLE_HY2_HOP=1
        ok "  Для Hysteria 2 активирован Port Hopping (диапазон 20000:50000 -> $HY2_PORT)"
    else
        ENABLE_HY2_HOP=0
        ok "  Для Hysteria 2 выбран классический режим (только порт $HY2_PORT)"
    fi
fi

prompt_yes_no "Установить AmneziaWG v3.1 (WG3 — для смартфонов и ПК)?" "y" && ENABLE_AWG_V3=1 || ENABLE_AWG_V3=0
if [ "$ENABLE_AWG_V3" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для AmneziaWG v3.1" "8443" AWG_V3_PORT
fi

prompt_yes_no "Установить AmneziaWG v2.0 / Legacy (для роутеров Keenetic / OpenWrt)?" "y" && ENABLE_AWG_V2=1 || ENABLE_AWG_V2=0
if [ "$ENABLE_AWG_V2" -eq 1 ]; then
    prompt_default "  Внешний UDP-порт для AmneziaWG v2.0" "8444" AWG_V2_PORT
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
echo -e "${WHITE}${BOLD}--- ШАГ 8: Сайт-маскировка и сертификация SSL ---${NC}"
echo -e "Выбор темы маскировочного сайта (Decoy Front):"
echo -e "  1) ${GREEN}DataSphere Analytics Enterprise${NC} (Корпоративный SaaS, динамическая телеметрия ±10%, модальные окна)"
echo -e "  2) ${GREEN}CosmosCloud NextGen${NC} (Облачный диск, логотип, сессии)"
echo -e "  3) Стандартная заглушка Nginx (Welcome to nginx)"
prompt_default "Ваш выбор" "1" DECOY_MODE

echo
echo -e "Метод выпуска SSL-сертификатов:"
echo -e "  1) ${GREEN}Нативный Certbot HTTP-01 (Рекомендуется — системный APT без Snapd)${NC}"
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
#  ФАЗА 1: СИСТЕМНЫЙ ХАРДЕНИНГ (ОС, BBR, NO IPV6, SSH, FAIL2BAN)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 1: Системный Hardening ОС, TCP BBR и защита SSH               ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

log "Обновление пакетных репозиториев..."
apt-get update -q

if [ "${DO_SYS_UPGRADE:-0}" -eq 1 ]; then
    log "Полное обновление пакетов системы (apt upgrade)..."
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y -q
    apt-get autoclean -y -q
fi

log "Установка системного набора утилит (включая sqlite3 CLI)..."
CORE_PKGS=(
    curl wget bash sudo systemd openssl gawk lsb-release gnupg dnsutils bind9-dnsutils
    socat cron ufw iptables iproute2 tar apache2-utils fail2ban python3 python3-systemd
    python3-bcrypt ca-certificates build-essential jq tmux net-tools bc xxd unzip sqlite3 bsdextrautils
)
apt-get install -y "${CORE_PKGS[@]}" -q || true

if [ "${INSTALL_EXTRA_UTILS:-0}" -eq 1 ]; then
    apt-get install -y htop iperf3 iftop tcpdump mtr-tiny ncdu vnstat openssh-client -q || true
    apt-get install -y btop -q 2>/dev/null || true
fi
ok "Системные утилиты установлены."

log "Настройка TCP BBR, fq, сокетов somaxconn и отключение IPv6..."
modprobe tcp_bbr 2>/dev/null || true
mkdir -p /etc/sysctl.d/
cat << 'EOF' > /etc/sysctl.d/99-hardened-network.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_tw_buckets = 524288
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 212992
net.core.wmem_default = 212992
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 131072 16777216
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
vm.swappiness = 10
fs.file-max = 2097152
net.ipv4.tcp_notsent_lowat = 16384
EOF
sysctl --system >/dev/null 2>&1 || true

IS_LXC=$(systemd-detect-virt 2>/dev/null | grep -q "lxc" && echo "1" || echo "0")
if [ "$IS_LXC" -eq 0 ] && [ -f /etc/default/grub ] && ! grep -q "ipv6.disable=1" /etc/default/grub; then
    cp /etc/default/grub /etc/default/grub.bak 2>/dev/null || true
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 /' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    update-grub >/dev/null 2>&1 || grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
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
ok "Ядро и лимиты дескрипторов успешно оптимизированы."

# Настройка пользователей и SSH
log "Настройка параметров безопасности SSH и учётных записей..."
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
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
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

if [ "$KEYS_APPLIED" -eq 1 ] && prompt_yes_no "Отключить вход по паролю SSH?" "n"; then
    cat << 'EOF' >> /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
EOF
fi

mkdir -p /run/sshd
if /usr/sbin/sshd -t; then
    systemctl restart "$SSH_SERVICE.service" || true
    ok "Служба SSH перезапущена на порту $TARGET_SSH_PORT."
else
    warn "Ошибка проверки конфигурации SSH! Откат изменений."
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
#  ФАЗА 2: ВНЕШНИЙ ШЛЮЗ, SSL И МАСКИРОВКА (NGINX MAINLINE + ADGUARD HOME DOH)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 2: Внешний шлюз Nginx Mainline, SSL и AdGuard Home DoH        ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

log "Превентивное открытие портов HTTP/HTTPS в UFW..."
ufw allow 80/tcp comment 'HTTP ACME' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS L4 Router' >/dev/null 2>&1 || true

log "Pre-flight проверка DNS A-записей для всех собственных доменов..."
WAN_IP=$(curl -s4 --connect-timeout 4 icanhazip.com || curl -s4 --connect-timeout 4 ifconfig.me || echo "")
if [ -n "$WAN_IP" ]; then
    for dom in "${ALL_DOMAINS[@]}"; do
        resolved_ip=$(dig +short "$dom" @77.88.8.8 2>/dev/null | tail -n1 || echo "")
        [ -z "$resolved_ip" ] && resolved_ip=$(dig +short "$dom" @8.8.8.8 2>/dev/null | tail -n1 || echo "")
        [ -z "$resolved_ip" ] && resolved_ip=$(getent ahosts "$dom" 2>/dev/null | awk '{print $1}' | head -n1 || echo "")
        if [ -z "$resolved_ip" ]; then
            warn "Домен $dom пока не резолвится в IP. Убедитесь, что в Cloudflare включен режим DNS-Only."
            prompt_yes_no "Продолжить установку SSL?" "y" || die "Установка отменена пользователем."
        elif [ "$resolved_ip" != "$WAN_IP" ]; then
            warn "Несовпадение IP: $dom указывает на $resolved_ip, а IP сервера: $WAN_IP."
            prompt_yes_no "Продолжить установку SSL?" "y" || die "Установка отменена пользователем."
        else
            ok "DNS проверен: $dom -> $WAN_IP"
        fi
    done
fi

log "Подключение официального Nginx Mainline для $OS_ID ($OS_CODENAME)..."
mkdir -p /usr/share/keyrings
curl -fsSL --connect-timeout 5 https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes 2>/dev/null || true

systemctl stop nginx 2>/dev/null || true

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/$OS_ID $OS_CODENAME nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

apt-get update -q
apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx

systemctl daemon-reload
systemctl reset-failed nginx.service 2>/dev/null || true

NGINX_USER="nginx"
id -u nginx >/dev/null 2>&1 || NGINX_USER="www-data"

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p /var/cache/nginx /var/www/mirror /var/www/proxy_temp /etc/nginx/stream.d /etc/nginx/conf.d

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp
chmod 755 "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp

rm -rf /etc/nginx/conf.d/* /etc/nginx/stream.d/*

cat << EOF > "/etc/nginx/conf.d/00-acme.conf"
server {
    listen 80;
    server_name ${ALL_DOMAINS[*]};
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ { root $WEBROOT; try_files \$uri =404; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
nginx -t || die "Ошибка конфигурации стартового ACME сервера Nginx."
systemctl restart nginx

# Выпуск или переиспользование существующих SSL-сертификатов
if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Настройка Certbot через нативные системные пакеты APT (без Snapd)..."
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
            ok "Сертификат для $dom уже существует в системе. Пропуск повторного выпуска (Safe Mode)."
            continue
        fi

        log "Выпуск сертификата для $dom..."
        certbot_email_flag="--register-unsafely-without-email"
        [ -n "$LE_EMAIL" ] && certbot_email_flag="--email $LE_EMAIL"

        if certbot certonly --webroot -w "$WEBROOT" --cert-name "$dom" --expand --non-interactive --agree-tos $certbot_email_flag -d "$dom"; then
            ok "Сертификат для $dom получен: /etc/letsencrypt/live/$dom/"
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
    log "Выпуск SSL через acme.sh (Cloudflare DNS-01)..."
    curl -s https://get.acme.sh | sh -s email="${LE_EMAIL:-admin@$PRIMARY_DOMAIN}"
    _ACME="${HOME:-/root}/.acme.sh/acme.sh"
    chmod +x "$_ACME"
    "$_ACME" --register-account -m "${LE_EMAIL:-admin@$PRIMARY_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p /etc/ssl/acme && chmod 755 /etc/ssl /etc/ssl/acme

    for dom in "${ALL_DOMAINS[@]}"; do
        if [ -f "/etc/ssl/acme/$dom/fullchain.pem" ]; then
            ok "Сертификат для $dom уже существует в /etc/ssl/acme/. Пропуск (Safe Mode)."
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

# Установка AdGuard Home DoH
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    log "Установка AdGuard Home (DoH + Split-DNS)..."
    apt-get install -y systemd-resolved -q >/dev/null 2>&1 || true
    mkdir -p /etc/systemd/resolved.conf.d
    
    if [ "$GEO_PROFILE" = "1" ]; then
        cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard.conf
[Resolve]
DNS=77.88.8.8 77.88.8.1 8.8.8.8
FallbackDNS=77.88.8.8
DNSStubListener=no
EOF
    else
        cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8 9.9.9.9
FallbackDNS=1.1.1.1
DNSStubListener=no
EOF
    fi
    systemctl restart systemd-resolved || true
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true

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
            "https://ghfast.top/https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
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

    # Защита от затирания существующего AdGuardHome.yaml в режиме миграции
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
  disallowed_clients: []
  blocked_hosts: []
tls:
  enabled: false
  allow_unencrypted_doh: true
schema_version: 28
EOF
    else
        ok "Существующая конфигурация AdGuard Home (/opt/AdGuardHome/AdGuardHome.yaml) сохранена."
    fi

    /opt/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || true
    systemctl restart AdGuardHome || true
    ok "AdGuard Home DoH активен на 127.0.0.1:53 (Панель: 127.0.0.1:3000)."
fi

# =============================================================
#  ВЕБ-МАСКИРОВКА И MOCK REST API
# =============================================================
log "Генерация выбранной веб-маскировки (1/2) и Mock REST API..."

if [ "$DECOY_MODE" = "1" ]; then
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DataSphere Analytics — Платформа распределенных данных</title>
    <style>
        :root {
            --bg: #131314;
            --surface: #1e1f20;
            --surface-card: #1e1f20;
            --border: rgba(255, 255, 255, 0.08);
            --accent: #a8c7fa;
            --accent-purple: #c58af9;
            --text: #e3e3e3;
            --text-muted: #9aa0a6;
            --success: #81c995;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Google Sans', 'Product Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background-color: var(--bg);
            background-image: 
                radial-gradient(circle at 50% -10%, rgba(66, 133, 244, 0.18) 0%, rgba(155, 114, 207, 0.1) 40%, rgba(217, 101, 112, 0.04) 65%, transparent 80%),
                var(--bg);
            color: var(--text); line-height: 1.6; overflow-x: hidden; min-height: 100vh;
        }
        header {
            display: flex; justify-content: space-between; align-items: center; padding: 18px 6%;
            border-bottom: 1px solid var(--border); backdrop-filter: blur(20px);
            position: sticky; top: 0; z-index: 50; background: rgba(19, 19, 20, 0.8);
        }
        .logo { font-size: 21px; font-weight: 700; display: flex; align-items: center; gap: 10px; color: #fff; letter-spacing: -0.5px; }
        .btn {
            background: var(--surface-card); border: 1px solid var(--border); color: var(--text);
            padding: 10px 22px; border-radius: 999px; font-size: 14px; font-weight: 600; cursor: pointer;
            transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
            display: inline-flex; align-items: center; justify-content: center; gap: 8px;
            box-shadow: 0 4px 14px rgba(0, 0, 0, 0.2);
        }
        .btn:hover { 
            transform: translateY(-1px); border-color: rgba(168, 199, 250, 0.4); 
            background: #242628; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4); 
        }
        .btn-outline {
            background: var(--surface-card); border: 1px solid var(--border); color: var(--text);
            box-shadow: none; border-radius: 999px;
        }
        .btn-outline:hover { background: #242628; border-color: rgba(168, 199, 250, 0.4); }
        .hero { text-align: center; padding: 90px 20px 70px; max-width: 900px; margin: 0 auto; }
        .badge {
            display: inline-flex; align-items: center; gap: 8px; padding: 6px 16px;
            background: var(--surface-card); border: 1px solid var(--border);
            border-radius: 999px; font-size: 13px; font-weight: 500; color: var(--accent); margin-bottom: 24px;
        }
        .badge-dot { width: 7px; height: 7px; background: var(--success); border-radius: 50%; box-shadow: 0 0 8px var(--success); }
        .hero h1 {
            font-size: clamp(34px, 5vw, 54px); font-weight: 700; line-height: 1.18; margin-bottom: 22px;
            letter-spacing: -0.8px; color: #d1d5db; 
        }
        .hero p { font-size: clamp(16px, 2vw, 18px); color: var(--text-muted); margin: 0 auto 36px; line-height: 1.65; max-width: 720px; }
        .hero-actions { display: flex; gap: 14px; justify-content: center; flex-wrap: wrap; }
        .stats-bar { display: flex; justify-content: center; gap: 40px; margin-top: 60px; padding-top: 40px; border-top: 1px solid var(--border); flex-wrap: wrap; }
        .stat-item h4 { font-size: 28px; font-weight: 700; color: #fff; letter-spacing: -0.5px; }
        .stat-item p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
        .features { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; max-width: 1100px; margin: 40px auto 90px; padding: 0 6%; }
        .feature-card {
            background: var(--surface-card); padding: 32px 28px; border-radius: 24px; border: 1px solid var(--border);
            backdrop-filter: blur(12px); transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1); cursor: pointer;
            user-select: none; display: flex; flex-direction: column; justify-content: space-between;
        }
        .feature-card:hover {
            transform: translateY(-4px); border-color: rgba(168, 199, 250, 0.4); background: #242628;
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45), 0 0 20px rgba(155, 114, 207, 0.12);
        }
        .feature-card:active { transform: scale(0.98); }
        .feature-card .icon-box {
            width: 44px; height: 44px; background: rgba(168, 199, 250, 0.08); border: 1px solid rgba(168, 199, 250, 0.18);
            border-radius: 14px; display: flex; align-items: center; justify-content: center; color: var(--accent); margin-bottom: 20px;
        }
        .feature-card h3 { font-size: 18px; font-weight: 600; margin-bottom: 10px; color: #fff; }
        .feature-card p { color: var(--text-muted); line-height: 1.55; font-size: 14px; margin-bottom: 16px; }
        .card-action {
            display: inline-flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600;
            color: var(--accent); transition: gap 0.2s ease;
        }
        .feature-card:hover .card-action { gap: 10px; color: #d3e3fd; }
        .modal-overlay {
            position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(5, 7, 10, 0.85);
            backdrop-filter: blur(16px); display: flex; align-items: center; justify-content: center;
            padding: 20px; z-index: 100; opacity: 0; visibility: hidden; transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }
        .modal-overlay.active { opacity: 1; visibility: visible; }
        .modal-card {
            background: var(--surface); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 28px;
            width: 100%; max-width: 480px; padding: 36px 32px; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7);
        }
        .modal-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 20px; }
        .modal-header h2 { font-size: 21px; font-weight: 700; color: #fff; }
        .modal-header p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
        .modal-close { background: transparent; border: none; color: var(--text-muted); cursor: pointer; padding: 4px; }
        .modal-close:hover { color: #fff; }
        .form-group { margin-bottom: 18px; text-align: left; }
        .form-group label { display: block; font-size: 13px; font-weight: 500; color: #c4c7c5; margin-bottom: 6px; }
        .form-control {
            width: 100%; padding: 13px 16px; background: #131314; border: 1px solid var(--border);
            border-radius: 14px; color: #fff; font-size: 14px; outline: none; transition: all 0.2s ease;
        }
        .form-control:focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(168, 199, 250, 0.2); }
        .alert-box {
            background: rgba(239, 68, 68, 0.12); border: 1px solid rgba(239, 68, 68, 0.3); color: #fca5a5;
            padding: 12px 14px; border-radius: 12px; font-size: 13px; margin-bottom: 20px; display: none; align-items: center; gap: 10px;
        }
        .spinner { width: 18px; height: 18px; border: 2px solid rgba(255, 255, 255, 0.3); border-top: 2px solid #fff; border-radius: 50%; animation: spin 0.8s linear infinite; }
        footer { text-align: center; padding: 40px 20px; color: var(--text-muted); font-size: 13px; border-top: 1px solid var(--border); }
        @keyframes spin { 100% { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <header>
        <div class="logo">
            <svg viewBox="0 0 100 100" width="26" height="26" xmlns="http://www.w3.org/2000/svg">
                <clipPath id="circleMask"><circle cx="50" cy="50" r="48"/></clipPath>
                <g clip-path="url(#circleMask)">
                    <rect x="0" y="0" width="100" height="100" fill="#008dd5"/>
                    <polygon points="50,-8 100,21 100,79 50,108 0,79 0,21" fill="#ffffff"/>
                    <polygon points="50,6.7 87.5,28.35 87.5,71.65 50,93.3 12.5,71.65 12.5,28.35" fill="#66a88f"/>
                    <polygon points="50,28.35 68.75,39.17 68.75,60.83 50,71.65 31.25,60.83 31.25,39.17" fill="#e7ab21"/>
                    <g stroke="#000000" stroke-width="4" stroke-linecap="round">
                        <line x1="-10" y1="6.7" x2="110" y2="6.7"/>
                        <line x1="-10" y1="28.35" x2="110" y2="28.35"/>
                        <line x1="-10" y1="50" x2="110" y2="50"/>
                        <line x1="-10" y1="71.65" x2="110" y2="71.65"/>
                        <line x1="-10" y1="93.3" x2="110" y2="93.3"/>
                        <line x1="15.36" y1="-10" x2="84.64" y2="110"/>
                        <line x1="40.36" y1="-10" x2="109.64" y2="110"/>
                        <line x1="-9.64" y1="-10" x2="59.64" y2="110"/>
                        <line x1="84.64" y1="-10" x2="15.36" y2="110"/>
                        <line x1="109.64" y1="-10" x2="40.36" y2="110"/>
                        <line x1="59.64" y1="-10" x2="-9.64" y2="110"/>
                    </g>
                </g>
                <circle cx="50" cy="50" r="48" fill="none" stroke="#000000" stroke-width="5"/>
            </svg>
            <span>DataSphere</span>
        </div>
        <button class="btn" onclick="openAuthModal('Вход в Консоль')">Консоль</button>
    </header>
    <main>
        <section class="hero">
            <div class="badge"><span class="badge-dot"></span><span>DataSphere Cloud Engine v3.14 — Доступность <span id="heroSla">99.998%</span></span></div>
            <h1>Инфраструктура распределения данных нового поколения</h1>
            <p>Корпоративная аналитическая среда с аппаратным ускорением сетевого стека, сквозным TLS 1.3 шифрованием и Anycast-маршрутизацией узлов.</p>
            <div class="hero-actions">
                <button class="btn" style="padding: 13px 28px; font-size: 15px;" onclick="openAuthModal('Подключение вычислительного узла')">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" width="16" height="16"><path d="M5 12h14M12 5l7 7-7 7"/></svg>
                    Подключить узел
                </button>
                <button class="btn btn-outline" style="padding: 13px 28px; font-size: 15px;" onclick="fetchClusterStatus()">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" width="16" height="16"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
                    Статус сети
                </button>
            </div>
            <div class="stats-bar">
                <div class="stat-item"><h4 id="heroLatency">&lt; 1.2 ms</h4><p>Средняя задержка ядра</p></div>
                <div class="stat-item"><h4 id="heroBandwidth">100 Gbps</h4><p>Пропускная способность</p></div>
                <div class="stat-item"><h4>TLS 1.3 / H2</h4><p>Аппаратное шифрование</p></div>
            </div>
        </section>
        <section class="features">
            <div class="feature-card" onclick="openDetailModal('crypto')">
                <div class="icon-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="22" height="22"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></div>
                <h3>Сквозное квантовое шифрование</h3>
                <p>Передача пакетов осуществляется с аппаратным криптоускорением TLS 1.3 и защитой от перехвата на пограничных маршрутизаторах.</p>
                <span class="card-action">Аудит протоколов &rarr;</span>
            </div>
            <div class="feature-card" onclick="openDetailModal('telemetry')">
                <div class="icon-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="22" height="22"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg></div>
                <h3>Распределённая телеметрия</h3>
                <p>Многопоточный конвейер аналитики агрегирует метрики узлов в реальном времени с нулевой деградацией пропускной способности.</p>
                <span class="card-action">Anycast-магистраль &rarr;</span>
            </div>
            <div class="feature-card" onclick="openDetailModal('ipc')">
                <div class="icon-box"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="22" height="22"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2zM22 6l-10 7L2 6"/></svg></div>
                <h3>Изоляция сокетов IPC</h3>
                <p>Все процессы ввода-вывода распределяются по энергонезависимым сегментам оперативной памяти с прямой маршрутизацией через Unix-сокеты.</p>
                <span class="card-action">In-Memory конвейер &rarr;</span>
            </div>
        </section>
    </main>

    <div id="authModal" class="modal-overlay" onclick="if(event.target===this)closeAuthModal()">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="modalTitle">Авторизация в DataSphere</h2>
                    <p>Введите учётные данные для доступа к консоли</p>
                </div>
                <button class="modal-close" onclick="closeAuthModal()">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="errorAlert" class="alert-box">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="18" height="18"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/></svg>
                <span id="errorMsg">Ошибка аутентификации</span>
            </div>
            <form id="authForm" onsubmit="handleDataSphereAuth(event)">
                <div class="form-group">
                    <label>Идентификатор узла / Email</label>
                    <input type="text" id="dsUser" class="form-control" placeholder="cluster-admin@datasphere.cloud" required autocomplete="username">
                </div>
                <div class="form-group">
                    <label>API Token / Ключ</label>
                    <input type="password" id="dsKey" class="form-control" placeholder="••••••••••••••••" required autocomplete="current-password">
                </div>
                <button type="submit" id="submitBtn" class="btn" style="width: 100%; height: 46px; margin-top: 10px;">Подключиться к кластеру</button>
            </form>
        </div>
    </div>

    <div id="detailModal" class="modal-overlay" onclick="if(event.target===this)closeDetailModal()">
        <div class="modal-card" style="max-width: 500px;">
            <div class="modal-header">
                <div>
                    <h2 id="detailTitle" style="font-size: 20px; color: #fff;">Архитектурный узел</h2>
                    <p id="detailSubtitle" style="font-size: 13px; color: var(--text-muted); margin-top: 4px;">Спецификация и статус безопасности подсистемы</p>
                </div>
                <button class="modal-close" onclick="closeDetailModal()">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="detailContent" style="font-size: 14px; line-height: 1.6; color: #cbd5e1;"></div>
            <button class="btn" style="width: 100%; height: 44px; margin-top: 24px;" onclick="closeDetailModal()">Понятно</button>
        </div>
    </div>

    <footer>&copy; 2026 DataSphere Cloud Systems Inc. Платформа распределенной аналитики и защиты данных.</footer>

    <script>
        function randVar(base, pct = 10, dec = 0) {
            const delta = base * (pct / 100);
            const val = base + (Math.random() * 2 - 1) * delta;
            return dec > 0 ? val.toFixed(dec) : Math.round(val);
        }

        window.addEventListener('DOMContentLoaded', () => {
            const dynLat = randVar(1.18, 10, 1);
            const dynBw = randVar(99.4, 8, 1);
            const dynSla = (99.995 + Math.random() * 0.004).toFixed(3);
            document.getElementById("heroLatency").innerText = "< " + dynLat + " ms";
            document.getElementById("heroBandwidth").innerText = dynBw + " Gbps";
            document.getElementById("heroSla").innerText = dynSla + "%";
        });

        function getDynamicData() {
            const nodes = randVar(148, 10, 0);
            const rtt = randVar(1.15, 10, 1);
            const bus = randVar(0.048, 10, 2);
            const sla = (99.995 + Math.random() * 0.004).toFixed(3);

            return {
                crypto: {
                    title: "Сквозное шифрование (Data-in-Transit)",
                    subtitle: "Корпоративный криптографический аудит",
                    content: `
                        <div style="background: rgba(168, 199, 250, 0.08); border: 1px solid rgba(168, 199, 250, 0.2); padding: 14px; border-radius: 14px; margin-bottom: 16px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                <span style="font-weight:600; color:#fff;">Статус криптомодуля:</span>
                                <span style="color:#81c995; font-size:12px; font-weight:700;">● CERTIFIED</span>
                            </div>
                            <p style="font-size:13px; color:#9aa0a6; margin:0;">Аппаратная терминация сессий с защитой от компрометации закрытых ключей.</p>
                        </div>
                        <ul style="list-style:none; padding:0; margin:0; display:flex; flex-direction:column; gap:10px;">
                            <li style="display:flex; gap:10px; align-items:flex-start;">
                                <svg viewBox="0 0 24 24" fill="none" stroke="#81c995" stroke-width="2.5" width="18" height="18" style="flex-shrink:0; margin-top:2px;"><polyline points="20 6 9 17 4 12"/></svg>
                                <span><strong>Протоколы шифрования:</strong> TLS 1.3 (RFC 8446) / ChaCha20-Poly1305 & AES-256-GCM.</span>
                            </li>
                            <li style="display:flex; gap:10px; align-items:flex-start;">
                                <svg viewBox="0 0 24 24" fill="none" stroke="#81c995" stroke-width="2.5" width="18" height="18" style="flex-shrink:0; margin-top:2px;"><polyline points="20 6 9 17 4 12"/></svg>
                                <span><strong>Perfect Forward Secrecy:</strong> Ротация сессионных ключей на базе эллиптических кривых X25519.</span>
                            </li>
                        </ul>
                    `
                },
                telemetry: {
                    title: "Распределённая телеметрия Anycast",
                    subtitle: "Мониторинг магистральной сети и доступность SLA",
                    content: `
                        <div style="background: rgba(129, 201, 149, 0.08); border: 1px solid rgba(129, 201, 149, 0.2); padding: 14px; border-radius: 14px; margin-bottom: 16px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                <span style="font-weight:600; color:#fff;">Доступность SLA:</span>
                                <span style="color:#81c995; font-size:12px; font-weight:700;">` + sla + `% ACTIVE</span>
                            </div>
                            <p style="font-size:13px; color:#9aa0a6; margin:0;">Многопоточный Anycast-конвейер маршрутизации трафика к ближайшему POP-узлу.</p>
                        </div>
                        <ul style="list-style:none; padding:0; margin:0; display:flex; flex-direction:column; gap:10px;">
                            <li style="display:flex; gap:10px; align-items:flex-start;">
                                <svg viewBox="0 0 24 24" fill="none" stroke="#81c995" stroke-width="2.5" width="18" height="18" style="flex-shrink:0; margin-top:2px;"><polyline points="20 6 9 17 4 12"/></svg>
                                <span><strong>Глобальная связность:</strong> ` + nodes + ` активных пограничных узлов Anycast.</span>
                            </li>
                            <li style="display:flex; gap:10px; align-items:flex-start;">
                                <svg viewBox="0 0 24 24" fill="none" stroke="#81c995" stroke-width="2.5" width="18" height="18" style="flex-shrink:0; margin-top:2px;"><polyline points="20 6 9 17 4 12"/></svg>
                                <span><strong>RTT задержка:</strong> Маршрутизация на границе датацентра с откликом &lt; ` + rtt + ` ms.</span>
                            </li>
                        </ul>
                    `
                },
                ipc: {
                    title: "Высокоскоростная IPC-обработка",
                    subtitle: "In-Memory конвейер и архитектура Zero-Copy",
                    content: `
                        <div style="background: rgba(197, 138, 249, 0.08); border: 1px solid rgba(197, 138, 249, 0.2); padding: 14px; border-radius: 14px; margin-bottom: 16px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                                <span style="font-weight:600; color:#fff;">Подсистема ввода-вывода:</span>
                                <span style="color:#c58af9; font-size:12px; font-weight:700;">● ZERO-COPY RAM</span>
                            </div>
                            <p style="font-size:13px; color:#9aa0a6; margin:0;">Изолированные очереди процессов в памяти без блокировок файлового хранилища.</p>
                        </div>
                        <ul style="list-style:none; padding:0; margin:0; display:flex; flex-direction:column; gap:10px;">
                            <li style="display:flex; gap:10px; align-items:flex-start;">
                                <svg viewBox="0 0 24 24" fill="none" stroke="#81c995" stroke-width="2.5" width="18" height="18" style="flex-shrink:0; margin-top:2px;"><polyline points="20 6 9 17 4 12"/></svg>
                                <span><strong>Задержка шины:</strong> Менее ` + bus + ` ms при мультиплексировании стримов.</span>
                            </li>
                        </ul>
                    `
                }
            };
        }

        function openDetailModal(type) {
            const data = getDynamicData()[type];
            if (!data) return;
            document.getElementById("detailTitle").innerText = data.title;
            document.getElementById("detailSubtitle").innerText = data.subtitle;
            document.getElementById("detailContent").innerHTML = data.content;
            document.getElementById("detailModal").classList.add("active");
        }

        function closeDetailModal() {
            document.getElementById("detailModal").classList.remove("active");
        }

        function openAuthModal(title) {
            document.getElementById("modalTitle").innerText = title || "Авторизация в DataSphere";
            document.getElementById("errorAlert").style.display = "none";
            document.getElementById("authModal").classList.add("active");
            document.getElementById("dsUser").focus();
        }

        function closeAuthModal() { document.getElementById("authModal").classList.remove("active"); }

        async function fetchClusterStatus() {
            try {
                const res = await fetch("/api/v1/datasphere/status");
                const data = await res.json();
                const curNodes = randVar(data.nodes_active || 148, 10, 0);
                const curSla = (99.995 + Math.random() * 0.004).toFixed(3);
                alert("Статус кластера DataSphere: " + (data.status || "online") + "\nАктивных Anycast-узлов: " + curNodes + "\nSLA: " + curSla + "%");
            } catch(e) { openAuthModal("Мониторинг кластера (Требуется ключ)"); }
        }

        async function handleDataSphereAuth(e) {
            e.preventDefault();
            const btn = document.getElementById("submitBtn"), errBox = document.getElementById("errorAlert"), errText = document.getElementById("errorMsg");
            errBox.style.display = "none"; btn.disabled = true; btn.innerHTML = '<div class="spinner"></div>';
            try {
                const response = await fetch("/api/v1/datasphere/auth", {
                    method: "POST", headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ principal: document.getElementById("dsUser").value, secret: document.getElementById("dsKey").value })
                });
                const result = await response.json();
                errText.innerText = result.error || "Недействительный токен кластера или ключ авторизации узла. Доступ запрещен.";
                errBox.style.display = "flex";
            } catch (err) {
                errText.innerText = "Ошибка защищенного соединения с контроллером кластера.";
                errBox.style.display = "flex";
            } finally {
                btn.disabled = false; btn.innerHTML = "Подключиться к кластеру";
            }
        }

        document.cookie = "datasphere_session=" + Math.random().toString(36).substring(2) + "; path=/; Secure; SameSite=Lax";
    </script>
</body>
</html>
EOF

elif [ "$DECOY_MODE" = "2" ]; then
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
                    body: JSON.stringify({ user: document.getElementById("user").value, pass: document.getElementById("pass").value })
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

    log "Загрузка графического логотипа Cosmos Cloud..."
    curl -fsSL --connect-timeout 8 "https://raw.githubusercontent.com/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui/main/assets/logo.webp" -o "$WEBROOT/logo.webp" 2>/dev/null || \
    curl -fsSL --connect-timeout 8 "https://cdn.jsdelivr.net/gh/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui@main/assets/logo.webp" -o "$WEBROOT/logo.webp" 2>/dev/null || true

    if [ -f "$WEBROOT/logo.webp" ]; then
        magic_riff=$(head -c 4 "$WEBROOT/logo.webp" | tr -d '\0' || true)
        magic_webp=$(dd if="$WEBROOT/logo.webp" bs=1 skip=8 count=4 status=none 2>/dev/null | tr -d '\0' || true)
        if [[ "$magic_riff" != "RIFF" || "$magic_webp" != "WEBP" ]]; then
            rm -f "$WEBROOT/logo.webp"
        fi
    fi
else
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html><html><head><title>Welcome to nginx!</title><style>body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }</style></head><body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working.</p></body></html>
EOF
fi

cat << 'EOF' > /var/www/html/404.html
<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body></html>
EOF
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"
chmod 644 "$WEBROOT"/*.html

DECOY_LOCATION_BLOCKS="
    add_header X-DataSphere-Engine \"v3.14.8-enterprise\" always;

    location ~ ^/(api/v1/datasphere/status|status)\$ {
        default_type application/json;
        return 200 '{\"status\":\"online\",\"cluster\":\"datasphere-eu-central\",\"nodes_active\":148,\"telemetry_rate\":\"99.998%\",\"version\":\"3.14.8\"}';
    }

    location = /api/v1/datasphere/auth {
        if (\$request_method = POST) {
            add_header Content-Type \"application/json; charset=utf-8\" always;
            return 401 '{\"status\":\"error\",\"code\":401,\"error\":\"Недействительный токен кластера или ключ авторизации узла. Доступ запрещен.\"}';
        }
        return 405;
    }

    location = /api/v1/auth/login {
        if (\$request_method = POST) {
            add_header Content-Type \"application/json; charset=utf-8\" always;
            return 401 '{\"error\":\"Wrong nickname or password.\",\"code\":401}';
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
        add_header Cache-Control \"public, max-age=604800, immutable\" always;
        try_files \$uri =404;
    }

    location / {
        return 404;
    }
"

# -------------------------------------------------------------
# КОНФИГУРАЦИЯ NGINX MAINLINE (L4 STREAM + L7 NATIVE H2C)
# -------------------------------------------------------------
log "Сборка конфигурации Nginx Mainline (Stream L4 + HTTP/2 Native H2C Engine)..."
rm -f /etc/nginx/conf.d/00-acme.conf

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
    resolver 77.88.8.8 1.1.1.1 ipv6=off valid=300s;

    # Оптимизация окна и стриминга HTTP/2 для устранения просадок больших потоков
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

server {
    listen 8443 backlog=65535 reuseport;
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
    location ^~ /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl default_server proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl default_server proxy_protocol;
    server_name _;
    ssl_reject_handshake on;
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

    if (\$badbot) { return 404; }

    location = ${PANEL_PATH%/} { return 301 ${PANEL_PATH}; }
    location ^~ ${PANEL_PATH} {
        limit_req zone=panel burst=40 delay=20;
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location ~* ^/(sub|json|clash)/ {
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_PATH} {
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_JSON_PATH} {
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_CLASH_PATH} {
        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }

    # Полнодуплексный H2C xHTTP стрим (Матчинг URI как со слэшем, так и без)
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

    $DECOY_LOCATION_BLOCKS
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
        proxy_set_header Connection "";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto https;
        proxy_buffering off;
    }

    location / {
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

for ((i=1; i<${#ALL_DOMAINS[@]}; i++)); do
    ext_dom="${ALL_DOMAINS[$i]}"
    if [ "$ext_dom" != "$PRIMARY_DOMAIN" ] && [ "$ext_dom" != "${AGH_DOMAIN:-}" ] && [ -f "${SSL_BASE_DIR}/$ext_dom/fullchain.pem" ]; then
        cat << EOF > "/etc/nginx/conf.d/02-${ext_dom}.conf"
server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $ext_dom;

    ssl_certificate ${SSL_BASE_DIR}/$ext_dom/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$ext_dom/privkey.pem;

    $DECOY_LOCATION_BLOCKS

    location ^~ ${PANEL_PATH} {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$http_host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
    location ~* ^/(sub|json|clash)/ {
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_PATH} {
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_JSON_PATH} {
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_http_version 1.1;
    }
    location ^~ ${SUB_CLASH_PATH} {
        proxy_pass http://127.0.0.1:$SUB_PORT;
        proxy_set_header Host \$http_host;
        proxy_http_version 1.1;
    }
}
EOF
    fi
done

nginx -t || die "Критическая ошибка синтаксиса Nginx!"
systemctl restart nginx
ok "Внешний шлюз Nginx Mainline успешно запущен."

# =============================================================
#  ФАЗА 3: УСТАНОВКА 3X-UI, ПИННИНГ XRAY v26.7.28 И БАЗА SQLITE
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 3: Оркестрация 3X-UI и закрепление Xray Core v26.7.28         ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

systemctl stop x-ui 2>/dev/null || true

DB_PATH="/etc/x-ui/x-ui.db"
if [ ! -f "$DB_PATH" ]; then
    log "Установка официального релиза 3X-UI через отказоустойчивый пул..."
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
            "https://ghfast.top/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
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

# -------------------------------------------------------------
# ЖЕСТКИЙ ПИННИНГ И УСТАНОВКА XRAY CORE v26.7.28
# -------------------------------------------------------------
TARGET_XRAY_VERSION="v26.7.28"
log "Инспекция архитектуры и принудительное закрепление Xray Core ${TARGET_XRAY_VERSION}..."

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
        die "Архитектура процессора $SYS_ARCH не поддерживается для авто-установки Xray!"
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

download_asset "$XRAY_ZIP" "${XRAY_URLS[@]}" || die "Не удалось загрузить бинарник Xray-core ${TARGET_XRAY_VERSION}!"

XRAY_EXTRACT_DIR="/tmp/xray_unpack"
rm -rf "$XRAY_EXTRACT_DIR"
mkdir -p "$XRAY_EXTRACT_DIR"
unzip -q -o "$XRAY_ZIP" -d "$XRAY_EXTRACT_DIR"
rm -f "$XRAY_ZIP"

mkdir -p /usr/local/x-ui/bin
if [ -f "$XRAY_EXTRACT_DIR/xray" ]; then
    for bin_name in "${XRAY_BIN_NAMES[@]}"; do
        cp -f "$XRAY_EXTRACT_DIR/xray" "/usr/local/x-ui/bin/${bin_name}"
        chmod +x "/usr/local/x-ui/bin/${bin_name}"
    done
    [ -f "$XRAY_EXTRACT_DIR/geoip.dat" ] && cp -f "$XRAY_EXTRACT_DIR/geoip.dat" /usr/local/x-ui/bin/
    [ -f "$XRAY_EXTRACT_DIR/geosite.dat" ] && cp -f "$XRAY_EXTRACT_DIR/geosite.dat" /usr/local/x-ui/bin/
    rm -rf "$XRAY_EXTRACT_DIR"
    ok "Ядро Xray ${TARGET_XRAY_VERSION} успешно распаковано и зафиксировано в /usr/local/x-ui/bin/."
else
    die "Не найден бинарный файл xray внутри скачанного архива!"
fi

XRAY_BIN="/usr/local/x-ui/bin/xray"
[ -x "$XRAY_BIN" ] || XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"
[ -x "$XRAY_BIN" ] || die "Штатный бинарник Xray не найден!"

DETECTED_XRAY_VER=$("$XRAY_BIN" version 2>/dev/null | head -n1 | awk '{print $2}' || echo "v26.7.28")
ok "Активная версия Xray в системе: ${GREEN}${DETECTED_XRAY_VER}${NC}"

log "Генерация постквантового ключа VLESS Encryption (ML-KEM-768) через $XRAY_BIN..."
vl_out=$("$XRAY_BIN" vlessenc 2>&1)
VLESS_DECRYPTION=$(echo "$vl_out" | grep '"decryption":' | tail -n1 | awk -F'"' '{print $4}' || true)
VLESS_ENCRYPTION=$(echo "$vl_out" | grep '"encryption":' | tail -n1 | awk -F'"' '{print $4}' || true)

if [[ ! "$VLESS_DECRYPTION" =~ ^mlkem768 ]] || [ -z "$VLESS_ENCRYPTION" ]; then
    die "Ошибка генерации ключа VLESS Encryption! Xray вернул: $vl_out"
fi
ok "Квантово-устойчивый ключ ML-KEM-768 успешно сгенерирован!"

STEAL_JSON="{"
first_p=1
for p in "${STEAL_PORTS_LIST[@]:-}"; do
    [ -n "$p" ] || continue
    doms_arr=(${STEAL_PORT_DOMAINS[$p]:-})
    doms_json=$(printf '%s\n' "${doms_arr[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[\"${doms_arr[0]:-cdn.$PRIMARY_DOMAIN}\"]")
    [ $first_p -eq 0 ] && STEAL_JSON="${STEAL_JSON},"
    STEAL_JSON="${STEAL_JSON}\"${p}\":${doms_json}"
    first_p=0
done
STEAL_JSON="${STEAL_JSON}}"

CLASSIC_JSON="{"
first_cp=1
for cp in "${CLASSIC_PORTS_LIST[@]:-}"; do
    [ -n "$cp" ] || continue
    snis_arr=(${CLASSIC_PORT_SNIS[$cp]:-})
    snis_json=$(printf '%s\n' "${snis_arr[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[\"${snis_arr[0]:-tbank.ru}\"]")
    [ $first_cp -eq 0 ] && CLASSIC_JSON="${CLASSIC_JSON},"
    CLASSIC_JSON="${CLASSIC_JSON}\"${cp}\":${snis_json}"
    first_cp=0
done
CLASSIC_JSON="${CLASSIC_JSON}}"

STEAL_DOMAINS_STR="${STEAL_DOMAINS[*]:-}"
export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_JSON
export ENABLE_CLASSIC CLASSIC_JSON ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ENABLE_AWG_V2 AWG_V2_PORT ADMIN_USER ADMIN_PASS SSL_BASE_DIR VLESS_DECRYPTION VLESS_ENCRYPTION STEAL_DOMAINS_STR INSTALL_MODE ENABLE_AGH GEO_PROFILE

# -------------------------------------------------------------
# ZERO-TOUCH SQLITE ENGINE (ТОЧНАЯ АНАТОМИЯ РАБОЧЕГО ДАМПА)
# -------------------------------------------------------------
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

# Пути подписок со скриншотов и рабочего дампа
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

steal_doms = os.environ.get("STEAL_DOMAINS_STR", "").split()
target_host = f"cdn.{domain}" if steal_doms else domain

cur.execute("SELECT id, username, password FROM users LIMIT 1")
urow = cur.fetchone()
if install_mode == "1":
    hashed_p = admin_p
    try:
        import bcrypt
        hashed_p = bcrypt.hashpw(admin_p.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    except Exception:
        pass
    if urow:
        cur.execute("UPDATE users SET username = ?, password = ? WHERE id = ?", (admin_u, hashed_p, urow[0]))
        uid = urow[0]
    else:
        cur.execute("INSERT INTO users (id, username, password) VALUES (1, ?, ?)", (admin_u, hashed_p))
        uid = 1
else:
    uid = urow[0] if urow else 1

# 1. Реестр параметров settings с подтвержденными адаптивными флагами
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
    "trustedProxyCIDRs": "127.0.0.1/32",
    "realityScanCandidates": "www.cloudflare.com:443,www.microsoft.com:443,www.amazon.com:443,aws.amazon.com:443,www.samsung.com:443,www.nvidia.com:443,www.amd.com:443,www.intel.com:443,www.sony.com:443,dl.google.com:443",
    "restartXrayOnClientDisable": "true",
    "xrayOutboundTestUrl": "https://www.google.com/generate_204",
    # Адаптивные подписки
    "subJsonAlwaysArray": "true",
    "subClashAutoDetect": "true",
    "subJsonAutoDetect": "false"
}
for k, v in settings_data.items():
    cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
    if cur.fetchone():
        if install_mode == "1" or k in ["webListen", "subListen", "subJsonEnable", "subClashEnable", "subJsonPath", "subJsonURI", "subClashPath", "trustedProxyCIDRs", "subJsonAlwaysArray", "subClashAutoDetect"]:
            cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

# 2. Интеллектуальный xrayTemplateConfig (Динамический DNS и Freedom finalRules)
freedom_final_rules = []
if enable_agh:
    freedom_final_rules.append({"action": "allow", "ip": ["127.0.0.1"], "port": "53"})
freedom_final_rules.append({"action": "block", "ip": ["geoip:private"]})
freedom_final_rules.append({"action": "allow"})

routing_rules = [
    {"inboundTag": ["api"], "outboundTag": "api", "type": "field"}
]
if enable_agh:
    routing_rules.append({"ip": ["127.0.0.1"], "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
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
    "api": {
        "services": ["HandlerService", "LoggerService", "StatsService", "RoutingService"],
        "tag": "api"
    },
    "dns": dns_config,
    "fakedns": None,
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": 62789,
            "protocol": "tunnel",
            "settings": {"rewriteAddress": "127.0.0.1"},
            "tag": "api"
        }
    ],
    "log": {
        "access": "none",
        "dnsLog": False,
        "error": "",
        "loglevel": "warning",
        "maskAddress": ""
    },
    "metrics": {
        "listen": "127.0.0.1:11111",
        "tag": "metrics_out"
    },
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "finalRules": freedom_final_rules
            },
            "streamSettings": {
                "sockopt": {"domainStrategy": "ForceIPv4"}
            }
        },
        {
            "tag": "blocked",
            "protocol": "blackhole",
            "settings": {}
        }
    ],
    "policy": {
        "system": {
            "statsInboundDownlink": True,
            "statsInboundUplink": True,
            "statsOutboundDownlink": False,
            "statsOutboundUplink": False
        },
        "levels": {
            "0": {
                "statsUserDownlink": True,
                "statsUserUplink": True
            }
        }
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": routing_rules
    },
    "stats": {}
}

cur.execute("SELECT id FROM settings WHERE key = 'xrayTemplateConfig'")
if cur.fetchone():
    cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(tpl_config),))
else:
    cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(tpl_config),))

# 3. Данные тестового клиента "Test"
test_email = "Test"
test_sub_id = "SUB_Test"
test_uuid = str(uuid.uuid4())
test_password = secrets.token_hex(8)
test_auth = secrets.token_hex(8)

# Строгий 16-ричный HEX shortId для Reality
reality_hex_sid = secrets.token_hex(8)

def_r_priv, def_r_pub = gen_reality_keypair()
def_wg_s_priv, def_wg_s_pub = gen_wg_keypair()
def_wg_c_priv, def_wg_c_pub = gen_wg_keypair()

now_ms = int(time.time() * 1000)

# Для чистой установки Reality идет с чистым flow: "" (максимальная совместимость)
client_reality_dict = {
    "auth": test_auth, "comment": "", "created_at": now_ms, "email": test_email,
    "enable": True, "expiryTime": 0, "flow": "", "id": test_uuid, "keepAlive": 25,
    "limitIp": 0, "password": test_password, "privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub,
    "reset": 0, "resetDay": 0, "resetMax": 0, "security": "auto", "subId": test_sub_id,
    "tgId": 0, "totalGB": 0, "trafficReset": "never", "trafficResetDay": 1, "updated_at": now_ms
}

client_xhttp_dict = dict(client_reality_dict)
client_xhttp_dict["flow"] = "xtls-rprx-vision"

# Безопасная инициализация переменных инбаундов (исключает NameError при отказе от протоколов)
ib1_id = ib2_id = ib3_id = ib4_id = ib5_id = ib6_id = None

def upsert_inbound(port, proto, tag, remark, s_obj_def, st_obj_def, listen="127.0.0.1"):
    cur.execute("SELECT id, settings, stream_settings FROM inbounds WHERE port = ? OR tag = ?", (port, tag))
    row = cur.fetchone()
    sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})
    inbound_id = None
    
    if row and install_mode == "2":
        inbound_id = row[0]
        existing_s = json.loads(row[1]) if row[1] else {}
        existing_st = json.loads(row[2]) if row[2] else {}
        
        # Умное сохранение существующих клиентов без изменения их flow
        final_s = existing_s
        if not final_s.get("clients"):
            final_s["clients"] = s_obj_def.get("clients", [])

        if proto == "vless" and "decryption" in s_obj_def and s_obj_def["decryption"] != "none":
            final_s["decryption"] = s_obj_def["decryption"]
            final_s["encryption"] = s_obj_def.get("encryption", "")

        # Сохраняем существующие streamSettings, обновляя только префикс spiderX и minClientVer
        final_st = existing_st
        if "realitySettings" in final_st:
            rs = final_st["realitySettings"]
            rs["minClientVer"] = "1.0.0"
            if not rs.get("shortIds"):
                rs["shortIds"] = [reality_hex_sid]
            # Гарантируем универсальный корень spiderX, если он был пустым
            if not rs.get("spiderX"):
                rs["spiderX"] = "/"
            if "settings" in rs and not rs["settings"].get("spiderX"):
                rs["settings"]["spiderX"] = "/"
            if rs.get("xver") is None:
                rs["xver"] = 1

        s_json = json.dumps(final_s, ensure_ascii=False)
        st_json = json.dumps(final_st, ensure_ascii=False)
        cur.execute("UPDATE inbounds SET protocol=?, tag=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (proto, tag, remark, s_json, st_json, listen, sniff, inbound_id))
    elif row:
        inbound_id = row[0]
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("UPDATE inbounds SET protocol=?, tag=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (proto, tag, remark, s_json, st_json, listen, sniff, inbound_id))
    else:
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing, share_addr_strategy, disable_flow) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?, 'node', 0)",
                    (uid, remark, listen, port, proto, s_json, st_json, tag, sniff))
        inbound_id = cur.lastrowid
    return inbound_id

# 4. Создание инбаундов
# 4.1 Steal Reality
if os.environ.get("ENABLE_STEAL") == "1":
    steal_dict = json.loads(os.environ.get("STEAL_JSON", "{}"))
    for p_str, doms in steal_dict.items():
        p = int(p_str)
        primary_dom = doms[0] if doms else f"cdn.{domain}"
        tag = f"in-steal-reality-{p}" if p != 45443 else "in-steal-reality"
        remark = f"REALITY-443 ({p})" if len(steal_dict) > 1 else "REALITY-443"
        s_obj = {"clients": [client_reality_dict], "decryption": "none"}
        st_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 1,
                "target": "127.0.0.1:9443", "dest": "127.0.0.1:9443",
                "serverNames": doms,
                "privateKey": def_r_priv,
                "minClientVer": "1.0.0", "maxClientVer": "", "maxTimediff": 0,
                "shortIds": [reality_hex_sid],
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": "", "spiderX": "/"}
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": remark}]
        }
        ib1_id = upsert_inbound(p, "vless", tag, remark, s_obj, st_obj)

# 4.2 Classic Reality
if os.environ.get("ENABLE_CLASSIC") == "1":
    classic_dict = json.loads(os.environ.get("CLASSIC_JSON", "{}"))
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
                "show": False, "xver": 0,
                "target": f"{primary_sni}:443", "dest": f"{primary_sni}:443",
                "serverNames": snis,
                "privateKey": def_r_priv,
                "minClientVer": "1.0.0", "maxClientVer": "", "maxTimediff": 0,
                "shortIds": [reality_hex_sid],
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": "", "spiderX": "/"}
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": remark}]
        }
        ib2_id = upsert_inbound(p, "vless", tag, remark, c_obj, ct_obj)

# 4.3 VLESS xHTTP (Native H2C Stream-One)
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
    "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "firefox", "remark": "VLESS xHTTP"}]
}
ib3_id = upsert_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS xHTTP", x_obj, xt_obj)

# 4.4 Hysteria 2
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
        "externalProxy": [{"dest": domain, "port": hp, "forceTls": "tls", "remark": "Hysteria 2"}]
    }
    ib4_id = upsert_inbound(hp, "hysteria", "in-hysteria2", "Hysteria 2", h_obj, ht_obj, listen="0.0.0.0")

# 4.5 AmneziaWG v3.1
if os.environ.get("ENABLE_AWG_V3") == "1":
    a3p = int(os.environ["AWG_V3_PORT"])
    a3_client = dict(client_reality_dict)
    a3_client["allowedIPs"] = ["10.8.1.3/32"]
    a3_client.pop("flow", None)
    a3_obj = {
        "clients": [a3_client],
        "server": {
            "h1": "", "h2": "", "h3": "", "h4": "", "jc": 4, "jmin": 50, "jmax": 160, "s1": 45, "s2": 60, "s3": 24, "s4": 16,
            "mtu": 1320, "primaryDns": "8.8.8.8", "secondaryDns": "8.8.4.4",
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "randomTrailers": False, "disableCookies": True, "contentPaddingAddition": "3-16",
            "keepaliveTimeout": "8-10", "rekeyAfterTime": "107-135", "rekeyTimeout": "3-4", "rejectAfterTime": "178-211", "maxHandshakeAttempts": "21-26",
            "subnetCidr": 24, "subnetIp": "10.8.1.0"
        }
    }
    a3t_obj = {"externalProxy": [{"dest": domain, "port": a3p, "remark": "AmneziaWG v3"}]}
    ib5_id = upsert_inbound(a3p, "amneziawg", "in-8443-udp", "AmneziaWG v3", a3_obj, a3t_obj, listen="0.0.0.0")

# 4.6 AmneziaWG v2.0
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
            "primaryDns": "8.8.8.8", "secondaryDns": "8.8.4.4",
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "subnetCidr": 24, "subnetIp": "10.8.2.0"
        }
    }
    a2t_obj = {"externalProxy": [{"dest": domain, "port": a2p, "remark": "AmneziaWG v2"}]}
    ib6_id = upsert_inbound(a2p, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2", a2_obj, a2t_obj, listen="0.0.0.0")

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = set(r[0] for r in cur.fetchall())

# 5. Синхронизация глобальной сущности clients
if "clients" in tables:
    cur.execute("SELECT id FROM clients WHERE email = ?", (test_email,))
    cl_row = cur.fetchone()
    if not cl_row and install_mode == "1":
        cur.execute("""
            INSERT INTO clients (
                email, sub_id, uuid, password, auth, flow, security, reverse,
                wg_private_key, wg_public_key, wg_allowed_ips, wg_pre_shared_key,
                wg_keep_alive, wg_forwarded_ports, secret, ad_tag, limit_ip, limit_hwid,
                total_gb, expiry_time, enable, tg_id, group_name, comment, reset, reset_day, reset_max,
                traffic_reset, traffic_reset_day, created_at, updated_at, sync_orphaned_at
            ) VALUES (
                ?, ?, ?, ?, ?, '', 'auto', '',
                ?, ?, '10.8.2.3/32', '',
                25, '', '', '', 0, 0,
                0, 0, 1, 0, '', '', 0, 0, 0,
                'never', 1, ?, ?, 0
            )
        """, (test_email, test_sub_id, test_uuid, test_password, test_auth, def_wg_c_priv, def_wg_c_pub, now_ms, now_ms))
        client_global_id = cur.lastrowid
    elif cl_row:
        client_global_id = cl_row[0]
    else:
        client_global_id = None

    # 6. Синхронизация junction-связей Many-to-Many (Безопасный цикл без NameError)
    if "client_inbounds" in tables and client_global_id and install_mode == "1":
        cur.execute("DELETE FROM client_inbounds WHERE client_id = ?", (client_global_id,))
        active_inbound_links = [
            (ib_id, fl) for ib_id, fl in [
                (ib1_id, ""),
                (ib2_id, ""),
                (ib3_id, "xtls-rprx-vision"),
                (ib4_id, ""),
                (ib5_id, ""),
                (ib6_id, "")
            ] if ib_id is not None
        ]
        for ib_id, flow_val in active_inbound_links:
            cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                        (client_global_id, ib_id, flow_val, now_ms))
    elif "client_inbounds" in tables and install_mode == "2":
        # Умная ситуативная миграция flow для ВСЕХ существующих клиентов
        cur.execute("SELECT id, settings FROM inbounds WHERE protocol = 'vless'")
        for v_ib_id, v_s_json in cur.fetchall():
            if not v_s_json: continue
            v_s = json.loads(v_s_json)
            for c in v_s.get("clients", []):
                c_mail = c.get("email")
                c_flow = c.get("flow", "")  # Сохраняем ТОЧНО ТОТ flow, который уже был у клиента!
                cur.execute("SELECT id FROM clients WHERE email = ?", (c_mail,))
                c_row = cur.fetchone()
                if c_row:
                    cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                                (c_row[0], v_ib_id, c_flow, now_ms))

# 7. Синхронизация таблицы client_traffics (строго одна запись на email)
if "client_traffics" in tables and install_mode == "1":
    cur.execute("SELECT id FROM client_traffics WHERE email = ?", (test_email,))
    ct_row = cur.fetchone()
    first_valid_ib = next((i for i in [ib1_id, ib2_id, ib3_id, ib4_id, ib5_id, ib6_id] if i is not None), 1)
    if not ct_row:
        cur.execute("INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)",
                    (first_valid_ib, test_email))

# 8. Таблица hosts (100% безопасная эталонная структура 1.2.0)
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
    insert_data = {}
    for k, v in col_candidates.items():
        if k in active_cols and k not in insert_data:
            insert_data[k] = v

    keys = list(insert_data.keys())
    vals = [insert_data[k] for k in keys]
    placeholders = ",".join(["?"] * len(keys))
    cur.execute(f"INSERT INTO hosts ({','.join(keys)}) VALUES ({placeholders})", vals)

if install_mode == "1":
    cur.execute("DELETE FROM hosts")
    group_all_uuid = str(uuid.uuid4())
    group_xhttp_uuid = str(uuid.uuid4())

    cur.execute("SELECT id, tag FROM inbounds WHERE tag != 'in-xhttp-stream' AND protocol != 'dokodemo-door'")
    for ib_id, ib_tag in cur.fetchall():
        add_host_entry(group_all_uuid, ib_id, "ALL_443", target_host, 443, "same", sort_order=1)

    cur.execute("SELECT id FROM inbounds WHERE tag = 'in-xhttp-stream'")
    x_row = cur.fetchone()
    if x_row:
        alpn_str = json.dumps(["h2"])
        add_host_entry(group_xhttp_uuid, x_row[0], "xHTTP", target_host, 443, "tls", sni=domain, alpn=alpn_str, fp="firefox", sort_order=2)
else:
    cur.execute("SELECT COUNT(*) FROM hosts")
    h_count = cur.fetchone()[0]
    if h_count == 0:
        group_all_uuid = str(uuid.uuid4())
        group_xhttp_uuid = str(uuid.uuid4())
        cur.execute("SELECT id, tag FROM inbounds WHERE tag != 'in-xhttp-stream' AND protocol != 'dokodemo-door'")
        for ib_id, ib_tag in cur.fetchall():
            add_host_entry(group_all_uuid, ib_id, "ALL_443", target_host, 443, "same", sort_order=1)

        cur.execute("SELECT id FROM inbounds WHERE tag = 'in-xhttp-stream'")
        x_row = cur.fetchone()
        if x_row:
            alpn_str = json.dumps(["h2"])
            add_host_entry(group_xhttp_uuid, x_row[0], "xHTTP", target_host, 443, "tls", sni=domain, alpn=alpn_str, fp="firefox", sort_order=2)

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
    ok "Служба 3X-UI успешно запущена и слушает локальный сокет 127.0.0.1:${PANEL_PORT}."
else
    warn "Служба 3X-UI стартовала. Проверьте статус в веб-панели."
fi

UNIFIED_SUB_ID="SUB_Test"
TEST_EMAIL="Test"
if [ -f "/tmp/vpn_unified_creds.txt" ]; then
    . /tmp/vpn_unified_creds.txt
    rm -f /tmp/vpn_unified_creds.txt
fi

# =============================================================
#  ФАЗА 4: ФИНАЛЬНЫЙ ЗАМОК (ПЕРСИСТЕНТНЫЙ PORT HOPPING, MSS CLAMPING, UFW)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 4: Персистентный Port Hopping, TCP MSS Clamping и изоляция UFW ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if grep -q "^IPV6=" /etc/default/ufw 2>/dev/null; then
    sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
else
    echo "IPV6=no" >> /etc/default/ufw
fi

ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true

ufw allow "${TARGET_SSH_PORT}/tcp" comment 'SSH' >/dev/null 2>&1 || true
ufw allow 80/tcp comment 'HTTP ACME' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS L4 Router' >/dev/null 2>&1 || true
ufw allow 8443/tcp comment 'HTTPS L4 Stream' >/dev/null 2>&1 || true

[ "${ENABLE_HY2:-0}" -eq 1 ] && ufw allow "${HY2_PORT}/udp" comment 'Hysteria 2' >/dev/null 2>&1 || true
[ "${ENABLE_AWG_V3:-0}" -eq 1 ] && ufw allow "${AWG_V3_PORT}/udp" comment 'AmneziaWG v3' >/dev/null 2>&1 || true
[ "${ENABLE_AWG_V2:-0}" -eq 1 ] && ufw allow "${AWG_V2_PORT}/udp" comment 'AmneziaWG v2' >/dev/null 2>&1 || true

export ENABLE_HY2_HOP HY2_PORT
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
content = content.strip() + "\n"

enable_hop = os.environ.get("ENABLE_HY2_HOP") == "1"
hy2_p = os.environ.get("HY2_PORT", "443")

nat_part = ""
if enable_hop:
    nat_part = f"""# START HARDENED NAT
*nat
:PREROUTING ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports {hy2_p}
COMMIT
# END HARDENED NAT

"""

mangle_part = """
# START HARDENED MANGLE
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
# END HARDENED MANGLE
"""

final_body = nat_part + content + mangle_part + "\n"

with open(rules_file, "w") as f:
    f.write(final_body)
EOF_UFW_PYTHON

if [ "${ENABLE_HY2:-0}" -eq 1 ] && [ "${ENABLE_HY2_HOP:-0}" -eq 1 ]; then
    log "Активация Port Hopping для Hysteria 2 (UDP 20000:50000 -> $HY2_PORT)..."
    ufw allow 20000:50000/udp comment 'Hy2 Port Hopping' >/dev/null 2>&1 || true

    iptables -t nat -C PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || \
        iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports "$HY2_PORT"
fi

log "Активация TCP MSS Clamping (--clamp-mss-to-pmtu)..."
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

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
ok "Фаервол UFW настроен. Port Hopping и TCP MSS Clamping персистентны."

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ДАШБОРД
# =============================================================
HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT}"
[ "${ENABLE_HY2_HOP:-0}" -eq 1 ] && HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT},20000-50000"

CRED_FILE="/root/vpn_credentials.txt"
cat << EOF > "$CRED_FILE"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА (Monoscript v2.1 Universal)
  ОС: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  Ядро Xray-core: ${DETECTED_XRAY_VER} (Pinned)
  Режим развертывания: $([ "$INSTALL_MODE" = "2" ] && echo "Safe Migration (Существующие клиенты сохранены)" || echo "Clean Setup (С нуля)")
  Сетевой профиль: $([ "$GEO_PROFILE" = "1" ] && echo "RU (Россия / Зеркала / Яндекс DNS)" || echo "EU/World (Зарубежный)")
  Дата развертывания: $(date '+%Y-%m-%d %H:%M:%S')
=====================================================================

[ ВЕБ-ПАНЕЛЬ 3X-UI ]
URL панели:            https://${PRIMARY_DOMAIN}${PANEL_PATH}
$([ "$INSTALL_MODE" = "1" ] && echo "Логин администратора:  ${ADMIN_USER}
Пароль администратора: ${ADMIN_PASS}" || echo "Учетные данные админа: Сохранены из прежней базы 3X-UI")
Внутренний сокет:      127.0.0.1:${PANEL_PORT} (Надежно изолирован)

$([ "${ENABLE_AGH:-0}" -eq 1 ] && cat << EOF_AGH_CRED
[ ПРИВАТНЫЙ ADGUARD HOME DOH ]
Веб-интерфейс:         https://${AGH_DOMAIN}/
Логин администратора:  ${AGH_USER}
Пароль администратора: ${AGH_PASS}
URL DoH для роутера:   https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}
(Для Keenetic / OpenWrt Podkop / MikroTik)

EOF_AGH_CRED
)
$([ "$INSTALL_MODE" = "1" ] && cat << EOF_SUB_CRED
[ ПОДПИСКИ КЛИЕНТОВ (МУЛЬТИПРОТОКОЛЬНЫЕ) ]
Клиент по умолчанию:   ${TEST_EMAIL} (Все настроенные протоколы в 1 ссылке)
Прямая ссылка (Base64):https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (JSON):  https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (Clash): https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}
(Для Happ, Streisand, FoXray, Karing, NekoBox, v2rayNG, Clash Verge, Mihomo)
EOF_SUB_CRED
)
$([ "$INSTALL_MODE" = "2" ] && echo "[ ПОДПИСКИ КЛИЕНТОВ ]
Все существующие подписки, клиенты, UUID, индивидуальные flow и ключи сохранены без изменений.")

$([ "${ENABLE_HY2:-0}" -eq 1 ] && echo "[ HYSTERIA 2 ]
Подключение:           ${HY2_REPORT_LINE}
")
[ СЕТЕВЫЕ ПАРАМЕТРЫ ]
SSH порт:              ${TARGET_SSH_PORT}
Основной домен:        ${PRIMARY_DOMAIN}
Сайт-маскировка:       https://${PRIMARY_DOMAIN}/

[ ВАЖНОЕ ДЕЙСТВИЕ ДЛЯ ПЕРВОГО ВХОДА В ПАНЕЛЬ ]
1. Откройте НОВОЕ окно консоли и проверьте доступ по SSH (порт ${TARGET_SSH_PORT}).
2. Выполните команду: reboot
После перезагрузки веб-панель сразу станет доступна по указанной ссылке.
=====================================================================
EOF
chmod 600 "$CRED_FILE"

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА И ГОТОВА К РАБОТЕ (v2.1)!                ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Панель управления 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  Логин: ${WHITE}${ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
else
echo -e "  Учетные данные:              ${GREEN}Сохранены из действующей базы${NC}"
fi
echo
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
echo -e "  Панель AdGuard Home:         ${CYAN}https://${AGH_DOMAIN}/${NC}"
echo -e "  Приватный DoH для роутера:   ${GREEN}https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}${NC}"
echo
fi
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Единая адаптивная ссылка Base64):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Эталонная ссылка JSON для Happ/Sing-box):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Выделенная ссылка Clash / Mihomo YAML):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}${NC}"
echo
else
echo -e "  ${BOLD}Клиентская база:${NC}          ${GREEN}100% действующих клиентов сохранены со своими персональными flow${NC}"
echo
fi
if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
echo -e "  ${WHITE}Hysteria 2 (UDP):${NC}            ${CYAN}${HY2_REPORT_LINE}${NC}"
fi
echo -e "  ${WHITE}Ядро Xray-core:${NC}              ${GREEN}${DETECTED_XRAY_VER} (Pinned)${NC}"
echo -e "  ${WHITE}Встроенный DNS Xray:${NC}         ${GREEN}$([ "${ENABLE_AGH:-0}" -eq 1 ] && echo "127.0.0.1:53 (AGH DoH, ForceIPv4)" || echo "Выключен (Системный resolv.conf)")${NC}"
echo -e "  ${WHITE}Маршрутизация Freedom:${NC}       ${GREEN}IPIfNonMatch, Block BitTorrent & Private IPs${NC}"
echo -e "  ${WHITE}База данных SQLite:${NC}          ${GREEN}Синхронизирована (Таблицы clients, client_inbounds)${NC}"
echo -e "  ${WHITE}TCP MSS Clamping:${NC}            ${GREEN}Персистентно в mangle (--clamp-mss-to-pmtu)${NC}"
echo -e "  ${WHITE}VLESS xHTTP:${NC}                 ${GREEN}Native H2C + ML-KEM-768 + XTLS Vision${NC}"
echo -e "  ${WHITE}VLESS Steal REALITY:${NC}         ${GREEN}target/dest 127.0.0.1:9443, xver 1, spiderX /${NC}"
echo -e "  ${WHITE}VLESS Classic REALITY:${NC}       ${GREEN}target/dest external:443, xver 0, spiderX /${NC}"
echo -e "  ${WHITE}Раздел «Хосты» 3X-UI:${NC}        ${GREEN}Группировка ALL_443 (+4) и xHTTP (ALPN: h2)${NC}"
echo -e "  ${WHITE}Сетевой профиль:${NC}             ${GREEN}$([ "$GEO_PROFILE" = "1" ] && echo "RU (Яндекс DNS + Зеркала)" || echo "EU/World")${NC}"
echo
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${YELLOW}---------------------------------------------------------------------${NC}"
echo -e "  ${YELLOW}${BOLD}ОБЯЗАТЕЛЬНОЕ ДЕЙСТВИЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "  ${WHITE}1. Откройте ${BOLD}НОВОЕ${NC} окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).${NC}"
echo -e "  ${WHITE}2. Выполните команду: ${GREEN}${BOLD}reboot${NC}"
echo -e "  ${DIM}После перезапуска сервера веб-панель сразу откроется по указанной ссылке.${NC}"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
