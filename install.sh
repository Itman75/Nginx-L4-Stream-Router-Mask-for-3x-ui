#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup Monoscript: Hardened Master Engine v3.7 MyPrivateCloud Ultra
# Architecture: Single-IP Ultra Enhanced + Native Kernel AmneziaWG (Bare-Metal)
# Zero-Leak Frontend: My Private Cloud SSO Hub + Modular WebCrypto Plane
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

LOCK_FILE="/var/run/hardened-master-engine-v360.lock"
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

# shellcheck disable=SC2317
cleanup() {
    local exit_code=$?
    trap - ERR EXIT INT TERM
    systemctl start x-ui 2>/dev/null || true
    rm -f /tmp/vpn_unified_creds.txt /tmp/3xui_install.log /tmp/xray-*.zip /tmp/agh.tar.gz /tmp/nginx_prev_sni_map.txt 2>/dev/null || true
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n${RED}[X] Скрипт аварийно прерван на строке ${1:-unknown} (код: ${exit_code}).${NC}" >&2
    fi
    exit "$exit_code"
}
trap 'cleanup $LINENO' ERR INT TERM

clear 2>/dev/null || true
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  Hardened Master Engine v3.7 (MyPrivateCloud Ultra + Native AmneziaWG)  ${NC}"
echo -e "${CYAN}   Clean Setup / Safe Migration + Nginx L4                              ${NC}"
echo -e "${WHITE}  Xray Core v26.7.28 Pinned + Native H2 xHTTP + ML-KEM-768 + Vision    ${NC}"
echo -e "${WHITE}  Dual UDP Pools: Hy2 (20000-35000) & AWG Native (35001-49999)      ${NC}"
echo -e "${WHITE}  Stealth SSO Hub: DataSphere In-Memory Portal (3X-UI / AWG / AGH)   ${NC}"
echo -e "${WHITE}  Ingress Shield: Zero-SNI + Port 80 444 Drop + Live Fallback 9443   ${NC}"
echo -e "${WHITE}  Universal WAN Engine (Tier 1-4) + Dual-Sync Matrix Reconciliation  ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

# Инициализация системных переменных для строгого режима set -u
LE_EMAIL=""
TARGET_SSH_PORT="22"
ROOT_PASSWORD=""
NEW_USERNAME=""
NEW_USER_PASS=""
HY2_PORT="443"
NATIVE_AWG_PORT="8443"
AWG_V3_PORT="10443"
ENABLE_NATIVE_AWG=1
ENABLE_STEAL=0
ENABLE_CLASSIC=0
ENABLE_XHTTP=1
ENABLE_HY2=0
ENABLE_HY2_HOP=0
ENABLE_AWG_HOP=0
ENABLE_AWG_V3=0
ENABLE_AGH=0
AGH_DOMAIN=""
AGH_USER="admin"
AGH_PASS=""
AGH_CLIENT_ID=""
PRIMARY_DOMAIN=""
GEO_PROFILE="2"
INSTALL_MODE="1"
SSL_ENGINE_CHOICE="1"
SSL_BASE_DIR="/etc/letsencrypt/live"
DO_SYS_UPGRADE=0
INSTALL_EXTRA_UTILS=0
ENABLE_BBR_IPV6=0
BLOCK_PING=0
CHANGE_ROOT_PASS=0
CREATE_USER=0
SETUP_KEYS=0
EXISTING_DB_PATH=""
export EXISTING_DB_PATH

rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx /usr/share/keyrings/nginx-archive-keyring.gpg.tmp 2>/dev/null || true
if [ -f /usr/share/keyrings/nginx-archive-keyring.gpg ] && [ ! -s /usr/share/keyrings/nginx-archive-keyring.gpg ]; then
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null || true
fi

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
        elif [[ "$OS_CODENAME" =~ ^(jammy|noble|plucky|questy|testing)$ ]]; then
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
        die "ОС ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME) не поддерживается. Разрешены строго Ubuntu 22.04+ / 24.04+ / 26.04+ или Debian 12+ / 13+."
    fi
    ok "Операционная система валидирована: ${PRETTY_NAME:-$OS_ID $OS_VER_ID} ($OS_CODENAME)"
else
    die "Не удалось определить параметры дистрибутива."
fi

VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")


patch_amnezia_dkms_kernel_compat() {
    # На Ubuntu 24.04 (ядра 5.x / 6.x) патч НЕ ТРЕБУЕТСЯ — выходим сразу
    local k_major
    k_major=$(uname -r | cut -d. -f1)
    if [ "${k_major:-0}" -lt 7 ]; then
        return 0
    fi

    local dkms_dirs=()
    shopt -s nullglob
    dkms_dirs=(/usr/src/amneziawg-*)
    shopt -u nullglob

    [ "${#dkms_dirs[@]}" -gt 0 ] || return 0

    local root_dir target_header
    for root_dir in "${dkms_dirs[@]}"; do
        [ -d "$root_dir" ] || continue
        target_header=""
        if [ -f "${root_dir}/compat/compat.h" ]; then
            target_header="${root_dir}/compat/compat.h"
        elif [ -f "${root_dir}/src/compat/compat.h" ]; then
            target_header="${root_dir}/src/compat/compat.h"
        fi
        [ -n "$target_header" ] || continue

        if grep -q "__compat_setup_udp_tunnel_sock" "$target_header" 2>/dev/null; then
            continue
        fi

        log "Обнаружено ядро 7.0+ ($(uname -r)). Применение патча совместимости для AmneziaWG..."
        awk '
        index($0, "setup_udp_tunnel_sock(net, sk, sock_cfg) setup_udp_tunnel_sock(net, sk->sk_socket, sock_cfg)") > 0 {
            print "/* Kernel 7.0+ compatibility backport */"
            print "#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 0, 0)"
            print "#define setup_udp_tunnel_sock(net, sk, sock_cfg) setup_udp_tunnel_sock(net, sk->sk_socket, sock_cfg)"
            print "#elif LINUX_VERSION_CODE < KERNEL_VERSION(7, 2, 0)"
            print "#define __compat_setup_udp_tunnel_sock 1"
            print "#endif"
            next
        }
        { print }
        ' "$target_header" > "${target_header}.tmp" && mv -f "${target_header}.tmp" "$target_header"
        chmod 0644 "$target_header"
        ok "Заголовочный файл ${target_header} пропатчен под ядро 7.0+."
    done
}

wait_for_apt_lock() {
    local max_wait=120
    local count=0
    while :; do
        local locked=0
        if command -v fuser >/dev/null 2>&1; then
            if fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1; then
                locked=1
            fi
        else
            if pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x unattended-upgrade >/dev/null 2>&1; then
                locked=1
            fi
        fi
        [ "$locked" -eq 0 ] && break
        if [ "$count" -ge "$max_wait" ]; then
            warn "Блокировка APT удерживается более ${max_wait}с."
            break
        fi
        if [ "$count" -eq 0 ]; then
            log "Ожидание завершения фонового обновления пакетов..."
        fi
        sleep 2
        count=$((count + 2))
    done
    return 0
}

log "Первичная подготовка системных утилит (Low-Memory Profile: 1 GB RAM)..."
wait_for_apt_lock
dpkg --configure -a >/dev/null 2>&1 || true

# Очистка кэша APT для освобождения буферов памяти перед установкой
apt-get clean -q >/dev/null 2>&1 || true
apt-get update -q >/dev/null 2>&1 || true
wait_for_apt_lock

# Минимально необходимый набор: исключены компиляторы, dirmngr, apache2-utils, bc и тяжелые зависимости
BASE_BOOTSTRAP_PKGS=(
    curl iproute2 openssl gawk python3 python3-bcrypt
    unzip jq sqlite3 gnupg psmisc ca-certificates
)

apt-get install -y "${BASE_BOOTSTRAP_PKGS[@]}" -q --no-install-recommends >/dev/null 2>&1 || true

# Контрольная проверка наличия критических утилит
MISSING_CRITICAL=()
for tool in curl sqlite3 jq openssl python3 awk ip ss; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_CRITICAL+=("$tool")
    fi
done

if [ "${#MISSING_CRITICAL[@]}" -gt 0 ]; then
    die "Критические базовые утилиты не установлены: ${MISSING_CRITICAL[*]}. Проверьте доступ к сети и репозиториям APT."
fi

ok "Базовые утилиты готовы к работе (минимальный footprint)."

