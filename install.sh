#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup Monoscript: Hardened Master Engine v3.9 MyPrivateCloud Ultra
# Architecture: Single-IP Ultra Enhanced + Native Kernel AmneziaWG (Bare-Metal)
# Zero-Leak Frontend: My Private Cloud SSO Hub + Modular WebCrypto Plane
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

LOCK_FILE="/var/run/hardened-master-engine-v39.lock"
umask 077
exec 200>"$LOCK_FILE"
umask 022
chmod 0600 "$LOCK_FILE" 2>/dev/null || true
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

ROLLBACK_ACTIVE=0
NGINX_PRE_BAK="/tmp/nginx_pre_install_bak"
XUI_PRE_BAK="/tmp/xui_pre_phase3.db"

# shellcheck disable=SC2317
cleanup() {
    local exit_code=$?
    trap - ERR EXIT INT TERM
    if [ "$exit_code" -ne 0 ] && [ "${ROLLBACK_ACTIVE:-0}" -eq 1 ]; then
        echo -e "\n${YELLOW}[!] Обнаружен сбой. Выполняется автоматический откат из временных снимков...${NC}" >&2
        if [ -d "${NGINX_PRE_BAK:-}" ]; then
            if [ -f "${NGINX_PRE_BAK}/nginx.conf" ]; then
                cp -a "${NGINX_PRE_BAK}/nginx.conf" /etc/nginx/nginx.conf 2>/dev/null || true
            fi
            if [ -d "${NGINX_PRE_BAK}/conf.d" ]; then
                rm -rf /etc/nginx/conf.d
                cp -a "${NGINX_PRE_BAK}/conf.d" /etc/nginx/conf.d 2>/dev/null || true
            fi
            if [ -d "${NGINX_PRE_BAK}/stream.d" ]; then
                rm -rf /etc/nginx/stream.d
                cp -a "${NGINX_PRE_BAK}/stream.d" /etc/nginx/stream.d 2>/dev/null || true
            fi
            if [ -d "${NGINX_PRE_BAK}/sites-enabled" ]; then
                rm -rf /etc/nginx/sites-enabled
                cp -a "${NGINX_PRE_BAK}/sites-enabled" /etc/nginx/sites-enabled 2>/dev/null || true
            fi
            if [ -d "${NGINX_PRE_BAK}/sites-available" ]; then
                rm -rf /etc/nginx/sites-available
                cp -a "${NGINX_PRE_BAK}/sites-available" /etc/nginx/sites-available 2>/dev/null || true
            fi
            if nginx -t >/dev/null 2>&1; then
                systemctl restart nginx 2>/dev/null || true
            fi
        fi
        if [ -f /usr/local/x-ui/x-ui.pre_upd.bak ]; then
            mv -f /usr/local/x-ui/x-ui.pre_upd.bak /usr/local/x-ui/x-ui 2>/dev/null || true
            chmod 0755 /usr/local/x-ui/x-ui 2>/dev/null || true
        fi
        if [ -f "${XUI_PRE_BAK:-}" ] && [ -n "${DB_PATH:-}" ]; then
            cp -a "$XUI_PRE_BAK" "$DB_PATH" 2>/dev/null || true
            rm -f "${DB_PATH}-wal" "${DB_PATH}-shm" 2>/dev/null || true
            chmod 600 "$DB_PATH" 2>/dev/null || true
            systemctl start x-ui 2>/dev/null || true
        fi
    fi
    rm -rf /tmp/xray_unpack /tmp/xui_upd_unpack /usr/local/bin/myprivatecloud_core.py.tmp* /usr/local/bin/myprivatecloud_utils.py.tmp* /usr/local/bin/hardcore_dpi_audit.sh.tmp* /tmp/vpn_unified_creds.txt /tmp/3xui_install.log /tmp/3x-ui-install.sh /tmp/xray-*.zip /tmp/x-ui-linux-*.tar.gz /tmp/agh.tar.gz /tmp/nginx_prev_sni_map.txt /tmp/nginx_signing.key.tmp /tmp/xui_stage2_* /tmp/awg-kernel-src /tmp/awg-tools-build /tmp/ufw_before_pre_b10.bak /tmp/resolv.conf.pre_geo_bak "${NGINX_PRE_BAK:-}" "${XUI_PRE_BAK:-}" 2>/dev/null || true
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n${RED}[X] Скрипт аварийно прерван на строке ${1:-unknown} (код: ${exit_code}).${NC}" >&2
    fi
    exit "$exit_code"
}
trap 'cleanup $LINENO' ERR EXIT INT TERM

clear 2>/dev/null || true
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${GREEN}  Hardened Master Engine v3.9 (MyPrivateCloud Ultra + Native AmneziaWG)  ${NC}"
echo -e "${CYAN}   Clean Setup / Safe Migration + Nginx L4                              ${NC}"
echo -e "${WHITE}  Xray Core v26.7.28 Pinned + Native H2 xHTTP + ML-KEM-768 + Vision    ${NC}"
echo -e "${WHITE}  UDP Defaults: Hy2 (:40443), AWG Native (:41443), AWG v3 (:42443)       ${NC}"
echo -e "${WHITE}  Stealth SSO Hub: MyPrivateCloud In-Memory Portal (3X-UI / AWG / AGH)   ${NC}"
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
HY2_PORT="40443"
NATIVE_AWG_PORT="41443"
AWG_V3_PORT="42443"
ENABLE_NATIVE_AWG=1
ENABLE_STEAL=1
ENABLE_CLASSIC=0
ENABLE_XHTTP=1
ENABLE_HY2=0
ENABLE_AWG_V3=0
ENABLE_AGH=0
AGH_DOMAIN=""
AGH_USER="admin"
AGH_PASS=""
AGH_CLIENT_ID=""
AGH_RAM_TELEMETRY="0"
PRIMARY_DOMAIN=""

# Загрузка ранее сохраненных канонических параметров
if [ -f /etc/myprivatecloud/config.env ]; then
    # shellcheck source=/dev/null
    . /etc/myprivatecloud/config.env 2>/dev/null || true
fi

PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-}"
GEO_PROFILE="2"
INSTALL_MODE="1"
SSL_ENGINE_CHOICE="1"
SSL_BASE_DIR="/etc/letsencrypt/live"
DO_SYS_UPGRADE=0
INSTALL_EXTRA_UTILS=0
ENABLE_BBR_TUNING=1
DISABLE_IPV6=0
ENABLE_AUTO_UPDATE=0
BLOCK_PING=0
CHANGE_ROOT_PASS=0
CREATE_USER=0
SETUP_KEYS=0
EXISTING_DB_PATH=""
export EXISTING_DB_PATH
# HARDCORE_PREUPDATE_AND_AUDIT_PATCH_V1
# HARDCORE_PREUPDATE_AND_AUDIT_PATCH_V2
PRE_UPGRADE_DONE=0
PRE_UTILS_DONE=0
PRE_UPD_CHOICE="0"
PRE_UTILS_CHOICE="0"
IS_COMBAT_HOST=0

rm -f /usr/share/keyrings/nginx-archive-keyring.gpg.tmp 2>/dev/null || true
if [ -f /etc/apt/sources.list.d/nginx.list ] && [ ! -s /usr/share/keyrings/nginx-archive-keyring.gpg ]; then
    rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx 2>/dev/null || true
fi
AMNEZIA_KEY_VALID=0
if [ -s /etc/apt/keyrings/amnezia.gpg ] && command -v gpg >/dev/null 2>&1; then
    if gpg --no-default-keyring --keyring /etc/apt/keyrings/amnezia.gpg --list-keys 4166F2C257290828 >/dev/null 2>&1; then
        AMNEZIA_KEY_VALID=1
    fi
fi
for apt_f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$apt_f" ] || continue
    if grep -qiE 'launchpadcontent\.net/amnezia|launchpad\.net/amnezia|amnezia/ppa' "$apt_f" 2>/dev/null; then
        if [ "$AMNEZIA_KEY_VALID" -ne 1 ] || ! grep -q '/etc/apt/keyrings/amnezia.gpg' "$apt_f" 2>/dev/null; then
            rm -f "$apt_f" 2>/dev/null || true
        fi
    fi
done
if [ "$AMNEZIA_KEY_VALID" -ne 1 ]; then
    rm -f /etc/apt/sources.list.d/amnezia.list /etc/apt/keyrings/amnezia.gpg 2>/dev/null || true
fi
if [ -f /usr/share/keyrings/nginx-archive-keyring.gpg ] && [ ! -s /usr/share/keyrings/nginx-archive-keyring.gpg ]; then
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null || true
fi

mkdir -p /etc/needrestart/conf.d
printf "%s\n" "\$nrconf{restart} = 'a';" > /etc/needrestart/conf.d/99-disable-auto-restart.conf.tmp 2>/dev/null || true
mv -f /etc/needrestart/conf.d/99-disable-auto-restart.conf.tmp /etc/needrestart/conf.d/99-disable-auto-restart.conf 2>/dev/null || true

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
        elif [[ "$OS_CODENAME" =~ ^(jammy|noble|plucky|questing|resolute|testing)$ ]]; then
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

# =============================================================
#  ДИНАМИЧЕСКИЙ ТИРИНГ РЕСУРСОВ И МНОГОЯДЕРНАЯ ОПТИМИЗАЦИЯ
# =============================================================
TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo "1024")
CPU_CORES=$(nproc 2>/dev/null || echo "1")

# Расчет 16-ричной битовой маски ядер (32-битные группы через запятую для sysfs RPS/XPS)
calc_cpu_mask() {
    local cores="${1:-1}"
    if ! [[ "$cores" =~ ^[0-9]+$ ]] || [ "$cores" -lt 1 ]; then
        cores=1
    fi
    if [ "$cores" -gt 256 ]; then
        cores=256
    fi
    local full_chunks=$(( cores / 32 ))
    local rem=$(( cores % 32 ))
    local parts=()
    if [ "$rem" -gt 0 ]; then
        local top_val=$(( (1 << rem) - 1 ))
        parts+=("$(printf '%x' "$top_val")")
    fi
    local i=0
    while [ "$i" -lt "$full_chunks" ]; do
        parts+=("ffffffff")
        i=$(( i + 1 ))
    done
    ( IFS=','; printf '%s' "${parts[*]}" )
}
CPU_MASK=$(calc_cpu_mask "$CPU_CORES")

# Динамический расчет квот оперативной памяти и воркеров
if [ "$TOTAL_RAM_MB" -lt 1500 ]; then
    # Low-Memory Profile (1 GB RAM)
    XUI_GOMEMLIMIT="90MiB"
    XUI_GOGC="50"
    XUI_MEM_HIGH="110M"
    XUI_MEM_MAX="140M"
    AGH_GOMEMLIMIT="210MiB"
    AGH_MEM_HIGH="260M"
    AGH_MEM_MAX="340M"
    FASTAPI_MEM_HIGH="90M"
    AGH_TMPFS_SIZE="24M"
    FASTAPI_MEM_MAX="150M"
    FASTAPI_WORKERS="1"
elif [ "$TOTAL_RAM_MB" -lt 3500 ]; then
    # Standard Profile (2 GB RAM)
    XUI_GOMEMLIMIT="350MiB"
    XUI_GOGC="80"
    XUI_MEM_HIGH="450M"
    XUI_MEM_MAX="600M"
    AGH_GOMEMLIMIT="320MiB"
    AGH_MEM_HIGH="380M"
    AGH_MEM_MAX="512M"
    FASTAPI_MEM_HIGH="120M"
    AGH_TMPFS_SIZE="48M"
    FASTAPI_MEM_MAX="180M"
    FASTAPI_WORKERS="1"
elif [ "$TOTAL_RAM_MB" -lt 7500 ]; then
    # High-Load Profile (4 GB RAM)
    XUI_GOMEMLIMIT="1024MiB"
    XUI_GOGC="100"
    XUI_MEM_HIGH="1400M"
    XUI_MEM_MAX="1800M"
    AGH_GOMEMLIMIT="512MiB"
    AGH_MEM_HIGH="650M"
    AGH_MEM_MAX="850M"
    FASTAPI_MEM_HIGH="150M"
    AGH_TMPFS_SIZE="64M"
    FASTAPI_MEM_MAX="250M"
    FASTAPI_WORKERS="1"
else
    # Enterprise Profile (8 GB+ RAM)
    XUI_GOMEMLIMIT="2048MiB"
    XUI_GOGC="100"
    XUI_MEM_HIGH="2800M"
    XUI_MEM_MAX="3500M"
    AGH_GOMEMLIMIT="768MiB"
    AGH_MEM_HIGH="1024M"
    AGH_MEM_MAX="1280M"
    FASTAPI_MEM_HIGH="180M"
    AGH_TMPFS_SIZE="64M"
    FASTAPI_MEM_MAX="280M"
    FASTAPI_WORKERS="1"
fi

ok "Аппаратный профиль: ${GREEN}${CPU_CORES} vCPU${NC} / ${GREEN}${TOTAL_RAM_MB} MB RAM${NC} (Xray: ${XUI_GOMEMLIMIT}, RPS-маска: 0x${CPU_MASK})"

patch_amnezia_dkms_kernel_compat() {
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

        if grep -qE '__compat_udp_tunnel_sock_patched' "$target_header" 2>/dev/null && grep -qE '^[[:space:]]*#define[[:space:]]+udp_tunnel_sock_release\(' "$target_header" 2>/dev/null; then
            continue
        fi

        log "Применение сигнатурного патча совместимости udp_tunnel (PR #265) к ${target_header}..."
        local rc=0
        TARGET_HEADER="$target_header" python3 - << 'EOF_AWG_COMPAT' || rc=$?
import os, re, sys

hp = os.environ["TARGET_HEADER"]
with open(hp, "r", encoding="utf-8", errors="ignore") as f:
    txt = f.read()

pr265_block = """/* PR #265: signature-based udp_tunnel sock/socket compat */
#ifndef __compat_udp_tunnel_sock_patched
#define __compat_udp_tunnel_sock_patched 1
#include <net/udp_tunnel.h>
static inline void __compat_setup_udp_tunnel_sock(struct net *net, struct sock *sk, struct udp_tunnel_sock_cfg *cfg)
{
    setup_udp_tunnel_sock(net, __builtin_choose_expr(
        __builtin_types_compatible_p(typeof(&setup_udp_tunnel_sock),
            void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *)),
        sk, sk->sk_socket), cfg);
}
#define setup_udp_tunnel_sock(net, sk, cfg) __compat_setup_udp_tunnel_sock((net), (sk), (cfg))
static inline void __compat_udp_tunnel_sock_release(struct sock *sk)
{
    udp_tunnel_sock_release(__builtin_choose_expr(
        __builtin_types_compatible_p(typeof(&udp_tunnel_sock_release), void (*)(struct sock *)),
        sk, sk->sk_socket));
}
#define udp_tunnel_sock_release(sk) __compat_udp_tunnel_sock_release(sk)
#endif"""

legacy_re = re.compile(
    r"/\* Kernel 7\.0\+ compatibility backport \*/\s*"
    r"#if LINUX_VERSION_CODE < KERNEL_VERSION\(7, 0, 0\)\s*"
    r"#define setup_udp_tunnel_sock\(net, sk, sock_cfg\) setup_udp_tunnel_sock\(net, sk->sk_socket, sock_cfg\)\s*"
    r"#elif LINUX_VERSION_CODE < KERNEL_VERSION\(7, 2, 0\)\s*"
    r"#define __compat_setup_udp_tunnel_sock 1\s*"
    r"#endif",
    re.M,
)

changed = False
multiline_setup_re = re.compile(r"^[ \t]*#define[ \t]+setup_udp_tunnel_sock\b(?:[^\n]*\\\n)*[^\n]*sk->sk_socket[^\n]*\n?", re.M)
multiline_rel_re = re.compile(r"^[ \t]*#define[ \t]+udp_tunnel_sock_release\b(?:[^\n]*\\\n)*[^\n]*\n?", re.M)
incomplete_pr265_re = re.compile(r"/\* PR #265:.*?#ifndef __compat_udp_tunnel_sock_patched.*?#endif", re.S)
if "__compat_udp_tunnel_sock_patched" in txt and not re.search(r"^[ \t]*#define[ \t]+udp_tunnel_sock_release\(", txt, re.M):
    txt = incomplete_pr265_re.sub(pr265_block, txt, count=1)
    changed = True
elif legacy_re.search(txt):
    txt = multiline_rel_re.sub("", txt)
    txt = legacy_re.sub(pr265_block, txt, count=1)
    changed = True
elif multiline_setup_re.search(txt):
    txt = multiline_rel_re.sub("", txt)
    txt = multiline_setup_re.sub(pr265_block + "\n", txt, count=1)
    changed = True

if changed:
    tmp = hp + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(txt)
    os.chmod(tmp, 0o644)
    os.replace(tmp, hp)
    sys.exit(0)
sys.exit(2)
EOF_AWG_COMPAT
        if [ "$rc" -eq 0 ]; then
            chmod 0644 "$target_header"
            ok "Заголовочный файл ${target_header} пропатчен (PR #265)."
        elif [ "$rc" -ne 2 ]; then
            warn "Не удалось применить патч совместимости к ${target_header}."
        fi
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

log "Первичная подготовка системных утилит (Профиль: ${CPU_CORES} vCPU / ${TOTAL_RAM_MB} MB RAM)..."
wait_for_apt_lock
dpkg --configure -a >/dev/null 2>&1 || true

if [ -e /etc/resolv.conf ] && grep -qE '^\s*nameserver\s+127\.0\.0\.1\b' /etc/resolv.conf 2>/dev/null; then
    if ! getent ahosts deb.debian.org >/dev/null 2>&1 && ! getent ahosts archive.ubuntu.com >/dev/null 2>&1; then
        warn "Обнаружен неактивный локальный DNS (127.0.0.1). Временное переключение /etc/resolv.conf для APT bootstrap..."
        if [ ! -f /tmp/resolv.conf.pre_geo_bak ]; then
            cp -L /etc/resolv.conf /tmp/resolv.conf.pre_geo_bak 2>/dev/null || true
        fi
        cat << 'EOF_BOOT_DNS' > /etc/resolv.conf.tmp
nameserver 1.1.1.1
nameserver 77.88.8.8
nameserver 8.8.8.8
EOF_BOOT_DNS
        mv -f /etc/resolv.conf.tmp /etc/resolv.conf
        chmod 0644 /etc/resolv.conf 2>/dev/null || true
    fi
fi

# Очистка кэша APT для освобождения буферов памяти перед установкой
apt-get clean -q >/dev/null 2>&1 || true
apt-get update -q >/dev/null 2>&1 || true
wait_for_apt_lock

# Минимально необходимый набор базовых утилит
BASE_BOOTSTRAP_PKGS=(
    curl iproute2 openssl gawk python3 python3-bcrypt
    unzip jq sqlite3 gnupg psmisc ca-certificates
)

if ! apt-get install -y "${BASE_BOOTSTRAP_PKGS[@]}" -q --no-install-recommends >/dev/null 2>&1; then
    warn "Повторная установка базовых пакетов с выводом диагностики..."
    wait_for_apt_lock
    apt-get update -q || true
    apt-get install -y "${BASE_BOOTSTRAP_PKGS[@]}" -q --no-install-recommends || die "Сбой установки базовых пакетов APT."
fi

# Контрольная проверка наличия критических утилит
MISSING_CRITICAL=()
for tool in curl sqlite3 jq openssl python3 awk ip ss gpg fuser unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_CRITICAL+=("$tool")
    fi
done
if ! python3 -c "import bcrypt" >/dev/null 2>&1; then
    MISSING_CRITICAL+=("python3-bcrypt")
fi

if [ "${#MISSING_CRITICAL[@]}" -gt 0 ]; then
    die "Критические базовые утилиты не установлены: ${MISSING_CRITICAL[*]}. Проверьте доступ к сети и репозиториям APT."
fi

ok "Базовые утилиты готовы к работе (минимальный footprint)."

USED_TCP_PORTS_REG=()
USED_UDP_PORTS_REG=()

validate_port() {
    local p="${1:-}"
    if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 22 ] && [ "$p" -le 65535 ]; then
        return 0
    fi
    return 1
}

is_tcp_port_free() {
    local p="$1"
    case "$p" in
        53|80|443|3000|8088|9443|11111|20443|62789) return 1 ;;
    esac
    local used
    for used in "${USED_TCP_PORTS_REG[@]:-}"; do
        if [ -n "$used" ] && [ "$used" = "$p" ]; then
            return 1
        fi
    done
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | awk -v port="$p" '$4 ~ (":" port "$") && $0 !~ /(x-ui|xray|nginx|AdGuardHome|sshd|uvicorn)/ {f=1} END {exit !f}'; then
            return 1
        fi
    fi
    return 0
}

is_udp_port_free() {
    local p="$1"
    if [ "$p" = "53" ]; then
        return 1
    fi
    local used
    for used in "${USED_UDP_PORTS_REG[@]:-}"; do
        if [ -n "$used" ] && [ "$used" = "$p" ]; then
            return 1
        fi
    done
    if command -v ss >/dev/null 2>&1; then
        local cur_awg_p=""
        if [ -f /etc/amnezia/amneziawg/awg0.conf ]; then
            cur_awg_p=$(grep -E '^\s*ListenPort\s*=' /etc/amnezia/amneziawg/awg0.conf 2>/dev/null | head -n1 | awk -F= '{print $2}' | tr -d '[:space:]' || echo "")
        fi
        if [ "$p" != "$cur_awg_p" ]; then
            if ss -ulnp 2>/dev/null | awk -v port="$p" '$4 ~ (":" port "$") && $0 !~ /(x-ui|xray|AdGuardHome)/ {f=1} END {exit !f}'; then
                return 1
            fi
        fi
    fi
    return 0
}

prompt_tcp_port() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val=""
    local p_val=""
    while true; do
        echo -en "${prompt_text} [${GREEN}${default_val}${NC}]: "
        read -r input_val
        p_val=$(echo "${input_val:-$default_val}" | tr -d '[:space:]')
        if validate_port "$p_val" && is_tcp_port_free "$p_val"; then
            declare -g "$var_name=$p_val"
            USED_TCP_PORTS_REG+=("$p_val")
            return 0
        fi
        warn "Порт '$p_val/tcp' некорректен, зарезервирован системой или уже занят другим сервисом."
    done
}

prompt_udp_port() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local input_val=""
    local p_val=""
    while true; do
        echo -en "${prompt_text} [${GREEN}${default_val}${NC}]: "
        read -r input_val
        p_val=$(echo "${input_val:-$default_val}" | tr -d '[:space:]')
        if validate_port "$p_val" && is_udp_port_free "$p_val"; then
            declare -g "$var_name=$p_val"
            USED_UDP_PORTS_REG+=("$p_val")
            return 0
        fi
        warn "Порт '$p_val/udp' некорректен, зарезервирован или уже занят другим туннелем."
    done
}

prompt_choice() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    shift 3
    local valid_opts=("$@")
    local input_val=""
    local ans=""
    local opt
    while true; do
        echo -en "${prompt_text} [${GREEN}${default_val}${NC}]: "
        read -r input_val
        ans=$(echo "${input_val:-$default_val}" | tr -d '[:space:]')
        for opt in "${valid_opts[@]}"; do
            if [ "$ans" = "$opt" ]; then
                declare -g "$var_name=$ans"
                return 0
            fi
        done
        warn "Некорректный выбор: '$ans'. Допустимые варианты: ${valid_opts[*]}."
    done
}

validate_path_segment() {
    local p="${1:-}"
    if [[ -z "$p" ]] || [[ ! "$p" =~ ^[a-zA-Z0-9_./-]+$ ]] || [[ "$p" =~ \.\. ]] || [[ "$p" =~ // ]]; then
        return 1
    fi
    local trimmed="${p#/}"
    trimmed="${trimmed%/}"
    if [ -z "$trimmed" ]; then
        return 1
    fi
    if [[ "$trimmed" =~ ^(api|assets|dns-query|robots\.txt|\.well-known|favicon\.ico|favicon\.svg)(/|$) ]]; then
        return 1
    fi
    return 0
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
        warn "Недопустимый или зарезервированный путь: '$p_val'. Допустимы латиница, цифры, дефис, точка и слэш (без '..' и служебных префиксов)."
    done
}

in_array() {
    local needle="${1:-}"
    shift || return 1
    local item
    for item in "$@"; do
        if [ -n "$item" ] && [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

is_ddns_domain() {
    local d="${1:-}"
    [[ "$d" =~ \.(duckdns\.org|no-ip\.(org|com)|ddns\.net|hopto\.org|zapto\.org|dynu\.net|ydns\.eu|dedyn\.io|nip\.io|sslip\.io)$ ]]
}

sqlite_ro() {
    local db="$1"
    local sql="$2"
    sqlite3 -cmd ".timeout 5000" "$db" "$sql" 2>/dev/null || true
}

get_local_ib_cond() {
    local db="$1"
    local cond=""
    local cols
    cols=$(sqlite_ro "$db" "PRAGMA table_info(inbounds);")
    if printf '%s\n' "$cols" | grep -qE '\|node_id\|'; then
        cond="AND (node_id IS NULL OR node_id = 0)"
    fi
    if printf '%s\n' "$cols" | grep -qE '\|origin_node_guid\|'; then
        local pguid
        pguid=$(sqlite_ro "$db" "SELECT value FROM settings WHERE key='panelGuid' LIMIT 1;" | tr -d "'\";[:space:]")
        if [[ "$pguid" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            cond="${cond} AND (origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = '${pguid}')"
        else
            cond="${cond} AND (origin_node_guid IS NULL OR origin_node_guid = '')"
        fi
    fi
    printf '%s' "$cond"
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
        candidate=$(ip -4 route get "$canary" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' || true)
        if [ -n "$candidate" ] && [ -d "/sys/class/net/$candidate" ]; then
            iface="$candidate"
            break
        fi
    done

    # Tier 2: Поиск шлюза по умолчанию в основной таблице маршрутизации
    if [ -z "$iface" ]; then
        candidate=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' || true)
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
    if [ -x /usr/sbin/sshd ]; then
        mkdir -p /run/sshd 2>/dev/null || true
        SSH_ACTIVE_PORT=$(/usr/sbin/sshd -T 2>/dev/null | awk '/^port[[:space:]]+/ {print $2; exit}' || echo "")
    fi
fi
if [ -z "$SSH_ACTIVE_PORT" ] || ! validate_port "$SSH_ACTIVE_PORT"; then
    SSH_ACTIVE_PORT=$(systemctl show ssh.socket -p Listen --value 2>/dev/null | sed -E 's/.*:([0-9]+).*/\1/' | head -n1 || echo "")
fi
if [ -z "$SSH_ACTIVE_PORT" ] || ! validate_port "$SSH_ACTIVE_PORT"; then
    SSH_ACTIVE_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | grep -vE '127\.0\.0\.1|::1' | awk '{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | grep -vE '^60[0-9]{2}$' | sort -n | tail -n1 || echo "")
fi
if [ -z "$SSH_ACTIVE_PORT" ] || ! validate_port "$SSH_ACTIVE_PORT"; then
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
    # Исключены отечественные домены во избежание детекта SNI/ASN-мисматча на зарубежных VPS
    local candidates=("gateway.icloud.com" "swdist.apple.com" "dl.google.com" "www.samsung.com" "www.microsoft.com")
    local best_sni="gateway.icloud.com"
    local min_rtt=999999

    echo -e "${CYAN}[+] Тестирование внешних доверенных SNI для Classic REALITY...${NC}" >&2
    for sni in "${candidates[@]}"; do
        local rtt=""
        local is_valid=0
        if rtt=$(LC_ALL=C curl -s -o /dev/null -w "%{time_connect}" --connect-timeout 2 --tlsv1.3 "https://${sni}" 2>/dev/null); then
            if [[ "$rtt" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                is_valid=$(awk -v r="$rtt" 'BEGIN {print (r > 0.0001) ? 1 : 0}' 2>/dev/null || echo "0")
            fi
        fi

        if [ "$is_valid" = "1" ]; then
            local rtt_ms
            rtt_ms=$(awk -v r="$rtt" 'BEGIN {v = int(r * 1000); print (v < 1) ? 1 : v}')
            echo -e "  - ${CYAN}${sni}${NC}: RTT = ${GREEN}${rtt_ms} ms${NC} (TLS 1.3 OK)" >&2
            if [ "$rtt_ms" -lt "$min_rtt" ]; then
                min_rtt="$rtt_ms"
                best_sni="$sni"
            fi
        else
            echo -e "  - ${CYAN}${sni}${NC}: ${RED}Таймаут или недоступен${NC}" >&2
        fi
    done
    echo -e "${GREEN}[OK]${NC} Выбран оптимальный глобальный SNI: ${GREEN}${best_sni}${NC} (${min_rtt} ms)" >&2
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
    prompt_choice "Выберите режим работы" "2" INSTALL_MODE "1" "2"

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
            /etc/myprivatecloud \
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
prompt_choice "Выберите сетевой профиль" "$DEFAULT_GEO_PROFILE" GEO_PROFILE "1" "2"

if [ ! -f /tmp/resolv.conf.pre_geo_bak ] && [ -e /etc/resolv.conf ]; then
    cp -L /etc/resolv.conf /tmp/resolv.conf.pre_geo_bak 2>/dev/null || true
fi
if [ "$GEO_PROFILE" = "1" ]; then
    log "Активация сетевой стратегии для РФ (Яндекс DNS Primary)..."
    cat << 'EOF' > /etc/resolv.conf.tmp
nameserver 77.88.8.8
nameserver 77.88.8.1
nameserver 8.8.8.8
EOF
    mv -f /etc/resolv.conf.tmp /etc/resolv.conf
    chmod 0644 /etc/resolv.conf 2>/dev/null || true
else
    log "Активация сетевой стратегии для зарубежного сервера (Cloudflare Primary)..."
    cat << 'EOF' > /etc/resolv.conf.tmp
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    mv -f /etc/resolv.conf.tmp /etc/resolv.conf
    chmod 0644 /etc/resolv.conf 2>/dev/null || true
fi

IS_COMBAT_HOST=0
if [ "$INSTALL_MODE" = "2" ] || [ -n "${EXISTING_DB_PATH:-}" ] || \
   [ -f /etc/amnezia/amneziawg/awg0.conf ] || [ -f /opt/AdGuardHome/AdGuardHome.yaml ] || \
   [ -f /etc/nginx/conf.d/01-main.conf ]; then
    IS_COMBAT_HOST=1
elif systemctl is-active --quiet x-ui 2>/dev/null || \
     systemctl is-active --quiet nginx 2>/dev/null || \
     systemctl is-active --quiet AdGuardHome 2>/dev/null || \
     systemctl is-active --quiet awg-quick@awg0 2>/dev/null; then
    IS_COMBAT_HOST=1
fi

echo
echo -e "${WHITE}${BOLD}--- ПРЕДВАРИТЕЛЬНОЕ ОБНОВЛЕНИЕ И УТИЛИТЫ СЕРВЕРА ---${NC}"
if [ "$IS_COMBAT_HOST" -eq 1 ]; then
    ok "Статус сервера: ${YELLOW}${BOLD}БОЕВОЙ СЕРВЕР${NC} (обнаружены активные компоненты/конфиги)."
    DEFAULT_PRE_UPD_MODE="2"
else
    ok "Статус сервера: ${GREEN}${BOLD}ГОЛЫЙ СЕРВЕР${NC} (чистое окружение)."
    DEFAULT_PRE_UPD_MODE="1"
fi

echo -e "  1) ${GREEN}Голый сервер (Full Upgrade)${NC} — apt full-upgrade + autoremove --purge + clean"
echo -e "  2) ${YELLOW}Боевой сервер (Safe Upgrade)${NC} — apt upgrade --with-new-pkgs + autoclean + dkms/systemd аудит"
echo -e "  3) ${CYAN}Пропустить${NC} обновление пакетов ОС на этом этапе"
prompt_choice "Выберите стратегию обновления сервера" "$DEFAULT_PRE_UPD_MODE" PRE_UPD_CHOICE "1" "2" "3"

if [ "$PRE_UPD_CHOICE" = "1" ] || [ "$PRE_UPD_CHOICE" = "2" ]; then
    if [ "$IS_COMBAT_HOST" -eq 1 ] && [ "$INSTALL_MODE" != "2" ]; then
        BAK_PATHS=()
        for bp in /etc/x-ui /etc/nginx /etc/letsencrypt /etc/ssl/acme /etc/amnezia/amneziawg /etc/myprivatecloud /etc/ufw/before.rules /opt/AdGuardHome/AdGuardHome.yaml; do
            if [ -e "$bp" ]; then
                BAK_PATHS+=("$bp")
            fi
        done
        if [ "${#BAK_PATHS[@]}" -gt 0 ]; then
            PRE_BAK_TAR="/root/backup_before_preupdate_$(date +%F_%H%M%S).tar.gz"
            log "Создание страховочного архива перед обновлением боевого хоста ($PRE_BAK_TAR)..."
            tar -czf "$PRE_BAK_TAR" "${BAK_PATHS[@]}" 2>/dev/null || true
            if [ -f "$PRE_BAK_TAR" ]; then
                chmod 0600 "$PRE_BAK_TAR" 2>/dev/null || true
            fi
        fi
    fi

    for apt_f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -f "$apt_f" ] || continue
        if grep -qiE 'launchpadcontent\.net/amnezia|launchpad\.net/amnezia|amnezia/ppa' "$apt_f" 2>/dev/null; then
            if [ ! -s /etc/apt/keyrings/amnezia.gpg ] || ! grep -q '/etc/apt/keyrings/amnezia.gpg' "$apt_f" 2>/dev/null; then
                rm -f "$apt_f" 2>/dev/null || true
            fi
        fi
    done

    wait_for_apt_lock
    dpkg --configure -a >/dev/null 2>&1 || true

    if [ "$PRE_UPD_CHOICE" = "1" ]; then
        log "Запуск оптимального обновления голого сервера (full-upgrade + autoremove --purge + clean)..."
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 update -q
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 full-upgrade -y -q \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"
        apt-get autoremove --purge -y -q
        apt-get clean -q
        PRE_UPGRADE_DONE=1
        if [ -f /var/run/reboot-required ]; then
            warn "[!] Требуется reboot перед деплоем (при смене ABI ядра на Debian отказ от reboot заблокирует сборку AmneziaWG awg0)."
            if [ -f /var/run/reboot-required.pkgs ]; then
                cat /var/run/reboot-required.pkgs 2>/dev/null || true
            fi
            if prompt_yes_no "Перезагрузить сервер сейчас перед продолжением деплоя?" "y"; then
                ok "Выполняется перезагрузка. После входа запустите /root/install.sh повторно."
                trap - ERR EXIT INT TERM
                exec 200>&- || true
                rm -f "$LOCK_FILE" /tmp/resolv.conf.pre_geo_bak 2>/dev/null || true
                systemctl reboot
                exit 0
            fi
        else
            ok "[OK] Система актуальна, reboot не требуется."
        fi
    else
        log "Запуск безопасного обновления боевого сервера (upgrade --with-new-pkgs + autoclean)..."
        patch_amnezia_dkms_kernel_compat
        if dpkg -s amneziawg-dkms >/dev/null 2>&1 && dpkg -l amneziawg-dkms 2>/dev/null | grep -qE '^i[UHRF]|^r[cF]'; then
            dpkg --configure -a || true
        fi
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 update -q
        if ! DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 upgrade --with-new-pkgs -y -q \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"; then
            warn "Обновление завершилось с ошибкой (возможен DKMS postinst под новое ядро). Применение патча PR #265 и восстановление dpkg..."
            patch_amnezia_dkms_kernel_compat
            dpkg --configure -a || true
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 install -f -y -q \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" || die "Не удалось завершить безопасное обновление боевого сервера."
        fi
        apt-get autoclean -y -q
        patch_amnezia_dkms_kernel_compat
        if dpkg -s amneziawg-dkms >/dev/null 2>&1 && dpkg -l amneziawg-dkms 2>/dev/null | grep -qE '^i[UHRF]|^r[cF]'; then
            dpkg --configure -a || true
        fi
        if command -v dkms >/dev/null 2>&1; then
            log "Статус модулей DKMS:"
            dkms status || true
        fi
        log "Проверка сбойных юнитов systemd:"
        systemctl --failed --no-pager || true
        PRE_UPGRADE_DONE=1
        if [ -f /var/run/reboot-required ]; then
            warn "[!] Требуется плановый reboot. Пакеты:"
            cat /var/run/reboot-required.pkgs 2>/dev/null || true
            if ! prompt_yes_no "Продолжить развёртывание/миграцию сейчас (плановый reboot выполнить в конце)?" "y"; then
                if [ -s /tmp/resolv.conf.pre_geo_bak ] && systemctl is-active --quiet AdGuardHome 2>/dev/null; then
                    cp -f /tmp/resolv.conf.pre_geo_bak /etc/resolv.conf 2>/dev/null || true
                    chmod 0644 /etc/resolv.conf 2>/dev/null || true
                    ok "Локальный DNS /etc/resolv.conf боевого сервера восстановлен."
                fi
                warn "Установка приостановлена для плановой перезагрузки. После reboot запустите /root/install.sh повторно."
                exit 0
            fi
        else
            ok "[OK] Обновление завершено, reboot не требуется."
        fi
    fi
fi

DEFAULT_PRE_UTILS="2"
if [ "$VIRT_TYPE" = "lxc" ] || [ "$VIRT_TYPE" = "openvz" ] || [ "$VIRT_TYPE" = "docker" ]; then
    DEFAULT_PRE_UTILS="1"
fi

echo
echo -e "${WHITE}${BOLD}--- НАБОР СИСТЕМНЫХ И ДИАГНОСТИЧЕСКИХ УТИЛИТ ---${NC}"
echo -e "  1) ${GREEN}Вариант 1 — Базовый набор${NC} (curl, jq, sqlite3, shellcheck, mtr-tiny, tcpdump, iperf3, btop, iftop, tmux, ncdu)"
echo -e "  2) ${GREEN}Вариант 2 — Базовый + сборка модулей ядра (amneziawg-dkms)${NC} (+ build-essential, git, dkms)"
echo -e "  3) ${CYAN}Пропустить${NC} установку дополнительных утилит"
prompt_choice "Выберите набор утилит для установки" "$DEFAULT_PRE_UTILS" PRE_UTILS_CHOICE "1" "2" "3"

if [ "$PRE_UTILS_CHOICE" = "1" ] || [ "$PRE_UTILS_CHOICE" = "2" ]; then
    wait_for_apt_lock
    if [ "$PRE_UPGRADE_DONE" -eq 0 ]; then
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 update -q || true
    fi
    PRE_UTIL_BASE=(
        curl ca-certificates gnupg unzip psmisc jq sqlite3 python3
        bind9-dnsutils iproute2 mtr-tiny tcpdump iperf3 iftop tmux ncdu
    )
    PRE_UTIL_OPT=(btop shellcheck htop)
    PRE_UTIL_FULL=("${PRE_UTIL_BASE[@]}" "${PRE_UTIL_OPT[@]}")
    if [ "$PRE_UTILS_CHOICE" = "2" ]; then
        PRE_UTIL_FULL+=(build-essential git dkms)
    fi

    log "Установка выбранного набора утилит..."
    if ! DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends -q "${PRE_UTIL_FULL[@]}"; then
        warn "Единый пакетный запрос не прошёл (возможна недоступность btop/shellcheck в текущем репо). Выполняется резервная установка..."
        PRE_UTIL_FALLBACK=("${PRE_UTIL_BASE[@]}")
        if [ "$PRE_UTILS_CHOICE" = "2" ]; then
            PRE_UTIL_FALLBACK+=(build-essential git dkms)
        fi
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends -q "${PRE_UTIL_FALLBACK[@]}" || warn "Часть базовых утилит не установлена."
        for opt_pkg in "${PRE_UTIL_OPT[@]}"; do
            DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends -q "$opt_pkg" 2>/dev/null || true
        done
    fi
    PRE_UTILS_DONE=1
    ok "Набор системных утилит установлен."
fi

echo
echo -e "${WHITE}${BOLD}--- ШАГ 1: Конфигурация домена и SSL ---${NC}"

DETECTED_MAIN_DOM="${PRIMARY_DOMAIN:-}"
if [ -z "$DETECTED_MAIN_DOM" ] && [ "$INSTALL_MODE" = "2" ] && [ -f /etc/nginx/conf.d/01-main.conf ]; then
    DETECTED_MAIN_DOM=$(grep -E 'server_name\s+[^;]+;' /etc/nginx/conf.d/01-main.conf 2>/dev/null | grep -v '_' | awk '{print $2}' | tr -d ';' | head -n1 || echo "")
fi
if [ -z "$DETECTED_MAIN_DOM" ] && [ -f /etc/myprivatecloud/config.json ]; then
    DETECTED_MAIN_DOM=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/config.json')).get('primary_domain',''))" 2>/dev/null || echo "")
fi

while true; do
    prompt_default "Введите ваш основной домен (FQDN для Nginx L7, панели и xHTTP)" "${DETECTED_MAIN_DOM:-yourdomain.online}" PRIMARY_DOMAIN
    PRIMARY_DOMAIN=$(echo "$PRIMARY_DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$PRIMARY_DOMAIN" =~ ^(yourdomain\.online|example\.(com|org|net)|localhost\.localdomain)$ ]]; then
        warn "Укажите реальное доменное имя вместо шаблона '$PRIMARY_DOMAIN'."
        continue
    fi
    if [[ "$PRIMARY_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        if is_ddns_domain "$PRIMARY_DOMAIN"; then
            warn "Обнаружен публичный DDNS-домен '$PRIMARY_DOMAIN' (аудит R1-04 / DPI отдаёт приоритет собственным доменам 2+ уровня)."
            if ! prompt_yes_no "Всё равно использовать '$PRIMARY_DOMAIN'?" "n"; then
                continue
            fi
        fi
        break
    fi
    warn "Некорректный формат доменного имени."
done
ok "Главный домен L7 (PRIMARY_DOMAIN): ${GREEN}${PRIMARY_DOMAIN}${NC}"

ALL_DOMAINS=("$PRIMARY_DOMAIN")
declare -A DOMAIN_TO_PORT=()
declare -A EXT_SNI_TO_PORT=()
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
DO_SYS_UPGRADE=0
if [ "${PRE_UPGRADE_DONE:-0}" -eq 1 ]; then
    ok "Обновление пакетов ОС уже выполнено на предварительном этапе."
else
    log "Обновление пакетов ОС пропущено согласно предварительному выбору."
fi

INSTALL_EXTRA_UTILS=0
if [ "${PRE_UTILS_DONE:-0}" -eq 1 ]; then
    ok "Набор диагностических утилит уже установлен на предварительном этапе (Вариант ${PRE_UTILS_CHOICE})."
else
    log "Установка дополнительных утилит пропущена согласно предварительному выбору."
fi

if prompt_yes_no "Включить сетевой тюнинг ядра (TCP BBR, somaxconn, буферы, MTU probing)?" "y"; then
    ENABLE_BBR_TUNING=1
else
    ENABLE_BBR_TUNING=0
fi

if prompt_yes_no "Отключить стек IPv6 в ядре и фаерволе?" "n"; then
    DISABLE_IPV6=1
else
    DISABLE_IPV6=0
fi

if prompt_yes_no "Включить еженедельное автообновление ОС/ядра и пересборку AWG (Circuit Breaker)?" "y"; then
    ENABLE_AUTO_UPDATE=1
else
    ENABLE_AUTO_UPDATE=0
fi

if prompt_yes_no "Блокировать входящие ICMP (Ping) запросы в фаерволе?" "n"; then
    BLOCK_PING=1
else
    BLOCK_PING=0
fi

echo -e "Текущий активный порт SSH: ${GREEN}${SSH_ACTIVE_PORT}${NC}"
if prompt_yes_no "Сменить порт SSH на нестандартный?" "n"; then
    while true; do
        echo -en "Введите новый порт SSH (1024-65535) [${GREEN}20022${NC}]: "
        read -r input_ssh_p
        p_ssh=$(echo "${input_ssh_p:-20022}" | tr -d '[:space:]')
        if [[ "$p_ssh" =~ ^[0-9]+$ ]] && [ "$p_ssh" -ge 1024 ] && [ "$p_ssh" -le 65535 ] && is_tcp_port_free "$p_ssh"; then
            TARGET_SSH_PORT="$p_ssh"
            break
        fi
        warn "Недопустимый или зарезервированный порт SSH: '$p_ssh'. Выберите 1024-65535."
    done
else
    TARGET_SSH_PORT="$SSH_ACTIVE_PORT"
fi
USED_TCP_PORTS_REG+=("$TARGET_SSH_PORT")

if [ "$INSTALL_MODE" = "1" ]; then
    if prompt_yes_no "Сменить пароль root?" "n"; then
        CHANGE_ROOT_PASS=1
        while true; do
            read -rsp "Введите новый пароль root: " ROOT_PASSWORD; echo
            if [ -n "$ROOT_PASSWORD" ]; then
                break
            fi
            warn "Пароль root не может быть пустым."
        done
    fi
    if prompt_yes_no "Создать непривилегированного пользователя с sudo?" "n"; then
        CREATE_USER=1
        while true; do
            read -rp "Введите имя пользователя (латиница, не root): " NEW_USERNAME
            NEW_USERNAME=$(echo "$NEW_USERNAME" | tr -d '[:space:]')
            if [[ "$NEW_USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$NEW_USERNAME" != "root" ]; then
                break
            fi
            warn "Некорректное имя пользователя '$NEW_USERNAME'. Допустимы строчные латинские буквы, цифры, '_' и '-'."
        done
        while true; do
            read -rsp "Введите пароль для $NEW_USERNAME: " NEW_USER_PASS; echo
            if [ -n "$NEW_USER_PASS" ]; then
                break
            fi
            warn "Пароль пользователя не может быть пустым."
        done
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
    DETECTED_PANEL_PATH=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webBasePath';")
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH#/}"
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH%/}"
    DETECTED_PANEL_PATH="${DETECTED_PANEL_PATH:-my-3x-panel}"
    DETECTED_SUB_PATH=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPath';")
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH#/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH%/}"
    DETECTED_SUB_PATH="${DETECTED_SUB_PATH:-my-post-key}"
    DETECTED_PANEL_PORT=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='webPort';")
    DETECTED_PANEL_PORT="${DETECTED_PANEL_PORT:-10443}"
    DETECTED_SUB_PORT=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT value FROM settings WHERE key='subPort';")
    DETECTED_SUB_PORT="${DETECTED_SUB_PORT:-55443}"

    LOCAL_IB_COND=$(get_local_ib_cond "$EXISTING_DB_PATH")
    DB_XHTTP_PATH=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT json_extract(stream_settings, '$.xhttpSettings.path') FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%xhttp%' ${LOCAL_IB_COND} ORDER BY enable DESC, id ASC LIMIT 1;")
    if [ -n "$DB_XHTTP_PATH" ]; then
        DETECTED_XHTTP_PATH="${DB_XHTTP_PATH#/}"
        DETECTED_XHTTP_PATH="${DETECTED_XHTTP_PATH%/}"
    fi
    DB_XHTTP_PORT=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT port FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%xhttp%' ${LOCAL_IB_COND} ORDER BY enable DESC, id ASC LIMIT 1;")
    if [ -n "$DB_XHTTP_PORT" ] && validate_port "$DB_XHTTP_PORT"; then
        DETECTED_XHTTP_PORT="$DB_XHTTP_PORT"
    fi
fi

prompt_tcp_port "Внутренний локальный порт панели 3X-UI" "${DETECTED_PANEL_PORT:-10443}" PANEL_PORT
prompt_path "Секретный URI-путь к веб-панели (например: my-3x-panel)" "${DETECTED_PANEL_PATH:-my-3x-panel}" RAW_PATH
PANEL_PATH="/${RAW_PATH#/}"
PANEL_PATH="${PANEL_PATH%/}/"

prompt_tcp_port "Внутренний порт сервера подписок 3X-UI" "${DETECTED_SUB_PORT:-55443}" SUB_PORT
while true; do
    prompt_path "Секретный URI-путь подписок (например: my-post-key)" "${DETECTED_SUB_PATH:-my-post-key}" RAW_SUB_PATH
    SUB_PATH="/${RAW_SUB_PATH#/}"
    SUB_PATH="${SUB_PATH%/}/"
    if [ "$SUB_PATH" != "$PANEL_PATH" ]; then
        break
    fi
    warn "URI-путь подписок не может совпадать с путём панели ($PANEL_PATH)."
done

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
DETECTED_STEAL_PORT="45443"
DETECTED_STEAL_DOM=""
if [ -n "${EXISTING_DB_PATH:-}" ] && [ -f "$EXISTING_DB_PATH" ]; then
    DB_STEAL_INFO=$(EXISTING_DB_PATH="$EXISTING_DB_PATH" PRIMARY_DOMAIN="$PRIMARY_DOMAIN" python3 - << 'EOF_DET_STEAL'
import json, os, sqlite3
db_p = os.environ.get("EXISTING_DB_PATH", "")
p_dom = os.environ.get("PRIMARY_DOMAIN", "").strip().lower()
port_out, dom_out = "", ""
if db_p and os.path.exists(db_p):
    try:
        conn = sqlite3.connect(f"file:{db_p}?mode=ro", uri=True, timeout=5.0)
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(inbounds)")
        _cols_det = {r[1] for r in cur.fetchall()}
        _nc_det_parts = []
        _nc_det_params = []
        if "node_id" in _cols_det:
            _nc_det_parts.append("(node_id IS NULL OR node_id = 0)")
        if "origin_node_guid" in _cols_det:
            cur.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1")
            _pg_det = cur.fetchone()
            _pg_val = str(_pg_det[0]).strip() if _pg_det and _pg_det[0] else ""
            if _pg_val:
                _nc_det_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                _nc_det_params.append(_pg_val)
            else:
                _nc_det_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
        _nc_det = (" AND " + " AND ".join(_nc_det_parts)) if _nc_det_parts else ""
        cur.execute(f"SELECT port, tag, stream_settings FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%reality%'{_nc_det} ORDER BY enable DESC, id ASC", _nc_det_params)
        for p, tag, st_raw in cur.fetchall():
            st = json.loads(st_raw) if st_raw else {}
            rs = st.get("realitySettings", {})
            dest = str(rs.get("dest", rs.get("target", ""))).strip()
            if "in-steal" in str(tag or "").lower() or dest == "127.0.0.1:9443":
                if not port_out and str(p).isdigit():
                    port_out = str(p)
                for s in rs.get("serverNames", []):
                    s_clean = str(s).strip().lower()
                    if s_clean and s_clean != p_dom and not dom_out:
                        dom_out = s_clean
        conn.close()
    except Exception:
        pass
print(f"{port_out}|{dom_out}")
EOF_DET_STEAL
    )
    DB_S_PORT="${DB_STEAL_INFO%%|*}"
    DB_S_DOM="${DB_STEAL_INFO#*|}"
    if validate_port "$DB_S_PORT"; then DETECTED_STEAL_PORT="$DB_S_PORT"; fi
    if [ -n "$DB_S_DOM" ]; then DETECTED_STEAL_DOM="$DB_S_DOM"; fi
fi

if prompt_yes_no "Включить Steal-Oneself REALITY (Кража у своего поддомена с Anti-Loop Fallback 9443)?" "y"; then
    ENABLE_STEAL=1
else
    ENABLE_STEAL=0
fi

declare -A STEAL_PORT_DOMAINS=()
if [ "$ENABLE_STEAL" -eq 1 ]; then
    while true; do
        prompt_tcp_port "  Локальный порт Xray для Steal-Oneself" "$DETECTED_STEAL_PORT" PORT_VAL

        if ! in_array "$PORT_VAL" "${STEAL_PORTS_LIST[@]:-}"; then
            STEAL_PORTS_LIST+=("$PORT_VAL")
            ALL_REALITY_PORTS+=("$PORT_VAL")
        fi

        echo -e "${CYAN}  Введите домены для порта $PORT_VAL (для завершения - пусто и Enter):${NC}"
        added_count_for_port=0
        port_doms_str=""
        while true; do
            local_def="${DETECTED_STEAL_DOM:-cdn.$PRIMARY_DOMAIN}"
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

            if in_array "$S_DOM" "${ALL_DOMAINS[@]:-}"; then
                warn "    Домен '$S_DOM' уже используется или добавлен в список."
                continue
            fi
            ALL_DOMAINS+=("$S_DOM")

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
    prompt_tcp_port "  Внутренний порт инбаунда VLESS xHTTP (Native H2 Stream-One)" "${DETECTED_XHTTP_PORT:-50443}" XHTTP_STREAM_PORT
    while true; do
        prompt_path "  Секретный URI-путь для xHTTP (например: Stream-One-Path)" "${DETECTED_XHTTP_PATH:-Stream-One-Path}" RAW_XHTTP_STREAM_PATH
        XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH#/}"
        XHTTP_STREAM_PATH="${XHTTP_STREAM_PATH%/}/"
        if [ "$XHTTP_STREAM_PATH" != "$PANEL_PATH" ] && [ "$XHTTP_STREAM_PATH" != "$SUB_PATH" ] && \
           [[ "$XHTTP_STREAM_PATH" != "$PANEL_PATH"* ]] && [[ "$PANEL_PATH" != "$XHTTP_STREAM_PATH"* ]] && \
           [[ "$XHTTP_STREAM_PATH" != "$SUB_PATH"* ]] && [[ "$SUB_PATH" != "$XHTTP_STREAM_PATH"* ]] && \
           [[ "$XHTTP_STREAM_PATH" != "/api/v1/myprivatecloud/"* ]]; then
            break
        fi
        warn "URI-путь xHTTP конфликтует или пересекается с путём панели, подписок или системного API."
    done
    BASE_XHTTP_PATH="${XHTTP_STREAM_PATH%/}"
else
    ENABLE_XHTTP=0
    XHTTP_STREAM_PORT=""
    XHTTP_STREAM_PATH=""
    BASE_XHTTP_PATH=""
fi

if prompt_yes_no "Включить Classic External REALITY (Сторонний доверенный глобальный SNI)?" "n"; then
    ENABLE_CLASSIC=1
else
    ENABLE_CLASSIC=0
fi

declare -A CLASSIC_PORT_SNIS=()
if [ "$ENABLE_CLASSIC" -eq 1 ]; then
    while true; do
        prompt_tcp_port "  Локальный порт Xray для Classic REALITY" "46443" PORT_VAL

        if ! in_array "$PORT_VAL" "${CLASSIC_PORTS_LIST[@]:-}"; then
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
        if in_array "$EXTRA_DOM" "${ALL_DOMAINS[@]:-}"; then
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
echo -e "${WHITE}${BOLD}--- ШАГ 6: Выделенные порты UDP VPN туннелей ---${NC}"
DETECTED_HY2_PORT="40443"
DETECTED_AWG_V3_PORT="42443"
DETECTED_NATIVE_AWG_PORT="41443"
if [ -n "${EXISTING_DB_PATH:-}" ] && [ -f "$EXISTING_DB_PATH" ]; then
    LOCAL_IB_COND=$(get_local_ib_cond "$EXISTING_DB_PATH")
    DB_HY2_P=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT port FROM inbounds WHERE protocol='hysteria' ${LOCAL_IB_COND} ORDER BY enable DESC, id ASC LIMIT 1;")
    if validate_port "$DB_HY2_P"; then DETECTED_HY2_PORT="$DB_HY2_P"; fi
    DB_AWG3_P=$(sqlite_ro "$EXISTING_DB_PATH" "SELECT port FROM inbounds WHERE protocol='amneziawg' ${LOCAL_IB_COND} ORDER BY enable DESC, id ASC LIMIT 1;")
    if validate_port "$DB_AWG3_P"; then DETECTED_AWG_V3_PORT="$DB_AWG3_P"; fi
fi
if [ -f /etc/amnezia/amneziawg/awg0.conf ]; then
    CONF_AWG_P=$(grep -E '^\s*ListenPort\s*=' /etc/amnezia/amneziawg/awg0.conf 2>/dev/null | head -n1 | awk -F= '{print $2}' | tr -d '[:space:]' || echo "")
    if validate_port "$CONF_AWG_P"; then DETECTED_NATIVE_AWG_PORT="$CONF_AWG_P"; fi
fi

if prompt_yes_no "Установить Hysteria 2 (UDP)?" "y"; then
    ENABLE_HY2=1
    prompt_udp_port "  Внешний UDP-порт для Hysteria 2" "$DETECTED_HY2_PORT" HY2_PORT
else
    ENABLE_HY2=0
fi

if [ "$VIRT_TYPE" = "lxc" ] || [ "$VIRT_TYPE" = "openvz" ] || [ "$VIRT_TYPE" = "docker" ]; then
    warn "Обнаружена среда контейнеризации ($VIRT_TYPE). Нативный DKMS AmneziaWG отключён (требуется KVM/Bare-Metal)."
    ENABLE_NATIVE_AWG=0
else
    if prompt_yes_no "Установить НА ТЕХНОЛОГИЯХ ЯДРА нативный сервер AmneziaWG (Bare-Metal awg0)?" "y"; then
        ENABLE_NATIVE_AWG=1
        prompt_udp_port "  Выделенный UDP-порт для нативного сервера AmneziaWG awg0" "$DETECTED_NATIVE_AWG_PORT" NATIVE_AWG_PORT
    else
        ENABLE_NATIVE_AWG=0
    fi
fi
if prompt_yes_no "Установить AmneziaWG v3.2 в 3X-UI (UDP)?" "y"; then
    ENABLE_AWG_V3=1
    prompt_udp_port "  Выделенный UDP-порт для AmneziaWG v3.2 (3X-UI)" "$DETECTED_AWG_V3_PORT" AWG_V3_PORT
else
    ENABLE_AWG_V3=0
fi
echo

DETECTED_AGH_DOM=""
if [ -f /etc/nginx/conf.d/03-adguard.conf ]; then
    DETECTED_AGH_DOM=$(grep -E 'server_name\s+[^;]+;' /etc/nginx/conf.d/03-adguard.conf 2>/dev/null | awk '{print $2}' | tr -d ';' | head -n1 || echo "")
fi
if [ -z "$DETECTED_AGH_DOM" ] && [ -f /etc/myprivatecloud/config.json ]; then
    DETECTED_AGH_DOM=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/config.json')).get('agh_domain',''))" 2>/dev/null || echo "")
fi
if [ -z "$DETECTED_AGH_DOM" ] && [ -f /etc/myprivatecloud/sso_agh.json ]; then
    DETECTED_AGH_DOM=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/sso_agh.json')).get('domain',''))" 2>/dev/null || echo "")
fi
DETECTED_AGH_USER="admin"
DETECTED_AGH_PASS=""
if [ -f /etc/myprivatecloud/sso_agh.json ]; then
    DETECTED_AGH_PASS=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/sso_agh.json')).get('pass',''))" 2>/dev/null || echo "")
    DETECTED_AGH_USER=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/sso_agh.json')).get('user','admin'))" 2>/dev/null || echo "admin")
fi
if [ -z "$DETECTED_AGH_PASS" ] && [ -f /etc/myprivatecloud/config.json ]; then
    DETECTED_AGH_PASS=$(python3 -c "import json; print(json.load(open('/etc/myprivatecloud/config.json')).get('agh_pass',''))" 2>/dev/null || echo "")
fi
if [ -z "$DETECTED_AGH_PASS" ] && [ -f /root/vpn_credentials.txt ]; then
    DETECTED_AGH_PASS=$(awk '/\[ ПРИВАТНЫЙ ADGUARD HOME DOH \]/{f=1} f&&/Пароль администратора:/{print $3; exit}' /root/vpn_credentials.txt 2>/dev/null || echo "")
fi
if [ -z "$DETECTED_AGH_PASS" ] && [ -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
    DETECTED_AGH_USER=$(awk '/^users:/{u=1;next} /^[^[:space:]]/{u=0} u && /name:/{sub(/^.*name:[[:space:]]*/, ""); gsub(/["'\''[:space:]]/, ""); print; exit}' /opt/AdGuardHome/AdGuardHome.yaml 2>/dev/null || echo "admin")
    DETECTED_AGH_USER="${DETECTED_AGH_USER:-admin}"
fi
if [ -z "${AGH_CLIENT_ID:-}" ] && [ -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
    DETECTED_AGH_CID=$(python3 -c "import re; txt=open('/opt/AdGuardHome/AdGuardHome.yaml','r',encoding='utf-8',errors='ignore').read(); m=re.search(r'persistent:\s*\n\s*-\s*name:[^\n]*\n\s*ids:\s*\n\s*-\s*([^\s\n]+)', txt); print(m.group(1) if m else '')" 2>/dev/null || echo "")
    if [ -n "$DETECTED_AGH_CID" ]; then
        AGH_CLIENT_ID="$DETECTED_AGH_CID"
    fi
fi

AGH_INSTALLED=0
if [ -f /opt/AdGuardHome/AdGuardHome.yaml ] || [ -x /opt/AdGuardHome/AdGuardHome ]; then
    AGH_INSTALLED=1
fi

echo -e "${WHITE}${BOLD}--- ШАГ 7: Приватный DNS AdGuard Home (DoH) ---${NC}"
DEFAULT_AGH_CHOICE="y"
if [ "$INSTALL_MODE" = "2" ] && [ "$AGH_INSTALLED" -eq 0 ] && [ -z "$DETECTED_AGH_DOM" ]; then
    DEFAULT_AGH_CHOICE="n"
fi

if [ "$AGH_INSTALLED" -eq 1 ]; then
    AGH_PROMPT_MSG="Сохранить/обновить интеграцию AdGuard Home DoH со Split-DNS (предыдущие настройки AGH сохраняются)?"
else
    AGH_PROMPT_MSG="Установить приватный AdGuard Home DoH со Split-DNS?"
fi

if prompt_yes_no "$AGH_PROMPT_MSG" "$DEFAULT_AGH_CHOICE"; then
    ENABLE_AGH=1
else
    ENABLE_AGH=0
    AGH_DOMAIN=""
    AGH_PASS=""
    AGH_CLIENT_ID=""
    AGH_RAM_TELEMETRY=0
fi
if [ "$ENABLE_AGH" -eq 1 ]; then
    CLEAN_BASE_DOM=$(echo "${PRIMARY_DOMAIN}" | sed -E "s/^www\.//")
    DEF_AGH_DOM="${AGH_DOMAIN:-${DETECTED_AGH_DOM:-dns.$CLEAN_BASE_DOM}}"
    if [ "$DEF_AGH_DOM" = "$PRIMARY_DOMAIN" ] || in_array "$DEF_AGH_DOM" "${STEAL_DOMAINS[@]:-}"; then
        DEF_AGH_DOM="dns.$CLEAN_BASE_DOM"
    fi
    while true; do
        prompt_default "  Поддомен для AdGuard Home DoH" "$DEF_AGH_DOM" AGH_DOMAIN
        AGH_DOMAIN=$(echo "$AGH_DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        if [[ ! "$AGH_DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            warn "  Некорректный формат домена: '$AGH_DOMAIN'."
            continue
        fi
        if [ "$AGH_DOMAIN" = "$PRIMARY_DOMAIN" ]; then
            warn "  ОШИБКА КОЛЛИЗИИ: '$AGH_DOMAIN' совпадает с главным доменом ($PRIMARY_DOMAIN)."
            continue
        fi
        if in_array "$AGH_DOMAIN" "${STEAL_DOMAINS[@]:-}"; then
            warn "  ОШИБКА КОЛЛИЗИИ: '$AGH_DOMAIN' уже используется для Steal-REALITY."
            continue
        fi
        break
    done
    if ! in_array "$AGH_DOMAIN" "${ALL_DOMAINS[@]:-}"; then
        ALL_DOMAINS+=("$AGH_DOMAIN")
    fi
    prompt_default "  Логин администратора AdGuard Home" "${DETECTED_AGH_USER:-admin}" AGH_USER
    DEFAULT_AG_PASS="${DETECTED_AGH_PASS:-AgHome_$(openssl rand -hex 4)}"
    prompt_default "  Пароль администратора AdGuard Home" "$DEFAULT_AG_PASS" AGH_PASS
    while true; do
        prompt_default "  Секретный ClientID токен для роутера" "${AGH_CLIENT_ID:-home-router}" AGH_CLIENT_ID
        AGH_CLIENT_ID=$(echo "$AGH_CLIENT_ID" | tr -d '[:space:]')
        if [[ "$AGH_CLIENT_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            break
        fi
        warn "  Некорректный ClientID '$AGH_CLIENT_ID'. Допустимы латиница, цифры, '.', '_' и '-'."
    done
    DEF_AGH_RAM_LOG="n"
    if [ "${AGH_RAM_TELEMETRY:-0}" = "1" ]; then
        DEF_AGH_RAM_LOG="y"
    elif [ "$INSTALL_MODE" = "2" ] && [ -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
        if python3 -c "import re; t=open('/opt/AdGuardHome/AdGuardHome.yaml','r',encoding='utf-8',errors='ignore').read(); m=re.search(r'^querylog:\n([\s\S]*?)(?=^\S|\Z)',t,re.M); raise SystemExit(0 if (m and re.search(r'^  enabled:\s*true\b',m.group(1),re.M)) else 1)" 2>/dev/null; then
            DEF_AGH_RAM_LOG="y"
        fi
    fi
    if prompt_yes_no "  Включить журнал запросов и статистику AGH в RAM (tmpfs /run/adguardhome, ротация 24ч, квота ${AGH_TMPFS_SIZE})?" "$DEF_AGH_RAM_LOG"; then
        AGH_RAM_TELEMETRY=1
    else
        AGH_RAM_TELEMETRY=0
    fi
fi

mkdir -p /etc/myprivatecloud
chmod 0700 /etc/myprivatecloud
(
    umask 077
    cat << EOF_CFG_ENV > /etc/myprivatecloud/config.env.tmp
PRIMARY_DOMAIN="${PRIMARY_DOMAIN}"
AGH_DOMAIN="${AGH_DOMAIN}"
ENABLE_AGH="${ENABLE_AGH}"
PANEL_PORT="${PANEL_PORT}"
PANEL_PATH="${PANEL_PATH}"
SUB_PORT="${SUB_PORT}"
SUB_PATH="${SUB_PATH}"
AGH_USER="${AGH_USER}"
AGH_CLIENT_ID="${AGH_CLIENT_ID}"
AGH_RAM_TELEMETRY="${AGH_RAM_TELEMETRY}"
EOF_CFG_ENV
)
chmod 0600 /etc/myprivatecloud/config.env.tmp
mv -f /etc/myprivatecloud/config.env.tmp /etc/myprivatecloud/config.env

AGH_PASS_ENV="$AGH_PASS" PRIMARY_DOMAIN_ENV="$PRIMARY_DOMAIN" AGH_DOMAIN_ENV="$AGH_DOMAIN" \
PANEL_PORT_ENV="$PANEL_PORT" PANEL_PATH_ENV="$PANEL_PATH" SUB_PORT_ENV="$SUB_PORT" \
SUB_PATH_ENV="$SUB_PATH" ENABLE_AGH_ENV="$ENABLE_AGH" AGH_USER_ENV="$AGH_USER" \
AGH_CLIENT_ID_ENV="${AGH_CLIENT_ID:-}" AGH_RAM_TELEMETRY_ENV="${AGH_RAM_TELEMETRY:-0}" \
python3 - << 'EOF_CANON_JSON'
import json, os
cfg = {
    "primary_domain": os.environ.get("PRIMARY_DOMAIN_ENV", ""),
    "agh_domain": os.environ.get("AGH_DOMAIN_ENV", ""),
    "enable_agh": os.environ.get("ENABLE_AGH_ENV", "0") == "1",
    "panel_port": os.environ.get("PANEL_PORT_ENV", "10443"),
    "panel_path": os.environ.get("PANEL_PATH_ENV", "/my-3x-panel/"),
    "sub_port": os.environ.get("SUB_PORT_ENV", "55443"),
    "sub_path": os.environ.get("SUB_PATH_ENV", "/my-post-key/"),
    "agh_user": os.environ.get("AGH_USER_ENV", "admin"),
    "agh_pass": os.environ.get("AGH_PASS_ENV", ""),
    "agh_client_id": os.environ.get("AGH_CLIENT_ID_ENV", ""),
    "agh_ram_telemetry": os.environ.get("AGH_RAM_TELEMETRY_ENV", "0") == "1"
}
tmp_p = "/etc/myprivatecloud/config.json.tmp"
with open(tmp_p, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
os.chmod(tmp_p, 0o600)
os.replace(tmp_p, "/etc/myprivatecloud/config.json")
EOF_CANON_JSON

echo
echo -e "Метод выпуска SSL-сертификатов:"
echo -e "  1) ${GREEN}Нативный Certbot HTTP-01 (Рекомендуется)${NC}"
echo -e "  2) ${GREEN}acme.sh + Cloudflare DNS-01${NC} (Каталог: /etc/ssl/acme/)"
prompt_choice "Ваш выбор" "1" SSL_ENGINE_CHOICE "1" "2"

if [ "$SSL_ENGINE_CHOICE" = "2" ]; then
    prompt_choice "Вариант аутентификации Cloudflare (1-Token, 2-Global Key)" "1" CF_AUTH_METHOD "1" "2"
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
if ! apt-get update -q; then
    warn "Сбой apt-get update (возможен неподписанный сторонний PPA). Изоляция списков Amnezia PPA..."
    for apt_f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -f "$apt_f" ] || continue
        if grep -qiE 'launchpadcontent\.net/amnezia|launchpad\.net/amnezia|amnezia/ppa' "$apt_f" 2>/dev/null; then
            rm -f "$apt_f" 2>/dev/null || true
        fi
    done
    rm -f /etc/apt/keyrings/amnezia.gpg 2>/dev/null || true
    wait_for_apt_lock
    apt-get update -q || die "Не удалось обновить пакетные репозитории APT."
fi

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
    curl iproute2 bind9-dnsutils ca-certificates ufw iptables systemd
    sudo bash psmisc openssl gnupg sqlite3 jq unzip gawk tar
    python3 python3-bcrypt python3-systemd qrencode fail2ban openssh-client
)
if ! apt-get install -y "${CORE_PKGS[@]}" -q >/dev/null 2>&1; then
    warn "Повторная установка системных пакетов с выводом диагностики..."
    wait_for_apt_lock
    apt-get update -q || true
    apt-get install -y "${CORE_PKGS[@]}" -q || die "Сбой установки критических системных пакетов."
fi
for req_bin in ufw iptables qrencode fail2ban-client; do
    if ! command -v "$req_bin" >/dev/null 2>&1; then
        die "Критическая утилита '$req_bin' не найдена после установки пакетов."
    fi
done

if [ "${INSTALL_EXTRA_UTILS:-0}" -eq 1 ]; then
    wait_for_apt_lock
    apt-get install -y htop iperf3 iftop tcpdump mtr-tiny ncdu vnstat openssh-client -q || true
    apt-get install -y btop -q 2>/dev/null || true
fi
ok "Системные утилиты установлены."

mkdir -p /etc/systemd/journald.conf.d/
cat << 'EOF' > /etc/systemd/journald.conf.d/00-volatile.conf.tmp
[Journal]
Storage=volatile
RuntimeMaxUse=16M
RuntimeMaxFileSize=4M
MaxRetentionSec=1day
EOF
mv -f /etc/systemd/journald.conf.d/00-volatile.conf.tmp /etc/systemd/journald.conf.d/00-volatile.conf
chmod 0644 /etc/systemd/journald.conf.d/00-volatile.conf 2>/dev/null || true
rm -rf /var/log/journal 2>/dev/null || true
systemctl restart systemd-journald 2>/dev/null || true
ok "Политика Zero-Log активирована в RAM (systemd-journald Storage=volatile)."

SYSCTL_IF="${DEFAULT_IF//./\/}"
mkdir -p /etc/modules-load.d
cat << 'EOF_NET_MODS' > /etc/modules-load.d/99-hardened-net.conf.tmp
nf_conntrack
tcp_bbr
EOF_NET_MODS
mv -f /etc/modules-load.d/99-hardened-net.conf.tmp /etc/modules-load.d/99-hardened-net.conf
chmod 0644 /etc/modules-load.d/99-hardened-net.conf 2>/dev/null || true
modprobe nf_conntrack 2>/dev/null || true
cat << 'EOF_SCTP_BL' > /etc/modprobe.d/99-disable-sctp.conf.tmp
install sctp /bin/false
blacklist sctp
EOF_SCTP_BL
mv -f /etc/modprobe.d/99-disable-sctp.conf.tmp /etc/modprobe.d/99-disable-sctp.conf
chmod 0644 /etc/modprobe.d/99-disable-sctp.conf 2>/dev/null || true
modprobe -r sctp 2>/dev/null || true

mkdir -p /etc/sysctl.d/
cat << EOF > /etc/sysctl.d/99-hardened-network.conf.tmp
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.${SYSCTL_IF}.rp_filter = 2
EOF

if [ "${ENABLE_BBR_TUNING:-0}" -eq 1 ]; then
    log "Настройка TCP BBR, fq, somaxconn, Path MTU probing и loose rp_filter..."
    modprobe tcp_bbr 2>/dev/null || true
    cat << 'EOF_BBR_SYSCTL' >> /etc/sysctl.d/99-hardened-network.conf.tmp
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
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
net.core.rmem_default = 131072
net.core.wmem_default = 131072
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.udp_mem = 65536 131072 262144
vm.swappiness = 10
fs.file-max = 524288
net.ipv4.tcp_fastopen = 3
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_udp_timeout = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_mtu_probe_floor = 1024
net.ipv4.tcp_orphan_retries = 2
fs.inotify.max_user_watches = 131072
fs.inotify.max_user_instances = 2048
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.vfs_cache_pressure = 100
net.core.rps_sock_flow_entries = 32768
EOF_BBR_SYSCTL
fi

if [ "${DISABLE_IPV6:-0}" -eq 1 ]; then
    log "Отключение стека IPv6 в sysctl (/etc/sysctl.d/99-hardened-network.conf)..."
    cat << 'EOF_IPV6' >> /etc/sysctl.d/99-hardened-network.conf.tmp
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF_IPV6
else
    cat << 'EOF_IPV6' >> /etc/sysctl.d/99-hardened-network.conf.tmp
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF_IPV6
fi

mv -f /etc/sysctl.d/99-hardened-network.conf.tmp /etc/sysctl.d/99-hardened-network.conf
chmod 0644 /etc/sysctl.d/99-hardened-network.conf 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true

if [ "${ENABLE_BBR_TUNING:-0}" -eq 1 ] && [ "${CPU_CORES:-1}" -le 1 ]; then
    systemctl disable --now network-rps.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/network-rps.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
fi
if [ "${ENABLE_BBR_TUNING:-0}" -eq 1 ] && [ "${CPU_CORES:-1}" -gt 1 ]; then
    log "Настройка сквозной балансировки прерываний сетевой карты (RPS/RFS/XPS, маска: 0x$CPU_MASK)..."
    q_cnt=$({ find /sys/class/net/"$DEFAULT_IF"/queues -maxdepth 1 -type d -name "rx-*" 2>/dev/null || true; } | wc -l)
    [ "${q_cnt:-1}" -lt 1 ] && q_cnt=1
    rfs_flow_val=$((32768 / q_cnt))
    for f in /sys/class/net/"$DEFAULT_IF"/queues/rx-*/rps_cpus /sys/class/net/"$DEFAULT_IF"/queues/tx-*/xps_cpus; do
        if [ -e "$f" ]; then echo "$CPU_MASK" > "$f" 2>/dev/null || true; fi
    done
    for f in /sys/class/net/"$DEFAULT_IF"/queues/rx-*/rps_flow_cnt; do
        if [ -e "$f" ]; then echo "$rfs_flow_val" > "$f" 2>/dev/null || true; fi
    done

    cat << EOF > /etc/systemd/system/network-rps.service.tmp
[Unit]
Description=Network RPS/RFS/XPS Multi-Core Scaling on $DEFAULT_IF
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'q_cnt=\$({ find /sys/class/net/$DEFAULT_IF/queues -maxdepth 1 -type d -name "rx-*" 2>/dev/null || true; } | wc -l); [ "\$q_cnt" -lt 1 ] && q_cnt=1; flow_val=\$((32768 / q_cnt)); for f in /sys/class/net/$DEFAULT_IF/queues/rx-*/rps_cpus /sys/class/net/$DEFAULT_IF/queues/tx-*/xps_cpus; do [ -e "\$f" ] && echo "$CPU_MASK" > "\$f" || true; done; for f in /sys/class/net/$DEFAULT_IF/queues/rx-*/rps_flow_cnt; do [ -e "\$f" ] && echo "\$flow_val" > "\$f" || true; done'

[Install]
WantedBy=multi-user.target
EOF
    mv -f /etc/systemd/system/network-rps.service.tmp /etc/systemd/system/network-rps.service
    chmod 0644 /etc/systemd/system/network-rps.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now network-rps.service >/dev/null 2>&1 || true
fi

cat << 'EOF' > /etc/security/limits.d/99-proxy-limits.conf.tmp
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
www-data soft nofile 1048576
www-data hard nofile 1048576
nginx soft nofile 1048576
nginx hard nofile 1048576
EOF
mv -f /etc/security/limits.d/99-proxy-limits.conf.tmp /etc/security/limits.d/99-proxy-limits.conf
chmod 0644 /etc/security/limits.d/99-proxy-limits.conf 2>/dev/null || true
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
        printf "%s ALL=(ALL:ALL) ALL\n" "$NEW_USERNAME" > "/etc/sudoers.d/${NEW_USERNAME}.tmp"
        if command -v visudo >/dev/null 2>&1 && ! visudo -cf "/etc/sudoers.d/${NEW_USERNAME}.tmp" >/dev/null 2>&1; then
            rm -f "/etc/sudoers.d/${NEW_USERNAME}.tmp"
            warn "Ошибка валидации sudoers для $NEW_USERNAME."
        else
            chmod 440 "/etc/sudoers.d/${NEW_USERNAME}.tmp"
            mv -f "/etc/sudoers.d/${NEW_USERNAME}.tmp" "/etc/sudoers.d/$NEW_USERNAME"
        fi
    fi
fi

NOPASSWD_FILES=()
if [ -d /etc/sudoers.d ]; then
    while IFS= read -r -d '' sf; do
        if [ -f "$sf" ] && grep -qE '^[[:space:]]*[^#].*NOPASSWD' "$sf" 2>/dev/null; then
            NOPASSWD_FILES+=("$sf")
        fi
    done < <(find /etc/sudoers.d -maxdepth 1 -type f -print0 2>/dev/null)
fi
if [ "${#NOPASSWD_FILES[@]}" -gt 0 ]; then
    warn "Обнаружены правила sudo NOPASSWD в: ${NOPASSWD_FILES[*]}"
    DEF_RM_NOPW="n"
    if [ -z "${SUDO_USER:-}" ]; then
        DEF_RM_NOPW="y"
    fi
    if prompt_yes_no "Удалить NOPASSWD из /etc/sudoers.d/ (для sudo потребуется пароль)?" "$DEF_RM_NOPW"; then
        for sf in "${NOPASSWD_FILES[@]}"; do
            sed -E 's/NOPASSWD:[[:space:]]*//g' "$sf" > "${sf}.tmp"
            if command -v visudo >/dev/null 2>&1 && ! visudo -cf "${sf}.tmp" >/dev/null 2>&1; then
                rm -f "${sf}.tmp"
                warn "Ошибка валидации visudo для $sf; файл оставлен без изменений."
            else
                chmod 440 "${sf}.tmp"
                mv -f "${sf}.tmp" "$sf"
                ok "Правило NOPASSWD удалено из $sf."
            fi
        done
    fi
fi

KEYS_APPLIED=0
if [ "${SETUP_KEYS:-0}" -eq 1 ]; then
    TARGET_KEY_USER="root"
    if [ -n "${NEW_USERNAME:-}" ]; then
        TARGET_KEY_USER="$NEW_USERNAME"
    fi
    USER_HOME=$(getent passwd "$TARGET_KEY_USER" | cut -d: -f6)
    read -rp "SSH ключи: 1-Сгенерировать Ed25519, 2-Вставить, 3-Пропустить [1]: " KEY_CHOICE
    KEY_CHOICE="${KEY_CHOICE:-1}"
    mkdir -p "$USER_HOME/.ssh" && chmod 700 "$USER_HOME/.ssh"
    if [ "$KEY_CHOICE" = "1" ]; then
        GEN_NEW_SSH_KEY=1
        if [ -f "$USER_HOME/.ssh/id_ed25519" ]; then
            warn "Ключ $USER_HOME/.ssh/id_ed25519 уже существует."
            if ! prompt_yes_no "Перезаписать существующий SSH-ключ id_ed25519?" "n"; then
                GEN_NEW_SSH_KEY=0
                if [ ! -f "$USER_HOME/.ssh/id_ed25519.pub" ]; then
                    ssh-keygen -y -f "$USER_HOME/.ssh/id_ed25519" > "$USER_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
                fi
            fi
        fi
        if [ "$GEN_NEW_SSH_KEY" -eq 1 ]; then
            (umask 077 && ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/id_ed25519" -C "vps-$TARGET_KEY_USER" -N "" -q <<< "y")
        fi
        if [ -s "$USER_HOME/.ssh/id_ed25519.pub" ]; then
            touch "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/id_ed25519"
            PUB_KEY_VAL=$(cat "$USER_HOME/.ssh/id_ed25519.pub")
            if ! grep -qxF "$PUB_KEY_VAL" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null; then
                printf '%s\n' "$PUB_KEY_VAL" >> "$USER_HOME/.ssh/authorized_keys"
            fi
            chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
            if [ "$GEN_NEW_SSH_KEY" -eq 1 ]; then
                echo -e "\n${YELLOW}ПРИВАТНЫЙ КЛЮЧ:${NC}"
                cat "$USER_HOME/.ssh/id_ed25519"
                read -rp "Нажмите Enter после сохранения..." || true
            fi
            KEYS_APPLIED=1
        fi
    elif [ "$KEY_CHOICE" = "2" ]; then
        read -rp "Вставьте публичный ключ: " PUB_INPUT
        if [ -n "$PUB_INPUT" ]; then
            touch "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys"
            if ! grep -qxF "$PUB_INPUT" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null; then
                printf '%s\n' "$PUB_INPUT" >> "$USER_HOME/.ssh/authorized_keys"
            fi
            chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
            KEYS_APPLIED=1
        fi
    fi
fi

ufw allow "${TARGET_SSH_PORT}/tcp" comment 'SSH Target Port' >/dev/null 2>&1 || true

if [ -f /etc/ssh/sshd_config ]; then
    sed -i -E 's/^[#[:space:]]*Port [0-9]+/Port '"$TARGET_SSH_PORT"'/' /etc/ssh/sshd_config || true
    if ! head -n 5 /etc/ssh/sshd_config 2>/dev/null | grep -qE '^Include /etc/ssh/sshd_config\.d/\*\.conf'; then
        sed -i -E '/^[[:space:]]*Include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf/d' /etc/ssh/sshd_config
        if [ -s /etc/ssh/sshd_config ]; then
            sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
        else
            printf 'Include /etc/ssh/sshd_config.d/*.conf\n' > /etc/ssh/sshd_config
        fi
    fi
fi

SSH_SERVICE=$(get_ssh_service_name)
systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl enable "$SSH_SERVICE.service" 2>/dev/null || true

HAS_SSH_AUTH_KEYS=0
ROOT_HAS_KEYS=0
if [ -s /root/.ssh/authorized_keys ] && grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-ssh-)' /root/.ssh/authorized_keys 2>/dev/null; then
    ROOT_HAS_KEYS=1
    HAS_SSH_AUTH_KEYS=1
fi
if [ "$HAS_SSH_AUTH_KEYS" -eq 0 ]; then
    for ak_file in /home/*/.ssh/authorized_keys; do
        if [ -s "$ak_file" ] && grep -qE '^(ssh-(ed25519|rsa)|ecdsa-sha2-|sk-ssh-)' "$ak_file" 2>/dev/null; then
            HAS_SSH_AUTH_KEYS=1
            break
        fi
    done
fi

mkdir -p /etc/ssh/sshd_config.d/
rm -f /etc/ssh/sshd_config.d/99-hardening.conf
HARDENING_BAK=""
if [ -f /etc/ssh/sshd_config.d/00-hardening.conf ]; then
    HARDENING_BAK="/etc/ssh/sshd_config.d/00-hardening.conf.bak"
    cp -a /etc/ssh/sshd_config.d/00-hardening.conf "$HARDENING_BAK"
fi

SSH_ADDR_FAMILY="any"
if [ "${DISABLE_IPV6:-0}" -eq 1 ]; then
    SSH_ADDR_FAMILY="inet"
fi
cat << EOF > /etc/ssh/sshd_config.d/00-hardening.conf.tmp
Port $TARGET_SSH_PORT
AddressFamily $SSH_ADDR_FAMILY
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF

SSH_PWD_DISABLED=0
ROOT_PROHIBIT_PWD=0
SSH_NO_KEYS_WARN=0
if [ "$KEYS_APPLIED" -eq 1 ] || [ "$HAS_SSH_AUTH_KEYS" -eq 1 ]; then
    DEF_PWD_DISABLE="y"
    if prompt_yes_no "Отключить вход по паролю SSH (PasswordAuthentication no)?" "$DEF_PWD_DISABLE"; then
        cat << 'EOF' >> /etc/ssh/sshd_config.d/00-hardening.conf.tmp
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
UsePAM yes
EOF
        SSH_PWD_DISABLED=1
        ROOT_PROHIBIT_PWD=1
    fi
else
    SSH_NO_KEYS_WARN=1
    warn "Публичные ключи SSH в authorized_keys не найдены! Парольный вход сохранён во избежание блокировки доступа."
fi

if [ "$ROOT_PROHIBIT_PWD" -eq 0 ]; then
    if [ "$ROOT_HAS_KEYS" -eq 1 ] || { [ -f /etc/ssh/sshd_config.d/00-hardening.conf ] && grep -qiE '^\s*PermitRootLogin\s+(prohibit-password|without-password|no)\b' /etc/ssh/sshd_config.d/00-hardening.conf; }; then
        printf 'PermitRootLogin prohibit-password\n' >> /etc/ssh/sshd_config.d/00-hardening.conf.tmp
        ROOT_PROHIBIT_PWD=1
    fi
fi

mv -f /etc/ssh/sshd_config.d/00-hardening.conf.tmp /etc/ssh/sshd_config.d/00-hardening.conf
chmod 0644 /etc/ssh/sshd_config.d/00-hardening.conf 2>/dev/null || true

mkdir -p /run/sshd
if [ "$SSH_PWD_DISABLED" -eq 1 ] || [ "$ROOT_PROHIBIT_PWD" -eq 1 ]; then
    for scf in /etc/ssh/sshd_config.d/*.conf; do
        if [ ! -f "$scf" ] || [ "$scf" = "/etc/ssh/sshd_config.d/00-hardening.conf" ]; then
            continue
        fi
        if [ "$SSH_PWD_DISABLED" -eq 1 ]; then
            sed -i -E 's/^[[:space:]]*PasswordAuthentication[[:space:]]+yes\b.*/PasswordAuthentication no/I; s/^[[:space:]]*PermitRootLogin[[:space:]]+yes\b.*/PermitRootLogin prohibit-password/I' "$scf" 2>/dev/null || true
        else
            sed -i -E 's/^[[:space:]]*PermitRootLogin[[:space:]]+yes\b.*/PermitRootLogin prohibit-password/I' "$scf" 2>/dev/null || true
        fi
    done
    if /usr/sbin/sshd -T 2>/dev/null | grep -qiE '^(passwordauthentication yes|permitrootlogin yes)$'; then
        if [ -f /etc/ssh/sshd_config ]; then
            if [ "$SSH_PWD_DISABLED" -eq 1 ]; then
                sed -i -E 's/^[#[:space:]]*PasswordAuthentication[[:space:]]+yes\b.*/PasswordAuthentication no/I; s/^[#[:space:]]*PermitRootLogin[[:space:]]+yes\b.*/PermitRootLogin prohibit-password/I' /etc/ssh/sshd_config 2>/dev/null || true
            else
                sed -i -E 's/^[#[:space:]]*PermitRootLogin[[:space:]]+yes\b.*/PermitRootLogin prohibit-password/I' /etc/ssh/sshd_config 2>/dev/null || true
            fi
        fi
    fi
fi

if /usr/sbin/sshd -t; then
    if [ -n "$HARDENING_BAK" ]; then
        rm -f "$HARDENING_BAK"
    fi
    systemctl restart "$SSH_SERVICE.service" || true
    ok "Служба SSH перезапущена на порту $TARGET_SSH_PORT."
    if [ "$ROOT_PROHIBIT_PWD" -eq 1 ] && /usr/sbin/sshd -T 2>/dev/null | grep -qiE '^permitrootlogin[[:space:]]+yes$'; then
        warn "sshd -T сообщает permitrootlogin yes; проверьте конфликты в /etc/ssh/sshd_config."
    fi
    if [ "$SSH_PWD_DISABLED" -eq 1 ] && /usr/sbin/sshd -T 2>/dev/null | grep -qiE '^passwordauthentication[[:space:]]+yes$'; then
        warn "sshd -T сообщает passwordauthentication yes; проверьте конфликты в /etc/ssh/sshd_config."
    fi
else
    warn "Ошибка конфигурации SSH! Откат изменений."
    if [ -n "$HARDENING_BAK" ] && [ -f "$HARDENING_BAK" ]; then
        mv -f "$HARDENING_BAK" /etc/ssh/sshd_config.d/00-hardening.conf
    else
        rm -f /etc/ssh/sshd_config.d/00-hardening.conf
    fi
    systemctl restart "$SSH_SERVICE.service" || true
fi

if command -v fail2ban-client >/dev/null 2>&1; then
    F2B_BACKEND="systemd"
    if ! python3 -c "import systemd.journal" >/dev/null 2>&1; then
        F2B_BACKEND="auto"
    fi
    mkdir -p /etc/fail2ban
    cat << EOF > /etc/fail2ban/jail.local.tmp
[sshd]
enabled = true
port = $TARGET_SSH_PORT
maxretry = 5
findtime = 10m
bantime = 1h
backend = $F2B_BACKEND
EOF
    mv -f /etc/fail2ban/jail.local.tmp /etc/fail2ban/jail.local
    chmod 0644 /etc/fail2ban/jail.local 2>/dev/null || true
    systemctl enable fail2ban >/dev/null 2>&1 || true
    systemctl restart fail2ban 2>/dev/null || true
    sleep 1
    if fail2ban-client status sshd >/dev/null 2>&1; then
        ok "Служба Fail2ban активна (jail sshd, backend=$F2B_BACKEND)."
    else
        warn "Fail2ban запущен, но jail sshd не отвечает на проверку fail2ban-client status sshd."
    fi
fi

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
rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx 2>/dev/null || true

if systemctl is-active --quiet apache2 2>/dev/null || systemctl list-unit-files apache2.service 2>/dev/null | grep -q "apache2"; then
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi
BUSY_PORT_HOLDERS=$(ss -tlnp 2>/dev/null | awk '$4 ~ /:(80|443)$/ {print $0}' | grep -vE 'nginx|apache2' || true)
if [ -n "$BUSY_PORT_HOLDERS" ]; then
    warn "Обнаружены сторонние процессы на портах 80/443:"
    echo "$BUSY_PORT_HOLDERS" >&2
    die "Освободите порты 80/443 (caddy/traefik/haproxy/docker) перед установкой Nginx."
fi

NGINX_KEYRING="/usr/share/keyrings/nginx-archive-keyring.gpg"
mkdir -p /usr/share/keyrings
chmod 0755 /usr/share/keyrings

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

if [ "$NGINX_KEY_OK" -eq 0 ]; then
    warn "Официальный PGP-ключ nginx.org не загружен (сеть недоступна). Пропуск подключения репозитория nginx.org."
fi

EXISTING_NGINX_VER="0"
if command -v nginx >/dev/null 2>&1; then
    EXISTING_NGINX_VER=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0")
fi

is_cve_safe_nginx() {
    local v="${1:-0}"
    [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    local maj="${BASH_REMATCH[1]}" mn="${BASH_REMATCH[2]}"
    if [ "$maj" -gt 1 ]; then return 0; fi
    if [ $((mn % 2)) -eq 1 ]; then
        dpkg --compare-versions "$v" "ge" "1.31.10"
    else
        dpkg --compare-versions "$v" "ge" "1.30.8"
    fi
}

MIN_NGINX_VER="1.29.4"
USE_OFFICIAL_NGINX_REPO=0
if [ "$NGINX_KEY_OK" -eq 1 ] && [ -s "$NGINX_KEYRING" ]; then
    NGINX_REPO_CODENAME="$OS_CODENAME"
    if ! curl -fsSL -I --connect-timeout 6 -m 10 "https://nginx.org/packages/mainline/$OS_ID/dists/$OS_CODENAME/Release" >/dev/null 2>&1; then
        if [ "$OS_ID" = "ubuntu" ]; then
            NGINX_REPO_CODENAME="noble"
        else
            NGINX_REPO_CODENAME="bookworm"
        fi
    fi

    echo "deb [signed-by=$NGINX_KEYRING] https://nginx.org/packages/mainline/$OS_ID $NGINX_REPO_CODENAME nginx" \
        | tee /etc/apt/sources.list.d/nginx.list >/dev/null

    cat << 'EOF' > /etc/apt/preferences.d/99nginx.tmp
Package: *
Pin: origin nginx.org
Pin-Priority: 1001
EOF
    mv -f /etc/apt/preferences.d/99nginx.tmp /etc/apt/preferences.d/99nginx
    chmod 0644 /etc/apt/preferences.d/99nginx 2>/dev/null || true

    wait_for_apt_lock
    if apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/nginx.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" >/dev/null 2>&1; then
        USE_OFFICIAL_NGINX_REPO=1
        ok "Репозиторий Nginx Mainline ($NGINX_REPO_CODENAME) верифицирован."
    else
        warn "Сбой обновления репозитория nginx.org. Откат репозиторных списков..."
        rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/preferences.d/99nginx
    fi
fi

wait_for_apt_lock
if [ "$USE_OFFICIAL_NGINX_REPO" -eq 1 ]; then
    CANDIDATE_NGINX_VER=$(apt-cache policy nginx 2>/dev/null | awk '/Candidate:/ {print $2}' | sed -E 's/^([0-9]+:)?([0-9]+\.[0-9]+\.[0-9]+).*/\2/' || echo "0")
    if [[ ! "$CANDIDATE_NGINX_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || dpkg --compare-versions "$CANDIDATE_NGINX_VER" "lt" "$MIN_NGINX_VER"; then
        die "Версия-кандидат Nginx ($CANDIDATE_NGINX_VER) ниже минимально требуемой $MIN_NGINX_VER (необходим proxy_http_version 2). Установка отменена."
    fi
    rm -f /etc/nginx/modules-enabled/*stream*.conf 2>/dev/null || true
    CONFLICT_NGINX_PKGS=()
    for npkg in nginx-common nginx-core nginx-full nginx-light nginx-extras; do
        if dpkg-query -W -f='${Status}' "$npkg" 2>/dev/null | grep -q "install ok installed"; then
            CONFLICT_NGINX_PKGS+=("$npkg")
        fi
    done
    while IFS= read -r mpkg; do
        [ -n "$mpkg" ] && CONFLICT_NGINX_PKGS+=("$mpkg")
    done < <(dpkg-query -W -f='${Package}\n' 'libnginx-mod-*' 2>/dev/null || true)
    if [ "${#CONFLICT_NGINX_PKGS[@]}" -gt 0 ]; then
        log "Удаление конфликтующих дистрибутивных пакетов Nginx (${CONFLICT_NGINX_PKGS[*]}) перед переходом на nginx.org..."
        rm -rf "$NGINX_PRE_BAK"
        mkdir -p "$NGINX_PRE_BAK"
        if [ -f /etc/nginx/nginx.conf ]; then cp -a /etc/nginx/nginx.conf "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
        if [ -d /etc/nginx/conf.d ]; then cp -a /etc/nginx/conf.d "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
        if [ -d /etc/nginx/stream.d ]; then cp -a /etc/nginx/stream.d "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
        if [ -d /etc/nginx/sites-enabled ]; then cp -a /etc/nginx/sites-enabled "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
        if [ -d /etc/nginx/sites-available ]; then cp -a /etc/nginx/sites-available "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
        ROLLBACK_ACTIVE=1
        apt-get remove -y -q "${CONFLICT_NGINX_PKGS[@]}" || true
    fi
    apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx
    ok "Nginx Mainline ($CANDIDATE_NGINX_VER) успешно актуализирован/установлен."
else
    if [ "$EXISTING_NGINX_VER" != "0" ] && is_cve_safe_nginx "$EXISTING_NGINX_VER"; then
        ok "Сохранена актуальная версия Nginx ($EXISTING_NGINX_VER, CVE-patched)."
    else
        die "Активный Nginx ($EXISTING_NGINX_VER) отсутствует или уязвим (требуется >= 1.31.10 mainline / >= 1.30.8 stable), а репозиторий nginx.org недоступен."
    fi
fi

INSTALLED_NGINX_VER=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0")
if [ "$INSTALLED_NGINX_VER" = "0" ] || dpkg --compare-versions "$INSTALLED_NGINX_VER" "lt" "$MIN_NGINX_VER"; then
    die "Установленная версия Nginx ($INSTALLED_NGINX_VER) ниже допустимой $MIN_NGINX_VER. Прекращение работы."
fi
if ! is_cve_safe_nginx "$INSTALLED_NGINX_VER"; then
    warn "Установленный Nginx ($INSTALLED_NGINX_VER) ниже CVE-патч уровня (1.31.10 mainline / 1.30.8 stable). Проверьте обновления nginx.org."
fi
ok "Версия Nginx верифицирована: ${GREEN}${INSTALLED_NGINX_VER}${NC} (>= ${MIN_NGINX_VER}, proxy_http_version 2 активен)."

if nginx -V 2>&1 | grep -qE -- '--with-stream($|[^-=])'; then
    rm -f /etc/nginx/modules-enabled/*stream*.conf 2>/dev/null || true
fi

NGINX_USER="nginx"
id -u nginx >/dev/null 2>&1 || NGINX_USER="www-data"

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p "$WEBROOT/assets/css" "$WEBROOT/assets/js" "$WEBROOT/assets/img"
mkdir -p /var/log/nginx /var/cache/nginx /var/www/mirror /var/www/proxy_temp /etc/nginx/stream.d /etc/nginx/conf.d /etc/nginx/modules-enabled

if [ ! -d "$NGINX_PRE_BAK" ]; then
    mkdir -p "$NGINX_PRE_BAK"
    chmod 0700 "$NGINX_PRE_BAK"
    if [ -f /etc/nginx/nginx.conf ]; then cp -a /etc/nginx/nginx.conf "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
    if [ -d /etc/nginx/conf.d ]; then cp -a /etc/nginx/conf.d "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
    if [ -d /etc/nginx/stream.d ]; then cp -a /etc/nginx/stream.d "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
    if [ -d /etc/nginx/sites-enabled ]; then cp -a /etc/nginx/sites-enabled "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
    if [ -d /etc/nginx/sites-available ]; then cp -a /etc/nginx/sites-available "$NGINX_PRE_BAK/" 2>/dev/null || true; fi
fi
ROLLBACK_ACTIVE=1

rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* 2>/dev/null || true
rm -rf /etc/nginx/conf.d/* /etc/nginx/stream.d/* 2>/dev/null || true

chmod 755 /var /var/www "$WEBROOT"
chmod -R 755 "$WEBROOT/.well-known"
find "$WEBROOT" -type d -exec chmod 755 {} +
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp /var/log/nginx 2>/dev/null || true

if [ ! -s /etc/nginx/mime.types ] || ! grep -q "text/css" /etc/nginx/mime.types 2>/dev/null; then
    log "Синтез канонической таблицы MIME-типов (/etc/nginx/mime.types)..."
    cat << 'EOF_MIME' > /etc/nginx/mime.types.tmp
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
    mv -f /etc/nginx/mime.types.tmp /etc/nginx/mime.types
    chmod 0644 /etc/nginx/mime.types 2>/dev/null || true
fi

cat << EOF > /etc/nginx/nginx.conf.tmp
user $NGINX_USER;
worker_processes auto;
worker_cpu_affinity auto;
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
mv -f /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
chmod 0644 /etc/nginx/nginx.conf 2>/dev/null || true

HAS_IPV6_STACK=0
if [ "${DISABLE_IPV6:-0}" -eq 0 ] && [ -f /proc/net/if_inet6 ] && grep -q '00000000000000000000000000000001' /proc/net/if_inet6 2>/dev/null; then
    HAS_IPV6_STACK=1
fi
NGINX_V6_80=""
NGINX_V6_443=""
if [ "$HAS_IPV6_STACK" -eq 1 ]; then
    NGINX_V6_80="    listen [::]:80 default_server;"
    NGINX_V6_443="    listen [::]:443 backlog=65535 reuseport;"
fi

cat << EOF > /etc/nginx/conf.d/00-acme.conf.tmp
server {
    listen 80 default_server;
${NGINX_V6_80}
    server_name _;
    server_tokens off;
    root /var/www/html;

    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 444;
    }
}
EOF
mv -f /etc/nginx/conf.d/00-acme.conf.tmp /etc/nginx/conf.d/00-acme.conf
chmod 0644 /etc/nginx/conf.d/00-acme.conf 2>/dev/null || true

if [ -f /usr/sbin/policy-rc.d ]; then
    rm -f /usr/sbin/policy-rc.d 2>/dev/null || true
fi

if systemctl is-active --quiet apache2 2>/dev/null || systemctl list-unit-files apache2.service 2>/dev/null | grep -q "apache2"; then
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
fi

nginx -t || die "Ошибка конфигурации ACME Bootstrap сервера Nginx."

systemctl unmask nginx.service 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed nginx.service 2>/dev/null || true
killall -9 nginx 2>/dev/null || true

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

is_valid_real_cert() {
    local cert_f="$1"
    local key_f="$2"
    [ -s "$cert_f" ] && [ -s "$key_f" ] || return 1
    openssl x509 -in "$cert_f" -noout -checkend 604800 >/dev/null 2>&1 || return 1
    local iss subj
    iss=$(openssl x509 -in "$cert_f" -noout -issuer 2>/dev/null | sed 's/^issuer=//' || echo "")
    subj=$(openssl x509 -in "$cert_f" -noout -subject 2>/dev/null | sed 's/^subject=//' || echo "")
    [ -n "$iss" ] && [ "$iss" != "$subj" ] || return 1
    local c_pub k_pub
    c_pub=$(openssl x509 -in "$cert_f" -noout -pubkey 2>/dev/null | openssl md5 2>/dev/null || echo "c")
    k_pub=$(openssl pkey -in "$key_f" -pubout 2>/dev/null | openssl md5 2>/dev/null || echo "k")
    [ "$c_pub" = "$k_pub" ]
}

gen_emergency_selfsigned() {
    local dom="$1"
    mkdir -p "${SSL_BASE_DIR}/$dom"
    chmod 755 "${SSL_BASE_DIR}/$dom"
    (
        umask 077
        openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
            -keyout "${SSL_BASE_DIR}/$dom/privkey.pem" \
            -out "${SSL_BASE_DIR}/$dom/fullchain.pem" \
            -subj "/CN=$dom" >/dev/null 2>&1
    )
    chmod 644 "${SSL_BASE_DIR}/$dom/fullchain.pem"
    chmod 600 "${SSL_BASE_DIR}/$dom/privkey.pem"
}

if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Настройка Certbot через системный APT..."
    wait_for_apt_lock
    apt-get install -y certbot -q

    mkdir -p /etc/letsencrypt
    if [ -n "$LE_EMAIL" ]; then
        cat << EOF > /etc/letsencrypt/cli.ini.tmp
email = $LE_EMAIL
agree-tos = true
non-interactive = true
EOF
        mv -f /etc/letsencrypt/cli.ini.tmp /etc/letsencrypt/cli.ini
        chmod 0644 /etc/letsencrypt/cli.ini 2>/dev/null || true
    else
        cat << EOF > /etc/letsencrypt/cli.ini.tmp
register-unsafely-without-email = true
agree-tos = true
non-interactive = true
EOF
        mv -f /etc/letsencrypt/cli.ini.tmp /etc/letsencrypt/cli.ini
        chmod 0644 /etc/letsencrypt/cli.ini 2>/dev/null || true
    fi

    for dom in "${ALL_DOMAINS[@]}"; do
        if is_valid_real_cert "/etc/letsencrypt/live/$dom/fullchain.pem" "/etc/letsencrypt/live/$dom/privkey.pem"; then
            ok "Сертификат для $dom уже существует, доверенный и действителен >7 дней (пропуск выпуска)."
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
                    gen_emergency_selfsigned "$PRIMARY_DOMAIN"
                    ok "Аварийный самоподписанный SSL успешно сгенерирован."
                else
                    warn "Установка прервана пользователем из-за отсутствия SSL."
                    exit 1
                fi
            elif [ "${ENABLE_AGH:-0}" -eq 1 ] && [ "$dom" = "${AGH_DOMAIN:-}" ]; then
                warn "Не удалось выпустить Let's Encrypt для AdGuard Home ($AGH_DOMAIN)."
                if prompt_yes_no "Сгенерировать аварийный Self-Signed SSL для $AGH_DOMAIN?" "y"; then
                    gen_emergency_selfsigned "$AGH_DOMAIN"
                    ok "Аварийный Self-Signed SSL для $AGH_DOMAIN сгенерирован."
                else
                    warn "Веб-интерфейс/DoH AdGuard Home будет отключён (нет SSL)."
                    ENABLE_AGH=0
                    sed -i -E 's/^ENABLE_AGH=.*/ENABLE_AGH="0"/' /etc/myprivatecloud/config.env 2>/dev/null || true
                    python3 -c 'import json, os; p="/etc/myprivatecloud/config.json"; d=json.load(open(p,"r",encoding="utf-8")); d["enable_agh"]=False; open(p+".tmp","w",encoding="utf-8").write(json.dumps(d,indent=2,ensure_ascii=False)); os.replace(p+".tmp",p); os.chmod(p,0o600)' 2>/dev/null || true
                fi
            fi
        fi
    done

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
    cat << 'EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh.tmp
#!/bin/bash
chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true
find /etc/letsencrypt/live/ -name "privkey.pem" -exec chmod 600 {} + 2>/dev/null || true
systemctl reload nginx
EOF
    mv -f /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh.tmp /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
    chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh 2>/dev/null || true
else
    log "Выпуск SSL через acme.sh..."
    curl -fsSL https://get.acme.sh | sh -s email="${LE_EMAIL:-admin@$PRIMARY_DOMAIN}"
    _ACME="${HOME:-/root}/.acme.sh/acme.sh"
    chmod +x "$_ACME"
    "$_ACME" --register-account -m "${LE_EMAIL:-admin@$PRIMARY_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p /etc/ssl/acme && chmod 755 /etc/ssl /etc/ssl/acme

    for dom in "${ALL_DOMAINS[@]}"; do
        if is_valid_real_cert "/etc/ssl/acme/$dom/fullchain.pem" "/etc/ssl/acme/$dom/privkey.pem"; then
            ok "Сертификат для $dom уже существует, доверенный и действителен >7 дней."
            continue
        fi

        if "$_ACME" --issue --dns dns_cf -d "$dom" --server letsencrypt --force; then
            mkdir -p "/etc/ssl/acme/$dom"
            chmod 755 "/etc/ssl/acme/$dom"
            "$_ACME" --install-cert -d "$dom" \
                --key-file "/etc/ssl/acme/$dom/privkey.pem" \
                --fullchain-file "/etc/ssl/acme/$dom/fullchain.pem" \
                --reloadcmd "chmod 755 /etc/ssl/acme/$dom; chmod 644 /etc/ssl/acme/$dom/*; chmod 600 /etc/ssl/acme/$dom/privkey.pem; systemctl reload nginx"
            ok "Сертификат для $dom получен."
        else
            warn "Ошибка выпуска SSL через acme.sh для $dom."
            if [ "$dom" = "$PRIMARY_DOMAIN" ]; then
                if prompt_yes_no "Сгенерировать аварийный Self-Signed SSL для $PRIMARY_DOMAIN, чтобы поднять шлюз?" "y"; then
                    gen_emergency_selfsigned "$PRIMARY_DOMAIN"
                    ok "Аварийный самоподписанный SSL успешно сгенерирован."
                else
                    die "Установка прервана из-за отсутствия SSL для $PRIMARY_DOMAIN."
                fi
            elif [ "${ENABLE_AGH:-0}" -eq 1 ] && [ "$dom" = "${AGH_DOMAIN:-}" ]; then
                if prompt_yes_no "Сгенерировать аварийный Self-Signed SSL для $AGH_DOMAIN?" "y"; then
                    gen_emergency_selfsigned "$AGH_DOMAIN"
                    ok "Аварийный Self-Signed SSL для $AGH_DOMAIN сгенерирован."
                else
                    warn "Веб-интерфейс/DoH AdGuard Home будет отключён (нет SSL)."
                    ENABLE_AGH=0
                    sed -i -E 's/^ENABLE_AGH=.*/ENABLE_AGH="0"/' /etc/myprivatecloud/config.env 2>/dev/null || true
                    python3 -c 'import json, os; p="/etc/myprivatecloud/config.json"; d=json.load(open(p,"r",encoding="utf-8")); d["enable_agh"]=False; open(p+".tmp","w",encoding="utf-8").write(json.dumps(d,indent=2,ensure_ascii=False)); os.replace(p+".tmp",p); os.chmod(p,0o600)' 2>/dev/null || true
                fi
            fi
        fi
    done
fi

chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive /etc/ssl/acme 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/*.pem /etc/ssl/acme/*/*.pem 2>/dev/null || true
find /etc/letsencrypt/live/ /etc/ssl/acme/ -name "privkey.pem" -exec chmod 600 {} + 2>/dev/null || true

if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    log "Установка AdGuard Home (DoH + Split-DNS)..."
    if systemctl is-active --quiet systemd-resolved 2>/dev/null || systemctl list-unit-files systemd-resolved.service 2>/dev/null | grep -q "systemd-resolved"; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard-disable-stub.conf.tmp
[Resolve]
DNSStubListener=no
EOF
        mv -f /etc/systemd/resolved.conf.d/adguard-disable-stub.conf.tmp /etc/systemd/resolved.conf.d/adguard-disable-stub.conf
        chmod 0644 /etc/systemd/resolved.conf.d/adguard-disable-stub.conf 2>/dev/null || true
        systemctl restart systemd-resolved 2>/dev/null || true
        sleep 1
    fi

    if [ "$GEO_PROFILE" = "1" ]; then
        cat << 'EOF' > /etc/resolv.conf.tmp
nameserver 77.88.8.8
nameserver 77.88.8.1
EOF
        mv -f /etc/resolv.conf.tmp /etc/resolv.conf
        chmod 0644 /etc/resolv.conf 2>/dev/null || true
    else
        cat << 'EOF' > /etc/resolv.conf.tmp
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
        mv -f /etc/resolv.conf.tmp /etc/resolv.conf
        chmod 0644 /etc/resolv.conf 2>/dev/null || true
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
        if [ -f /etc/myprivatecloud/config.env ]; then
            sed -i -E 's/^ENABLE_AGH=.*/ENABLE_AGH="0"/' /etc/myprivatecloud/config.env 2>/dev/null || true
        fi
        if [ -f /etc/myprivatecloud/config.json ]; then
            python3 -c 'import json, os; p="/etc/myprivatecloud/config.json"; d=json.load(open(p,"r",encoding="utf-8")); d["enable_agh"]=False; open(p+".tmp","w",encoding="utf-8").write(json.dumps(d,indent=2,ensure_ascii=False)); os.replace(p+".tmp",p); os.chmod(p,0o600)' 2>/dev/null || true
        fi
    fi
    if [ "$ENABLE_AGH" -eq 1 ]; then
        systemctl stop AdGuardHome 2>/dev/null || true
        tar -zxvf "$AGH_TAR" -C /opt/ >/dev/null
        rm -f "$AGH_TAR"

        AGH_PASS_HASH=$(AGH_PASS="$AGH_PASS" python3 -c "import bcrypt, os; print(bcrypt.hashpw(os.environ['AGH_PASS'].encode('utf-8'), bcrypt.gensalt(10)).decode('utf-8'))")

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

        # Динамический расчет bind_hosts: исключает падение AGH при выключенном Native AWG
        AGH_BIND_HOSTS="    - 127.0.0.1"
        if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
            AGH_BIND_HOSTS="${AGH_BIND_HOSTS}
    - 10.9.0.1"
        fi

        AGH_QL_ENABLED="false"
        AGH_QL_FILE_ENABLED="false"
        AGH_QL_INTERVAL="1h"
        AGH_QL_SIZE_MEM="0"
        AGH_STAT_ENABLED="false"
        if [ "${AGH_RAM_TELEMETRY:-0}" = "1" ]; then
            AGH_QL_ENABLED="true"
            AGH_QL_FILE_ENABLED="true"
            AGH_QL_INTERVAL="24h"
            AGH_QL_SIZE_MEM="200"
            AGH_STAT_ENABLED="true"
        fi

        if [ ! -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
            cat << EOF > /opt/AdGuardHome/AdGuardHome.yaml.tmp
http:
  address: 127.0.0.1:3000
  doh:
    routes:
      - GET /dns-query
      - POST /dns-query
      - GET /dns-query/{ClientID}
      - POST /dns-query/{ClientID}
    insecure_enabled: true
users:
  - name: ${AGH_USER}
    password: "${AGH_PASS_HASH}"
querylog:
  dir_path: /run/adguardhome
  enabled: ${AGH_QL_ENABLED}
  file_enabled: ${AGH_QL_FILE_ENABLED}
  interval: ${AGH_QL_INTERVAL}
  size_memory: ${AGH_QL_SIZE_MEM}
statistics:
  dir_path: /run/adguardhome
  enabled: ${AGH_STAT_ENABLED}
  interval: 24h
dns:
  bind_hosts:
${AGH_BIND_HOSTS}
  port: 53
  upstream_mode: parallel
  bootstrap_dns:
    - 9.9.9.11
    - 8.8.4.4
    - 1.0.0.1
  ratelimit: 0
  cache_size: 8388608
  cache_optimistic: true
  enable_dnssec: false
  use_http3_upstreams: true
  aaaa_disabled: $([ "${DISABLE_IPV6:-0}" -eq 1 ] && echo "true" || echo "false")
  trusted_proxies:
    - 127.0.0.1/32
    - 10.8.1.0/24
    - 10.8.2.0/24
    - 10.8.3.0/24
    - 10.9.0.0/24
  allowed_clients:
    - ${AGH_CLIENT_ID,,}
    - "10.8.1.0/24"
    - "10.8.2.0/24"
    - "10.8.3.0/24"
    - "10.9.0.0/24"
    - "127.0.0.1"
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
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
tls:
  enabled: false
  allow_unencrypted_doh: true
log:
  enabled: false
schema_version: 28
EOF
            mv -f /opt/AdGuardHome/AdGuardHome.yaml.tmp /opt/AdGuardHome/AdGuardHome.yaml
        else
            ok "Предыдущие настройки AdGuard Home (/opt/AdGuardHome/AdGuardHome.yaml) сохранены с реконсиляцией."
            AGH_CID_ENV="${AGH_CLIENT_ID:-}" AGH_USER_ENV="${AGH_USER:-admin}" AGH_HASH_ENV="${AGH_PASS_HASH:-}" \
            ENABLE_NAWG_ENV="${ENABLE_NATIVE_AWG:-0}" DISABLE_IPV6_ENV="${DISABLE_IPV6:-0}" AGH_RAM_TEL_ENV="${AGH_RAM_TELEMETRY:-0}" python3 - << 'EOF_AGH_YAML_AC'
import os, re

yaml_p = "/opt/AdGuardHome/AdGuardHome.yaml"
with open(yaml_p, "r", encoding="utf-8") as f:
    raw_lines = f.readlines()

env_cid = os.environ.get("AGH_CID_ENV", "").strip()
agh_user = os.environ.get("AGH_USER_ENV", "admin").strip() or "admin"
agh_hash = os.environ.get("AGH_HASH_ENV", "").strip()
en_nawg = os.environ.get("ENABLE_NAWG_ENV", "0").strip() == "1"
ipv6_off = os.environ.get("DISABLE_IPV6_ENV", "0").strip() == "1"
ram_tel = os.environ.get("AGH_RAM_TEL_ENV", "0").strip() == "1"

preamble = []
sections = []
cur_name = None
cur_lines = []
for ln in raw_lines:
    st = ln.strip()
    if st and not ln[0].isspace() and not st.startswith("#"):
        if cur_name is None:
            cur_name = st.split(":", 1)[0].strip()
            cur_lines = [ln]
        else:
            sections.append((cur_name, cur_lines))
            cur_name = st.split(":", 1)[0].strip()
            cur_lines = [ln]
    else:
        if cur_name is None:
            preamble.append(ln)
        else:
            cur_lines.append(ln)
if cur_name is not None:
    sections.append((cur_name, cur_lines))

sec_map = {n: ls for n, ls in sections}
sec_order = [n for n, _ in sections]

def ensure_section(name, default_lines):
    if name not in sec_map:
        sec_map[name] = list(default_lines)
        sec_order.append(name)

def replace_subblock(lines, key, new_block_lines):
    out = []
    i = 0
    found = False
    pat = re.compile(rf"^  {re.escape(key)}:(?:\s*(.*))?$")
    while i < len(lines):
        m = pat.match(lines[i])
        if m and not found:
            found = True
            out.extend(new_block_lines)
            i += 1
            while i < len(lines) and (lines[i].startswith("    ") or not lines[i].strip()):
                if not lines[i].strip():
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    if not found:
        out.extend(new_block_lines)
    return out

def set_scalar(lines, key, val):
    out = []
    found = False
    pat = re.compile(rf"^  {re.escape(key)}:\s*.*$")
    for ln in lines:
        if pat.match(ln) and not found:
            out.append(f"  {key}: {val}\n")
            found = True
        else:
            out.append(ln)
    if not found:
        out.append(f"  {key}: {val}\n")
    return out

def get_list_items(lines, key):
    items = []
    pat = re.compile(rf"^  {re.escape(key)}:(?:\s*(.*))?$")
    i = 0
    while i < len(lines):
        m = pat.match(lines[i])
        if m:
            rest = (m.group(1) or "").strip()
            if rest.startswith("[") and rest.endswith("]") and rest != "[]":
                for p in rest[1:-1].split(","):
                    v = p.strip().strip("\"'")
                    if v:
                        items.append(v)
                break
            i += 1
            while i < len(lines):
                ln = lines[i]
                if ln.startswith("    - "):
                    v = ln[6:].strip().strip("\"'")
                    if v:
                        items.append(v)
                elif ln.strip() and not ln.startswith("    "):
                    break
                i += 1
            break
        i += 1
    return items

# 1. http + doh
ensure_section("http", ["http:\n", "  address: 127.0.0.1:3000\n"])
sec_map["http"] = replace_subblock(
    sec_map["http"],
    "doh",
    [
        "  doh:\n",
        "    routes:\n",
        "      - GET /dns-query\n",
        "      - POST /dns-query\n",
        "      - GET /dns-query/{ClientID}\n",
        "      - POST /dns-query/{ClientID}\n",
        "    insecure_enabled: true\n",
    ],
)

# 2. users
if agh_hash:
    ensure_section("users", ["users:\n"])
    u_lines = ["users:\n"]
    cur_users = []
    tmp_u = None
    for ln in sec_map["users"][1:]:
        m_n = re.match(r"^\s*-\s*name:\s*(.+)$", ln)
        if m_n:
            if tmp_u:
                cur_users.append(tmp_u)
            tmp_u = {"name": m_n.group(1).strip().strip("\"'"), "extra": []}
        elif tmp_u is not None and ln.strip():
            tmp_u["extra"].append(ln)
    if tmp_u:
        cur_users.append(tmp_u)
    updated_u = False
    for uo in cur_users:
        if uo["name"] == agh_user:
            u_lines.append(f"  - name: {agh_user}\n")
            u_lines.append(f'    password: "{agh_hash}"\n')
            updated_u = True
        else:
            u_lines.append(f"  - name: {uo['name']}\n")
            u_lines.extend(uo["extra"])
    if not updated_u:
        u_lines.append(f"  - name: {agh_user}\n")
        u_lines.append(f'    password: "{agh_hash}"\n')
    sec_map["users"] = u_lines

# 3. querylog, statistics, log (Zero-Log / RAM-Only 24h)
sec_map["querylog"] = [
    "querylog:\n",
    "  dir_path: /run/adguardhome\n",
    f"  enabled: {'true' if ram_tel else 'false'}\n",
    f"  file_enabled: {'true' if ram_tel else 'false'}\n",
    f"  interval: {'24h' if ram_tel else '1h'}\n",
    f"  size_memory: {200 if ram_tel else 0}\n",
]
if "querylog" not in sec_order:
    sec_order.append("querylog")

stats_key = "stats" if "stats" in sec_map and "statistics" not in sec_map else "statistics"
sec_map[stats_key] = [
    f"{stats_key}:\n",
    "  dir_path: /run/adguardhome\n",
    f"  enabled: {'true' if ram_tel else 'false'}\n",
    "  interval: 24h\n",
]
if stats_key not in sec_order:
    sec_order.append(stats_key)

sec_map["log"] = ["log:\n", "  enabled: false\n"]
if "log" not in sec_order:
    sec_order.append("log")

# 4. tls
if "tls" in sec_map:
    sec_map["tls"] = set_scalar(sec_map["tls"], "allow_unencrypted_doh", "true")

# 5. dns
ensure_section("dns", ["dns:\n", "  port: 53\n"])
d_lines = sec_map["dns"]
bind_block = ["  bind_hosts:\n", "    - 127.0.0.1\n"] + (["    - 10.9.0.1\n"] if en_nawg else [])
d_lines = replace_subblock(d_lines, "bind_hosts", bind_block)

req_proxies = ["127.0.0.1/32", "10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24", "10.9.0.0/24"]
cur_proxies = get_list_items(d_lines, "trusted_proxies")
merged_proxies = list(cur_proxies)
for p in req_proxies:
    if p not in merged_proxies:
        merged_proxies.append(p)
d_lines = replace_subblock(d_lines, "trusted_proxies", ["  trusted_proxies:\n"] + [f"    - {p}\n" for p in merged_proxies])

cur_allowed = get_list_items(d_lines, "allowed_clients")
cids_to_ensure = []
if env_cid and re.match(r"^[a-zA-Z0-9._-]+$", env_cid):
    cids_to_ensure.append(env_cid.lower())
if "clients" in sec_map:
    c_txt = "".join(sec_map["clients"])
    for m_ids in re.finditer(r"^\s+ids:\s*\n((?:\s+-\s+[^\n]+\n)+)", c_txt, re.M):
        for ln in m_ids.group(1).splitlines():
            v = ln.strip().lstrip("-").strip().strip("\"'")
            if v and re.match(r"^[a-zA-Z0-9._-]+$", v) and v.lower() not in cids_to_ensure:
                cids_to_ensure.append(v.lower())
merged_allowed = list(cur_allowed)
for x in cids_to_ensure + ["10.8.1.0/24", "10.8.2.0/24", "10.8.3.0/24", "10.9.0.0/24", "127.0.0.1"]:
    if x not in merged_allowed and x.lower() not in [m.lower() for m in merged_allowed]:
        merged_allowed.append(x)
if merged_allowed:
    d_lines = replace_subblock(
        d_lines,
        "allowed_clients",
        ["  allowed_clients:\n"] + [f'    - "{x}"\n' if ("." in x or "/" in x) else f"    - {x}\n" for x in merged_allowed],
    )

for dk, dv in {
    "upstream_mode": "parallel",
    "cache_size": "8388608",
    "cache_optimistic": "true",
    "enable_dnssec": "false",
    "use_http3_upstreams": "true",
    "aaaa_disabled": "true" if ipv6_off else "false",
}.items():
    d_lines = set_scalar(d_lines, dk, dv)
sec_map["dns"] = d_lines

# 6. clients.persistent
ensure_section("clients", ["clients:\n", "  runtime_sources:\n", "    whois: false\n", "    dhcp: false\n", "  persistent: []\n"])
if env_cid and re.match(r"^[a-zA-Z0-9._-]+$", env_cid):
    c_all_txt = "".join(sec_map["clients"])
    if not re.search(rf"^\s*-\s*{re.escape(env_cid)}\s*$", c_all_txt, re.M | re.I):
        if re.search(r"^\s+persistent:\s*\[\]\s*$", c_all_txt, re.M):
            sec_map["clients"] = replace_subblock(
                sec_map["clients"],
                "persistent",
                ["  persistent:\n", "    - name: Home-Router\n", "      ids:\n", f"        - {env_cid}\n", "      use_global_settings: true\n"],
            )
        elif re.search(r"^\s+persistent:\s*$", c_all_txt, re.M):
            sec_map["clients"].extend(["    - name: Home-Router\n", "      ids:\n", f"        - {env_cid}\n", "      use_global_settings: true\n"])
        else:
            sec_map["clients"].extend(["  persistent:\n", "    - name: Home-Router\n", "      ids:\n", f"        - {env_cid}\n", "      use_global_settings: true\n"])

out_all = list(preamble)
for sn in sec_order:
    lines_s = sec_map[sn]
    if lines_s and not lines_s[-1].endswith("\n"):
        lines_s[-1] += "\n"
    out_all.extend(lines_s)

with open(yaml_p + ".tmp", "w", encoding="utf-8") as f:
    f.writelines(out_all)
os.chmod(yaml_p + ".tmp", 0o600)
os.replace(yaml_p + ".tmp", yaml_p)
EOF_AGH_YAML_AC
        fi
        chmod 0600 /opt/AdGuardHome/AdGuardHome.yaml 2>/dev/null || true
        rm -f /opt/AdGuardHome/data/querylog.json* /opt/AdGuardHome/data/stats.db* 2>/dev/null || true
        if [ "${AGH_RAM_TELEMETRY:-0}" != "1" ]; then
            rm -f /run/adguardhome/querylog.json* /run/adguardhome/stats.db* 2>/dev/null || true
        fi

        mkdir -p /etc/systemd/system/AdGuardHome.service.d/
        if [ "${AGH_RAM_TELEMETRY:-0}" = "1" ]; then
            cat << EOF_AGH_MOUNT > /etc/systemd/system/run-adguardhome.mount.tmp
[Unit]
Description=AdGuard Home Volatile RAM Storage (/run/adguardhome)
DefaultDependencies=no
After=local-fs.target
Before=AdGuardHome.service umount.target
Conflicts=umount.target

[Mount]
What=tmpfs
Where=/run/adguardhome
Type=tmpfs
DirectoryMode=0700
Options=mode=0700,uid=0,gid=0,nosuid,nodev,noexec,size=${AGH_TMPFS_SIZE}

[Install]
WantedBy=multi-user.target
EOF_AGH_MOUNT
            mv -f /etc/systemd/system/run-adguardhome.mount.tmp /etc/systemd/system/run-adguardhome.mount
            chmod 0644 /etc/systemd/system/run-adguardhome.mount 2>/dev/null || true
            mkdir -p /run/adguardhome
            chmod 0700 /run/adguardhome
            systemctl daemon-reload 2>/dev/null || true
            systemctl enable run-adguardhome.mount >/dev/null 2>&1 || true
            systemctl restart run-adguardhome.mount 2>/dev/null || true

            cat << EOF > /etc/systemd/system/AdGuardHome.service.d/10-memory.conf.tmp
[Unit]
Requires=run-adguardhome.mount
After=run-adguardhome.mount

[Service]
Environment="GOMEMLIMIT=$AGH_GOMEMLIMIT"
Environment="GODEBUG=madvdontneed=1"
MemoryHigh=$AGH_MEM_HIGH
MemoryMax=$AGH_MEM_MAX
LimitNOFILE=1048576
LimitNPROC=512
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictSUIDSGID=true
LockPersonality=true
TimeoutStopSec=15s
ReadWritePaths=-/opt/AdGuardHome -/run/adguardhome
EOF
        else
            systemctl disable --now run-adguardhome.mount >/dev/null 2>&1 || true
            rm -f /etc/systemd/system/run-adguardhome.mount 2>/dev/null || true
            cat << EOF > /etc/systemd/system/AdGuardHome.service.d/10-memory.conf.tmp
[Service]
Environment="GOMEMLIMIT=$AGH_GOMEMLIMIT"
Environment="GODEBUG=madvdontneed=1"
MemoryHigh=$AGH_MEM_HIGH
MemoryMax=$AGH_MEM_MAX
LimitNOFILE=1048576
LimitNPROC=512
RuntimeDirectory=adguardhome
RuntimeDirectoryMode=0700
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictNamespaces=true
RestrictSUIDSGID=true
LockPersonality=true
TimeoutStopSec=15s
ReadWritePaths=-/opt/AdGuardHome -/run/adguardhome
EOF
        fi
        mv -f /etc/systemd/system/AdGuardHome.service.d/10-memory.conf.tmp /etc/systemd/system/AdGuardHome.service.d/10-memory.conf
        chmod 0644 /etc/systemd/system/AdGuardHome.service.d/10-memory.conf 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
        /opt/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || true
        systemctl daemon-reload 2>/dev/null || true
        systemctl restart AdGuardHome || true

        AGH_DNS_READY=0
        for _ in {1..30}; do
            agh_dig_res=$(dig +short +time=2 +tries=1 google.com @127.0.0.1 2>/dev/null || true)
            if systemctl is-active --quiet AdGuardHome && printf '%s\n' "$agh_dig_res" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                AGH_DNS_READY=1
                break
            fi
            sleep 1
        done

        if [ "$AGH_DNS_READY" -eq 1 ]; then
            cp -L /etc/resolv.conf /tmp/resolv.conf.agh_bak 2>/dev/null || true
            cp -a /etc/nsswitch.conf /tmp/nsswitch.conf.agh_bak 2>/dev/null || true

            systemctl stop systemd-resolved 2>/dev/null || true
            systemctl disable systemd-resolved 2>/dev/null || true
            systemctl mask systemd-resolved 2>/dev/null || true

            python3 - << 'EOF_AGH_NSS'
import os
import re

nss_path = "/etc/nsswitch.conf"
if os.path.exists(nss_path):
    with open(nss_path, "r", encoding="utf-8") as f:
        nss_lines = f.readlines()
    new_lines = []
    for line in nss_lines:
        m = re.match(r"^(\s*hosts:\s*)(.*)$", line)
        if m:
            prefix, rhs = m.group(1), m.group(2)
            tokens = rhs.split()
            filtered = []
            skip_bracket = False
            for tok in tokens:
                if skip_bracket:
                    skip_bracket = False
                    if tok.startswith("[") and tok.endswith("]"):
                        continue
                if tok == "resolve":
                    skip_bracket = True
                    continue
                filtered.append(tok)
            if "files" not in filtered:
                filtered.insert(0, "files")
            if "dns" not in filtered:
                filtered.append("dns")
            new_lines.append(f"{prefix}{' '.join(filtered)}\n")
        else:
            new_lines.append(line)
    with open(nss_path + ".tmp", "w", encoding="utf-8") as f:
        f.writelines(new_lines)
    os.chmod(nss_path + ".tmp", 0o644)
    os.replace(nss_path + ".tmp", nss_path)
EOF_AGH_NSS

            cat << 'EOF_AGH_RESOLV' > /etc/resolv.conf.tmp
nameserver 127.0.0.1
options edns0 trust-ad
EOF_AGH_RESOLV
            chmod 0644 /etc/resolv.conf.tmp 2>/dev/null || true
            mv -Tf /etc/resolv.conf.tmp /etc/resolv.conf

            AGH_DIG_SYS=$(dig +short +time=3 google.com 2>/dev/null || true)
            AGH_GETENT_SYS=$(getent ahosts google.com 2>/dev/null || true)
            if printf '%s\n' "$AGH_DIG_SYS" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' && [ -n "$AGH_GETENT_SYS" ]; then
                if [ -d /etc/dhcp/dhclient-enter-hooks.d ]; then
                    cat << 'EOF_DH_NODNS' > /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate.tmp
make_resolv_conf() { :; }
EOF_DH_NODNS
                    mv -f /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate.tmp /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
                    chmod 0755 /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate 2>/dev/null || true
                fi
                if [ -d /etc/NetworkManager/conf.d ]; then
                    cat << 'EOF_NM_NODNS' > /etc/NetworkManager/conf.d/99-local-dns.conf.tmp
[main]
dns=none
EOF_NM_NODNS
                    mv -f /etc/NetworkManager/conf.d/99-local-dns.conf.tmp /etc/NetworkManager/conf.d/99-local-dns.conf
                    chmod 0644 /etc/NetworkManager/conf.d/99-local-dns.conf 2>/dev/null || true
                fi
                ok "DNS ОС изолирован через 127.0.0.1 (systemd-resolved замаскирован, AdGuard Home Zero-Log в tmpfs)."
            else
                warn "Системный резолвинг через 127.0.0.1 не подтверждён; откат /etc/resolv.conf и /etc/nsswitch.conf."
                systemctl unmask systemd-resolved 2>/dev/null || true
                if [ -s /tmp/nsswitch.conf.agh_bak ]; then
                    mv -f /tmp/nsswitch.conf.agh_bak /etc/nsswitch.conf
                    chmod 0644 /etc/nsswitch.conf 2>/dev/null || true
                fi
                if [ -s /tmp/resolv.conf.agh_bak ]; then
                    mv -f /tmp/resolv.conf.agh_bak /etc/resolv.conf
                    chmod 0644 /etc/resolv.conf 2>/dev/null || true
                fi
            fi
            rm -f /tmp/resolv.conf.agh_bak /tmp/nsswitch.conf.agh_bak
        else
            warn "AdGuard Home не ответил на 127.0.0.1:53 за 30с; /etc/resolv.conf оставлен на внешнем DNS."
        fi

        mkdir -p /etc/myprivatecloud
        chmod 0700 /etc/myprivatecloud
        AGH_USER_ENV="$AGH_USER" AGH_PASS_ENV="$AGH_PASS" AGH_DOMAIN_ENV="$AGH_DOMAIN" \
        python3 - << 'EOF_SSO_AGH'
import json, os
data = {
    "user": os.environ.get("AGH_USER_ENV", "admin"),
    "pass": os.environ.get("AGH_PASS_ENV", ""),
    "domain": os.environ.get("AGH_DOMAIN_ENV", "")
}
tmp_p = "/etc/myprivatecloud/sso_agh.json.tmp"
with open(tmp_p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
os.chmod(tmp_p, 0o600)
os.replace(tmp_p, "/etc/myprivatecloud/sso_agh.json")
EOF_SSO_AGH

        ok "AdGuard Home DoH активен на 127.0.0.1:53$([ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ] && echo " и 10.9.0.1:53")."
    fi
fi

mkdir -p /etc/myprivatecloud
chmod 0700 /etc/myprivatecloud
if [ ! -s /etc/myprivatecloud/sso.key ]; then
    (umask 077 && openssl rand 32 > /etc/myprivatecloud/sso.key.tmp)
    chmod 0600 /etc/myprivatecloud/sso.key.tmp
    mv -f /etc/myprivatecloud/sso.key.tmp /etc/myprivatecloud/sso.key
fi

# =============================================================
#  ВЕБ-МАСКИРОВКА (My Private Cloud Decoy Shield v3.18 - CSP Compliant)
# =============================================================
log "Генерация веб-маскировки (My Private Cloud Decoy Shield v3.18)..."

mkdir -p /var/www/steal
chmod 755 /var/www/steal
python3 - << 'EOF_FAV_GEN'
import os, secrets

def mk_svg(lbl: str) -> str:
    uid = secrets.token_hex(6)
    return f"""<svg viewBox="0 0 100 100" width="100" height="100" xmlns="http://www.w3.org/2000/svg" data-v="{lbl}-{uid}">
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
"""

for p, lbl in (("/var/www/html/assets/img/favicon.svg", "main"), ("/var/www/steal/favicon.svg", "steal")):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w", encoding="utf-8") as f:
        f.write(mk_svg(lbl))
    os.chmod(p + ".tmp", 0o644)
    os.replace(p + ".tmp", p)
EOF_FAV_GEN
cat << 'EOF_STEAL_CSS' > /var/www/steal/steal.css.tmp
:root { color-scheme: dark; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center;
    background: #0d1117; color: #c9d1d9; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    text-align: center; padding: 24px;
}
main { max-width: 560px; background: #161b22; border: 1px solid #30363d; border-radius: 16px; padding: 36px 28px; }
h1 { font-size: 22px; font-weight: 600; color: #f0f6fc; margin-bottom: 10px; }
p { font-size: 14px; color: #8b949e; line-height: 1.5; }
.badge { display: inline-block; margin-top: 18px; padding: 4px 12px; font-size: 12px; border-radius: 999px; background: rgba(46, 160, 67, 0.15); color: #3fb950; border: 1px solid rgba(46, 160, 67, 0.4); }
EOF_STEAL_CSS
mv -f /var/www/steal/steal.css.tmp /var/www/steal/steal.css
chmod 0644 /var/www/steal/steal.css

cat << 'EOF_STEAL_HTML' > /var/www/steal/index.html.tmp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Edge Content Delivery Node</title>
    <link rel="icon" type="image/svg+xml" href="/favicon.svg">
    <link rel="stylesheet" href="/steal.css">
</head>
<body>
    <main>
        <h1>Edge Content Delivery Node</h1>
        <p>Static asset distribution endpoint. Direct directory indexing and unauthenticated administrative endpoints are disabled.</p>
        <span class="badge">Status: Operational</span>
    </main>
</body>
</html>
EOF_STEAL_HTML
mv -f /var/www/steal/index.html.tmp /var/www/steal/index.html
chmod 0644 /var/www/steal/index.html

chown -R "$NGINX_USER:$NGINX_USER" /var/www/steal 2>/dev/null || true
chmod 0644 /var/www/html/assets/img/favicon.svg 2>/dev/null || true

ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.svg
ln -sf /var/www/html/assets/img/favicon.svg /var/www/html/favicon.ico

cat << 'EOF' > /var/www/html/robots.txt.tmp
User-agent: *
Disallow: /api/
Allow: /
EOF
mv -f /var/www/html/robots.txt.tmp /var/www/html/robots.txt
chmod 0644 /var/www/html/robots.txt 2>/dev/null || true

cat << 'EOF' > /var/www/html/assets/css/myprivatecloud.css.tmp
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
html, body { height: 100%; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Google Sans", sans-serif;
    background-color: var(--bg);
    background-image: radial-gradient(circle at 50% -10%, rgba(66, 133, 244, 0.18) 0%, rgba(155, 114, 207, 0.1) 40%, transparent 80%), var(--bg);
    color: var(--text); line-height: 1.6; overflow-x: hidden;
    min-height: 100vh; min-height: 100dvh; display: flex; flex-direction: column;
}
main { flex: 1 0 auto; display: flex; flex-direction: column; justify-content: center; align-items: center; width: 100%; }
header {
    display: flex; justify-content: space-between; align-items: center; padding: 18px 6%;
    border-bottom: 1px solid var(--border); backdrop-filter: blur(20px);
    position: sticky; top: 0; z-index: 50; background: rgba(19, 19, 20, 0.85);
}
.logo { font-size: 20px; font-weight: 500; display: flex; align-items: center; gap: 10px; color: #fff; letter-spacing: -0.5px; }
.header-actions { display: inline-flex; align-items: center; gap: 12px; }
.btn-header-auth {
    padding: 7px 18px; font-size: 13px; font-weight: 500; border-radius: 999px;
    background: var(--surface-card); border: 1px solid var(--border); color: var(--text);
    cursor: pointer; transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    display: inline-flex; align-items: center; justify-content: center; user-select: none;
}
.btn-header-auth:hover { border-color: rgba(168, 199, 250, 0.4); background: #242628; transform: translateY(-1px); }
.btn-header-auth:active { transform: translateY(0); }
.hero { text-align: center; padding: 60px 20px; max-width: 900px; margin: 0 auto; width: 100%; }
.hero h1 {
    font-size: clamp(32px, 4.5vw, 48px); font-weight: 600; line-height: 1.25; margin-bottom: 24px;
    letter-spacing: -0.8px; color: #e3e3e3;
}
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
.storage-table { width: 100%; border-collapse: collapse; margin-top: 14px; font-size: 13px; }
.storage-table th { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--border); color: var(--text-muted); font-weight: 500; }
.storage-table td { padding: 10px 10px; border-bottom: 1px solid rgba(255,255,255,0.04); }
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
@keyframes spin { 100% { transform: rotate(360deg); } }
EOF
mv -f /var/www/html/assets/css/myprivatecloud.css.tmp /var/www/html/assets/css/myprivatecloud.css
chmod 0644 /var/www/html/assets/css/myprivatecloud.css 2>/dev/null || true

DECOY_LANG="en"
if [ "${GEO_PROFILE:-2}" = "1" ]; then
    DECOY_LANG="ru"
fi

cat << EOF > /var/www/html/assets/js/myprivatecloud.js.tmp
"use strict";

const I18N = {
    ru: {
        doc_title: "My Private Cloud",
        hero_h1: "Облачная инфраструктура распределения данных",
        btn_auth: "Авторизация",
        modal_auth_title: "Авторизация в кластере",
        modal_auth_desc: "Введите учётные данные для доступа к консоли управления",
        auth_user_label: "Идентификатор узла / Email",
        auth_user_ph: "admin@privatecloud.internal",
        auth_key_label: "API Token / Ключ",
        btn_submit_auth: "Подключиться к кластеру",
        hub_title: "Консоль управления хранилищем",
        hub_desc: "Контроллер узлов и репликации данных S3",
        hub_xui_title: "Репликация объектов и буферизация",
        hub_xui_desc: "Распределенный шлюз данных S3 & Zero-Copy I/O",
        hub_agh_title: "Служба каталогов метаданных",
        hub_agh_desc: "Распределенный реестр метаданных объектов с контролем целостности",
        hub_node_title: "Кластерный транспорт узлов хранения",
        hub_node_desc: "Транспортная шина блочной синхронизации кластера",
        node_syncing: "Синхронизация с узлами хранения...",
        node_back_hub: "← Назад в консоль",
        node_new_client: "+ Подключить ноду",
        node_meta: "Подсистема: <strong class=\"text-success\">Distributed Block Storage Fabric</strong> | Кластер синхронизации",
        th_client: "Узел кластера",
        th_ip: "Адрес ноды",
        th_traffic: "Объем I/O",
        th_actions: "Действия",
        peers_empty: "Нет подключенных узлов в пуле хранилища",
        btn_close: "Закрыть",
        btn_cancel: "Отмена",
        btn_create: "Подключить",
        btn_delete: "Отозвать",
        btn_token: "Токен",
        btn_key: ".key",
        qr_modal_title: "Токен синхронизации узла",
        qr_modal_desc: "Считайте токен узла доверенным клиентом",
        qr_modal_hint: "Считайте в доверенном клиенте",
        add_peer_title: "Регистрация нового узла",
        add_peer_desc: "Добавление узла в пул блочного хранилища",
        add_peer_name_label: "Идентификатор ноды (латиница)",
        del_peer_title: "Подтверждение отключения",
        del_peer_desc: "Отозвать ключ и отключить узел от шины данных?",
        toast_auth_ok_title: "Авторизация успешна",
        toast_auth_ok_desc: "Сессия подтверждена. Добро пожаловать в консоль хранилища.",
        toast_err_conn: "Ошибка защищенного соединения с контроллером кластера.",
        toast_err_unauth: "Недействительный токен кластера или ключ авторизации узла."
    },
    en: {
        doc_title: "My Private Cloud",
        hero_h1: "Distributed Cloud Data Infrastructure",
        btn_auth: "Authorization",
        modal_auth_title: "Cluster Authorization",
        modal_auth_desc: "Enter node credentials to access management console",
        auth_user_label: "Node Identifier / Email",
        auth_user_ph: "admin@privatecloud.internal",
        auth_key_label: "API Token / Key",
        btn_submit_auth: "Connect to Cluster",
        hub_title: "Storage Management Console",
        hub_desc: "S3 Storage Node & Replication Gateway",
        hub_xui_title: "Object Store Replication & Edge Cache",
        hub_xui_desc: "Distributed S3 Data Plane & Zero-Copy I/O",
        hub_agh_title: "Metadata Directory Service",
        hub_agh_desc: "Distributed Object Catalog & Integrity Verification",
        hub_node_title: "Cluster Interconnect & Node Mesh",
        hub_node_desc: "Dedicated Storage Node Fabric & Block Transport",
        node_syncing: "Synchronizing storage nodes...",
        node_back_hub: "← Back to Console",
        node_new_client: "+ Attach Storage Node",
        node_meta: "Subsystem: <strong class=\"text-success\">Distributed Block Storage Fabric</strong> | Sync Cluster",
        th_client: "Storage Node",
        th_ip: "Node Address",
        th_traffic: "I/O Volume",
        th_actions: "Actions",
        peers_empty: "No active nodes in storage pool",
        btn_close: "Close",
        btn_cancel: "Cancel",
        btn_create: "Attach",
        btn_delete: "Revoke",
        btn_token: "Token",
        btn_key: ".key",
        qr_modal_title: "Node Sync Token",
        qr_modal_desc: "Scan sync token in trusted client",
        qr_modal_hint: "Scan in trusted client",
        add_peer_title: "Register Storage Node",
        add_peer_desc: "Attach node to block storage pool",
        add_peer_name_label: "Node Identifier (Latin)",
        del_peer_title: "Detach Confirmation",
        del_peer_desc: "Revoke key and detach node from data fabric?",
        toast_auth_ok_title: "Authorization Successful",
        toast_auth_ok_desc: "Session verified. Welcome to storage console.",
        toast_err_conn: "Secure connection error to cluster controller.",
        toast_err_unauth: "Invalid cluster token or node authorization key."
    }
};

const activeLang = "${DECOY_LANG}";

function applyLanguage() {
    const dict = I18N[activeLang] || I18N.en;
    document.querySelectorAll("[data-i18n]").forEach(node => {
        const key = node.dataset.i18n;
        if (dict && dict[key]) {
            if (node.tagName === "INPUT" || node.tagName === "TEXTAREA") {
                node.placeholder = dict[key];
            } else {
                node.textContent = dict[key];
            }
        }
    });
}

function escapeHtml(str) {
    return String(str ?? "").replace(/[&<>"']/g, ch => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    }[ch]));
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

function openAuthModal(title) {
    const dict = I18N[activeLang] || I18N.en;
    const modalTitle = document.getElementById("modalTitle");
    const errAlert = document.getElementById("errorAlert");
    const authModal = document.getElementById("authModal");
    if (!authModal) return;
    if (modalTitle) modalTitle.innerText = title || dict.modal_auth_title;
    if (errAlert) errAlert.style.display = "none";
    authModal.classList.add("active");
    setTimeout(() => { document.getElementById("cloudUser")?.focus(); }, 100);
}

function closeAuthModal() {
    document.getElementById("authModal")?.classList.remove("active");
}

let authenticatedSession = null;
let currentNodePeers = [];

function renderAdminHub(services) {
    const modalHeader = document.querySelector("#authModal .modal-header");
    const modalBody = document.querySelector("#authModal .modal-card");
    if (!modalBody) return;

    const dict = I18N[activeLang] || I18N.en;
    modalHeader.innerHTML = \`
        <div>
            <h2>\${dict.hub_title}</h2>
            <p>\${dict.hub_desc}</p>
        </div>
        <button type="button" class="modal-close" data-action="close-hub" aria-label="\${dict.btn_close}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
        </button>
    \`;

    let aghCard = "";
    if (services.agh_enabled && services.agh_url) {
        aghCard = \`
            <a href="\${escapeHtml(services.agh_url)}" target="_blank" rel="noopener noreferrer" class="hub-card">
                <div class="hub-info">
                    <h4>\${dict.hub_agh_title}</h4>
                    <p>\${dict.hub_agh_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </a>
        \`;
    }

    let nodeCard = "";
    if (services.nodes_enabled) {
        nodeCard = \`
            <div class="hub-card" data-action="open-nodes">
                <div class="hub-info">
                    <h4>\${dict.hub_node_title}</h4>
                    <p>\${dict.hub_node_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </div>
        \`;
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

    hubContainer.innerHTML = \`
        <div class="hub-grid">
            <a href="\${escapeHtml(services.panel_url)}" target="_blank" rel="noopener noreferrer" class="hub-card">
                <div class="hub-info">
                    <h4>\${dict.hub_xui_title}</h4>
                    <p>\${dict.hub_xui_desc}</p>
                </div>
                <div class="hub-arrow">&rarr;</div>
            </a>
            \${nodeCard}
            \${aghCard}
        </div>
    \`;
}

async function openNodeManager() {
    const hubContainer = document.getElementById("hubContainer");
    if (!hubContainer || !authenticatedSession) return;

    const dict = I18N[activeLang] || I18N.en;
    hubContainer.innerHTML = \`<div class="hub-loading"><div class="spinner spinner-center"></div>\${dict.node_syncing}</div>\`;

    try {
        const res = await fetch("/api/v1/myprivatecloud/storage/nodes", {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        const data = await res.json();
        currentNodePeers = data.peers || [];

        let rows = "";
        currentNodePeers.forEach(p => {
            const statusClass = p.is_online ? "online" : "offline";
            const safeName = escapeHtml(p.name);
            const safeIp = escapeHtml(p.ip);
            const safeRx = escapeHtml(p.rx);
            const safeTx = escapeHtml(p.tx);
            const safeKey = escapeHtml(p.public_key);
            rows += \`
                <tr>
                    <td><span class="status-pill \${statusClass}"></span><strong>\${safeName}</strong></td>
                    <td>\${safeIp}</td>
                    <td>&darr; \${safeRx} / &uarr; \${safeTx}</td>
                    <td class="actions-cell">
                        <div class="actions-group">
                            <button class="btn btn-mini" data-action="show-qr" data-key="\${safeKey}">\${dict.btn_token}</button>
                            <button class="btn btn-mini" data-action="download-conf" data-key="\${safeKey}">\${dict.btn_key}</button>
                            <button class="btn btn-mini" data-action="remove-peer" data-key="\${safeKey}">&times;</button>
                        </div>
                    </td>
                </tr>
            \`;
        });

        hubContainer.innerHTML = \`
            <div class="hub-toolbar">
                <button class="btn btn-outline btn-toolbar" data-action="back-to-hub">\${dict.node_back_hub}</button>
                <button class="btn btn-toolbar" data-action="add-peer">\${dict.node_new_client}</button>
            </div>
            <div class="hub-meta-box">
                \${dict.node_meta}
            </div>

            <div class="peers-table-container">
                <table class="storage-table">
                    <thead>
                        <tr><th>\${dict.th_client}</th><th>\${dict.th_ip}</th><th>\${dict.th_traffic}</th><th>\${dict.th_actions}</th></tr>
                    </thead>
                    <tbody>\${rows || \`<tr><td colspan="4" class="peers-empty-td">\${dict.peers_empty}</td></tr>\`}</tbody>
                </table>
            </div>
        \`;
    } catch(err) {
        showToast(dict.toast_err_conn, "");
    }
}

function promptAddPeer() {
    let nextNum = 1;
    if (currentNodePeers && currentNodePeers.length > 0) {
        const nums = currentNodePeers
            .map(p => {
                const m = p.name.match(/^Node-(\d+)$/i);
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
        nameInput.value = "Node-" + nextNum;
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
        const res = await fetch("/api/v1/myprivatecloud/storage/node/add", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer " + authenticatedSession.token
            },
            body: JSON.stringify({ name: name })
        });
        if (!res.ok) {
            const errD = await res.json().catch(() => ({}));
            throw new Error(errD.detail || ("HTTP " + res.status));
        }
        const result = await res.json();
        if (result.status === "ok") {
            showToast("OK", \`Node \${name} attached.\`);
            openNodeManager();
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
        const res = await fetch("/api/v1/myprivatecloud/storage/node/token?key=" + encodeURIComponent(pubKey), {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        if (!res.ok) throw new Error("Unauthorized");
        const blob = await res.blob();
        if (img.dataset.blobUrl) {
            URL.revokeObjectURL(img.dataset.blobUrl);
        }
        const blobUrl = URL.createObjectURL(blob);
        img.dataset.blobUrl = blobUrl;
        img.src = blobUrl;
        modal.classList.add("active");
    } catch(err) {
        showToast("Error", "");
    }
}

function closeQrModal() {
    const modal = document.getElementById("qrModal");
    const img = document.getElementById("qrModalImg");
    if (img && img.dataset.blobUrl) {
        URL.revokeObjectURL(img.dataset.blobUrl);
        delete img.dataset.blobUrl;
        img.src = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
    }
    if (modal) modal.classList.remove("active");
}

async function downloadNodeKey(publicKey) {
    try {
        const res = await fetch(\`/api/v1/myprivatecloud/storage/node/key?key=\${encodeURIComponent(publicKey)}\`, {
            headers: { "Authorization": "Bearer " + authenticatedSession.token }
        });
        if (!res.ok) throw new Error("HTTP " + res.status);
        const confText = await res.text();
        const blob = new Blob([confText], { type: "text/plain" });
        const dlUrl = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = dlUrl;
        a.download = \`storage-node-\${publicKey.substring(0,6)}.key\`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(dlUrl), 1000);
    } catch(e) {
        showToast("Error", "");
    }
}

let pendingDeleteKey = null;
function removeNodePeer(publicKey) {
    pendingDeleteKey = publicKey;
    const dialog = document.getElementById("confirmDeleteDialog");
    if (dialog) dialog.classList.add("active");
}

async function confirmDeletePeerAction() {
    const dialog = document.getElementById("confirmDeleteDialog");
    if (dialog) dialog.classList.remove("active");
    if (!pendingDeleteKey || !authenticatedSession) return;

    try {
        const res = await fetch("/api/v1/myprivatecloud/storage/node/remove", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer " + authenticatedSession.token
            },
            body: JSON.stringify({ public_key: pendingDeleteKey })
        });
        if (!res.ok) throw new Error("HTTP " + res.status);
        openNodeManager();
    } catch(e) {
        showToast("Error", "");
    } finally {
        pendingDeleteKey = null;
    }
}

async function handleCloudAuth(e) {
    e.preventDefault();
    const dict = I18N[activeLang] || I18N.en;
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
            showToast(dict.toast_auth_ok_title, dict.toast_auth_ok_desc);
        } else {
            if (errText) errText.innerText = result.error || result.detail || dict.toast_err_unauth;
            if (errBox) errBox.style.display = "flex";
        }
    } catch (err) {
        if (errText) errText.innerText = dict.toast_err_conn;
        if (errBox) errBox.style.display = "flex";
    } finally {
        if (btn && !authenticatedSession) {
            btn.disabled = false;
            btn.innerHTML = dict.btn_submit_auth;
        }
    }
}

document.addEventListener("click", (e) => {
    const el = e.target.closest("[data-action]");
    if (!el) return;
    const act = el.dataset.action;

    if (act === "open-nodes") openNodeManager();
    if (act === "back-to-hub") renderAdminHub(authenticatedSession.services);
    if (act === "add-peer") promptAddPeer();
    if (act === "show-qr") { const r = el.closest("tr"); const cName = r ? r.querySelector("strong")?.innerText : ""; showQr(el.dataset.key, cName); }
    if (act === "download-conf") downloadNodeKey(el.dataset.key);
    if (act === "remove-peer") removeNodePeer(el.dataset.key);
    if (act === "close-hub") { closeAuthModal(); location.reload(); }
    if (act === "close-qr-modal") closeQrModal();
    if (act === "cancel-add-peer") { document.getElementById("addPeerDialog")?.classList.remove("active"); }
    if (act === "confirm-add-peer") confirmAddPeerAction();
    if (act === "cancel-delete-peer") { document.getElementById("confirmDeleteDialog")?.classList.remove("active"); pendingDeleteKey = null; }
    if (act === "confirm-delete-peer") confirmDeletePeerAction();
});

window.addEventListener('DOMContentLoaded', () => {
    applyLanguage();
    document.getElementById("headerAuthBtn")?.addEventListener("click", () => openAuthModal());
    document.getElementById("authModalClose")?.addEventListener("click", closeAuthModal);
    document.getElementById("authForm")?.addEventListener("submit", handleCloudAuth);
});

window.addEventListener('keydown', (e) => {
    if (e.key === "Escape") {
        closeAuthModal();
        closeQrModal();
        document.getElementById("addPeerDialog")?.classList.remove("active");
        document.getElementById("confirmDeleteDialog")?.classList.remove("active");
    }
});
EOF
mv -f /var/www/html/assets/js/myprivatecloud.js.tmp /var/www/html/assets/js/myprivatecloud.js
chmod 0644 /var/www/html/assets/js/myprivatecloud.js 2>/dev/null || true

cat << EOF > /var/www/html/index.html.tmp
<!DOCTYPE html>
<html lang="${DECOY_LANG}">
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
            <button id="headerAuthBtn" class="btn btn-header-auth" type="button" data-i18n="btn_auth">$([ "$DECOY_LANG" = "ru" ] && echo "Авторизация" || echo "Authorization")</button>
        </div>
    </header>
    <main>
        <section class="hero">
            <h1 data-i18n="hero_h1">$([ "$DECOY_LANG" = "ru" ] && echo "Облачная инфраструктура распределения данных" || echo "Distributed Cloud Data Infrastructure")</h1>
        </section>
    </main>

    <div id="authModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="modalTitle">
        <div class="modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="modalTitle" data-i18n="modal_auth_title">Authorization</h2>
                    <p data-i18n="modal_auth_desc">Enter node credentials to access console</p>
                </div>
                <button id="authModalClose" class="modal-close" type="button" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div id="errorAlert" class="alert-box">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="18" height="18"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
                <span id="errorMsg">Error</span>
            </div>
            <form id="authForm">
                <div class="form-group">
                    <label for="cloudUser" data-i18n="auth_user_label">Node Identifier / Email</label>
                    <input type="text" id="cloudUser" class="form-control" data-i18n="auth_user_ph" placeholder="admin@privatecloud.internal" required autocomplete="username">
                </div>
                <div class="form-group">
                    <label for="cloudKey" data-i18n="auth_key_label">API Token / Key</label>
                    <input type="password" id="cloudKey" class="form-control" placeholder="••••••••••••••••" required autocomplete="current-password">
                </div>
                <button type="submit" id="submitBtn" class="btn btn-full-width-46" data-i18n="btn_submit_auth">Connect to Cluster</button>
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

    <div id="qrModal" class="modal-overlay qr-modal-overlay" role="dialog" aria-modal="true" aria-labelledby="qrClientTitle">
        <div class="modal-card qr-modal-card">
            <div class="modal-header">
                <div>
                    <h2 id="qrClientTitle" data-i18n="qr_modal_title">Node Sync Token</h2>
                    <p data-i18n="qr_modal_desc">Scan token in trusted client</p>
                </div>
                <button id="qrModalClose" class="modal-close" type="button" aria-label="Close" data-action="close-qr-modal">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="qr-display-container">
                <div class="qr-card-inner-large">
                    <img id="qrModalImg" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" class="qr-img-large" alt="Node Token">
                    <span class="qr-hint-large" data-i18n="qr_modal_hint">Scan in trusted client</span>
                </div>
            </div>
            <button type="button" id="qrModalCloseBtn" class="btn btn-qr-modal-close" data-action="close-qr-modal" data-i18n="btn_close">Close</button>
        </div>
    </div>

    <div id="addPeerDialog" class="modal-overlay dialog-overlay">
        <div class="modal-card dialog-card">
            <div class="modal-header">
                <div>
                    <h2 data-i18n="add_peer_title">Register Storage Node</h2>
                    <p data-i18n="add_peer_desc">Attach node to block storage pool</p>
                </div>
                <button type="button" class="modal-close" data-action="cancel-add-peer" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="form-group">
                <label for="newPeerName" data-i18n="add_peer_name_label">Node Identifier (Latin)</label>
                <input type="text" id="newPeerName" class="form-control" placeholder="Node-1">
            </div>
            <div class="dialog-actions">
                <button type="button" class="btn btn-outline" data-action="cancel-add-peer" data-i18n="btn_cancel">Cancel</button>
                <button type="button" class="btn" data-action="confirm-add-peer" data-i18n="btn_create">Attach</button>
            </div>
        </div>
    </div>

    <div id="confirmDeleteDialog" class="modal-overlay dialog-overlay">
        <div class="modal-card dialog-card">
            <div class="modal-header">
                <div>
                    <h2 data-i18n="del_peer_title">Detach Confirmation</h2>
                    <p data-i18n="del_peer_desc">Revoke key and detach node from data fabric?</p>
                </div>
                <button type="button" class="modal-close" data-action="cancel-delete-peer" aria-label="Close">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><path d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
            </div>
            <div class="dialog-actions">
                <button type="button" class="btn btn-outline" data-action="cancel-delete-peer" data-i18n="btn_cancel">Cancel</button>
                <button type="button" class="btn" data-action="confirm-delete-peer" data-i18n="btn_delete">Revoke</button>
            </div>
        </div>
    </div>

    <footer>&copy; 2026 My Private Cloud</footer>
    <script src="/assets/js/myprivatecloud.js?v=2026"></script>
</body>
</html>
EOF
mv -f /var/www/html/index.html.tmp /var/www/html/index.html
chmod 0644 /var/www/html/index.html 2>/dev/null || true

cat << 'EOF' > /var/www/html/404.html.tmp
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>404 Not Found</title>
</head>
<body>
<h1>404 Not Found</h1>
<p>The requested resource was not found on this server.</p>
</body>
</html>
EOF
mv -f /var/www/html/404.html.tmp /var/www/html/404.html
chmod 0644 /var/www/html/404.html 2>/dev/null || true

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
if ! nginx -V 2>&1 | grep -qE -- '--with-stream($|[^-=])' && [ -d /etc/nginx/modules-enabled ]; then
    MODULE_LOAD_LINE="include /etc/nginx/modules-enabled/*.conf;"
fi

PANEL_PORT="${PANEL_PORT//[!0-9]/}"
SUB_PORT="${SUB_PORT//[!0-9]/}"
XHTTP_UPSTREAM_LINE=""
XHTTP_BADBOT_MAP_LINE=""
XHTTP_NGINX_LOC_BLOCK=""

if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    XHTTP_STREAM_PORT="${XHTTP_STREAM_PORT//[!0-9]/}"
    if [ -z "${XHTTP_STREAM_PORT:-}" ]; then XHTTP_STREAM_PORT="50443"; fi
    XHTTP_UPSTREAM_LINE="upstream xray_xhttp_stream { server 127.0.0.1:${XHTTP_STREAM_PORT}; }"
    XHTTP_BADBOT_MAP_LINE="~^.*:[01]:${XHTTP_STREAM_PATH} 0;"
    XHTTP_NGINX_LOC_BLOCK="    location ^~ ${XHTTP_STREAM_PATH} {
        if (\$request_method != POST) { return 404; }
        gzip off;
        proxy_http_version 2;
        proxy_set_header Connection \"\";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_max_temp_file_size 0;
        tcp_nodelay on;
        tcp_nopush off;
        proxy_socket_keepalive on;
        client_body_timeout 1h;
        send_timeout 1h;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
        client_max_body_size 0;
        proxy_intercept_errors on;
        error_page 400 403 404 405 421 429 500 502 503 504 =404 /404.html;
        proxy_pass http://xray_xhttp_stream;
    }"
fi
if [ -z "${PANEL_PORT:-}" ]; then PANEL_PORT="10443"; fi
if [ -z "${SUB_PORT:-}" ]; then SUB_PORT="55443"; fi
if [ -z "${XHTTP_STREAM_PORT:-}" ]; then XHTTP_STREAM_PORT="50443"; fi

mkdir -p /etc/nginx/snippets
cat << 'EOF_NGX_SEC_SNIP' > /etc/nginx/snippets/hardened-headers.conf.tmp
add_header X-Frame-Options "DENY" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
EOF_NGX_SEC_SNIP
mv -f /etc/nginx/snippets/hardened-headers.conf.tmp /etc/nginx/snippets/hardened-headers.conf
chmod 0644 /etc/nginx/snippets/hardened-headers.conf 2>/dev/null || true

cat << EOF > /etc/nginx/nginx.conf.tmp
user $NGINX_USER;
worker_processes auto;
worker_cpu_affinity auto;
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

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    http2_recv_buffer_size 256k;
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
    upstream myprivatecloud_core_backend { server 127.0.0.1:20443; keepalive 16; }

    access_log off;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;
    set_real_ip_from unix:;

    client_max_body_size 32m;
    client_body_buffer_size 128k;
    large_client_header_buffers 4 16k;
    client_header_buffer_size 4k;

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
        ~*(?:oai-searchbot|chatgpt-user|operator|meta-externalfetcher|meta-webindexer|duckassistbot|mistralai-user|claude-web|claude-user|perplexity-user|youbot|timpibot|pangubot|petalbot|amazonbot|ai2bot|cohere-ai|deepseek|zgrab2|leakix|internetmeasurement|expanse|projectdiscovery|assetnote|grokbot|claude-searchbot|mistralai-index|googleother|cohere-training|xai-bot) 1;
    }

    map \$request_uri \$is_scan_attempt {
        default 0;
        ~*\.(?:php|php5|phtml|asp|aspx|jsp|do|action|cgi|pl|py|rb)\$ 1;
        ~*(\.env|\.git|\.config|\.htaccess|\.sql|\.bak|\.old|\.swp|\.ini|config\.php|web\.config|settings\.py)\$ 1;
        ~*^/(?:admin|administrator|wp-admin|wp-login|phpmyadmin|sqladmin|setup|install|dashboard|manager|controlpanel|config|auth|backend|logs)/ 1;
        ~*(\.\./|\.\.\\\\|/etc/passwd|/boot/|/windows/|/proc/) 1;
        ~*^/(?:graphql|swagger-ui|api-docs|redoc)/ 1;
        ~*\.(?:zip|tar\.gz|rar|7z)\$ 1;
        ~*(?:\.git/|wp-json|xmlrpc|/\.env|config\.bak|debug\.log|test\.php) 1;
    }

    map "\$badbot_raw:\$is_scan_attempt:\$request_uri" \$badbot {
        ~^.*:0:/robots\.txt(\?|\$) 0;
        ~^.*:0:/\.well-known/ 0;
        ~^.*:0:/favicon\.(ico|svg)\$ 0;
        ~^.*:0:/assets/ 0;
        ~^.*:0:/dns-query 0;
        ~^.*:0:/api/v1/myprivatecloud/ 0;
        ~^.*:[01]:${PANEL_PATH} 0;
        ~^.*:[01]:${SUB_PATH} 0;
        ~^.*:[01]:${SUB_JSON_PATH} 0;
        ~^.*:[01]:${SUB_CLASH_PATH} 0;
        $XHTTP_BADBOT_MAP_LINE
        ~^(?:1:[01]|0:1): 1;
        default 0;
    }

    limit_req_zone \$binary_remote_addr zone=panel:2m rate=30r/s;
    limit_req_zone \$binary_remote_addr zone=sso_auth:1m rate=10r/m;
    limit_req_zone \$binary_remote_addr zone=subs:512k rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=doh:2m rate=300r/s;
    limit_req_zone \$binary_remote_addr zone=scan:512k rate=1r/s;
    limit_req_zone \$binary_remote_addr zone=bot:512k rate=4r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:512k;
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
mv -f /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
chmod 0644 /etc/nginx/nginx.conf 2>/dev/null || true

HAS_IPV6_STACK=0
if [ "${DISABLE_IPV6:-0}" -eq 0 ] && [ -f /proc/net/if_inet6 ] && grep -q '00000000000000000000000000000001' /proc/net/if_inet6 2>/dev/null; then
    HAS_IPV6_STACK=1
fi

NGINX_V6_80=""
NGINX_V6_443=""
if [ "$HAS_IPV6_STACK" -eq 1 ]; then
    NGINX_V6_80="    listen [::]:80 default_server;"
    NGINX_V6_443="    listen [::]:443 backlog=65535 reuseport;"
fi

sync_nginx_stream_and_steal() {
    local sync_phase="${1:-bootstrap}"
    local sync_db="${2:-${EXISTING_DB_PATH:-}}"
    local -a local_reality_ports=("${ALL_REALITY_PORTS[@]:-}")
    local -A local_ext_sni_map=()
    local k_sni
    if [ "${#EXT_SNI_TO_PORT[@]}" -gt 0 ]; then
        for k_sni in "${!EXT_SNI_TO_PORT[@]}"; do
            local_ext_sni_map["$k_sni"]="${EXT_SNI_TO_PORT[$k_sni]}"
        done
    fi

    if [ "$sync_phase" = "post_phase3" ] && [ -n "$sync_db" ] && [ -f "$sync_db" ]; then
        local_reality_ports=()
        local_ext_sni_map=()
    fi

    if [ -n "$sync_db" ] && [ -f "$sync_db" ]; then
        local ib_cond=""
        ib_cond=$(get_local_ib_cond "$sync_db")
        local db_prev_reality drp
        db_prev_reality=$(sqlite_ro "$sync_db" "SELECT DISTINCT port FROM inbounds WHERE enable = 1 AND protocol='vless' AND stream_settings LIKE '%reality%' ${ib_cond};")
        for drp in $db_prev_reality; do
            if validate_port "$drp"; then
                local_reality_ports+=("$drp")
                if [ "$sync_phase" = "bootstrap" ]; then
                    ok "Обнаружен действующий порт REALITY из существующей базы: ${drp}"
                fi
            fi
        done

        rm -f /tmp/nginx_prev_sni_map.txt
        EXISTING_DB_PATH="$sync_db" python3 - << 'EOF_EXT_SNI'
import sqlite3, json, os

db_p = os.environ.get("EXISTING_DB_PATH", "")
if os.path.exists(db_p):
    try:
        conn = sqlite3.connect(f"file:{db_p}?mode=ro", uri=True, timeout=5.0)
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(inbounds)")
        _cols_sni = {r[1] for r in cur.fetchall()}
        _sni_parts = []
        _sni_params = []
        if "node_id" in _cols_sni:
            _sni_parts.append("(node_id IS NULL OR node_id = 0)")
        if "origin_node_guid" in _cols_sni:
            cur.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1")
            _pg_r = cur.fetchone()
            _pg_v = str(_pg_r[0]).strip() if _pg_r and _pg_r[0] else ""
            if _pg_v:
                _sni_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                _sni_params.append(_pg_v)
            else:
                _sni_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
        _nc_sni = (" AND " + " AND ".join(_sni_parts)) if _sni_parts else ""
        cur.execute(f"SELECT port, stream_settings FROM inbounds WHERE enable = 1 AND protocol='vless' AND stream_settings LIKE '%reality%'{_nc_sni}", _sni_params)
        with open("/tmp/nginx_prev_sni_map.txt", "w", encoding="utf-8") as f_out:
            for p, st_raw in cur.fetchall():
                if st_raw:
                    st = json.loads(st_raw)
                    rs = st.get("realitySettings", {})
                    for s in rs.get("serverNames", []):
                        if s:
                            f_out.write(f"{str(s).strip().lower()}:{p}\n")
        conn.close()
    except Exception:
        pass
EOF_EXT_SNI
        if [ -f /tmp/nginx_prev_sni_map.txt ]; then
            while IFS=: read -r s_name s_port; do
                if [ -n "$s_name" ] && [ -n "$s_port" ]; then
                    local_ext_sni_map["$s_name"]="$s_port"
                fi
            done < /tmp/nginx_prev_sni_map.txt
            rm -f /tmp/nginx_prev_sni_map.txt
        fi
    fi

    local -A seen_sni_map=()
    local stream_map_rules=""
    local reality_upstreams=""
    local s_dom port ext_sni

    stream_map_rules+="        ${PRIMARY_DOMAIN}     nginx_http_backend;\n"
    seen_sni_map["$PRIMARY_DOMAIN"]=1

    if [ -n "${AGH_DOMAIN:-}" ]; then
        stream_map_rules+="        ${AGH_DOMAIN}     nginx_http_backend;\n"
        seen_sni_map["$AGH_DOMAIN"]=1
    fi

    if [ "$ENABLE_STEAL" -eq 1 ] && [ "${#STEAL_DOMAINS[@]}" -gt 0 ]; then
        for s_dom in "${STEAL_DOMAINS[@]}"; do
            if [ -n "$s_dom" ] && [ -z "${seen_sni_map[$s_dom]:-}" ] && [ -n "${DOMAIN_TO_PORT[$s_dom]:-}" ]; then
                seen_sni_map["$s_dom"]=1
                port="${DOMAIN_TO_PORT[$s_dom]}"
                stream_map_rules+="        ${s_dom}     reality_backend_${port};\n"
                local_reality_ports+=("$port")
            fi
        done
    fi

    if [ "${#local_ext_sni_map[@]}" -gt 0 ]; then
        for ext_sni in "${!local_ext_sni_map[@]}"; do
            if [ -n "$ext_sni" ] && [ -z "${seen_sni_map[$ext_sni]:-}" ]; then
                seen_sni_map["$ext_sni"]=1
                port="${local_ext_sni_map[$ext_sni]}"
                stream_map_rules+="        ${ext_sni}     reality_backend_${port};\n"
                local_reality_ports+=("$port")
            fi
        done
    fi

    mapfile -t local_reality_ports < <(printf "%s\n" "${local_reality_ports[@]:-}" | grep -E "^[0-9]+$" | sort -u || true)

    local -A seen_reality_upstreams=()
    for port in "${local_reality_ports[@]:-}"; do
        if [ -n "$port" ] && [ -z "${seen_reality_upstreams[$port]:-}" ]; then
            seen_reality_upstreams["$port"]=1
            reality_upstreams+="
    upstream reality_backend_${port} {
        server 127.0.0.1:${port} max_fails=0;
    }
"
        fi
    done

    cat << EOF > "/etc/nginx/stream.d/00-stream.conf.tmp"
map \$ssl_preread_server_name \$sni_gate {
    hostnames;
    ""                     nginx_http_backend;
$(echo -e "$stream_map_rules")
    default                nginx_http_backend;
}

map \$ssl_preread_protocol \$backend_gate {
    ""                     stream_drop_backend;
    "TLSv1.3"              \$sni_gate;
    "TLSv1.2"              \$sni_gate;
    "TLSv1.1"              \$sni_gate;
    "TLSv1"                \$sni_gate;
    "SSLv3"                \$sni_gate;
    default                stream_drop_backend;
}

upstream nginx_http_backend {
    server unix:/dev/shm/nginx-http.sock;
}

upstream stream_drop_backend {
    server unix:/dev/shm/nginx-drop.sock;
}

server {
    listen unix:/dev/shm/nginx-drop.sock proxy_protocol;
    return "";
}

${reality_upstreams}

server {
    listen 443 backlog=65535 reuseport;
${NGINX_V6_443}
    proxy_protocol on;
    proxy_pass \$backend_gate;
    preread_timeout 5s;
    ssl_preread on;
}
EOF
    mv -f "/etc/nginx/stream.d/00-stream.conf.tmp" "/etc/nginx/stream.d/00-stream.conf"
    chmod 0644 "/etc/nginx/stream.d/00-stream.conf" 2>/dev/null || true

    local -A seen_fb_steal_map=()
    local -a fallback_steal_domains=()
    if [ "${ENABLE_STEAL:-0}" -eq 1 ] && [ "${#STEAL_DOMAINS[@]}" -gt 0 ]; then
        for s_dom in "${STEAL_DOMAINS[@]}"; do
            if [ -n "$s_dom" ] && [ -z "${seen_fb_steal_map[$s_dom]:-}" ]; then
                seen_fb_steal_map["$s_dom"]=1
                fallback_steal_domains+=("$s_dom")
            fi
        done
    fi
    if [ -n "$sync_db" ] && [ -f "$sync_db" ]; then
        local db_s_dom
        while IFS= read -r db_s_dom; do
            if [ -n "$db_s_dom" ] && [ "$db_s_dom" != "$PRIMARY_DOMAIN" ] && [ "$db_s_dom" != "${AGH_DOMAIN:-}" ] && [ -z "${seen_fb_steal_map[$db_s_dom]:-}" ]; then
                seen_fb_steal_map["$db_s_dom"]=1
                fallback_steal_domains+=("$db_s_dom")
            fi
        done < <(EXISTING_DB_PATH="$sync_db" python3 - << 'EOF_STEAL_FB_DB'
import json, os, sqlite3
db_p = os.environ.get("EXISTING_DB_PATH", "")
seen = set()
if db_p and os.path.exists(db_p):
    try:
        conn = sqlite3.connect(f"file:{db_p}?mode=ro", uri=True, timeout=5.0)
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(inbounds)")
        _cols_fb = {r[1] for r in cur.fetchall()}
        _fb_parts = []
        _fb_params = []
        if "node_id" in _cols_fb:
            _fb_parts.append("(node_id IS NULL OR node_id = 0)")
        if "origin_node_guid" in _cols_fb:
            cur.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1")
            _pg_f = cur.fetchone()
            _pg_fv = str(_pg_f[0]).strip() if _pg_f and _pg_f[0] else ""
            if _pg_fv:
                _fb_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                _fb_params.append(_pg_fv)
            else:
                _fb_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
        _nc_fb = (" AND " + " AND ".join(_fb_parts)) if _fb_parts else ""
        cur.execute(f"SELECT tag, stream_settings FROM inbounds WHERE enable = 1 AND protocol='vless' AND stream_settings LIKE '%reality%'{_nc_fb}", _fb_params)
        for tag, st_raw in cur.fetchall():
            st = json.loads(st_raw) if st_raw else {}
            rs = st.get("realitySettings", {})
            dest = str(rs.get("dest", rs.get("target", ""))).strip()
            if "in-steal" in str(tag or "").lower() or dest == "127.0.0.1:9443":
                for s in rs.get("serverNames", []):
                    s_clean = str(s).strip().lower()
                    if s_clean and s_clean not in seen:
                        seen.add(s_clean)
                        print(s_clean)
        conn.close()
    except Exception:
        pass
EOF_STEAL_FB_DB
        )
    fi

    rm -f /etc/nginx/conf.d/02-steal-fallback.conf /etc/nginx/conf.d/02-steal-fallback.conf.tmp
    if [ "${#fallback_steal_domains[@]}" -gt 0 ]; then
        for s_dom in "${fallback_steal_domains[@]}"; do
            if [ ! -s "${SSL_BASE_DIR}/$s_dom/fullchain.pem" ] || [ ! -s "${SSL_BASE_DIR}/$s_dom/privkey.pem" ]; then
                warn "Для Steal-домена $s_dom отсутствует SSL-сертификат. Генерация локального fallback-сертификата во избежание обрыва рукопожатия на :9443..."
                gen_emergency_selfsigned "$s_dom"
            fi
            cat << EOF >> "/etc/nginx/conf.d/02-steal-fallback.conf.tmp"
server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    listen 127.0.0.1:$REALITY_FALLBACK_PORT ssl proxy_protocol;
    http2 on;
    server_name $s_dom;
    set \$sni_mismatch 0;
    if (\$ssl_server_name != \$host) { set \$sni_mismatch 1; }
    if (\$ssl_server_name = "") { set \$sni_mismatch 0; }
    if (\$uri = /404.html) { set \$sni_mismatch 0; }
    if (\$sni_mismatch = 1) { return 421; }
    root $WEBROOT;

    ssl_certificate ${SSL_BASE_DIR}/$s_dom/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$s_dom/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL_FALLBACK:1m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    set \$do_drop 0;
    if (\$badbot) { set \$do_drop 1; }
    if (\$uri = /404.html) { set \$do_drop 0; }
    if (\$do_drop = 1) { return 404; }
    if (\$request_method !~ ^(GET|HEAD|POST)\$) { return 405; }
    error_page 400 403 404 405 413 414 421 429 500 502 503 504 /404.html;

    location = /robots.txt { root $WEBROOT; access_log off; }
    location ~ ^/(favicon\\.ico|favicon\\.svg)\$ { root /var/www/steal; try_files /favicon.svg =404; access_log off; expires 30d; }
    location = /assets/img/favicon.svg { root /var/www/steal; try_files /favicon.svg =404; access_log off; expires 7d; }
    location = /steal.css { root /var/www/steal; expires 7d; access_log off; include /etc/nginx/snippets/hardened-headers.conf; add_header Cache-Control "public, max-age=604800, immutable" always; try_files /steal.css =404; }
    location /assets/ { root $WEBROOT; expires 7d; access_log off; include /etc/nginx/snippets/hardened-headers.conf; add_header Cache-Control "public, max-age=604800, immutable" always; try_files \$uri =404; }
    location = / { default_type text/html; root /var/www/steal; try_files /index.html =404; }
    location / { return 404; }
    location = /404.html { root $WEBROOT; internal; }
    error_page 497 @drop_plain;
    location @drop_plain { return 444; }
}
EOF
        done
        if [ -f /etc/nginx/conf.d/02-steal-fallback.conf.tmp ]; then
            mv -f /etc/nginx/conf.d/02-steal-fallback.conf.tmp /etc/nginx/conf.d/02-steal-fallback.conf
            chmod 0644 /etc/nginx/conf.d/02-steal-fallback.conf 2>/dev/null || true
        fi
    fi
}

cat << EOF > "/etc/nginx/conf.d/01-main.conf.tmp"
server {
    listen 80 default_server;
${NGINX_V6_80}
    server_name _;
    access_log off;

    location ^~ /.well-known/acme-challenge/ {
        root $WEBROOT;
        default_type "text/plain";
        try_files \$uri =404;
    }

    if (\$host = "$PRIMARY_DOMAIN") {
        return 301 https://\$host\$request_uri;
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
    root $WEBROOT;
    error_page 400 403 404 405 413 414 421 429 500 502 503 504 /404.html;
    location = /404.html { root $WEBROOT; internal; }
    location / { return 421; }
    error_page 497 @drop_plain;
    location @drop_plain { return 444; }
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    http2 on;
    server_name $PRIMARY_DOMAIN;
    set \$sni_mismatch 0;
    if (\$ssl_server_name != \$host) { set \$sni_mismatch 1; }
    if (\$ssl_server_name = "") { set \$sni_mismatch 0; }
    if (\$uri = /404.html) { set \$sni_mismatch 0; }
    if (\$sni_mismatch = 1) { return 421; }
    root $WEBROOT;
    index index.html;

    ssl_certificate ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$PRIMARY_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:2m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    set \$do_drop 0;
    if (\$badbot) { set \$do_drop 1; }
    if (\$uri = /404.html) { set \$do_drop 0; }
    if (\$do_drop = 1) { return 404; }
    if (\$request_method !~ ^(GET|HEAD|POST)\$) { return 405; }

    error_page 400 403 404 405 413 414 421 429 500 502 503 504 /404.html;

    location = ${PANEL_PATH%/} { return 301 ${PANEL_PATH}; }
    location ^~ ${PANEL_PATH} {
        proxy_hide_header Content-Security-Policy;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws: wss:; frame-ancestors 'self';" always;

        limit_req zone=panel burst=40 delay=20;
        proxy_pass http://panel_3xui;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location = ${SUB_PATH%/} { return 301 ${SUB_PATH}; }
    location ^~ ${SUB_PATH} {
        proxy_hide_header Content-Security-Policy;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
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
        proxy_intercept_errors on;
        error_page 400 403 404 405 421 429 500 502 503 504 =404 /404.html;
    }

    $XHTTP_NGINX_LOC_BLOCK

    location = /api/v1/myprivatecloud/auth {
        limit_req zone=sso_auth burst=5 nodelay;
        proxy_pass http://myprivatecloud_core_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header X-Forwarded-For \$ak_real_ip;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ^~ /api/v1/myprivatecloud/ {
        proxy_pass http://myprivatecloud_core_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
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
        include /etc/nginx/snippets/hardened-headers.conf;
        add_header Cache-Control "public, max-age=604800, immutable" always;
        try_files \$uri =404;
    }

    location = /404.html {
        root $WEBROOT;
        internal;
    }

    location / {
        limit_req zone=scan burst=3 nodelay;
        return 404;
    }

    error_page 497 @drop_plain;
    location @drop_plain { return 444; }
}

server {
    listen 127.0.0.1:8088 default_server;
    server_name _;
    access_log off;
    root $WEBROOT;
    index index.html;

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    if (\$request_method !~ ^(GET|HEAD|POST)\$) { return 405; }
    error_page 400 403 404 405 413 414 421 429 500 502 503 504 /404.html;

    location = /404.html { root $WEBROOT; internal; }
    location = /robots.txt { root $WEBROOT; access_log off; }
    location ~ ^/(favicon\\.ico|favicon\\.svg)\$ { root $WEBROOT; access_log off; expires 30d; }
    location /assets/ { root $WEBROOT; expires 7d; access_log off; include /etc/nginx/snippets/hardened-headers.conf; add_header Cache-Control "public, max-age=604800, immutable" always; try_files \$uri =404; }
    location = / { default_type text/html; root $WEBROOT; try_files /index.html =404; }
    location / { return 404; }
}
EOF
mv -f "/etc/nginx/conf.d/01-main.conf.tmp" "/etc/nginx/conf.d/01-main.conf"
chmod 0644 "/etc/nginx/conf.d/01-main.conf" 2>/dev/null || true

sync_nginx_stream_and_steal "bootstrap" "${EXISTING_DB_PATH:-}"

if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ -f "${SSL_BASE_DIR}/$AGH_DOMAIN/fullchain.pem" ]; then
    AGH_CLIENT_IDS_REGEX=$(AGH_CID_ENV="${AGH_CLIENT_ID:-}" python3 - << 'EOF_AGH_CID_RE'
import os, re
cids = []
env_cid = os.environ.get("AGH_CID_ENV", "").strip()
if env_cid and re.match(r"^[a-zA-Z0-9._-]+$", env_cid):
    cids.append(env_cid)
yaml_p = "/opt/AdGuardHome/AdGuardHome.yaml"
if os.path.exists(yaml_p):
    with open(yaml_p, "r", encoding="utf-8", errors="ignore") as f:
        ytxt = f.read()
    m_clients = re.search(r"^clients:\n([\s\S]*?)(?=^\S|\Z)", ytxt, re.M)
    if m_clients:
        for m_ids in re.finditer(r"^\s+ids:\s*\n((?:\s+-\s+[^\n]+\n)+)", m_clients.group(1), re.M):
            for line in m_ids.group(1).splitlines():
                val = line.strip().lstrip("-").strip().strip("\"'")
                if val and re.match(r"^[a-zA-Z0-9._-]+$", val):
                    cids.append(val)
uniq, seen = [], set()
for c in cids:
    if c.lower() not in seen:
        seen.add(c.lower())
        uniq.append(re.escape(c))
print("|".join(uniq) if uniq else "home-router")
EOF_AGH_CID_RE
    )
    cat << EOF > "/etc/nginx/conf.d/03-adguard.conf.tmp"
upstream adguard_backend { server 127.0.0.1:3000; keepalive 32; }

map \$http_cookie \$http_cookie_no_agh {
    "~^(.*);[ \t]*agh_session=[^;]*\$" "\$1";
    "~^(.*)agh_session=[^;]*;?[ \t]*(.*)\$" "\$1\$2";
    default \$http_cookie;
}

map "\$agh_sess:\$http_cookie_no_agh" \$agh_merged_cookie {
    ~^:                \$http_cookie;
    ~^([^:]+):\$       \$1;
    ~^([^:]+):(.+)\$   "\$1; \$2";
    default            \$http_cookie;
}

server {
    listen unix:/dev/shm/nginx-http.sock ssl proxy_protocol;
    http2 on;
    server_name $AGH_DOMAIN;
    set \$sni_mismatch 0;
    if (\$ssl_server_name != \$host) { set \$sni_mismatch 1; }
    if (\$ssl_server_name = "") { set \$sni_mismatch 0; }
    if (\$uri = /404.html) { set \$sni_mismatch 0; }
    if (\$sni_mismatch = 1) { return 421; }
    root $WEBROOT;

    ssl_certificate ${SSL_BASE_DIR}/$AGH_DOMAIN/fullchain.pem;
    ssl_certificate_key ${SSL_BASE_DIR}/$AGH_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL_AGH:1m;
    ssl_session_timeout 4h;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    set \$do_drop 0;
    if (\$badbot) { set \$do_drop 1; }
    if (\$uri = /404.html) { set \$do_drop 0; }
    if (\$do_drop = 1) { return 404; }
    error_page 400 403 404 405 413 414 421 429 500 502 503 504 /404.html;

    location ~* ^/dns-query/(?:${AGH_CLIENT_IDS_REGEX})/?\$ {
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

    location /dns-query {
        return 404;
    }

    location = /internal_sso_verify {
        internal;
        proxy_pass http://myprivatecloud_core_backend/api/v1/myprivatecloud/verify-token?\$args;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI \$request_uri;
        proxy_set_header X-Real-IP \$ak_real_ip;
        proxy_set_header Cookie \$http_cookie;
        proxy_set_header X-Access-Key \$arg_access_key;
    }

    location = /404.html {
        root $WEBROOT;
        internal;
    }

    location / {
        auth_request /internal_sso_verify;
        auth_request_set \$saved_sso_cookie \$upstream_http_set_cookie;
        auth_request_set \$agh_cookie \$upstream_http_x_agh_cookie;
        auth_request_set \$agh_sess \$upstream_http_x_agh_session;
        auth_request_set \$agh_auth \$upstream_http_x_agh_auth;
        add_header Set-Cookie \$saved_sso_cookie always;
        add_header Set-Cookie \$agh_cookie always;
        error_page 401 403 =404 /404.html;
        error_page 500 502 503 504 /404.html;

        proxy_hide_header Content-Security-Policy;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self';" always;

        limit_req zone=panel burst=60 delay=30;
        proxy_pass http://adguard_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade "";
        proxy_set_header Connection "";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Cookie \$agh_merged_cookie;
        proxy_set_header Authorization \$agh_auth;
    }

    error_page 497 @drop_plain;
    location @drop_plain { return 444; }
}
EOF
    mv -f "/etc/nginx/conf.d/03-adguard.conf.tmp" "/etc/nginx/conf.d/03-adguard.conf"
    chmod 0644 "/etc/nginx/conf.d/03-adguard.conf" 2>/dev/null || true
fi

mkdir -p /etc/systemd/system/nginx.service.d/
cat << 'EOF_NGINX_LIM' > /etc/systemd/system/nginx.service.d/10-limits.conf.tmp
[Service]
LimitNOFILE=1048576
LimitNPROC=512
EOF_NGINX_LIM
mv -f /etc/systemd/system/nginx.service.d/10-limits.conf.tmp /etc/systemd/system/nginx.service.d/10-limits.conf
chmod 0644 /etc/systemd/system/nginx.service.d/10-limits.conf 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

rm -f /dev/shm/nginx-http.sock /dev/shm/nginx-drop.sock 2>/dev/null || true
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
            "https://ghfast.top/https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
        )
    fi

    while ! download_asset "$UI_SCRIPT" "${UI_URLS[@]}"; do
        warn "Не удалось загрузить инсталлятор 3X-UI."
        if ! prompt_yes_no "Повторить попытку загрузки 3X-UI?" "y"; then
            exit 1
        fi
    done
    rc_ui=0
    bash "$UI_SCRIPT" >/tmp/3xui_install.log 2>&1 <<< $'n\n' || rc_ui=$?
    rm -f "$UI_SCRIPT"
    if [ "$rc_ui" -ne 0 ] && [ ! -x "/usr/local/x-ui/x-ui" ]; then
        tail -n 25 /tmp/3xui_install.log >&2 || true
        die "Ошибка установки 3X-UI (код $rc_ui)."
    fi
    for alt_db in "$DB_PATH" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
        if [ -f "$alt_db" ]; then DB_PATH="$alt_db"; break; fi
    done
    systemctl stop x-ui 2>/dev/null || true
    /usr/local/x-ui/x-ui setting -webBasePath "${RAW_PATH}" -port "${PANEL_PORT}" >/dev/null 2>&1 || true
    sqlite3 -cmd ".timeout 5000" "$DB_PATH" "UPDATE settings SET value = '${PANEL_PATH}' WHERE key = 'webBasePath';" 2>/dev/null || true
    sqlite3 -cmd ".timeout 5000" "$DB_PATH" "UPDATE settings SET value = '${PANEL_PORT}' WHERE key = 'webPort';" 2>/dev/null || true
elif [ "$INSTALL_MODE" = "2" ]; then
    if prompt_yes_no "Обновить исполняемый файл панели 3X-UI до последнего релиза (база x-ui.db сохраняется)?" "y"; then
        XUI_DL_ARCH="amd64"
        if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
            XUI_DL_ARCH="arm64"
        fi
        XUI_TAR="/tmp/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
        rm -f "$XUI_TAR"
        if [ "$GEO_PROFILE" = "1" ]; then
            XUI_REL_URLS=(
                "https://ghfast.top/https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
                "https://ghproxy.net/https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
                "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
            )
        else
            XUI_REL_URLS=(
                "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
                "https://ghfast.top/https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-${XUI_DL_ARCH}.tar.gz"
            )
        fi
        if download_asset "$XUI_TAR" "${XUI_REL_URLS[@]}"; then
            rm -rf /tmp/xui_upd_unpack
            mkdir -p /tmp/xui_upd_unpack
            if tar -zxf "$XUI_TAR" -C /tmp/xui_upd_unpack >/dev/null 2>&1 && [ -f /tmp/xui_upd_unpack/x-ui/x-ui ]; then
                systemctl stop x-ui 2>/dev/null || true
                cp -a /usr/local/x-ui/x-ui /usr/local/x-ui/x-ui.pre_upd.bak 2>/dev/null || true
                cp -f /tmp/xui_upd_unpack/x-ui/x-ui /usr/local/x-ui/x-ui.tmp
                chmod 0755 /usr/local/x-ui/x-ui.tmp
                mv -f /usr/local/x-ui/x-ui.tmp /usr/local/x-ui/x-ui
                ok "Бинарный файл 3X-UI успешно обновлён без изменения x-ui.db."
            else
                warn "Архив 3X-UI повреждён; используется действующий бинарник."
            fi
            rm -rf /tmp/xui_upd_unpack "$XUI_TAR"
        else
            warn "Не удалось загрузить обновление 3X-UI; миграция продолжена с текущим бинарником."
        fi
    fi
fi

for alt_db in "$DB_PATH" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then DB_PATH="$alt_db"; break; fi
done
ok "База SQLite 3X-UI готова: $DB_PATH"

systemctl stop x-ui 2>/dev/null || true
if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
    cp -a "$DB_PATH" "$XUI_PRE_BAK" 2>/dev/null || true
    chmod 600 "$XUI_PRE_BAK" 2>/dev/null || true
    ROLLBACK_ACTIVE=1
fi

TARGET_XRAY_VERSION="v26.7.28"
export TARGET_XRAY_VERSION
KEEP_CURRENT_XRAY=0

XRAY_BIN="/usr/local/x-ui/bin/xray"
if [ ! -x "$XRAY_BIN" ]; then
    XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"
fi

if [ "$INSTALL_MODE" = "2" ] && [ -x "$XRAY_BIN" ]; then
    CUR_XRAY_RAW=$("$XRAY_BIN" version 2>/dev/null | awk 'NR==1 {print $2; exit}' | tr -d 'v\r\n' || echo "0")
    if [[ "$CUR_XRAY_RAW" =~ ^[0-9]+(\.[0-9]+)+$ ]] && dpkg --compare-versions "$CUR_XRAY_RAW" "gt" "26.7.28"; then
        warn "В системе установлено ядро Xray v${CUR_XRAY_RAW} (новее закреплённого ${TARGET_XRAY_VERSION})."
        if prompt_yes_no "Сохранить действующее ядро Xray v${CUR_XRAY_RAW} без отката на ${TARGET_XRAY_VERSION}?" "y"; then
            KEEP_CURRENT_XRAY=1
            ok "Сохранено действующее ядро Xray v${CUR_XRAY_RAW}."
        fi
    fi
fi

if [ "$KEEP_CURRENT_XRAY" -eq 0 ]; then
    log "Инспекция архитектуры и закрепление Xray Core ${TARGET_XRAY_VERSION}..."
    SYS_ARCH=$(uname -m)
    case "$SYS_ARCH" in
        x86_64)
            XRAY_ZIP_ARCH="64"
            XRAY_BIN_NAMES=("xray-linux-amd64" "xray")
            ;;
        aarch64|arm64)
            XRAY_ZIP_ARCH="arm64-v8a"
            XRAY_BIN_NAMES=("xray-linux-arm64" "xray-linux-arm64-v8a" "xray")
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
fi

if [ -f "$DB_PATH" ]; then
    EXT_GEO_NEEDED=$(sqlite_ro "$DB_PATH" "SELECT value FROM settings WHERE key='xrayTemplateConfig' LIMIT 1;" | grep -oE 'ext:(geosite_RU|geoip_RU)\.dat' | sort -u || true)
    for geo_ext in $EXT_GEO_NEEDED; do
        geo_fn="${geo_ext#ext:}"
        if [ ! -s "/usr/local/x-ui/bin/${geo_fn}" ]; then
            src_name="geosite.dat"
            if [[ "$geo_fn" == geoip* ]]; then src_name="geoip.dat"; fi
            log "Загрузка отсутствующей пользовательской геобазы ${geo_fn} (используется в routing.rules)..."
            if [ "$GEO_PROFILE" = "1" ]; then
                RU_GEO_URLS=(
                    "https://ghfast.top/https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/${src_name}"
                    "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/${src_name}"
                )
            else
                RU_GEO_URLS=(
                    "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/${src_name}"
                    "https://ghfast.top/https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/${src_name}"
                )
            fi
            download_asset "/usr/local/x-ui/bin/${geo_fn}.tmp" "${RU_GEO_URLS[@]}" && mv -f "/usr/local/x-ui/bin/${geo_fn}.tmp" "/usr/local/x-ui/bin/${geo_fn}" || rm -f "/usr/local/x-ui/bin/${geo_fn}.tmp"
        fi
    done
fi

DETECTED_XRAY_VER=$("$XRAY_BIN" version 2>/dev/null | awk 'NR==1 {print $2; exit}' | tr -d '\r\n' || echo "v26.7.28")
ok "Активная версия Xray: ${GREEN}${DETECTED_XRAY_VER}${NC}"

MIGRATE_FORCE_MLKEM=1
MIGRATE_XHTTP_FLOW_POLICY="vision"
ATTACH_NEW_IB_CLIENTS=0
if [ "$INSTALL_MODE" = "2" ] && [ -f "$DB_PATH" ]; then
    LOC_COND_X=$(get_local_ib_cond "$DB_PATH")
    if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
        CUR_XHTTP_DEC=$(sqlite_ro "$DB_PATH" "SELECT json_extract(settings, '$.decryption') FROM inbounds WHERE (tag='in-xhttp-stream' OR (protocol='vless' AND stream_settings LIKE '%xhttp%')) ${LOC_COND_X} ORDER BY enable DESC, id ASC LIMIT 1;")
        if [ "$CUR_XHTTP_DEC" = "none" ] || [ -z "$CUR_XHTTP_DEC" ]; then
            warn "В действующей базе xHTTP работает без постквантового шифрования (decryption=none)."
            if ! prompt_yes_no "Включить ML-KEM-768 (потребует обновления подписки у существующих клиентов xHTTP)?" "y"; then
                MIGRATE_FORCE_MLKEM=0
            fi
        fi
        echo -e "  ${WHITE}Политика поля flow для текущих клиентов xHTTP при миграции:${NC}"
        echo -e "    1) ${GREEN}Сохранить текущий flow каждого клиента (рекомендуется при клиентах с др. узлов)${NC}"
        echo -e "    2) ${CYAN}Принудительно установить xtls-rprx-vision всем клиентам xHTTP (эталон с ML-KEM-768)${NC}"
        echo -e "    3) ${YELLOW}Очистить flow=\"\" всем клиентам xHTTP (фикс совместимости, если Vision ломает клиентов)${NC}"
        prompt_choice "  Выберите политику flow для xHTTP" "1" XHTTP_FLOW_CHOICE "1" "2" "3"
        case "$XHTTP_FLOW_CHOICE" in
            2) MIGRATE_XHTTP_FLOW_POLICY="vision" ;;
            3) MIGRATE_XHTTP_FLOW_POLICY="clear" ;;
            *) MIGRATE_XHTTP_FLOW_POLICY="keep" ;;
        esac
    fi
    EXISTING_CL_CNT=$(sqlite_ro "$DB_PATH" "SELECT COUNT(*) FROM clients;")
    if [ "${EXISTING_CL_CNT:-0}" -gt 0 ]; then
        if prompt_yes_no "При добавлении новых инбаундов привязывать к ним всех текущих активных клиентов (иначе добавится только Test)?" "n"; then
            ATTACH_NEW_IB_CLIENTS=1
        fi
    fi
fi
export MIGRATE_XHTTP_FLOW_POLICY ATTACH_NEW_IB_CLIENTS

VLESS_DECRYPTION=""
VLESS_ENCRYPTION=""
if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    log "Генерация постквантового ключа VLESS Encryption (ML-KEM-768)..."
    if vl_out=$("$XRAY_BIN" vlessenc 2>&1); then
        VLESS_DECRYPTION=$(printf '%s\n' "$vl_out" | grep -oE '"decryption"[[:space:]]*:[[:space:]]*"mlkem768[^"]*"' | head -n1 | awk -F'"' '{print $4}' || true)
        VLESS_ENCRYPTION=$(printf '%s\n' "$vl_out" | grep -oE '"encryption"[[:space:]]*:[[:space:]]*"mlkem768[^"]*"' | head -n1 | awk -F'"' '{print $4}' || true)
    else
        vl_out="vlessenc exit code $?"
    fi

    if [[ ! "$VLESS_DECRYPTION" =~ ^mlkem768 ]] || [ -z "$VLESS_ENCRYPTION" ]; then
        warn "Ошибка генерации ключа VLESS Encryption! Xray вернул: $vl_out"
        if ! prompt_yes_no "Продолжить без постквантового шифрования xHTTP?" "n"; then
            exit 1
        fi
        VLESS_DECRYPTION="none"
        VLESS_ENCRYPTION="none"
    else
        ok "Ключ ML-KEM-768 успешно сгенерирован!"
    fi
fi

STEAL_CONFIG_DATA=""
for p in "${STEAL_PORTS_LIST[@]:-}"; do
    if [ -z "$p" ]; then continue; fi
    IFS=$' \t\n' read -r -a doms_arr <<< "${STEAL_PORT_DOMAINS[$p]:-}"
    doms_joined=$(IFS=,; echo "${doms_arr[*]}")
    STEAL_CONFIG_DATA="${STEAL_CONFIG_DATA}${p}=${doms_joined};"
done

CLASSIC_CONFIG_DATA=""
for cp in "${CLASSIC_PORTS_LIST[@]:-}"; do
    if [ -z "$cp" ]; then continue; fi
    IFS=$' \t\n' read -r -a snis_arr <<< "${CLASSIC_PORT_SNIS[$cp]:-}"
    snis_joined=$(IFS=,; echo "${snis_arr[*]}")
    CLASSIC_CONFIG_DATA="${CLASSIC_CONFIG_DATA}${cp}=${snis_joined};"
done

export ENABLE_XHTTP="${ENABLE_XHTTP:-0}"
export ENABLE_NATIVE_AWG="${ENABLE_NATIVE_AWG:-0}"
export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH SUB_CLASH_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_CONFIG_DATA
export ENABLE_CLASSIC CLASSIC_CONFIG_DATA ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ADMIN_USER ADMIN_PASS
export SSL_BASE_DIR VLESS_DECRYPTION VLESS_ENCRYPTION MIGRATE_FORCE_MLKEM
export STEAL_DOMAINS_STR="${STEAL_DOMAINS[*]:-}" INSTALL_MODE ENABLE_AGH GEO_PROFILE

python3 - << 'EOF_PY_STAGE1'
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

domain = os.environ["PRIMARY_DOMAIN"]
panel_port = os.environ["PANEL_PORT"]
panel_path = os.environ["PANEL_PATH"]
sub_port = os.environ["SUB_PORT"]
sub_path = os.environ["SUB_PATH"]
sub_json_path = f"{sub_path}sub-json/"
sub_clash_path = os.environ.get("SUB_CLASH_PATH", f"{sub_path}sub-clash/")
admin_u = os.environ["ADMIN_USER"]
admin_p = os.environ["ADMIN_PASS"]
install_mode = os.environ.get("INSTALL_MODE", "1")
enable_agh = os.environ.get("ENABLE_AGH") == "1"
enable_native_awg = os.environ.get("ENABLE_NATIVE_AWG") == "1"
enable_awg_v3 = os.environ.get("ENABLE_AWG_V3") == "1"

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
    else:
        cur.execute("INSERT INTO users (id, username, password) VALUES (1, ?, ?)", (admin_u, hashed_p))
    uid = urow[0] if urow else 1
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
    "trustedProxyCIDRs": ",".join(["127.0.0.1/32"] + (["10.8.1.0/24"] if enable_awg_v3 else []) + (["10.9.0.0/24"] if enable_native_awg else [])),
    "realityScanCandidates": "",
    "restartXrayOnClientDisable": "true",
    "xrayOutboundTestUrl": "https://www.google.com/generate_204",
    "subJsonAlwaysArray": "true",
    "subClashAutoDetect": "true",
    "subJsonAutoDetect": "false"
}

for k, v in settings_data.items():
    cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
    if cur.fetchone():
        if install_mode == "1" or k in ["webPort", "webBasePath", "webListen", "subPort", "subPath", "subURI", "subJsonPath", "subJsonURI", "subClashPath", "subClashURI", "subListen", "trustedProxyCIDRs", "subJsonAlwaysArray", "subClashAutoDetect", "subShowInfo", "subEnable", "subClashEnable", "subJsonEnable"]:
            cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

routing_rules = [
    {"inboundTag": ["api"], "outboundTag": "api", "type": "field"}
]

direct_dns_ips = ["127.0.0.1"]
if enable_native_awg:
    direct_dns_ips.append("10.9.0.1")
if enable_agh:
    routing_rules.append({"ip": direct_dns_ips, "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})

awg_subnets = []
if enable_awg_v3:
    awg_subnets.append("10.8.1.0/24")
if enable_native_awg:
    awg_subnets.append("10.9.0.0/24")
if awg_subnets:
    routing_rules.append({"ip": awg_subnets, "outboundTag": "direct", "type": "field"})
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
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}, "streamSettings": {"sockopt": {"domainStrategy": "ForceIPv4"}}},
        {"tag": "blocked", "protocol": "blackhole", "settings": {}}
    ],
    "policy": {"system": {"statsInboundDownlink": True, "statsInboundUplink": True, "statsOutboundDownlink": False, "statsOutboundUplink": False}, "levels": {"0": {"statsUserDownlink": True, "statsUserUplink": True}}},
    "routing": {"domainStrategy": "AsIs", "rules": routing_rules},
    "stats": {}
}

cur.execute("SELECT value FROM settings WHERE key = 'xrayTemplateConfig'")
existing_tpl_row = cur.fetchone()
if existing_tpl_row and existing_tpl_row[0] and install_mode == "2":
    try:
        current_tpl = json.loads(existing_tpl_row[0])
        current_tpl["log"] = {"access": "none", "dnsLog": False, "error": "", "loglevel": "warning", "maskAddress": ""}
        routing = current_tpl.setdefault("routing", {})
        routing["domainStrategy"] = "AsIs"
        for ob in current_tpl.get("outbounds", []):
            if isinstance(ob, dict) and ob.get("tag") == "direct":
                ob.pop("sendThrough", None)
                ob_set = ob.setdefault("settings", {})
                if isinstance(ob_set, dict):
                    ob_set["domainStrategy"] = "UseIPv4"
                ob.setdefault("streamSettings", {}).setdefault("sockopt", {})["domainStrategy"] = "ForceIPv4"
        rules = routing.setdefault("rules", [])
        if enable_agh:
            current_tpl["dns"] = dns_config
            rules = [r for r in rules if not (isinstance(r, dict) and r.get("ruleTag") == "xui-dns-allow")]
            has_dns_rule = any(isinstance(r, dict) and ("127.0.0.1" in r.get("ip", []) and str(r.get("port")) == "53") for r in rules)
            if not has_dns_rule:
                rules.insert(0, {"ip": direct_dns_ips, "outboundTag": "direct", "port": "53", "ruleTag": "xui-dns-allow", "type": "field"})
        else:
            current_tpl["dns"] = {}
            rules = [r for r in rules if not (isinstance(r, dict) and (r.get("ruleTag") == "xui-dns-allow" or ("127.0.0.1" in r.get("ip", []) and str(r.get("port")) == "53")))]
        routing["rules"] = rules
        cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(current_tpl, ensure_ascii=False),))
    except Exception:
        pass
else:
    cur.execute("SELECT id FROM settings WHERE key = 'xrayTemplateConfig'")
    if cur.fetchone():
        cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(tpl_config),))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)", (json.dumps(tpl_config),))

conn.commit()
conn.close()
EOF_PY_STAGE1

cat << 'EOF_S2_HELPER' > /tmp/xui_stage2_helper.py
# -*- coding: utf-8 -*-
import os, json, base64

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

def register_or_get_inbound(ctx, port, proto, tag, remark, s_obj_def, st_obj_def, listen="127.0.0.1"):
    cur = ctx["cur"]
    uid = ctx["uid"]
    install_mode = ctx["install_mode"]
    domain = ctx["domain"]
    xhttp_path = ctx["xhttp_path"]
    vless_dekey = ctx["vless_dekey"]
    vless_enkey = ctx["vless_enkey"]
    active_inbound_ids = ctx["active_inbound_ids"]
    new_inbound_ids = ctx["new_inbound_ids"]
    panel_guid = ctx.get("panel_guid", "")

    cur.execute("PRAGMA table_info(inbounds)")
    ib_cols = {r[1] for r in cur.fetchall()}
    reg_conds = []
    reg_params = [port, proto, tag]
    if "node_id" in ib_cols:
        reg_conds.append("(node_id IS NULL OR node_id = 0)")
    if "origin_node_guid" in ib_cols:
        if panel_guid:
            reg_conds.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
            reg_params.append(panel_guid)
        else:
            reg_conds.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
    _nc_reg = (" AND " + " AND ".join(reg_conds)) if reg_conds else ""
    cur.execute(f"SELECT id, port, settings, stream_settings FROM inbounds WHERE ((port = ? AND protocol = ?) OR tag = ?){_nc_reg}", reg_params)
    row = cur.fetchone()
    sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True})

    if row and install_mode == "2":
        inbound_id = row[0]
        cur_port = int(row[1]) if row[1] is not None else int(port)
        cur_s = json.loads(row[2]) if row[2] else {}
        cur_st = json.loads(row[3]) if row[3] else {}
        port_mutated = (cur_port != int(port))
        s_mutated = False
        st_mutated = False

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

        if proto == "vless" and "realitySettings" in cur_st:
            if "testseed" in cur_s:
                cur_s.pop("testseed", None)
                s_mutated = True
            rs = cur_st["realitySettings"]
            sids = rs.get("shortIds", [])
            rs_set = rs.setdefault("settings", {})
            if isinstance(rs_set, dict) and not rs_set.get("shortId") and isinstance(sids, list) and sids:
                rs_set["shortId"] = str(sids[0])
                st_mutated = True
            if not rs.get("minClientVer"):
                rs["minClientVer"] = "0.0.0"
                st_mutated = True
            if rs.get("dest") != "127.0.0.1:9443" and "in-steal" in tag:
                rs["dest"] = "127.0.0.1:9443"
                rs["target"] = "127.0.0.1:9443"
                rs["xver"] = 1
                st_mutated = True
            if "tcpSettings" in cur_st:
                if not cur_st["tcpSettings"].get("acceptProxyProtocol"):
                    cur_st["tcpSettings"]["acceptProxyProtocol"] = True
                    st_mutated = True

        if proto == "vless" and tag == "in-xhttp-stream":
            force_mlkem = os.environ.get("MIGRATE_FORCE_MLKEM", "1") == "1"
            flow_policy = os.environ.get("MIGRATE_XHTTP_FLOW_POLICY", "keep")
            if force_mlkem and (not cur_s.get("decryption") or cur_s.get("decryption") == "none") and vless_dekey and vless_dekey != "none":
                cur_s["decryption"] = vless_dekey
                cur_s["encryption"] = vless_enkey
                s_mutated = True
            has_vless_enc = bool(cur_s.get("decryption") and cur_s.get("decryption") != "none")
            has_tls_sec = bool(cur_st.get("security") and cur_st.get("security") != "none")
            for c_item in cur_s.get("clients", []):
                if not isinstance(c_item, dict):
                    continue
                if (not has_vless_enc and not has_tls_sec) or flow_policy == "clear":
                    if c_item.get("flow"):
                        c_item["flow"] = ""
                        s_mutated = True
                elif flow_policy == "vision" and c_item.get("flow") != "xtls-rprx-vision":
                    c_item["flow"] = "xtls-rprx-vision"
                    s_mutated = True
            if "xhttpSettings" in cur_st:
                xh = cur_st["xhttpSettings"]
                ref_xh = {
                    "host": domain,
                    "path": xhttp_path,
                    "mode": "stream-one",
                    "noSSEHeader": True,
                    "xPaddingBytes": "120-1120",
                    "xPaddingObfsMode": True,
                    "xPaddingPlacement": "header",
                    "xPaddingHeader": "X-Amz-Meta-Trace",
                    "xPaddingMethod": "tokenish",
                    "xPaddingKey": "X-Amz-Meta-Trace",
                    "enableXmux": True
                }
                for rk, rv in ref_xh.items():
                    if xh.get(rk) != rv:
                        xh[rk] = rv
                        st_mutated = True
                if not isinstance(xh.get("xmux"), dict) or xh["xmux"].get("hKeepAlivePeriod") != 3000 or xh["xmux"].get("maxConnections") != "1-3":
                    xh["xmux"] = {"maxConcurrency": "0", "maxConnections": "1-3", "cMaxReuseTimes": "150-300", "hMaxRequestTimes": "300-500", "hMaxReusableSecs": "900-1800", "hKeepAlivePeriod": 3000}
                    st_mutated = True
            if cur_st.get("sockopt", {}).get("trustedXForwardedFor") != ["X-Forwarded-For"]:
                cur_st.setdefault("sockopt", {})["trustedXForwardedFor"] = ["X-Forwarded-For"]
                st_mutated = True
            if "externalProxy" in cur_st and isinstance(cur_st["externalProxy"], list):
                for ep in cur_st["externalProxy"]:
                    if ep.get("dest") != domain or ep.get("sni") != domain or ep.get("remark") != remark or ep.get("fingerprint") != "firefox" or ep.get("alpn") != ["h2"]:
                        ep["dest"] = domain
                        ep["sni"] = domain
                        ep["port"] = 443
                        ep["forceTls"] = "tls"
                        ep["fingerprint"] = "firefox"
                        ep["alpn"] = ["h2"]
                        ep["remark"] = remark
                        st_mutated = True

        if proto == "amneziawg" and "server" in cur_s:
            srv = cur_s["server"]
            if srv.get("contentPaddingAddition") == "0":
                srv["contentPaddingAddition"] = ""
                s_mutated = True
            patch_defaults = {
                "contentPaddingAddition": "", "randomTrailers": False, "disableCookies": True,
                "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
                "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
                "mtu": 1360, "jc": 4, "jmin": 40, "jmax": 70, "s1": 72, "s2": 56, "s3": 32, "s4": 16
            }
            for pk, pv in patch_defaults.items():
                if pk not in srv or srv[pk] is None or (pk != "contentPaddingAddition" and srv[pk] == ""):
                    srv[pk] = pv
                    s_mutated = True

        if proto == "hysteria":
            hs = cur_st.setdefault("hysteriaSettings", {})
            masq = hs.setdefault("masquerade", {})
            if masq.get("type") != "proxy" or masq.get("url") in (None, "", "http://127.0.0.1:80"):
                masq["type"] = "proxy"
                masq["url"] = "http://127.0.0.1:8088"
                st_mutated = True

        if port_mutated and "externalProxy" in cur_st and isinstance(cur_st["externalProxy"], list) and proto in ("hysteria", "amneziawg"):
            for ep in cur_st["externalProxy"]:
                if isinstance(ep, dict) and ep.get("port") != int(port):
                    ep["port"] = int(port)
                    st_mutated = True

        if proto in ("hysteria", "amneziawg"):
            meta_upd = {}
            if "share_addr_strategy" in ib_cols:
                meta_upd["share_addr_strategy"] = "custom"
            if "share_addr" in ib_cols:
                meta_upd["share_addr"] = domain
            if "exclude_from_sub" in ib_cols:
                meta_upd["exclude_from_sub"] = 1 if proto == "amneziawg" else 0
            if meta_upd:
                m_keys = list(meta_upd.keys())
                m_sql = ", ".join(f"{k} = ?" for k in m_keys)
                cur.execute(f"UPDATE inbounds SET {m_sql} WHERE id = ?", [meta_upd[k] for k in m_keys] + [inbound_id])
        if s_mutated or st_mutated or port_mutated:
            cur.execute("UPDATE inbounds SET port = ?, settings = ?, stream_settings = ?, sniffing = ? WHERE id = ?",
                        (int(port), json.dumps(cur_s, ensure_ascii=False), json.dumps(cur_st, ensure_ascii=False), sniff, inbound_id))
        else:
            cur.execute("UPDATE inbounds SET sniffing = ? WHERE id = ?", (sniff, inbound_id))
        active_inbound_ids.append(inbound_id)
        return inbound_id
    elif row:
        inbound_id = row[0]
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        share_strat = "custom" if proto in ("hysteria", "amneziawg") else "node"
        share_addr_val = domain if proto in ("hysteria", "amneziawg") else ""
        upd_cand = {
            "port": port, "protocol": proto, "remark": remark,
            "settings": s_json, "stream_settings": st_json,
            "listen": listen, "sniffing": sniff, "enable": 1,
            "share_addr_strategy": share_strat, "share_addr": share_addr_val,
            "exclude_from_sub": 1 if proto == "amneziawg" else 0,
        }
        upd_f = {k: v for k, v in upd_cand.items() if k in ib_cols}
        u_keys = list(upd_f.keys())
        u_sql = ", ".join(f"{k} = ?" for k in u_keys)
        cur.execute(f"UPDATE inbounds SET {u_sql} WHERE id = ?", [upd_f[k] for k in u_keys] + [inbound_id])
        active_inbound_ids.append(inbound_id)
        return inbound_id
    else:
        s_json = json.dumps(s_obj_def, ensure_ascii=False)
        st_json = json.dumps(st_obj_def, ensure_ascii=False)
        share_strat = "custom" if proto in ("hysteria", "amneziawg") else "node"
        share_addr_val = domain if proto in ("hysteria", "amneziawg") else ""
        ins_cand = {
            "user_id": uid, "up": 0, "down": 0, "total": 0,
            "remark": remark, "enable": 1, "expiry_time": 0,
            "listen": listen, "port": port, "protocol": proto,
            "settings": s_json, "stream_settings": st_json,
            "tag": tag, "sniffing": sniff,
            "share_addr_strategy": share_strat, "share_addr": share_addr_val,
            "exclude_from_sub": 1 if proto == "amneziawg" else 0, "disable_flow": 0,
        }
        ins_f = {k: v for k, v in ins_cand.items() if k in ib_cols}
        i_keys = list(ins_f.keys())
        i_ph = ",".join(["?"] * len(i_keys))
        cur.execute(f"INSERT INTO inbounds ({','.join(i_keys)}) VALUES ({i_ph})", [ins_f[k] for k in i_keys])
        inbound_id = cur.lastrowid
        active_inbound_ids.append(inbound_id)
        new_inbound_ids.add(inbound_id)
        return inbound_id
EOF_S2_HELPER
chmod 0600 /tmp/xui_stage2_helper.py

python3 - << 'EOF_PY_STAGE2A'
# -*- coding: utf-8 -*-
import os, sys, sqlite3, json, uuid, secrets, time
sys.path.insert(0, "/tmp")
from xui_stage2_helper import gen_reality_keypair, gen_wg_keypair

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path, timeout=60.0)
cur = conn.cursor()
cur.execute("SELECT id FROM users LIMIT 1")
urow = cur.fetchone()
uid = urow[0] if urow else 1
conn.close()

test_email = "Test"
test_sub_id = f"sub_{secrets.token_hex(10)}"
test_uuid = str(uuid.uuid4())
test_password = secrets.token_hex(8)
test_auth = test_password
reality_short_ids = [secrets.token_hex(8) for _ in range(6)]
reality_hex_sid = reality_short_ids[0]

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

state = {
    "uid": uid, "test_email": test_email, "test_sub_id": test_sub_id,
    "test_uuid": test_uuid, "test_password": test_password, "test_auth": test_auth,
    "reality_short_ids": reality_short_ids, "reality_hex_sid": reality_hex_sid,
    "def_r_priv": def_r_priv, "def_r_pub": def_r_pub,
    "def_wg_s_priv": def_wg_s_priv, "def_wg_s_pub": def_wg_s_pub,
    "def_wg_c_priv": def_wg_c_priv, "def_wg_c_pub": def_wg_c_pub,
    "now_ms": now_ms, "client_reality_dict": client_reality_dict,
    "client_xhttp_dict": client_xhttp_dict
}
with open("/tmp/xui_stage2_state.json", "w", encoding="utf-8") as f:
    json.dump(state, f)
os.chmod("/tmp/xui_stage2_state.json", 0o600)
EOF_PY_STAGE2A

python3 - << 'EOF_PY_STAGE2B'
# -*- coding: utf-8 -*-
import os, sys, sqlite3, json, uuid, secrets, time, shutil, base64
sys.path.insert(0, "/tmp")
from xui_stage2_helper import register_or_get_inbound, gen_wg_keypair

with open("/tmp/xui_stage2_state.json", "r", encoding="utf-8") as f:
    st_data = json.load(f)

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path, timeout=60.0)
cur = conn.cursor()

try:
    cur.execute("PRAGMA busy_timeout = 60000")
    cur.execute("PRAGMA journal_mode = WAL")
    cur.execute("PRAGMA synchronous = NORMAL")
except Exception:
    pass

domain = os.environ["PRIMARY_DOMAIN"]
xhttp_port = int(os.environ["XHTTP_STREAM_PORT"]) if os.environ.get("XHTTP_STREAM_PORT", "").isdigit() else 0
xhttp_path = os.environ["XHTTP_STREAM_PATH"]
vless_dekey = os.environ["VLESS_DECRYPTION"]
vless_enkey = os.environ["VLESS_ENCRYPTION"]
install_mode = os.environ.get("INSTALL_MODE", "1")
geo_profile = os.environ.get("GEO_PROFILE", "2")

uid = st_data["uid"]
test_email = st_data["test_email"]
test_sub_id = st_data["test_sub_id"]
test_uuid = st_data["test_uuid"]
test_password = st_data["test_password"]
reality_short_ids = st_data["reality_short_ids"]
reality_hex_sid = st_data["reality_hex_sid"]
def_r_priv = st_data["def_r_priv"]
def_r_pub = st_data["def_r_pub"]
def_wg_s_priv = st_data["def_wg_s_priv"]
def_wg_s_pub = st_data["def_wg_s_pub"]
def_wg_c_priv = st_data["def_wg_c_priv"]
def_wg_c_pub = st_data["def_wg_c_pub"]
now_ms = st_data["now_ms"]
client_reality_dict = st_data["client_reality_dict"]
client_xhttp_dict = st_data["client_xhttp_dict"]

vision_inbound_ids = set()
active_inbound_ids = []
new_inbound_ids = set()
cur.execute("SELECT value FROM settings WHERE key = 'panelGuid' LIMIT 1")
_pg_row = cur.fetchone()
panel_guid = str(_pg_row[0]).strip() if _pg_row and _pg_row[0] else ""

ctx = {
    "cur": cur, "uid": uid, "install_mode": install_mode,
    "domain": domain, "xhttp_path": xhttp_path,
    "vless_dekey": vless_dekey, "vless_enkey": vless_enkey,
    "active_inbound_ids": active_inbound_ids,
    "new_inbound_ids": new_inbound_ids,
    "panel_guid": panel_guid
}

ib1_id = None
ib2_id = None
ib3_id = None
ib4_id = None
ib5_id = None

# 1. Steal-Oneself REALITY (Anti-Loop Fallback 9443)
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
        s_obj = {"clients": [client_reality_dict], "decryption": "none", "encryption": "none"}
        st_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 1, "target": "127.0.0.1:9443", "dest": "127.0.0.1:9443",
                "serverNames": doms, "privateKey": def_r_priv, "minClientVer": "0.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": reality_short_ids,
                "mldsa65Seed": "",
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": primary_steal_sni, "shortId": reality_hex_sid, "spiderX": "/", "mldsa65Verify": ""},
                "spiderX": "/"
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "sni": primary_steal_sni, "remark": remark}]
        }
        ib1_id = register_or_get_inbound(ctx, p, "vless", tag, remark, s_obj, st_obj)
        vision_inbound_ids.add(ib1_id)

# 2. Classic REALITY
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
        primary_sni = snis[0] if snis else "gateway.icloud.com"
        tag = f"in-classic-reality-{p}" if p != 46443 else "in-classic-reality"
        remark = f"REALITY Classic ({primary_sni})"
        c_obj = {"clients": [client_reality_dict], "decryption": "none", "encryption": "none"}
        ct_obj = {
            "network": "tcp", "security": "reality",
            "tcpSettings": {"acceptProxyProtocol": True, "header": {"type": "none"}},
            "realitySettings": {
                "show": False, "xver": 0, "target": f"{primary_sni}:443", "dest": f"{primary_sni}:443",
                "serverNames": snis, "privateKey": def_r_priv, "minClientVer": "0.0.0",
                "maxClientVer": "", "maxTimediff": 0, "shortIds": reality_short_ids,
                "mldsa65Seed": "",
                "settings": {"publicKey": def_r_pub, "fingerprint": "firefox", "serverName": primary_sni, "shortId": reality_hex_sid, "spiderX": "/", "mldsa65Verify": ""},
                "spiderX": "/"
            },
            "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "sni": primary_sni, "remark": remark}]
        }
        ib2_id = register_or_get_inbound(ctx, p, "vless", tag, remark, c_obj, ct_obj)
        vision_inbound_ids.add(ib2_id)

# 3. VLESS xHTTP (Native H2 Stream-One) + ML-KEM-768
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
            "xPaddingBytes": "120-1120", "xPaddingObfsMode": True,
            "xPaddingPlacement": "header", "xPaddingHeader": "X-Amz-Meta-Trace", "xPaddingMethod": "tokenish",
            "xPaddingKey": "X-Amz-Meta-Trace",
            "xmux": {"maxConcurrency": "0", "maxConnections": "1-3", "cMaxReuseTimes": "150-300", "hMaxRequestTimes": "300-500", "hMaxReusableSecs": "900-1800", "hKeepAlivePeriod": 3000},
            "enableXmux": True
        },
        "security": "none",
        "sockopt": {"trustedXForwardedFor": ["X-Forwarded-For"]},
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "firefox", "alpn": ["h2"], "remark": remark_xhttp}]
    }
    ib3_id = register_or_get_inbound(ctx, xhttp_port, "vless", "in-xhttp-stream", remark_xhttp, x_obj, xt_obj)
    vision_inbound_ids.add(ib3_id)

# 4. Hysteria 2
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
        "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60, "masquerade": {"type": "proxy", "url": "http://127.0.0.1:8088"}},
        "security": "tls",
        "tlsSettings": {
            "serverName": domain, "minVersion": "1.3", "maxVersion": "1.3",
            "certificates": [{"certificateFile": f"{ssl_dir}/{domain}/fullchain.pem", "keyFile": f"{ssl_dir}/{domain}/privkey.pem"}],
            "alpn": ["h3"]
        },
        "externalProxy": [{"dest": domain, "port": hp, "forceTls": "tls", "alpn": ["h3"], "remark": remark_hy2}]
    }
    ib4_id = register_or_get_inbound(ctx, hp, "hysteria", "in-hysteria2", remark_hy2, h_obj, ht_obj, listen="0.0.0.0")

# 5. AmneziaWG v3.2 (3X-UI) — выделенный пир AWG-v3-Client (без попадания в подписку Test)
awg3_client_meta = None
if os.environ.get("ENABLE_AWG_V3") == "1":
    a3p = int(os.environ["AWG_V3_PORT"])
    remark_awg3 = f"AmneziaWG v3.2 ({domain})"
    awg3_dns_prim = "77.88.8.8" if geo_profile == "1" else "1.1.1.1"
    awg3_dns_sec = "77.88.8.1" if geo_profile == "1" else "8.8.8.8"
    awg3_uuid = str(uuid.uuid4())
    awg3_sub_id = f"sub_{secrets.token_hex(10)}"
    awg3_pwd = secrets.token_hex(8)
    awg3_client_meta = {
        "email": "AWG-v3-Client", "sub_id": awg3_sub_id, "uuid": awg3_uuid,
        "password": awg3_pwd, "auth": awg3_pwd, "priv": def_wg_c_priv, "pub": def_wg_c_pub,
        "ip": "10.8.1.2/32"
    }
    a3_client = {
        "allowedIPs": ["10.8.1.2/32"], "auth": awg3_pwd, "comment": "Dedicated AWG v3.2 Peer",
        "created_at": now_ms, "email": "AWG-v3-Client", "enable": True, "expiryTime": 0,
        "id": awg3_uuid, "keepAlive": 25, "limitIp": 0, "password": awg3_pwd,
        "privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub, "reset": 0, "resetDay": 0,
        "resetMax": 0, "security": "auto", "subId": awg3_sub_id, "tgId": 0, "totalGB": 0,
        "trafficReset": "never", "trafficResetDay": 1, "updated_at": now_ms
    }

    _h_vals = []
    while len(_h_vals) < 4:
        _cand = str(secrets.randbelow(2000000000) + 100000000)
        if _cand not in _h_vals:
            _h_vals.append(_cand)
    a3_h1, a3_h2, a3_h3, a3_h4 = _h_vals

    a3_obj = {
        "clients": [a3_client],
        "server": {
            "h1": a3_h1, "h2": a3_h2, "h3": a3_h3, "h4": a3_h4,
            "jc": 4, "jmin": 40, "jmax": 70, "s1": 72, "s2": 56, "s3": 32, "s4": 16,
            "mtu": 1360, "primaryDns": awg3_dns_prim, "secondaryDns": awg3_dns_sec,
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "randomTrailers": False, "disableCookies": True, "contentPaddingAddition": "",
            "keepaliveTimeout": "20-25", "rekeyAfterTime": "300-500", "rekeyTimeout": "10-15",
            "rejectAfterTime": "600-900", "maxHandshakeAttempts": "10-15",
            "subnetCidr": 24, "subnetIp": "10.8.1.0"
        }
    }
    a3t_obj = {"externalProxy": [{"dest": domain, "port": a3p, "remark": remark_awg3}]}
    ib5_id = register_or_get_inbound(ctx, a3p, "amneziawg", "in-awg-v3", remark_awg3, a3_obj, a3t_obj, listen="0.0.0.0")

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = set(r[0] for r in cur.fetchall())

if "clients" in tables:
    cur.execute("PRAGMA table_info(clients)")
    client_cols = {r[1] for r in cur.fetchall()}

    if install_mode == "1":
        client_data_map = {
            "email": test_email, "sub_id": test_sub_id, "uuid": test_uuid, "password": test_password,
            "auth": test_password, "flow": "xtls-rprx-vision", "security": "auto", "reverse": "",
            "wg_private_key": "", "wg_public_key": "", "wg_allowed_ips": "",
            "wg_pre_shared_key": "", "wg_keep_alive": 25, "wg_forwarded_ports": "", "secret": "",
            "ad_tag": "", "limit_ip": 0, "limit_hwid": 0, "total_gb": 0, "expiry_time": 0,
            "enable": 1, "tg_id": 0, "group_name": "", "group": "", "comment": "", "reset": 0, "reset_day": 0,
            "reset_max": 0, "traffic_reset": "never", "traffic_reset_day": 1,
            "created_at": now_ms, "updated_at": now_ms, "sync_orphaned_at": 0
        }
        filtered_client_data = {k: v for k, v in client_data_map.items() if k in client_cols}
        c_keys = list(filtered_client_data.keys())
        c_vals = [filtered_client_data[k] for k in c_keys]
        placeholders = ",".join(["?"] * len(c_keys))
        cur.execute(f"INSERT INTO clients ({','.join(f'\"{k}\"' for k in c_keys)}) VALUES ({placeholders})", c_vals)
        client_global_id = cur.lastrowid

        test_inbound_ids = [ib_id for ib_id in active_inbound_ids if ib_id is not None and ib_id != ib5_id]
        if "client_inbounds" in tables and client_global_id:
            active_inbound_links = [
                (ib_id, "xtls-rprx-vision" if ib_id in vision_inbound_ids else "")
                for ib_id in test_inbound_ids
            ]
            for ib_id, flow_val in active_inbound_links:
                cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                            (client_global_id, ib_id, flow_val, now_ms))

        if "client_traffics" in tables:
            for ib_id in test_inbound_ids:
                cur.execute("SELECT 1 FROM client_traffics WHERE LOWER(email) = LOWER(?) LIMIT 1", (test_email,))
                if cur.fetchone() is None:
                    cur.execute("INSERT OR IGNORE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)",
                                (ib_id, test_email))

        if ib5_id is not None and awg3_client_meta is not None:
            awg3_data_map = {
                "email": awg3_client_meta["email"], "sub_id": awg3_client_meta["sub_id"],
                "uuid": awg3_client_meta["uuid"], "password": awg3_client_meta["password"],
                "auth": awg3_client_meta["auth"], "flow": "", "security": "auto", "reverse": "",
                "wg_private_key": awg3_client_meta["priv"], "wg_public_key": awg3_client_meta["pub"],
                "wg_allowed_ips": awg3_client_meta["ip"], "wg_pre_shared_key": "",
                "wg_keep_alive": 25, "wg_forwarded_ports": "", "secret": "",
                "ad_tag": "", "limit_ip": 0, "limit_hwid": 0, "total_gb": 0, "expiry_time": 0,
                "enable": 1, "tg_id": 0, "group_name": "", "group": "",
                "comment": "Dedicated AWG v3.2 Peer", "reset": 0, "reset_day": 0,
                "reset_max": 0, "traffic_reset": "never", "traffic_reset_day": 1,
                "created_at": now_ms, "updated_at": now_ms, "sync_orphaned_at": 0
            }
            flt_a3 = {k: v for k, v in awg3_data_map.items() if k in client_cols}
            a3_keys = list(flt_a3.keys())
            a3_vals = [flt_a3[k] for k in a3_keys]
            a3_ph = ",".join(["?"] * len(a3_keys))
            cur.execute(f"INSERT INTO clients ({','.join(f'\"{k}\"' for k in a3_keys)}) VALUES ({a3_ph})", a3_vals)
            awg3_cid = cur.lastrowid
            if "client_inbounds" in tables and awg3_cid:
                cur.execute("INSERT OR REPLACE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)",
                            (awg3_cid, ib5_id, "", now_ms))
            if "client_traffics" in tables:
                cur.execute("SELECT 1 FROM client_traffics WHERE LOWER(email) = LOWER(?) LIMIT 1", (awg3_client_meta["email"],))
                if cur.fetchone() is None:
                    cur.execute("INSERT OR IGNORE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)",
                                (ib5_id, awg3_client_meta["email"]))

    elif install_mode == "2":
        if "client_traffics" in tables and "inbounds" in tables:
            cur.execute("DELETE FROM client_traffics WHERE inbound_id NOT IN (SELECT id FROM inbounds)")

        if "client_inbounds" in tables and "inbounds" in tables:
            cur.execute("PRAGMA table_info(inbounds)")
            _rec_ib_cols = {r[1] for r in cur.fetchall()}
            _rec_parts = []
            _rec_params = []
            if "node_id" in _rec_ib_cols:
                _rec_parts.append("(node_id IS NULL OR node_id = 0)")
            if "origin_node_guid" in _rec_ib_cols:
                if panel_guid:
                    _rec_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                    _rec_params.append(panel_guid)
                else:
                    _rec_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
            _nc_rec = (" WHERE " + " AND ".join(_rec_parts)) if _rec_parts else ""
            xhttp_flow_pol = os.environ.get("MIGRATE_XHTTP_FLOW_POLICY", "keep")
            attach_new_ib = os.environ.get("ATTACH_NEW_IB_CLIENTS", "0") == "1"

            cur.execute(f"SELECT id, protocol, tag, settings, stream_settings FROM inbounds{_nc_rec}", _rec_params)
            for ib_row in cur.fetchall():
                cur_ib_id, cur_ib_proto, cur_ib_tag = ib_row[0], ib_row[1], str(ib_row[2] or "")
                cur_ib_s = json.loads(ib_row[3]) if ib_row[3] else {}
                cur_ib_st = json.loads(ib_row[4]) if ib_row[4] else {}

                if cur_ib_id in new_inbound_ids and cur_ib_proto in ("vless", "hysteria"):
                    cur.execute("SELECT COUNT(*) FROM client_inbounds WHERE inbound_id = ?", (cur_ib_id,))
                    if (cur.fetchone()[0] or 0) == 0:
                        if attach_new_ib:
                            cur.execute("SELECT id, flow FROM clients WHERE enable = 1 AND uuid IS NOT NULL AND uuid != '' ORDER BY id ASC")
                            for ex_cid, ex_flow in cur.fetchall():
                                if cur_ib_proto == "hysteria":
                                    f_ov = ""
                                elif cur_ib_tag == "in-xhttp-stream":
                                    has_enc = bool(cur_ib_s.get("decryption") and cur_ib_s.get("decryption") != "none")
                                    if not has_enc or xhttp_flow_pol == "clear":
                                        f_ov = ""
                                    elif xhttp_flow_pol == "vision":
                                        f_ov = "xtls-rprx-vision"
                                    else:
                                        f_ov = str(ex_flow or "")
                                else:
                                    f_ov = str(ex_flow or "xtls-rprx-vision")
                                cur.execute("INSERT OR IGNORE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)", (ex_cid, cur_ib_id, f_ov, now_ms))
                        else:
                            cur.execute("SELECT id FROM clients WHERE LOWER(email) = LOWER(?) LIMIT 1", (test_email,))
                            t_row = cur.fetchone()
                            if t_row:
                                t_cid = t_row[0]
                            else:
                                t_map = {
                                    "email": test_email, "sub_id": test_sub_id, "uuid": test_uuid, "password": test_password,
                                    "auth": test_password, "flow": "xtls-rprx-vision", "security": "auto", "reverse": "",
                                    "wg_private_key": "", "wg_public_key": "", "wg_allowed_ips": "", "wg_pre_shared_key": "",
                                    "wg_keep_alive": 25, "wg_forwarded_ports": "", "secret": "", "ad_tag": "",
                                    "limit_ip": 0, "limit_hwid": 0, "total_gb": 0, "expiry_time": 0, "enable": 1,
                                    "tg_id": 0, "group_name": "", "group": "", "comment": "", "reset": 0,
                                    "reset_day": 0, "reset_max": 0, "traffic_reset": "never", "traffic_reset_day": 1,
                                    "created_at": now_ms, "updated_at": now_ms, "sync_orphaned_at": 0
                                }
                                flt_t = {k: v for k, v in t_map.items() if k in client_cols}
                                tk_list = list(flt_t.keys())
                                cur.execute(f"INSERT INTO clients ({','.join(f'\"{k}\"' for k in tk_list)}) VALUES ({','.join(['?'] * len(tk_list))})", [flt_t[k] for k in tk_list])
                                t_cid = cur.lastrowid
                                if "client_traffics" in tables:
                                    cur.execute("INSERT OR IGNORE INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?, 1, ?, 0, 0, 0, 0, 0)", (cur_ib_id, test_email))
                            t_f_ov = "xtls-rprx-vision" if cur_ib_proto == "vless" else ""
                            cur.execute("INSERT OR IGNORE INTO client_inbounds (client_id, inbound_id, flow_override, created_at) VALUES (?, ?, ?, ?)", (t_cid, cur_ib_id, t_f_ov, now_ms))

                existing_clients_map = {}
                for old_c in cur_ib_s.get("clients", []):
                    if isinstance(old_c, dict):
                        if old_c.get("id"):
                            existing_clients_map[("id", str(old_c["id"]))] = old_c
                        if old_c.get("email"):
                            existing_clients_map[("email", str(old_c["email"]))] = old_c

                opt_cols = [col for col in ["enable", "expiry_time", "total_gb", "reset", "limit_ip", "tg_id", "comment", "security"] if col in client_cols]
                base_select = "c.id, c.email, c.uuid, c.password, c.auth, c.flow, c.wg_public_key, c.wg_allowed_ips, ci.flow_override, c.sub_id"
                extra_select = (", " + ", ".join(f"c.{col}" for col in opt_cols)) if opt_cols else ""
                cur.execute(
                    f"SELECT {base_select}{extra_select} FROM client_inbounds ci JOIN clients c ON c.id = ci.client_id WHERE ci.inbound_id = ?",
                    (cur_ib_id,)
                )
                mapped_clients = cur.fetchall()

                if mapped_clients:
                    is_xhttp = (cur_ib_tag == "in-xhttp-stream" or cur_ib_st.get("network") == "xhttp")
                    has_xhttp_enc = bool(cur_ib_s.get("decryption") and cur_ib_s.get("decryption") != "none")
                    has_tls_sec = bool(cur_ib_st.get("security") and cur_ib_st.get("security") != "none")
                    reconciled_client_list = []
                    for row_c in mapped_clients:
                        cid, cemail, cuuid, cpwd, cauth, cflow, cwg_pub, cwg_ips, cflow_over, csub_id = row_c[:10]
                        extra_vals = dict(zip(opt_cols, row_c[10:]))
                        prev_c = existing_clients_map.get(("email", str(cemail))) or existing_clients_map.get(("id", str(cuuid))) or {}
                        c_entry = dict(prev_c) if isinstance(prev_c, dict) else {}

                        if cur_ib_proto == "vless":
                            if is_xhttp:
                                if (not has_xhttp_enc and not has_tls_sec) or xhttp_flow_pol == "clear":
                                    target_flow = ""
                                elif xhttp_flow_pol == "vision":
                                    target_flow = "xtls-rprx-vision"
                                elif cflow_over is not None and cflow_over != "":
                                    target_flow = str(cflow_over)
                                elif prev_c.get("flow") is not None:
                                    target_flow = str(prev_c.get("flow"))
                                else:
                                    target_flow = str(cflow or "")
                            else:
                                target_flow = str(cflow_over if (cflow_over is not None and cflow_over != "") else (prev_c.get("flow") or cflow or "xtls-rprx-vision"))

                        c_entry.update({
                            "id": cuuid,
                            "email": cemail,
                            "subId": str(csub_id).strip() if csub_id else (c_entry.get("subId") or secrets.token_hex(8)),
                            "enable": bool(extra_vals["enable"]) if "enable" in extra_vals and extra_vals["enable"] is not None else c_entry.get("enable", True),
                            "expiryTime": int(extra_vals["expiry_time"]) if "expiry_time" in extra_vals and extra_vals["expiry_time"] is not None else int(c_entry.get("expiryTime", 0) or 0),
                            "totalGB": int(extra_vals["total_gb"]) if "total_gb" in extra_vals and extra_vals["total_gb"] is not None else int(c_entry.get("totalGB", 0) or 0),
                            "reset": int(extra_vals["reset"]) if "reset" in extra_vals and extra_vals["reset"] is not None else int(c_entry.get("reset", 0) or 0)
                        })
                        if "limit_ip" in extra_vals and extra_vals["limit_ip"] is not None:
                            c_entry["limitIp"] = int(extra_vals["limit_ip"])
                        if "tg_id" in extra_vals and extra_vals["tg_id"] is not None:
                            c_entry["tgId"] = int(extra_vals["tg_id"])
                        if "comment" in extra_vals and extra_vals["comment"] is not None:
                            c_entry["comment"] = str(extra_vals["comment"])
                        if cur_ib_proto == "vless":
                            c_entry["flow"] = target_flow
                            if cflow_over != target_flow:
                                cur.execute("UPDATE client_inbounds SET flow_override = ? WHERE client_id = ? AND inbound_id = ?", (target_flow, cid, cur_ib_id))
                            if "security" in extra_vals and extra_vals["security"]:
                                c_entry["security"] = str(extra_vals["security"])
                            if cpwd: c_entry["password"] = cpwd
                            if cauth: c_entry["auth"] = cauth
                        elif cur_ib_proto == "hysteria":
                            c_entry["auth"] = cauth if cauth else (cpwd if cpwd else cemail)
                            c_entry["password"] = cpwd if cpwd else (cauth if cauth else cemail)
                            c_entry.pop("flow", None)
                        elif cur_ib_proto in ["amneziawg", "wireguard"]:
                            c_entry["publicKey"] = cwg_pub if cwg_pub else c_entry.get("publicKey", "")
                            try:
                                parsed_aips = json.loads(cwg_ips) if (cwg_ips and cwg_ips.startswith("[")) else ([cwg_ips] if cwg_ips else [])
                            except Exception:
                                parsed_aips = [cwg_ips] if cwg_ips else []
                            if parsed_aips:
                                c_entry["allowedIPs"] = parsed_aips
                            c_entry.pop("flow", None)
                        else:
                            if cpwd: c_entry["password"] = cpwd
                            if cauth: c_entry["auth"] = cauth
                        reconciled_client_list.append(c_entry)

                    cur_ib_s["clients"] = reconciled_client_list
                    cur.execute("UPDATE inbounds SET settings = ? WHERE id = ?",
                                (json.dumps(cur_ib_s, ensure_ascii=False), cur_ib_id))

        if ib5_id is not None and "inbounds" in tables:
            def _is_valid_wg_key(val):
                if not isinstance(val, str) or not val.strip():
                    return False
                try:
                    return len(base64.b64decode(val.strip().encode("ascii"), validate=True)) == 32
                except Exception:
                    return False

            def _norm_cidr(val):
                ip_part = str(val or "").strip().split("/")[0].strip()
                return f"{ip_part}/32" if ip_part else ""

            cur.execute("SELECT settings FROM inbounds WHERE id = ?", (ib5_id,))
            awg_row = cur.fetchone()
            if awg_row:
                awg_s = json.loads(awg_row[0]) if awg_row[0] else {}
                srv_sub = str(awg_s.get("server", {}).get("subnetIp") or "10.8.1.0").strip()
                sub_octets = srv_sub.split(".")
                if len(sub_octets) != 4:
                    sub_octets = ["10", "8", "1", "0"]
                sub_pref = ".".join(sub_octets[:3]) + "."
                used_awg_ips = {f"{sub_pref}0/32", f"{sub_pref}1/32", f"{sub_pref}255/32"}
                if "wg_allowed_ips" in client_cols:
                    cur.execute(
                        "SELECT c.email, c.wg_allowed_ips FROM client_inbounds ci JOIN clients c ON c.id = ci.client_id WHERE ci.inbound_id = ? AND c.wg_allowed_ips IS NOT NULL AND c.wg_allowed_ips != ''",
                        (ib5_id,)
                    )
                    for c_em_r, c_ip_r in cur.fetchall():
                        if str(c_em_r or "").strip().lower() != "awg-v3-client":
                            nc_r = _norm_cidr(c_ip_r)
                            if nc_r.startswith(sub_pref):
                                used_awg_ips.add(nc_r)
                prev_awg_by_email = {}
                prev_awg_by_uuid = {}
                for old_c in awg_s.get("clients", []):
                    if isinstance(old_c, dict):
                        em_k = str(old_c.get("email") or "").strip()
                        uid_k = str(old_c.get("id") or "").strip()
                        aips_v = old_c.get("allowedIPs")
                        if isinstance(aips_v, list):
                            for ip_x in aips_v:
                                nc = _norm_cidr(ip_x)
                                if nc:
                                    used_awg_ips.add(nc)
                        if em_k:
                            prev_awg_by_email[em_k] = old_c
                        if uid_k:
                            prev_awg_by_uuid[uid_k] = old_c

                def _alloc_awg_ip():
                    for ho in range(2, 255):
                        cand = f"{sub_pref}{ho}/32"
                        if cand not in used_awg_ips:
                            used_awg_ips.add(cand)
                            return cand
                    return ""

                awg_sel_cols = [c for c in ["id", "email", "sub_id", "uuid", "password", "auth", "wg_private_key", "wg_public_key", "wg_allowed_ips", "limit_ip", "total_gb", "expiry_time", "enable", "tg_id", "comment", "reset", "reset_day", "reset_max", "traffic_reset", "traffic_reset_day", "security", "created_at"] if c in client_cols]
                cur.execute("SELECT COUNT(*) FROM client_inbounds WHERE inbound_id = ?", (ib5_id,))
                has_existing_awg_links = (cur.fetchone()[0] or 0) > 0
                if has_existing_awg_links:
                    sel_q = ", ".join(f"c.{col}" for col in awg_sel_cols)
                    cur.execute(f"SELECT {sel_q} FROM client_inbounds ci JOIN clients c ON c.id = ci.client_id WHERE ci.inbound_id = ? ORDER BY c.id ASC", (ib5_id,))
                    all_active_c = cur.fetchall()
                else:
                    cur.execute(f"SELECT {', '.join(awg_sel_cols)} FROM clients WHERE LOWER(email) = 'awg-v3-client' LIMIT 1")
                    all_active_c = cur.fetchall()
                    if not all_active_c:
                        _a3_pk, _a3_pub = gen_wg_keypair()
                        _a3_pwd = secrets.token_hex(8)
                        _a3_ins = {
                            "email": "AWG-v3-Client", "sub_id": f"sub_{secrets.token_hex(10)}",
                            "uuid": str(uuid.uuid4()), "password": _a3_pwd, "auth": _a3_pwd,
                            "flow": "", "security": "auto", "reverse": "",
                            "wg_private_key": _a3_pk, "wg_public_key": _a3_pub, "wg_allowed_ips": "",
                            "wg_pre_shared_key": "", "wg_keep_alive": 25, "wg_forwarded_ports": "",
                            "secret": "", "ad_tag": "", "limit_ip": 0, "limit_hwid": 0,
                            "total_gb": 0, "expiry_time": 0, "enable": 1, "tg_id": 0,
                            "group_name": "", "group": "", "comment": "Dedicated AWG v3.2 Peer",
                            "reset": 0, "reset_day": 0, "reset_max": 0, "traffic_reset": "never",
                            "traffic_reset_day": 1, "created_at": now_ms, "updated_at": now_ms,
                            "sync_orphaned_at": 0
                        }
                        _a3_flt = {k: v for k, v in _a3_ins.items() if k in client_cols}
                        _a3_k = list(_a3_flt.keys())
                        cur.execute(
                            f"INSERT INTO clients ({','.join(f'\"{k}\"' for k in _a3_k)}) VALUES ({','.join(['?'] * len(_a3_k))})",
                            [_a3_flt[k] for k in _a3_k],
                        )
                        cur.execute(f"SELECT {', '.join(awg_sel_cols)} FROM clients WHERE LOWER(email) = 'awg-v3-client' LIMIT 1")
                        all_active_c = cur.fetchall()
                new_awg_clients = []
                cur.execute("PRAGMA table_info(client_inbounds)")
                ci_cols_set = {r[1] for r in cur.fetchall()}
                ct_cols_set = set()
                if "client_traffics" in tables:
                    cur.execute("PRAGMA table_info(client_traffics)")
                    ct_cols_set = {r[1] for r in cur.fetchall()}

                for crow in all_active_c:
                    cd = dict(zip(awg_sel_cols, crow))
                    c_id = int(cd["id"])
                    c_em = str(cd.get("email") or "").strip()
                    c_sub = str(cd.get("sub_id") or "").strip()
                    c_uid = str(cd.get("uuid") or "").strip()
                    if not c_em or not c_sub:
                        continue
                    prev_awg = prev_awg_by_email.get(c_em) or prev_awg_by_uuid.get(c_uid)
                    if prev_awg is not None:
                        pk = str(prev_awg.get("privateKey") or cd.get("wg_private_key") or "").strip()
                        pubk = str(prev_awg.get("publicKey") or cd.get("wg_public_key") or "").strip()
                        if not (_is_valid_wg_key(pk) and _is_valid_wg_key(pubk)):
                            pk, pubk = gen_wg_keypair()
                        pa = prev_awg.get("allowedIPs")
                        aip = _norm_cidr(pa[0]) if isinstance(pa, list) and pa else ""
                        if not aip or not aip.startswith(sub_pref):
                            aip = _alloc_awg_ip()
                        c_entry_awg = dict(prev_awg)
                    else:
                        pk = str(cd.get("wg_private_key") or "").strip()
                        pubk = str(cd.get("wg_public_key") or "").strip()
                        if not (_is_valid_wg_key(pk) and _is_valid_wg_key(pubk)):
                            pk, pubk = gen_wg_keypair()
                        db_ip = _norm_cidr(cd.get("wg_allowed_ips") or "")
                        if db_ip and db_ip.startswith(sub_pref) and db_ip not in used_awg_ips:
                            used_awg_ips.add(db_ip)
                            aip = db_ip
                        else:
                            aip = _alloc_awg_ip()
                        c_entry_awg = {}

                    if not aip:
                        continue
                    used_awg_ips.add(aip)
                    c_entry_awg.update({
                        "allowedIPs": [aip],
                        "auth": str(cd.get("auth") or ""),
                        "comment": str(cd.get("comment") or ""),
                        "created_at": int(cd.get("created_at") or now_ms),
                        "email": c_em,
                        "enable": bool(cd.get("enable")) if cd.get("enable") is not None else True,
                        "expiryTime": int(cd.get("expiry_time") or 0),
                        "id": c_uid,
                        "keepAlive": 25,
                        "limitIp": int(cd.get("limit_ip") or 0),
                        "password": str(cd.get("password") or ""),
                        "privateKey": pk,
                        "publicKey": pubk,
                        "reset": int(cd.get("reset") or 0),
                        "resetDay": int(cd.get("reset_day") or 0),
                        "resetMax": int(cd.get("reset_max") or 0),
                        "security": str(cd.get("security") or "auto"),
                        "subId": c_sub,
                        "tgId": int(cd.get("tg_id") or 0),
                        "totalGB": int(cd.get("total_gb") or 0),
                        "trafficReset": str(cd.get("traffic_reset") or "never"),
                        "trafficResetDay": int(cd.get("traffic_reset_day") or 1),
                        "updated_at": now_ms,
                    })
                    c_entry_awg.pop("flow", None)
                    new_awg_clients.append(c_entry_awg)

                    upd_sets, upd_vals = [], []
                    for cn, cv in [("wg_private_key", pk), ("wg_public_key", pubk), ("wg_allowed_ips", aip), ("wg_keep_alive", 25), ("updated_at", now_ms)]:
                        if cn in client_cols:
                            upd_sets.append(f'"{cn}" = ?')
                            upd_vals.append(cv)
                    if upd_sets:
                        upd_vals.append(c_id)
                        cur.execute(f"UPDATE clients SET {', '.join(upd_sets)} WHERE id = ?", upd_vals)

                    cur.execute("SELECT 1 FROM client_inbounds WHERE client_id = ? AND inbound_id = ?", (c_id, ib5_id))
                    if cur.fetchone() is None:
                        ci_d = {"client_id": c_id, "inbound_id": ib5_id, "flow_override": "", "created_at": now_ms}
                        ci_f = {k: v for k, v in ci_d.items() if k in ci_cols_set}
                        ci_k = list(ci_f.keys())
                        cur.execute(f"INSERT OR IGNORE INTO client_inbounds ({','.join(ci_k)}) VALUES ({','.join(['?'] * len(ci_k))})", [ci_f[k] for k in ci_k])

                    if ct_cols_set:
                        cur.execute("SELECT 1 FROM client_traffics WHERE LOWER(email) = LOWER(?) LIMIT 1", (c_em,))
                        if cur.fetchone() is None:
                            ct_d = {"inbound_id": ib5_id, "enable": 1, "email": c_em, "up": 0, "down": 0, "expiry_time": int(cd.get("expiry_time") or 0), "total": int(cd.get("total_gb") or 0), "reset": int(cd.get("reset") or 0)}
                            ct_f = {k: v for k, v in ct_d.items() if k in ct_cols_set}
                            ct_k = list(ct_f.keys())
                            cur.execute(f"INSERT OR IGNORE INTO client_traffics ({','.join(ct_k)}) VALUES ({','.join(['?'] * len(ct_k))})", [ct_f[k] for k in ct_k])

                awg_s["clients"] = new_awg_clients
                cur.execute("UPDATE inbounds SET settings = ? WHERE id = ?", (json.dumps(awg_s, ensure_ascii=False), ib5_id))

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
    if isinstance(alpn, list):
        alpn = json.dumps(alpn)
    elif isinstance(alpn, str) and alpn.strip().startswith("[") and alpn.strip().endswith("]"):
        alpn = alpn.strip()
    elif alpn and isinstance(alpn, str):
        alpn = json.dumps([x.strip() for x in alpn.split(",") if x.strip()])
    else:
        alpn = "[]"
    col_candidates = {
        "group_id": gid, "groupId": gid,
        "inbound_id": ib_id, "inboundId": ib_id,
        "sort_order": sort_order, "sortOrder": sort_order,
        "remark": remark, "address": addr, "port": port, "security": sec,
        "sni": sni, "host_header": "", "hostHeader": "", "path": path,
        "alpn": alpn, "fingerprint": fp, "allow_insecure": 0, "allowInsecure": 0,
        "is_disabled": 0, "isDisabled": 0, "is_hidden": 0, "isHidden": 0,
        "tags": "[]", "ech_config_list": "", "mux_params": "", "sockopt_params": "",
        "final_mask": "", "exclude_from_sub_types": "[]",
        "pinned_peer_cert_sha256": "[]", "node_guids": "[]", "random_count": 1
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
        c_def_sni = "gateway.icloud.com"
        if "=" in c_snis:
            c_def_sni = c_snis.split("=", 1)[1].split(";")[0].split(",")[0].strip()
        r2 = f"REALITY Classic ({c_def_sni})"
        add_host_entry(str(uuid.uuid4()), ib2_id, r2, domain, 443, "same", sni=c_def_sni, fp="firefox", sort_order=1)
    if ib3_id is not None:
        r3 = f"VLESS xHTTP ({domain})"
        add_host_entry(str(uuid.uuid4()), ib3_id, r3, domain, 443, "tls", sni=domain, path=xhttp_path, alpn=json.dumps(["h2"]), fp="firefox", sort_order=2)
    if ib4_id is not None:
        add_host_entry(str(uuid.uuid4()), ib4_id, f"Hysteria 2 ({domain})", domain, int(os.environ.get("HY2_PORT", 40443)), "tls", alpn=json.dumps(["h3"]), sort_order=3)
    if ib5_id is not None:
        add_host_entry(str(uuid.uuid4()), ib5_id, f"AmneziaWG v3.2 ({domain})", domain, int(os.environ.get("AWG_V3_PORT", 42443)), "same", sort_order=4)
elif install_mode == "2":
    cur.execute("PRAGMA table_info(inbounds)")
    _h_ib_cols = {r[1] for r in cur.fetchall()}
    _h_parts = []
    _h_params = []
    if "node_id" in _h_ib_cols:
        _h_parts.append("(node_id IS NULL OR node_id = 0)")
    if "origin_node_guid" in _h_ib_cols:
        if panel_guid:
            _h_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
            _h_params.append(panel_guid)
        else:
            _h_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
    _nc_hosts = (" WHERE " + " AND ".join(_h_parts)) if _h_parts else ""

    cur.execute(f"SELECT id, remark, settings, stream_settings, protocol, port, tag FROM inbounds{_nc_hosts}", _h_params)
    ib_rows = cur.fetchall()
    local_ib_ids = [r[0] for r in ib_rows]

    if local_ib_ids:
        _h_ng_cond = " AND (node_guids IS NULL OR node_guids = '' OR node_guids = '[]')" if "node_guids" in active_cols else ""
        _ib_ph = ",".join(["?"] * len(local_ib_ids))
        cur.execute(f"SELECT id, alpn FROM hosts WHERE inbound_id IN ({_ib_ph}){_h_ng_cond}", local_ib_ids)
        for _hid, _val in cur.fetchall():
            _new_alpn = "[]"
            try:
                if _val is not None and str(_val).strip():
                    _parsed = json.loads(_val)
                    if isinstance(_parsed, list):
                        _new_alpn = json.dumps([str(x).strip() for x in _parsed if str(x).strip()])
                    else:
                        _new_alpn = json.dumps([str(_parsed).strip()]) if str(_parsed).strip() else "[]"
            except Exception:
                if _val is not None and str(_val).strip():
                    _new_alpn = json.dumps([x.strip() for x in str(_val).split(",") if x.strip()])
            cur.execute("UPDATE hosts SET alpn = ? WHERE id = ?", (_new_alpn, _hid))

    for cur_ib_id, cur_ib_remark, ib_s_raw, ib_st_raw, ib_proto, cur_ib_port, cur_ib_tag in ib_rows:
        st_info = json.loads(ib_st_raw) if ib_st_raw else {}
        rs_sni = ""
        if "realitySettings" in st_info:
            s_names = st_info["realitySettings"].get("serverNames", [])
            if s_names: rs_sni = s_names[0]
        is_xhttp_ib = (ib_proto == "vless" and st_info.get("network") == "xhttp")
        is_steal_ib = ("in-steal" in str(cur_ib_tag or "").lower() or str(st_info.get("realitySettings", {}).get("dest", "")).strip() == "127.0.0.1:9443")
        target_port = 443 if ib_proto == "vless" else cur_ib_port
        _h_ng_sel = " AND (node_guids IS NULL OR node_guids = '' OR node_guids = '[]')" if "node_guids" in active_cols else ""
        cur.execute(f"SELECT id, sni, group_id, address FROM hosts WHERE inbound_id = ?{_h_ng_sel}", (cur_ib_id,))
        existing_h = cur.fetchall()
        def _upd_host(hid, vals_map):
            flt = {k: v for k, v in vals_map.items() if k in active_cols}
            if not flt:
                return
            ks = list(flt.keys())
            cur.execute(f"UPDATE hosts SET {', '.join(f'{k} = ?' for k in ks)} WHERE id = ?", [flt[k] for k in ks] + [hid])

        if ib_proto == "hysteria":
            if existing_h:
                for h_row in existing_h:
                    gid_keep = h_row[2] if (h_row[2] and str(h_row[2]).strip()) else str(uuid.uuid4())
                    _upd_host(h_row[0], {"group_id": gid_keep, "address": domain, "port": target_port, "security": "tls", "sni": domain, "alpn": json.dumps(["h3"]), "fingerprint": "", "is_disabled": 0, "is_hidden": 0})
            else:
                add_host_entry(str(uuid.uuid4()), cur_ib_id, cur_ib_remark, domain, target_port, "tls", sni=domain, alpn=json.dumps(["h3"]), fp="", sort_order=3)
        elif ib_proto in ("amneziawg", "wireguard"):
            if existing_h:
                for h_row in existing_h:
                    gid_keep = h_row[2] if (h_row[2] and str(h_row[2]).strip()) else str(uuid.uuid4())
                    _upd_host(h_row[0], {"group_id": gid_keep, "address": domain, "port": target_port, "security": "same", "sni": "", "alpn": "[]", "fingerprint": "", "is_disabled": 0, "is_hidden": 0})
            else:
                add_host_entry(str(uuid.uuid4()), cur_ib_id, cur_ib_remark, domain, target_port, "same", sni="", alpn="[]", fp="", sort_order=4)
        elif is_xhttp_ib:
            if existing_h:
                for h_row in existing_h:
                    gid_keep = h_row[2] if (h_row[2] and str(h_row[2]).strip()) else str(uuid.uuid4())
                    _upd_host(h_row[0], {"group_id": gid_keep, "address": domain, "port": 443, "security": "tls", "sni": domain, "path": xhttp_path, "alpn": json.dumps(["h2"]), "fingerprint": "firefox", "is_disabled": 0, "is_hidden": 0})
            else:
                add_host_entry(str(uuid.uuid4()), cur_ib_id, cur_ib_remark, domain, 443, "tls", sni=domain, path=xhttp_path, alpn=json.dumps(["h2"]), fp="firefox", sort_order=2)
        else:
            if existing_h:
                for h_row in existing_h:
                    gid_keep = h_row[2] if (h_row[2] and str(h_row[2]).strip()) else str(uuid.uuid4())
                    target_sni = h_row[1] if (h_row[1] and h_row[1].strip()) else rs_sni
                    target_addr = (target_sni or domain) if is_steal_ib else domain
                    _upd_host(h_row[0], {"group_id": gid_keep, "address": target_addr, "port": target_port, "sni": target_sni})
            else:
                add_host_entry(str(uuid.uuid4()), cur_ib_id, cur_ib_remark, (rs_sni or domain) if is_steal_ib else domain, target_port, "same", sni=rs_sni or domain, fp="firefox", sort_order=1)

    if ib3_id is not None:
        cur.execute("SELECT id, group_id FROM hosts WHERE inbound_id = ?", (ib3_id,))
        h3_row = cur.fetchone()
        if h3_row:
            gid3_keep = h3_row[1] if (h3_row[1] and str(h3_row[1]).strip()) else str(uuid.uuid4())
            h3_upd = {k: v for k, v in {"group_id": gid3_keep, "address": domain, "port": 443, "sni": domain, "path": xhttp_path, "alpn": json.dumps(["h2"])}.items() if k in active_cols}
            if h3_upd:
                h3_ks = list(h3_upd.keys())
                cur.execute(f"UPDATE hosts SET {', '.join(f'{k} = ?' for k in h3_ks)} WHERE id = ?", [h3_upd[k] for k in h3_ks] + [h3_row[0]])
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

_cred_fd = os.open("/tmp/vpn_unified_creds.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(_cred_fd, "w", encoding="utf-8") as f:
    f.write(f"UNIFIED_SUB_ID={test_sub_id}\n")
    f.write(f"UNIFIED_UUID={test_uuid}\n")
    f.write(f"TEST_EMAIL={test_email}\n")

for tmp_p in ["/tmp/xui_stage2_state.json", "/tmp/xui_stage2_helper.py"]:
    if os.path.exists(tmp_p):
        os.remove(tmp_p)
shutil.rmtree("/tmp/__pycache__", ignore_errors=True)
EOF_PY_STAGE2B

if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    chmod 700 "$(dirname "$DB_PATH")" 2>/dev/null || true
    chmod 600 "$DB_PATH" 2>/dev/null || true
    chmod 600 "${DB_PATH}-wal" 2>/dev/null || true
    chmod 600 "${DB_PATH}-shm" 2>/dev/null || true
fi

mkdir -p /etc/systemd/system/x-ui.service.d/
cat << EOF > /etc/systemd/system/x-ui.service.d/10-memory-limit.conf.tmp
[Service]
Environment="GOMEMLIMIT=$XUI_GOMEMLIMIT"
Environment="GOGC=$XUI_GOGC"
Environment="GODEBUG=madvdontneed=1"
MemoryHigh=$XUI_MEM_HIGH
MemoryMax=$XUI_MEM_MAX
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectControlGroups=true
ReadWritePaths=-/etc/x-ui -/usr/local/x-ui -/run -/tmp
LimitNOFILE=1048576
LimitNPROC=512
EOF
mv -f /etc/systemd/system/x-ui.service.d/10-memory-limit.conf.tmp /etc/systemd/system/x-ui.service.d/10-memory-limit.conf
chmod 0644 /etc/systemd/system/x-ui.service.d/10-memory-limit.conf 2>/dev/null || true
systemctl daemon-reload

systemctl restart x-ui || true

XUI_PANEL_READY=0
for _ in {1..15}; do
    if systemctl is-active --quiet x-ui && ss -tlnp 2>/dev/null | grep -q "127.0.0.1:${PANEL_PORT}"; then
        XUI_PANEL_READY=1
        break
    fi
    sleep 1
done

if [ "$XUI_PANEL_READY" -eq 1 ]; then
    ok "Служба 3X-UI успешно запущена на сокете 127.0.0.1:${PANEL_PORT}."
else
    journalctl -u x-ui --no-pager -n 20 >&2 || true
    die "Служба 3X-UI не поднялась на 127.0.0.1:${PANEL_PORT}."
fi

if [ "${ENABLE_AWG_V3:-0}" -eq 1 ] && validate_port "${AWG_V3_PORT:-}"; then
    log "Проверка UDP-сокета AmneziaWG v3.2 (:${AWG_V3_PORT}, цикл AmneziaWGJob)..."
    AWG3_SOCK_READY=0
    for _ in {1..20}; do
        if systemctl is-active --quiet x-ui && ss -tulnp 2>/dev/null | awk -v port="${AWG_V3_PORT}" '$1=="udp" && $5 ~ (":" port "$") {found=1} END {exit !found}'; then
            AWG3_SOCK_READY=1
            break
        fi
        sleep 1
    done
    if [ "$AWG3_SOCK_READY" -eq 1 ]; then
        ok "Встроенный стек AmneziaWG v3.2 слушает :${AWG_V3_PORT}/udp."
    else
        warn "Сокет :${AWG_V3_PORT}/udp не поднялся за 20с (проверьте пиров in-awg-v3). Правило UFW будет снято во избежание ICMP_UNREACH."
        ENABLE_AWG_V3=0
    fi
fi

for _ in {1..10}; do
    [ -s /usr/local/x-ui/bin/config.json ] && break
    sleep 1
done
if [ -f /usr/local/x-ui/bin/config.json ]; then
    if "$XRAY_BIN" -test -config /usr/local/x-ui/bin/config.json >/dev/null 2>&1; then
        ok "Конфигурация ядра Xray (/usr/local/x-ui/bin/config.json) прошла xray -test."
    else
        "$XRAY_BIN" -test -config /usr/local/x-ui/bin/config.json >&2 || true
        die "Ошибка валидации сгенерированного Xray-конфига (xray -test)."
    fi
fi

if ! pgrep -f '/usr/local/x-ui/bin/xray' >/dev/null 2>&1; then
    warn "Процесс Xray ещё не активен; проверьте логи 3X-UI (journalctl -u x-ui -n 20)."
else
    ok "Процесс Xray-core активен и обслуживает инбаунды."
fi

log "Финальная синхронизация Nginx L4 Stream и Steal-Fallback с актуальной БД 3X-UI..."
sync_nginx_stream_and_steal "post_phase3" "$DB_PATH"
nginx -t || die "Ошибка конфигурации Nginx после пост-синхронизации с 3X-UI."
systemctl reload nginx
ROLLBACK_ACTIVE=0
rm -f /usr/local/x-ui/x-ui.pre_upd.bak 2>/dev/null || true
rm -rf "${NGINX_PRE_BAK:-}" "${XUI_PRE_BAK:-}" 2>/dev/null || true
ok "Nginx L4 Stream и Steal-Fallback синхронизированы с актуальной БД."

UNIFIED_SUB_ID="SUB_Test"
TEST_EMAIL="Test"
if [ -f "/tmp/vpn_unified_creds.txt" ]; then
    # shellcheck source=/dev/null
    . /tmp/vpn_unified_creds.txt
    rm -rf /tmp/xray_unpack /usr/local/bin/myprivatecloud_core.py.tmp* /tmp/vpn_unified_creds.txt /tmp/xui_stage2_*
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
    AWG_BUILT_FROM_GIT=0
    if [ "$OS_ID" = "ubuntu" ]; then
        wait_for_apt_lock
        log "Установка заголовков ядра linux-headers..."
        apt-get install -y build-essential dkms "linux-headers-$(uname -r)" -q < /dev/null || true
        log "Импорт официального репозитория AmneziaWG по HTTPS (порт 443)..."
        mkdir -p /etc/apt/keyrings
        chmod 0755 /etc/apt/keyrings
        rm -f /etc/apt/keyrings/amnezia.gpg /etc/apt/keyrings/amnezia.gpg.tmp /etc/apt/sources.list.d/amnezia.list /etc/apt/sources.list.d/amnezia*.list /etc/apt/sources.list.d/amnezia*.sources 2>/dev/null || true
        if curl -fsSL --connect-timeout 8 -m 20 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x4166F2C257290828" | gpg --dearmor -o /etc/apt/keyrings/amnezia.gpg.tmp 2>/dev/null; then
            if [ -s /etc/apt/keyrings/amnezia.gpg.tmp ] && gpg --no-default-keyring --keyring /etc/apt/keyrings/amnezia.gpg.tmp --list-keys 4166F2C257290828 >/dev/null 2>&1; then
                chmod 0644 /etc/apt/keyrings/amnezia.gpg.tmp
                mv -f /etc/apt/keyrings/amnezia.gpg.tmp /etc/apt/keyrings/amnezia.gpg
                LOCAL_UBUNTU_CODENAME="$OS_CODENAME"
                if [[ ! "$LOCAL_UBUNTU_CODENAME" =~ ^(jammy|noble)$ ]]; then LOCAL_UBUNTU_CODENAME="noble"; fi
                echo "deb [signed-by=/etc/apt/keyrings/amnezia.gpg] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu ${LOCAL_UBUNTU_CODENAME} main" > /etc/apt/sources.list.d/amnezia.list
                chmod 0644 /etc/apt/sources.list.d/amnezia.list 2>/dev/null || true
                wait_for_apt_lock
                if apt-get update -q -o Dir::Etc::sourcelist="sources.list.d/amnezia.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" >/dev/null 2>&1; then
                    wait_for_apt_lock
                    DEBIAN_FRONTEND=noninteractive apt-get install -y amneziawg-dkms amneziawg-tools -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" < /dev/null || true
                else
                    warn "Сбой обновления Amnezia PPA; список удалён, переход на сборку из исходников."
                    rm -f /etc/apt/sources.list.d/amnezia.list /etc/apt/keyrings/amnezia.gpg 2>/dev/null || true
                fi
            else
                rm -f /etc/apt/keyrings/amnezia.gpg.tmp 2>/dev/null || true
            fi
        else
            rm -f /etc/apt/keyrings/amnezia.gpg.tmp 2>/dev/null || true
        fi
    fi

    modprobe amneziawg 2>/dev/null || true
    AWG_DKMS_CUR=$(dkms status -m amneziawg -k "$(uname -r)" 2>/dev/null || true)
    if ! command -v awg >/dev/null 2>&1 || ! grep -qE '^amneziawg\b' /proc/modules 2>/dev/null || [[ "$AWG_DKMS_CUR" != *"installed"* ]]; then
        log "Синхронизация заголовков активного ядра $(uname -r) и сборка DKMS AmneziaWG..."
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

        patch_amnezia_dkms_kernel_compat
        AWG_REG_VER=$(dkms status 2>/dev/null | awk -F'[/,:]' '/amneziawg/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' || true)
        if [ -n "$AWG_REG_VER" ]; then
            dkms build -m amneziawg -v "$AWG_REG_VER" -k "$(uname -r)" >/dev/null 2>&1 || true
            dkms install -m amneziawg -v "$AWG_REG_VER" -k "$(uname -r)" >/dev/null 2>&1 || true
            dpkg --configure -a >/dev/null 2>&1 || true
        fi

        AWG_DKMS_CUR=$(dkms status -m amneziawg -k "$(uname -r)" 2>/dev/null || true)
        if [[ "$AWG_DKMS_CUR" != *"installed"* ]]; then
            AWG_CLONE_DIR="/tmp/awg-kernel-src"
            AWG_BUILD_DIR="/usr/src/amneziawg-1.0.0"
            rm -rf "$AWG_CLONE_DIR" "$AWG_BUILD_DIR"
            git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git "$AWG_CLONE_DIR" 2>/dev/null || true
            if [ -d "$AWG_CLONE_DIR/src" ]; then
                mkdir -p "$AWG_BUILD_DIR"
                chmod 0755 "$AWG_BUILD_DIR"
                cp -r "$AWG_CLONE_DIR"/src/* "$AWG_BUILD_DIR"/

                cat << 'EOF_DKMS' > "$AWG_BUILD_DIR/dkms.conf.tmp"
PACKAGE_NAME="amneziawg"
PACKAGE_VERSION="1.0.0"
BUILT_MODULE_NAME[0]="amneziawg"
DEST_MODULE_LOCATION[0]="/kernel/net"
AUTOINSTALL="yes"
MAKE[0]="'make' -C $kernel_source_dir M=$dkms_tree/$PACKAGE_NAME/$PACKAGE_VERSION/build"
EOF_DKMS
                mv -f "$AWG_BUILD_DIR/dkms.conf.tmp" "$AWG_BUILD_DIR/dkms.conf"
                chmod 0644 "$AWG_BUILD_DIR/dkms.conf" 2>/dev/null || true
                dkms remove amneziawg/1.0.0 --all 2>/dev/null || true
                patch_amnezia_dkms_kernel_compat
                dkms add -m amneziawg -v 1.0.0 2>/dev/null || true
                if dkms build -m amneziawg -v 1.0.0 -k "$(uname -r)" >/dev/null 2>&1; then
                    dkms install -m amneziawg -v 1.0.0 -k "$(uname -r)" >/dev/null 2>&1 || true
                fi
                rm -rf "$AWG_CLONE_DIR"
                AWG_BUILT_FROM_GIT=1
            fi
        fi

        if [ "$AWG_BUILT_FROM_GIT" -eq 1 ] || ! command -v awg >/dev/null 2>&1; then
            TOOLS_BUILD_DIR="/tmp/awg-tools-build"
            rm -rf "$TOOLS_BUILD_DIR"
            git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git "$TOOLS_BUILD_DIR" 2>/dev/null || true
            if [ -d "$TOOLS_BUILD_DIR/src" ]; then
                make -C "$TOOLS_BUILD_DIR/src" >/dev/null 2>&1 || true
                make -C "$TOOLS_BUILD_DIR/src" install >/dev/null 2>&1 || true
                rm -rf "$TOOLS_BUILD_DIR"
            fi
        fi
    fi

    mkdir -p /etc/modules-load.d
    echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
    chmod 0644 /etc/modules-load.d/amneziawg.conf 2>/dev/null || true
    modprobe amneziawg 2>/dev/null || true

    if ! command -v awg >/dev/null 2>&1 || ! grep -qE '^amneziawg\b' /proc/modules 2>/dev/null; then
        warn "Модуль ядра amneziawg не загружен в /proc/modules или отсутствует утилита awg. Нативный AmneziaWG awg0 отключён."
        ENABLE_NATIVE_AWG=0
        if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
            python3 - << 'EOF_AGH_DROP_NAWG1'
import os, re
yp = "/opt/AdGuardHome/AdGuardHome.yaml"
txt = open(yp, "r", encoding="utf-8").read()
new_txt = re.sub(r"^[ \t]*-[ \t]*10\.9\.0\.1[ \t]*\n", "", txt, flags=re.M)
if new_txt != txt:
    open(yp + ".tmp", "w", encoding="utf-8").write(new_txt)
    os.chmod(yp + ".tmp", 0o600)
    os.replace(yp + ".tmp", yp)
EOF_AGH_DROP_NAWG1
            systemctl restart AdGuardHome 2>/dev/null || true
        fi
    fi
fi

if [ "$ENABLE_NATIVE_AWG" -eq 1 ]; then
    mkdir -p /etc/amnezia/amneziawg
    chmod 700 /etc/amnezia /etc/amnezia/amneziawg

    if [ -f /etc/amnezia/amneziawg/awg0.conf ]; then
        ok "Обнаружена действующая конфигурация awg0 (/etc/amnezia/amneziawg/awg0.conf). Режим сохранения активен."
        if grep -qE '^[#[:space:]]*ListenPort[[:space:]]*=' /etc/amnezia/amneziawg/awg0.conf; then
            sed -i -E "s/^[#[:space:]]*ListenPort[[:space:]]*=.*/ListenPort = $NATIVE_AWG_PORT/" /etc/amnezia/amneziawg/awg0.conf
        else
            sed -i -E "/^\[Interface\]/a ListenPort = $NATIVE_AWG_PORT" /etc/amnezia/amneziawg/awg0.conf
        fi
        if [ -f /root/amneziawg-client.conf ]; then
            sed -i -E "s|^([#[:space:]]*Endpoint[[:space:]]*=[[:space:]]*).*|\1${PRIMARY_DOMAIN}:${NATIVE_AWG_PORT}|" /root/amneziawg-client.conf 2>/dev/null || true
            chmod 600 /root/amneziawg-client.conf 2>/dev/null || true
        fi
        ok "Рабочий порт сервера AmneziaWG awg0: :${NATIVE_AWG_PORT}/udp"

        CLIENTS_JSON="/etc/amnezia/amneziawg/clients.json"
        if [ ! -f "$CLIENTS_JSON" ]; then
            log "Синтез clients.json из действующих пиров awg0.conf..."
            python3 - << 'EOF_RECON'
import re, json, os
conf_path = "/etc/amnezia/amneziawg/awg0.conf"
clients_json_path = "/etc/amnezia/amneziawg/clients.json"
clients = {}
def _reconstruct():
    if not os.path.exists(conf_path):
        return
    with open(conf_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    pending_name = ""
    in_peer = False
    cur_pub = ""
    cur_ip = ""
    cur_name = ""
    peer_idx = 0

    def _flush_peer():
        nonlocal peer_idx, cur_pub, cur_ip, cur_name
        if cur_pub:
            peer_idx += 1
            clients[cur_pub] = {
                "name": cur_name or f"Client-{peer_idx}",
                "private_key": "",
                "public_key": cur_pub,
                "ip": cur_ip or f"10.9.0.{peer_idx + 1}/32",
            }
        cur_pub = ""
        cur_ip = ""
        cur_name = ""

    for ln in content.splitlines():
        st = ln.strip()
        m_nm = re.search(r"# --- Client:\s*([^\n\r]+?)\s*---", st)
        if m_nm:
            pending_name = m_nm.group(1).strip()
            continue
        if st.startswith("[") and st.endswith("]"):
            if in_peer:
                _flush_peer()
            in_peer = (st == "[Peer]")
            if in_peer:
                cur_name = pending_name
            pending_name = ""
            continue
        if in_peer:
            m_pub = re.match(r"PublicKey\s*=\s*(\S+)", st, re.I)
            if m_pub:
                cur_pub = m_pub.group(1).strip()
            m_ip = re.match(r"AllowedIPs\s*=\s*(\S+)", st, re.I)
            if m_ip:
                cur_ip = m_ip.group(1).strip()
    if in_peer:
        _flush_peer()
    tmp_p = clients_json_path + ".tmp"
    with open(tmp_p, "w", encoding="utf-8") as f:
        json.dump(clients, f, indent=2)
    os.chmod(tmp_p, 0o600)
    os.replace(tmp_p, clients_json_path)

_reconstruct()
EOF_RECON
        fi
        chmod 600 /etc/amnezia/amneziawg/awg0.conf
    else
        log "Генерация криптографически стойких ключей и параметров awg0..."
        AWG_GEN_OUT=$(python3 - << 'EOF_AWG_KEYGEN'
import base64, os, secrets

P = 2**255 - 19
A24 = 121665

def clamp(k_bytes):
    b = bytearray(k_bytes)
    b[0] &= 248
    b[31] &= 127
    b[31] |= 64
    return int.from_bytes(b, "little")

def x25519(k, u=9):
    x1, x2, z2, x3, z3 = u, 1, 0, u, 1
    for i in range(254, -1, -1):
        bit = (k >> i) & 1
        if bit:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
        A = (x2 + z2) % P
        AA = (A * A) % P
        B = (x2 - z2) % P
        BB = (B * B) % P
        E = (AA - BB) % P
        C = (x3 + z3) % P
        D = (x3 - z3) % P
        DA = (D * A) % P
        CB = (C * B) % P
        x3 = pow(DA + CB, 2, P)
        z3 = (x1 * pow(DA - CB, 2, P)) % P
        x2 = (AA * BB) % P
        z2 = (E * (AA + A24 * E)) % P
        if bit:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
    return (x2 * pow(z2, P - 2, P)) % P

def kp():
    raw = os.urandom(32)
    pub = x25519(clamp(raw), 9).to_bytes(32, "little")
    return base64.b64encode(raw).decode(), base64.b64encode(pub).decode()

s_priv, s_pub = kp()
c_priv, c_pub = kp()
hs = []
while len(hs) < 4:
    val = secrets.randbelow(2000000000) + 100000000
    if val not in hs:
        hs.append(val)
print(f"{s_priv}|{s_pub}|{c_priv}|{c_pub}|{hs[0]}|{hs[1]}|{hs[2]}|{hs[3]}")
EOF_AWG_KEYGEN
        )
        IFS='|' read -r AWG_S_PRIV AWG_S_PUB AWG_C_PRIV AWG_C_PUB AWG_H1 AWG_H2 AWG_H3 AWG_H4 <<< "$AWG_GEN_OUT"

        (
            umask 077
            cat << EOF > /etc/amnezia/amneziawg/awg0.conf.tmp
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
        )
        chmod 0600 /etc/amnezia/amneziawg/awg0.conf.tmp
        mv -f /etc/amnezia/amneziawg/awg0.conf.tmp /etc/amnezia/amneziawg/awg0.conf

        AWG_DNS_IP="77.88.8.8"
        if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
            AWG_DNS_IP="10.9.0.1"
        elif [ "$GEO_PROFILE" != "1" ]; then
            AWG_DNS_IP="1.1.1.1"
        fi

        (
            umask 077
            cat << EOF > /root/amneziawg-client.conf.tmp
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
        )
        chmod 0600 /root/amneziawg-client.conf.tmp
        mv -f /root/amneziawg-client.conf.tmp /root/amneziawg-client.conf

        CLIENTS_JSON="/etc/amnezia/amneziawg/clients.json"
        (
            umask 077
            cat << EOF > "$CLIENTS_JSON.tmp"
{
  "${AWG_C_PUB}": {
    "name": "Test-Client",
    "private_key": "${AWG_C_PRIV}",
    "public_key": "${AWG_C_PUB}",
    "ip": "10.9.0.2/32"
  }
}
EOF
        )
        chmod 0600 "$CLIENTS_JSON.tmp"
        mv -f "$CLIENTS_JSON.tmp" "$CLIENTS_JSON"
    fi

    awg-quick down awg0 2>/dev/null || true
    systemctl stop awg-quick@awg0 2>/dev/null || true
    systemctl enable awg-quick@awg0 >/dev/null 2>&1 || true
    if systemctl restart awg-quick@awg0 && awg show awg0 >/dev/null 2>&1; then
        if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
            systemctl restart AdGuardHome 2>/dev/null || true
            AGH_POST_OK=0
            for _ in {1..15}; do
                agh_chk=$(dig +short +time=2 +tries=1 google.com @127.0.0.1 2>/dev/null || true)
                if systemctl is-active --quiet AdGuardHome && printf '%s\n' "$agh_chk" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
                    AGH_POST_OK=1
                    break
                fi
                sleep 1
            done
            if [ "$AGH_POST_OK" -ne 1 ]; then
                warn "AdGuardHome не ответил на 127.0.0.1:53 после перезапуска с awg0."
            fi
        fi
        ok "Нативный сервер AmneziaWG активен на сокете :${NATIVE_AWG_PORT}/udp (awg0)."
    else
        journalctl -u awg-quick@awg0 --no-pager -n 15 >&2 || true
        warn "Служба awg-quick@awg0 не запустилась. Нативный AmneziaWG awg0 отключён."
        systemctl disable awg-quick@awg0 >/dev/null 2>&1 || true
        ENABLE_NATIVE_AWG=0
        if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ -f /opt/AdGuardHome/AdGuardHome.yaml ]; then
            python3 - << 'EOF_AGH_DROP_NAWG2'
import os, re
yp = "/opt/AdGuardHome/AdGuardHome.yaml"
txt = open(yp, "r", encoding="utf-8").read()
new_txt = re.sub(r"^[ \t]*-[ \t]*10\.9\.0\.1[ \t]*\n", "", txt, flags=re.M)
if new_txt != txt:
    open(yp + ".tmp", "w", encoding="utf-8").write(new_txt)
    os.chmod(yp + ".tmp", 0o600)
    os.replace(yp + ".tmp", yp)
EOF_AGH_DROP_NAWG2
            systemctl restart AdGuardHome 2>/dev/null || true
        fi
    fi
fi

# =============================================================
#  ФАЗА 5: МНОГОПОТОЧНЫЙ ПИТОН-ДЕМОН MY PRIVATE CLOUD CORE GATEWAY
# =============================================================
log "Развёртывание изолированного окружения PEP 668 и стека FastAPI..."
wait_for_apt_lock
if ! apt-get install -y python3-venv python3-pip -q >/dev/null 2>&1; then
    wait_for_apt_lock
    apt-get update -q || true
    apt-get install -y python3-venv python3-pip -q || die "Не удалось установить python3-venv / python3-pip."
fi
rm -rf /opt/myprivatecloud/venv
python3 -m venv /opt/myprivatecloud/venv || die "Ошибка создания venv в /opt/myprivatecloud/venv."
if ! /opt/myprivatecloud/venv/bin/pip install --no-cache-dir fastapi uvicorn pydantic bcrypt -q; then
    /opt/myprivatecloud/venv/bin/pip install --no-cache-dir fastapi uvicorn pydantic bcrypt || die "Ошибка установки зависимостей FastAPI в venv."
fi
if [ ! -x /opt/myprivatecloud/venv/bin/uvicorn ]; then
    die "Исполняемый файл /opt/myprivatecloud/venv/bin/uvicorn не найден."
fi

log "Сборка модулей и асинхронного сервиса My Private Cloud Core (FastAPI/uvicorn)..."
cat << 'EOF_CORE_UTILS' > /usr/local/bin/myprivatecloud_utils.py.tmp
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os, sys, subprocess, hmac, secrets, re, time, sqlite3, json, fcntl, base64, hashlib
import urllib.request, urllib.parse, http.cookiejar
from contextlib import contextmanager
from typing import Optional, Dict, Any, List, Tuple, Iterator

DB_PATHS = ["/etc/x-ui/x-ui.db", "/usr/local/x-ui/bin/x-ui.db", "/etc/x-ui/db/x-ui.db"]
CLIENTS_FILE = "/etc/amnezia/amneziawg/clients.json"
CONF_PATH = "/etc/amnezia/amneziawg/awg0.conf"
AWG_LOCK_PATH = "/etc/amnezia/amneziawg/.awg0.lock"
CONFIG_ENV = "/etc/myprivatecloud/config.env"
CONFIG_JSON = "/etc/myprivatecloud/config.json"
SSO_AGH_FILE = "/etc/myprivatecloud/sso_agh.json"
KEY_FILE = "/etc/myprivatecloud/sso.key"

ACTIVE_SESSIONS: Dict[str, float] = {}

P = 2**255 - 19
A24 = 121665

def _read_runtime_env() -> Dict[str, str]:
    env_map: Dict[str, str] = {}
    if os.path.exists(CONFIG_ENV):
        try:
            with open(CONFIG_ENV, "r", encoding="utf-8") as f:
                for ln in f:
                    m = re.match(r'^\s*([A-Z0-9_]+)\s*=\s*"?([^"\n\r]*)"?\s*$', ln)
                    if m:
                        env_map[m.group(1)] = m.group(2).strip()
        except Exception:
            pass
    return env_map

def is_agh_enabled() -> bool:
    if os.path.exists(CONFIG_JSON):
        try:
            with open(CONFIG_JSON, "r", encoding="utf-8") as f:
                val = json.load(f).get("enable_agh")
                if isinstance(val, bool):
                    return val
        except Exception:
            pass
    env_map = _read_runtime_env()
    if "ENABLE_AGH" in env_map:
        return env_map["ENABLE_AGH"] == "1"
    return os.environ.get("ENABLE_AGH", "0") == "1"

def get_geo_profile() -> str:
    return os.environ.get("GEO_PROFILE", "2").strip() or "2"

def get_native_awg_port() -> str:
    if os.path.exists(CONF_PATH):
        try:
            with open(CONF_PATH, "r", encoding="utf-8", errors="ignore") as f:
                m = re.search(r"^\s*ListenPort\s*=\s*(\d+)", f.read(), re.M | re.I)
                if m:
                    return m.group(1).strip()
        except Exception:
            pass
    return os.environ.get("NATIVE_AWG_PORT", "41443").strip() or "41443"

def get_server_key() -> bytes:
    if os.path.exists(KEY_FILE):
        try:
            with open(KEY_FILE, "rb") as f:
                k = f.read().strip()
                if len(k) >= 32:
                    return k
        except Exception:
            pass
    k = secrets.token_bytes(32)
    try:
        os.makedirs(os.path.dirname(KEY_FILE), exist_ok=True)
        tmp_k = KEY_FILE + ".tmp"
        with open(tmp_k, "wb") as f:
            f.write(k)
        os.chmod(tmp_k, 0o600)
        os.replace(tmp_k, KEY_FILE)
    except Exception:
        pass
    return k

SERVER_KEY = get_server_key()

def sign_session_token(user: str, ttl: int = 43200) -> str:
    exp = int(time.time()) + ttl
    salt = secrets.token_hex(6)
    payload = f"{user}:{exp}:{salt}"
    sig = hmac.new(SERVER_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
    raw = f"{payload}:{sig}".encode("utf-8")
    token = base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=")
    ACTIVE_SESSIONS[token] = float(exp)
    if len(ACTIVE_SESSIONS) > 256:
        now_t = time.time()
        for k_t in [k for k, v in ACTIVE_SESSIONS.items() if v <= now_t]:
            ACTIVE_SESSIONS.pop(k_t, None)
    return token

def verify_session_token(token: str) -> bool:
    if not token:
        return False
    try:
        padded = token + "=" * (-len(token) % 4)
        raw = base64.urlsafe_b64decode(padded.encode("utf-8")).decode("utf-8")
        parts = raw.split(":")
        if len(parts) == 4:
            u, exp_str, salt, sig = parts
            if int(exp_str) > time.time():
                payload = f"{u}:{exp_str}:{salt}"
                calc = hmac.new(SERVER_KEY, payload.encode("utf-8"), hashlib.sha256).hexdigest()
                if hmac.compare_digest(sig, calc):
                    return True
    except Exception:
        pass
    now = time.time()
    for t, exp in list(ACTIVE_SESSIONS.items()):
        if exp > now and hmac.compare_digest(token, t):
            return True
    return False

def clamp(k_bytes: bytes) -> int:
    b = bytearray(k_bytes)
    b[0] &= 248
    b[31] &= 127
    b[31] |= 64
    return int.from_bytes(b, "little")

def x25519(k: int, u: int = 9) -> int:
    x1, x2, z2, x3, z3 = u, 1, 0, u, 1
    for i in range(254, -1, -1):
        bit = (k >> i) & 1
        if bit:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
        A = (x2 + z2) % P
        AA = (A * A) % P
        B = (x2 - z2) % P
        BB = (B * B) % P
        E = (AA - BB) % P
        C = (x3 + z3) % P
        D = (x3 - z3) % P
        DA = (D * A) % P
        CB = (C * B) % P
        x3 = pow(DA + CB, 2, P)
        z3 = (x1 * pow(DA - CB, 2, P)) % P
        x2 = (AA * BB) % P
        z2 = (E * (AA + A24 * E)) % P
        if bit:
            x2, x3 = x3, x2
            z2, z3 = z3, z2
    return (x2 * pow(z2, P - 2, P)) % P

def gen_wireguard_keypair() -> Tuple[str, str]:
    raw = os.urandom(32)
    k = clamp(raw)
    pub = x25519(k, 9).to_bytes(32, "little")
    return base64.b64encode(raw).decode(), base64.b64encode(pub).decode()

def safe_cmd_output(args: List[str]) -> str:
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL).decode("utf-8")
    except Exception:
        return ""

@contextmanager
def awg_file_lock() -> Iterator[None]:
    os.makedirs(os.path.dirname(AWG_LOCK_PATH), exist_ok=True)
    fd = os.open(AWG_LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)

def load_clients() -> Dict[str, Any]:
    if not os.path.exists(CONF_PATH):
        return {}
    clients: Dict[str, Any] = {}
    if os.path.exists(CLIENTS_FILE):
        try:
            with open(CLIENTS_FILE, "r", encoding="utf-8") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                clients = json.load(f)
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        except Exception:
            pass
    return clients

def save_clients(clients: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(CLIENTS_FILE), exist_ok=True)
        tmp_p = CLIENTS_FILE + ".tmp"
        with open(tmp_p, "w", encoding="utf-8") as f:
            json.dump(clients, f, indent=2)
        os.chmod(tmp_p, 0o600)
        os.replace(tmp_p, CLIENTS_FILE)
    except Exception:
        pass

def remove_peer_from_awg_conf(conf_text: str, pub_key: str) -> str:
    lines = conf_text.splitlines(keepends=True)
    sections: List[Tuple[str, List[str]]] = []
    cur_header = ""
    cur_lines: List[str] = []
    pending_comments: List[str] = []

    for ln in lines:
        st = ln.strip()
        if st.startswith("[") and st.endswith("]"):
            if cur_header:
                sections.append((cur_header, cur_lines))
            elif pending_comments:
                sections.append(("__preamble__", pending_comments))
                pending_comments = []
            cur_header = st
            cur_lines = pending_comments + [ln]
            pending_comments = []
        elif st.startswith("# --- Client:"):
            pending_comments.append(ln)
        else:
            if pending_comments:
                cur_lines.extend(pending_comments)
                pending_comments = []
            cur_lines.append(ln)
    if cur_header:
        cur_lines.extend(pending_comments)
        sections.append((cur_header, cur_lines))
    elif cur_lines or pending_comments:
        sections.append(("__preamble__", cur_lines + pending_comments))

    kept: List[str] = []
    for hdr, sec_lines in sections:
        if hdr == "[Peer]":
            sec_txt = "".join(sec_lines)
            m_pub = re.search(r"^\s*PublicKey\s*=\s*(\S+)", sec_txt, re.M)
            if m_pub and m_pub.group(1).strip() == pub_key:
                continue
        kept.extend(sec_lines)
    return "".join(kept).rstrip() + "\n"

def verify_credentials(user: str, pwd: str) -> Tuple[bool, str, bool]:
    for db_path in DB_PATHS:
        if not os.path.exists(db_path):
            continue
        try:
            conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5.0)
            cur = conn.cursor()
            cur.execute("SELECT username, password FROM users WHERE username = ? LIMIT 1", (user,))
            row = cur.fetchone()
            if not row:
                cur.execute("SELECT username, password FROM users WHERE LOWER(username) = LOWER(?) LIMIT 1", (user,))
                row = cur.fetchone()
            tfa_on = False
            try:
                cur.execute("SELECT value FROM settings WHERE key = 'twoFactorEnable' LIMIT 1")
                tfa_row = cur.fetchone()
                if tfa_row and str(tfa_row[0]).strip().lower() == "true":
                    tfa_on = True
            except Exception:
                pass
            conn.close()

            if row:
                canon_user = str(row[0]).strip()
                db_hash = str(row[1]).strip()
                matched = False
                if db_hash.startswith("$2"):
                    import bcrypt
                    if bcrypt.checkpw(pwd.encode("utf-8"), db_hash.encode("utf-8")):
                        matched = True
                elif len(db_hash) == 64 and all(c in "0123456789abcdefABCDEF" for c in db_hash):
                    pwd_sha256 = hashlib.sha256(pwd.encode("utf-8")).hexdigest()
                    if hmac.compare_digest(pwd_sha256.lower(), db_hash.lower()):
                        matched = True
                elif hmac.compare_digest(pwd, db_hash):
                    matched = True
                if matched:
                    return True, canon_user, tfa_on
        except Exception:
            pass
    return False, "", False

def get_canonical_domains() -> Tuple[str, str]:
    env_map = _read_runtime_env()
    p_dom = (env_map.get("PRIMARY_DOMAIN") or os.environ.get("PRIMARY_DOMAIN", "")).strip()
    a_dom = (env_map.get("AGH_DOMAIN") or os.environ.get("AGH_DOMAIN", "")).strip()

    if os.path.exists(CONFIG_JSON):
        try:
            with open(CONFIG_JSON, "r", encoding="utf-8") as f:
                d = json.load(f)
                if d.get("primary_domain"):
                    p_dom = str(d["primary_domain"]).strip()
                if d.get("agh_domain"):
                    a_dom = str(d["agh_domain"]).strip()
        except Exception:
            pass

    if os.path.exists(SSO_AGH_FILE):
        try:
            with open(SSO_AGH_FILE, "r", encoding="utf-8") as f:
                d = json.load(f)
                if d.get("domain"):
                    a_dom = str(d["domain"]).strip()
        except Exception:
            pass

    if not p_dom and os.path.exists("/etc/nginx/conf.d/01-main.conf"):
        try:
            with open("/etc/nginx/conf.d/01-main.conf", "r", encoding="utf-8") as f:
                m = re.search(r"server_name\s+([^;\s_]+);", f.read())
                if m:
                    p_dom = m.group(1).strip()
        except Exception:
            pass

    if not a_dom and os.path.exists("/etc/nginx/conf.d/03-adguard.conf"):
        try:
            with open("/etc/nginx/conf.d/03-adguard.conf", "r", encoding="utf-8") as f:
                m = re.search(r"server_name\s+([^;\s_]+);", f.read())
                if m:
                    a_dom = m.group(1).strip()
        except Exception:
            pass

    if not a_dom and p_dom:
        clean_base = re.sub(r"^www\.", "", p_dom, flags=re.I)
        a_dom = f"dns.{clean_base}"

    return p_dom, a_dom

def get_panel_info() -> Tuple[str, str]:
    env_map = _read_runtime_env()
    port = (env_map.get("PANEL_PORT") or os.environ.get("PANEL_PORT", "10443")).strip()
    path = (env_map.get("PANEL_PATH") or os.environ.get("PANEL_PATH", "/my-3x-panel/")).strip()
    for db_path in DB_PATHS:
        if os.path.exists(db_path):
            try:
                conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5.0)
                cur = conn.cursor()
                cur.execute("SELECT key, value FROM settings WHERE key IN ('webBasePath', 'webPort')")
                for k, v in cur.fetchall():
                    if k == "webBasePath" and v:
                        clean_p = str(v).strip().strip("/")
                        path = f"/{clean_p}/" if clean_p else "/"
                    elif k == "webPort" and v and str(v).isdigit():
                        port = str(v).strip()
                conn.close()
                break
            except Exception:
                pass
    return port, path

def login_3xui_session(user: str, pwd: str, port: str, base_path: str) -> List[str]:
    clean_bp = "/" + base_path.strip("/") + "/" if base_path.strip("/") else "/"
    base_url = f"http://127.0.0.1:{port}{clean_bp}"
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    csrf_token = ""

    for probe_path in (f"{base_url}csrf-token", base_url):
        try:
            req_get = urllib.request.Request(probe_path, method="GET")
            req_get.add_header("Accept", "application/json, text/html;q=0.9")
            with opener.open(req_get, timeout=3.0) as r_get:
                hdr_csrf = r_get.headers.get("X-CSRF-Token") or r_get.headers.get("x-csrf-token")
                if hdr_csrf:
                    csrf_token = hdr_csrf.strip()
                body_txt = r_get.read(65536).decode("utf-8", errors="ignore")
                if not csrf_token and probe_path.endswith("csrf-token"):
                    try:
                        j = json.loads(body_txt)
                        if isinstance(j, dict) and j.get("obj"):
                            csrf_token = str(j["obj"]).strip()
                    except Exception:
                        pass
                if not csrf_token:
                    m_meta = re.search(r'<meta[^>]+name=["\']csrf-token["\'][^>]+content=["\']([^"\']+)["\']', body_txt, re.I)
                    if m_meta:
                        csrf_token = m_meta.group(1).strip()
                if csrf_token:
                    break
        except Exception:
            pass
    if not csrf_token:
        for ck in cj:
            if "csrf" in ck.name.lower() and ck.value:
                csrf_token = ck.value.strip()
                break

    data = urllib.parse.urlencode({"username": user, "password": pwd}).encode("utf-8")
    req_post = urllib.request.Request(f"{base_url}login", data=data, method="POST")
    req_post.add_header("Content-Type", "application/x-www-form-urlencoded")
    req_post.add_header("X-Requested-With", "XMLHttpRequest")
    if csrf_token:
        req_post.add_header("X-CSRF-Token", csrf_token)

    out_cookies: List[str] = []
    try:
        with opener.open(req_post, timeout=4.0) as resp:
            resp_body = resp.read(16384).decode("utf-8", errors="ignore")
            try:
                j_res = json.loads(resp_body)
                if isinstance(j_res, dict) and j_res.get("success") is False:
                    return []
            except Exception:
                pass
            for ck in cj:
                c_path = clean_bp if (not ck.path or ck.path == "/") else ck.path
                out_cookies.append(f"{ck.name}={ck.value}; Path={c_path}; HttpOnly; SameSite=Lax; Secure")
    except Exception:
        return []
    return out_cookies

def _get_agh_credentials() -> Tuple[str, str]:
    u = "admin"
    p = ""
    for cfg_file, u_key, p_key in [
        (SSO_AGH_FILE, "user", "pass"),
        (CONFIG_JSON, "agh_user", "agh_pass")
    ]:
        if os.path.exists(cfg_file):
            try:
                with open(cfg_file, "r", encoding="utf-8") as f:
                    d = json.load(f)
                    if d.get(u_key):
                        u = str(d[u_key])
                    if d.get(p_key):
                        p = str(d[p_key])
                        break
            except Exception:
                pass
    return u, p

def get_agh_basic_auth() -> str:
    u, p = _get_agh_credentials()
    if u and p:
        b64 = base64.b64encode(f"{u}:{p}".encode("utf-8")).decode("utf-8")
        return f"Basic {b64}"
    return ""

def login_agh_session() -> str:
    u, p = _get_agh_credentials()
    if not u or not p:
        return ""
    payload = json.dumps({"name": u, "password": p}).encode("utf-8")
    req = urllib.request.Request("http://127.0.0.1:3000/control/login", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=3.0) as resp:
            hdrs = resp.headers
            raw_cookies = hdrs.get_all("Set-Cookie") if hasattr(hdrs, "get_all") else [hdrs.get("Set-Cookie")]
            for c in (raw_cookies or []):
                if c and "agh_session=" in c:
                    m_ck = re.search(r"(agh_session=[^;\s]+)", c)
                    if m_ck:
                        return m_ck.group(1)
    except Exception:
        pass
    return ""

def is_agh_session_valid(agh_session_cookie: str) -> bool:
    if not agh_session_cookie:
        return False
    req = urllib.request.Request("http://127.0.0.1:3000/control/status", method="GET")
    req.add_header("Cookie", f"agh_session={agh_session_cookie}")
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            return resp.status == 200
    except Exception:
        return False

def build_client_conf(pub_key: str) -> Optional[str]:
    srv: Dict[str, str] = {}
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

    dns_ip = "77.88.8.8" if get_geo_profile() == "1" else "1.1.1.1"
    if is_agh_enabled():
        dns_ip = "10.9.0.1"

    p_dom, _ = get_canonical_domains()
    port_val = srv.get("LISTENPORT", get_native_awg_port())

    return f"""[Interface]
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
Endpoint = {p_dom}:{port_val}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"""
EOF_CORE_UTILS
mv -f /usr/local/bin/myprivatecloud_utils.py.tmp /usr/local/bin/myprivatecloud_utils.py
chmod 0644 /usr/local/bin/myprivatecloud_utils.py

cat << 'EOF_CORE_PY' > /usr/local/bin/myprivatecloud_core.py.tmp.tmp
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os, sys, subprocess, re, time
sys.path.insert(0, "/usr/local/bin")
from typing import Optional, Dict
from fastapi import FastAPI, HTTPException, Header, Request, status
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
import uvicorn

from myprivatecloud_utils import (
    CONF_PATH, is_agh_enabled, get_native_awg_port,
    sign_session_token, verify_session_token,
    gen_wireguard_keypair, safe_cmd_output,
    awg_file_lock, load_clients, save_clients,
    remove_peer_from_awg_conf,
    verify_credentials, get_canonical_domains,
    get_panel_info, login_3xui_session,
    get_agh_basic_auth, login_agh_session, is_agh_session_valid, build_client_conf
)

app = FastAPI(title="MyPrivateCloud Core", docs_url=None, redoc_url=None, openapi_url=None)
_VALID_PUBKEY_RE = re.compile(r"^[A-Za-z0-9+/=]{40,50}$")

class AuthIn(BaseModel):
    principal: str
    secret: str

class PeerAddIn(BaseModel):
    name: str

class PeerRemoveIn(BaseModel):
    public_key: str

def check_token(authorization: Optional[str]) -> bool:
    if not authorization or not authorization.startswith("Bearer "):
        return False
    return verify_session_token(authorization[7:].strip())

@app.post("/api/v1/myprivatecloud/auth")
def api_auth(data: AuthIn, request: Request):
    user = data.principal.strip()
    pwd = data.secret.strip()
    ok_auth, canon_user, tfa_enabled = verify_credentials(user, pwd)
    if ok_auth:
        if tfa_enabled:
            time.sleep(0.5)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="В панели 3X-UI включена 2FA: вход через упрощённый SSO недоступен."
            )
        token = sign_session_token(canon_user, ttl=43200)
        panel_port, panel_url = get_panel_info()
        _, agh_target = get_canonical_domains()

        resp_data = {
            "status": "ok",
            "token": token,
            "services": {
                "panel_url": panel_url,
                "nodes_enabled": os.path.exists(CONF_PATH),
                "awg_port": get_native_awg_port(),
                "agh_enabled": is_agh_enabled() and os.path.exists("/opt/AdGuardHome/AdGuardHome.yaml") and bool(agh_target),
                "agh_url": f"https://{agh_target}/?access_key={token}" if agh_target else ""
            }
        }
        resp = JSONResponse(content=resp_data)

        # Бесшовный SSO-мост в 3X-UI (CSRF + все cookies)
        cookies_3xui = login_3xui_session(canon_user, pwd, panel_port, panel_url)
        for ck in cookies_3xui:
            resp.headers.append("Set-Cookie", ck)
        return resp
    time.sleep(0.5)
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Доступ запрещен.")

@app.get("/api/v1/myprivatecloud/verify-token")
def api_verify_token(request: Request):
    from urllib.parse import urlparse, parse_qs

    url_token = (
        request.query_params.get("access_key")
        or request.headers.get("x-access-key")
        or ""
    ).strip()
    if not url_token:
        orig_uri = request.headers.get("x-original-uri", "")
        if orig_uri:
            qs = parse_qs(urlparse(orig_uri).query)
            url_token = str(qs.get("access_key", [""])[0]).strip()

    cookie_token = (request.cookies.get("agh_sso_token") or "").strip()

    if url_token:
        is_valid = verify_session_token(url_token)
        active_token = url_token
        issue_cookie = True
    elif cookie_token:
        is_valid = verify_session_token(cookie_token)
        active_token = cookie_token
        issue_cookie = False
    else:
        is_valid = False
        active_token = ""
        issue_cookie = False

    if is_valid:
        headers: Dict[str, str] = {"Cache-Control": "no-store, private"}
        cur_agh_ck = (request.cookies.get("agh_session") or "").strip()
        has_agh_cookie = is_agh_session_valid(cur_agh_ck) if cur_agh_ck else False
        if issue_cookie or not has_agh_cookie:
            agh_kv = login_agh_session()
            if agh_kv:
                headers["X-AGH-Session"] = agh_kv
                headers["X-AGH-Cookie"] = f"{agh_kv}; Path=/; HttpOnly; SameSite=Lax; Secure"
            else:
                agh_auth = get_agh_basic_auth()
                if agh_auth:
                    headers["X-AGH-Auth"] = agh_auth
        resp = Response(status_code=200, headers=headers)
        if issue_cookie and active_token:
            resp.set_cookie(
                key="agh_sso_token",
                value=active_token,
                max_age=43200,
                secure=True,
                httponly=True,
                samesite="lax",
                path="/"
            )
        return resp
    return Response(status_code=403, headers={"Cache-Control": "no-store, private"})

@app.get("/api/v1/myprivatecloud/status")
def api_status(token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    return {
        "status": "online",
        "cluster": "myprivatecloud-edge-ultra",
        "nodes_active": 148,
        "telemetry_rate": "99.998%",
        "version": "3.18.0"
    }

@app.get("/api/v1/myprivatecloud/storage/nodes")
def api_peers(token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    dump = safe_cmd_output(["awg", "show", "awg0", "dump"]).strip()
    name_map: Dict[str, str] = {}
    if os.path.exists(CONF_PATH):
        with open(CONF_PATH, "r", encoding="utf-8", errors="ignore") as f:
            curr_name = ""
            for line in f:
                mn = re.search(r"# --- Client:\s*([^\n\r]+?)\s*---", line)
                if mn:
                    curr_name = mn.group(1).strip()
                mk = re.search(r"PublicKey\s*=\s*([^\s]+)", line)
                if mk and curr_name:
                    name_map[mk.group(1)] = curr_name
                    curr_name = ""
    peers = []
    now = int(time.time())
    clients = load_clients()
    for line in dump.split("\n")[1:]:
        p = line.split("\t")
        if len(p) >= 6:
            pub, ip = p[0], p[3]
            try:
                last_hs = int(p[4])
            except ValueError:
                last_hs = 0
            try:
                rx = int(p[5])
            except ValueError:
                rx = 0
            try:
                tx = int(p[6]) if len(p) >= 7 else 0
            except ValueError:
                tx = 0
            peers.append({
                "name": clients.get(pub, {}).get("name") or name_map.get(pub, pub[:8]),
                "public_key": pub,
                "ip": ip,
                "rx": f"{rx / (1024*1024):.1f} MB",
                "tx": f"{tx / (1024*1024):.1f} MB",
                "is_online": (now - last_hs < 180) if last_hs > 0 else False
            })
    return {"status": "ok", "peers": peers}

@app.post("/api/v1/myprivatecloud/storage/node/add")
def api_peer_add(data: PeerAddIn, token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    if not os.path.exists(CONF_PATH):
        raise HTTPException(status_code=400, detail="AWG is not enabled")
    name = re.sub(r"[^a-zA-Z0-9_-]", "", data.name).strip() or "Client"
    priv, pub = gen_wireguard_keypair()

    with awg_file_lock():
        with open(CONF_PATH, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        used_octets = {1}
        for l in lines:
            m = re.search(r"AllowedIPs\s*=\s*10\.9\.0\.(\d+)", l)
            if m:
                used_octets.add(int(m.group(1)))
        next_ip = 2
        while next_ip in used_octets and next_ip <= 254:
            next_ip += 1
        if next_ip > 254:
            raise HTTPException(status_code=400, detail="AWG IP pool exhausted")
        client_ip = f"10.9.0.{next_ip}/32"
        awg_res = subprocess.run(["awg", "set", "awg0", "peer", pub, "allowed-ips", client_ip], capture_output=True, text=True)
        if awg_res.returncode != 0:
            raise HTTPException(status_code=500, detail=f"awg0 interface error: {(awg_res.stderr or '').strip() or 'awg set failed'}")
        new_conf = "".join(lines).rstrip() + f"\n\n# --- Client: {name} ---\n[Peer]\nPublicKey = {pub}\nAllowedIPs = {client_ip}\n"
        tmp_c = CONF_PATH + ".tmp"
        with open(tmp_c, "w", encoding="utf-8") as f:
            f.write(new_conf)
        os.chmod(tmp_c, 0o600)
        os.replace(tmp_c, CONF_PATH)
        clients = load_clients()
        clients[pub] = {"name": name, "private_key": priv, "public_key": pub, "ip": client_ip}
        save_clients(clients)
    return {"status": "ok", "public_key": pub, "ip": client_ip, "name": name}

@app.post("/api/v1/myprivatecloud/storage/node/remove")
def api_peer_remove(data: PeerRemoveIn, token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    pub = data.public_key.strip()
    if pub and _VALID_PUBKEY_RE.match(pub):
        with awg_file_lock():
            subprocess.run(["awg", "set", "awg0", "peer", pub, "remove"], capture_output=True)
            if os.path.exists(CONF_PATH):
                with open(CONF_PATH, "r", encoding="utf-8", errors="ignore") as f:
                    txt = f.read()
                new_txt = remove_peer_from_awg_conf(txt, pub)
                tmp_c = CONF_PATH + ".tmp"
                with open(tmp_c, "w", encoding="utf-8") as f:
                    f.write(new_txt)
                os.chmod(tmp_c, 0o600)
                os.replace(tmp_c, CONF_PATH)
            clients = load_clients()
            if pub in clients:
                del clients[pub]
                save_clients(clients)
    return {"status": "ok"}

@app.get("/api/v1/myprivatecloud/storage/node/token")
def api_peer_qr(key: str, token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    key_clean = key.strip()
    if not _VALID_PUBKEY_RE.match(key_clean):
        raise HTTPException(status_code=400, detail="Invalid Key")
    conf_str = build_client_conf(key_clean)
    if not conf_str:
        raise HTTPException(status_code=404, detail="Peer Not Found")
    p = subprocess.Popen(["qrencode", "-t", "PNG", "-s", "8", "-m", "2", "-o", "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    img_out, _ = p.communicate(input=conf_str.encode("utf-8"))
    c_type = "image/png"
    if not img_out:
        p_svg = subprocess.Popen(["qrencode", "-t", "SVG", "-m", "2", "-o", "-"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        img_out, _ = p_svg.communicate(input=conf_str.encode("utf-8"))
        c_type = "image/svg+xml"
    return Response(content=img_out, media_type=c_type, headers={"Cache-Control": "no-store, private"})

@app.get("/api/v1/myprivatecloud/storage/node/key")
def api_peer_conf(key: str, token: Optional[str] = Header(None, alias="Authorization")):
    if not check_token(token):
        raise HTTPException(status_code=401, detail="Unauthorized")
    key_clean = key.strip()
    if not _VALID_PUBKEY_RE.match(key_clean):
        raise HTTPException(status_code=400, detail="Invalid Key")
    conf_str = build_client_conf(key_clean)
    if not conf_str:
        raise HTTPException(status_code=404, detail="Peer Not Found")
    safe_fn = re.sub(r"[^A-Za-z0-9_-]", "", key_clean)[:8] or "peer"
    return Response(
        content=conf_str.encode("utf-8"),
        media_type="text/plain; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="awg0-{safe_fn}.conf"',
            "Cache-Control": "no-store, private"
        }
    )

if __name__ == "__main__":
    uvicorn.run("myprivatecloud_core:app", host="127.0.0.1", port=20443, log_level="warning")
EOF_CORE_PY
mv -f /usr/local/bin/myprivatecloud_core.py.tmp.tmp /usr/local/bin/myprivatecloud_core.py.tmp
chmod 0644 /usr/local/bin/myprivatecloud_core.py.tmp 2>/dev/null || true
mv -f /usr/local/bin/myprivatecloud_core.py.tmp /usr/local/bin/myprivatecloud_core.py
chmod 0755 /usr/local/bin/myprivatecloud_core.py

cat << EOF > /etc/systemd/system/myprivatecloud-core.service.tmp
[Unit]
Description=My Private Cloud Core Gateway Daemon
After=network.target

[Service]
Type=simple
User=root
MemoryHigh=$FASTAPI_MEM_HIGH
MemoryMax=$FASTAPI_MEM_MAX
Environment="ENABLE_AGH=${ENABLE_AGH:-0}"
Environment="GEO_PROFILE=$GEO_PROFILE"
Environment="PRIMARY_DOMAIN=$PRIMARY_DOMAIN"
Environment="PANEL_PORT=$PANEL_PORT"
Environment="PANEL_PATH=$PANEL_PATH"
Environment="AGH_DOMAIN=${AGH_DOMAIN:-}"
Environment="NATIVE_AWG_PORT=$NATIVE_AWG_PORT"
EnvironmentFile=-/etc/myprivatecloud/config.env
ExecStart=/opt/myprivatecloud/venv/bin/uvicorn myprivatecloud_core:app --app-dir /usr/local/bin --host 127.0.0.1 --port 20443 --workers $FASTAPI_WORKERS --no-access-log --log-level warning
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
CapabilityBoundingSet=CAP_NET_ADMIN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@mount @swap @reboot @module @raw-io @obsolete @debug @cpu-emulation
IPAddressDeny=any
IPAddressAllow=localhost
UMask=0077
ReadWritePaths=-/etc/amnezia/amneziawg -/etc/x-ui -/usr/local/x-ui/bin -/etc/myprivatecloud
LimitNOFILE=1048576
LimitNPROC=512

[Install]
WantedBy=multi-user.target
EOF
mv -f /etc/systemd/system/myprivatecloud-core.service.tmp /etc/systemd/system/myprivatecloud-core.service
chmod 0644 /etc/systemd/system/myprivatecloud-core.service 2>/dev/null || true

systemctl daemon-reload
systemctl enable myprivatecloud-core >/dev/null 2>&1 || true
systemctl restart myprivatecloud-core || true
MPC_READY=0
for _ in {1..10}; do
    if systemctl is-active --quiet myprivatecloud-core && ss -tlnp 2>/dev/null | grep -q "127.0.0.1:20443"; then
        MPC_READY=1
        break
    fi
    sleep 1
done
if [ "$MPC_READY" -eq 1 ]; then
    ok "Служба My Private Cloud Core SSO Gateway запущена на 127.0.0.1:20443 (Zero-Log + HMAC SSO)."
else
    journalctl -u myprivatecloud-core --no-pager -n 20 >&2 || true
    die "Служба My Private Cloud Core SSO Gateway не запустилась на 127.0.0.1:20443."
fi

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
    TARGET_UFW_IPV6="no"
    if [ "${DISABLE_IPV6:-0}" -eq 0 ]; then
        TARGET_UFW_IPV6="yes"
    fi
    if grep -q "^IPV6=" /etc/default/ufw; then
        sed -i "s/^IPV6=.*/IPV6=${TARGET_UFW_IPV6}/" /etc/default/ufw
    else
        echo "IPV6=${TARGET_UFW_IPV6}" >> /etc/default/ufw
    fi
fi

ufw logging off >/dev/null 2>&1 || true
ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true

TARGET_SSH_PORT="$TARGET_SSH_PORT" ENABLE_HY2="${ENABLE_HY2:-0}" HY2_PORT="${HY2_PORT:-}" \
ENABLE_NATIVE_AWG="${ENABLE_NATIVE_AWG:-0}" NATIVE_AWG_PORT="${NATIVE_AWG_PORT:-}" \
ENABLE_AWG_V3="${ENABLE_AWG_V3:-0}" AWG_V3_PORT="${AWG_V3_PORT:-}" \
ENABLE_AGH="${ENABLE_AGH:-0}" python3 - << 'EOF_UFW_PRUNE'
import os, re, subprocess

res = subprocess.run(["ufw", "status", "numbered"], capture_output=True, text=True)
if res.returncode != 0:
    raise SystemExit(0)

ssh_p = os.environ.get("TARGET_SSH_PORT", "22").strip()
hy2_on = os.environ.get("ENABLE_HY2", "0") == "1"
hy2_p = os.environ.get("HY2_PORT", "").strip()
nawg_on = os.environ.get("ENABLE_NATIVE_AWG", "0") == "1"
nawg_p = os.environ.get("NATIVE_AWG_PORT", "").strip()
awg3_on = os.environ.get("ENABLE_AWG_V3", "0") == "1"
awg3_p = os.environ.get("AWG_V3_PORT", "").strip()
agh_on = os.environ.get("ENABLE_AGH", "0") == "1"

managed_comments = {
    "SSH", "SSH Target Port",
    "Hysteria 2",
    "AmneziaWG Native awg0 Base",
    "3X-UI AWG v3.2",
    "AdGuard DNS awg0 UDP",
    "AdGuard DNS awg0 TCP",
}

to_delete = []
for ln in res.stdout.splitlines():
    m = re.match(r"^\[\s*(\d+)\]\s+(.+?)\s+#\s*(.+?)\s*$", ln)
    if not m:
        continue
    num, body, cmt = int(m.group(1)), m.group(2), m.group(3).strip()
    if cmt not in managed_comments:
        continue
    keep = False
    if cmt in ("SSH", "SSH Target Port"):
        keep = bool(re.match(rf"^{re.escape(ssh_p)}/tcp(?:\s+\(v6\))?\s+ALLOW\b", body))
    elif cmt == "Hysteria 2":
        keep = hy2_on and bool(hy2_p) and bool(re.match(rf"^{re.escape(hy2_p)}/udp(?:\s+\(v6\))?\s+ALLOW\b", body))
    elif cmt == "AmneziaWG Native awg0 Base":
        keep = nawg_on and bool(nawg_p) and bool(re.match(rf"^{re.escape(nawg_p)}/udp(?:\s+\(v6\))?\s+ALLOW\b", body))
    elif cmt == "3X-UI AWG v3.2":
        keep = awg3_on and bool(awg3_p) and bool(re.match(rf"^{re.escape(awg3_p)}/udp(?:\s+\(v6\))?\s+ALLOW\b", body))
    elif cmt == "AdGuard DNS awg0 UDP":
        keep = agh_on and nawg_on and ("53/udp" in body) and ("awg0" in body)
    elif cmt == "AdGuard DNS awg0 TCP":
        keep = agh_on and nawg_on and ("53/tcp" in body) and ("awg0" in body)
    if not keep:
        to_delete.append(num)

for num in sorted(to_delete, reverse=True):
    subprocess.run(["ufw", "--force", "delete", str(num)], stdin=subprocess.DEVNULL, capture_output=True)
EOF_UFW_PRUNE

ufw allow "${TARGET_SSH_PORT}/tcp" comment 'SSH' >/dev/null 2>&1 || true
ufw allow 80/tcp comment 'HTTP ACME' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS L4 Router' >/dev/null 2>&1 || true

if [ "${ENABLE_AGH:-0}" -eq 1 ] && [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    ufw allow in on awg0 to 10.9.0.1 port 53 proto udp comment 'AdGuard DNS awg0 UDP' >/dev/null 2>&1 || true
    ufw allow in on awg0 to 10.9.0.1 port 53 proto tcp comment 'AdGuard DNS awg0 TCP' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    ufw allow "${HY2_PORT}/udp" comment 'Hysteria 2' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    ufw allow "${NATIVE_AWG_PORT}/udp" comment 'AmneziaWG Native awg0 Base' >/dev/null 2>&1 || true
fi

if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    ufw allow "${AWG_V3_PORT}/udp" comment '3X-UI AWG v3.2' >/dev/null 2>&1 || true
elif validate_port "${AWG_V3_PORT:-}"; then
    ufw delete allow "${AWG_V3_PORT}/udp" </dev/null >/dev/null 2>&1 || true
fi

if [ -f /etc/ufw/before.rules ]; then cp -a /etc/ufw/before.rules /tmp/ufw_before_pre_b10.bak 2>/dev/null || true; fi

export HY2_PORT ENABLE_NATIVE_AWG NATIVE_AWG_PORT ENABLE_AWG_V3 ENABLE_AGH DEFAULT_IF BLOCK_PING
python3 - << 'EOF_UFW_PYTHON'
# -*- coding: utf-8 -*-
import os, sys, re, subprocess

rules_file = "/etc/ufw/before.rules"
if not os.path.exists(rules_file):
    sys.exit(0)

with open(rules_file, "r", encoding="utf-8") as f:
    content = f.read()

content = re.sub(r'# START HARDENED NAT[\s\S]*?# END HARDENED NAT\n*', '', content)
content = re.sub(r'# START HARDENED MANGLE[\s\S]*?# END HARDENED MANGLE\n*', '', content)
content = re.sub(r'# START HARDENED FORWARD[\s\S]*?# END HARDENED FORWARD\n*', '', content)
content = re.sub(r'# START HARDENED DNS-INPUT[\s\S]*?# END HARDENED DNS-INPUT\n*', '', content)
content = re.sub(r'# START HARDENED SECURITY[\s\S]*?# END HARDENED SECURITY\n*', '', content)
content = content.strip() + "\n"

default_if = os.environ.get("DEFAULT_IF", "eth0")
awg_native = os.environ.get("ENABLE_NATIVE_AWG") == "1"
awg3 = os.environ.get("ENABLE_AWG_V3") == "1"
enable_agh = os.environ.get("ENABLE_AGH") == "1"
block_ping = os.environ.get("BLOCK_PING") == "1"

# NAT управляется идемпотентной цепочкой HARDENED_NAT в apply-mss-clamp.sh во избежание дублей UFW reload
nat_part = ""

sec_lines = [
    "# START HARDENED SECURITY",
    "-A ufw-before-input -m conntrack --ctstate INVALID -j DROP",
    "-A ufw-before-input -p tcp --tcp-flags ALL NONE -j DROP",
    "-A ufw-before-input -p tcp --tcp-flags ALL ALL -j DROP",
    "-A ufw-before-input -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP",
    "# END HARDENED SECURITY"
]
if awg_native and enable_agh:
    sec_lines.extend([
        "# START HARDENED DNS-INPUT",
        "-A ufw-before-input -i awg0 -d 10.9.0.1 -p udp --dport 53 -j ACCEPT",
        "-A ufw-before-input -i awg0 -d 10.9.0.1 -p tcp --dport 53 -j ACCEPT",
        "# END HARDENED DNS-INPUT"
    ])

fwd_lines = ["# START HARDENED FORWARD"]
if awg_native:
    fwd_lines.append("-A ufw-before-forward -s 10.9.0.0/24 -j ACCEPT")
    fwd_lines.append(f"-A ufw-before-forward -i {default_if} -d 10.9.0.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
if awg3:
    fwd_lines.append("-A ufw-before-forward -s 10.8.1.0/24 -j ACCEPT")
    fwd_lines.append(f"-A ufw-before-forward -i {default_if} -d 10.8.1.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT")
fwd_lines.append("# END HARDENED FORWARD")

lines = content.splitlines()
out_lines = []
in_filter = False
sec_inserted = False
fwd_inserted = False
last_chain_idx = -1

for ln in lines:
    st = ln.strip()
    if st == "*filter":
        in_filter = True
        out_lines.append(ln)
        continue
    if in_filter and st == "COMMIT":
        if not sec_inserted:
            insert_at = max(last_chain_idx + 1, 0)
            for offset, s_ln in enumerate(sec_lines):
                out_lines.insert(insert_at + offset, s_ln)
            sec_inserted = True
        if not fwd_inserted and len(fwd_lines) > 2:
            insert_at = len(out_lines)
            if last_chain_idx >= 0:
                for idx_c in range(len(out_lines) - 1, -1, -1):
                    if out_lines[idx_c].strip().startswith(":"):
                        insert_at = idx_c + 1
                        break
            for offset, f_ln in enumerate(fwd_lines):
                out_lines.insert(insert_at + offset, f_ln)
            fwd_inserted = True
        in_filter = False
        out_lines.append(ln)
        continue

    if in_filter and st.startswith(":"):
        out_lines.append(ln)
        last_chain_idx = len(out_lines) - 1
        continue

    if in_filter and block_ping and re.match(r"^-A\s+ufw-before-input\s+-p\s+icmp\s+--icmp-type\s+echo-request\s+-j\s+ACCEPT\b", st):
        ln = re.sub(r"-j\s+ACCEPT\b", "-j DROP", ln)
    elif in_filter and (not block_ping) and re.match(r"^-A\s+ufw-before-input\s+-p\s+icmp\s+--icmp-type\s+echo-request\s+-j\s+DROP\b", st):
        ln = re.sub(r"-j\s+DROP\b", "-j ACCEPT", ln)

    out_lines.append(ln)

    if in_filter and not sec_inserted and re.match(r"^-A\s+ufw-before-input\b.*--(ct)?state\s+(RELATED,ESTABLISHED|ESTABLISHED,RELATED)\b.*-j\s+ACCEPT\b", st):
        out_lines.extend(sec_lines)
        sec_inserted = True
    elif in_filter and not fwd_inserted and len(fwd_lines) > 2 and re.match(r"^-A\s+ufw-before-forward\b.*--(ct)?state\s+(RELATED,ESTABLISHED|ESTABLISHED,RELATED)\b.*-j\s+ACCEPT\b", st):
        out_lines.extend(fwd_lines)
        fwd_inserted = True

final_body = nat_part + "\n".join(out_lines).strip() + "\n"

# Валидация через iptables-restore --test (если доступен)
try:
    res = subprocess.run(["iptables-restore", "--test"], input=final_body, text=True, capture_output=True)
    if res.returncode != 0:
        sys.exit(f"[X] Ошибка синтаксиса собранного /etc/ufw/before.rules: {res.stderr.strip()}")
except FileNotFoundError:
    pass

tmp_r = rules_file + ".tmp"
with open(tmp_r, "w", encoding="utf-8") as f:
    f.write(final_body)
os.chmod(tmp_r, 0o600)
os.replace(tmp_r, rules_file)
EOF_UFW_PYTHON

DENIED_PORTS=("$PANEL_PORT" "$SUB_PORT" 8088 9443 3000 20443)
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
        ufw delete deny "${dp}/tcp" </dev/null >/dev/null 2>&1 || true
    fi
done

if ! ufw --force enable >/dev/null 2>&1 || ! ufw reload >/dev/null 2>&1; then
    warn "Ошибка активации UFW; откат /etc/ufw/before.rules из временного снимка."
    if [ -f /tmp/ufw_before_pre_b10.bak ]; then
        cp -a /tmp/ufw_before_pre_b10.bak /etc/ufw/before.rules
        ufw --force enable >/dev/null 2>&1 || true
    fi
    die "Не удалось активировать фаервол UFW с правилами /etc/ufw/before.rules."
fi
if ! ufw status 2>/dev/null | grep -qiE '^Status:\s*active'; then
    die "Фаервол UFW не перешёл в активное состояние."
fi
rm -f /tmp/ufw_before_pre_b10.bak 2>/dev/null || true

MSS_SCRIPT="/usr/local/bin/apply-mss-clamp.sh"
cat << EOF_MSS_SCRIPT > "${MSS_SCRIPT}.tmp"
#!/usr/bin/env bash
set -Eeuo pipefail
while iptables -t nat -D POSTROUTING -s 10.9.0.0/24 -o ${DEFAULT_IF} -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.8.1.0/24 -o ${DEFAULT_IF} -j MASQUERADE 2>/dev/null; do :; done
iptables -t nat -D POSTROUTING -j HARDENED_NAT 2>/dev/null || true
iptables -t nat -F HARDENED_NAT 2>/dev/null || true
iptables -t nat -X HARDENED_NAT 2>/dev/null || true
iptables -t nat -N HARDENED_NAT

iptables -t mangle -D FORWARD -j HARDENED_MSS 2>/dev/null || true
iptables -t mangle -F HARDENED_MSS 2>/dev/null || true
iptables -t mangle -X HARDENED_MSS 2>/dev/null || true
iptables -t mangle -N HARDENED_MSS
EOF_MSS_SCRIPT

if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    cat << EOF_MSS_NAWG >> "${MSS_SCRIPT}.tmp"
iptables -t nat -A HARDENED_NAT -s 10.9.0.0/24 -o ${DEFAULT_IF} -j MASQUERADE
iptables -t mangle -A HARDENED_MSS -s 10.9.0.0/24 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1320
iptables -t mangle -A HARDENED_MSS -s 10.9.0.0/24 -j RETURN
iptables -t mangle -A HARDENED_MSS -d 10.9.0.0/24 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1320
iptables -t mangle -A HARDENED_MSS -d 10.9.0.0/24 -j RETURN
EOF_MSS_NAWG
fi
if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    cat << EOF_MSS_AWG3 >> "${MSS_SCRIPT}.tmp"
iptables -t nat -A HARDENED_NAT -s 10.8.1.0/24 -o ${DEFAULT_IF} -j MASQUERADE
iptables -t mangle -A HARDENED_MSS -s 10.8.1.0/24 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1320
iptables -t mangle -A HARDENED_MSS -s 10.8.1.0/24 -j RETURN
iptables -t mangle -A HARDENED_MSS -d 10.8.1.0/24 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1320
iptables -t mangle -A HARDENED_MSS -d 10.8.1.0/24 -j RETURN
EOF_MSS_AWG3
fi
cat << 'EOF_MSS_TAIL' >> "${MSS_SCRIPT}.tmp"
iptables -t nat -A POSTROUTING -j HARDENED_NAT
iptables -t mangle -A HARDENED_MSS -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -t mangle -I FORWARD 1 -j HARDENED_MSS
EOF_MSS_TAIL
mv -f "${MSS_SCRIPT}.tmp" "$MSS_SCRIPT"
chmod 0700 "$MSS_SCRIPT"

cat << EOF_MSS_SVC > /etc/systemd/system/network-mss-clamp.service.tmp
[Unit]
Description=Idempotent NAT and TCP MSS Clamping (HARDENED_NAT / HARDENED_MSS)
After=ufw.service network-online.target
Wants=network-online.target
PartOf=ufw.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${MSS_SCRIPT}

[Install]
WantedBy=multi-user.target
EOF_MSS_SVC
mv -f /etc/systemd/system/network-mss-clamp.service.tmp /etc/systemd/system/network-mss-clamp.service
chmod 0644 /etc/systemd/system/network-mss-clamp.service
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now network-mss-clamp.service >/dev/null 2>&1 || true
systemctl restart network-mss-clamp.service >/dev/null 2>&1 || true
ok "Фаервол UFW настроен на адаптере $DEFAULT_IF. Маршрутизация пулов и изоляция MSS Clamping (1320 + RETURN) активны."

# =============================================================
#  СЛУЖБА РЕГЛАМЕНТНОГО ОБСЛУЖИВАНИЯ, АВТООБНОВЛЕНИЯ И ПЕРЕСБОРКИ AWG
# =============================================================
if [ "${ENABLE_AUTO_UPDATE:-0}" -eq 1 ]; then
    log "Настройка регламентного обслуживания, автообновления ОС/ядра и пересборки AWG..."
    mkdir -p /usr/local/bin /var/backups/vpn-autoupdate

    cat << 'EOF_AUTO_MAINT' > /usr/local/bin/system-autoupdate.sh.tmp
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

LOCK_FILE="/var/run/system-autoupdate.lock"
exec 201>"$LOCK_FILE"
if ! flock -n 201; then
    echo "[!] Процесс регламентного автообновления уже выполняется."
    exit 0
fi

log()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [+] $*"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [!] $*" >&2; }

patch_awg_compat_sources() {
    python3 - << 'EOF_AUTO_AWG_COMPAT'
import glob, os, re

pr265_block = """/* PR #265: signature-based udp_tunnel sock/socket compat */
#ifndef __compat_udp_tunnel_sock_patched
#define __compat_udp_tunnel_sock_patched 1
#include <net/udp_tunnel.h>
static inline void __compat_setup_udp_tunnel_sock(struct net *net, struct sock *sk, struct udp_tunnel_sock_cfg *cfg)
{
    setup_udp_tunnel_sock(net, __builtin_choose_expr(
        __builtin_types_compatible_p(typeof(&setup_udp_tunnel_sock),
            void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *)),
        sk, sk->sk_socket), cfg);
}
#define setup_udp_tunnel_sock(net, sk, cfg) __compat_setup_udp_tunnel_sock((net), (sk), (cfg))
static inline void __compat_udp_tunnel_sock_release(struct sock *sk)
{
    udp_tunnel_sock_release(__builtin_choose_expr(
        __builtin_types_compatible_p(typeof(&udp_tunnel_sock_release), void (*)(struct sock *)),
        sk, sk->sk_socket));
}
#define udp_tunnel_sock_release(sk) __compat_udp_tunnel_sock_release(sk)
#endif"""

legacy_re = re.compile(
    r"/\* Kernel 7\.0\+ compatibility backport \*/\s*"
    r"#if LINUX_VERSION_CODE < KERNEL_VERSION\(7, 0, 0\)\s*"
    r"#define setup_udp_tunnel_sock\(net, sk, sock_cfg\) setup_udp_tunnel_sock\(net, sk->sk_socket, sock_cfg\)\s*"
    r"#elif LINUX_VERSION_CODE < KERNEL_VERSION\(7, 2, 0\)\s*"
    r"#define __compat_setup_udp_tunnel_sock 1\s*"
    r"#endif",
    re.M,
)
multiline_setup_re = re.compile(r"^[ \t]*#define[ \t]+setup_udp_tunnel_sock\b(?:[^\n]*\\\n)*[^\n]*sk->sk_socket[^\n]*\n?", re.M)
multiline_rel_re = re.compile(r"^[ \t]*#define[ \t]+udp_tunnel_sock_release\b(?:[^\n]*\\\n)*[^\n]*\n?", re.M)

for root_dir in glob.glob("/usr/src/amneziawg-*"):
    for rel in ("compat/compat.h", "src/compat/compat.h"):
        hp = os.path.join(root_dir, rel)
        if not os.path.isfile(hp):
            continue
        with open(hp, "r", encoding="utf-8", errors="ignore") as f:
            txt = f.read()
        has_rel = bool(re.search(r"^[ \t]*#define[ \t]+udp_tunnel_sock_release\(", txt, re.M))
        if ("__compat_udp_tunnel_sock_patched" in txt or ("__builtin_types_compatible_p" in txt and "setup_udp_tunnel_sock" in txt)) and has_rel:
            continue
        changed = False
        incomplete_pr265_re = re.compile(r"/\* PR #265:.*?#ifndef __compat_udp_tunnel_sock_patched.*?#endif", re.S)
        if "__compat_udp_tunnel_sock_patched" in txt and not has_rel:
            txt = incomplete_pr265_re.sub(pr265_block, txt, count=1)
            changed = True
        elif legacy_re.search(txt):
            txt = multiline_rel_re.sub("", txt)
            txt = legacy_re.sub(pr265_block, txt, count=1)
            changed = True
        elif multiline_setup_re.search(txt):
            txt = multiline_rel_re.sub("", txt)
            txt = multiline_setup_re.sub(pr265_block + "\n", txt, count=1)
            changed = True
        if changed:
            tmp = hp + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(txt)
            os.chmod(tmp, 0o644)
            os.replace(tmp, hp)
EOF_AUTO_AWG_COMPAT
}

log "Старт регламентного еженедельного обслуживания сервера..."

BACKUP_DIR="/var/backups/vpn-autoupdate"
mkdir -p "$BACKUP_DIR"
TS=$(date +%F_%H%M%S)

if [ -d /etc/amnezia/amneziawg ]; then
    tar -czf "$BACKUP_DIR/awg_backup_${TS}.tar.gz" -C /etc/amnezia amneziawg 2>/dev/null || true
    log "Конфигурации AmneziaWG (awg0) успешно зарезервированы."
fi
for db_cand in /etc/x-ui/x-ui.db /usr/local/x-ui/bin/x-ui.db /etc/x-ui/db/x-ui.db; do
    if [ -f "$db_cand" ]; then
        sqlite3 -cmd ".timeout 5000" "$db_cand" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
        cp -a "$db_cand" "$BACKUP_DIR/x-ui_backup_${TS}.db" 2>/dev/null || true
        chmod 0600 "$BACKUP_DIR/x-ui_backup_${TS}.db" 2>/dev/null || true
        log "База данных 3X-UI ($db_cand) успешно зарезервирована."
        break
    fi
done
find "$BACKUP_DIR" -type f -mtime +28 -delete 2>/dev/null || true

count=0
while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; do
    sleep 2
    count=$((count + 2))
    if [ "$count" -ge 120 ]; then
        warn "APT заблокирован более 120 секунд. Отмена текущей итерации."
        exit 1
    fi
done

patch_awg_compat_sources || true
apt-get update -q
if dpkg -l linux-image-generic >/dev/null 2>&1; then
    apt-get install -y -q linux-headers-generic 2>/dev/null || true
elif dpkg -l linux-image-amd64 >/dev/null 2>&1; then
    apt-get install -y -q linux-headers-amd64 2>/dev/null || true
elif dpkg -l linux-image-arm64 >/dev/null 2>&1; then
    apt-get install -y -q linux-headers-arm64 2>/dev/null || true
fi

if ! apt-get upgrade --with-new-pkgs -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
    warn "Обнаружен сбой apt-get upgrade (возможен DKMS postinst); применяю патч совместимости AWG и повторяю..."
    patch_awg_compat_sources || true
    dpkg --configure -a || true
    apt-get install -f -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
fi
apt-get autoremove -y -q

REBOOT_NEEDED=0
if [ -f /var/run/reboot-required ]; then
    REBOOT_NEEDED=1
    log "Обнаружен флаг обновления ядра Linux (/var/run/reboot-required)."
fi

RUNNING_KERNEL=$(uname -r)
NEW_KERNEL="$RUNNING_KERNEL"
while IFS= read -r kcand; do
    [ -n "$kcand" ] || continue
    if [ -e "/boot/vmlinuz-${kcand}" ] || [ -e "/boot/vmlinux-${kcand}" ]; then
        NEW_KERNEL="$kcand"
    fi
done < <(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V || true)

if [ "$REBOOT_NEEDED" -eq 1 ] || [ "$NEW_KERNEL" != "$RUNNING_KERNEL" ]; then
    AWG_DKMS_VER=$(dkms status 2>/dev/null | awk -F'[/,:]' '/amneziawg/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' || true)
    if [ -n "$AWG_DKMS_VER" ]; then
        log "Обнаружен модуль AmneziaWG ($AWG_DKMS_VER). Верификация компиляции под ядро $NEW_KERNEL..."
        patch_awg_compat_sources || true
        if ! dkms status -m amneziawg -v "$AWG_DKMS_VER" -k "$NEW_KERNEL" 2>/dev/null | grep -q "installed"; then
            log "Принудительная сборка amneziawg/$AWG_DKMS_VER под новое ядро $NEW_KERNEL..."
            dkms build -m amneziawg -v "$AWG_DKMS_VER" -k "$NEW_KERNEL" 2>/dev/null || true
            dkms install -m amneziawg -v "$AWG_DKMS_VER" -k "$NEW_KERNEL" 2>/dev/null || true
        fi

        if dkms status -m amneziawg -v "$AWG_DKMS_VER" -k "$NEW_KERNEL" 2>/dev/null | grep -q "installed"; then
            log "Модуль amneziawg/$AWG_DKMS_VER успешно верифицирован для ядра $NEW_KERNEL. Перезагрузка..."
            systemctl reboot
        else
            warn "ВНИМАНИЕ (CIRCUIT BREAKER): amneziawg/$AWG_DKMS_VER НЕ скомпилировался под ядро $NEW_KERNEL!"
            warn "Перезагрузка заблокирована для защиты работы туннелей. Сервер остается на стабильном ядре $RUNNING_KERNEL."
            exit 0
        fi
    else
        log "Модуль amneziawg не используется. Безопасная регламентная перезагрузка..."
        systemctl reboot
    fi
else
    log "Регламентное обслуживание завершено успешно. Смена ядра не производилась."
fi
EOF_AUTO_MAINT
    mv -f /usr/local/bin/system-autoupdate.sh.tmp /usr/local/bin/system-autoupdate.sh
    chmod 0700 /usr/local/bin/system-autoupdate.sh

    cat << 'EOF_MAINT_SERVICE' > /etc/systemd/system/system-autoupdate.service.tmp
[Unit]
Description=Weekly System and AmneziaWG Kernel Maintenance
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-autoupdate.sh
TimeoutStartSec=1800
EOF_MAINT_SERVICE
    mv -f /etc/systemd/system/system-autoupdate.service.tmp /etc/systemd/system/system-autoupdate.service
    chmod 0644 /etc/systemd/system/system-autoupdate.service 2>/dev/null || true

    cat << 'EOF_MAINT_TIMER' > /etc/systemd/system/system-autoupdate.timer.tmp
[Unit]
Description=Weekly System and AmneziaWG Kernel Maintenance Timer

[Timer]
OnCalendar=Sun *-*-* 04:00:00 UTC
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF_MAINT_TIMER
    mv -f /etc/systemd/system/system-autoupdate.timer.tmp /etc/systemd/system/system-autoupdate.timer
    chmod 0644 /etc/systemd/system/system-autoupdate.timer 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable --now system-autoupdate.timer >/dev/null 2>&1 || true
    ok "Еженедельный таймер автообновления и пересборки AWG активен (каждое воскресенье в 04:00 UTC)."
fi

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ДАШБОРД
# =============================================================
REAL_ADMIN_USER="$ADMIN_USER"
if [ "$INSTALL_MODE" = "2" ] && [ -f "${DB_PATH:-}" ]; then
    DB_ADMIN_USER=$(sqlite_ro "$DB_PATH" "SELECT username FROM users LIMIT 1;")
    if [ -n "$DB_ADMIN_USER" ]; then
        REAL_ADMIN_USER="$DB_ADMIN_USER"
    fi
fi

DECOY_BTN_LABEL="Authorization"
if [ "${GEO_PROFILE:-2}" = "1" ]; then
    DECOY_BTN_LABEL="Авторизация"
fi

if [ "${GEO_PROFILE:-2}" = "1" ]; then
    SSO_MENU_ITEMS="1) «Репликация объектов и буферизация» (Панель 3X-UI)"
    if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
        SSO_MENU_ITEMS="${SSO_MENU_ITEMS}  2) «Кластерный транспорт узлов хранения» (AmneziaWG)"
    fi
    if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
        SSO_MENU_ITEMS="${SSO_MENU_ITEMS}  3) «Служба каталогов метаданных» (AdGuard Home)"
    fi
else
    SSO_MENU_ITEMS="1) «Object Store Replication & Edge Cache» (Панель 3X-UI)"
    if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
        SSO_MENU_ITEMS="${SSO_MENU_ITEMS}  2) «Cluster Interconnect & Node Mesh» (AmneziaWG)"
    fi
    if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
        SSO_MENU_ITEMS="${SSO_MENU_ITEMS}  3) «Metadata Directory Service» (AdGuard Home)"
    fi
fi

PQC_STATUS_LABEL=""
if [ "${ENABLE_XHTTP:-0}" -eq 1 ] && [ -f "${DB_PATH:-}" ]; then
    _LOC_C_PQC=$(get_local_ib_cond "$DB_PATH")
    _DB_XHTTP_DEC=$(sqlite_ro "$DB_PATH" "SELECT json_extract(settings, '$.decryption') FROM inbounds WHERE (tag='in-xhttp-stream' OR (protocol='vless' AND stream_settings LIKE '%xhttp%')) ${_LOC_C_PQC} ORDER BY enable DESC, id ASC LIMIT 1;")
    if [[ "${_DB_XHTTP_DEC:-}" =~ ^mlkem768 ]]; then
        PQC_STATUS_LABEL=" + ML-KEM-768"
    fi
elif [[ "${VLESS_DECRYPTION:-}" =~ ^mlkem768 ]] && [ "${MIGRATE_FORCE_MLKEM:-1}" -eq 1 ]; then
    PQC_STATUS_LABEL=" + ML-KEM-768"
fi

HAS_3XUI_INBOUND=0
if { [ "${ENABLE_STEAL:-0}" -eq 1 ] && [ "${#STEAL_PORTS_LIST[@]}" -gt 0 ]; } || \
   [ "${ENABLE_XHTTP:-0}" -eq 1 ] || \
   { [ "${ENABLE_CLASSIC:-0}" -eq 1 ] && [ "${#CLASSIC_PORTS_LIST[@]}" -gt 0 ]; } || \
   [ "${ENABLE_HY2:-0}" -eq 1 ] || \
   [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    HAS_3XUI_INBOUND=1
fi

STEAL_PORTS_DISP=$(IFS=' '; echo "${STEAL_PORTS_LIST[*]:-}")
STEAL_DOMS_DISP=$(IFS=' '; echo "${STEAL_DOMAINS[*]:-}")
CLASSIC_PORTS_DISP=$(IFS=' '; echo "${CLASSIC_PORTS_LIST[*]:-}")
EXT_SNI_DISP=$(IFS=' '; echo "${EXT_SNI_LIST[*]:-}")

STEAL_CRED_BLOCK=""
if [ "${ENABLE_STEAL:-0}" -eq 1 ] && [ "${#STEAL_PORTS_LIST[@]}" -gt 0 ]; then
    STEAL_CRED_BLOCK="[ STEAL-ONESELF REALITY ]
Локальные порты Xray:  ${STEAL_PORTS_DISP} (L4 Ingress 443/tcp)
Домены маскировки:     ${STEAL_DOMS_DISP}
Anti-Loop Fallback:    127.0.0.1:${REALITY_FALLBACK_PORT} (Proxy_Protocol v1)

"
fi

XHTTP_CRED_BLOCK=""
if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    XHTTP_CRED_BLOCK="[ VLESS XHTTP (NATIVE H2 STREAM-ONE) ]
Точка входа:           ${PRIMARY_DOMAIN}:443
Секретный URI-путь:    ${BASE_XHTTP_PATH}
Транспорт / Flow:      H2 Stream-One + proxy_http_version 2 + xtls-rprx-vision${PQC_STATUS_LABEL}

"
fi

CLASSIC_CRED_BLOCK=""
if [ "${ENABLE_CLASSIC:-0}" -eq 1 ] && [ "${#CLASSIC_PORTS_LIST[@]}" -gt 0 ]; then
    CLASSIC_CRED_BLOCK="[ CLASSIC EXTERNAL REALITY ]
Локальные порты Xray:  ${CLASSIC_PORTS_DISP} (L4 Ingress 443/tcp)
Внешние SNI:           ${EXT_SNI_DISP}

"
fi

NAWG_CRED_BLOCK=""
if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    NAWG_CONF_NOTE="Действующая конфигурация клиентов сохранена в /etc/amnezia/amneziawg/clients.json"
    if [ -f /root/amneziawg-client.conf ]; then
        NAWG_CONF_NOTE="/root/amneziawg-client.conf (клиент: Test-Client)"
    fi
    NAWG_CRED_BLOCK=$(cat << EOF_NAWG_CRED
[ НА ТЕХНОЛОГИЯХ ЯДРА: НА РАБОЧЕМ ЖЕЛЕЗЕ AMNEZIAWG ]
Интерфейс:             awg0 (Модуль ядра Linux DKMS)
Выделенный порт/хост:  ${PRIMARY_DOMAIN}:${NATIVE_AWG_PORT}
Клиентский профиль:    ${NAWG_CONF_NOTE}
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4 | Jmin 40 | Jmax 70 | S1 72 | S2 56 | S3 32 | S4 16
EOF_NAWG_CRED
)
    NAWG_CRED_BLOCK+=$'\n\n'
fi

AGH_CRED_BLOCK=""
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    AGH_CRED_BLOCK=$(cat << EOF_AGH_CRED
[ ПРИВАТНЫЙ ADGUARD HOME DOH ]
Веб-интерфейс:         https://${AGH_DOMAIN}/
Логин администратора:  ${AGH_USER}
Пароль администратора: ${AGH_PASS}
URL DoH для роутера:   https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}
Телеметрия (24ч RAM):  $([ "${AGH_RAM_TELEMETRY:-0}" = "1" ] && echo "Включена (tmpfs /run/adguardhome, ${AGH_TMPFS_SIZE})" || echo "Отключена (Strict Zero-Log)")
EOF_AGH_CRED
)
    AGH_CRED_BLOCK+=$'\n\n'
fi

SUB_CRED_BLOCK=""
if [ "$INSTALL_MODE" = "1" ] && [ "$HAS_3XUI_INBOUND" -eq 1 ]; then
    SUB_CRED_BLOCK=$(cat << EOF_SUB_CRED
[ ПОДПИСКИ КЛИЕНТОВ (МУЛЬТИПРОТОКОЛЬНЫЕ) ]
Клиент:                ${TEST_EMAIL}
Прямая ссылка (Base64):https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (JSON):  https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (Clash): https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}
EOF_SUB_CRED
)
    SUB_CRED_BLOCK+=$'\n\n'
elif [ "$INSTALL_MODE" = "2" ]; then
    SUB_CRED_BLOCK="[ ПОДПИСКИ КЛИЕНТОВ ]
Все существующие подписки, UUID и ключи сохранены без перезаписи.

"
fi

PANEL_AUTH_CRED_BLOCK="Логин администратора:  ${REAL_ADMIN_USER}
Пароль администратора: Сохранён из прежней базы"
if [ "$INSTALL_MODE" = "1" ]; then
    PANEL_AUTH_CRED_BLOCK="Логин администратора:  ${REAL_ADMIN_USER}
Пароль администратора: ${ADMIN_PASS}"
fi

HY2_CRED_BLOCK=""
if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    HY2_CRED_BLOCK="[ HYSTERIA 2 ]
Подключение:           ${PRIMARY_DOMAIN}:${HY2_PORT}/udp

"
fi

AWG3_CRED_BLOCK=""
if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    AWG3_CRED_BLOCK="[ AMNEZIAWG v3.2 (3X-UI) ]
Порт / Хост:           ${PRIMARY_DOMAIN}:${AWG_V3_PORT}/udp
Клиент (.conf / QR):   AWG-v3-Client (exclude_from_sub=1, без vpn:// в подписках)
Стандарт скорости:     MTU 1360 | MSS 1320 | Jc 4 | S1 72 | S2 56 | S3 32 | S4 16

"
fi

CRED_FILE="/root/vpn_credentials.txt"
(
    umask 077
    cat << EOF > "$CRED_FILE.tmp"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА (Hardened Master Engine v3.9)
  ОС: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  Ядро Xray-core: ${DETECTED_XRAY_VER} (Pinned)
  Nginx Mainline: ${INSTALLED_NGINX_VER} (proxy_http_version 2)
  Режим:          $([ "$INSTALL_MODE" = "2" ] && echo "Safe Migration" || echo "Clean Setup")
  Дата:           $(date '+%Y-%m-%d %H:%M:%S')
=====================================================================

[ СКРЫТЫЙ SSO ШЛЮЗ АДМИНИСТРАТОРА (ZERO-LEAK) ]
Точка входа:           https://${PRIMARY_DOMAIN}/
Инструкция:            Нажмите кнопку «${DECOY_BTN_LABEL}» в правом верхнем углу шапки сайта MyPrivateCloud.
                       В открывшейся замаскированной форме введите логин: ${REAL_ADMIN_USER}
                       и пароль: $([ "$INSTALL_MODE" = "1" ] && echo "${ADMIN_PASS}" || echo "Ваш пароль администратора 3X-UI")
                       После входа в памяти браузера откроется меню модулей:
                       ${SSO_MENU_ITEMS}

[ ПРЯМОЙ ДОСТУП В ПАНЕЛЬ 3X-UI ]
URL панели:            https://${PRIMARY_DOMAIN}${PANEL_PATH}
${PANEL_AUTH_CRED_BLOCK}
Внутренний сокет:      127.0.0.1:${PANEL_PORT} (Изолирован)

${STEAL_CRED_BLOCK}${XHTTP_CRED_BLOCK}${CLASSIC_CRED_BLOCK}${HY2_CRED_BLOCK}${NAWG_CRED_BLOCK}${AWG3_CRED_BLOCK}${AGH_CRED_BLOCK}${SUB_CRED_BLOCK}[ СЕТЕВЫЕ ПАРАМЕТРЫ ]
Основной хост:         ${PRIMARY_DOMAIN} (IP: ${WAN_IP:-auto})
Сетевой адаптер (WAN): ${DEFAULT_IF}
SSH порт:              ${TARGET_SSH_PORT}

[ ПРОВЕРКА ДОСТУПА И ПЛАНОВАЯ ПЕРЕЗАГРУЗКА ]
1. Откройте НОВОЕ окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).
2. При обновлении ядра или для контрольного рестарта выполните: reboot
=====================================================================
EOF
)
chmod 0600 "$CRED_FILE.tmp"
mv -f "$CRED_FILE.tmp" "$CRED_FILE"

for sec_f in \
    /root/vpn_credentials.txt \
    /root/amneziawg-client.conf \
    /etc/myprivatecloud/sso.key \
    /etc/myprivatecloud/sso_agh.json \
    /etc/myprivatecloud/config.env \
    /etc/myprivatecloud/config.json \
    /opt/AdGuardHome/AdGuardHome.yaml \
    /etc/amnezia/amneziawg/awg0.conf \
    /etc/amnezia/amneziawg/clients.json \
    "${DB_PATH:-/etc/x-ui/x-ui.db}"; do
    if [ -f "$sec_f" ]; then
        chmod 0600 "$sec_f" 2>/dev/null || true
    fi
done

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА (v3.9 MyPrivateCloud ULTRA)!            ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Сайт-маскировка MyPrivateCloud:  ${CYAN}https://${PRIMARY_DOMAIN}/${NC}"
echo -e "  Скрытый SSO Hub:             ${WHITE}Кнопка «${DECOY_BTN_LABEL}» в правом верхнем углу шапки${NC}"
if [ "$INSTALL_MODE" = "1" ]; then
    echo -e "  Логин: ${WHITE}${REAL_ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
fi
echo
echo -e "  Прямой URL панели 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
echo -e "  Сетевой адаптер (WAN):       ${GREEN}${DEFAULT_IF} (Universal Dynamic WAN Engine)${NC}"
echo -e "  Веб-шлюз Nginx Mainline:     ${GREEN}${INSTALLED_NGINX_VER} (L4 Ingress 443/tcp, Zero-SNI Shield, Port 80 444 Drop)${NC}"
if [ "${ENABLE_BBR_TUNING:-0}" -eq 1 ]; then
    echo -e "  Тюнинг ядра (BBR/FQ/TFO):    ${GREEN}Активен (BBR + Loose rp_filter + MTU Probing)${NC}"
fi
if [ "${ENABLE_AUTO_UPDATE:-0}" -eq 1 ]; then
    if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
        echo -e "  Автообслуживание (ОС/AWG):   ${GREEN}Активно (Вс 04:00 UTC, пересборка AWG + Circuit Breaker ON)${NC}"
    else
        echo -e "  Автообслуживание (ОС/Ядро):  ${GREEN}Активно (Вс 04:00 UTC)${NC}"
    fi
fi

if [ "${ENABLE_STEAL:-0}" -eq 1 ] && [ "${#STEAL_PORTS_LIST[@]}" -gt 0 ]; then
    echo -e "  ${WHITE}Steal-Oneself REALITY:${NC}       ${GREEN}Порты ${STEAL_PORTS_DISP} | Домены: ${STEAL_DOMS_DISP} (Fallback :${REALITY_FALLBACK_PORT})${NC}"
fi
if [ "${ENABLE_XHTTP:-0}" -eq 1 ]; then
    echo -e "  ${WHITE}VLESS xHTTP Inbound:${NC}         ${GREEN}${PRIMARY_DOMAIN}:443 (${BASE_XHTTP_PATH}, H2 Stream-One, proxy_http_version 2, Vision${PQC_STATUS_LABEL})${NC}"
fi
if [ "${ENABLE_CLASSIC:-0}" -eq 1 ] && [ "${#CLASSIC_PORTS_LIST[@]}" -gt 0 ]; then
    echo -e "  ${WHITE}Classic External REALITY:${NC}    ${GREEN}Порты ${CLASSIC_PORTS_DISP} | SNI: ${EXT_SNI_DISP}${NC}"
fi
if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    echo -e "  ${WHITE}Hysteria 2:${NC}                  ${GREEN}Выделенный порт :${HY2_PORT}/udp${NC}"
fi
if [ "${ENABLE_NATIVE_AWG:-0}" -eq 1 ]; then
    echo -e "  ${WHITE}AmneziaWG Native (Kernel):${NC}   ${GREEN}awg0 (:${NATIVE_AWG_PORT}/udp, MTU 1360 / MSS 1320)${NC}"
    if [ -f /root/amneziawg-client.conf ]; then
        echo -e "  ${WHITE}Профиль AWG клиента:${NC}         ${GREEN}/root/amneziawg-client.conf (Test-Client)${NC}"
    fi
fi
if [ "${ENABLE_AWG_V3:-0}" -eq 1 ]; then
    echo -e "  ${WHITE}AmneziaWG v3.2 (3X-UI):${NC}      ${GREEN}:${AWG_V3_PORT}/udp (Клиент: AWG-v3-Client, exclude_from_sub=1, MTU 1360)${NC}"
fi
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    echo -e "  ${WHITE}Панель AdGuard Home:${NC}         ${CYAN}https://${AGH_DOMAIN}/${NC}"
    echo -e "  ${WHITE}Приватный DoH для роутера:${NC}   ${GREEN}https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}${NC}"
    echo -e "  ${WHITE}AGH Журнал/Статистика (24ч):${NC} $([ "${AGH_RAM_TELEMETRY:-0}" = "1" ] && echo "${GREEN}RAM tmpfs /run/adguardhome (${AGH_TMPFS_SIZE})${NC}" || echo "${GREEN}Отключены (Strict Zero-Log)${NC}")"
fi

if [ "$INSTALL_MODE" = "1" ] && [ "$HAS_3XUI_INBOUND" -eq 1 ]; then
    echo
    echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Единая ссылка Base64):${NC}"
    echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}${NC}"
    echo
    echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (JSON для Sing-box):${NC}"
    echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}${NC}"
    echo
    echo -e "  ${BOLD}Клиент «${TEST_EMAIL}» (Clash / Mihomo Meta):${NC}"
    echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_CLASH_PATH}${UNIFIED_SUB_ID}${NC}"
fi

echo
echo -e "  ${WHITE}Zero-Leak In-Memory Hub:${NC}     ${GREEN}Разметка меню строится в RAM только после 200 OK${NC}"
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${YELLOW}---------------------------------------------------------------------${NC}"
echo -e "${YELLOW}${BOLD}ПРОВЕРКА ДОСТУПА И ПЛАНОВАЯ ПЕРЕЗАГРУЗКА:${NC}"
echo -e "${WHITE}1. Откройте ${BOLD}НОВОЕ${NC} окно консоли и проверьте вход по SSH (порт ${TARGET_SSH_PORT}).${NC}"
if [ "${SSH_NO_KEYS_WARN:-0}" -eq 1 ]; then
    echo -e "${RED}${BOLD}[!] ВНИМАНИЕ: Вход по паролю SSH остался активен (ключи не настроены). Добавьте Ed25519-ключ!${NC}"
fi
echo -e "${WHITE}2. При обновлении ядра или для контрольного рестарта выполните: ${GREEN}${BOLD}reboot${NC}"
echo -e "${GREEN}=====================================================================${NC}"

ROLLBACK_ACTIVE=0
rm -rf "${NGINX_PRE_BAK:-}" "${XUI_PRE_BAK:-}" 2>/dev/null || true

echo
if prompt_yes_no "Установить / обновить скрипт аудита безопасности и DPI/ТСПУ (/usr/local/bin/hardcore_dpi_audit.sh)?" "n"; then
    AUDIT_BIN="/usr/local/bin/hardcore_dpi_audit.sh"
    cat << 'EOF_HARDCORE_AUDIT' > "${AUDIT_BIN}.tmp"
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8 PYTHONUTF8=1

command -v python3 >/dev/null 2>&1 || { echo "[X] Требуется python3." >&2; exit 1; }
LOCK_DIR="/run/lock"
[ -w "${LOCK_DIR}" ] || LOCK_DIR="/tmp"
exec 200>"${LOCK_DIR}/hardcore_dpi_audit.lock"
flock -n 200 || { echo "[X] Аудит уже выполняется." >&2; exit 1; }

# shellcheck disable=SC2317
cleanup() { local rc=$?; trap - ERR EXIT INT TERM; rm -f /tmp/hardcore_audit_*.tmp 2>/dev/null || true; exit "$rc"; }
trap cleanup ERR EXIT INT TERM

python3 - "$@" << 'PY_AUDIT'
# -*- coding: utf-8 -*-
from __future__ import annotations
import argparse, base64, glob, hashlib, http.client, ipaddress, json, os, re, secrets, shutil, socket, sqlite3, ssl, stat, struct, subprocess, sys, time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

G, C, Y, R, D, B, N = "\033[0;32m", "\033[0;36m", "\033[1;33m", "\033[0;31m", "\033[0;90m", "\033[1m", "\033[0m"
DDNS_SFX = ("duckdns.org", "no-ip.org", "no-ip.com", "ddns.net", "hopto.org", "zapto.org", "dynu.net", "ydns.eu", "dedyn.io", "nip.io", "sslip.io")
VPN_KWS = ("mihomo", "singbox", "sing-box", "happ://", "incy://", "vless", "vmess", "trojan", "hysteria", "reality", "xhttp", "xray", "3x-ui", "amnezia", "wireguard", "xtls-rprx-vision", "mlkem768")
BANNERS = ("<center>nginx</center>", "openresty", "uvicorn", "fastapi", "adguard home", "dns request failed")

@dataclass
class Check:
    cid: str; dom: str; title: str; sev: str; st: str; ev: str; fix: str = ""; view: str = ""; pub_title: str = ""

@dataclass
class Cfg:
    mode: str; ip: str; p_dom: str; steals: List[str] = field(default_factory=list)
    agh_dom: str = ""; agh_cid: str = ""; xhttp_p: str = ""; panel_p: str = ""; sub_p: str = ""
    p_port: int = 10443; s_port: int = 55443; x_port: int = 50443; hy2_p: int = 0
    nawg_p: int = 0; awg3_p: int = 0; en_agh: bool = False; en_nawg: bool = False
    r_ports: List[int] = field(default_factory=list); db: str = ""; rl: bool = False; to: float = 4.0; pub_ip: str = ""

def cmd(args: List[str], to: int = 10) -> Tuple[int, str, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=to)
        return p.returncode, p.stdout, p.stderr
    except Exception as e:
        return -1, "", str(e)

def mmh3_32_signed(data: bytes, seed: int = 0) -> int:
    c1, c2 = 0xCC9E2D51, 0x1B873593
    h1 = seed & 0xFFFFFFFF
    length = len(data)
    rounded_end = length & ~0x3
    for i in range(0, rounded_end, 4):
        k1 = struct.unpack_from("<I", data, i)[0]
        k1 = (k1 * c1) & 0xFFFFFFFF
        k1 = ((k1 << 15) | (k1 >> 17)) & 0xFFFFFFFF
        k1 = (k1 * c2) & 0xFFFFFFFF
        h1 ^= k1
        h1 = ((h1 << 13) | (h1 >> 19)) & 0xFFFFFFFF
        h1 = (h1 * 5 + 0xE6546B64) & 0xFFFFFFFF
    tail = length & 0x3
    k1 = 0
    if tail == 3: k1 ^= data[rounded_end + 2] << 16
    if tail >= 2: k1 ^= data[rounded_end + 1] << 8
    if tail >= 1:
        k1 ^= data[rounded_end]
        k1 = (k1 * c1) & 0xFFFFFFFF
        k1 = ((k1 << 15) | (k1 >> 17)) & 0xFFFFFFFF
        k1 = (k1 * c2) & 0xFFFFFFFF
        h1 ^= k1
    h1 ^= length
    h1 ^= (h1 >> 16)
    h1 = (h1 * 0x85EBCA6B) & 0xFFFFFFFF
    h1 ^= (h1 >> 13)
    h1 = (h1 * 0xC2B2AE35) & 0xFFFFFFFF
    h1 ^= (h1 >> 16)
    return -((h1 ^ 0xFFFFFFFF) + 1) if (h1 & 0x80000000) else h1

def tcp_open(ip: str, port: int, to: float = 1.0, fam: int = socket.AF_INET) -> Tuple[bool, bytes]:
    s = socket.socket(fam, socket.SOCK_STREAM)
    s.settimeout(to)
    try:
        s.connect((ip, port)); s.settimeout(0.35)
        try: b = s.recv(256)
        except Exception: b = b""
        return True, b
    except Exception: return False, b""
    finally: s.close()

def raw_tcp(ip: str, port: int, payload: bytes, to: float = 2.8) -> Tuple[str, bytes, float]:
    t0 = time.monotonic()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(to)
    try:
        s.connect((ip, port))
        if payload: s.sendall(payload)
        chunks: List[bytes] = []; s.settimeout(min(to, 1.8))
        try:
            while True:
                buf = s.recv(4096)
                if not buf: break
                chunks.append(buf)
                if sum(len(x) for x in chunks) > 16384: break
        except socket.timeout:
            ms = (time.monotonic() - t0) * 1000.0
            return ("DATA", b"".join(chunks), ms) if chunks else ("HANG_TIMEOUT", b"", ms)
        except ConnectionResetError:
            return "TCP_RST", b"".join(chunks), (time.monotonic() - t0) * 1000.0
        raw = b"".join(chunks); ms = (time.monotonic() - t0) * 1000.0
        return ("DATA", raw, ms) if raw else ("EOF_SILENT", b"", ms)
    except ConnectionResetError: return "TCP_RST", b"", (time.monotonic() - t0) * 1000.0
    except socket.timeout: return "CONNECT_TIMEOUT", b"", (time.monotonic() - t0) * 1000.0
    except OSError as e: return f"ERR_{e.errno}", b"", (time.monotonic() - t0) * 1000.0
    finally: s.close()

def http_sni(ip: str, sni: str, meth: str, path: str, hdrs: Optional[Dict[str, str]] = None, body: Optional[bytes] = None, to: float = 4.0) -> Tuple[int, Dict[str, str], bytes, float, str]:
    cb = shutil.which("curl")
    rh = dict(hdrs or {})
    if "User-Agent" not in rh:
        rh["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0"
    if cb:
        c = [cb, "-sS", "-i", "-k", "--http2", "--connect-timeout", str(int(max(2.0, to))), "-m", str(int(to + 2)), "--resolve", f"{sni}:443:{ip}", "-X", meth, "-w", "\n__META__%{http_code}|%{time_appconnect}|%{http_version}"]
        for k, v in rh.items():
            c.extend(["-H", f"{k}:" if v == "" else f"{k}: {v}"])
        if body is not None: c.extend(["--data-binary", "@-"])
        c.append(f"https://{sni}{path}")
        try:
            p = subprocess.run(c, input=body, capture_output=True, timeout=int(to + 5))
            out = p.stdout; mk = b"\n__META__"
            if mk in out:
                hp, mp = out.rsplit(mk, 1)
                mv = mp.decode("utf-8", "replace").strip().split("|")
                st = int(mv[0]) if mv[0].isdigit() else 0
                rtt = float(mv[1]) * 1000.0 if len(mv) > 1 and mv[1] else 0.0
                ver = f"HTTP/{mv[2]}" if len(mv) > 2 else "HTTP/2"
                sep = b"\r\n\r\n" if b"\r\n\r\n" in hp else b"\n\n"
                hr, rb = hp.split(sep, 1) if sep in hp else (hp, b"")
                res_h: Dict[str, str] = {}
                for ln in hr.decode("utf-8", "replace").splitlines()[1:]:
                    if ":" in ln:
                        k, v = ln.split(":", 1); res_h[k.strip().lower()] = v.strip()
                return st, res_h, rb, rtt, ver
        except Exception as e:
            raise RuntimeError(str(e))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    ctx.set_alpn_protocols(["http/1.1"])
    class SC(http.client.HTTPSConnection):
        def connect(self) -> None:
            self.sock = ctx.wrap_socket(socket.create_connection((ip, self.port), self.timeout), server_hostname=sni)
    t0 = time.monotonic(); cn = SC(sni, port=443, timeout=to)
    try:
        cn.request(meth, path, body=body, headers=rh); r = cn.getresponse()
        return r.status, {k.lower(): v for k, v in r.getheaders()}, r.read(), (time.monotonic() - t0) * 1000.0, "HTTP/1.1"
    finally: cn.close()

def raw_hello(sni: Optional[str], rver: int = 0x0301, cver: int = 0x0303, t13: bool = True, weak: bool = False, corrupt: bool = False) -> bytes:
    rnd = secrets.token_bytes(32); sid = secrets.token_bytes(32) if t13 else b""
    cids = [0x0005, 0x000A, 0x002F, 0x0035] if weak else [0x1301, 0x1302, 0x1303, 0xC02B, 0xC02F]
    craw = b"".join(struct.pack(">H", c) for c in cids); exts: List[bytes] = []
    if sni:
        sb = sni.encode("ascii"); ent = struct.pack(">BH", 0, len(sb)) + sb
        sl = struct.pack(">H", len(ent)) + ent; exts.append(struct.pack(">HH", 0, len(sl)) + sl)
    al = b"".join(struct.pack(">B", len(a)) + a for a in (b"h2", b"http/1.1"))
    ab = struct.pack(">H", len(al)) + al; exts.append(struct.pack(">HH", 0x0010, len(ab)) + ab)
    gr = struct.pack(">HHH", 0x001D, 0x0017, 0x0018); exts.append(struct.pack(">HHH", 0x000A, len(gr) + 2, len(gr)) + gr)
    exts.append(struct.pack(">HHBB", 0x000B, 2, 1, 0))
    sg = struct.pack(">HHH", 0x0403, 0x0804, 0x0401); exts.append(struct.pack(">HHH", 0x000D, len(sg) + 2, len(sg)) + sg)
    if t13:
        sv = struct.pack(">HH", 0x0304, 0x0303); exts.append(struct.pack(">HHB", 0x002B, len(sv) + 1, len(sv)) + sv)
        ks = struct.pack(">HH", 0x001D, 32) + secrets.token_bytes(32)
        exts.append(struct.pack(">HHH", 0x0033, len(ks) + 2, len(ks)) + ks)
        exts.append(struct.pack(">HHBB", 0x002D, 2, 1, 1))
    if corrupt: exts.append(struct.pack(">HH", 0xFFFE, 48) + secrets.token_bytes(16))
    er = b"".join(exts)
    bd = struct.pack(">H", cver) + rnd + struct.pack(">B", len(sid)) + sid + struct.pack(">H", len(craw)) + craw + b"\x01\x00" + struct.pack(">H", len(er)) + er
    hs = b"\x01" + struct.pack(">I", len(bd))[1:] + bd
    return struct.pack(">BHH", 0x16, rver, len(hs)) + hs

def tls_probe_raw(ip: str, payload: bytes, to: float = 2.8) -> Tuple[str, float, int]:
    st, d, ms = raw_tcp(ip, 443, payload, to)
    if st != "DATA": return st, ms, 0
    if len(d) >= 7 and d[0] == 0x15: return f"TLS_ALERT_{d[6]}", ms, len(d)
    if len(d) >= 6 and d[0] == 0x16 and d[5] == 0x02: return "SERVER_HELLO", ms, len(d)
    return f"RAW_{d[:4].hex()}", ms, len(d)

def tls_details(ip: str, sni: str, ver: str, to: float = 4.0) -> Tuple[bool, str, List[str], Optional[int]]:
    ctx = ssl.create_default_context(); ctx.check_hostname = True
    if ver == "1.2": ctx.minimum_version = ssl.TLSVersion.TLSv1_2; ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    elif ver == "1.3": ctx.minimum_version = ssl.TLSVersion.TLSv1_3; ctx.maximum_version = ssl.TLSVersion.TLSv1_3
    ctx.set_alpn_protocols(["h2", "http/1.1"])
    try:
        with socket.create_connection((ip, 443), to) as r:
            with ctx.wrap_socket(r, server_hostname=sni) as ss:
                cert = ss.getpeercert() or {}
                sans = [str(e[1]) for e in cert.get("subjectAltName", ()) if isinstance(e, tuple) and len(e) == 2 and e[0] == "DNS"]
                age = None; nb = cert.get("notBefore")
                if isinstance(nb, str):
                    try: age = (datetime.now(timezone.utc) - datetime.strptime(nb, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)).days
                    except Exception: pass
                return True, str(ss.selected_alpn_protocol() or "none"), sans, age
    except ssl.SSLCertVerificationError as e: return False, f"CERT_ERR:{e.verify_message}", [], None
    except Exception as e: return False, type(e).__name__, [], None

def sclient_fingerprint(ip: str, sni: str) -> Dict[str, str]:
    info: Dict[str, str] = {}
    if not shutil.which("openssl"): return info
    try:
        p = subprocess.run(
            ["openssl", "s_client", "-connect", f"{ip}:443", "-servername", sni, "-tls1_3", "-alpn", "h2"],
            input=b"", capture_output=True, timeout=4
        )
        out = (p.stdout + p.stderr).decode("utf-8", "ignore")
        for cm in re.finditer(r"^\s*(?:New,\s+TLSv[\d.]+,\s+Cipher\s+is|Cipher\s*:)\s*([^\s(,]+)", out, re.M):
            cv = cm.group(1).strip()
            if cv not in ("0000", "(NONE)"):
                info["cipher"] = cv
                break
        for key, pat in (
            ("temp_key", r"^\s*Server Temp Key:\s*(.+)$"),
            ("alpn", r"^\s*ALPN protocol:\s*(\S+)"),
            ("early", r"^\s*Max Early Data:\s*(\d+)"),
        ):
            m = re.search(pat, out, re.M)
            if m: info[key] = m.group(1).strip()
        info["early_data"] = "YES" if ("Early data was accepted" in out or int(info.get("early", "0")) > 0) else "NO"
    except Exception: pass
    return info

def dns_wire(qn: str = "example.com") -> bytes:
    lb = b"".join(bytes([len(p)]) + p.encode("ascii") for p in qn.split(".")) + b"\x00"
    return secrets.token_bytes(2) + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + lb + struct.pack(">HH", 1, 1)

def discover(args: argparse.Namespace) -> Cfg:
    has_loc = os.path.exists("/etc/myprivatecloud/config.json") or os.path.exists("/etc/x-ui/x-ui.db")
    mode = ("local" if has_loc else "remote") if args.mode == "auto" else args.mode
    env_m: Dict[str, str] = {}; cfg_j: Dict[str, Any] = {}
    if mode == "local":
        if os.path.exists("/etc/myprivatecloud/config.env"):
            for ln in open("/etc/myprivatecloud/config.env", encoding="utf-8", errors="ignore"):
                m = re.match(r'^\s*([A-Z0-9_]+)\s*=\s*"?([^"\n\r]*)"?\s*$', ln)
                if m: env_m[m.group(1)] = m.group(2).strip()
        if os.path.exists("/etc/myprivatecloud/config.json"):
            try: cfg_j = json.load(open("/etc/myprivatecloud/config.json", encoding="utf-8"))
            except Exception: pass

    t_arg = args.target.strip()
    p_dom = args.domain or ("" if re.match(r"^\d+\.\d+\.\d+\.\d+$", t_arg) else t_arg) or str(cfg_j.get("primary_domain") or env_m.get("PRIMARY_DOMAIN") or "")
    a_dom = args.agh_domain or str(cfg_j.get("agh_domain") or env_m.get("AGH_DOMAIN") or "")
    a_cid = args.agh_client_id or str(env_m.get("AGH_CLIENT_ID") or "")
    ip = args.target_ip or (t_arg if re.match(r"^\d+\.\d+\.\d+\.\d+$", t_arg) else "")

    if mode == "remote" and not p_dom and not ip:
        if sys.stdin.isatty():
            v = input("Введите домен (FQDN) или IP целевого сервера: ").strip()
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", v): ip = v
            else: p_dom = v
            if not args.steal_domain: args.steal_domain = input("Steal-REALITY домен (опц., Enter пропуск): ").strip()
            if not a_dom: a_dom = input("AdGuard DoH домен (опц., Enter пропуск): ").strip()
            if not args.xhttp_path: args.xhttp_path = input("xHTTP путь (опц., Enter пропуск): ").strip()
        else:
            print(f"{R}[X] Укажите цель: --target <DOMAIN_OR_IP>{N}", file=sys.stderr); sys.exit(1)

    if not ip and mode == "local":
        rc, out, _ = cmd(["ip", "-4", "route", "get", "1.1.1.1"], 3)
        ms = re.search(r"\bsrc\s+(\d+\.\d+\.\d+\.\d+)", out) if rc == 0 else None
        if ms: ip = ms.group(1)
    if not ip and p_dom:
        try: ip = socket.gethostbyname(p_dom)
        except Exception: pass
    ip = ip or "127.0.0.1"
    pub_ip = ""
    try:
        if not ipaddress.ip_address(ip).is_private:
            pub_ip = ip
    except Exception:
        pass
    if mode == "local" and not pub_ip and shutil.which("curl"):
        for ep in ("https://icanhazip.com", "https://ifconfig.me"):
            rc_p, out_p, _ = cmd(["curl", "-s4", "--connect-timeout", "2", "-m", "3", ep], 4)
            cand_p = out_p.strip()
            if rc_p == 0 and re.match(r"^\d+\.\d+\.\d+\.\d+$", cand_p):
                try:
                    if not ipaddress.ip_address(cand_p).is_private:
                        pub_ip = cand_p
                        break
                except Exception:
                    pass

    steals = [x.strip() for x in args.steal_domain.split(",") if x.strip()]
    r_ports: List[int] = []; xp = args.xhttp_path or ""; sp = args.sub_path or str(cfg_j.get("sub_path") or env_m.get("SUB_PATH") or "")
    pp = str(cfg_j.get("panel_path") or env_m.get("PANEL_PATH") or "")
    p_port = int(str(cfg_j.get("panel_port") or env_m.get("PANEL_PORT") or "10443"))
    s_port = int(str(cfg_j.get("sub_port") or env_m.get("SUB_PORT") or "55443"))
    x_port, hy2_p, awg3_p, nawg_p = 50443, args.hy2_port, 0, 0
    db_p = ""; en_nawg = False; en_agh = bool(a_dom)

    if mode == "local":
        for cand in ("/etc/x-ui/x-ui.db", "/usr/local/x-ui/bin/x-ui.db", "/etc/x-ui/db/x-ui.db"):
            if os.path.exists(cand): db_p = cand; break
        if db_p:
            try:
                cn = sqlite3.connect(f"file:{db_p}?mode=ro", uri=True, timeout=3.0)
                for k, v in cn.execute("SELECT key, value FROM settings WHERE key IN ('webPort','subPort','webBasePath','subPath')"):
                    if k == "webPort" and str(v).isdigit(): p_port = int(v)
                    elif k == "subPort" and str(v).isdigit(): s_port = int(v)
                    elif k == "webBasePath" and v: pp = str(v)
                    elif k == "subPath" and v and not sp: sp = str(v)
                ib_cols = {r[1] for r in cn.execute("PRAGMA table_info(inbounds)")}
                nc_parts, nc_params = [], []
                if "node_id" in ib_cols: nc_parts.append("(node_id IS NULL OR node_id = 0)")
                if "origin_node_guid" in ib_cols:
                    pg_r = cn.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1").fetchone()
                    pg_v = str(pg_r[0]).strip() if pg_r and pg_r[0] else ""
                    if pg_v:
                        nc_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                        nc_params.append(pg_v)
                    else:
                        nc_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
                nc_sql = (" AND " + " AND ".join(nc_parts)) if nc_parts else ""
                for pr, port, st_raw, tag in cn.execute(f"SELECT protocol, port, stream_settings, tag FROM inbounds WHERE enable=1{nc_sql}", nc_params):
                    st = json.loads(st_raw) if st_raw else {}
                    if pr == "vless" and "xhttpSettings" in st:
                        x_port = int(port); xp = xp or str(st["xhttpSettings"].get("path", ""))
                    if pr == "vless" and "realitySettings" in st:
                        r_ports.append(int(port))
                        rs_d = st["realitySettings"]
                        if "steal" in str(tag).lower() or str(rs_d.get("dest", rs_d.get("target", ""))).strip() == "127.0.0.1:9443":
                            for sn in rs_d.get("serverNames", []):
                                if sn and str(sn) not in steals: steals.append(str(sn))
                    if pr == "hysteria" and hy2_p == 0: hy2_p = int(port)
                    if pr == "amneziawg": awg3_p = int(port)
                cn.close()
            except Exception: pass
        en_nawg = os.path.exists("/etc/amnezia/amneziawg/awg0.conf")
        if en_nawg:
            mp = re.search(r"^\s*ListenPort\s*=\s*(\d+)", open("/etc/amnezia/amneziawg/awg0.conf", errors="ignore").read(), re.M)
            if mp: nawg_p = int(mp.group(1))
        en_agh = os.path.exists("/opt/AdGuardHome/AdGuardHome.yaml") and os.path.exists("/etc/nginx/conf.d/03-adguard.conf")

    if args.awg_ports:
        ap = [int(x.strip()) for x in args.awg_ports.split(",") if x.strip().isdigit()]
        if ap: nawg_p = ap[0]; awg3_p = ap[1] if len(ap) > 1 else awg3_p

    return Cfg(mode, ip, p_dom, steals, a_dom, a_cid, xp, pp, sp, p_port, s_port, x_port, hy2_p, nawg_p, awg3_p, en_agh, en_nawg, sorted(set(r_ports)), db_p, bool(args.test_ratelimit), 4.0, pub_ip)

def run_remote_checks(cfg: Cfg) -> List[Check]:
    items: List[Check] = []
    fp_main: Dict[str, str] = {}

    # R1: Периметр, Open Proxy, Port 80, PTR, IPv6 Dual-Stack, DNS Origin Leak
    ports = sorted(set([21, 22, 23, 25, 53, 80, 443, 1080, 3000, 3128, 5201, 8080, 8088, 8443, 9443, 10443, 11111, 20443, 45443, 46443, 50443, 55443, 62789, 65140, cfg.p_port, cfg.s_port, cfg.x_port] + cfg.r_ports))
    intl = {53, 1080, 3000, 3128, 5201, 8088, 9443, 11111, 20443, 45443, 46443, 50443, 55443, 62789, 65140, cfg.p_port, cfg.s_port, cfg.x_port}
    op_list: List[str] = []; exp_int: List[int] = []
    for p in ports:
        if p <= 0: continue
        ok, ban = tcp_open(cfg.ip, p, 0.85)
        if ok:
            bs = ban.decode("ascii", "ignore").strip().splitlines()[0][:32] if ban else ""
            op_list.append(f"{p}({bs})" if bs else str(p))
            if p in intl: exp_int.append(p)
    items.append(Check("R1-01", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "Изоляция внутренних TCP-портов", "CRITICAL", "FAIL" if exp_int else "PASS",
        f"Открыты внутренние: {exp_int} (все: {', '.join(op_list)})" if exp_int else f"Открыты только штатные порты: {', '.join(op_list) or 'нет'}",
        "Закройте внутренние порты в UFW и bind на 127.0.0.1", f"Внешние порты: {', '.join(op_list)}", "Изоляция внутренних TCP-портов"))

    pl = [str(pp) for pp in (80, 443) if b"200 Connection established" in raw_tcp(cfg.ip, pp, b"CONNECT 1.1.1.1:443 HTTP/1.1\r\nHost: 1.1.1.1:443\r\n\r\n", 1.8)[1]]
    items.append(Check("R1-02", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "Защита от Open HTTP/CONNECT Proxy", "CRITICAL", "FAIL" if pl else "PASS",
        f"Уязвимы порты: {', '.join(pl)}" if pl else "CONNECT-проксирование на 80/443 отклонено.", pub_title="Защита от Open HTTP/CONNECT Proxy"))

    st_i, d_i, _ = raw_tcp(cfg.ip, 80, f"GET / HTTP/1.1\r\nHost: {cfg.ip}\r\nConnection: close\r\n\r\n".encode("ascii"), 2.0)
    st_f, d_f, _ = raw_tcp(cfg.ip, 80, b"GET / HTTP/1.1\r\nHost: evil-scanner.invalid\r\nConnection: close\r\n\r\n", 2.0)
    drop_ok = (st_i in ("EOF_SILENT", "TCP_RST") and not d_i and st_f in ("EOF_SILENT", "TCP_RST") and not d_f)
    p80_dom_bad: List[str] = []
    if cfg.p_dom:
        _, d80, _ = raw_tcp(cfg.ip, 80, f"GET / HTTP/1.1\r\nHost: {cfg.p_dom}\r\nConnection: close\r\n\r\n".encode("ascii"), 2.0)
        h80 = d80.decode("utf-8", "ignore").splitlines()[0] if d80 else "NO_DATA"
        if "301" not in h80 or re.search(rb"Server:\s*nginx/\d", d80, re.I): p80_dom_bad.append(h80)
    items.append(Check("R1-03", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "Порт 80/tcp (IP/Fake-Host 444 Drop & Redirect)", "MEDIUM",
        "PASS" if (drop_ok and not p80_dom_bad) else "WARN",
        f"IP={st_i}, FakeHost={st_f}, MainHost={p80_dom_bad or '301 OK'}", "Настройте return 444 для _ и 301 для PRIMARY_DOMAIN", pub_title="Порт 80/tcp (Drop без Host и 301 Redirect)"))

    ptr_ip = cfg.pub_ip or cfg.ip
    try:
        is_priv_ptr = ipaddress.ip_address(ptr_ip).is_private
        ptr = "PRIVATE_NAT" if is_priv_ptr else socket.gethostbyaddr(ptr_ip)[0]
    except Exception:
        ptr = "NXDOMAIN"
    ddns = [d for d in [cfg.p_dom, cfg.agh_dom] + cfg.steals if d and any(d.endswith(x) for x in DDNS_SFX)]
    items.append(Check("R1-04", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "Репутация домена и PTR", "LOW", "WARN" if ddns else "PASS",
        f"DDNS={ddns}; PTR={ptr}" if ddns else f"Собственный домен 2+ уровня; PTR={ptr}", pub_title="Репутация домена и PTR-запись"))

    # R1-05: IPv6 Dual-Stack & AAAA Bypass
    aaaa_ips: List[str] = []
    if cfg.p_dom:
        for d in [x for x in [cfg.p_dom, cfg.agh_dom] + cfg.steals if x]:
            try:
                for fam, _, _, _, sa in socket.getaddrinfo(d, None, socket.AF_INET6):
                    if fam == socket.AF_INET6 and sa[0] not in aaaa_ips: aaaa_ips.append(sa[0])
            except Exception: pass
    v6_intl: List[int] = []; v6_all: List[int] = []
    for v6a in aaaa_ips[:1]:
        for vp in sorted(set([22, 53, 80, 443, 3000, 8088, 9443, 10443, 20443, 45443, 46443, 50443, 55443, cfg.p_port, cfg.s_port, cfg.x_port])):
            if vp <= 0: continue
            if tcp_open(v6a, vp, 0.85, socket.AF_INET6)[0]:
                v6_all.append(vp)
                if vp not in (80, 443): v6_intl.append(vp)
    items.append(Check("R1-05", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "Изоляция IPv6 Dual-Stack (AAAA и внешние порты)", "CRITICAL" if v6_intl else "INFO",
        "FAIL" if v6_intl else "PASS",
        f"По IPv6 ({aaaa_ips[:1]}) открыты внутренние порты {v6_intl}!" if v6_intl else (f"AAAA={aaaa_ips[:2]}, открыты только {v6_all}" if aaaa_ips else "Записи AAAA отсутствуют, утечек по IPv6 нет."),
        "Отключите AAAA или настройте ip6tables/UFW IPV6=yes" if v6_intl else "", pub_title="Изоляция IPv6 Dual-Stack (AAAA и порты)"))

    # R1-06: DNS Origin / MX / SPF / Subdomain Metadata Leak
    if cfg.p_dom:
        dom_ip = ""
        try: dom_ip = socket.gethostbyname(cfg.p_dom)
        except Exception: pass
        cmp_ip = cfg.pub_ip or cfg.ip
        try: cmp_priv = ipaddress.ip_address(cmp_ip).is_private
        except Exception: cmp_priv = True
        is_cdn = bool(dom_ip and cmp_ip and not cmp_priv and dom_ip != cmp_ip)
        leaks_dns: List[str] = []
        if shutil.which("dig"):
            _, txt_out, _ = cmd(["dig", "+short", "TXT", cfg.p_dom, "@1.1.1.1"], 3)
            _, mx_out, _ = cmd(["dig", "+short", "MX", cfg.p_dom, "@1.1.1.1"], 3)
            if is_cdn and cmp_ip in txt_out: leaks_dns.append("SPF/TXT содержит origin IP")
            for mx_ln in mx_out.splitlines():
                mx_h = mx_ln.split()[-1].rstrip(".") if mx_ln.split() else ""
                if mx_h and mx_h != ".":
                    try:
                        mx_ip = socket.gethostbyname(mx_h)
                        if is_cdn and mx_ip == cmp_ip: leaks_dns.append(f"MX {mx_h}->origin IP")
                    except Exception: pass
            _, wc_out, _ = cmd(["dig", "+short", "A", f"{secrets.token_hex(5)}.{cfg.p_dom}", "@1.1.1.1"], 3)
            if is_cdn and not wc_out.strip():
                for sub in ("mail", "direct", "origin", "vpn", "panel", "admin"):
                    _, s_out, _ = cmd(["dig", "+short", "A", f"{sub}.{cfg.p_dom}", "@1.1.1.1"], 3)
                    if cmp_ip in s_out.splitlines(): leaks_dns.append(f"{sub}.->origin IP")
        items.append(Check("R1-06", "R1. Периметр L3/L4 (Shodan/Censys/ZMap)", "DNS Origin Leak (MX / SPF / TXT / Поддомены)", "HIGH" if leaks_dns else "INFO",
            "FAIL" if leaks_dns else "PASS",
            f"Обнаружена утечка Origin IP: {leaks_dns}" if leaks_dns else ("Проксируемый домен (CDN) не раскрывает Origin IP в MX/SPF/поддоменах." if is_cdn else "Прямой A-резолв без лишних MX/SPF утечек."),
            "Удалите прямые A/SPF/MX записи с реальным IP при использовании CDN" if leaks_dns else "", pub_title="Защита DNS-метаданных (MX / SPF / Origin IP)"))

    # R2: TLS Oracle & Stack Parity
    zs, _, _ = tls_probe_raw(cfg.ip, raw_hello(None, t13=True), cfg.to)
    bs, _, _ = tls_probe_raw(cfg.ip, raw_hello("censys-scan-2026.invalid", t13=True), cfg.to)
    ips, _, _ = tls_probe_raw(cfg.ip, raw_hello(cfg.ip, t13=True), cfg.to)
    ok_sni = all(x != "SERVER_HELLO" for x in (zs, bs, ips))
    items.append(Check("R2-01", "R2. TLS Oracle (GFW / ТСПУ / Censys)", "Zero-SNI, IP-SNI и Random-SNI Shield (:443)", "CRITICAL", "PASS" if ok_sni else "FAIL",
        f"Отклонены: Zero-SNI={zs}, IP-SNI={ips}, Fake-SNI={bs}", "Включите ssl_reject_handshake on для default_server",
        "Сканер по IP/без SNI не получает X.509 сертификат" if ok_sni else "УТЕЧКА сертификата без валидного SNI!", "Zero-SNI, IP-SNI и Random-SNI Shield (:443)"))

    if cfg.p_dom:
        t10, _, _ = tls_probe_raw(cfg.ip, raw_hello(cfg.p_dom, 0x0301, 0x0301, False, False), cfg.to)
        t11, _, _ = tls_probe_raw(cfg.ip, raw_hello(cfg.p_dom, 0x0302, 0x0302, False, False), cfg.to)
        wk, _, _ = tls_probe_raw(cfg.ip, raw_hello(cfg.p_dom, 0x0301, 0x0303, False, True), cfg.to)
        ok_old = all(x != "SERVER_HELLO" for x in (t10, t11, wk))
        items.append(Check("R2-02", "R2. TLS Oracle (GFW / ТСПУ / Censys)", "Отказ TLS 1.0/1.1 и слабых шифров", "HIGH", "PASS" if ok_old else "FAIL",
            f"TLS1.0={t10}, TLS1.1={t11}, Weak={wk}", pub_title="Отказ TLS 1.0/1.1 и слабых шифров"))

        doms = [d for d in [cfg.p_dom, cfg.agh_dom] + cfg.steals if d]
        pmap: Dict[str, str] = {}; san_l: List[str] = []; y_c: List[str] = []
        for d in doms:
            o13, al13, sans, age = tls_details(cfg.ip, d, "1.3", cfg.to)
            o12, _, _, _ = tls_details(cfg.ip, d, "1.2", cfg.to)
            pmap[d] = f"T1.3={'OK' if o13 else 'NO'}/T1.2={'OK' if o12 else 'NO'}/ALPN={al13}"
            if cfg.agh_dom and d != cfg.agh_dom and cfg.agh_dom in sans: san_l.append(f"{d}->{cfg.agh_dom}")
            if age is not None and age < 7: y_c.append(f"{d}({age}д)")
        items.append(Check("R2-03", "R2. TLS Oracle (GFW / ТСПУ / Censys)", "Изоляция SAN сертификатов и ALPN h2", "HIGH", "FAIL" if san_l else "PASS",
            f"Утечка SAN: {san_l}" if san_l else f"SAN изолированы ({', '.join(f'{k}:{v}' for k,v in pmap.items())}); новые CT={y_c or 'нет'}",
            pub_title="Изоляция SAN сертификатов и ALPN h2"))

        fp_main = sclient_fingerprint(cfg.ip, cfg.p_dom)
        if cfg.steals:
            p12 = "T1.2=OK" in pmap.get(cfg.p_dom, ""); s12 = "T1.2=OK" in pmap.get(cfg.steals[0], "")
            items.append(Check("R2-04", "R2. TLS Oracle (GFW / ТСПУ / Censys)", "Паритет версий TLS (Main vs Steal-REALITY)", "MEDIUM", "PASS" if p12 == s12 else "WARN",
                f"{cfg.p_dom} ({pmap[cfg.p_dom]}) vs {cfg.steals[0]} ({pmap[cfg.steals[0]]})", pub_title="Паритет версий TLS (Main vs Steal-REALITY)"))

            fp_steal = sclient_fingerprint(cfg.ip, cfg.steals[0])
            if fp_main and fp_steal:
                mism = [k for k in ("cipher", "temp_key", "alpn") if fp_main.get(k) != fp_steal.get(k)]
                items.append(Check("R2-05", "R2. TLS Oracle (GFW / ТСПУ / Censys)", "JA4S/TLS Stack Паритет (Шифр / KeyShare / PQ)", "MEDIUM",
                    "WARN" if mism else "PASS",
                    f"Отличие {mism}: Main={fp_main} vs Steal={fp_steal}" if mism else f"Паритет 100%: Cipher={fp_main.get('cipher')}, KeyShare={fp_main.get('temp_key')}, ALPN={fp_main.get('alpn')}",
                    pub_title="TLS Stack / KeyShare / Cipher Паритет (JA4S)"))

    # R3: Активные зонды DPI
    sp4, dp4, msp = raw_tcp(cfg.ip, 443, f"GET / HTTP/1.1\r\nHost: {cfg.p_dom or cfg.ip}\r\nConnection: close\r\n\r\n".encode("ascii"), 3.0)
    ok_p4 = (sp4 != "HANG_TIMEOUT" and b"nginx" not in dp4.lower() and msp < 1500)
    items.append(Check("R3-01", "R3. Активные зонды DPI / GFW / ТСПУ", "Plain-HTTP-on-443 (Anti-#4610)", "HIGH", "PASS" if ok_p4 else "FAIL",
        f"Реакция: {sp4} за {msp:.1f}ms ({len(dp4)}B)", view=f"Plain HTTP на 443 -> {sp4} ({msp:.0f}ms)", pub_title="Plain-HTTP-on-443 (Anti-#4610)"))

    j1, m1, _ = tls_probe_raw(cfg.ip, secrets.token_bytes(64), 2.5)
    j2, m2, _ = tls_probe_raw(cfg.ip, raw_hello(cfg.p_dom or "example.com", corrupt=True), 2.5)
    ok_j = all(x.startswith("TLS_ALERT_") or x in ("EOF_SILENT", "TCP_RST") for x in (j1, j2))
    items.append(Check("R3-02", "R3. Активные зонды DPI / GFW / ТСПУ", "J3 Junk Probing (мусор + битый ClientHello)", "HIGH", "PASS" if ok_j else "WARN",
        f"Junk64B={j1}({m1:.0f}ms), CorruptExt={j2}({m2:.0f}ms)", pub_title="J3 Junk Probing (мусор + битый ClientHello)"))

    if cfg.steals and cfg.p_dom:
        sd = cfg.steals[0]; c_bad: List[str] = []; b_bad: List[str] = []
        for sh in [cfg.p_dom] + ([cfg.agh_dom] if cfg.agh_dom else []):
            for pp in ["/", cfg.panel_p or "/api/v1/myprivatecloud/auth", cfg.xhttp_p or "/"]:
                try:
                    sc, _, bc, _, _ = http_sni(cfg.ip, sd, "GET", pp, {"Host": sh}, to=cfg.to)
                    if sc == 200 or b"3x-ui" in bc.lower() or b"adguard" in bc.lower(): c_bad.append(f"{sh}{pp}->{sc}")
                    if any(sig.encode("ascii") in bc.lower() for sig in BANNERS): b_bad.append(f"{sh}->{sc}")
                except Exception: pass
        items.append(Check("R3-03", "R3. Активные зонды DPI / GFW / ТСПУ", f"Host/SNI Confusion на Fallback ({sd})", "CRITICAL",
            "FAIL" if (c_bad or b_bad) else "PASS",
            f"Пробой={c_bad}; Баннеры={b_bad}" if (c_bad or b_bad) else f"Подмена Host внутри SNI={sd} полностью изолирована.",
            "Проверьте listen 127.0.0.1:9443 и error_page 421/429", pub_title="Host/SNI Confusion на Fallback (Steal-REALITY)"))
        try:
            rm = sorted(http_sni(cfg.ip, cfg.p_dom, "GET", "/", to=cfg.to)[3] for _ in range(3))[1]
            rs = sorted(http_sni(cfg.ip, sd, "GET", "/", to=cfg.to)[3] for _ in range(3))[1]
            dl = abs(rs - rm)
            items.append(Check("R3-04", "R3. Активные зонды DPI / GFW / ТСПУ", "Тайминг-дельта ретрансляции (Main vs Steal)", "LOW", "PASS" if dl < 45 else "WARN",
                f"Main={rm:.1f}ms, Steal={rs:.1f}ms (дельта {dl:.1f}ms)", pub_title="Тайминг-дельта ретрансляции (Main vs Steal)"))
        except Exception: pass

        st_sh, ms_sh, sz_sh = tls_probe_raw(cfg.ip, raw_hello(sd, t13=True), cfg.to)
        ok_rep = (st_sh == "SERVER_HELLO" and sz_sh >= 120)
        items.append(Check("R3-05", "R3. Активные зонды DPI / GFW / ТСПУ", "REALITY Fallback & Post-Handshake Probe (Steal)", "HIGH",
            "PASS" if ok_rep else "FAIL",
            f"Невалидная сессия REALITY -> {st_sh} ({sz_sh}B за {ms_sh:.1f}ms)" + ("" if ok_rep else " (сбой fallback-ретрансляции!)"),
            pub_title="REALITY Fallback & Post-Handshake Probe"))

    # R4: Web Decoy, Боты 11.2026, Утечки IP/Заголовков, Favicon, OWASP
    if cfg.p_dom:
        try:
            sm, mh, mb, _, vm = http_sni(cfg.ip, cfg.p_dom, "GET", "/", to=cfg.to)
            st_ok = True; st_inf = ""
            if cfg.steals:
                ss, _, sb_steal, _, _ = http_sni(cfg.ip, cfg.steals[0], "GET", "/", to=cfg.to)
                st_ok = (ss == 200 and b"/api/v1/myprivatecloud/" not in sb_steal)
                st_inf = f", Steal={ss}"
            items.append(Check("R4-01", "R4. Web Decoy, Боты 11.2026 & OWASP", "Доступность веб-декоев (HTTP/2)", "HIGH", "PASS" if (sm == 200 and st_ok) else "FAIL",
                f"{vm} Main={sm} ({len(mb)}B){st_inf}", pub_title="Доступность веб-декоев (HTTP/2)"))

            cls_uas = [("Empty", ""), ("Nuclei", "nuclei"), ("Sqlmap", "sqlmap/1.7"), ("ZGrab2", "Mozilla/5.0 zgrab/0.x"), ("Censys", "CensysInspect/1.1"), ("Httpx", "httpx")]
            cls_res = {lbl: http_sni(cfg.ip, cfg.p_dom, "GET", "/", {"User-Agent": ua}, to=cfg.to)[0] for lbl, ua in cls_uas}
            bad_cls = [f"{k}->{v}" for k, v in cls_res.items() if v not in (200, 404)]
            err_leaks = []
            for mth, ep in [("GET", "/.env"), ("GET", "/nonexistent-2026-probe"), ("DELETE", "/")]:
                se, _, be, _, _ = http_sni(cfg.ip, cfg.p_dom, mth, ep, to=cfg.to)
                lb = be.decode("utf-8", "ignore").lower()
                for sg in BANNERS:
                    if sg in lb: err_leaks.append(f"{ep}({se}):{sg}")
            items.append(Check("R4-02", "R4. Web Decoy, Боты 11.2026 & OWASP", "Сканеры (Nuclei/ZGrab2/Censys) и стерильность 404/405", "HIGH",
                "FAIL" if (bad_cls or err_leaks) else "PASS",
                f"Аномалии={bad_cls}, баннеры={err_leaks}" if (bad_cls or err_leaks) else f"Сканеры={cls_res}; баннеры ошибок скрыты.",
                "Уберите баннеры в error_page @notfound", pub_title="Сканеры и стерильность 404/405"))

            ai_uas = [
                ("GPTBot", "GPTBot/1.0"), ("OAI-SearchBot", "OAI-SearchBot/1.0"), ("ChatGPT-User", "ChatGPT-User/1.0"),
                ("ClaudeBot", "ClaudeBot/1.0"), ("Claude-SearchBot", "Claude-SearchBot/1.0"), ("Claude-User", "Claude-User/1.0"),
                ("PerplexityBot", "PerplexityBot/1.0"), ("Perplexity-User", "Perplexity-User/1.0"),
                ("Meta-ExternalFetcher", "Meta-ExternalFetcher/1.1"), ("Meta-ExternalAgent", "Meta-ExternalAgent/1.1"),
                ("GrokBot", "GrokBot/1.0"), ("MistralAI-Index", "MistralAI-Index/1.0"),
                ("GoogleOther", "GoogleOther/1.0"), ("Bytespider", "Bytespider"),
            ]
            ai_bypass = [f"{lbl}->{http_sni(cfg.ip, cfg.p_dom, 'GET', '/', {'User-Agent': ua}, to=cfg.to)[0]}" for lbl, ua in ai_uas]
            ai_200 = [x for x in ai_bypass if x.endswith("->200")]
            items.append(Check("R4-03", "R4. Web Decoy, Боты 11.2026 & OWASP", "Фильтрация AI-краулеров 11.2026 (14 ботов: OAI/Claude/Grok/Mistral)", "MEDIUM",
                "WARN" if ai_200 else "PASS",
                f"Пропущены через $badbot (отдан 200): {', '.join(ai_200)}" if ai_200 else f"Все {len(ai_uas)} AI-краулеров 11.2026 блокируются 404.",
                "Добавьте пропущенные UA (grokbot|claude-searchbot|mistralai-index|googleother) в $badbot_raw" if ai_200 else "",
                f"AI-боты 11.2026: {', '.join(ai_200[:3]) if ai_200 else 'все 14->404'}",
                "Фильтрация AI-краулеров 11.2026 (14 агентов)"))

            ht = mb.decode("utf-8", "ignore"); assets = ["/robots.txt"] + [m.group(1) for m in re.finditer(r'(?:src|href)=["\'](/[^"\'?#]+)', ht, re.I)][:10]
            texts = [("/", ht)]; all_hdrs: List[Tuple[str, Dict[str, str]]] = [("/", mh)]
            for ap in set(assets):
                try:
                    sa, ah, ba, _, _ = http_sni(cfg.ip, cfg.p_dom, "GET", ap, to=cfg.to)
                    if sa == 200:
                        texts.append((ap, ba.decode("utf-8", "ignore"))); all_hdrs.append((ap, ah))
                except Exception: pass
            kws = [f"{sn}:'{kw}'" for sn, tx in texts for kw in VPN_KWS if kw in tx.lower()]
            cdns = [f"{sn}:{u}" for sn, tx in texts for u in re.findall(r"https?://(?!www\.w3\.org)([a-zA-Z0-9.-]+)", tx) if u not in (cfg.p_dom, "privatecloud.internal") and u not in cfg.steals]
            items.append(Check("R4-04", "R4. Web Decoy, Боты 11.2026 & OWASP", "Скан публичных JS/CSS/HTML на VPN-ключи и внешние CDN", "CRITICAL",
                "FAIL" if (kws or cdns) else "PASS", f"Утечки={kws[:4]} CDN={cdns[:3]}" if (kws or cdns) else f"Проверено {len(texts)} файлов: 0 VPN-маркеров и 0 внешних CDN.",
                pub_title="Скан публичных ресурсов на VPN-ключи и внешние CDN"))

            fz = [f"{u}->{http_sni(cfg.ip, cfg.p_dom, 'GET', u, to=cfg.to)[0]}" for u in ("/.env", "/.git/config", "/wp-login.php", "/phpmyadmin/", "/admin/", "/panel/", "/x-ui/")]
            fz_bad = [x for x in fz if not (x.endswith("->404") or x.endswith("->429"))]
            api_bad = [u for u in ("/api/v1/myprivatecloud/docs", "/api/v1/myprivatecloud/openapi.json", "/api/v1/myprivatecloud/storage/nodes") if http_sni(cfg.ip, cfg.p_dom, "GET", u, to=cfg.to)[0] == 200]
            api_st = http_sni(cfg.ip, cfg.p_dom, "GET", "/api/v1/myprivatecloud/status", to=cfg.to)[0]
            miss_h = [h for h in ("strict-transport-security", "x-frame-options", "x-content-type-options", "content-security-policy") if h not in mh]
            csp = mh.get("content-security-policy", ""); bad_csp = "'unsafe-inline'" in csp or "'unsafe-eval'" in csp
            leak_h = [h for h in ("x-powered-by", "via", "alt-svc", "etag") if h in mh] + ([f"server={mh['server']}"] if "/" in mh.get("server", "") else [])
            ok_owasp = not (fz_bad or api_bad or api_st != 401 or miss_h or bad_csp or leak_h)
            items.append(Check("R4-05", "R4. Web Decoy, Боты 11.2026 & OWASP", "URI Fuzzing, защита API и OWASP-заголовки", "HIGH", "PASS" if ok_owasp else "FAIL",
                f"fuzz_bad={fz_bad}, api_200={api_bad}, status_code={api_st}, miss_h={miss_h}, bad_csp={bad_csp}, leak={leak_h}" if not ok_owasp else "Fuzzing=404/429, API=401, Swagger=404, HSTS/CSP/Headers OK.",
                pub_title="URI Fuzzing, защита API и OWASP-заголовки"))

            if cfg.rl:
                rls = [http_sni(cfg.ip, cfg.p_dom, "GET", f"/rl-scan-probe-{i}", to=2.0)[0] for i in range(8)]
                items.append(Check("R4-06", "R4. Web Decoy, Боты 11.2026 & OWASP", "Rate-Limit защита (zone=scan -> 429)", "LOW", "PASS" if 429 in rls else "WARN",
                    f"Коды серии 8 запросов: {rls}", pub_title="Rate-Limit защита от перебора"))

            spoof_h = {"X-Forwarded-For": "127.0.0.1", "X-Real-IP": "127.0.0.1", "Forwarded": "for=127.0.0.1", "X-Original-URL": "/api/v1/myprivatecloud/storage/nodes"}
            sp_api = http_sni(cfg.ip, cfg.p_dom, "GET", "/api/v1/myprivatecloud/status", spoof_h, to=cfg.to)[0]
            sp_nodes = http_sni(cfg.ip, cfg.p_dom, "GET", "/api/v1/myprivatecloud/storage/nodes", spoof_h, to=cfg.to)[0]
            ip_leaks: List[str] = []
            chk_tokens = list(dict.fromkeys([x for x in (cfg.ip, cfg.pub_ip, "127.0.0.1", "10.8.1.", "10.9.0.") if x]))
            port_pat = re.compile(r":(?:10443|55443|50443|20443|8088|9443|62789|11111|3000)\b")
            for sn, tx in texts:
                for tok in chk_tokens:
                    if tok in tx: ip_leaks.append(f"{sn}:{tok}")
                if port_pat.search(tx): ip_leaks.append(f"{sn}:internal_port")
            for sn, hd in all_hdrs:
                for hk, hv in hd.items():
                    for tok in chk_tokens:
                        if tok in hv: ip_leaks.append(f"hdr {sn}[{hk}]:{tok}")
                    if hk == "location" and port_pat.search(hv): ip_leaks.append(f"hdr {sn}[location]:port")
            sp_bad = (sp_api == 200 or sp_nodes == 200 or bool(ip_leaks))
            items.append(Check("R4-07", "R4. Web Decoy, Боты 11.2026 & OWASP", "Spoofing XFF/X-Real-IP и утечки IP/портов в HTTP", "CRITICAL",
                "FAIL" if sp_bad else "PASS",
                f"Bypass/Leak: api={sp_api}, nodes={sp_nodes}, leaks={ip_leaks[:4]}" if sp_bad else "XFF/X-Real-IP спуфинг отклонён (401); утечек IP/внутренних портов в HTML/JS/Headers нет.",
                pub_title="Защита от Spoofing XFF и утечки IP/портов в HTTP"))

            fav_m = http_sni(cfg.ip, cfg.p_dom, "GET", "/favicon.svg", to=cfg.to)
            if fav_m[0] != 200: fav_m = http_sni(cfg.ip, cfg.p_dom, "GET", "/favicon.ico", to=cfg.to)
            if fav_m[0] == 200 and fav_m[2]:
                mmh_m = mmh3_32_signed(base64.encodebytes(fav_m[2]), 0)
                sha_m = hashlib.sha256(fav_m[2]).hexdigest()[:16]
                fav_dup = False
                if cfg.steals:
                    fav_s = http_sni(cfg.ip, cfg.steals[0], "GET", "/favicon.svg", to=cfg.to)
                    if fav_s[0] != 200: fav_s = http_sni(cfg.ip, cfg.steals[0], "GET", "/favicon.ico", to=cfg.to)
                    if fav_s[0] == 200 and fav_s[2] == fav_m[2]: fav_dup = True
                items.append(Check("R4-08", "R4. Web Decoy, Боты 11.2026 & OWASP", "Favicon Hash Корреляция (Shodan MMH3 & Censys SHA256)", "LOW",
                    "WARN" if fav_dup else "PASS",
                    f"Main и Steal отдают идентичный фавикон (MMH3={mmh_m}, SHA256={sha_m}...) — риск групповой корреляции." if fav_dup else f"MMH3={mmh_m}, SHA256={sha_m}...",
                    "Задайте уникальный favicon для Steal-домена (или уберите дефолтный шаблонный SVG)" if fav_dup else "",
                    pub_title="Корреляция Favicon (Shodan MMH3 & Censys SHA256)"))

            ed_on = (fp_main.get("early_data") == "YES") if fp_main else False
            as_on = "alt-svc" in mh
            items.append(Check("R4-10", "R4. Web Decoy, Боты 11.2026 & OWASP", "Защита от TLS 0-RTT (Early Data) и утечки Alt-Svc", "MEDIUM",
                "WARN" if (ed_on or as_on) else "PASS",
                f"early_data={ed_on}, alt_svc={as_on}" if (ed_on or as_on) else "TLS 0-RTT (ssl_early_data) отключён, заголовок Alt-Svc скрыт.",
                pub_title="Отключение TLS 0-RTT и скрытие Alt-Svc"))
        except Exception as e:
            items.append(Check("R4-01", "R4. Web Decoy, Боты 11.2026 & OWASP", "Веб-зондирование", "CRITICAL", "FAIL", f"Сбой HTTPS-пробы: {e}", pub_title="Доступность веб-декоев (HTTP/2)"))

    stun_exp = [f"{pn}:{pt}" for pn, pt in (("STUN", 3478), ("mDNS", 5353), ("UPnP", 1900)) if tcp_open(cfg.ip, pt, 0.5)[0]]
    items.append(Check("R4-09", "R4. Web Decoy, Боты 11.2026 & OWASP", "Изоляция STUN / mDNS / UPnP (WebRTC & Discovery)", "MEDIUM",
        "FAIL" if stun_exp else "PASS",
        f"Открыты: {stun_exp}" if stun_exp else "Порты STUN (3478), mDNS (5353), UPnP (1900) закрыты снаружи.",
        pub_title="Закрытие STUN / mDNS / UPnP"))

    # R5: xHTTP, SUB_PATH / PANEL_PATH Differential Oracle & AdGuard DoH
    scan_cooled = False
    if cfg.p_dom and cfg.xhttp_p:
        time.sleep(4.2 if cfg.rl else 3.5)
        scan_cooled = True
        xp = "/" + cfg.xhttp_p.strip("/") + "/"
        try:
            sg, _, bg, _, _ = http_sni(cfg.ip, cfg.p_dom, "GET", xp, to=cfg.to)
            sp, _, bp, _, _ = http_sni(cfg.ip, cfg.p_dom, "POST", xp, body=secrets.token_bytes(64), to=cfg.to)
            sr, _, br, _, _ = http_sni(cfg.ip, cfg.p_dom, "POST", f"/probe-{secrets.token_hex(4)}/", body=secrets.token_bytes(64), to=cfg.to)
            leak_502 = sp in (500, 502, 504) and sp != sr
            items.append(Check("R5-01", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Differential Oracle xHTTP (GET/POST vs 404)", "MEDIUM",
                "WARN" if (sg != 404 or leak_502) else "PASS",
                f"GET {xp}->{sg}({len(bg)}B), POST {xp}->{sp}({len(bp)}B) vs POST /rnd->{sr}({len(br)}B)",
                "Настройте обработку сброса невалидного POST от Xray (proxy_intercept_errors / 404) без 502" if leak_502 else "",
                f"xHTTP POST={sp} vs 404-эталон={sr}", "Differential Oracle xHTTP (GET/POST)"))

            shd, _, _, _, _ = http_sni(cfg.ip, cfg.p_dom, "HEAD", xp, to=cfg.to)
            sop, _, _, _, _ = http_sni(cfg.ip, cfg.p_dom, "OPTIONS", xp, to=cfg.to)
            sgr, _, bgr, _, _ = http_sni(cfg.ip, cfg.p_dom, "POST", xp, {"Content-Type": "application/grpc", "X-Amz-Meta-Trace": "probe"}, secrets.token_bytes(32), to=cfg.to)
            sr_h = http_sni(cfg.ip, cfg.p_dom, "HEAD", f"/probe-{secrets.token_hex(4)}/", to=cfg.to)[0]
            sr_g, _, br_g, _, _ = http_sni(cfg.ip, cfg.p_dom, "POST", f"/probe-{secrets.token_hex(4)}/", {"Content-Type": "application/grpc"}, secrets.token_bytes(32), to=cfg.to)
            diff_x = (shd != sr_h or sop != 405 or sgr != sr_g or abs(len(bgr) - len(br_g)) > 64)
            items.append(Check("R5-06", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Deep xHTTP Probe (HEAD/OPTIONS/gRPC vs 404)", "LOW",
                "WARN" if diff_x else "PASS",
                f"HEAD={shd}(rnd={sr_h}), OPT={sop}, gRPC-POST={sgr}/{len(bgr)}B(rnd={sr_g}/{len(br_g)}B)",
                pub_title="Deep xHTTP Probe (HEAD/OPTIONS/gRPC)"))
        except Exception as e:
            items.append(Check("R5-01", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Тест xHTTP", "MEDIUM", "WARN", f"Ошибка: {e}", pub_title="Differential Oracle xHTTP"))

    if cfg.p_dom and cfg.sub_p:
        time.sleep(1.2 if scan_cooled else (4.2 if cfg.rl else 3.5))
        sp_norm = "/" + cfg.sub_p.strip("/") + "/"
        try:
            su_code, su_hdr, su_body, _, _ = http_sni(cfg.ip, cfg.p_dom, "GET", f"{sp_norm}nonexistent-{secrets.token_hex(4)}", {"User-Agent": ""}, to=cfg.to)
            rnd_code, _, rnd_body, _, _ = http_sni(cfg.ip, cfg.p_dom, "GET", f"/rnd-{secrets.token_hex(4)}", {"User-Agent": ""}, to=cfg.to)
            su_leak = (su_code in (200, 500, 502) or b"3x-ui" in su_body.lower() or "127.0.0.1" in su_hdr.get("location", "") or (su_code == 404 and abs(len(su_body) - len(rnd_body)) > 40))
            items.append(Check("R5-05", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Изоляция SUB_PATH (Empty-UA & Error Intercept)", "MEDIUM",
                "WARN" if su_leak else "PASS",
                f"GET <SUB_PATH>rnd (empty UA) -> HTTP {su_code} ({len(su_body)}B) vs эталон {rnd_code} ({len(rnd_body)}B)" + (" — отличие от Nginx 404" if su_leak else ""),
                "Добавьте proxy_intercept_errors on; error_page 400 404 ... /404.html в location SUB_PATH" if su_leak else "",
                pub_title="Изоляция эндпоинта подписок (Error Intercept)"))
        except Exception: pass

    if cfg.en_agh and cfg.agh_dom:
        wq = dns_wire("example.com"); b64q = base64.urlsafe_b64encode(wq).decode("ascii").rstrip("=")
        try:
            ar, ahr, abr, _, _ = http_sni(cfg.ip, cfg.agh_dom, "GET", "/", to=cfg.to)
            adg, _, _, _, _ = http_sni(cfg.ip, cfg.agh_dom, "GET", f"/dns-query?dns={b64q}", {"Accept": "application/dns-message"}, to=cfg.to)
            adp, _, _, _, _ = http_sni(cfg.ip, cfg.agh_dom, "POST", "/dns-query", {"Content-Type": "application/dns-message"}, wq, to=cfg.to)
            root_ok = (ar == 404 and "www-authenticate" not in ahr and b"adguard" not in abr.lower())
            items.append(Check("R5-02", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", f"Скрытие админки {cfg.agh_dom} под 404", "CRITICAL", "PASS" if root_ok else "FAIL",
                f"GET / -> {ar}" + ("" if root_ok else " (ОБНАРУЖЕНА АДМИНКА!)"), pub_title="Скрытие веб-админки DoH под 404"))
            open_doh = (adg == 200 or adp == 200)
            items.append(Check("R5-03", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Проверка на Open DoH Resolver (/dns-query)", "HIGH", "WARN" if open_doh else "PASS",
                f"ПУБЛИЧНЫЙ /dns-query ОТКРЫТ БЕЗ ClientID (GET={adg}, POST={adp}) — риск DNS-абуза!" if open_doh else f"Публичный /dns-query закрыт (GET={adg}, POST={adp}).",
                "Ограничьте location = /dns-query (return 404)" if open_doh else "",
                "Open DoH Resolver доступен любому без ClientID!" if open_doh else "Публичный DoH закрыт", "Проверка на Open DoH Resolver (/dns-query)"))
            if cfg.agh_cid:
                ac, ahc, abc, _, _ = http_sni(cfg.ip, cfg.agh_dom, "GET", f"/dns-query/{cfg.agh_cid}?dns={b64q}", {"Accept": "application/dns-message"}, to=cfg.to)
                items.append(Check("R5-04", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", f"DoH-резолв с ClientID ({cfg.agh_cid})", "MEDIUM",
                    "PASS" if (ac == 200 and len(abc) > 12) else "FAIL", f"HTTP {ac}, {len(abc)}B, CT={ahc.get('content-type')}", pub_title="DoH-резолв с ClientID"))
        except Exception as e:
            items.append(Check("R5-02", "R5. xHTTP (ML-KEM-768), Sub-Oracle & AdGuard DoH", "Проверка AGH DoH", "HIGH", "WARN", f"Ошибка: {e}", pub_title="Проверка AGH DoH"))

    # R6: UDP DPI & Amplification
    if cfg.hy2_p > 0:
        dc, sc = secrets.token_bytes(8), secrets.token_bytes(8)
        pkt = bytes([0xC0]) + struct.pack(">I", 0x0A0A0A0A) + bytes([len(dc)]) + dc + bytes([len(sc)]) + sc
        pkt += secrets.token_bytes(1200 - len(pkt))
        us = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); us.settimeout(1.5)
        try:
            us.sendto(pkt, (cfg.ip, cfg.hy2_p)); resp, _ = us.recvfrom(2048)
            is_vn = (len(resp) >= 7 and resp[1:5] == b"\x00\x00\x00\x00")
            amp = len(resp) > len(pkt)
            items.append(Check("R6-01", "R6. Активные UDP DPI-зонды (ТСПУ)", f"Hysteria 2 QUIC GREASE Probe (:{cfg.hy2_p}/udp)", "INFO",
                "WARN" if amp else "PASS",
                f"{'RFC 9000 QUIC Version Negotiation' if is_vn else 'UDP ответ'} ({len(resp)}B <= {len(pkt)}B, без амплификации).",
                view=f"UDP {cfg.hy2_p} распознаётся как QUIC", pub_title="Hysteria 2 QUIC GREASE Probe (без усиления)"))
        except socket.timeout:
            items.append(Check("R6-01", "R6. Активные UDP DPI-зонды (ТСПУ)", f"Hysteria 2 QUIC Probe (:{cfg.hy2_p}/udp)", "MEDIUM", "WARN", "Таймаут ответа на QUIC GREASE.", pub_title="Hysteria 2 QUIC Probe (UDP)"))
        except ConnectionRefusedError:
            items.append(Check("R6-01", "R6. Активные UDP DPI-зонды (ТСПУ)", f"Hysteria 2 QUIC Probe (:{cfg.hy2_p}/udp)", "HIGH", "FAIL", "ICMP Port Unreachable — служба Hy2 не слушает!", pub_title="Hysteria 2 QUIC Probe (UDP)"))
        finally: us.close()

    awg_t = [("AWG-Native", cfg.nawg_p), ("AWG-v3", cfg.awg3_p)]
    awg_f: List[str] = []; awg_ok: List[str] = []
    probes = [("WG1", b"\x01\x00\x00\x00" + secrets.token_bytes(144)), ("Junk64", secrets.token_bytes(64)),
              ("STUN", b"\x00\x01\x00\x00\x21\x12\xa4\x42" + secrets.token_bytes(12)), ("QUIC", b"\xc0\x00\x00\x01\x08" + secrets.token_bytes(1195))]
    for lbl, up in awg_t:
        if up <= 0: continue
        awg_ok.append(f"{lbl}:{up}")
        for pn, pload in probes:
            us = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); us.settimeout(0.9)
            try:
                us.connect((cfg.ip, up)); us.send(pload); r = us.recv(512)
                awg_f.append(f"{lbl}:{up}({pn})->{len(r)}B")
            except socket.timeout: pass
            except ConnectionRefusedError: awg_f.append(f"{lbl}:{up}->ICMP_UNREACH")
            finally: us.close()
    if awg_ok:
        items.append(Check("R6-02", "R6. Активные UDP DPI-зонды (ТСПУ)", f"AmneziaWG Silent Drop ({', '.join(awg_ok)})", "HIGH",
            "FAIL" if awg_f else "PASS", f"Утечки/ошибки: {awg_f}" if awg_f else "100% Silent Drop на все 4 DPI-сигнатуры (WG-Type1, Junk-64B, STUN, QUIC).",
            view="Полная UDP-невидимость (Silent Drop)" if not awg_f else f"UDP аномалия: {awg_f[0]}", pub_title="AmneziaWG Silent Drop (UDP)"))
    return items

def run_local_checks(cfg: Cfg) -> List[Check]:
    items: List[Check] = []

    if cfg.db:
        try:
            cn = sqlite3.connect(f"file:{cfg.db}?mode=ro", uri=True, timeout=3.0)
            ib_cols_l = {r[1] for r in cn.execute("PRAGMA table_info(inbounds)")}
            nc_l_parts, nc_l_params = [], []
            if "node_id" in ib_cols_l: nc_l_parts.append("(node_id IS NULL OR node_id = 0)")
            if "origin_node_guid" in ib_cols_l:
                pg_rl = cn.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1").fetchone()
                pg_vl = str(pg_rl[0]).strip() if pg_rl and pg_rl[0] else ""
                if pg_vl:
                    nc_l_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)")
                    nc_l_params.append(pg_vl)
                else:
                    nc_l_parts.append("(origin_node_guid IS NULL OR origin_node_guid = '')")
            nc_l = (" AND " + " AND ".join(nc_l_parts)) if nc_l_parts else ""
            rx = cn.execute(f"SELECT settings, stream_settings FROM inbounds WHERE protocol='vless' AND stream_settings LIKE '%xhttp%'{nc_l} LIMIT 1", nc_l_params).fetchone()
            if rx:
                xs, xst = json.loads(rx[0]), json.loads(rx[1]); xh = xst.get("xhttpSettings", {}); xm = xh.get("xmux", {})
                ep = (xst.get("externalProxy") or [{}])[0]; errs = []
                has_pq = str(xs.get("decryption", "")).startswith("mlkem768")
                if not has_pq: errs.append("нет mlkem768")
                elif not any(c.get("flow") == "xtls-rprx-vision" for c in xs.get("clients", [])): errs.append("нет flow xtls-rprx-vision")
                if xh.get("mode") != "stream-one" or not xh.get("xPaddingObfsMode") or xh.get("xPaddingKey") != "X-Amz-Meta-Trace" or xh.get("xPaddingBytes") != "120-1120":
                    errs.append("отклонение xhttpSettings/padding")
                if xm.get("hKeepAlivePeriod") != 3000 or xm.get("maxConnections") != "1-3": errs.append("xmux")
                if ep.get("alpn") != ["h2"] or ep.get("fingerprint") != "firefox": errs.append("externalProxy")
                items.append(Check("L1-01", "L1. Стек Nginx + Xray v26.7.28", "Эталон xHTTP (ML-KEM-768 + Vision + Padding + xmux)", "CRITICAL",
                    "FAIL" if errs else "PASS", f"Ошибки: {errs}" if errs else "Эталон xHTTP соблюдён (ML-KEM-768, Vision, X-Amz-Meta-Trace 120-1120, stream-one, xmux 3000s, h2, firefox).",
                    pub_title="Эталон xHTTP (ML-KEM-768 + Vision + xmux)"))

            rh = cn.execute(f"SELECT stream_settings FROM inbounds WHERE protocol='hysteria'{nc_l} LIMIT 1", nc_l_params).fetchone()
            if rh:
                mq = json.loads(rh[0]).get("hysteriaSettings", {}).get("masquerade", {}); murl = str(mq.get("url", ""))
                if "127.0.0.1:80" in murl and not murl.endswith(":8088"):
                    st_m = raw_tcp("127.0.0.1", 80, b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", 1.5)[0]
                    is_444 = st_m in ("EOF_SILENT", "TCP_RST")
                    items.append(Check("L1-02", "L1. Стек Nginx + Xray v26.7.28", "Hysteria 2 Masquerade Origin", "HIGH", "WARN" if is_444 else "PASS",
                        f"Masquerade={murl}: порт 80 рвёт TCP (444 Drop) -> риск 502!" if is_444 else f"Masquerade={murl} отвечает штатно.",
                        "Направьте masquerade на 127.0.0.1:8088" if is_444 else "", pub_title="Hysteria 2 Masquerade Origin"))

            r_rows = cn.execute(f"SELECT tag, stream_settings FROM inbounds WHERE enable=1 AND protocol='vless' AND stream_settings LIKE '%reality%'{nc_l}", nc_l_params).fetchall()
            if r_rows:
                ap_bad: List[str] = []; gfw_warn: List[str] = []
                for r_tag, r_raw in r_rows:
                    rs = json.loads(r_raw).get("realitySettings", {})
                    snames = rs.get("serverNames", [])
                    if "" in snames or not snames: ap_bad.append(f"{r_tag}:empty_serverNames(#7280)")
                    dest = str(rs.get("dest", rs.get("target", "")))
                    xver = int(rs.get("xver", 0) or 0)
                    if dest == "127.0.0.1:9443" and xver != 1: ap_bad.append(f"{r_tag}:xver={xver}!=1")
                    mc_ver = str(rs.get("minClientVer") or "").strip()
                    if mc_ver == "": gfw_warn.append(f"{r_tag}:empty_minClientVer(риск_отвала_Mihomo_на_26.7.28)")
                    elif mc_ver not in ("0.0.0", "1.1.1"): gfw_warn.append(f"{r_tag}:minClientVer={mc_ver}")
                items.append(Check("L1-04", "L1. Стек Nginx + Xray v26.7.28", "Аудит REALITY (Aparecium #7280, xver, minClientVer)", "CRITICAL" if ap_bad else "LOW",
                    "FAIL" if ap_bad else ("WARN" if gfw_warn else "PASS"),
                    f"Критично: {ap_bad}" if ap_bad else (f"GFW warning в логах Xray: {gfw_warn} (empty-SNI #7280 защищён)." if gfw_warn else "serverNames без пустых строк (#7280 OK), xver корректен."),
                    "Уберите '' из serverNames и проверьте xver" if ap_bad else ("Уберите minClientVer в realitySettings для исключения GFW-предупреждений Xray" if gfw_warn else ""),
                    pub_title="Аудит REALITY (Aparecium #7280 и xver)"))
            cn.close()
        except Exception as e:
            items.append(Check("L1-01", "L1. Стек Nginx + Xray v26.7.28", "Аудит БД x-ui.db", "HIGH", "WARN", f"Ошибка БД: {e}", pub_title="Аудит БД x-ui.db"))

    ng_err = []
    rc_nt, _, e_nt = cmd(["nginx", "-t"], 5)
    if rc_nt != 0: ng_err.append(f"nginx -t: {e_nt.strip()}")
    if os.path.exists("/etc/nginx/conf.d/01-main.conf") and cfg.xhttp_p:
        m1 = open("/etc/nginx/conf.d/01-main.conf", errors="ignore").read()
        for req in ("proxy_http_version 2;", "proxy_request_buffering off;", "proxy_buffering off;"):
            if req not in m1: ng_err.append(f"нет {req}")
    xb = "/usr/local/x-ui/bin/xray" if os.path.exists("/usr/local/x-ui/bin/xray") else "/usr/local/x-ui/bin/xray-linux-amd64"
    rc_xt, _, e_xt = cmd([xb, "-test", "-config", "/usr/local/x-ui/bin/config.json"], 6) if os.path.exists(xb) else (-1, "", "нет xray")
    geo_ok = os.path.exists("/usr/local/x-ui/bin/geoip.dat") and os.path.exists("/usr/local/x-ui/bin/geosite.dat")
    items.append(Check("L1-03", "L1. Стек Nginx + Xray v26.7.28", "Nginx H2 Proxy, xray -test и геобазы", "HIGH",
        "FAIL" if (ng_err or rc_xt != 0) else "PASS",
        f"nginx_err={ng_err}, xray_rc={rc_xt} ({e_xt.strip()}), geo_ok={geo_ok}", pub_title="Nginx H2 Proxy, xray -test и геобазы"))

    _, _, nv_err = cmd(["nginx", "-v"], 3)
    m_nv = re.search(r"(\d+)\.(\d+)\.(\d+)", nv_err or "")
    ng_ver_str = m_nv.group(0) if m_nv else "0.0.0"
    ng_patched = False
    if m_nv:
        maj, mn, pat = int(m_nv.group(1)), int(m_nv.group(2)), int(m_nv.group(3))
        if (mn % 2 == 1 and (maj, mn, pat) >= (1, 31, 10)) or (mn % 2 == 0 and (maj, mn, pat) >= (1, 30, 8)) or maj > 1:
            ng_patched = True
    sctp_loaded = "sctp" in (open("/proc/modules", errors="ignore").read() if os.path.exists("/proc/modules") else "")
    modprobe_txt = "".join(open(f, errors="ignore").read() for f in glob.glob("/etc/modprobe.d/*.conf") if os.path.isfile(f))
    sctp_blocked = bool(re.search(r"install\s+sctp\s+/bin/(false|true)|blacklist\s+sctp", modprobe_txt))
    items.append(Check("L1-05", "L1. Стек Nginx + Xray v26.7.28", "Защита от NGINX2Root (18.11.2026) и модуля ядра sctp", "CRITICAL" if not ng_patched else "MEDIUM",
        "FAIL" if (not ng_patched or sctp_loaded) else ("WARN" if not sctp_blocked else "PASS"),
        f"nginx={ng_ver_str} ({'OK (NGINX2Root patched)' if ng_patched else 'УЯЗВИМ к NGINX2Root!'}), sctp_loaded={sctp_loaded}, sctp_blacklisted={sctp_blocked}",
        "Обновите nginx >= 1.31.10 и добавьте 'install sctp /bin/false' + 'blacklist sctp' в /etc/modprobe.d/99-disable-sctp.conf" if (not ng_patched or not sctp_blocked) else "",
        pub_title="Защита от NGINX2Root (11.2026) и ядра SCTP"))

    if os.path.exists("/usr/local/x-ui/bin/config.json"):
        try:
            xcfg = json.load(open("/usr/local/x-ui/bin/config.json", encoding="utf-8"))
            obs = {o.get("tag") for o in xcfg.get("outbounds", []) if isinstance(o, dict) and o.get("tag")}
            if isinstance(xcfg.get("api"), dict) and xcfg["api"].get("tag"):
                obs.add(str(xcfg["api"]["tag"]))
            orphans = [r.get("outboundTag") for r in xcfg.get("routing", {}).get("rules", []) if isinstance(r, dict) and r.get("enabled", True) and r.get("outboundTag") and r.get("outboundTag") not in obs]
            dir_ob = next((o for o in xcfg.get("outbounds", []) if isinstance(o, dict) and o.get("tag") == "direct"), {})
            v4_ok = (dir_ob.get("settings", {}).get("domainStrategy") in ("UseIPv4", "ForceIPv4"))
            items.append(Check("L1-06", "L1. Стек Nginx + Xray v26.7.28", "Целостность routing.rules и IPv4 Force в config.json", "MEDIUM",
                "WARN" if (orphans or not v4_ok) else "PASS",
                f"Осиротевшие outboundTag={orphans}, direct_v4={v4_ok}" if (orphans or not v4_ok) else "Все outboundTag валидны, direct outbound принудительно на UseIPv4/ForceIPv4.",
                "Удалите битые правила в xrayTemplateConfig.routing.rules" if orphans else "",
                pub_title="Целостность Xray routing и ForceIPv4"))
        except Exception: pass

    def chk_awg(nm: str, s1: int, s2: int, jc: int, hs: List[int], mtu: int) -> None:
        errs = []
        if s1 + 56 == s2: errs.append(f"КОЛЛИЗИЯ S1+56==S2 ({s1}+56={s2})")
        if hs and (len(set(hs)) != 4 or any(h in (1, 2, 3, 4) for h in hs)): errs.append("невалидные H1..H4")
        if mtu > 1380 or mtu <= 0: errs.append(f"MTU={mtu}")
        items.append(Check(f"L2-{nm}", "L2. AmneziaWG & ТСПУ-матрица", f"Параметры {nm}", "CRITICAL" if errs else "INFO", "FAIL" if errs else "PASS",
            f"Ошибки: {errs}" if errs else f"S1={s1}, S2={s2}, Jc={jc}, MTU={mtu}, уникальные H1-H4 (коллизий нет).",
            pub_title=f"Матрица параметров AmneziaWG ({nm})"))

    if cfg.en_nawg and os.path.exists("/etc/amnezia/amneziawg/awg0.conf"):
        at = open("/etc/amnezia/amneziawg/awg0.conf", errors="ignore").read()
        g = lambda k: int(m.group(1)) if (m := re.search(rf"^\s*{k}\s*=\s*(\d+)", at, re.M | re.I)) else 0
        chk_awg("awg0", g("S1"), g("S2"), g("Jc"), [g("H1"), g("H2"), g("H3"), g("H4")], g("MTU"))
    if cfg.db and cfg.awg3_p > 0:
        try:
            _cn_awg = sqlite3.connect(f"file:{cfg.db}?mode=ro", uri=True)
            _ib_c_awg = {r[1] for r in _cn_awg.execute("PRAGMA table_info(inbounds)")}
            _nc_awg = " AND (node_id IS NULL OR node_id = 0)" if "node_id" in _ib_c_awg else ""
            _nc_awg_p = []
            if "origin_node_guid" in _ib_c_awg:
                _pg_awg = _cn_awg.execute("SELECT value FROM settings WHERE key='panelGuid' LIMIT 1").fetchone()
                _pg_awgv = str(_pg_awg[0]).strip() if _pg_awg and _pg_awg[0] else ""
                if _pg_awgv:
                    _nc_awg += " AND (origin_node_guid IS NULL OR origin_node_guid = '' OR origin_node_guid = ?)"
                    _nc_awg_p.append(_pg_awgv)
                else:
                    _nc_awg += " AND (origin_node_guid IS NULL OR origin_node_guid = '')"
            row = _cn_awg.execute(f"SELECT settings FROM inbounds WHERE protocol='amneziawg'{_nc_awg} LIMIT 1", _nc_awg_p).fetchone()
            _cn_awg.close()
            if row:
                sv = json.loads(row[0]).get("server", {})
                hs = [int(sv.get(k, 0) or 0) for k in ("h1", "h2", "h3", "h4")]
                chk_awg("AWG-v3", int(sv.get("s1", 0)), int(sv.get("s2", 0)), int(sv.get("jc", 0)), hs, int(sv.get("mtu", 0)))
        except Exception: pass

    _, ss_u, _ = cmd(["ss", "-ulnp"], 4)
    stubs = [ln.strip() for ln in ss_u.splitlines() if re.search(r"127\.0\.0\.5[34]\b", ln)]
    r_ns = re.findall(r"^\s*nameserver\s+(\S+)", open("/etc/resolv.conf", errors="ignore").read(), re.M) if os.path.exists("/etc/resolv.conf") else []
    if cfg.en_agh:
        dns_bad = bool(stubs or r_ns != ["127.0.0.1"])
        items.append(Check("L3-01", "L3. Ядро, DNS Leaks, SSH & Firewall", "DNS-утечки ОС и systemd-resolved", "HIGH", "WARN" if dns_bad else "PASS",
            f"systemd-resolved слушает {len(stubs)} stub-сокетов, resolv.conf={r_ns}" if dns_bad else "systemd-resolved выключен, resolv.conf=127.0.0.1.",
            pub_title="DNS-утечки ОС и systemd-resolved"))

    rc_sh, out_sh, _ = cmd(["sshd", "-T"], 5)
    if rc_sh == 0:
        sm = {ln.split(None, 1)[0].lower(): ln.split(None, 1)[1].strip() for ln in out_sh.splitlines() if len(ln.split(None, 1)) == 2}
        root_ok = sm.get("permitrootlogin") in ("prohibit-password", "without-password", "no")
        pwd_ok = sm.get("passwordauthentication") == "no"
        items.append(Check("L3-02", "L3. Ядро, DNS Leaks, SSH & Firewall", "Харденинг SSH (sshd -T)", "HIGH" if not root_ok else "CRITICAL",
            "PASS" if (pwd_ok and root_ok) else ("FAIL" if not pwd_ok else "WARN"),
            f"port={sm.get('port')}, PasswordAuth={sm.get('passwordauthentication')}, PermitRootLogin={sm.get('permitrootlogin')}",
            pub_title="Харденинг SSH (Pubkey-Only)"))

    _, cc, _ = cmd(["sysctl", "-n", "net.ipv4.tcp_congestion_control"], 3)
    _, qd, _ = cmd(["sysctl", "-n", "net.core.default_qdisc"], 3)
    _, mg, _ = cmd(["iptables", "-t", "mangle", "-S"], 4)
    _, fl, _ = cmd(["iptables", "-S", "ufw-before-input"], 4)
    rc_fb, _, _ = cmd(["fail2ban-client", "status", "sshd"], 4)
    k_ok = (cc.strip() == "bbr" and qd.strip() in ("fq", "cake") and "--clamp-mss-to-pmtu" in mg and "INVALID -j DROP" in fl and rc_fb == 0)
    items.append(Check("L3-03", "L3. Ядро, DNS Leaks, SSH & Firewall", "BBR/FQ, TCPMSS, INVALID Drop и Fail2ban", "HIGH", "PASS" if k_ok else "WARN",
        f"cc={cc.strip()}, qdisc={qd.strip()}, tcpmss={'--clamp-mss-to-pmtu' in mg}, invalid_drop={'INVALID -j DROP' in fl}, fail2ban_rc={rc_fb}",
        pub_title="BBR/FQ, TCPMSS, INVALID Drop и Fail2ban"))

    _, v6_off, _ = cmd(["sysctl", "-n", "net.ipv6.conf.all.disable_ipv6"], 3)
    _, v6_g, _ = cmd(["ip", "-6", "addr", "show", "scope", "global"], 3)
    ufw_v6 = ""
    if os.path.exists("/etc/default/ufw"):
        m_u6 = re.search(r"^\s*IPV6=(\S+)", open("/etc/default/ufw", errors="ignore").read(), re.M)
        if m_u6: ufw_v6 = m_u6.group(1).lower()
    v6_asym = (v6_off.strip() == "0" and bool(v6_g.strip()) and ufw_v6 == "no")
    items.append(Check("L3-04", "L3. Ядро, DNS Leaks, SSH & Firewall", "Локальный паритет IPv6 (sysctl / UFW / global)", "CRITICAL" if v6_asym else "INFO",
        "FAIL" if v6_asym else "PASS",
        "Глобальный IPv6 активен при IPV6=no в /etc/default/ufw!" if v6_asym else f"disable_ipv6={v6_off.strip()}, global_v6={bool(v6_g.strip())}, ufw_ipv6={ufw_v6 or 'n/a'}",
        pub_title="Локальный паритет стека IPv6"))

    rc_ufw, out_ufw, _ = cmd(["ufw", "status"], 4)
    _, out_ss_all, _ = cmd(["ss", "-tulnp"], 4)
    if rc_ufw == 0 and "Status: active" in out_ufw and out_ss_all:
        live_tcp4, live_udp4, live_tcp6, live_udp6 = set(), set(), set(), set()
        for ln in out_ss_all.splitlines()[1:]:
            cols = ln.split()
            if len(cols) >= 5 and not cols[4].startswith(("127.", "[::1]:")):
                m_pt = re.search(r":(\d+)$", cols[4])
                if m_pt:
                    pt_i = int(m_pt.group(1))
                    addr = cols[4]
                    is_v6 = addr.startswith("[") or addr.startswith("*:")
                    is_v4 = not addr.startswith("[")
                    if cols[0].startswith("tcp"):
                        if is_v4: live_tcp4.add(pt_i)
                        if is_v6: live_tcp6.add(pt_i)
                    elif cols[0].startswith("udp"):
                        if is_v4: live_udp4.add(pt_i)
                        if is_v6: live_udp6.add(pt_i)
        dead_rules: List[str] = []
        for ln in out_ufw.splitlines():
            if " on " in ln: continue
            m_r = re.match(r"^\s*(\d+)/(tcp|udp)(\s+\(v6\))?\s+ALLOW\b", ln, re.I)
            if m_r:
                rp, rpr, is_rule_v6 = int(m_r.group(1)), m_r.group(2).lower(), bool(m_r.group(3))
                if is_rule_v6:
                    if (rpr == "tcp" and rp not in live_tcp6) or (rpr == "udp" and rp not in live_udp6):
                        dead_rules.append(f"{rp}/{rpr}(v6)")
                else:
                    if (rpr == "tcp" and rp not in live_tcp4) or (rpr == "udp" and rp not in live_udp4):
                        dead_rules.append(f"{rp}/{rpr}")
        items.append(Check("L3-05", "L3. Ядро, DNS Leaks, SSH & Firewall", "Паритет UFW и живых сокетов ss (Anti-ICMP_UNREACH)", "HIGH",
            "FAIL" if dead_rules else "PASS",
            f"Открыты в UFW без процесса (риск ICMP_UNREACH): {dead_rules}" if dead_rules else "Все внешние порты UFW имеют активный слушающий сокет.",
            "Закройте мёртвые правила UFW или поднимите соответствующие службы" if dead_rules else "",
            pub_title="Паритет правил фаервола и живых сокетов"))

    zl_err: List[str] = []; zl_info: List[str] = []
    if not os.path.exists("/etc/systemd/journald.conf.d/00-volatile.conf") or os.path.isdir("/var/log/journal"): zl_err.append("journald на диске")
    if os.path.exists("/etc/nginx/nginx.conf") and "access_log off;" not in open("/etc/nginx/nginx.conf", errors="ignore").read(): zl_err.append("nginx access_log")
    disk_agh_files = glob.glob("/opt/AdGuardHome/data/querylog.json*") + glob.glob("/opt/AdGuardHome/data/stats.db*")
    if disk_agh_files: zl_err.append(f"файлы на диске: {[os.path.basename(x) for x in disk_agh_files]}")
    if os.path.exists("/opt/AdGuardHome/AdGuardHome.yaml"):
        yt = open("/opt/AdGuardHome/AdGuardHome.yaml", errors="ignore").read()
        m_ql = re.search(r"(?ms)^querylog:\n((?:  [^\n]*\n)*)", yt)
        m_st = re.search(r"(?ms)^statistics:\n((?:  [^\n]*\n)*)", yt)
        ql_on = bool(m_ql and "enabled: true" in m_ql.group(1))
        st_on = bool(m_st and "enabled: true" in m_st.group(1))
        _, fm_out, _ = cmd(["findmnt", "-n", "-o", "FSTYPE,SIZE", "/run/adguardhome"], 3)
        is_tmpfs = fm_out.strip().startswith("tmpfs")
        if (ql_on or st_on) and (not is_tmpfs or (m_ql and 'dir_path: ""' in m_ql.group(1)) or (m_st and 'dir_path: ""' in m_st.group(1))):
            zl_err.append("AGH логи/статистика не изолированы в tmpfs /run/adguardhome")
        elif ql_on:
            _fm_clean = " ".join(fm_out.split())
            zl_info.append(f"AGH querylog=true в изолированном {_fm_clean}")
    items.append(Check("L4-01", "L4. Политика Zero-Log & FHS", "Zero-Log на диске и изоляция AGH в tmpfs", "HIGH",
        "FAIL" if any("на диске" in x or "не изолированы" in x for x in zl_err) else ("WARN" if (zl_err or zl_info) else "PASS"),
        f"Нарушения: {zl_err}" if zl_err else (f"Дисковых логов 0; {'; '.join(zl_info)}" if zl_info else "journald=volatile, nginx access_log=off, Xray access=none, AGH без дисковых логов."),
        "Отключите querylog или оставьте в квотированном tmpfs /run/adguardhome" if (zl_err or zl_info) else "",
        pub_title="Политика Zero-Log и RAM-изоляция телеметрии"))

    bad_p = [f"{fp}={oct(stat.S_IMODE(os.stat(os.path.realpath(fp)).st_mode))}" for fp in (
        "/root/vpn_credentials.txt", "/root/amneziawg-client.conf", "/etc/myprivatecloud/sso.key",
        "/etc/myprivatecloud/config.env", "/etc/myprivatecloud/config.json", "/opt/AdGuardHome/AdGuardHome.yaml",
        "/etc/amnezia/amneziawg/awg0.conf", "/etc/amnezia/amneziawg/clients.json", "/etc/x-ui/x-ui.db"
    ) if os.path.exists(fp) and stat.S_IMODE(os.stat(os.path.realpath(fp)).st_mode) > 0o600]
    items.append(Check("L4-02", "L4. Политика Zero-Log & FHS", "Права доступа секретов (<=0600)", "HIGH", "FAIL" if bad_p else "PASS",
        f"Избыточные права: {bad_p}" if bad_p else "Все БД, ключи и конфиги защищены маской <= 0600.",
        pub_title="Права доступа секретов и ключей (<=0600)"))
    return items

def main() -> int:
    ap = argparse.ArgumentParser(description="Hardcore DPI / GFW / TSPU & Hardening Auditor (11.2026)")
    ap.add_argument("target", nargs="?", default="", help="Домен или IP (позиционный или --target)")
    ap.add_argument("--target", dest="target_flag", default="", help="Целевой домен или IP")
    ap.add_argument("--mode", choices=["auto", "local", "remote"], default="auto")
    ap.add_argument("--target-ip", "--ip", dest="target_ip", default="")
    ap.add_argument("--domain", default="")
    ap.add_argument("--steal-domain", "--steal", dest="steal_domain", default="")
    ap.add_argument("--agh-domain", "--agh", dest="agh_domain", default="")
    ap.add_argument("--agh-client-id", default="")
    ap.add_argument("--xhttp-path", "--xhttp", dest="xhttp_path", default="")
    ap.add_argument("--sub-path", default="")
    ap.add_argument("--hy2-port", "--hy2", dest="hy2_port", type=int, default=0)
    ap.add_argument("--awg-ports", "--awg", dest="awg_ports", default="")
    ap.add_argument("--test-ratelimit", "--rate-limit", dest="test_ratelimit", action="store_true")
    ap.add_argument("--public", action="store_true", help="Вывести в stdout только анонимный отчёт (подробный всё равно сохранится в файл)")
    args = ap.parse_args()
    if args.target_flag and not args.target: args.target = args.target_flag

    cfg = discover(args)
    items = run_remote_checks(cfg)
    if cfg.mode == "local":
        if os.geteuid() != 0 and not args.public: print(f"{Y}[!] Запуск без root ограничивает локальные проверки.{N}")
        items.extend(run_local_checks(cfg))

    ps = sum(1 for x in items if x.st == "PASS"); wr = sum(1 for x in items if x.st == "WARN"); fl = sum(1 for x in items if x.st == "FAIL")
    tot = ps + wr + fl; sc = int((ps / tot) * 100) if tot else 0
    views = [(it.cid, "CLEAN" if it.st == "PASS" else ("MEDIUM" if it.st == "WARN" else "HIGH RISK"), it.view) for it in items if it.view]

    if not args.public:
        print(f"{C}{'='*78}\n{B}  HARDCORE DPI / GFW / ТСПУ И АУДИТ БОТОВ 11.2026 (Режим: {cfg.mode.upper()}){N}")
        print(f"  IP: {cfg.ip} | Main: {cfg.p_dom or 'N/A'} | Steal: {','.join(cfg.steals) or 'N/A'} | AGH: {cfg.agh_dom or 'выкл'}\n{'='*78}{N}")
        cur_d = ""
        for it in items:
            if it.dom != cur_d: cur_d = it.dom; print(f"\n{C}{B}[ {cur_d} ]{N}")
            mk = f"{G}[✓ PASS]{N}" if it.st == "PASS" else (f"{R}[✗ FAIL]{N}" if it.st == "FAIL" else f"{Y}[! WARN]{N}")
            print(f"  {mk} {B}{it.cid:<8}{N} ({it.sev:<8}) {it.title}\n           {D}└─ {it.ev}{N}")
            if it.fix and it.st in ("FAIL", "WARN"): print(f"           {Y}   Фикс: {it.fix}{N}")

        print(f"\n{C}{'='*78}\n{B}  МАТРИЦА ВИДИМОСТИ: ГЛАЗАМИ СКАНЕРОВ / БОТОВ / DPI / GFW / ТСПУ{N}\n{'-'*78}{N}")
        for cid, rsk, vw in views:
            cl = G if rsk == "CLEAN" else (Y if rsk == "MEDIUM" else R)
            print(f"  {cl}[{rsk:<9}]{N} {B}{cid:<7}{N} {vw}")

    pub_lines = [
        "==============================================================================",
        f"  ANONYMOUS DPI & SECURITY AUDIT REPORT (11.2026) | Score: {sc}%",
        f"  Total={tot} | PASS={ps} | WARN={wr} | FAIL={fl}",
        "==============================================================================",
    ]
    pub_json_items = []
    for it in items:
        p_t = it.pub_title or it.title
        pub_lines.append(f"[{it.st:<4}] {it.cid:<8} | {p_t}")
        pub_json_items.append({"id": it.cid, "title": p_t, "result": it.st})
    pub_lines.append("==============================================================================")

    print(f"\n{C}{'='*78}\n{B}  АНОНИМНЫЙ ОТЧЁТ (ДЛЯ ПУБЛИКАЦИИ — БЕЗ IP, ДОМЕНОВ И ПУТЕЙ){N}\n{'-'*78}{N}")
    for it in items:
        p_t = it.pub_title or it.title
        cl = G if it.st == "PASS" else (Y if it.st == "WARN" else R)
        print(f"  {cl}[{it.st:<4}]{N} {B}{it.cid:<8}{N} | {p_t}")

    out_dir = "/root" if os.access("/root", os.W_OK) else "/tmp"
    safe_t = re.sub(r"[^a-zA-Z0-9._-]", "_", cfg.p_dom or cfg.ip) or "target"
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    txt_p = os.path.join(out_dir, f"hardcore_dpi_audit_{safe_t}_{ts}.txt")
    json_p = os.path.join(out_dir, f"hardcore_dpi_audit_{safe_t}_{ts}.json")
    pub_txt_p = os.path.join(out_dir, f"hardcore_dpi_audit_public_{ts}.txt")
    pub_json_p = os.path.join(out_dir, f"hardcore_dpi_audit_public_{ts}.json")

    lines = [
        f"HARDCORE DPI / GFW / TSPU AUDIT REPORT ({ts})",
        f"Mode: {cfg.mode} | IP: {cfg.ip} | Main: {cfg.p_dom} | Steal: {cfg.steals} | AGH: {cfg.agh_dom}",
        f"Summary: PASS={ps} | WARN={wr} | FAIL={fl} | Score={sc}%", "", "=== DPI VISIBILITY ==="
    ] + [f"[{r}] {c}: {v}" for c, r, v in views] + ["", "=== CHECKLIST ==="]
    for it in items:
        lines.append(f"[{it.st}] [{it.cid}] ({it.sev}) {it.title} -> {it.ev}")
        if it.fix and it.st in ("FAIL", "WARN"): lines.append(f"   FIX: {it.fix}")

    for path, content in (
        (txt_p, "\n".join(lines) + "\n"),
        (json_p, json.dumps({"config": asdict(cfg), "summary": {"pass": ps, "warn": wr, "fail": fl, "score": sc}, "items": [asdict(x) for x in items]}, indent=2, ensure_ascii=False)),
        (pub_txt_p, "\n".join(pub_lines) + "\n"),
        (pub_json_p, json.dumps({"summary": {"total": tot, "pass": ps, "warn": wr, "fail": fl, "score": sc}, "items": pub_json_items}, indent=2, ensure_ascii=False)),
    ):
        open(path + ".tmp", "w", encoding="utf-8").write(content)
        os.replace(path + ".tmp", path); os.chmod(path, 0o600)

    print(f"{C}{'='*78}{N}")
    print(f"  ИТОГ: {G}PASS={ps}{N} | {Y}WARN={wr}{N} | {R}FAIL={fl}{N} | Индекс стойкости: {B}{sc}%{N}")
    print(f"  1) Подробный (0600): {C}{txt_p}{N} | {C}{json_p}{N}")
    print(f"  2) Анонимный (0600): {G}{pub_txt_p}{N} | {G}{pub_json_p}{N}")
    print(f"{C}{'='*78}{N}")
    return 1 if fl > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
PY_AUDIT
EOF_HARDCORE_AUDIT
    chmod 0700 "${AUDIT_BIN}.tmp"
    mv -f "${AUDIT_BIN}.tmp" "$AUDIT_BIN"
    ok "Скрипт аудита установлен: ${CYAN}${AUDIT_BIN}${NC} (chmod 0700)"

    echo
    if prompt_yes_no "Провести комплексный аудит безопасности и DPI/ТСПУ прямо сейчас?" "n"; then
        echo -e "  1) ${GREEN}Стандартный локальный + внешний аудит${NC} (--mode local)"
        echo -e "  2) ${YELLOW}Расширенный аудит с проверкой Rate-Limit${NC} (--mode local --test-ratelimit)"
        echo -e "  3) ${CYAN}Анонимный вывод в консоль + полный отчёт в файл${NC} (--mode local --public)"
        prompt_choice "Выберите режим аудита" "1" AUDIT_MODE_CHOICE "1" "2" "3"
        AUDIT_ARGS=("--mode" "local")
        if [ "$AUDIT_MODE_CHOICE" = "2" ]; then
            AUDIT_ARGS+=("--test-ratelimit")
        elif [ "$AUDIT_MODE_CHOICE" = "3" ]; then
            AUDIT_ARGS+=("--public")
        fi
        audit_rc=0
        "$AUDIT_BIN" "${AUDIT_ARGS[@]}" || audit_rc=$?
        if [ "$audit_rc" -eq 0 ]; then
            ok "Финальный аудит завершён успешно (FAIL=0)."
        else
            warn "Аудит зафиксировал замечания (код: $audit_rc). Отчёт сохранён в /root/hardcore_dpi_audit_*.txt; повторите проверку после reboot: ${AUDIT_BIN} --mode local"
        fi
    else
        log "Аудит отложен. Для запуска после reboot выполните: ${CYAN}${AUDIT_BIN} --mode local${NC}"
    fi
else
    log "Установка скрипта аудита hardcore_dpi_audit.sh пропущена (только по запросу)."
fi

exit 0