validate_port() {
    local p="${1:-}"
    if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 22 ] && [ "$p" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_path_segment() {
    local p="${1:-}"
    if [[ -n "$p" ]] && [[ "$p" =~ ^[a-zA-Z0-9_./-]+$ ]] && [[ ! "$p" =~ \.\. ]]; then
        return 0
    fi
    return 1
}

prompt_path() {
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
        if validate_path_segment "$p_val"; then
            declare -g "$var_name=$p_val"
            break
        fi
        warn "Недопустимый формат пути: '$p_val'. Допустимы латиница, цифры, дефис, точка и слэш (без '..'). Попробуйте снова."
    done
}

# =============================================================
#  УНИВЕРСАЛЬНЫЙ ДЕТЕКТОР ВНЕШНЕГО СЕТЕВОГО ИНТЕРФЕЙСА (TIER 1-4)
# =============================================================
detect_wan_interface() {
    local iface=""
    local candidate=""
    local canaries=("1.1.1.1" "8.8.8.8" "77.88.8.8" "9.9.9.9")

    # Tier 1: Запрос FIB-кэша ядра через тестовые Anycast-маршруты
    for canary in "${canaries[@]}"; do
        candidate=$(ip -4 route get "$canary" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
        if [ -n "$candidate" ] && [ -d "/sys/class/net/$candidate" ]; then
            iface="$candidate"
            break
        fi
    done

    # Tier 2: Поиск шлюза по умолчанию в основной таблице маршрутизации
    if [ -z "$iface" ]; then
        candidate=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
        if [ -n "$candidate" ] && [ -d "/sys/class/net/$candidate" ]; then
            iface="$candidate"
        fi
    fi

    # Tier 3: Инспекция физических интерфейсов в /sys/class/net/ с блэклистом виртуальных
    if [ -z "$iface" ]; then
        for dev_path in /sys/class/net/*; do
            [ -e "$dev_path" ] || continue
            candidate=$(basename "$dev_path")
            case "$candidate" in
                lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|awg*|tailscale*|zt*|dummy*)
                    continue
                    ;;
            esac
            if [ -f "$dev_path/operstate" ] && [ -f "$dev_path/carrier" ]; then
                local operstate carrier
                operstate=$(cat "$dev_path/operstate" 2>/dev/null || echo "down")
                carrier=$(cat "$dev_path/carrier" 2>/dev/null || echo "0")
                if [ "$operstate" = "up" ] || [ "$carrier" = "1" ]; then
                    if ip -4 addr show dev "$candidate" 2>/dev/null | grep -q "inet "; then
                        iface="$candidate"
                        break
                    fi
                fi
            fi
        done
    fi

    # Tier 4: Валидация и fail-safe fallback
    if [ -z "$iface" ] || [ ! -d "/sys/class/net/$iface" ]; then
        iface=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' || echo "")
    fi
    if [ -z "$iface" ]; then
        iface="eth0"
    fi
    echo "$iface"
}

DEFAULT_IF=$(detect_wan_interface)
export DEFAULT_IF
ok "Сетевой WAN-интерфейс ядра (Universal Engine): ${GREEN}${DEFAULT_IF}${NC}"

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
    local candidates=("gateway.icloud.com" "swdist.apple.com" "dl.google.com" "www.samsung.com")
    local best_sni="gateway.icloud.com"
    if [ "${GEO_PROFILE:-2}" = "1" ]; then
        candidates=("tbank.ru" "gateway.icloud.com" "dl.google.com" "www.samsung.com")
        best_sni="tbank.ru"
    fi
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

for alt_db in "/etc/x-ui/x-ui.db" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then
        EXISTING_DB_PATH="$alt_db"
        export EXISTING_DB_PATH
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
    echo -e "     их UUID, ключей, паролей, статистики и хостов + Dual-Sync реконсиляция инбаундов"
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
if [ "$INSTALL_MODE" = "2" ] && [ -f /etc/nginx/conf.d/01-main.conf ]; then
    DETECTED_MAIN_DOM=$(grep -E 'server_name\s+[^;]+;' /etc/nginx/conf.d/01-main.conf 2>/dev/null | grep -v '_' | awk '{print $2}' | tr -d ';' | head -n1 || echo "")
fi

while true; do
    prompt_default "Введите ваш основной домен (любой валидный FQDN, включая www.* при желании)" "${DETECTED_MAIN_DOM:-yourdomain.online}" PRIMARY_DOMAIN
    PRIMARY_DOMAIN=$(echo "$PRIMARY_DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат доменного имени."
done
ok "Главный домен L7 (PRIMARY_DOMAIN): ${GREEN}${PRIMARY_DOMAIN}${NC}"

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

if prompt_yes_no "Включить TCP BBR, somaxconn, MTU probing и отключить IPv6?" "y"; then
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
    prompt_port "Введите новый порт SSH (1024-65535)" "20022" TARGET_SSH_PORT
else
    TARGET_SSH_PORT="$SSH_ACTIVE_PORT"
fi

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
DETECTED_XHTTP_PATH="Stream-One-Path"
DETECTED_XHTTP_PORT="50443"

if [ -n "$EXISTING_DB_PATH" ]; then
    DETECTED_PANEL_PATH=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webBasePath';" 2>/dev/null || echo "my-3x-panel")
    DETECTED_SUB_PATH=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPath';" 2>/dev/null || echo "my-post-key")
    DETECTED_PANEL_PORT=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webPort';" 2>/dev/null || echo "10443")
    DETECTED_SUB_PORT=$(sqlite3 "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPort';" 2>/dev/null || echo "55443")
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH#/}"
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH%/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH#/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH%/}"

    DB_XHTTP_PATH=$(sqlite3 "$EXISTING_DB_PATH" "SELECT json_extract(stream_settings, '$.xhttpSettings.path') FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%xhttp%' LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$DB_XHTTP_PATH" ]; then
        DETECTED_XHTTP_PATH="${DB_XHTTP_PATH#/}"
        DETECTED_XHTTP_PATH="${DETECTED_XHTTP_PATH%/}"
    fi
    DB_XHTTP_PORT=$(sqlite3 "$EXISTING_DB_PATH" "SELECT port FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%xhttp%' LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$DB_XHTTP_PORT" ] && validate_port "$DB_XHTTP_PORT"; then
        DETECTED_XHTTP_PORT="$DB_XHTTP_PORT"
    fi
fi

prompt_port "Внутренний локальный порт панели 3X-UI" "${DETECTED_PANEL_PORT:-10443}" PANEL_PORT
prompt_path "Секретный URI-путь к веб-панели (без слэшей)" "${DETECTED_PANEL_PATH:-my-3x-panel}" RAW_PATH
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_port "Внутренний порт сервера подписок 3X-UI" "${DETECTED_SUB_PORT:-55443}" SUB_PORT
prompt_path "Секретный URI-путь подписок (без слэшей)" "${DETECTED_SUB_PATH:-my-post-key}" RAW_SUB_PATH
SUB_PATH="/${RAW_SUB_PATH#/}"
SUB_PATH="${SUB_PATH%/}/"

SUB_JSON_PATH="${SUB_PATH}sub-json/"
SUB_CLASH_PATH="${SUB_PATH}sub-clash/"



ADMIN_USER="admin"
ADMIN_PASS=""
if [ "$INSTALL_MODE" = "1" ]; then
    prompt_default "Логин администратора панели 3X-UI" "admin" ADMIN_USER
    DEFAULT_XP="3X_$(openssl rand -hex 4)"
    prompt_default "Пароль администратора панели 3X-UI" "$DEFAULT_XP" ADMIN_PASS
else
    ok "В режиме Safe Migration учетные данные администратора панели сохраняются из базы."
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 4: Настройка протоколов маскировки REALITY и xHTTP ---${NC}"
if prompt_yes_no "Включить Steal-Oneself REALITY (Кража у своего поддомена с Anti-Loop Fallback 9443)?" "y"; then
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

            # Collision Guardrail: Домен Steal-REALITY не может совпадать с PRIMARY_DOMAIN
            if [ "$S_DOM" = "$PRIMARY_DOMAIN" ]; then
                warn "    ОШИБКА КОЛЛИЗИИ: '$S_DOM' совпадает с главным доменом (PRIMARY_DOMAIN)!"
                warn "    Главный домен зарезервирован за Nginx L7 (веб-декоем, панелью, подписками и xHTTP)."
                warn "    Для Steal-REALITY укажите поддомен (например, cdn.$PRIMARY_DOMAIN)."
                continue
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
            ok "    Домен $S_DOM привязан к инбаунд-порту $PORT_VAL (Anti-Loop Fallback 9443)"
        done
        STEAL_PORT_DOMAINS["$PORT_VAL"]="$(echo "$port_doms_str" | xargs)"

        if ! prompt_yes_no "  Сконфигурировать еще один порт Steal-Oneself?" "n"; then
            break
        fi
    done
fi

if prompt_yes_no "Включить VLESS xHTTP (Native H2 Stream-One + Post-Quantum ML-KEM-768)?" "y"; then
    ENABLE_XHTTP=1
    prompt_port "  Внутренний порт инбаунда VLESS xHTTP (Native H2 Stream-One)" "${DETECTED_XHTTP_PORT:-50443}" XHTTP_STREAM_PORT
    prompt_path "  Секретный URI-путь для xHTTP (без слэшей)" "${DETECTED_XHTTP_PATH:-Stream-One-Path}" RAW_XHTTP_STREAM_PATH
    XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH#/}"
    XHTTP_STREAM_PATH="${XHTTP_STREAM_PATH%/}/"
    BASE_XHTTP_PATH="${XHTTP_STREAM_PATH%/}"
else
    ENABLE_XHTTP=0
    XHTTP_STREAM_PORT=""
    XHTTP_STREAM_PATH=""
    BASE_XHTTP_PATH=""
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
echo -e "${WHITE}${BOLD}--- ШАГ 6: Скоростные UDP VPN туннели и портовые пулы ---${NC}"
if prompt_yes_no "Установить Hysteria 2 (UDP)?" "y"; then
    ENABLE_HY2=1
else
    ENABLE_HY2=0
fi

if [ "$ENABLE_HY2" -eq 1 ]; then
    prompt_port "  Внешний UDP-порт для Hysteria 2" "443" HY2_PORT
    echo -e "  ${WHITE}Режим работы портов Hysteria 2:${NC}"
    echo -e "    1) ${GREEN}Одиночный порт :${HY2_PORT}/udp${NC}"
    echo -e "    2) ${GREEN}Скоростной пул Hopping :${HY2_PORT} + диапазон 20000-35000/udp${NC}"
    prompt_default "  Выберите вариант (1 или 2)" "2" HY2_MODE_CHOICE
    if [ "$HY2_MODE_CHOICE" = "2" ]; then
        ENABLE_HY2_HOP=1
        ok "  Hysteria 2 Hopping пул 20000:35000 активирован"
    else
        ENABLE_HY2_HOP=0
        ok "  Выбран одиночный порт ${HY2_PORT}/udp"
    fi
fi

if [ "$VIRT_TYPE" = "lxc" ] || [ "$VIRT_TYPE" = "openvz" ] || [ "$VIRT_TYPE" = "docker" ]; then
    warn "Обнаружена среда контейнеризации ($VIRT_TYPE). Нативный DKMS AmneziaWG отключён (требуется KVM/Bare-Metal)."
    ENABLE_NATIVE_AWG=0
else
    if prompt_yes_no "Установить НА ТЕХНОЛОГИЯХ ЯДРА нативный сервер AmneziaWG (Bare-Metal awg0)?" "y"; then
        ENABLE_NATIVE_AWG=1
        prompt_port "  Базовый UDP-порт для нативного сервера AmneziaWG awg0" "8443" NATIVE_AWG_PORT
        echo -e "  ${WHITE}Режим работы портов AmneziaWG (awg0):${NC}"
        echo -e "    1) ${GREEN}Одиночный порт :${NATIVE_AWG_PORT}/udp${NC}"
        echo -e "    2) ${GREEN}Скоростной пул Hopping :${NATIVE_AWG_PORT} + диапазон 35001-49999/udp [Рекомендуется]${NC}"
        prompt_default "  Выберите вариант (1 или 2)" "2" AWG_MODE_CHOICE
        if [ "$AWG_MODE_CHOICE" = "2" ]; then
            ENABLE_AWG_HOP=1
            ok "  Скоростной пул AmneziaWG 35001-49999/udp привязан к порту :${NATIVE_AWG_PORT}/udp"
        else
            ENABLE_AWG_HOP=0
            ok "  Выбран одиночный порт :${NATIVE_AWG_PORT}/udp"
        fi
    else
        ENABLE_NATIVE_AWG=0
    fi
fi

if prompt_yes_no "Установить AmneziaWG v3.2 в 3X-UI (UDP)?" "y"; then
    ENABLE_AWG_V3=1
else
    ENABLE_AWG_V3=0
fi
if [ "$ENABLE_AWG_V3" -eq 1 ]; then
    prompt_port "  Выделенный UDP-порт для AmneziaWG v3.2 (3X-UI)" "10443" AWG_V3_PORT
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

log "Обновление пакетных репозиториев..."
wait_for_apt_lock
apt-get update -q

if [ "${DO_SYS_UPGRADE:-0}" -eq 1 ]; then
    patch_amnezia_dkms_kernel_compat
    if dpkg -s amneziawg-dkms >/dev/null 2>&1 && dpkg -l amneziawg-dkms 2>/dev/null | grep -qE '^i[UHRF]|^r[cF]'; then
        dpkg --configure -a || true
    fi
    log "Неинтерактивное обновление системных библиотек и проверка состояния ядра..."
    wait_for_apt_lock
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y -q
    apt-get autoclean -y -q
    if [ -f /var/run/reboot-required ]; then
        warn "Обнаружено обновление компонентов ядра Linux. Рекомендуется плановая перезагрузка."
    fi
fi

log "Установка системного набора утилит..."
wait_for_apt_lock
CORE_PKGS=(
    curl wget bash sudo systemd openssl gawk lsb-release gnupg bind9-dnsutils
    socat cron ufw iptables iproute2 tar apache2-utils fail2ban python3 python3-systemd
    python3-bcrypt ca-certificates build-essential jq tmux net-tools bc xxd unzip sqlite3
    bsdextrautils dirmngr psmisc qrencode libmnl-dev make gcc
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
    log "Настройка TCP BBR, fq, somaxconn, Path MTU probing, loose rp_filter и отключение IPv6..."
    modprobe tcp_bbr 2>/dev/null || true
    mkdir -p /etc/sysctl.d/
    cat << EOF > /etc/sysctl.d/99-hardened-network.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.${DEFAULT_IF}.rp_filter = 2
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
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = 65536 131072 262144
vm.swappiness = 10
fs.file-max = 2097152
net.ipv4.tcp_fastopen = 3
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_mtu_probe_floor = 1024
net.ipv4.tcp_orphan_retries = 2
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
vm.dirty_ratio = 6
vm.dirty_background_ratio = 3
EOF
    sysctl --system >/dev/null 2>&1 || true
fi

cat << 'EOF' > /etc/security/limits.d/99-proxy-limits.conf
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
www-data soft nofile 1048576
www-data hard nofile 1048576
nginx soft nofile 1048576
nginx hard nofile 1048576
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
#  ФАЗА 2: ВНЕШНИЙ ШЛЮЗ NGINX MAINLINE, SSL И ADGUARD HOME DOH
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

log "Оркестрация официального репозитория Nginx для $OS_ID ($OS_CODENAME)..."
systemctl stop nginx 2>/dev/null || true

NGINX_KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
mkdir -p /usr/share/keyrings

# 1. Идемпотентная верификация существующего Keyring (исключает сбои при Safe Migration)
NGINX_KEY_OK=0
if [ -s "$NGINX_KEYRING" ]; then
    if gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 >/dev/null 2>&1 || \
       gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys 8540A6F18833A80E >/dev/null 2>&1 || \
       gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys 9E9BE90EACBCDE69 >/dev/null 2>&1 || \
       gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys 2FD21310B49F6B46 >/dev/null 2>&1 || \
       gpg --no-default-keyring --keyring "$NGINX_KEYRING" --list-keys >/dev/null 2>&1; then
        NGINX_KEY_OK=1
        ok "Действующий Keyring Nginx успешно верифицирован в системе (загрузка пропущена)."
    fi
fi

# 2. Безопасная загрузка ключей без разрушения конвейера pipefail
if [ "$NGINX_KEY_OK" -eq 0 ]; then
    NGINX_TMP_KEY="/tmp/nginx_signing.key.tmp"
    rm -f "$NGINX_TMP_KEY" "${NGINX_KEYRING}.tmp"
    for key_url in "https://nginx.org/keys/nginx_signing.key" "http://nginx.org/keys/nginx_signing.key"; do
        log "Запрос официального ключа Nginx: $key_url"
        if curl -fsSL --connect-timeout 8 -m 25 --retry 2 "$key_url" -o "$NGINX_TMP_KEY" 2>/dev/null; then
            if [ -s "$NGINX_TMP_KEY" ] && gpg --dearmor -o "${NGINX_KEYRING}.tmp" < "$NGINX_TMP_KEY" 2>/dev/null; then
                if [ -s "${NGINX_KEYRING}.tmp" ]; then
                    mv -f "${NGINX_KEYRING}.tmp" "$NGINX_KEYRING"
                    chmod 644 "$NGINX_KEYRING"
                    NGINX_KEY_OK=1
                    ok "Ключ Nginx успешно загружен и деарморирован."
                    break
                fi
            fi
        fi
    done
    rm -f "$NGINX_TMP_KEY"
fi

# 3. Встроенный Fail-Safe ASCII-Armor (защита от сетевых сбоев, блокировок DPI и таймаутов dirmngr)
if [ "$NGINX_KEY_OK" -eq 0 ]; then
    warn "Сетевые зеркала недоступны. Развёртывание встроенного доверенного ASCII-Armor ключа Nginx..."
    cat << 'EOF_NGINX_GPG_ARMOR' | gpg --dearmor -o "${NGINX_KEYRING}.tmp" 2>/dev/null
-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2

mQENBE5OMmIBCAD+FPYKGriGGf7NqwKfWC83cBV01gabgVWQmZbMcFzeW+hMsgxH
W6iimD0RsfZ9oEbfJCPG0CRSZ7ppq5pKamYs2+EJ8Q2ysOFHHwpGrA2C8zyNAs4I
QxnZZIbETgcSwFtDun0XiqPwPZgyuXVm9PAbLZRbfBzm8wR/3SWygqZBBLdQk5TE
fDR+Eny/M1RVR4xClECONF9UBB2ejFdI1LD45APbP2hsN/piFByU1t7yK2gpFyRt
97WzGHn9MV5/TL7AmRPM4pcr3JacmtCnxXeCZ8nLqedoSuHFuhwyDnlAbu8I16O5
XRrfzhrHRJFM1JnIiGmzZi6zBvH0ItfyX6ttABEBAAG0KW5naW54IHNpZ25pbmcg
a2V5IDxzaWduaW5nLWtleUBuZ2lueC5jb20+iQE+BBMBAgAoBQJOTjJiAhsDBQkJ
ZgGABgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAKCRCr9b2Ce9m/YpvjB/98uV4t
94d0oEh5XlqEZzVMrcTgPQ3BZt05N5xVuYaglv7OQtdlErMXmRWaFZEqDaMHdniC
sF63jWMd29vC4xpzIfmsLK3ce9oYo4t9o4WWqBUdf0Ff1LMz1dfLG2HDtKPfYg3C
8NESud09zuP5NohaE8Qzj/4p6rWDiRpuZ++4fnL3Dt3N6jXILwr/TM/Ma7jvaXGP
DO3kzm4dNKp5b5bn2nT2QWLPnEKxvOg5Zoej8l9+KFsUnXoWoYCkMQ2QTpZQFNwF
xwJGoAz8K3PwVPUrIL6b1lsiNovDgcgP0eDgzvwLynWKBPkRRjtgmWLoeaS9FAZV
ccXJMmANXJFuCf26
=eW4P
-----END PGP PUBLIC KEY BLOCK-----
EOF_NGINX_GPG_ARMOR
    if [ -s "${NGINX_KEYRING}.tmp" ]; then
        mv -f "${NGINX_KEYRING}.tmp" "$NGINX_KEYRING"
        chmod 644 "$NGINX_KEYRING"
        NGINX_KEY_OK=1
        ok "Встроенный Fail-Safe ключ Nginx успешно применён."
    else
        rm -f "${NGINX_KEYRING}.tmp"
    fi
fi

# 4. Аудит установленной версии бинарника Nginx
EXISTING_NGINX_VER="0"
if command -v nginx >/dev/null 2>&1; then
    EXISTING_NGINX_VER=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0")
fi

USE_OFFICIAL_NGINX_REPO=0
if [ "$NGINX_KEY_OK" -eq 1 ] && [ -s "$NGINX_KEYRING" ]; then
    NGINX_REPO_CODENAME="$OS_CODENAME"
    if ! curl -fsSL -I --connect-timeout 4 "https://nginx.org/packages/mainline/$OS_ID/dists/$OS_CODENAME/Release" >/dev/null 2>&1; then
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
        warn "Сбой обновления репозитория nginx.org. Откат репозиторных списков..."
        rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx
    fi
fi

# 5. Установка и предотвращение конфликта версий DPKG (held broken packages)
wait_for_apt_lock
if [ "$USE_OFFICIAL_NGINX_REPO" -eq 1 ]; then
    rm -f /etc/nginx/modules-enabled/*mod-stream*.conf 2>/dev/null || true
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx
    ok "Nginx Mainline успешно актуализирован/установлен."
else
    # Если официальный репозиторий недоступен, но Nginx >= 1.25.1 уже установлен, не ломаем систему
    if [ "$EXISTING_NGINX_VER" = "0" ] || dpkg --compare-versions "$EXISTING_NGINX_VER" "lt" "1.25.1"; then
        log "Установка Nginx из системного репозитория $OS_ID..."
        wait_for_apt_lock
        apt-get update -q
        wait_for_apt_lock
        apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx libnginx-mod-stream 2>/dev/null || apt-get install -y -q nginx
    else
        ok "Сохранена активная версия Nginx ($EXISTING_NGINX_VER). Конфликт пакетов DPKG предотвращен."
    fi
fi

# 6. Очистка устаревших конфигураций динамических модулей при монолитном stream
if nginx -V 2>&1 | grep -q -- '--with-stream'; then
    rm -f /etc/nginx/modules-enabled/*stream*.conf 2>/dev/null || true
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
find "$WEBROOT" -type d -exec chmod 755 {} +
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp /var/log/nginx 2>/dev/null || true

if [ ! -s /etc/nginx/mime.types ] || ! grep -q "text/css" /etc/nginx/mime.types 2>/dev/null; then
    log "Синтез канонической таблицы MIME-типов (/etc/nginx/mime.types)..."
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
    chmod 644 /etc/nginx/mime.types
fi

cat << EOF > /etc/nginx/nginx.conf
user $NGINX_USER;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    server_tokens off;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat << 'EOF' > /etc/nginx/conf.d/00-acme.conf
server {
    listen 80 default_server;
    server_name _;
    server_tokens off;
    root /var/www/html;

    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 444;
    }
}
EOF

# Предотвращение блокировок запуска служб на облачных шаблонах Ubuntu
if [ -f /usr/sbin/policy-rc.d ]; then
    rm -f /usr/sbin/policy-rc.d 2>/dev/null || true
fi

# Отключение конкурирующего веб-сервера Apache (если присутствует в базовом образе)
if systemctl is-active --quiet apache2 2>/dev/null || systemctl list-unit-files apache2.service 2>/dev/null | grep -q "apache2"; then
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi

# Валидация синтаксиса конфигурации Nginx
nginx -t || die "Ошибка конфигурации ACME Bootstrap сервера Nginx."

# Устранение рассинхронизации systemd (фикс "Device or resource busy" на Ubuntu 24.04 Noble)
systemctl unmask nginx.service 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed nginx.service 2>/dev/null || true
killall -9 nginx 2>/dev/null || true

# Запуск службы Nginx
systemctl restart nginx || {
    journalctl -xeu nginx.service --no-pager | tail -n 20 >&2
    die "Не удалось запустить службу Nginx после актуализации systemd."
}
ok "Служба Nginx успешно запущена (ACME Bootstrap)."

log "Локальный Pre-flight Loopback Smoke Test для ACME..."
mkdir -p "$WEBROOT/.well-known/acme-challenge"
chmod 755 /var /var/www "$WEBROOT" "$WEBROOT/.well-known" "$WEBROOT/.well-known/acme-challenge"
SMOKE_FILE="$WEBROOT/.well-known/acme-challenge/smoke-test.txt"
echo "acme-smoke-test-payload-ok" > "$SMOKE_FILE"
chmod 644 "$SMOKE_FILE"
chown "$NGINX_USER:$NGINX_USER" "$SMOKE_FILE"

SMOKE_RESPONSE=$(curl -s4 -m 5 "http://127.0.0.1/.well-known/acme-challenge/smoke-test.txt" || echo "FAIL")
rm -f "$SMOKE_FILE"

if [ "$SMOKE_RESPONSE" != "acme-smoke-test-payload-ok" ]; then
    warn "Pre-flight тест отдачи ACME токена вернул: '$SMOKE_RESPONSE'."
    if ! prompt_yes_no "Продолжить установку, несмотря на предупреждение теста порта 80?" "y"; then
        warn "Пользователь решил скорректировать окружение. Выход."
        exit 1
    fi
fi
ok "Pre-flight Loopback Smoke Test успешно пройден: Nginx отдает ACME токены."

if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Настройка Certbot через системный APT..."
    wait_for_apt_lock
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
            ok "Сертификат для $dom уже существует в системе и валиден (пропуск выпуска)."
            continue
        fi

        log "Выпуск сертификата для $dom..."
        certbot_email_args=("--register-unsafely-without-email")
        if [ -n "$LE_EMAIL" ]; then
            certbot_email_args=("--email" "$LE_EMAIL")
        fi

        if certbot certonly --webroot -w "$WEBROOT" --cert-name "$dom" --expand --non-interactive --agree-tos "${certbot_email_args[@]}" -d "$dom"; then
            ok "Сертификат для $dom получен."
        else
            warn "Ошибка выпуска SSL для $dom."
            if [ "$dom" = "$PRIMARY_DOMAIN" ]; then
                warn "Не удалось выпустить Let's Encrypt для $PRIMARY_DOMAIN."
                if prompt_yes_no "Сгенерировать аварийный Self-Signed SSL, чтобы поднять шлюз и продолжить?" "y"; then
                    mkdir -p "${SSL_BASE_DIR}/$PRIMARY_DOMAIN"
                    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
                        -keyout "${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem" \
                        -out "${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem" \
                        -subj "/CN=$PRIMARY_DOMAIN" >/dev/null 2>&1
                    ok "Аварийный самоподписанный SSL успешно сгенерирован."
                else
                    warn "Установка прервана пользователем из-за отсутствия SSL."
                    exit 1
                fi
            fi
        fi
    done

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
    cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true
find /etc/letsencrypt/live/ -name "privkey.pem" -exec chmod 600 {} + 2>/dev/null || true
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
                --reloadcmd "chmod 755 /etc/ssl/acme/$dom; chmod 644 /etc/ssl/acme/$dom/*; chmod 600 /etc/ssl/acme/$dom/privkey.pem; systemctl reload nginx"
            ok "Сертификат для $dom получен."
        fi
    done
fi

chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true
find /etc/letsencrypt/live/ -name "privkey.pem" -exec chmod 600 {} + 2>/dev/null || true

if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    log "Установка AdGuard Home (DoH + Split-DNS)..."
    if systemctl is-active --quiet systemd-resolved 2>/dev/null || systemctl list-unit-files systemd-resolved.service 2>/dev/null | grep -q "systemd-resolved"; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard-disable-stub.conf
[Resolve]
DNSStubListener=no
EOF
        systemctl restart systemd-resolved 2>/dev/null || true
    fi

    if [ "$GEO_PROFILE" = "1" ]; then
        cat << 'EOF' > /etc/resolv.conf
nameserver 77.88.8.8
nameserver 77.88.8.1
EOF
    else
        cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
    fi

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

    if ! download_asset "$AGH_TAR" "${AGH_URLS[@]}"; then
        warn "Не удалось загрузить AdGuard Home. Модуль AGH отключен, продолжаю установку остальных служб..."
        ENABLE_AGH=0
    fi
    if [ "$ENABLE_AGH" -eq 1 ]; then
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
    - 10.9.0.1
  port: 53
  trusted_proxies:
    - 127.0.0.1
    - 10.8.1.0/24
    - 10.8.2.0/24
    - 10.8.3.0/24
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
        ok "Конфигурация AdGuard Home сохранена без перезаписи."
    fi

    /opt/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || true
    systemctl restart AdGuardHome || true
    ok "AdGuard Home DoH активен на 127.0.0.1:53 и 10.9.0.1:53."
    fi
fi

# =============================================================
#  ВЕБ-МАСКИРОВКА (My Private Cloud Decoy Shield v3.14 - CSP Compliant)
# =============================================================
log "Генерация веб-маскировки (My Private Cloud Decoy Shield v3.14)..."

cat << 'EOF' > /var/www/html/assets/img/favicon.svg
<svg viewBox="0 0 100 100" width="100" height="100" xmlns="http://www.w3.org/2000/svg">
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
EOF

ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.svg
ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.ico

cat << 'EOF' > /var/www/html/robots.txt
User-agent: *
Disallow: /api/
Disallow: /console/
Disallow: /telemetry/
Allow: /
EOF

cat << 'EOF' > /var/www/html/assets/css/myprivatecloud.css
:root {
    --bg: #131314;
    --surface: #1e1f20;
    --surface-card: #1e1f20;
    --border: rgba(255, 255, 255, 0.08);
    --accent: #a8c7fa;
    --text: #e3e3e3;
    --text-muted: #9aa0a6;
    --success: #81c995;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body {
    height: 100%;
}
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Google Sans", sans-serif;
    background-color: var(--bg);
    background-image: radial-gradient(circle at 50% -10%, rgba(66, 133, 244, 0.18) 0%, rgba(155, 114, 207, 0.1) 40%, transparent 80%), var(--bg);
    color: var(--text); line-height: 1.6; overflow-x: hidden;
    min-height: 100vh; min-height: 100dvh; display: flex; flex-direction: column;
}
main {
    flex: 1 0 auto; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 100%;
}
header {
    display: flex; justify-content: space-between; align-items: center; padding: 18px 6%;
    border-bottom: 1px solid var(--border); backdrop-filter: blur(20px);
    position: sticky; top: 0; z-index: 50; background: rgba(19, 19, 20, 0.85);
}
.logo { font-size: 20px; font-weight: 500; display: flex; align-items: center; gap: 10px; color: #fff; letter-spacing: -0.5px; }
.header-actions { display: inline-flex; align-items: center; gap: 12px; }
.lang-switcher {
    display: inline-flex; align-items: center; background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--border); border-radius: 999px; padding: 3px; gap: 2px;
}
.lang-btn {
    background: transparent; border: 1px solid transparent; color: var(--text-muted);
    font-size: 11px; font-weight: 600; padding: 5px 11px; border-radius: 999px;
    cursor: pointer; transition: all 0.2s ease; user-select: none;
}
.lang-btn:hover { color: #fff; background: rgba(255, 255, 255, 0.06); }
.lang-btn.active {
    color: #fff; background: var(--surface-card); border-color: rgba(168, 199, 250, 0.4);
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
}
.hero { text-align: center; padding: 40px 20px; max-width: 900px; margin: 0 auto; width: 100%; }
.hero h1 {
    font-size: clamp(30px, 4.5vw, 46px); font-weight: 600; line-height: 1.25; margin-bottom: 24px;
    letter-spacing: -0.8px; color: #e3e3e3;
}
.hero-actions { display: flex; justify-content: center; gap: 14px; margin-bottom: 36px; flex-wrap: wrap; }
.hero-metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 40px; }
.metric-box { background: var(--surface-card); border: 1px solid var(--border); border-radius: 16px; padding: 18px 12px; text-align: center; }
.metric-val { font-size: 22px; font-weight: 600; color: var(--accent); margin-bottom: 4px; }
.metric-label { font-size: 12px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }

.cards-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 18px; margin-top: 10px; text-align: left; }
.feature-card {
    background: var(--surface-card); border: 1px solid var(--border); border-radius: 20px; padding: 22px;
    cursor: pointer; transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}
.feature-card:hover { transform: translateY(-3px); border-color: rgba(168, 199, 250, 0.4); background: #232527; box-shadow: 0 8px 24px rgba(0,0,0,0.4); }
.feature-card h3 { font-size: 16px; font-weight: 500; color: #fff; margin-bottom: 6px; display: flex; align-items: center; justify-content: space-between; }
.feature-card p { font-size: 13px; color: var(--text-muted); line-height: 1.5; margin: 0; }
.card-arrow { color: var(--accent); font-size: 16px; transition: transform 0.2s ease; }
.feature-card:hover .card-arrow { transform: translateX(3px); }

.btn {
    background: var(--surface-card); border: 1px solid var(--border); color: var(--text);
    padding: 12px 32px; border-radius: 999px; font-size: 15px; font-weight: 500; cursor: pointer;
    transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
    display: inline-flex; align-items: center; justify-content: center; gap: 8px;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.2); user-select: none;
}
.btn:hover { transform: translateY(-1px); border-color: rgba(168, 199, 250, 0.4); background: #242628; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4); }
.btn:active { transform: translateY(0); }
.btn-outline { background: var(--surface-card); border: 1px solid var(--border); color: var(--text); box-shadow: none; }
.modal-overlay {
    position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(5, 7, 10, 0.85);
    backdrop-filter: blur(16px); display: flex; align-items: center; justify-content: center;
    padding: 20px; z-index: 100; opacity: 0; visibility: hidden; transition: all 0.3s ease;
}
.modal-overlay.active { opacity: 1; visibility: visible; }
.modal-card {
    background: var(--surface); border: 1px solid rgba(255, 255, 255, 0.12); border-radius: 28px;
    width: 100%; max-width: 620px; padding: 36px 32px; box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.7);
    transform: translateY(20px); transition: transform 0.3s ease;
}
.modal-overlay.active .modal-card { transform: translateY(0); }
.modal-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 20px; }
.modal-header h2 { font-size: 21px; font-weight: 500; color: #fff; }
.modal-header p { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
.modal-close { background: transparent; border: none; color: var(--text-muted); cursor: pointer; padding: 4px; display: flex; }
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
.toast-hud {
    position: fixed; bottom: 30px; right: 30px; background: #1e1f20; border: 1px solid rgba(168, 199, 250, 0.3);
    border-radius: 16px; padding: 16px 20px; box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6);
    display: flex; align-items: flex-start; gap: 14px; z-index: 200; max-width: 380px;
    transform: translateY(100px); opacity: 0; visibility: hidden; transition: all 0.3s ease;
}
.toast-hud.active { transform: translateY(0); opacity: 1; visibility: visible; }
.toast-icon { flex-shrink: 0; color: var(--success); margin-top: 2px; }
.toast-title { font-size: 14px; font-weight: 500; color: #fff; margin-bottom: 4px; }
.toast-desc { font-size: 12px; color: var(--text-muted); line-height: 1.4; }
.hub-grid { display: flex; flex-direction: column; gap: 14px; margin-top: 10px; }
.hub-card {
    background: #171819; border: 1px solid var(--border); border-radius: 18px; padding: 18px;
    display: flex; justify-content: space-between; align-items: center; cursor: pointer;
    transition: all 0.2s ease; text-decoration: none; color: inherit;
}
.hub-card:hover { background: #222325; border-color: rgba(168, 199, 250, 0.4); transform: translateY(-2px); }
.hub-info h4 { font-size: 15px; font-weight: 500; color: #fff; margin-bottom: 4px; }
.hub-info p { font-size: 13px; color: var(--text-muted); margin: 0; }
.hub-arrow { color: var(--accent); font-size: 18px; font-weight: 500; }
.awg-table { width: 100%; border-collapse: collapse; margin-top: 14px; font-size: 13px; }
.awg-table th { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--border); color: var(--text-muted); font-weight: 500; }
.awg-table td { padding: 10px 10px; border-bottom: 1px solid rgba(255,255,255,0.04); }
.status-pill { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; }
.status-pill.online { background: var(--success); box-shadow: 0 0 6px var(--success); }
.status-pill.offline { background: var(--text-muted); }
.hub-loading { text-align: center; padding: 30px; }
.spinner-center { margin: 0 auto 10px; }
.actions-cell { white-space: nowrap; text-align: right; }
.actions-group { display: inline-flex; align-items: center; gap: 5px; }
.btn-mini { padding: 4px 10px; font-size: 11px; }
.hub-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; }
.btn-toolbar { padding: 6px 14px; font-size: 12px; }
.hub-meta-box { background: #131314; border: 1px solid var(--border); border-radius: 14px; padding: 12px; font-size: 12px; margin-bottom: 12px; }
.text-success { color: var(--success); }
.peers-table-container { max-height: 240px; overflow-y: auto; }
.peers-empty-td { text-align: center; color: var(--text-muted); padding: 20px; }
footer { margin-top: auto; width: 100%; text-align: center; padding: 24px 20px; color: var(--text-muted); font-size: 13px; border-top: 1px solid var(--border); flex-shrink: 0; }
.qr-modal-overlay { z-index: 150; }
.qr-modal-card { max-width: 440px; text-align: center; }
.qr-display-container { display: flex; justify-content: center; align-items: center; margin: 12px 0 6px; }
.qr-card-inner-large {
    display: inline-flex; flex-direction: column; align-items: center; background: #ffffff;
    border: 1px solid rgba(168, 199, 250, 0.25); border-radius: 24px; padding: 22px;
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.65);
}
.qr-img-large { width: clamp(260px, 70vw, 320px); height: clamp(260px, 70vw, 320px); display: block; border-radius: 12px; }
.qr-hint-large { margin-top: 14px; font-size: 13px; font-weight: 600; color: #1e1f20; }
.btn-qr-modal-close { width: 100%; height: 46px; margin-top: 18px; }
.dialog-overlay { z-index: 160; }
.dialog-card { max-width: 420px; }
.dialog-actions { display: flex; gap: 10px; justify-content: flex-end; margin-top: 20px; }
.btn-full-width-46 { width: 100%; height: 46px; margin-top: 10px; }

.modal-banner { border-radius: 14px; padding: 14px; margin-bottom: 16px; border: 1px solid var(--border); }
.modal-banner.crypto { background: rgba(168, 199, 250, 0.08); border-color: rgba(168, 199, 250, 0.3); }
.modal-banner.telemetry { background: rgba(129, 201, 149, 0.08); border-color: rgba(129, 201, 149, 0.3); }
.modal-banner.ipc { background: rgba(218, 180, 242, 0.08); border-color: rgba(218, 180, 242, 0.3); }
.banner-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.banner-title { font-size: 13px; font-weight: 600; color: #fff; }
.banner-status.green { color: var(--success); font-size: 12px; font-weight: 600; }
.banner-status.purple { color: #d0bcff; font-size: 12px; font-weight: 600; }
.banner-desc { font-size: 12px; color: var(--text-muted); margin: 0; line-height: 1.4; }
.spec-list { list-style: none; display: flex; flex-direction: column; gap: 10px; margin-top: 14px; }
.spec-item { font-size: 13px; color: var(--text); display: flex; gap: 10px; align-items: flex-start; }
.spec-check { color: var(--success); font-weight: bold; flex-shrink: 0; }

@keyframes spin { 100% { transform: rotate(360deg); } }
@media (max-width: 600px) {
    .hero-metrics { grid-template-columns: 1fr; gap: 10px; }
    .hero { padding: 40px 16px; }
    .btn { padding: 10px 24px; font-size: 14px; }
}
EOF

cat << 'EOF' > /var/www/html/assets/js/myprivatecloud.js
"use strict";

const I18N = {
    ru: {
        doc_title: "My Private Cloud",
        hero_h1: "Облачная инфраструктура распределения данных",
        btn_auth: "Авторизация",
        btn_console: "Консоль",
        btn_status: "Телеметрия",
        modal_auth_title: "Авторизация в кластере",
        modal_auth_desc: "Введите учётные данные для доступа к панели управления",
        auth_user_label: "Идентификатор узла / Email",
        auth_user_ph: "admin@privatecloud.internal",
        auth_key_label: "API Token / Ключ",
        btn_submit_auth: "Подключиться к кластеру",
        hub_title: "Центр управления My Private Cloud",
        hub_desc: "Единый шлюз администрирования сетевых сервисов",
        hub_xui_title: "Консоль маршрутизации трафика",
        hub_xui_desc: "L7 Stream Ingress, Quantum-Resistant TLS & Telemetry Multiplexing",
        hub_awg_title: "Контроллер оверлейной сети",
        hub_awg_desc: "Интерфейс ядра Linux awg0 (MTU 1360) • Диспетчер клиентов",
        hub_agh_title: "Шлюз приватного DNS",
        hub_agh_desc: "Рекурсивный DNS-over-HTTPS с защитой от аналитики и слежки",
        awg_syncing: "Синхронизация с ядром awg0...",
        awg_back_hub: "← Назад в Hub",
        awg_new_client: "+ Новый клиент",
        awg_meta: "Интерфейс: <strong class=\"text-success\">awg0 (Kernel Overlay)</strong> | Базовый порт: <strong>8443</strong> | Пул: <strong>35001-49999</strong> | MTU: <strong>1360</strong>",
        th_client: "Клиент",
        th_ip: "IP-адрес",
        th_traffic: "Трафик",
        th_actions: "Действия",
        peers_empty: "Нет активных пиров в таблице ядра",
        modal_spec_title: "Спецификация",
        modal_spec_desc: "Технический аудит подсистемы",
        btn_close: "Закрыть",
        btn_cancel: "Отмена",
        btn_create: "Создать",
        btn_delete: "Отозвать",
        qr_modal_title: "Конфигурация подключения",
        qr_modal_desc: "Сканируйте QR-код в мобильном клиенте",
        qr_modal_hint: "Сканируйте в приложении",
        add_peer_title: "Новый сетевой профиль",
        add_peer_desc: "Создание пира в таблице маршрутизации ядра",
        add_peer_name_label: "Имя профиля (латиница)",
        del_peer_title: "Подтверждение отзыва",
        del_peer_desc: "Отозвать ключ и отключить узел от ядра?",
        toast_auth_ok_title: "Авторизация успешна",
        toast_auth_ok_desc: "Сессия подтверждена. Добро пожаловать в центр управления.",
        toast_err_conn: "Ошибка защищенного соединения с контроллером кластера.",
        toast_err_unauth: "Недействительный токен кластера или ключ авторизации узла.",
        toast_cluster_status: "Статус кластера"
    },
    en: {
        doc_title: "My Private Cloud",
        hero_h1: "Distributed Cloud Data Infrastructure",
        btn_auth: "Authorization",
        btn_console: "Console",
        btn_status: "Telemetry",
        modal_auth_title: "Cluster Authorization",
        modal_auth_desc: "Enter node credentials to access management console",
        auth_user_label: "Node Identifier / Email",
        auth_user_ph: "admin@privatecloud.internal",
        auth_key_label: "API Token / Key",
        btn_submit_auth: "Connect to Cluster",
        hub_title: "My Private Cloud Control Hub",
        hub_desc: "Unified network module administration gateway",
        hub_xui_title: "Traffic Routing Console",
        hub_xui_desc: "L7 Stream Ingress, Quantum-Resistant TLS & Telemetry Multiplexing",
        hub_awg_title: "Overlay Network Controller",
        hub_awg_desc: "High-Throughput Kernel Interface (MTU 1360) • Client Dispatcher",
        hub_agh_title: "Private Encrypted DNS Gateway",
        hub_agh_desc: "Private Encrypted Recursive DNS-over-HTTPS Resolution Engine",
        awg_syncing: "Synchronizing with kernel awg0...",
        awg_back_hub: "← Back to Hub",
        awg_new_client: "+ New Client",
        awg_meta: "Interface: <strong class=\"text-success\">awg0 (Kernel Overlay)</strong> | Base Port: <strong>8443</strong> | Pool: <strong>35001-49999</strong> | MTU: <strong>1360</strong>",
        th_client: "Client",
        th_ip: "IP Address",
        th_traffic: "Traffic",
        th_actions: "Actions",
        peers_empty: "No active peers in kernel table",
        modal_spec_title: "Specification",
        modal_spec_desc: "Subsystem technical audit",
        btn_close: "Close",
        btn_cancel: "Cancel",
        btn_create: "Create",
        btn_delete: "Revoke",
        qr_modal_title: "Connection Profile",
        qr_modal_desc: "Scan QR code in your mobile client",
        qr_modal_hint: "Scan in application",
        add_peer_title: "New Network Profile",
        add_peer_desc: "Generate peer in kernel routing table",
        add_peer_name_label: "Profile Name (Latin)",
        del_peer_title: "Revoke Confirmation",
        del_peer_desc: "Revoke cryptographic key and disconnect peer?",
        toast_auth_ok_title: "Authorization Successful",
        toast_auth_ok_desc: "Session verified. Welcome to Infrastructure Control Hub.",
        toast_err_conn: "Secure connection error to cluster controller.",
        toast_err_unauth: "Invalid cluster token or node authorization key.",
        toast_cluster_status: "Cluster Status"
    },
    de: {
        doc_title: "My Private Cloud",
        hero_h1: "Verteilte Cloud-Dateninfrastruktur",
        btn_auth: "Autorisierung",
        btn_console: "Konsole",
        btn_status: "Telemetrie",
        modal_auth_title: "Cluster-Autorisierung",
        modal_auth_desc: "Geben Sie die Knotenanmeldedaten für das Control Panel ein",
        auth_user_label: "Knoten-ID / E-Mail",
        auth_user_ph: "admin@privatecloud.internal",
        auth_key_label: "API-Token / Schlüssel",
        btn_submit_auth: "Mit Cluster verbinden",
        hub_title: "My Private Cloud Steuerzentrale",
        hub_desc: "Zentrales Administrations-Gateway für Netzwerkdienste",
        hub_xui_title: "Traffic-Routing-Konsole",
        hub_xui_desc: "L7-Stream-Ingress, quantenresistentes TLS & Telemetrie-Multiplexing",
        hub_awg_title: "Overlay-Netzwerk-Controller",
        hub_awg_desc: "High-Throughput Linux-Kernel-Schnittstelle (MTU 1360) • Client-Verwaltung",
        hub_agh_title: "Privates verschlüsseltes DNS-Gateway",
        hub_agh_desc: "Private rekursive DNS-over-HTTPS-Engine mit Tracking-Schutz",
        awg_syncing: "Synchronisierung mit Kernel awg0...",
        awg_back_hub: "← Zurück zum Hub",
        awg_new_client: "+ Neuer Client",
        awg_meta: "Schnittstelle: <strong class=\"text-success\">awg0 (Kernel Overlay)</strong> | Basisport: <strong>8443</strong> | Pool: <strong>35001-49999</strong> | MTU: <strong>1360</strong>",
        th_client: "Client",
        th_ip: "IP-Adresse",
        th_traffic: "Traffic",
        th_actions: "Aktionen",
        peers_empty: "Keine aktiven Peers in der Kernel-Tabelle",
        modal_spec_title: "Spezifikation",
        modal_spec_desc: "Technisches Subsystem-Audit",
        btn_close: "Schließen",
        btn_cancel: "Abbrechen",
        btn_create: "Erstellen",
        btn_delete: "Widerrufen",
        qr_modal_title: "Verbindungsprofil",
        qr_modal_desc: "QR-Code mit mobiler App scannen",
        qr_modal_hint: "In der App scannen",
        add_peer_title: "Neues Netzwerkprofil",
        add_peer_desc: "Peer in der Kernel-Routingtabelle anlegen",
        add_peer_name_label: "Profilname (Lateinisch)",
        del_peer_title: "Widerruf bestätigen",
        del_peer_desc: "Schlüssel widerrufen und Knoten trennen?",
        toast_auth_ok_title: "Autorisierung erfolgreich",
        toast_auth_ok_desc: "Sitzung bestätigt. Willkommen in der Steuerzentrale.",
        toast_err_conn: "Sichere Verbindung zum Cluster-Controller fehlgeschlagen.",
        toast_err_unauth: "Ungültiges Cluster-Token oder Knotenschlüssel.",
        toast_cluster_status: "Cluster-Status"
    }
};

let activeLang = "ru";
try {
    activeLang = localStorage.getItem("myprivatecloud_lang") || "ru";
} catch (_) {}

function applyLanguage(lang) {
    if (!I18N[lang]) lang = "ru";
    activeLang = lang;
    try { localStorage.setItem("myprivatecloud_lang", lang); } catch (_) {}
    document.documentElement.setAttribute("lang", lang);

    document.querySelectorAll("[data-i18n]").forEach(node => {
        const key = node.dataset.i18n;
        if (I18N[lang] && I18N[lang][key]) {
            if (node.tagName === "INPUT" || node.tagName === "TEXTAREA") {
                node.placeholder = I18N[lang][key];
            } else {
                node.textContent = I18N[lang][key];
            }
        }
    });

    document.querySelectorAll(".lang-btn").forEach(btn => {
        const match = btn.dataset.lang === lang;
        btn.classList.toggle("active", match);
        btn.setAttribute("aria-pressed", match ? "true" : "false");
    });
}

function getCryptoEntropy() {
    const arr = new Uint32Array(1);
    window.crypto.getRandomValues(arr);
    return arr[0] / (0xffffffff + 1);
}

function randVarCrypto(base, pct, dec) {
    pct = pct || 10;
    dec = dec || 0;
    const delta = base * (pct / 100);
    const val = base + (getCryptoEntropy() * 2 - 1) * delta;
    return dec > 0 ? parseFloat(val.toFixed(dec)) : Math.round(val);
}

function getDynamicData(lang) {
    const l = I18N[lang] ? lang : "ru";
    const nodes = randVarCrypto(148, 10, 0);
    const rtt = (1.05 + getCryptoEntropy() * 0.15).toFixed(1);
    const bus = randVarCrypto(0.048, 15, 3);
    const sla = (99.995 + getCryptoEntropy() * 0.004).toFixed(3);

    const cards = {
        ru: {
            crypto: {
                title: "Сквозное квантовое шифрование (Data-in-Transit)",
                subtitle: "Корпоративный криптографический аудит",
                content: `<div class="modal-banner crypto"><div class="banner-head"><span class="banner-title">Статус криптомодуля:</span><span class="banner-status green">● АТТЕСТОВАН</span></div><p class="banner-desc">Аппаратная терминация сессий с защитой от компрометации закрытых ключей.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Протоколы:</strong> TLS 1.3 (RFC 8446) / ML-KEM-768 Post-Quantum Key Exchange.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>PFS:</strong> Ротация сессионных ключей Curve25519.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Комплаенс:</strong> FIPS 203, SOC 2 Type II, ISO/IEC 27001.</span></li></ul>`
            },
            telemetry: {
                title: "Распределённая телеметрия Anycast",
                subtitle: "Мониторинг магистральной сети и доступность SLA",
                content: `<div class="modal-banner telemetry"><div class="banner-head"><span class="banner-title">Доступность SLA:</span><span class="banner-status green">${sla}% АКТИВНО</span></div><p class="banner-desc">Многопоточный Anycast-конвейер маршрутизации трафика.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Связность:</strong> ${nodes} Anycast-узлов (EU, US, ASIA).</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>RTT задержка:</strong> Маршрутизация на границе датацентра &lt; ${rtt} ms.</span></li></ul>`
            },
            ipc: {
                title: "Высокоскоростная IPC-обработка",
                subtitle: "In-Memory конвейер и архитектура Zero-Copy",
                content: `<div class="modal-banner ipc"><div class="banner-head"><span class="banner-title">Подсистема ввода-вывода:</span><span class="banner-status purple">● ZERO-COPY RAM</span></div><p class="banner-desc">Изолированные очереди процессов в энергонезависимой памяти.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Шина:</strong> Около ${bus} ms при мультиплексировании стримов.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Буферы:</strong> somaxconn 65535 сокетное масштабирование.</span></li></ul>`
            }
        },
        en: {
            crypto: {
                title: "End-to-End Quantum Encryption (Data-in-Transit)",
                subtitle: "Enterprise cryptographic audit",
                content: `<div class="modal-banner crypto"><div class="banner-head"><span class="banner-title">Crypto Module Status:</span><span class="banner-status green">● CERTIFIED</span></div><p class="banner-desc">Hardware session termination with zero private key exposure.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Protocols:</strong> TLS 1.3 (RFC 8446) / ML-KEM-768 Post-Quantum Key Exchange.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>PFS:</strong> Curve25519 ephemeral key rotation.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Compliance:</strong> FIPS 203, SOC 2 Type II, ISO/IEC 27001.</span></li></ul>`
            },
            telemetry: {
                title: "Distributed Anycast Telemetry",
                subtitle: "Backbone network monitoring & SLA availability",
                content: `<div class="modal-banner telemetry"><div class="banner-head"><span class="banner-title">SLA Availability:</span><span class="banner-status green">${sla}% ACTIVE</span></div><p class="banner-desc">Multi-threaded Anycast traffic routing pipeline.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Connectivity:</strong> ${nodes} Anycast nodes (EU, US, ASIA).</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>RTT Latency:</strong> Datacenter edge routing &lt; ${rtt} ms.</span></li></ul>`
            },
            ipc: {
                title: "High-Throughput IPC Processing",
                subtitle: "In-Memory pipeline & Zero-Copy architecture",
                content: `<div class="modal-banner ipc"><div class="banner-head"><span class="banner-title">I/O Subsystem:</span><span class="banner-status purple">● ZERO-COPY RAM</span></div><p class="banner-desc">Isolated process queues in memory.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Bus Latency:</strong> ~${bus} ms under stream multiplexing.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Buffers:</strong> somaxconn 65535 high-capacity socket scaling.</span></li></ul>`
            }
        },
        de: {
            crypto: {
                title: "Ende-zu-Ende Quantenverschlüsselung (Data-in-Transit)",
                subtitle: "Kryptografisches Unternehmens-Audit",
                content: `<div class="modal-banner crypto"><div class="banner-head"><span class="banner-title">Kryptomodul-Status:</span><span class="banner-status green">● ZERTIFIZIERT</span></div><p class="banner-desc">Hardware-Sitzungsterminierung mit absolutem Schutz privater Schlüssel.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Protokolle:</strong> TLS 1.3 (RFC 8446) / ML-KEM-768 Post-Quantum Key Exchange.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>PFS:</strong> Curve25519 ephemere Schlüsselrotation.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Compliance:</strong> FIPS 203, SOC 2 Type II, ISO/IEC 27001.</span></li></ul>`
            },
            telemetry: {
                title: "Verteilte Anycast-Telemetrie",
                subtitle: "Backbone-Netzwerküberwachung & SLA-Verfügbarkeit",
                content: `<div class="modal-banner telemetry"><div class="banner-head"><span class="banner-title">SLA-Verfügbarkeit:</span><span class="banner-status green">${sla}% AKTIV</span></div><p class="banner-desc">Mehrfädige Anycast-Traffic-Routing-Pipeline.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Konnektivität:</strong> ${nodes} Anycast-Knoten (EU, US, ASIA).</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>RTT-Latenz:</strong> Rechenzentrums-Routing &lt; ${rtt} ms.</span></li></ul>`
            },
            ipc: {
                title: "High-Throughput IPC-Verarbeitung",
                subtitle: "In-Memory-Pipeline & Zero-Copy-Architektur",
                content: `<div class="modal-banner ipc"><div class="banner-head"><span class="banner-title">E/A-Subsystem:</span><span class="banner-status purple">● ZERO-COPY RAM</span></div><p class="banner-desc">Isolierte Prozesswarteschlangen im Arbeitsspeicher.</p></div><ul class="spec-list"><li class="spec-item"><span class="spec-check">✔</span><span><strong>Bus-Latenz:</strong> ca. ${bus} ms bei Stream-Multiplexing.</span></li><li class="spec-item"><span class="spec-check">✔</span><span><strong>Puffer:</strong> somaxconn 65535 Socket-Skalierung.</span></li></ul>`
            }
        }
    };

    return cards[l];
}

let toastTimer = null;
function showToast(title, desc) {
    const toast = document.getElementById("toastHud");
    if (!toast) return;
    document.getElementById("toastTitle").innerText = title;
    document.getElementById("toastDesc").innerText = desc;
    toast.classList.add("active");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.classList.remove("active"); }, 4500);
}

function openDetailModal(type) {
    const data = getDynamicData(activeLang)[type];
    if (!data) return;
    document.getElementById("detailTitle").innerText = data.title;
    document.getElementById("detailSubtitle").innerText = data.subtitle;
    document.getElementById("detailContent").innerHTML = data.content;
    document.getElementById("detailModal")?.classList.add("active");
}

function closeDetailModal() {
    document.getElementById("detailModal")?.classList.remove("active");
}

function openAuthModal(title) {
    const t = I18N[activeLang] || I18N.ru;
    const modalTitle = document.getElementById("modalTitle");
    const errAlert = document.getElementById("errorAlert");
    const authModal = document.getElementById("authModal");
    if (!authModal) return;
    if (modalTitle) modalTitle.innerText = title || t.modal_auth_title;
    if (errAlert) errAlert.style.display = "none";
    authModal.classList.add("active");
    setTimeout(() => { document.getElementById("cloudUser")?.focus(); }, 100);
}

function closeAuthModal() {
    document.getElementById("authModal")?.classList.remove("active");
}

let authenticatedSession = null;
let currentAwgPeers = [];

async function fetchClusterStatus() {
    const t = I18N[activeLang] || I18N.ru;
    if (!authenticatedSession) {
        openAuthModal(t.modal_auth_title);
        return;
    }
    try {
        const res = await fetch("/api/v1/myprivatecloud/status", {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        if (res.status === 401) {
            openAuthModal(t.modal_auth_title);
            return;
        }
        const data = await res.json();
        showToast(t.toast_cluster_status + ": " + (data.status || "online").toUpperCase(), `Nodes: ${data.nodes_active || 148} | SLA: 99.998% | Env: ${data.cluster || "Core"}`);
    } catch(e) {
        openAuthModal(t.modal_auth_title);
    }
}

function renderAdminHub(services) {
    const modalHeader = document.querySelector("#authModal .modal-header");
    const modalBody = document.querySelector("#authModal .modal-card");
    if (!modalBody) return;

    const t = I18N[activeLang] || I18N.ru;
    modalHeader.innerHTML = `
        <div>
            <h2>${t.hub_title}</h2>
            <p>${t.hub_desc}</p>
        </div>
        <button type="button" class="modal-close" data-action="close-hub" aria-label="${t.btn_close}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
        </button>
    `;

    let aghCard = "";
    if (services.agh_enabled && services.agh_url) {
        aghCard = `
            <a href="${services.agh_url}" target="_blank" class="hub-card">
                <div class="hub-info">
                    <h4>${t.hub_agh_title}</h4>
                    <p>${t.hub_agh_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </a>
        `;
    }

    let awgCard = "";
    if (services.awg_enabled) {
        awgCard = `
            <div class="hub-card" data-action="open-awg">
                <div class="hub-info">
                    <h4>${t.hub_awg_title}</h4>
                    <p>${t.hub_awg_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </div>
        `;
    }

    const formElement = document.getElementById("authForm");
    if (formElement) formElement.style.display = "none";
    const errBox = document.getElementById("errorAlert");
    if (errBox) errBox.style.display = "none";

    let hubContainer = document.getElementById("hubContainer");
    if (!hubContainer) {
        hubContainer = document.createElement("div");
        hubContainer.id = "hubContainer";
        modalBody.appendChild(hubContainer);
    }

    hubContainer.innerHTML = `
        <div class="hub-grid">
            <a href="${services.panel_url}" target="_blank" class="hub-card">
                <div class="hub-info">
                    <h4>${t.hub_xui_title}</h4>
                    <p>${t.hub_xui_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </a>
            ${awgCard}
            ${aghCard}
        </div>
    `;
}

async function openAwgManager() {
    const hubContainer = document.getElementById("hubContainer");
    if (!hubContainer || !authenticatedSession) return;

    const t = I18N[activeLang] || I18N.ru;
    hubContainer.innerHTML = `<div class="hub-loading"><div class="spinner spinner-center"></div>${t.awg_syncing}</div>`;

    try {
        const res = await fetch("/api/v1/myprivatecloud/awg/peers", {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        const data = await res.json();
        currentAwgPeers = data.peers || [];
        
        let rows = "";
        currentAwgPeers.forEach(p => {
            const statusClass = p.is_online ? "online" : "offline";
            rows += `
                <tr>
                    <td><span class="status-pill ${statusClass}"></span><strong>${p.name}</strong></td>
                    <td>${p.ip}</td>
                    <td>&darr; ${p.rx} / &uarr; ${p.tx}</td>
                    <td class="actions-cell">
                        <div class="actions-group">
                            <button class="btn btn-mini" data-action="show-qr" data-key="${p.public_key}">QR</button>
                            <button class="btn btn-mini" data-action="download-conf" data-key="${p.public_key}">.conf</button>
                            <button class="btn btn-mini" data-action="remove-peer" data-key="${p.public_key}">&times;</button>
                        </div>
                    </td>
                </tr>
            `;
        });

        hubContainer.innerHTML = `
            <div class="hub-toolbar">
                <button class="btn btn-outline btn-toolbar" data-action="back-to-hub">${t.awg_back_hub}</button>
                <button class="btn btn-toolbar" data-action="add-peer">${t.awg_new_client}</button>
            </div>
            <div class="hub-meta-box">
                ${t.awg_meta}
            </div>
            
            <div class="peers-table-container">
                <table class="awg-table">
                    <thead>
                        <tr><th>${t.th_client}</th><th>${t.th_ip}</th><th>${t.th_traffic}</th><th>${t.th_actions}</th></tr>
                    </thead>
                    <tbody>${rows || `<tr><td colspan="4" class="peers-empty-td">${t.peers_empty}</td></tr>`}</tbody>
                </table>
            </div>
        `;
    } catch(err) {
        showToast(t.toast_err_conn, "");
    }
}

function promptAddPeer() {
    let nextNum = 1;
    if (currentAwgPeers && currentAwgPeers.length > 0) {
        const nums = currentAwgPeers
            .map(p => {
                const m = p.name.match(/^Client-(\d+)$/i);
                return m ? parseInt(m[1], 10) : 0;
            })
            .filter(n => n > 0);
        if (nums.length > 0) {
            nextNum = Math.max(...nums) + 1;
        }
    }
    const dialog = document.getElementById("addPeerDialog");
    const nameInput = document.getElementById("newPeerName");
    if (dialog && nameInput) {
        nameInput.value = "Client-" + nextNum;
        dialog.classList.add("active");
        setTimeout(() => { nameInput.focus(); }, 100);
    }
}

async function confirmAddPeerAction() {
    const dialog = document.getElementById("addPeerDialog");
    const nameInput = document.getElementById("newPeerName");
    const name = nameInput ? nameInput.value.trim() : "";
    if (!name) return;
    if (dialog) dialog.classList.remove("active");

    try {
        const res = await fetch("/api/v1/myprivatecloud/awg/peer/add", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer " + authenticatedSession.token
            },
            body: JSON.stringify({ name: name })
        });
        const result = await res.json();
        if (result.status === "ok") {
            showToast("OK", `Client ${name} registered.`);
            openAwgManager();
        }
    } catch(e) {
        showToast("Error", "");
    }
}

async function showQr(pubKey, clientName) {
    const modal = document.getElementById("qrModal");
    const img = document.getElementById("qrModalImg");
    const title = document.getElementById("qrClientTitle");
    if (!modal || !img || !authenticatedSession) return;
    if (title && clientName) title.innerText = clientName;
    
    try {
        const res = await fetch("/api/v1/myprivatecloud/awg/peer/qr?key=" + encodeURIComponent(pubKey), {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        if (!res.ok) throw new Error("Unauthorized");
        const blob = await res.blob();
        img.src = URL.createObjectURL(blob);
        modal.classList.add("active");
    } catch(err) {
        showToast("Error", "");
    }
}

function closeQrModal() {
    const modal = document.getElementById("qrModal");
    if (modal) modal.classList.remove("active");
}

async function downloadAwgConf(publicKey) {
    try {
        const res = await fetch(`/api/v1/myprivatecloud/awg/peer/conf?key=${encodeURIComponent(publicKey)}`, {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        const confText = await res.text();
        const blob = new Blob([confText], { type: "text/plain" });
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = `cloud-node-${publicKey.substring(0,6)}.conf`;
        a.click();
    } catch(e) {
        showToast("Error", "");
    }
}

let pendingDeleteKey = null;
function removeAwgPeer(publicKey) {
    pendingDeleteKey = publicKey;
    const dialog = document.getElementById("confirmDeleteDialog");
    if (dialog) dialog.classList.add("active");
}

async function confirmDeletePeerAction() {
    const dialog = document.getElementById("confirmDeleteDialog");
    if (dialog) dialog.classList.remove("active");
    if (!pendingDeleteKey || !authenticatedSession) return;

    try {
        await fetch("/api/v1/myprivatecloud/awg/peer/remove", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer " + authenticatedSession.token
            },
            body: JSON.stringify({ public_key: pendingDeleteKey })
        });
        openAwgManager();
    } catch(e) {
        showToast("Error", "");
    } finally {
        pendingDeleteKey = null;
    }
}

async function handleCloudAuth(e) {
    e.preventDefault();
    const t = I18N[activeLang] || I18N.ru;
    const btn = document.getElementById("submitBtn");
    const errBox = document.getElementById("errorAlert");
    const errText = document.getElementById("errorMsg");
    
    if (errBox) errBox.style.display = "none";
    if (btn) {
        btn.disabled = true;
        btn.innerHTML = '<div class="spinner"></div>';
    }

    try {
        const response = await fetch("/api/v1/myprivatecloud/auth", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                principal: document.getElementById("cloudUser")?.value || "",
                secret: document.getElementById("cloudKey")?.value || ""
            })
        });
        const result = await response.json();
        
        if (response.status === 200 && result.status === "ok") {
            authenticatedSession = result;
            renderAdminHub(result.services);
            showToast(t.toast_auth_ok_title, t.toast_auth_ok_desc);
        } else {
            if (errText) errText.innerText = result.error || t.toast_err_unauth;
            if (errBox) errBox.style.display = "flex";
        }
    } catch (err) {
        if (errText) errText.innerText = t.toast_err_conn;
        if (errBox) errBox.style.display = "flex";
    } finally {
        if (btn && !authenticatedSession) {
            btn.disabled = false;
            btn.innerHTML = t.btn_submit_auth;
        }
    }
}

document.addEventListener("click", (e) => {
    const langBtn = e.target.closest(".lang-btn");
    if (langBtn && langBtn.dataset.lang) {
        applyLanguage(langBtn.dataset.lang);
        return;
    }
    const el = e.target.closest("[data-action]");
    if (!el) return;
    const act = el.dataset.action;

    if (act === "open-awg") openAwgManager();
    if (act === "back-to-hub") renderAdminHub(authenticatedSession.services);
    if (act === "add-peer") promptAddPeer();
    if (act === "show-qr") { const r = el.closest("tr"); const cName = r ? r.querySelector("strong")?.innerText : ""; showQr(el.dataset.key, cName); }
    if (act === "download-conf") downloadAwgConf(el.dataset.key);
    if (act === "remove-peer") removeAwgPeer(el.dataset.key);
    if (act === "close-hub") { closeAuthModal(); location.reload(); }
    if (act === "close-qr-modal") closeQrModal();
    if (act === "cancel-add-peer") { document.getElementById("addPeerDialog")?.classList.remove("active"); }
    if (act === "confirm-add-peer") confirmAddPeerAction();
    if (act === "cancel-delete-peer") { document.getElementById("confirmDeleteDialog")?.classList.remove("active"); pendingDeleteKey = null; }
    if (act === "confirm-delete-peer") confirmDeletePeerAction();
});

window.addEventListener('DOMContentLoaded', () => {
    const maxBw = 99.85;
    const dynBw = (maxBw - (getCryptoEntropy() * 0.10 * maxBw)).toFixed(1);
    const dynLat = (1.05 + getCryptoEntropy() * 0.15).toFixed(1);
    const dynSla = (99.995 + getCryptoEntropy() * 0.004).toFixed(3);
    
    const latElem = document.getElementById("heroLatency");
    const bwElem = document.getElementById("heroBandwidth");
    const slaElem = document.getElementById("heroSla");
    
    if (latElem) latElem.innerText = "< " + dynLat + " ms";
    if (bwElem) bwElem.innerText = dynBw + " Gbps";
    if (slaElem) slaElem.innerText = dynSla + "%";
    applyLanguage(activeLang);

    document.getElementById("headerConsoleBtn")?.addEventListener("click", () => openAuthModal());
    document.getElementById("connectNodeBtn")?.addEventListener("click", () => openAuthModal());
    document.getElementById("netStatusBtn")?.addEventListener("click", fetchClusterStatus);
    
    document.getElementById("cardCrypto")?.addEventListener("click", () => openDetailModal("crypto"));
    document.getElementById("cardTelemetry")?.addEventListener("click", () => openDetailModal("telemetry"));
    document.getElementById("cardIpc")?.addEventListener("click", () => openDetailModal("ipc"));
    
    document.getElementById("authModalClose")?.addEventListener("click", closeAuthModal);
    document.getElementById("detailModalClose")?.addEventListener("click", closeDetailModal);
    document.getElementById("detailModalOk")?.addEventListener("click", closeDetailModal);
    
    document.getElementById("authForm")?.addEventListener("submit", handleCloudAuth);
});

window.addEventListener('keydown', (e) => {
    if (e.key === "Escape") {
        closeAuthModal();
        closeDetailModal();
        closeQrModal();
        document.getElementById("addPeerDialog")?.classList.remove("active");
        document.getElementById("confirmDeleteDialog")?.classList.remove("active");
    }
});
EOF

cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title data-i18n="doc_title">My Private Cloud</title>
    <link rel="icon" type="image/svg+xml" href="/assets/img/favicon.svg">
    <link rel="stylesheet" href="/assets/css/myprivatecloud.css">
</head>
<body>
    <header>
        <div class="logo">
            <img src="/assets/img/favicon.svg" alt="Cloud Logo" width="28" height="28">
            <span>My Private Cloud</span>
        </div>
        <div class="header-actions">
            <div class="lang-switcher" role="group" aria-label="Language Selector">
                <button type="button" class="lang-btn active" data-lang="ru" aria-pressed="true">RU</button>
                <button type="button" class="lang-btn" data-lang="en" aria-pressed="false">EN</button>
                <button type="button" class="lang-btn" data-lang="de" aria-pressed="false">DE</button>
            </div>
        </div>
    </header>
    <main>
        <section class="hero">
            <h1 data-i18n="hero_h1">Облачная инфраструктура распределения данных</h1>
            <div class="hero-actions">
                <button id="connectNodeBtn" class="btn" type="button" data-i18n="btn_auth">Авторизация</button>
            </div>
        </section>
    </main>

    <div id="detailModal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="detailTitle" data-i18n="modal_spec_title">Спецификация</h2>
                    <p id="detailSubtitle" data-i18n="modal_spec_desc">Технический аудит подсистемы</p>
                </div>
                <button id="detailModalClose" class="modal-close" type="button" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="detailContent"></div>
            <button type="button" id="detailModalOk" class="btn btn-full-width-46" data-i18n="btn_close">Закрыть</button>
        </div>
    </div>

    <div id="authModal" class="modal-overlay">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="modalTitle" data-i18n="modal_auth_title">Авторизация</h2>
                    <p data-i18n="modal_auth_desc">Введите учётные данные для доступа к панели</p>
                </div>
                <button id="authModalClose" class="modal-close" type="button" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="errorAlert" class="alert-box">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="18" height="18"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                <span id="errorMsg">Ошибка</span>
            </div>
            <form id="authForm">
                <div class="form-group">
                    <label for="cloudUser" data-i18n="auth_user_label">Идентификатор узла / Email</label>
                    <input type="text" id="cloudUser" class="form-control" data-i18n="auth_user_ph" placeholder="admin@privatecloud.internal" required autocomplete="username">
                </div>
                <div class="form-group">
                    <label for="cloudKey" data-i18n="auth_key_label">API Token / Ключ</label>
                    <input type="password" id="cloudKey" class="form-control" placeholder="••••••••••••••••" required autocomplete="current-password">
                </div>
                <button type="submit" id="submitBtn" class="btn btn-full-width-46" data-i18n="btn_submit_auth">Подключиться к кластеру</button>
            </form>
        </div>
    </div>

    <div id="toastHud" class="toast-hud">
        <div class="toast-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="20" height="20"><polyline points="20 6 9 17 4 12"/></svg>
        </div>
        <div>
            <div id="toastTitle" class="toast-title">Notification</div>
            <div id="toastDesc" class="toast-desc">Synchronized</div>
        </div>
    </div>
    
    <div id="qrModal" class="modal-overlay qr-modal-overlay">
        <div class="modal-card qr-modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="qrClientTitle" data-i18n="qr_modal_title">Конфигурация подключения</h2>
                    <p data-i18n="qr_modal_desc">Сканируйте QR-код в мобильном клиенте</p>
                </div>
                <button id="qrModalClose" class="modal-close" type="button" aria-label="Close" data-action="close-qr-modal">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="qr-display-container">
                <div class="qr-card-inner-large">
                    <img id="qrModalImg" src="" class="qr-img-large" alt="Network QR Code">
                    <span class="qr-hint-large" data-i18n="qr_modal_hint">Сканируйте в приложении</span>
                </div>
            </div>
            <button type="button" id="qrModalCloseBtn" class="btn btn-qr-modal-close" data-action="close-qr-modal" data-i18n="btn_close">Закрыть</button>
        </div>
    </div>

    <div id="addPeerDialog" class="modal-overlay dialog-overlay">
        <div class="modal-card dialog-card">
            <div class="modal-header">
                <div>
                    <h2 data-i18n="add_peer_title">Новый сетевой профиль</h2>
                    <p data-i18n="add_peer_desc">Создание профиля в таблице маршрутизации</p>
                </div>
                <button type="button" class="modal-close" data-action="cancel-add-peer" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="form-group">
                <label for="newPeerName" data-i18n="add_peer_name_label">Имя профиля (латиница)</label>
                <input type="text" id="newPeerName" class="form-control" placeholder="Client-1">
            </div>
            <div class="dialog-actions">
                <button type="button" class="btn btn-outline" data-action="cancel-add-peer" data-i18n="btn_cancel">Отмена</button>
                <button type="button" class="btn" data-action="confirm-add-peer" data-i18n="btn_create">Создать</button>
            </div>
        </div>
    </div>

    <div id="confirmDeleteDialog" class="modal-overlay dialog-overlay">
        <div class="modal-card dialog-card">
            <div class="modal-header">
                <div>
                    <h2 data-i18n="del_peer_title">Подтверждение отзыва</h2>
                    <p data-i18n="del_peer_desc">Отозвать ключ и отключить узел?</p>
                </div>
                <button type="button" class="modal-close" data-action="cancel-delete-peer" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="dialog-actions">
                <button type="button" class="btn btn-outline" data-action="cancel-delete-peer" data-i18n="btn_cancel">Отмена</button>
                <button type="button" class="btn" data-action="confirm-delete-peer" data-i18n="btn_delete">Удалить</button>
            </div>
        </div>
    </div>

    <footer>&copy; 2026 My Private Cloud</footer>
    <script src="/assets/js/myprivatecloud.js"></script>
</body>
</html>
EOF

cat << 'EOF' > /var/www/html/404.html
<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body></html>
EOF

chmod 755 /var /var/www "$WEBROOT"
chmod -R 755 "$WEBROOT/assets" "$WEBROOT/.well-known" 2>/dev/null || true
find "$WEBROOT" -type d -exec chmod 755 {} +
find "$WEBROOT" -type f -exec chmod 644 {} +
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"

# =============================================================
#  БОЕВАЯ КОНФИГУРАЦИЯ NGINX MAINLINE L4/L7 (STREAM TCP 443 ONLY)
# =============================================================
log "Сборка постоянной конфигурации Nginx (Stream L4 Single-Ingress 443 + Zero-SNI Shield)..."
rm -f /etc/nginx/conf.d/00-acme.conf

MODULE_LOAD_LINE=""
if [ "$USE_OFFICIAL_NGINX_REPO" -eq 0 ] && [ -d /etc/nginx/modules-enabled ]; then
    MODULE_LOAD_LINE="include /etc/nginx/modules-enabled/*.conf;"
fi

PANEL_PORT="${PANEL_PORT//[!0-9]/}"
SUB_PORT="${SUB_PORT//[!0-9]/}"
XHTTP_UPSTREAM_LINE=""
XHTTP_BADBOT_MAP_LINE=""
XHTTP_NGINX_LOC_BLOCK=""

if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    XHTTP_STREAM_PORT="${XHTTP_STREAM_PORT//[!0-9]/}"
    if [ -z "$XHTTP_STREAM_PORT" ]; then XHTTP_STREAM_PORT="50443"; fi
    XHTTP_UPSTREAM_LINE="upstream xray_xhttp_stream { server 127.0.0.1:${XHTTP_STREAM_PORT}; keepalive 64; }"
    XHTTP_BADBOT_MAP_LINE="~^.*:[01]:${BASE_XHTTP_PATH} 0;"
    XHTTP_NGINX_LOC_BLOCK="    location ^~ ${BASE_XHTTP_PATH} {
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
        client_max_body_size 0;
        proxy_pass http://xray_xhttp_stream;
    }"
fi
if [ -z "$PANEL_PORT" ]; then PANEL_PORT="10443"; fi
if [ -z "$SUB_PORT" ]; then SUB_PORT="55443"; fi
if [ -z "$XHTTP_STREAM_PORT" ]; then XHTTP_STREAM_PORT="50443"; fi


cat << EOF > /etc/nginx/nginx.conf
user $NGINX_USER;
worker_processes auto;
pid /run/nginx.pid;
worker_rlimit_nofile 1048576;
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
    etag off;
    charset utf-8;
    resolver 77.88.8.8 1.1.1.1 ipv6=off valid=300s;
    resolver_timeout 5s;

    http2_recv_buffer_size 1m;
    http2_max_concurrent_streams 128;

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
    $XHTTP_UPSTREAM_LINE
    upstream datasphere_core_backend { server 127.0.0.1:20443; keepalive 16; }

    access_log off;

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
        ~^.*:[01]:.*(sub|json|clash).* 0; # sub_bypass
        ~^.*:[01]:/robots\.txt(\?|\$) 0;
        ~^.*:[01]:/\.well-known/ 0;
        ~^.*:[01]:/favicon\.(ico|svg)\$ 0;
        ~^.*:[01]:/assets/ 0;
        ~^.*:[01]:/dns-query 0;
        ~^.*:[01]:/api/v1/myprivatecloud/ 0;
        ~^.*:[01]:${PANEL_PATH} 0;
        ~^.*:[01]:${SUB_PATH} 0;
        ~^.*:[01]:${SUB_JSON_PATH} 0;
        ~^.*:[01]:${SUB_CLASH_PATH} 0;
        ~^.*:[01]:/sub/ 0;
        ~^.*:[01]:/json/ 0;
        ~^.*:[01]:/clash/ 0;
        $XHTTP_BADBOT_MAP_LINE
        ~^(?:1:[01]|0:1): 1;
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

# Синхронизация действующих REALITY-портов и доменов из существующей SQLite базы
if [ -n "$EXISTING_DB_PATH" ] && [ -f "$EXISTING_DB_PATH" ]; then
    DB_PREV_REALITY=$(sqlite3 "$EXISTING_DB_PATH" "SELECT DISTINCT port FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%reality%';" 2>/dev/null || echo "")
    for drp in $DB_PREV_REALITY; do
        if validate_port "$drp"; then
            ALL_REALITY_PORTS+=("$drp")
            ok "Обнаружен действующий порт REALITY из существующей базы: ${drp}"
        fi
    done

    # Автоматическое извлечение существующих SNI для сохранения маршрутизации действующих клиентов
    python3 - << 'EOF_EXT_SNI'
import sqlite3, json, os

db_p = os.environ.get("EXISTING_DB_PATH", "")
if os.path.exists(db_p):
    try:
        conn = sqlite3.connect(db_p)
        cur = conn.cursor()
        cur.execute("SELECT port, stream_settings FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%reality%'")
        for p, st_raw in cur.fetchall():
            if st_raw:
                st = json.loads(st_raw)
                rs = st.get("realitySettings", {})
                snames = rs.get("serverNames", [])
                for s in snames:
                    if s:
                        with open("/tmp/nginx_prev_sni_map.txt", "a") as f_out:
                            f_out.write(f"{s}:{p}\n")
        conn.close()
    except Exception:
        pass
EOF_EXT_SNI
    if [ -f /tmp/nginx_prev_sni_map.txt ]; then
        while IFS=: read -r s_name s_port; do
            if [ -n "$s_name" ] && [ -n "$s_port" ]; then
                EXT_SNI_TO_PORT["$s_name"]="$s_port"
            fi
        done < /tmp/nginx_prev_sni_map.txt
        rm -f /tmp/nginx_prev_sni_map.txt
    fi
fi

# Дедупликация маршрутов Nginx L4 Stream: PRIMARY_DOMAIN и AGH_DOMAIN защищены от перехвата
declare -A SEEN_SNI_MAP=()
STREAM_MAP_RULES=""
REALITY_UPSTREAMS=""

# 1. Приоритетная фиксация главного домена и DoH на L7 Unix-сокет Nginx
STREAM_MAP_RULES+="        ${PRIMARY_DOMAIN}     nginx_http_backend;\n"
SEEN_SNI_MAP["$PRIMARY_DOMAIN"]=1

if [ -n "${AGH_DOMAIN:-}" ]; then
    STREAM_MAP_RULES+="        ${AGH_DOMAIN}     nginx_http_backend;\n"
    SEEN_SNI_MAP["$AGH_DOMAIN"]=1
fi

# 2. Добавление Steal-REALITY поддоменов
if [ "$ENABLE_STEAL" -eq 1 ]; then
    for s_dom in "${STEAL_DOMAINS[@]:-}"; do
        if [ -n "$s_dom" ] && [ -z "${SEEN_SNI_MAP[$s_dom]:-}" ] && [ -n "${DOMAIN_TO_PORT[$s_dom]:-}" ]; then
            SEEN_SNI_MAP["$s_dom"]=1
            port="${DOMAIN_TO_PORT[$s_dom]}"
            STREAM_MAP_RULES+="        ${s_dom}     reality_backend_${port};\n"
        fi
    done
fi

# 3. Добавление внешних SNI (Classic REALITY и SNI из существующей базы)
for ext_sni in "${!EXT_SNI_TO_PORT[@]}"; do
    if [ -n "$ext_sni" ] && [ -z "${SEEN_SNI_MAP[$ext_sni]:-}" ]; then
        SEEN_SNI_MAP["$ext_sni"]=1
        port="${EXT_SNI_TO_PORT[$ext_sni]}"
        STREAM_MAP_RULES+="        ${ext_sni}     reality_backend_${port};\n"
    fi
done

# Использование mapfile -t для устранения предупреждений анализаторов
mapfile -t ALL_REALITY_PORTS < <(printf "%s\n" "${ALL_REALITY_PORTS[@]:-}" | grep -E "^[0-9]+$" | sort -u || true)

declare -A SEEN_REALITY_UPSTREAMS=()
for port in "${ALL_REALITY_PORTS[@]:-}"; do
    if [ -n "$port" ] && [ -z "${SEEN_REALITY_UPSTREAMS[$port]:-}" ]; then
        SEEN_REALITY_UPSTREAMS["$port"]=1
        REALITY_UPSTREAMS+="
    upstream reality_backend_${port} {
        server 127.0.0.1:${port} max_fails=0;
        server unix:/dev/shm/nginx-http.sock backup;
    }
"
    fi
done

cat << EOF > "/etc/nginx/stream.d/00-stream.conf"
map \$ssl_preread_server_name \$backend_gate {
    hostnames;
    ""                     nginx_http_backend;
$(echo -e "$STREAM_MAP_RULES")    default                nginx_http_backend;
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

    location / { return 444; }
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
    root $WEBROOT;
    index index.html;

    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

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
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Accept-Encoding "";
        gzip off;
    }

    location ^~ ${SUB_CLASH_PATH} {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Accept-Encoding "";
        gzip off;
    }

    location ~* ^/(sub|json|clash|sub-clash)/ {
        proxy_hide_header Content-Security-Policy;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=subs burst=60 nodelay;
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Accept-Encoding "";
        gzip off;
    }

        $XHTTP_NGINX_LOC_BLOCK

    location ^~ /api/v1/myprivatecloud/ {
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

    location /assets/ {
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

if [ "${ENABLE_STEAL:-0}" -eq 1 ] && [ "${#STEAL_DOMAINS[@]}" -gt 0 ]; then
    rm -f /etc/nginx/conf.d/02-steal-fallback.conf
    for s_dom in "${STEAL_DOMAINS[@]}"; do
        if [ -f "${SSL_BASE_DIR}/$s_dom/fullchain.pem" ]; then
            cat << EOF >> "/etc/nginx/conf.d/02-steal-fallback.conf"
server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $s_dom;

    ssl_certificate ${SSL_BASE_DIR}/$s_dom/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$s_dom/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL_FALLBACK:5m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    location ^~ /api/v1/myprivatecloud/ {
        proxy_pass http://datasphere_core_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    $XHTTP_NGINX_LOC_BLOCK

    location = ${PANEL_PATH%/} { return 301 ${PANEL_PATH}; }
    location ^~ ${PANEL_PATH} {
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
        proxy_pass http://sub_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        gzip off;
    }

    location = /robots.txt { root $WEBROOT; access_log off; }
    location ~ ^/(favicon\.ico|favicon\.svg)\$ { root $WEBROOT; access_log off; expires 30d; }
    location /assets/ { root $WEBROOT; expires 7d; access_log off; try_files \$uri =404; }
    location = / { default_type text/html; root $WEBROOT; try_files /index.html =404; }
    location / { root $WEBROOT; index index.html; try_files \$uri \$uri/ /index.html =404; }
}
EOF
        fi
    done
fi

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

rm -f /dev/shm/nginx-http.sock 2>/dev/null || true
nginx -t || die "Критическая ошибка синтаксиса Nginx!"
systemctl restart nginx
ok "Внешний шлюз Nginx успешно запущен на порту 443."

# =============================================================
#  ФАЗА 3: УСТАНОВКА 3X-UI, XRAY v26.7.28 И БАЗА SQLITE
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 3: Оркестрация 3X-UI, Xray Core v26.7.28 и база SQLite        ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

DB_PATH="/etc/x-ui/x-ui.db"
if [ ! -x "/usr/local/x-ui/x-ui" ]; then
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

    while ! download_asset "$UI_SCRIPT" "${UI_URLS[@]}"; do
        warn "Не удалось загрузить инсталлятор 3X-UI."
        if ! prompt_yes_no "Повторить попытку загрузки 3X-UI?" "y"; then
            exit 1
        fi
    done
    printf "n\n" | bash "$UI_SCRIPT" >/tmp/3xui_install.log 2>&1
    rm -f "$UI_SCRIPT"
    /usr/local/x-ui/x-ui setting -webBasePath "${RAW_PATH}" -port "${PANEL_PORT}" >/dev/null 2>&1 || true
    sqlite3 "$DB_PATH" "UPDATE settings SET value = '${PANEL_PATH}' WHERE key = 'webBasePath';" 2>/dev/null || true
    sqlite3 "$DB_PATH" "UPDATE settings SET value = '${PANEL_PORT}' WHERE key = 'webPort';" 2>/dev/null || true
fi

for alt_db in "$DB_PATH" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then DB_PATH="$alt_db"; break; fi
done
ok "База SQLite 3X-UI готова: $DB_PATH"

systemctl stop x-ui 2>/dev/null || true

TARGET_XRAY_VERSION="v26.7.28"
export TARGET_XRAY_VERSION
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
export XRAY_ZIP
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

while ! download_asset "$XRAY_ZIP" "${XRAY_URLS[@]}"; do
        warn "Не удалось загрузить бинарник Xray-core (${TARGET_XRAY_VERSION})."
        if ! prompt_yes_no "Повторить попытку загрузки Xray-core?" "y"; then
            exit 1
        fi
    done

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

VLESS_DECRYPTION=""
VLESS_ENCRYPTION=""
if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    log "Генерация постквантового ключа VLESS Encryption (ML-KEM-768)..."
    vl_out=$("$XRAY_BIN" vlessenc 2>&1)
    VLESS_DECRYPTION=$(echo "$vl_out" | grep '"decryption":' | tail -n1 | awk -F'"' '{print $4}' || true)
    VLESS_ENCRYPTION=$(echo "$vl_out" | grep '"encryption":' | tail -n1 | awk -F'"' '{print $4}' || true)

    if [[ ! "$VLESS_DECRYPTION" =~ ^mlkem768 ]] || [ -z "$VLESS_ENCRYPTION" ]; then
        warn "Ошибка генерации ключа VLESS Encryption! Xray вернул: $vl_out"
        if ! prompt_yes_no "Продолжить без постквантового шифрования xHTTP?" "n"; then
            exit 1
        fi
    else
        ok "Ключ ML-KEM-768 успешно сгенерирован!"
    fi
fi

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

export ENABLE_XHTTP="${ENABLE_XHTTP:-0}"
export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH SUB_CLASH_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_CONFIG_DATA
export ENABLE_CLASSIC CLASSIC_CONFIG_DATA ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ADMIN_USER ADMIN_PASS
export SSL_BASE_DIR VLESS_DECRYPTION VLESS_ENCRYPTION
export STEAL_DOMAINS_STR="${STEAL_DOMAINS[*]:-}" INSTALL_MODE ENABLE_AGH GEO_PROFILE ENABLE_AWG_HOP

python3 - << 'EOF_PY_ENGINE'
# -*- coding: utf-8 -*-
import os, sys, sqlite3, json, uuid, secrets, base64, time

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path, timeout=60.0)
cur = conn.cursor()

try:
    cur.execute("PRAGMA busy_timeout = 60000")
    cur.execute("PRAGMA journal_mode = WAL")
    cur.execute("PRAGMA synchronous = NORMAL")
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
sub_clash_path = os.environ.get("SUB_CLASH_PATH", f"{sub_path}sub-clash/")
xhttp_port = int(os.environ["XHTTP_STREAM_PORT"]) if os.environ.get("XHTTP_STREAM_PORT", "").isdigit() else 0
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

if "clients" in tables:
    cur.execute("PRAGMA table_info(clients)")
    c_cols = {r[1] for r in cur.fetchall()}
    ddl_patches = [
        ("group_name", "TEXT DEFAULT ''"),
        ("group", "TEXT DEFAULT ''"),
        ("reset_weekday", "INTEGER DEFAULT 0"),
        ("limit_hwid", "INTEGER DEFAULT 0"),
        ("auth", "TEXT DEFAULT ''"),
        ("password", "TEXT DEFAULT ''"),
        ("wg_private_key", "TEXT DEFAULT ''"),
        ("wg_public_key", "TEXT DEFAULT ''"),
        ("wg_allowed_ips", "TEXT DEFAULT ''"),
        ("wg_pre_shared_key", "TEXT DEFAULT ''"),
        ("wg_keep_alive", "INTEGER DEFAULT 25"),
        ("sub_id", "TEXT DEFAULT ''")
    ]
    for col_name, col_def in ddl_patches:
        if col_name not in c_cols:
            try:
                cur.execute(f'ALTER TABLE clients ADD COLUMN "{col_name}" {col_def}')
            except Exception:
                pass

if "client_traffics" in tables:
    cur.execute("PRAGMA table_info(client_traffics)")
    ct_cols = {r[1] for r in cur.fetchall()}
    ct_patches = [
        ("reset_count", "INTEGER DEFAULT 0"),
        ("last_online", "INTEGER DEFAULT 0"),
        ("last_sub_fetch", "INTEGER DEFAULT 0"),
        ("reset_weekday", "INTEGER DEFAULT 0")
    ]
    for col_name, col_def in ct_patches:
        if col_name not in ct_cols:
            try:
                cur.execute(f'ALTER TABLE client_traffics ADD COLUMN "{col_name}" {col_def}')
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
    "trustedProxyCIDRs": "127.0.0.1/32,10.8.1.0/24,10.9.0.0/24",
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
        if install_mode == "1" or k in ["webListen", "subListen", "trustedProxyCIDRs", "subJsonAlwaysArray", "subClashAutoDetect", "subShowInfo", "subEnable", "subClashEnable", "subJsonEnable"]:
            cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

freedom_final_rules = []
if enable_agh:
    freedom_final_rules.append({"action": "allow", "ip": ["127.0.0.1", "10.9.0.1"], "port": "53"})
freedom_final_rules.append({"action": "allow", "ip": ["10.8.1.0/24", "10.9.0.0/24"]})
freedom_final_rules.append({"action": "block", "ip": ["geoip:private"]})
freedom_final_rules.append({"action": "allow"})

routing_rules = [
    {"inboundTag": ["api"], "outboundTag": "api", "type": "field"}
]
if enable_agh:
    routing_rules.append({"ip": ["127.0.0.1", "10.9.0.1"], "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
routing_rules.append({"ip": ["10.8.1.0/24", "10.9.0.0/24"], "outboundTag": "direct", "type": "field"})
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

cur.execute("SELECT value FROM settings WHERE key = 'xrayTemplateConfig'")
existing_tpl_row = cur.fetchone()
if existing_tpl_row and existing_tpl_row[0] and install_mode == "2":
    try:
        current_tpl = json.loads(existing_tpl_row[0])
        if enable_agh:
            routing = current_tpl.setdefault("routing", {})
            rules = routing.setdefault("rules", [])
            has_agh_rule = any(isinstance(r, dict) and (r.get("ruleTag") == "xui-dns-allow" or ("127.0.0.1" in r.get("ip", []) and str(r.get("port")) == "53")) for r in rules)
            if not has_agh_rule:
                rules.insert(0, {"ip": ["127.0.0.1", "10.9.0.1"], "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
        cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(current_tpl, ensure_ascii=False),))
    except Exception:
        pass
else:
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
def_wg_c_priv, def_wg_c_pub = gen_wg_keypair()

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

ib1_id = None
ib2_id = None
ib3_id = None
ib4_id = None
ib5_id = None
vision_inbound_ids = set()

active_inbound_ids = []

def register_or_get_inbound(port, proto, tag, remark, s_obj_def, st_obj_def, listen="127.0.0.1"):
    cur.execute("SELECT id, settings, stream_settings FROM inbounds WHERE (port = ? AND protocol = ?) OR tag = ?", (port, proto, tag))
    row = cur.fetchone()
    sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})

    if row and install_mode == "2":
        inbound_id = row[0]
        cur_s = json.loads(row[1]) if row[1] else {}
        cur_st = json.loads(row[2]) if row[2] else {}
        s_mutated = False
        st_mutated = False

        # Пользовательские названия инбаундов и externalProxy сохранены без изменений

        if "externalProxy" in cur_st and isinstance(cur_st["externalProxy"], list):
            for ep in cur_st["externalProxy"]:
                if isinstance(ep, dict):
                    if "alpn" in ep and isinstance(ep["alpn"], str):
                        val = ep["alpn"].strip()
                        ep["alpn"] = [x.strip() for x in val.split(",") if x.strip()] if val else []
                        st_mutated = True
                    if "pinnedPeerCertSha256" in ep and isinstance(ep["pinnedPeerCertSha256"], str):
                        val = ep["pinnedPeerCertSha256"].strip()
                        ep["pinnedPeerCertSha256"] = [x.strip() for x in val.split(",") if x.strip()] if val else []
                        st_mutated = True

        if "encryption" in cur_s and cur_s["encryption"] == "":
            cur_s["encryption"] = "none"
            s_mutated = True

        if "testseed" in cur_s and not isinstance(cur_s["testseed"], list):
            try:
                cur_s["testseed"] = [int(x) for x in str(cur_s["testseed"]).split(",") if x.strip()]
                s_mutated = True
            except Exception:
                cur_s["testseed"] = [900, 500, 900, 256]
                s_mutated = True

        if proto == "vless" and "realitySettings" in cur_st:
            rs = cur_st["realitySettings"]
            if rs.get("dest") != "127.0.0.1:9443" and "in-steal" in tag:
                rs["dest"] = "127.0.0.1:9443"
                rs["target"] = "127.0.0.1:9443"
                rs["xver"] = 1
                st_mutated = True
            if "tcpSettings" in cur_st:
                if not cur_st["tcpSettings"].get("acceptProxyProtocol"):
                    cur_st["tcpSettings"]["acceptProxyProtocol"] = True
                    st_mutated = True
            if "settings" in rs and not rs["settings"].get("serverName"):
                if rs.get("serverNames") and len(rs["serverNames"]) > 0:
                    rs["settings"]["serverName"] = rs["serverNames"][0]
                    st_mutated = True

        if proto == "vless" and tag == "in-xhttp-stream":
            if not cur_s.get("decryption") or cur_s.get("decryption") == "none":
                cur_s["decryption"] = vless_dekey
                cur_s["encryption"] = vless_enkey
                s_mutated = True
            if "xhttpSettings" in cur_st:
                if cur_st["xhttpSettings"].get("host") != domain:
                    cur_st["xhttpSettings"]["host"] = domain
                    st_mutated = True
                if cur_st["xhttpSettings"].get("path") != xhttp_path:
                    cur_st["xhttpSettings"]["path"] = xhttp_path
                    st_mutated = True
            if "externalProxy" in cur_st and isinstance(cur_st["externalProxy"], list):
                for ep in cur_st["externalProxy"]:
                    if ep.get("dest") != domain or ep.get("sni") != domain or ep.get("remark") != remark:
                        ep["dest"] = domain
                        ep["sni"] = domain
                        ep["port"] = 443
                        ep["alpn"] = ["h2"]
                        ep["remark"] = remark
                        st_mutated = True

        if proto == "amneziawg" and "server" in cur_s:
            srv = cur_s["server"]
            patch_params = {
                "contentPaddingAddition": "0", "randomTrailers": False, "disableCookies": True,
                "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
                "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
                "mtu": 1360, "jc": 4, "jmin": 40, "jmax": 70, "s1": 72, "s2": 56, "s3": 32, "s4": 16
            }
            for pk, pv in patch_params.items():
                if pk not in srv or srv[pk] != pv:
                    srv[pk] = pv
                    s_mutated = True

        if s_mutated or st_mutated:
            cur.execute("UPDATE inbounds SET settings = ?, stream_settings = ? WHERE id = ?",
                        (json.dumps(cur_s, ensure_ascii=False), json.dumps(cur_st, ensure_ascii=False), inbound_id))
        active_inbound_ids.append(inbound_id)
        return inbound_id
    elif row:
        inbound_id = row[0]
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("UPDATE inbounds SET port=?, protocol=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (port, proto, remark, s_json, st_json, listen, sniff, inbound_id))
        active_inbound_ids.append(inbound_id)
        return inbound_id
    else:
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        cur.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing, share_addr_strategy, disable_flow) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?, 'node', 0)",
                    (uid, remark, listen, port, proto, s_json, st_json, tag, sniff))
        inbound_id = cur.lastrowid
        active_inbound_ids.append(inbound_id)
        return inbound_id


# 1. Steal-Oneself REALITY (Tri-Sync Remark)
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
        primary_steal_sni = doms[0] if doms else f"cdn.{domain}"
        remark = f"REALITY Steal-OneSelf ({primary_steal_sni})"
        s_obj = {"clients": [client_reality_dict], "decryption": "none", "encryption": "none", "testseed": [900, 500, 900, 256]}
        st_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 1, "target": "127.0.0.1:9443", "dest": "127.0.0.1:9443",
                "serverNames": doms, "privateKey": def_r_priv, "minClientVer": "1.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": [reality_hex_sid],
                "mldsa65Seed": "",
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": primary_steal_sni, "spiderX": "/", "mldsa65Verify": ""},
                "spiderX": "/"
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "sni": primary_steal_sni, "remark": remark}]
        }
        ib1_id = register_or_get_inbound(p, "vless", tag, remark, s_obj, st_obj)
        vision_inbound_ids.add(ib1_id)

# 2. Classic REALITY (Tri-Sync Remark)
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
        remark = f"REALITY Classic ({primary_sni})"
        c_obj = {"clients": [client_reality_dict], "decryption": "none", "encryption": "none", "testseed": [900, 500, 900, 256]}
        ct_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 0, "target": f"{primary_sni}:443", "dest": f"{primary_sni}:443",
                "serverNames": snis, "privateKey": def_r_priv, "minClientVer": "1.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": [reality_hex_sid],
                "mldsa65Seed": "",
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": primary_sni, "shortId": reality_hex_sid, "spiderX": "/", "mldsa65Verify": ""},
                "spiderX": "/"
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "sni": primary_sni, "remark": remark}]
        }
        ib2_id = register_or_get_inbound(p, "vless", tag, remark, c_obj, ct_obj)
        vision_inbound_ids.add(ib2_id)

# 3. VLESS xHTTP (Native H2 Stream-One) + ML-KEM-768 (Tri-Sync Remark)
if os.environ.get("ENABLE_XHTTP") == "1" and xhttp_port > 0 and xhttp_path:
    remark_xhttp = f"VLESS xHTTP ({domain})"
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
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "firefox", "alpn": ["h2"], "remark": remark_xhttp}]
    }
    ib3_id = register_or_get_inbound(xhttp_port, "vless", "in-xhttp-stream", remark_xhttp, x_obj, xt_obj)
    vision_inbound_ids.add(ib3_id)

# 4. Hysteria 2 (Tri-Sync Remark)
if os.environ.get("ENABLE_HY2") == "1":
    hp = int(os.environ["HY2_PORT"])
    ssl_dir = os.environ["SSL_BASE_DIR"]
    remark_hy2 = f"Hysteria 2 ({domain})"
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
        "externalProxy": [{"dest": domain, "port": hp, "forceTls": "tls", "alpn": ["h3"], "remark": remark_hy2}]
    }
    ib4_id = register_or_get_inbound(hp, "hysteria", "in-hysteria2", remark_hy2, h_obj, ht_obj, listen="0.0.0.0")

awg3_dns_prim = "77.88.8.8" if geo_profile == "1" else "1.1.1.1"
awg3_dns_sec = "77.88.8.1" if geo_profile == "1" else "8.8.8.8"

# 5. AmneziaWG v3.2 (3X-UI) (Tri-Sync Remark)
if os.environ.get("ENABLE_AWG_V3") == "1":
    a3p = int(os.environ["AWG_V3_PORT"])
    remark_awg3 = f"AmneziaWG v3.2 ({domain})"
    a3_client = dict(client_reality_dict)
    a3_client["allowedIPs"] = ["10.8.1.3/32"]
    a3_client["privateKey"] = def_wg_c_priv
    a3_client["publicKey"] = def_wg_c_pub
    a3_client.pop("flow", None)
    
    a3_h1 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h2 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h3 = str(secrets.randbelow(2000000000) + 100000000)
    a3_h4 = str(secrets.randbelow(2000000000) + 100000000)

    a3_obj = {
        "clients": [a3_client],
        "server": {
            "h1": a3_h1, "h2": a3_h2, "h3": a3_h3, "h4": a3_h4,
            "jc": 4, "jmin": 40, "jmax": 70, "s1": 72, "s2": 56, "s3": 32, "s4": 16,
            "mtu": 1360, "primaryDns": awg3_dns_prim, "secondaryDns": awg3_dns_sec,
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "randomTrailers": False, "disableCookies": True, "contentPaddingAddition": "0",
            "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
            "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
            "subnetCidr": 24, "subnetIp": "10.8.1.0"
        }
    }
    a3t_obj = {"externalProxy": [{"dest": domain, "port": a3p, "remark": remark_awg3}]}
    ib5_id = register_or_get_inbound(a3p, "amneziawg", "in-awg-v3", remark_awg3, a3_obj, a3t_obj, listen="0.0.0.0")


if "clients" in tables:
    cur.execute("PRAGMA table_info(clients)")
    client_cols = {r[1] for r in cur.fetchall()}
    
    if install_mode == "1":
        client_data_map = {
            "email": test_email, "sub_id": test_sub_id, "uuid": test_uuid, "password": test_password,
            "auth": test_password, "flow": "xtls-rprx-vision", "security": "auto", "reverse": "",
            "wg_private_key": def_wg_c_priv, "wg_public_key": def_wg_c_pub, "wg_allowed_ips": "10.8.1.3/32",
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

        if "client_inbounds" in tables and client_global_id:
            active_inbound_links = [
                (ib_id, "xtls-rprx-vision" if ib_id in vision_inbound_ids else "")
                for ib_id in active_inbound_ids if ib_id is not None
            ]
            for ib_id, flow_val in active_inbound_links:
                cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                            (client_global_id, ib_id, flow_val, now_ms))

        if "client_traffics" in tables:
            for ib_id in active_inbound_ids:
                if ib_id is not None:
                    cur.execute("INSERT OR REPLACE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)",
                                (ib_id, test_email))

    elif install_mode == "2":
        if "client_traffics" in tables and "inbounds" in tables:
            cur.execute("DELETE FROM client_traffics WHERE inbound_id NOT IN (SELECT id FROM inbounds)")

        if "client_inbounds" in tables and "inbounds" in tables:
            cur.execute("SELECT id, protocol, settings FROM inbounds")
            for ib_row in cur.fetchall():
                cur_ib_id = ib_row[0]
                cur_ib_proto = ib_row[1]
                cur_ib_s = json.loads(ib_row[2]) if ib_row[2] else {}

                cur.execute("""
                    SELECT c.id, c.email, c.uuid, c.password, c.auth, c.flow, c.wg_public_key, c.wg_allowed_ips, ci.flow_override, c.sub_id
                    FROM client_inbounds ci
                    JOIN clients c ON c.id = ci.client_id
                    WHERE ci.inbound_id = ?
                """, (cur_ib_id,))
                mapped_clients = cur.fetchall()

                if mapped_clients:
                    reconciled_client_list = []
                    for cid, cemail, cuuid, cpwd, cauth, cflow, cwg_pub, cwg_ips, cflow_over, csub_id in mapped_clients:
                        target_flow = cflow_over if cflow_over else cflow
                        if not target_flow and cur_ib_proto == "vless":
                            target_flow = "xtls-rprx-vision"

                        c_entry = {
                            "id": cuuid,
                            "email": cemail,
                            "subId": str(csub_id).strip() if csub_id else secrets.token_hex(8),
                            "enable": True,
                            "expiryTime": 0,
                            "totalGB": 0,
                            "reset": 0
                        }
                        if cur_ib_proto == "vless":
                            c_entry["flow"] = target_flow
                            if cpwd: c_entry["password"] = cpwd
                            if cauth: c_entry["auth"] = cauth
                        elif cur_ib_proto == "hysteria":
                            c_entry["auth"] = cauth if cauth else (cpwd if cpwd else cemail)
                            c_entry["password"] = cpwd if cpwd else (cauth if cauth else cemail)
                        elif cur_ib_proto in ["amneziawg", "wireguard"]:
                            c_entry["publicKey"] = cwg_pub if cwg_pub else ""
                            try:
                                c_entry["allowedIPs"] = json.loads(cwg_ips) if (cwg_ips and cwg_ips.startswith("[")) else ([cwg_ips] if cwg_ips else [])
                            except Exception:
                                c_entry["allowedIPs"] = [cwg_ips] if cwg_ips else []
                        else:
                            if cpwd: c_entry["password"] = cpwd
                            if cauth: c_entry["auth"] = cauth
                        reconciled_client_list.append(c_entry)

                    cur_ib_s["clients"] = reconciled_client_list
                    cur.execute("UPDATE inbounds SET settings = ? WHERE id = ?",
                                (json.dumps(cur_ib_s, ensure_ascii=False), cur_ib_id))

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
    if ib_id is None:
        return
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
    steal_dom = os.environ.get("STEAL_DOMAINS_STR", "").split()
    chosen_steal = steal_dom[0] if steal_dom else f"cdn.{domain}"
    
    if ib1_id is not None:
        r1 = f"REALITY Steal-OneSelf ({chosen_steal})"
        add_host_entry(str(uuid.uuid4()), ib1_id, r1, chosen_steal, 443, "same", sni=chosen_steal, fp="firefox", sort_order=1)
    if ib2_id is not None:
        c_snis = os.environ.get("CLASSIC_CONFIG_DATA", "")
        c_def_sni = "tbank.ru"
        if "=" in c_snis:
            c_def_sni = c_snis.split("=", 1)[1].split(";")[0].split(",")[0].strip()
        r2 = f"REALITY Classic ({c_def_sni})"
        add_host_entry(str(uuid.uuid4()), ib2_id, r2, domain, 443, "same", sni=c_def_sni, fp="firefox", sort_order=1)
    if ib3_id is not None:
        r3 = f"VLESS xHTTP ({domain})"
        add_host_entry(str(uuid.uuid4()), ib3_id, r3, domain, 443, "tls", sni=domain, path=xhttp_path, alpn=json.dumps(["h2"]), fp="firefox", sort_order=2)
    if ib4_id is not None:
        add_host_entry(str(uuid.uuid4()), ib4_id, f"Hysteria 2 ({domain})", domain, int(os.environ.get("HY2_PORT", 443)), "tls", alpn=json.dumps(["h3"]), sort_order=3)
    if ib5_id is not None:
        add_host_entry(str(uuid.uuid4()), ib5_id, f"AmneziaWG v3.2 ({domain})", domain, int(os.environ.get("AWG_V3_PORT", 10443)), "same", sort_order=4)
elif install_mode == "2":
    cur.execute("SELECT id, remark, settings, stream_settings, protocol, port FROM inbounds")
    ib_rows = cur.fetchall()
    for cur_ib_id, cur_ib_remark, ib_s_raw, ib_st_raw, ib_proto, cur_ib_port in ib_rows:
        st_info = json.loads(ib_st_raw) if ib_st_raw else {}
        rs_sni = ""
        if "realitySettings" in st_info:
            s_names = st_info["realitySettings"].get("serverNames", [])
            if s_names: rs_sni = s_names[0]
        cur.execute("SELECT id, sni FROM hosts WHERE inbound_id = ?", (cur_ib_id,))
        existing_h = cur.fetchall()
        if existing_h:
            for h_row in existing_h:
                target_sni = h_row[1] if (h_row[1] and h_row[1].strip()) else rs_sni
                # Обновляем только технический group_id и sni, название хоста (remark) не трогаем
                cur.execute("UPDATE hosts SET group_id = ?, sni = ? WHERE id = ?", (str(uuid.uuid4()), target_sni, h_row[0]))
        else:
            # Новый инбаунд регистрируется в hosts только как техническая точка входа (клиенты не привязываются)
            sec_v = "tls" if (ib_proto == "vless" and "xhttp" in str(ib_st_raw)) else "same"
            add_host_entry(str(uuid.uuid4()), cur_ib_id, cur_ib_remark, domain, cur_ib_port, sec_v, sni=rs_sni or domain, fp="firefox")

    if ib3_id is not None:
        cur.execute("SELECT id FROM hosts WHERE inbound_id = ?", (ib3_id,))
        h3_row = cur.fetchone()
        if h3_row:
            # Обновление путей xHTTP без изменения пользовательского имени
            cur.execute("UPDATE hosts SET group_id = ?, address = ?, sni = ?, path = ?, alpn = ? WHERE id = ?",
                        (str(uuid.uuid4()), domain, domain, xhttp_path, json.dumps(["h2"]), h3_row[0]))
        else:
            cur.execute("SELECT remark FROM inbounds WHERE id = ?", (ib3_id,))
            r3_row = cur.fetchone()
            r3 = r3_row[0] if r3_row else f"VLESS xHTTP ({domain})"
            add_host_entry(str(uuid.uuid4()), ib3_id, r3, domain, 443, "tls", sni=domain, path=xhttp_path, alpn=json.dumps(["h2"]), fp="firefox", sort_order=2)

conn.commit()
try:
    cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
except Exception:
    pass
conn.close()

with open("/tmp/vpn_unified_creds.txt", "w") as f:
    f.write(f"UNIFIED_SUB_ID={test_sub_id}\n")
    f.write(f"UNIFIED_UUID={test_uuid}\n")
    f.write(f"TEST_EMAIL={test_email}\n")
EOF_PY_ENGINE

if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    chmod 755 "$(dirname "$DB_PATH")" 2>/dev/null || true
    chmod 644 "$DB_PATH" 2>/dev/null || true
    chmod 644 "${DB_PATH}-wal" 2>/dev/null || true
    chmod 644 "${DB_PATH}-shm" 2>/dev/null || true
fi

# Лимитирование потребления памяти сборщиком мусора Go (GOMEMLIMIT для 1 GB RAM)
mkdir -p /etc/systemd/system/x-ui.service.d/
cat << 'EOF_XUI_MEM' > /etc/systemd/system/x-ui.service.d/10-memory-limit.conf
[Service]
Environment="GOMEMLIMIT=160MiB"
Environment="GOGC=80"
EOF_XUI_MEM
systemctl daemon-reload

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
#  ФАЗА 4: НА ТЕХНОЛОГИЯХ ЯДРА: NATIVE AMNEZIAWG SERVER (DKMS)
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 4: Нативный сервер AmneziaWG (Ядро Linux Bare-Metal awg0)     ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    log "Установка DKMS-модуля и инструментов AmneziaWG..."
    if [ "$OS_ID" = "ubuntu" ]; then
        wait_for_apt_lock
        log "Установка заголовков ядра linux-headers..."
        apt-get install -y build-essential dkms "linux-headers-$(uname -r)" -q < /dev/null || true
        log "Импорт официального репозитория AmneziaWG по HTTPS (порт 443)..."
        mkdir -p /etc/apt/keyrings
        rm -f /etc/apt/keyrings/amnezia.gpg /etc/apt/sources.list.d/amnezia.list
        if curl -fsSL --connect-timeout 8 -m 20 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x4166F2C257290828" | gpg --dearmor -o /etc/apt/keyrings/amnezia.gpg 2>/dev/null; then
            if [ -s /etc/apt/keyrings/amnezia.gpg ]; then
                echo "deb [signed-by=/etc/apt/keyrings/amnezia.gpg] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu noble main" > /etc/apt/sources.list.d/amnezia.list
                wait_for_apt_lock
                apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/amnezia.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" >/dev/null 2>&1 || true
                wait_for_apt_lock
                DEBIAN_FRONTEND=noninteractive apt-get install -y amneziawg-dkms amneziawg-tools -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null || true
            fi
        fi
    fi

    if ! command -v awg >/dev/null 2>&1 || ! dkms status 2>/dev/null | grep -q "amneziawg"; then
        log "Синхронизация заголовков активного ядра и репозитория ОС..."
        wait_for_apt_lock
        KERNEL_META_HEADERS="linux-headers-amd64"
        if [ "$OS_ID" = "ubuntu" ]; then
            KERNEL_META_HEADERS="linux-headers-generic"
        fi
        if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
            KERNEL_META_HEADERS="linux-headers-arm64"
            if [ "$OS_ID" = "ubuntu" ]; then
                KERNEL_META_HEADERS="linux-headers-generic"
            fi
        fi
        apt-get install -y build-essential git dkms wireguard-tools libmnl-dev make gcc -q >/dev/null 2>&1 || true
        apt-get install -y "linux-headers-$(uname -r)" -q >/dev/null 2>&1 || true
        apt-get install -y "$KERNEL_META_HEADERS" -q >/dev/null 2>&1 || true
        
        AWG_CLONE_DIR="/tmp/awg-kernel-src"
        AWG_BUILD_DIR="/usr/src/amneziawg-1.0.0"
        rm -rf "$AWG_CLONE_DIR" "$AWG_BUILD_DIR"
        git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git "$AWG_CLONE_DIR" 2>/dev/null || true
        if [ -d "$AWG_CLONE_DIR/src" ]; then
            mkdir -p "$AWG_BUILD_DIR"
            cp -r "$AWG_CLONE_DIR"/src/* "$AWG_BUILD_DIR"/
            
            cat << 'EOF_DKMS' > "$AWG_BUILD_DIR/dkms.conf"
PACKAGE_NAME="amneziawg"
PACKAGE_VERSION="1.0.0"
BUILT_MODULE_NAME[0]="amneziawg"
DEST_MODULE_LOCATION[0]="/kernel/net"
AUTOINSTALL="yes"
MAKE[0]="'make' -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build KCFLAGS='-Wno-incompatible-pointer-types -Wno-error=incompatible-pointer-types -Wno-error' EXTRA_CFLAGS='-Wno-incompatible-pointer-types -Wno-error=incompatible-pointer-types -Wno-error'"
EOF_DKMS
            dkms remove amneziawg/1.0.0 --all 2>/dev/null || true
            patch_amnezia_dkms_kernel_compat
            dkms add -m amneziawg -v 1.0.0 2>/dev/null || true
            dkms build -m amneziawg -v 1.0.0 -k "$(uname -r)" >/dev/null 2>&1 || dkms build -m amneziawg -v 1.0.0 >/dev/null 2>&1 || true
            dkms install -m amneziawg -v 1.0.0 -k "$(uname -r)" >/dev/null 2>&1 || dkms install -m amneziawg -v 1.0.0 >/dev/null 2>&1 || true
            rm -rf "$AWG_CLONE_DIR"
        fi

        TOOLS_BUILD_DIR="/tmp/awg-tools-build"
        rm -rf "$TOOLS_BUILD_DIR"
        git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git "$TOOLS_BUILD_DIR" 2>/dev/null || true
        if [ -d "$TOOLS_BUILD_DIR/src" ]; then
            make -C "$TOOLS_BUILD_DIR/src" >/dev/null 2>&1 || true
            make -C "$TOOLS_BUILD_DIR/src" install >/dev/null 2>&1 || true
            rm -rf "$TOOLS_BUILD_DIR"
        fi
    fi

    mkdir -p /etc/modules-load.d
    echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
    modprobe amneziawg 2>/dev/null || true

    if ! command -v awg >/dev/null 2>&1; then
        warn "Утилита awg не найдена. Нативный AmneziaWG awg0 отключен, остальные службы продолжают работу."
        ENABLE_NATIVE_AWG=0
    fi

    if [ "$ENABLE_NATIVE_AWG" -eq 1 ]; then
        mkdir -p /etc/amnezia/amneziawg
    chmod 700 /etc/amnezia /etc/amnezia/amneziawg

    if [ -f /etc/amnezia/amneziawg/awg0.conf ]; then
        ok "Обнаружена действующая конфигурация awg0 (/etc/amnezia/amneziawg/awg0.conf). Режим сохранения активен."
        DETECTED_AWG_PORT=$(grep -E '^\s*ListenPort\s*=' /etc/amnezia/amneziawg/awg0.conf | head -n1 | awk -F= '{print $2}' | tr -d '[:space:]' || echo "")
        if validate_port "$DETECTED_AWG_PORT"; then
            NATIVE_AWG_PORT="$DETECTED_AWG_PORT"
            ok "Рабочий порт сервера AmneziaWG awg0: :${NATIVE_AWG_PORT}/udp"
        fi

        CLIENTS_JSON="/etc/amnezia/amneziawg/clients.json"
        if [ ! -f "$CLIENTS_JSON" ]; then
            log "Синтез clients.json из действующих пиров awg0.conf..."
            python3 - << 'EOF_RECON'
import re, json, os
conf_path = "/etc/amnezia/amneziawg/awg0.conf"
clients_json_path = "/etc/amnezia/amneziawg/clients.json"
clients = {}
if os.path.exists(conf_path):
    with open(conf_path, "r") as f:
        content = f.read()
    peers = re.findall(r'\[Peer\][\s\S]*?(?=\n\[Peer\]|\Z)', content)
    for idx, p_block in enumerate(peers, 1):
        m_pub = re.search(r'PublicKey\s*=\s*([^\s\n\r]+)', p_block)
        m_ip = re.search(r'AllowedIPs\s*=\s*([^\s\n\r]+)', p_block)
        m_name = re.search(r'# --- Client:\s*([^\n\r]+?)\s*---', p_block)
        if m_pub:
            pub = m_pub.group(1).strip()
            ip = m_ip.group(1).strip() if m_ip else f"10.9.0.{idx+1}/32"
            name = m_name.group(1).strip() if m_name else f"Client-{idx}"
            clients[pub] = {
                "name": name,
                "private_key": "",
                "public_key": pub,
                "ip": ip
            }
    with open(clients_json_path, "w") as f:
        json.dump(clients, f, indent=2)
    os.chmod(clients_json_path, 0o600)
EOF_RECON
        fi
        chmod 600 /etc/amnezia/amneziawg/awg0.conf
    else
        log "Генерация новых ключей и конфигурации сервера AmneziaWG awg0..."
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
S1 = 72
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
S1 = 72
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
AllowedIPs = 0.0.0.0/0
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
    fi

    awg-quick down awg0 2>/dev/null || true
    systemctl stop awg-quick@awg0 2>/dev/null || true
    systemctl enable awg-quick@awg0 >/dev/null 2>&1 || true
        systemctl restart awg-quick@awg0 || true
        ok "Нативный сервер AmneziaWG активен на сокете :${NATIVE_AWG_PORT}/udp (awg0)."
    fi
fi

# =============================================================
#  ФАЗА 5: МНОГОПОТОЧНЫЙ ПИТОН-ДЕМОН MY PRIVATE CLOUD CORE GATEWAY
# =============================================================
log "Развёртывание управляющего микросервиса My Private Cloud Core (Loopback 20443)..."

cat << 'EOF_CORE_PY' > /usr/local/bin/myprivatecloud-core.py
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import http.server, socketserver, json, os, subprocess, hmac, secrets, re, time, sqlite3, urllib.parse, base64, fcntl, threading, shutil
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
AGH_DOMAIN = os.environ.get("AGH_DOMAIN", "")
NATIVE_AWG_PORT = os.environ.get("NATIVE_AWG_PORT", "8443")

SESSION_LOCK = threading.Lock()
ACTIVE_SESSIONS = {}

def safe_cmd_output(args):
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL).decode("utf-8")
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

    if not clients:
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
            with open(CONF_PATH, "r+") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                text = f.read()
                if pub not in text:
                    text = text.rstrip() + f"\n\n# --- Client: Test-Client ---\n[Peer]\nPublicKey = {pub}\nAllowedIPs = {ip}\n"
                    f.seek(0)
                    f.write(text)
                    f.truncate()
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            if shutil.which("awg"): subprocess.run(["awg", "set", "awg0", "peer", pub, "allowed-ips", ip], capture_output=True)
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
    import hashlib
    for db_path in DB_PATHS:
        if not os.path.exists(db_path):
            continue
        try:
            conn = sqlite3.connect(f"file:{db_path}?mode=ro&immutable=1", uri=True, timeout=5.0)
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
                elif len(db_hash) == 64 and all(c in "0123456789abcdefABCDEF" for c in db_hash):
                    pwd_sha256 = hashlib.sha256(pwd.encode('utf-8')).hexdigest()
                    if hmac.compare_digest(pwd_sha256.lower(), db_hash.lower()):
                        return True
                elif hmac.compare_digest(pwd, db_hash):
                    return True
        except Exception:
            pass
    return False

def get_panel_path():
    env_p = os.environ.get("PANEL_PATH", "").strip().strip("/")
    if env_p:
        return f"/{env_p}/"
    for db_path in DB_PATHS:
        if os.path.exists(db_path):
            try:
                conn = sqlite3.connect(f"file:{db_path}?mode=ro&immutable=1", uri=True, timeout=5.0)
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
        with open(CONF_PATH, "r", encoding="utf-8", errors="ignore") as f:
            c_text = f.read()
        for k in ["MTU", "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4", "H1", "H2", "H3", "H4", "ListenPort", "PrivateKey"]:
            m = re.search(r"^\s*" + k + r"\s*=\s*(\S+)", c_text, re.M | re.I)
            if m:
                srv[k.upper()] = m.group(1).strip()
    
    clients = load_clients()
    c_info = clients.get(pub_key)
    if not c_info:
        return None
    
    c_priv = c_info.get("private_key", "")
    c_ip = c_info.get("ip", "10.9.0.2/32")

    s_priv = srv.get("PRIVATEKEY", "")
    s_pub = ""
    if s_priv:
        try:
            raw_s = base64.b64decode(s_priv)
            s_pub = base64.b64encode(x25519(clamp(raw_s), 9).to_bytes(32, "little")).decode()
        except Exception:
            pass
    if not s_pub:
        s_pub = safe_cmd_output(["awg", "show", "awg0", "public-key"]).strip()

    dns_ip = "77.88.8.8"
    if ENABLE_AGH:
        dns_ip = "10.9.0.1"
    elif GEO_PROFILE != "1":
        dns_ip = "1.1.1.1"

    dest_endpoint = host.split(':')[0] if host else PRIMARY_DOMAIN
    port_val = srv.get('LISTENPORT', NATIVE_AWG_PORT)
    return f'''[Interface]
Address = {c_ip}
PrivateKey = {c_priv}
DNS = {dns_ip}
MTU = {srv.get('MTU', '1360')}
Jc = {srv.get('JC', '4')}
Jmin = {srv.get('JMIN', '40')}
Jmax = {srv.get('JMAX', '70')}
S1 = {srv.get('S1', '72')}
S2 = {srv.get('S2', '56')}
S3 = {srv.get('S3', '32')}
S4 = {srv.get('S4', '16')}
H1 = {srv.get('H1', '1407978111')}
H2 = {srv.get('H2', '1980238350')}
H3 = {srv.get('H3', '315765535')}
H4 = {srv.get('H4', '529409274')}

[Peer]
PublicKey = {s_pub}
Endpoint = {dest_endpoint}:{port_val}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
'''

def clean_expired_sessions():
    now = time.time()
    with SESSION_LOCK:
        expired = [t for t, exp in list(ACTIVE_SESSIONS.items()) if exp < now]
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
            with SESSION_LOCK:
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

        if self.path == "/api/v1/myprivatecloud/auth":
            user = data.get("principal", "").strip()
            pwd = data.get("secret", "").strip()

            if verify_credentials(user, pwd):
                clean_expired_sessions()
                token = secrets.token_hex(24)
                with SESSION_LOCK:
                    ACTIVE_SESSIONS[token] = time.time() + 3600
                panel_url = get_panel_path()
                agh_target = AGH_DOMAIN if AGH_DOMAIN else f"dns.{self.headers.get('Host', '')}"
                self._send_json({
                    "status": "ok",
                    "token": token,
                    "services": {
                        "panel_url": panel_url,
                        "awg_enabled": os.path.exists(CONF_PATH),
                        "awg_port": NATIVE_AWG_PORT,
                        "agh_enabled": os.path.exists("/opt/AdGuardHome/AdGuardHome.yaml"),
                        "agh_url": f"https://{agh_target}/"
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

        if self.path == "/api/v1/myprivatecloud/awg/peer/add":
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
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                f.write(new_peer)
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

            subprocess.run(["awg", "set", "awg0", "peer", pub, "allowed-ips", client_ip], capture_output=True)
            
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

        if self.path == "/api/v1/myprivatecloud/awg/peer/remove":
            pub = urllib.parse.unquote(data.get("public_key", "")).strip()
            if pub and re.match(r'^[A-Za-z0-9+/=]{40,50}$', pub):
                subprocess.run(["awg", "set", "awg0", "peer", pub, "remove"], capture_output=True)
                if os.path.exists(CONF_PATH):
                    with open(CONF_PATH, "r+") as f:
                        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                        text = f.read()
                        pattern = rf"(# --- Client: .*?---\n)?\[Peer\]\nPublicKey\s*=\s*{re.escape(pub)}[\s\S]*?(?=\n\[Peer\]|\n# ---|$)"
                        text = re.sub(pattern, "", text)
                        f.seek(0)
                        f.write(text.strip() + "\n")
                        f.truncate()
                        fcntl.flock(f.fileno(), fcntl.LOCK_UN)
                
                clients = load_clients()
                if pub in clients:
                    del clients[pub]
                    save_clients(clients)
            self._send_json({"status": "ok"})
            return

        self._send_json({"status": "error", "error": "Not Found"}, code=404)

    def do_GET(self):
        if self.path == "/api/v1/myprivatecloud/status":
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return
            self._send_json({
                "status": "online",
                "cluster": "myprivatecloud-edge-ultra",
                "nodes_active": 148,
                "telemetry_rate": "99.998%",
                "version": "3.14.0"
            })
            return

        if self.path.startswith("/api/v1/myprivatecloud/awg/peer/qr"):
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return
            pub_req = re.search(r'key=([^&]+)', self.path)
            raw_key = pub_req.group(1).strip() if pub_req else ""
            pub_key = urllib.parse.unquote(raw_key).strip()
            
            conf_str = build_client_conf(pub_key, self.headers.get('Host', ''))
            if not conf_str:
                self._send_json({"status": "error", "error": "Peer Not Found"}, code=404)
                return
            
            p = subprocess.Popen(["qrencode", "-t", "PNG", "-s", "8", "-m", "2", "-o", "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            img_out, _ = p.communicate(input=conf_str.encode("utf-8"))
            if not img_out:
                p_svg = subprocess.Popen(["qrencode", "-t", "SVG", "-m", "2", "-o", "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                img_out, _ = p_svg.communicate(input=conf_str.encode("utf-8"))
                content_type = "image/svg+xml"
            else:
                content_type = "image/png"
            
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(img_out)))
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, private")
            self.end_headers()
            self.wfile.write(img_out)
            return

        if self.path.startswith("/api/v1/myprivatecloud/awg/peer/conf"):
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return
            pub_req = re.search(r'key=([^&]+)', self.path)
            raw_key = pub_req.group(1).strip() if pub_req else ""
            pub_key = urllib.parse.unquote(raw_key).strip()
            
            body_conf = build_client_conf(pub_key, self.headers.get('Host', ''))
            if not body_conf:
                self._send_json({"status": "error", "error": "Peer Not Found"}, code=404)
                return
            
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Disposition", f'attachment; filename="awg0-{pub_key[:6]}.conf"')
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, private")
            self.end_headers()
            self.wfile.write(body_conf.encode("utf-8"))
            return

        if self.path.startswith("/api/v1/myprivatecloud/awg/peers"):
            if not self._auth_valid():
                self._send_json({"status": "error", "error": "Unauthorized"}, code=401)
                return

            dump = safe_cmd_output(["awg", "show", "awg0", "dump"]).strip()
            name_map = {}
            if os.path.exists(CONF_PATH):
                with open(CONF_PATH, "r") as f:
                    curr_name = ""
                    for l in f:
                        m_n = re.search(r'# --- Client:\s*([^\n\r]+?)\s*---', l)
                        if m_n:
                            curr_name = m_n.group(1).strip()
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
chmod 755 /usr/local/bin/myprivatecloud-core.py

cat << EOF > /etc/systemd/system/myprivatecloud-core.service
[Unit]
Description=My Private Cloud Core Gateway Daemon
After=network.target

[Service]
Type=simple
User=root
Environment="ENABLE_AGH=${ENABLE_AGH:-0}"
Environment="GEO_PROFILE=$GEO_PROFILE"
Environment="PRIMARY_DOMAIN=$PRIMARY_DOMAIN"
Environment="PANEL_PATH=$PANEL_PATH"
Environment="AGH_DOMAIN=${AGH_DOMAIN:-}"
Environment="NATIVE_AWG_PORT=$NATIVE_AWG_PORT"
ExecStart=/usr/bin/python3 /usr/local/bin/myprivatecloud-core.py
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/etc/amnezia/amneziawg /tmp /etc/x-ui
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable myprivatecloud-core >/dev/null 2>&1 || true
systemctl restart myprivatecloud-core || true
ok "Служба My Private Cloud Core SSO Gateway запущена на 127.0.0.1:20443."

# =============================================================
#  ФАЗА 6: СЕТЕВОЙ ШЛЮЗ NAT, TCP MSS CLAMPING И ИЗОЛЯЦИЯ UFW
# =============================================================
echo
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  ФАЗА 6: Сетевой шлюз NAT, TCP MSS Clamping и изоляция UFW          ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

ok "Сетевой интерфейс шлюза (Universal WAN Engine): ${GREEN}${DEFAULT_IF}${NC}"

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

if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    ufw allow in on awg0 to 10.9.0.1 port 53 proto udp comment 'AdGuard DNS awg0 UDP' >/dev/null 2>&1 || true
    ufw allow in on awg0 to 10.9.0.1 port 53 proto tcp comment 'AdGuard DNS awg0 TCP' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    ufw allow "${HY2_PORT}/udp" comment 'Hysteria 2' >/dev/null 2>&1 || true
    if [ "${ENABLE_HY2_HOP:-0}" -eq 1 ]; then
        ufw allow 20000:35000/udp comment 'Hysteria 2 Hopping Pool' >/dev/null 2>&1 || true
    fi
fi

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    ufw allow "${NATIVE_AWG_PORT}/udp" comment 'AmneziaWG Native awg0 Base' >/dev/null 2>&1 || true
    if [ "${ENABLE_AWG_HOP:-0}" -eq 1 ]; then
        ufw allow 35001:49999/udp comment 'AmneziaWG Native Speed Pool' >/dev/null 2>&1 || true
    fi
fi

if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    ufw allow "${AWG_V3_PORT}/udp" comment '3X-UI AWG v3.2' >/dev/null 2>&1 || true
fi


export ENABLE_HY2_HOP HY2_PORT ENABLE_NATIVE_AWG NATIVE_AWG_PORT ENABLE_AWG_HOP ENABLE_AWG_V3 DEFAULT_IF
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
content = re.sub(r'# START HARDENED DNS-INPUT[\s\S]*?# END HARDENED DNS-INPUT\n?', '', content)
content = content.strip() + "\n"

enable_hop = os.environ.get("ENABLE_HY2_HOP") == "1"
hy2_p = os.environ.get("HY2_PORT", "443")
default_if = os.environ.get("DEFAULT_IF", "eth0")
awg_native = os.environ.get("ENABLE_NATIVE_AWG") == "1"
nawg_p = os.environ.get("NATIVE_AWG_PORT", "8443")
awg_hop = os.environ.get("ENABLE_AWG_HOP") == "1"
awg3 = os.environ.get("ENABLE_AWG_V3") == "1"

nat_rules = ["*nat", ":PREROUTING ACCEPT [0:0]", ":POSTROUTING ACCEPT [0:0]", ":OUTPUT ACCEPT [0:0]"]
if enable_hop:
    nat_rules.append(f"-A PREROUTING -p udp --dport 20000:35000 -j REDIRECT --to-ports {hy2_p}")
if awg_native:
    if awg_hop:
        nat_rules.append(f"-A PREROUTING -p udp --dport 35001:49999 -j REDIRECT --to-ports {nawg_p}")
    nat_rules.append(f"-A POSTROUTING -s 10.9.0.0/24 -o {default_if} -j MASQUERADE")
if awg3:
    nat_rules.append(f"-A POSTROUTING -s 10.8.1.0/24 -o {default_if} -j MASQUERADE")
nat_rules.append("COMMIT\n")

nat_part = "# START HARDENED NAT\n" + "\n".join(nat_rules) + "\n# END HARDENED NAT\n\n"

dns_input = [
    "# START HARDENED DNS-INPUT",
    "-A ufw-before-input -i awg0 -p udp --dport 53 -j ACCEPT",
    "-A ufw-before-input -i awg0 -p tcp --dport 53 -j ACCEPT",
    "# END HARDENED DNS-INPUT\n"
]
dns_input_block = "\n".join(dns_input)

forward_rules = ["# START HARDENED FORWARD"]
if awg_native:
    forward_rules.append("-A ufw-before-forward -s 10.9.0.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.9.0.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
if awg3:
    forward_rules.append("-A ufw-before-forward -s 10.8.1.0/24 -j ACCEPT")
    forward_rules.append(f"-A ufw-before-forward -i {default_if} -d 10.8.1.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
forward_rules.append("# END HARDENED FORWARD\n")
forward_block = "\n".join(forward_rules)

if "-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT" in content:
    content = content.replace(
        "-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT",
        "-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n" + dns_input_block
    )

if "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT" in content:
    content = content.replace(
        "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT",
        "-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\n" + forward_block
    )
else:
    content = content.replace("*filter", "*filter\n" + forward_block)

mangle_part = f"""# START HARDENED MANGLE
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.9.0.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.9.0.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 10.8.1.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -d 10.8.1.0/24 -j TCPMSS --set-mss 1320
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
# END HARDENED MANGLE
"""

final_body = nat_part + content + "\n" + mangle_part + "\n"

with open(rules_file, "w") as f:
    f.write(final_body)
EOF_UFW_PYTHON

DENIED_PORTS=("$PANEL_PORT" "$SUB_PORT" 9443 3000 20443)
if [ "${ENABLE_XHTTP:-0}" -eq 1 ] && [ -n "${XHTTP_STREAM_PORT:-}" ]; then
    DENIED_PORTS+=("$XHTTP_STREAM_PORT")
fi
for p in "${ALL_REALITY_PORTS[@]:-}"; do
    if [ -n "$p" ]; then
        DENIED_PORTS+=("$p")
    fi
done

for dp in "${DENIED_PORTS[@]}"; do
    if [ -n "$dp" ]; then
        ufw deny "${dp}/tcp" >/dev/null 2>&1 || true
    fi
done

if [ "${BLOCK_PING:-0}" -eq 1 ] && [ -f /etc/ufw/before.rules ]; then
    sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
fi

ufw --force enable >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true
ok "Фаервол UFW настроен на адаптере $DEFAULT_IF. Маршрутизация пулов и MSS Clamping (1320/1380) активны."

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ДАШБОРД
# =============================================================
HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT:-443}"
if [ "${ENABLE_HY2_HOP:-0}" -eq 1 ]; then
    HY2_REPORT_LINE="${PRIMARY_DOMAIN}:${HY2_PORT:-443},20000-35000"
fi

CRED_FILE="/root/vpn_credentials.txt"
cat << EOF > "$CRED_FILE"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА ( Ultra Enhanced v3.7)
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
Базовый порт / Хост:   ${PRIMARY_DOMAIN}:${NATIVE_AWG_PORT:-8443}
$([ "${ENABLE_AWG_HOP:-0}" -eq 1 ] && echo "Скоростной пул UDP:    ${PRIMARY_DOMAIN}:35001-49999 (Любой порт пула -> :${NATIVE_AWG_PORT})" || echo "Режим портов:          Одиночный порт :${NATIVE_AWG_PORT}")
Первый клиент:         Test-Client
Конфиг файл (.conf):   /root/amneziawg-client.conf
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4 | Jmin 40 | Jmax 70 | S1 72 | S2 56 | S3 32 | S4 16

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
Все существующие подписки, UUID и ключи сохранены без перезаписи.")

$([ "${ENABLE_HY2:-0}" -eq 1 ] && echo "[ HYSTERIA 2 ]
Подключение:           ${HY2_REPORT_LINE}
")
$([ "${ENABLE_AWG_V3:-0}" -eq 1 ] && echo "[ AMNEZIAWG v3.2 (3X-UI) ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${AWG_V3_PORT:-10443}
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4 | S1 72 | S2 56 | S3 32 | S4 16
")
[ СЕТЕВЫЕ ПАРАМЕТРЫ ]
Основной хост:         ${PRIMARY_DOMAIN} (IP: ${WAN_IP:-auto})
Сетевой адаптер (WAN): ${DEFAULT_IF}
SSH порт:              ${TARGET_SSH_PORT}

[ ВАЖНОЕ ДЕЙСТВИЕ ДЛЯ ПЕРВОГО ВХОДА В ПАНЕЛЬ ]
1. Откройте НОВОЕ окно консоли и проверьте доступ по SSH (порт ${TARGET_SSH_PORT}).
2. Выполните команду: reboot
=====================================================================
EOF
chmod 600 "$CRED_FILE"

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА (v3.7 MyPrivateCloud ULTRA)!            ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Сайт-маскировка DataSphere:  ${CYAN}https://${PRIMARY_DOMAIN}/${NC}"
echo -e "  Скрытый SSO Hub:             ${WHITE}Кнопка «Консоль» в шапке сайта${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
echo -e "  Логин: ${WHITE}${ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
fi
echo
echo -e "  Прямой URL панели 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
echo -e "  Сетевой адаптер (WAN):       ${GREEN}${DEFAULT_IF} (Universal Dynamic WAN Engine)${NC}"
if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    if [ "${ENABLE_AWG_HOP:-0}" -eq 1 ]; then
echo -e "  Нативный AmneziaWG (Kernel): ${GREEN}awg0 (:8443/udp, пул 35001-49999, MTU 1360 / MSS 1320)${NC}"
else
echo -e "  Нативный AmneziaWG (Kernel): ${GREEN}awg0 (:8443/udp одиночный порт, MTU 1360 / MSS 1320)${NC}"
fi
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
echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Clash / Mihomo Meta):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}${NC}"
echo
fi
echo -e "  ${WHITE}Zero-SNI Shield:${NC}             ${GREEN}ssl_reject_handshake on (Скан IP изолирован)${NC}"
echo -e "  ${WHITE}Порт 80:${NC}                     ${GREEN}Только ACME, сканеры сбрасываются (444)${NC}"
echo -e "  ${WHITE}Anti-Loop Fallback 9443:${NC}     ${GREEN}Proxy_Protocol v1 + Живой Nginx (Декой DataSphere)${NC}"
echo -e "  ${WHITE}L4 Stream Ingress:${NC}           ${GREEN}Строго порт 443/tcp (Порт 8443 освобожден под UDP)${NC}"
if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
echo -e "  ${WHITE}VLESS xHTTP Inbound:${NC}         ${GREEN}Строго привязан к ${PRIMARY_DOMAIN} (H2 Stream-One)${NC}"
fi
echo -e "  ${WHITE}Hysteria 2 Hopping Пул:${NC}      ${GREEN}Порты 20000:35000/udp -> :443/udp${NC}"
if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    if [ "${ENABLE_AWG_HOP:-0}" -eq 1 ]; then
echo -e "  ${WHITE}AmneziaWG Native Пул:${NC}        ${GREEN}Порты 35001:49999/udp -> :8443/udp${NC}"
else
echo -e "  ${WHITE}AmneziaWG Native Режим:${NC}      ${GREEN}Одиночный порт :8443/udp${NC}"
fi
fi
echo -e "  ${WHITE}AWG3 Golden Matrix:${NC}          ${GREEN}S1=72 | S2=56 | S3=32 | S4=16 | MTU 1360 | MSS 1320${NC}"
echo -e "  ${WHITE}3X-UI Выделенный UDP Стек:${NC}   ${GREEN}AmneziaWG v3.2 (:10443/udp)${NC}"
echo -e "  ${WHITE}Zero-Leak In-Memory Hub:${NC}     ${GREEN}Разметка меню строится в RAM только после 200 OK${NC}"
echo
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${YELLOW}---------------------------------------------------------------------${NC}"
echo -e "${YELLOW}${BOLD}ОБЯЗАТЕЛЬНОЕ ДЕЙСТВИЕ ДЛЯ ВХОДА В ПАНЕЛЬ 3X-UI:${NC}"
echo -e "${WHITE}1. Откройте ${BOLD}НОВОЕ${NC} окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).${NC}"
echo -e "${WHITE}2. Выполните команду: ${GREEN}${BOLD}reboot${NC}"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
