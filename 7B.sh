#!/usr/bin/env bash
#
# ==============================================================================
# Production AutoSetup: Hardened Master Engine v7.1.0 Universal (Beta 2 All-in-One)
# OS Hardening + BBR + Nginx L4 Stream + 3X-UI + Zero-Touch + AdGuard DoH + Port Hop
# ==============================================================================
# Совместимость: Ubuntu 20.04 / 22.04 / 24.04 & Debian 11 / 12
# Архитектура:
#   1) Системный Hardening: BBR, fq, somaxconn 65535, отключение IPv6 (sysctl+GRUB+cron)
#   2) Защита SSH: генерация Ed25519, безопасная смена порта, Fail2ban, socket migration
#   3) Nginx Mainline L4 Stream + Unix Sockets (/dev/shm) + Anti-Loop 9443 + L4 Failover
#   4) Анти-фингерпринтинг веб-маски: динамические заголовки Last-Modified $date_gmt
#   5) Приватный AdGuard Home DoH (порт 53 свободен, ClientID токен, Split-DNS DE/RU)
#   6) Гибридный SSL: Certbot (--cert-name изоляция) / acme.sh Cloudflare DNS-01
#   7) Pre-flight SNI Benchmark: автоподбор самого быстрого домена для Classic Reality
#   8) Port Hopping для Hysteria 2: диапазон UDP 20000:50000 -> REDIRECT на порт Hy2
#   9) TCP MSS Clamping в mangle: защита от зависания пакетов на сотовых вышках
#  10) Автообновление geosite.dat и geoip.dat через systemd timer (еженедельно)
#  11) Zero-Touch SQLite Reconcile (Python RFC 7748 Curve25519):
#      - Автосоздание 6 инбаундов: Steal Reality, Classic Reality, xHTTP, Hy2, AWG v3, AWG v2
#      - Единый клиент (Unified Client) под одной ссылкой подписки
#      - Мультиформатный шлюз подписок (Base64, JSON, Clash) с обходом WAF
#      - AWG v3.1: безопасный MTU 1320 с компенсацией ContentPaddingAddition 3-16
#      - Автонастройка externalProxy: 443 для всех протоколов
#      - Защита Xray: блокировка SMTP (порт 25) и локальных сетей хоста (SSRF)
#  12) UFW фаервол: строгая изоляция всех внутренних технических сокетов
# ==============================================================================

set -euo pipefail

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
echo -e "${GREEN}  All-in-One Master Installer v7.1.0 Universal (Beta 2 Edition)      ${NC}"
echo -e "${CYAN}  Hardening + Nginx L4 + 3X-UI + Zero-Touch + DoH + Port Hopping     ${NC}"
echo -e "${CYAN}=====================================================================${NC}"

# ----------------------- Системные предусловия -----------------------
if [ "$EUID" -ne 0 ]; then
  die "Пожалуйста, запустите установщик с правами суперпользователя root (через sudo)."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
        die "Данный скрипт оптимизирован строго под дистрибутивы семейств Ubuntu и Debian."
    fi
else
    die "Не удалось определить параметры текущего дистрибутива ОС."
fi

export DEBIAN_FRONTEND=noninteractive

# Автоопределение активного SSH-порта
SSH_ACTIVE_PORT=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F: '{print $NF}' | sort -u | head -n1 || echo "")
SSH_ACTIVE_PORT="${SSH_ACTIVE_PORT:-22}"

# ----------------------- Функции валидации -----------------------
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

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 22 ] && [ "$1" -le 65535 ]
}

get_ssh_service_name() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^sshd\.service"; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

# Функция бенчмарка и выбора лучшего SNI для Classic REALITY (вывод логов строго в stderr)
benchmark_sni() {
    local candidates=("gateway.icloud.com" "www.samsung.com" "addons.mozilla.org" "dl.google.com")
    local best_sni="gateway.icloud.com"
    local min_rtt=999999

    echo -e "${CYAN}[+] Тестирование пула внешних SNI для Classic REALITY (Pre-flight Benchmark)...${NC}" >&2
    for sni in "${candidates[@]}"; do
        local rtt
        rtt=$(curl -s -o /dev/null -w "%{time_connect}" --connect-timeout 2 --tlsv1.3 "https://${sni}" 2>/dev/null || echo "0")
        if (( $(echo "$rtt > 0.001" | bc -l 2>/dev/null || [ "$rtt" != "0" ]) )); then
            local rtt_ms
            rtt_ms=$(awk "BEGIN {print int($rtt * 1000)}")
            echo -e "  - ${CYAN}${sni}${NC}: RTT = ${GREEN}${rtt_ms} ms${NC} (TLS 1.3 OK)" >&2
            if [ "$rtt_ms" -lt "$min_rtt" ]; then
                min_rtt="$rtt_ms"
                best_sni="$sni"
            fi
        else
            echo -e "  - ${CYAN}${sni}${NC}: ${RED}Недоступен или таймаут${NC}" >&2
        fi
    done
    echo -e "${GREEN}[OK]${NC} Выбран оптимальный внешний SNI: ${GREEN}${best_sni}${NC} (${min_rtt} ms)" >&2
    echo -n "$best_sni"
}

# =============================================================
#  ВЫБОР РЕЖИМА И СБОР ПАРАМЕТРОВ НА СТАРТЕ
# =============================================================
echo
echo -e "${WHITE}${BOLD}Выберите режим развёртывания системы:${NC}"
echo -e "  1) ${GREEN}${BOLD}Express (Автопилот — Рекомендуется)${NC} — Развёртывание под ключ за 3 вопроса."
echo -e "     ${DIM}Пароли, порты, BBR, фаервол, SSL, AdGuard DoH, Port Hopping и 6 инбаундов настроятся сами.${NC}"
echo -e "  2) ${YELLOW}${BOLD}Custom (Эксперт)${NC} — Ручной пошаговый контроль над каждым компонентом."
prompt_default "Ваш выбор" "1" INSTALL_MODE

# Шаг 1: Домен
echo
echo -e "${YELLOW}Шаг 1: Конфигурация доменного имени${NC}"
while true; do
    read -rp "Введите ваш основной домен (например, yourdomain.online): " PRIMARY_DOMAIN
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

if [[ ! "$PRIMARY_DOMAIN" =~ ^www\. ]]; then
    ALL_DOMAINS+=("www.$PRIMARY_DOMAIN")
fi

# Шаг 2: Email
echo
echo -e "${YELLOW}Шаг 2: Email для сертификатов Let's Encrypt${NC}"
while true; do
    read -rp "Введите контактный Email (для регистрации SSL): " LE_EMAIL
    LE_EMAIL=$(echo "$LE_EMAIL" | tr -d '[:space:]')
    if [[ -z "$LE_EMAIL" ]] || [[ "$LE_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    fi
    warn "Некорректный формат email. Введите валидный адрес или нажмите Enter."
done

# Шаг 3: SSH Порт
echo
echo -e "${YELLOW}Шаг 3: Настройка порта SSH (Защита от сканирования)${NC}"
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

# Ветвление режимов
if [ "$INSTALL_MODE" = "1" ]; then
    # --- EXPRESS РЕЖИМ ---
    DO_SYS_UPGRADE=1
    INSTALL_EXTRA_UTILS=1
    ENABLE_BBR_IPV6=1
    BLOCK_PING=0

    CHANGE_ROOT_PASS=0
    ROOT_PASSWORD=""
    CREATE_USER=0
    NEW_USERNAME=""
    SETUP_KEYS=0

    PANEL_PORT="10443"
    RAW_PATH="panel-$(openssl rand -hex 3)"
    PANEL_PATH="/${RAW_PATH}/"
    SUB_PORT="55443"
    RAW_SUB_PATH="sub-$(openssl rand -hex 4)"
    SUB_PATH="/${RAW_SUB_PATH}/"
    SUB_JSON_PATH="/${RAW_SUB_PATH}json/"

    XHTTP_STREAM_PORT="50443"
    RAW_XHTTP_STREAM_PATH="xhttp-stream"
    XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH}/"

    ADMIN_USER="admin"
    ADMIN_PASS="Xui_$(openssl rand -hex 6)"

    # Steal-Oneself Reality
    ENABLE_STEAL=1
    STEAL_PORT="45443"
    STEAL_PORTS_LIST+=("$STEAL_PORT")
    ALL_REALITY_PORTS+=("$STEAL_PORT")
    STEAL_DOM="cdn.$PRIMARY_DOMAIN"
    ALL_DOMAINS+=("$STEAL_DOM")
    STEAL_DOMAINS+=("$STEAL_DOM")
    DOMAIN_TO_PORT["$STEAL_DOM"]="$STEAL_PORT"

    # Classic External Reality (Автобенчмарк)
    ENABLE_CLASSIC=1
    CLASSIC_PORT="46443"
    CLASSIC_PORTS_LIST+=("$CLASSIC_PORT")
    ALL_REALITY_PORTS+=("$CLASSIC_PORT")
    EXT_SNI=$(benchmark_sni)
    EXT_SNI_TO_PORT["$EXT_SNI"]="$CLASSIC_PORT"
    EXT_SNI_LIST+=("$EXT_SNI")

    # Протоколы
    ENABLE_HY2=1
    HY2_PORT="443"
    ENABLE_AWG_V3=1
    AWG_V3_PORT="8443"
    ENABLE_AWG_V2=1
    AWG_V2_PORT="8444"

    # AdGuard Home DoH
    ENABLE_AGH=1
    AGH_DOMAIN="dns.$PRIMARY_DOMAIN"
    ALL_DOMAINS+=("$AGH_DOMAIN")
    AGH_USER="admin"
    AGH_PASS="AgHome_$(openssl rand -hex 4)"
    AGH_CLIENT_ID="home-router"

    DECOY_MODE="1"
    SSL_ENGINE_CHOICE="1"
    CF_AUTH_METHOD="1"

else
    # --- CUSTOM РЕЖИМ ---
    prompt_yes_no "Выполнить полное обновление системы (apt upgrade) и очистку?" "y" && DO_SYS_UPGRADE=1 || DO_SYS_UPGRADE=0
    prompt_yes_no "Установить системные утилиты и инструменты мониторинга (htop, btop, jq, tmux)?" "y" && INSTALL_EXTRA_UTILS=1 || INSTALL_EXTRA_UTILS=0
    prompt_yes_no "Включить TCP BBR и полностью отключить IPv6?" "y" && ENABLE_BBR_IPV6=1 || ENABLE_BBR_IPV6=0
    prompt_yes_no "Блокировать входящие ICMP (Ping) запросы в фаерволе?" "n" && BLOCK_PING=1 || BLOCK_PING=0

    prompt_yes_no "Сменить пароль root?" "n" && CHANGE_ROOT_PASS=1 || CHANGE_ROOT_PASS=0
    if [ "$CHANGE_ROOT_PASS" -eq 1 ]; then
        read -rsp "Введите новый пароль root: " ROOT_PASSWORD; echo
    fi

    prompt_yes_no "Создать непривилегированного пользователя с sudo?" "n" && CREATE_USER=1 || CREATE_USER=0
    if [ "$CREATE_USER" -eq 1 ]; then
        read -rp "Введите имя пользователя: " NEW_USERNAME
        read -rsp "Введите пароль для $NEW_USERNAME: " NEW_USER_PASS; echo
    fi

    prompt_yes_no "Настроить SSH ключи Ed25519?" "y" && SETUP_KEYS=1 || SETUP_KEYS=0

    echo
    echo -e "${YELLOW}Настройка внутренних портов 3X-UI:${NC}"
    prompt_default "Внутренний порт панели 3X-UI" "10443" PANEL_PORT
    prompt_default "Секретный URI панели (без слэшей)" "my-3x-panel" RAW_PATH
    validate_path_segment "$RAW_PATH" "URI панели"
    PANEL_PATH="/${RAW_PATH#/}/"

    prompt_default "Внутренний порт сервера подписок 3X-UI" "55443" SUB_PORT
    prompt_default "Секретный URI подписок (без слэшей)" "my-post-key" RAW_SUB_PATH
    validate_path_segment "$RAW_SUB_PATH" "URI подписок"
    SUB_PATH="/${RAW_SUB_PATH#/}/"
    SUB_JSON_PATH="/${RAW_SUB_PATH#/}json/"

    prompt_default "Внутренний порт VLESS xHTTP (Stream-One/Up)" "50443" XHTTP_STREAM_PORT
    prompt_default "URI-путь для xHTTP" "Stream-One-Path" RAW_XHTTP_STREAM_PATH
    validate_path_segment "$RAW_XHTTP_STREAM_PATH" "URI xHTTP"
    XHTTP_STREAM_PATH="/${RAW_XHTTP_STREAM_PATH#/}/"

    prompt_default "Логин администратора 3X-UI" "admin" ADMIN_USER
    DEFAULT_XP="Xui_$(openssl rand -hex 4)"
    prompt_default "Пароль администратора 3X-UI" "$DEFAULT_XP" ADMIN_PASS

    echo
    prompt_yes_no "Включить Steal-Oneself REALITY (Кража у самого себя)?" "y" && ENABLE_STEAL=1 || ENABLE_STEAL=0
    if [ "$ENABLE_STEAL" -eq 1 ]; then
        prompt_default "  Локальный порт Xray для Steal-Oneself" "45443" STEAL_PORT
        STEAL_PORTS_LIST+=("$STEAL_PORT")
        ALL_REALITY_PORTS+=("$STEAL_PORT")
        prompt_default "  Собственный поддомен для Steal-Oneself" "cdn.$PRIMARY_DOMAIN" STEAL_DOM
        ALL_DOMAINS+=("$STEAL_DOM")
        STEAL_DOMAINS+=("$STEAL_DOM")
        DOMAIN_TO_PORT["$STEAL_DOM"]="$STEAL_PORT"
    fi

    echo
    prompt_yes_no "Включить Classic External REALITY?" "y" && ENABLE_CLASSIC=1 || ENABLE_CLASSIC=0
    if [ "$ENABLE_CLASSIC" -eq 1 ]; then
        prompt_default "  Локальный порт Xray для Classic REALITY" "46443" CLASSIC_PORT
        CLASSIC_PORTS_LIST+=("$CLASSIC_PORT")
        ALL_REALITY_PORTS+=("$CLASSIC_PORT")
        AUTO_BENCH_SNI=$(benchmark_sni)
        prompt_default "  Внешний SNI маскировки" "$AUTO_BENCH_SNI" EXT_SNI
        EXT_SNI_TO_PORT["$EXT_SNI"]="$CLASSIC_PORT"
        EXT_SNI_LIST+=("$EXT_SNI")
    fi

    echo
    prompt_yes_no "Установить Hysteria 2 (UDP)?" "y" && ENABLE_HY2=1 || ENABLE_HY2=0
    if [ "$ENABLE_HY2" -eq 1 ]; then
        prompt_default "  Внешний UDP-порт для Hysteria 2" "443" HY2_PORT
    fi

    prompt_yes_no "Установить AmneziaWG v3.1 (WG3)?" "y" && ENABLE_AWG_V3=1 || ENABLE_AWG_V3=0
    if [ "$ENABLE_AWG_V3" -eq 1 ]; then
        prompt_default "  Внешний UDP-порт для AmneziaWG v3.1" "8443" AWG_V3_PORT
    fi

    prompt_yes_no "Установить AmneziaWG v2.0 / Legacy (для роутеров)?" "y" && ENABLE_AWG_V2=1 || ENABLE_AWG_V2=0
    if [ "$ENABLE_AWG_V2" -eq 1 ]; then
        prompt_default "  Внешний UDP-порт для AmneziaWG v2.0" "8444" AWG_V2_PORT
    fi

    echo
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
    echo -e "${YELLOW}Выбор маскировочного сайта (Decoy Front):${NC}"
    echo -e "  1) ${GREEN}DataSphere Analytics Enterprise${NC} (Корпоративный SaaS, живая телеметрия ±10%)"
    echo -e "  2) ${GREEN}CosmosCloud NextGen${NC} (Облачный диск, логотип, сессии)"
    echo -e "  3) Стандартная заглушка Nginx (Welcome to nginx)"
    prompt_default "Ваш выбор" "1" DECOY_MODE

    echo
    echo -e "${YELLOW}Метод выпуска SSL-сертификатов:${NC}"
    echo -e "  1) ${GREEN}Классический Certbot (HTTP-01)${NC} (/etc/letsencrypt/live/)"
    echo -e "  2) ${GREEN}acme.sh + Cloudflare DNS-01${NC} (/etc/ssl/acme/)"
    prompt_default "Ваш выбор" "1" SSL_ENGINE_CHOICE

    if [ "$SSL_ENGINE_CHOICE" = "2" ]; then
        prompt_default "Вариант аутентификации Cloudflare (1-Token, 2-Global Key)" "1" CF_AUTH_METHOD
        if [ "$CF_AUTH_METHOD" = "1" ]; then
            read -rp "Введите Cloudflare API Token: " CF_Token
            export CF_Token
        else
            read -rp "Введите Cloudflare Email: " CF_Email
            read -rp "Введите Cloudflare Global API Key: " CF_Key
            export CF_Email CF_Key
        fi
    fi
fi

if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    SSL_BASE_DIR="/etc/letsencrypt/live"
else
    SSL_BASE_DIR="/etc/ssl/acme"
fi

# =============================================================
#  ЭТАП 1: ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ПАКЕТОВ
# =============================================================
echo
log "Этап 1: Обновление системы и установка утилит..."
apt-get update -q

if [[ "$OS_ID" == "ubuntu" ]]; then
    apt-get install -y software-properties-common -q || true
    add-apt-repository -y universe || true
fi

if [ "${DO_SYS_UPGRADE:-0}" -eq 1 ]; then
    log "Полное обновление пакетов дистрибутива..."
    apt-get upgrade -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y -q
    apt-get autoclean -y -q
fi

CORE_PKGS=(
    curl wget bash sudo systemd openssl gawk lsb-release gnupg dnsutils
    socat cron ufw iproute2 tar apache2-utils fail2ban python3 python3-systemd
    python3-bcrypt ca-certificates build-essential jq tmux net-tools bc
)
apt-get install -y "${CORE_PKGS[@]}" -q || true

if [ "${INSTALL_EXTRA_UTILS:-0}" -eq 1 ]; then
    apt-get install -y htop iperf3 iftop tcpdump mtr-tiny ncdu vnstat openssh-client -q || true
    apt-get install -y btop -q 2>/dev/null || true
fi
ok "Системные утилиты успешно установлены."

# =============================================================
#  ЭТАП 2: СЕТЕВОЙ ХАРДЕНИНГ ЯДРА (BBR + NO IPV6 + TCP/UDP BUFFERS)
# =============================================================
echo
log "Этап 2: Консолидированный тюнинг сетевого стека ядра Linux..."

mkdir -p /etc/sysctl.d/
cat << 'EOF' > /etc/sysctl.d/99-hardened-network.conf
# TCP BBR Congestion Control & fq
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Защита от утечек трафика (No IPv6 leak)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Высокопроизводительные очереди somaxconn
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# Таймауты и сессии
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_max_tw_buckets = 524288
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0

# Буферы оперативной памяти для HTTP/2 и UDP (Hy2/AWG)
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
ok "Сетевые параметры ядра BBR, fq и буферы применены."

if [ -f /etc/default/grub ] && ! grep -q "ipv6.disable=1" /etc/default/grub; then
    cp /etc/default/grub /etc/default/grub.bak 2>/dev/null || true
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 /' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    if command -v update-grub &>/dev/null; then
        update-grub >/dev/null 2>&1 || true
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    fi
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

# =============================================================
#  ЭТАП 3: НАСТРОЙКА SSH, КЛЮЧЕЙ И FAIL2BAN
# =============================================================
echo
log "Этап 3: Защита службы SSH и настройка авторизации..."

if [ "${CHANGE_ROOT_PASS:-0}" -eq 1 ] && [ -n "${ROOT_PASSWORD:-}" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    ok "Пароль root изменён."
fi

if [ "${CREATE_USER:-0}" -eq 1 ] && [ -n "${NEW_USERNAME:-}" ]; then
    if ! id "$NEW_USERNAME" &>/dev/null; then
        adduser --disabled-password --gecos "" "$NEW_USERNAME"
        echo "$NEW_USERNAME:$NEW_USER_PASS" | chpasswd
        usermod -aG sudo "$NEW_USERNAME"
        echo "$NEW_USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USERNAME"
        chmod 440 "/etc/sudoers.d/$NEW_USERNAME"
        ok "Пользователь $NEW_USERNAME создан и наделён правами sudo."
    fi
fi

KEYS_APPLIED=0
if [ "${SETUP_KEYS:-0}" -eq 1 ]; then
    TARGET_KEY_USER="root"
    [ -n "${NEW_USERNAME:-}" ] && TARGET_KEY_USER="$NEW_USERNAME"
    USER_HOME=$(getent passwd "$TARGET_KEY_USER" | cut -d: -f6)

    echo -e "\n${WHITE}Настройка SSH-ключей для ${GREEN}${TARGET_KEY_USER}${NC}:"
    echo -e "  1) Сгенерировать пару Ed25519 на сервере"
    echo -e "  2) Вставить свой Public Key (ssh-ed25519 / ssh-rsa)"
    echo -e "  3) Пропустить"
    read -rp "Ваш выбор [1-3]: " KEY_CHOICE
    KEY_CHOICE="${KEY_CHOICE:-3}"

    mkdir -p "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"

    if [ "$KEY_CHOICE" = "1" ]; then
        ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/id_ed25519" -C "vps-$TARGET_KEY_USER" -N "" -q
        cat "$USER_HOME/.ssh/id_ed25519.pub" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
        echo -e "\n${YELLOW}=====================================================================${NC}"
        echo -e "${YELLOW}!!! СОХРАНИТЕ ПРИВАТНЫЙ КЛЮЧ ED25519 ПРЯМО СЕЙЧАС !!!${NC}"
        echo -e "${YELLOW}=====================================================================${NC}"
        cat "$USER_HOME/.ssh/id_ed25519"
        echo -e "${YELLOW}=====================================================================${NC}"
        read -rp "Нажмите Enter, когда сохраните ключ..." || true
        KEYS_APPLIED=1
    elif [ "$KEY_CHOICE" = "2" ]; then
        read -rp "Вставьте публичный ключ: " PUB_INPUT
        if [ -n "$PUB_INPUT" ]; then
            echo "$PUB_INPUT" >> "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys"
            chown -R "$TARGET_KEY_USER:$TARGET_KEY_USER" "$USER_HOME/.ssh" 2>/dev/null || true
            ok "Публичный ключ добавлен."
            KEYS_APPLIED=1
        fi
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

if [ "$KEYS_APPLIED" -eq 1 ] && prompt_yes_no "Отключить вход по паролю по SSH (PasswordAuthentication no)?" "n"; then
    cat << 'EOF' >> /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
EOF
    ok "Авторизация по паролю отключена."
fi

mkdir -p /run/sshd
if /usr/sbin/sshd -t; then
    systemctl restart "$SSH_SERVICE.service" || true
    ok "SSH успешно работает на порту $TARGET_SSH_PORT."
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
#  ЭТАП 4: УСТАНОВКА 3X-UI И ПОДГОТОВКА БАЗЫ SQLITE
# =============================================================
echo
log "Этап 4: Развёртывание официального ядра 3X-UI..."

systemctl stop x-ui 2>/dev/null || true

DB_PATH="/etc/x-ui/x-ui.db"
if [ ! -f "$DB_PATH" ]; then
    log "Установка официального релиза 3X-UI (mhsanaei)..."
    curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o /tmp/3x-ui-install.sh
    printf "n\n" | bash /tmp/3x-ui-install.sh
    rm -f /tmp/3x-ui-install.sh
fi

for alt_db in "$DB_PATH" "/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db"; do
    if [ -f "$alt_db" ]; then
        DB_PATH="$alt_db"
        break
    fi
done
ok "База 3X-UI инициализирована: $DB_PATH"

# =============================================================
#  ЭТАП 5: NGINX MAINLINE И ВЫПУСК SSL
# =============================================================
echo
log "Этап 5: Подключение репозитория Nginx Mainline и выпуск сертификатов..."

mkdir -p /usr/share/keyrings
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/$OS_ID $OS_CODENAME nginx" \
    | tee /etc/apt/sources.list.d/nginx.list

cat << EOF > /etc/apt/preferences.d/99nginx
Package: nginx*
Pin: origin nginx.org
Pin-Priority: 900
EOF

apt-get update -q
apt-get install -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx

NGINX_USER="nginx"
id -u nginx >/dev/null 2>&1 || NGINX_USER="www-data"

WEBROOT="/var/www/html"
mkdir -p "$WEBROOT/.well-known/acme-challenge"
mkdir -p /var/cache/nginx/img_cache /var/cache/nginx/html_cache /var/cache/nginx/video_cache
mkdir -p /var/www/mirror /var/www/proxy_temp /etc/nginx/stream.d /etc/nginx/conf.d

chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp
chmod 755 "$WEBROOT" /var/cache/nginx /var/www/mirror /var/www/proxy_temp

rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* /etc/nginx/conf.d/* /etc/nginx/stream.d/*

cat << EOF > "/etc/nginx/conf.d/00-acme.conf"
server {
    listen 80;
    server_name ${ALL_DOMAINS[*]};
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ { root $WEBROOT; try_files \$uri =404; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
nginx -t || die "Ошибка конфигурации ACME сервера Nginx."
systemctl restart nginx

# Выпуск SSL
if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    log "Выпуск SSL через Certbot..."
    apt-get install -y snapd -q
    systemctl start snapd.socket || true
    systemctl enable snapd.socket || true
    for i in {1..15}; do snap version >/dev/null 2>&1 && break || sleep 1; done
    snap install core >/dev/null 2>&1 || true
    snap install --classic certbot >/dev/null 2>&1 || true
    ln -sf /snap/bin/certbot /usr/bin/certbot
    [ -d /etc/letsencrypt/accounts ] && rm -rf /etc/letsencrypt/accounts/*/* 2>/dev/null || true

    mkdir -p /etc/letsencrypt
    cat << EOF > /etc/letsencrypt/cli.ini
email = ${LE_EMAIL:-admin@$PRIMARY_DOMAIN}
agree-tos = true
non-interactive = true
EOF

    for dom in "${ALL_DOMAINS[@]}"; do
        log "Выпуск сертификата для $dom..."
        if certbot certonly --webroot -w "$WEBROOT" --cert-name "$dom" --expand --non-interactive --agree-tos -d "$dom"; then
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
    log "Выпуск SSL через acme.sh..."
    curl -s https://get.acme.sh | sh -s email="${LE_EMAIL:-admin@$PRIMARY_DOMAIN}"
    _ACME="${HOME:-/root}/.acme.sh/acme.sh"
    chmod +x "$_ACME"
    "$_ACME" --register-account -m "${LE_EMAIL:-admin@$PRIMARY_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true
    mkdir -p /etc/ssl/acme
    chmod 755 /etc/ssl /etc/ssl/acme

    for dom in "${ALL_DOMAINS[@]}"; do
        if "$_ACME" --issue --dns dns_cf -d "$dom" --server letsencrypt --force; then
            mkdir -p "/etc/ssl/acme/$dom"
            "$_ACME" --install-cert -d "$dom" \
                --key-file "/etc/ssl/acme/$dom/privkey.pem" \
                --fullchain-file "/etc/ssl/acme/$dom/fullchain.pem" \
                --reloadcmd "chmod 755 /etc/ssl/acme/$dom; chmod 644 /etc/ssl/acme/$dom/*; systemctl reload nginx"
            ok "Сертификат для $dom получен: /etc/ssl/acme/$dom/"
        fi
    done
fi

chmod 755 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
chmod 644 /etc/letsencrypt/live/*/* 2>/dev/null || true

# =============================================================
#  ЭТАП 6: ADGUARD HOME DOH (ЕСЛИ ВКЛЮЧЕН)
# =============================================================
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
    echo
    log "Этап 6: Установка AdGuard Home (DoH + Split-DNS)..."

    mkdir -p /etc/systemd/resolved.conf.d
    cat << 'EOF' > /etc/systemd/resolved.conf.d/adguard.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8
DNSStubListener=no
EOF
    systemctl restart systemd-resolved || true
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) AGH_ARCH="amd64" ;;
        aarch64|arm64) AGH_ARCH="arm64" ;;
        *) AGH_ARCH="amd64" ;;
    esac

    curl -fsSL "https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${AGH_ARCH}.tar.gz" -o /tmp/agh.tar.gz || \
        curl -fsSL "https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${AGH_ARCH}.tar.gz" -o /tmp/agh.tar.gz
    tar -zxvf /tmp/agh.tar.gz -C /opt/ >/dev/null
    rm -f /tmp/agh.tar.gz

    AGH_PASS_HASH=$(htpasswd -b -n -B -C 10 "" "$AGH_PASS" | tr -d '\n' | cut -d: -f2)

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
    - "quic://dns.alidns.com:853"
    - "[/ru/kz/by/su/xn--p1ai/]https://77.88.8.8:443/dns-query"
    - "quic://dns.adguard-dns.com"
    - "quic://dns.nextdns.io"
    - "quic://p0.freedns.controld.com"
    - "quic://dns.quad9.net"
    - "quic://doq.ffmuc.net"
    - "quic://dns.surfsharkdns.com"
    - "[/google.com/googlevideo.com/youtube.com/ytimg.com/gstatic.com/googleapis.com/1e100.net/]h3://dns.google/dns-query"
    - "h3://cloudflare-dns.com/dns-query"
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

    /opt/AdGuardHome/AdGuardHome -s install >/dev/null 2>&1 || true
    systemctl restart AdGuardHome || true
    ok "AdGuard Home DoH активен на 127.0.0.1:53 (Веб-панель: 127.0.0.1:3000)."
fi

# =============================================================
#  ЭТАП 7: ВЕБ-МАСКИРОВКА С АНТИ-ФИНГЕРПРИНТИНГОМ NGINX
# =============================================================
echo
log "Этап 7: Генерация веб-маскировки (Decoy Front) с защитой от отпечатков..."

if [ "$DECOY_MODE" = "1" ]; then
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DataSphere Analytics — Платформа распределенных данных</title>
    <style>
        :root { --bg: #131314; --surface-card: #1e1f20; --border: rgba(255, 255, 255, 0.08); --accent: #a8c7fa; --text: #e3e3e3; --text-muted: #9aa0a6; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); min-height: 100vh; }
        header { display: flex; justify-content: space-between; align-items: center; padding: 18px 6%; border-bottom: 1px solid var(--border); }
        .logo { font-size: 21px; font-weight: 700; color: #fff; }
        .btn { background: var(--surface-card); border: 1px solid var(--border); color: var(--text); padding: 10px 22px; border-radius: 999px; cursor: pointer; }
        .hero { text-align: center; padding: 90px 20px 70px; max-width: 900px; margin: 0 auto; }
        .hero h1 { font-size: 42px; margin-bottom: 20px; color: #fff; }
        .hero p { color: var(--text-muted); font-size: 18px; margin-bottom: 30px; }
        .stats { display: flex; justify-content: center; gap: 40px; margin-top: 40px; }
        .stat h4 { font-size: 28px; color: #fff; }
        .stat p { color: var(--text-muted); font-size: 13px; }
    </style>
</head>
<body>
    <header><div class="logo">DataSphere Analytics</div><button class="btn" onclick="alert('Доступ в консоль ограничен корпоративным шлюзом.')">Консоль</button></header>
    <main><section class="hero">
        <h1>Инфраструктура распределенных данных нового поколения</h1>
        <p>Корпоративная среда с аппаратным ускорением сетевого стека и защитой данных.</p>
        <div class="stats"><div class="stat"><h4 id="lat">&lt; 1.2 ms</h4><p>Задержка ядра</p></div><div class="stat"><h4 id="bw">100 Gbps</h4><p>Пропускная способность</p></div><div class="stat"><h4 id="sla">99.998%</h4><p>Доступность SLA</p></div></div>
    </section></main>
    <script>
        document.getElementById("lat").innerText = "< " + (1.1 + Math.random() * 0.2).toFixed(1) + " ms";
        document.getElementById("sla").innerText = (99.995 + Math.random() * 0.004).toFixed(3) + "%";
        document.cookie = "datasphere_session=" + Math.random().toString(36).substring(2) + "; path=/; Secure; SameSite=Lax";
    </script>
</body>
</html>
EOF
    DECOY_LOCATION_BLOCKS="
        location = / {
            default_type text/html;
            root $WEBROOT;
            add_header Last-Modified \$date_gmt always;
            add_header Cache-Control \"public, no-transform, max-age=86400\" always;
            try_files /index.html =404;
        }
        location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|webp)\$ {
            root $WEBROOT;
            expires 7d;
            access_log off;
            add_header Cache-Control \"public, max-age=604800, immutable\" always;
            try_files \$uri =404;
        }
        location / { return 404; }
    "
else
    cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html><html><head><title>Welcome to nginx!</title><style>body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }</style></head><body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working.</p></body></html>
EOF
    DECOY_LOCATION_BLOCKS="
        location = / { default_type text/html; root $WEBROOT; try_files /index.html =404; }
        location / { return 404; }
    "
fi

cat << 'EOF' > /var/www/html/404.html
<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><center><h1>404 Not Found</h1></center><hr><center>nginx</center></body></html>
EOF
chown -R "$NGINX_USER:$NGINX_USER" "$WEBROOT"
chmod 644 "$WEBROOT"/*.html

# =============================================================
#  ЭТАП 8: ПОЛНАЯ КОНФИГУРАЦИЯ NGINX (STREAM L4 + HTTP/2 L7)
# =============================================================
echo
log "Этап 8: Сборка L4/L7 маршрутизатора Nginx Mainline..."

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
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;

    http2_recv_buffer_size 16m;
    http2_max_concurrent_streams 512;

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
        ~^1:[01]:/sub/ 0;
        ~^1:[01]:/json/ 0;
        ~^1:[01]:/clash/ 0;
        ~^1:[01]:${XHTTP_STREAM_PATH} 0;
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

# 2. L4 Stream Router с сокетным L4 Failover
STREAM_MAP_RULES=""
REALITY_UPSTREAMS=""

for dom in "${ALL_DOMAINS[@]}"; do
    if [ "$dom" = "$PRIMARY_DOMAIN" ] || [ "$dom" = "www.$PRIMARY_DOMAIN" ] || [ "$dom" = "${AGH_DOMAIN:-}" ]; then
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

# 3. Виртуальный хост главного домена
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

    # Подписки: Base64, JSON, Clash
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

    # VLESS xHTTP (Native HTTP/2 Stream-One/Up + VLESSENC + Vision)
    location ^~ ${XHTTP_STREAM_PATH} {
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
        client_max_body_size 0;
        proxy_pass http://xray_xhttp_stream;
    }

    $DECOY_LOCATION_BLOCKS
}
EOF

# 4. Виртуальный хост для AdGuard Home (если включен)
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

# 5. Виртуальные хосты для ВСЕХ дополнительных доменов
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
}
EOF
    fi
done

nginx -t || die "Критическая ошибка синтаксиса Nginx!"
systemctl restart nginx
ok "Nginx Mainline успешно запущен."

# =============================================================
#  ЭТАП 9: ZERO-TOUCH СИНХРОНИЗАЦИЯ 3X-UI SQLITE (PYTHON RFC 7748)
# =============================================================
echo
log "Этап 9: Генерация инбаундов и Единого клиента в 3X-UI (Zero-Touch)..."

export DB_PATH PRIMARY_DOMAIN PANEL_PORT PANEL_PATH SUB_PORT SUB_PATH
export XHTTP_STREAM_PORT XHTTP_STREAM_PATH ENABLE_STEAL STEAL_PORT STEAL_DOM
export ENABLE_CLASSIC CLASSIC_PORT EXT_SNI ENABLE_HY2 HY2_PORT ENABLE_AWG_V3 AWG_V3_PORT
export ENABLE_AWG_V2 AWG_V2_PORT ADMIN_USER ADMIN_PASS SSL_BASE_DIR

python3 - << 'EOF_PY_ENGINE'
import os, sys, sqlite3, json, uuid, secrets, base64, time

db_path = os.environ["DB_PATH"]
conn = sqlite3.connect(db_path, timeout=30.0)
cur = conn.cursor()

# RFC 7748 Curve25519 для Reality и WireGuard
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
sub_json_path = "/" + sub_path.strip("/") + "json/"
xhttp_port = int(os.environ["XHTTP_STREAM_PORT"])
xhttp_path = os.environ["XHTTP_STREAM_PATH"]

admin_u = os.environ["ADMIN_USER"]
admin_p = os.environ["ADMIN_PASS"]

# Хеширование пароля через bcrypt (если модуль доступен)
hashed_p = admin_p
try:
    import bcrypt
    hashed_p = bcrypt.hashpw(admin_p.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
except Exception:
    pass

cur.execute("SELECT id FROM users LIMIT 1")
urow = cur.fetchone()
if urow:
    cur.execute("UPDATE users SET username = ?, password = ? WHERE id = ?", (admin_u, hashed_p, urow[0]))
    uid = urow[0]
else:
    cur.execute("INSERT INTO users (id, username, password) VALUES (1, ?, ?)", (admin_u, hashed_p))
    uid = 1

settings_data = {
    "webPort": panel_port, "webBasePath": panel_path, "webListen": "127.0.0.1",
    "subPort": sub_port, "subPath": sub_path, "subURI": f"https://{domain}{sub_path}",
    "subJsonPath": sub_json_path, "subJsonURI": f"https://{domain}{sub_json_path}",
    "subDomain": domain, "subCertFile": "", "subKeyFile": "",
    "subUpdates": "1", "subEncrypt": "true", "subShowInfo": "true",
    "timeLocation": "Europe/Moscow", "trafficResetDay": "1"
}
for k, v in settings_data.items():
    cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
    if cur.fetchone():
        cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

cur.execute("SELECT value FROM settings WHERE key = 'xrayTemplateConfig'")
tpl_row = cur.fetchone()
tpl = json.loads(tpl_row[0]) if tpl_row and tpl_row[0] else {}
if not tpl:
    tpl = {
        "log": {"loglevel": "warning"},
        "outbounds": [{"protocol": "freedom", "tag": "direct"}, {"protocol": "blackhole", "tag": "blocked"}],
        "routing": {"rules": []}
    }

rules = tpl.get("routing", {}).get("rules", [])
if not any("25" in str(r.get("port", "")) for r in rules if isinstance(r, dict)):
    rules.insert(0, {"type": "field", "port": "25", "outboundTag": "blocked"})
if not any("geoip:private" in str(r.get("ip", [])) for r in rules if isinstance(r, dict)):
    rules.insert(0, {"type": "field", "ip": ["geoip:private", "127.0.0.0/8", "10.0.0.0/8"], "outboundTag": "blocked"})

tpl.setdefault("routing", {})["rules"] = rules
cur.execute("UPDATE settings SET value = ? WHERE key = 'xrayTemplateConfig'", (json.dumps(tpl, indent=2),))

unified_uuid = str(uuid.uuid4())
unified_sub_id = secrets.token_hex(8)
unified_hy2_pass = secrets.token_hex(12)
def_r_priv, def_r_pub = gen_reality_keypair()
def_wg_s_priv, def_wg_s_pub = gen_wg_keypair()
def_wg_c_priv, def_wg_c_pub = gen_wg_keypair()
vlessenc_key = secrets.token_urlsafe(32)

def upsert_inbound(port, proto, tag, remark, s_obj, st_obj, listen="127.0.0.1"):
    s_json = json.dumps(s_obj, ensure_ascii=False)
    st_json = json.dumps(st_obj, ensure_ascii=False)
    sniff = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})
    cur.execute("SELECT id FROM inbounds WHERE port = ? OR tag = ?", (port, tag))
    row = cur.fetchone()
    if row:
        cur.execute("UPDATE inbounds SET protocol=?, tag=?, remark=?, settings=?, stream_settings=?, listen=?, sniffing=?, enable=1 WHERE id=?",
                    (proto, tag, remark, s_json, st_json, listen, sniff, row[0]))
    else:
        cur.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?)",
                    (uid, remark, listen, port, proto, s_json, st_json, tag, sniff))

# 1. Steal Reality
if os.environ.get("ENABLE_STEAL") == "1":
    p = int(os.environ["STEAL_PORT"])
    s_dom = os.environ["STEAL_DOM"]
    s_obj = {"clients": [{"id": unified_uuid, "flow": "xtls-rprx-vision", "email": "Client-Unified", "subId": unified_sub_id, "enable": True}], "decryption": "none"}
    st_obj = {
        "network": "tcp", "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False, "xver": 1, "dest": "127.0.0.1:9443", "serverNames": [s_dom],
            "privateKey": def_r_priv, "shortIds": [unified_sub_id],
            "settings": {"publicKey": def_r_pub, "fingerprint": "chrome", "spiderX": f"/{unified_sub_id}"}
        },
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": "VLESS Steal"}]
    }
    upsert_inbound(p, "vless", "in-steal-reality", "VLESS Steal", s_obj, st_obj)

# 2. Classic Reality
if os.environ.get("ENABLE_CLASSIC") == "1":
    p = int(os.environ["CLASSIC_PORT"])
    ext_sni = os.environ["EXT_SNI"]
    c_obj = {"clients": [{"id": unified_uuid, "flow": "xtls-rprx-vision", "email": "Client-Unified", "subId": unified_sub_id, "enable": True}], "decryption": "none"}
    ct_obj = {
        "network": "tcp", "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False, "xver": 0, "dest": f"{ext_sni}:443", "serverNames": [ext_sni],
            "privateKey": def_r_priv, "shortIds": [unified_sub_id],
            "settings": {"publicKey": def_r_pub, "fingerprint": "chrome", "spiderX": f"/{unified_sub_id}"}
        },
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": "VLESS Classic"}]
    }
    upsert_inbound(p, "vless", "in-classic-reality", "VLESS Classic", c_obj, ct_obj)

# 3. VLESS xHTTP (Stream-One/Up + VLESSENC + Vision)
x_obj = {"clients": [{"id": unified_uuid, "flow": "xtls-rprx-vision", "email": "Client-Unified", "subId": unified_sub_id, "enable": True}], "decryption": vlessenc_key}
xt_obj = {
    "network": "xhttp",
    "xhttpSettings": {
        "path": xhttp_path, "host": domain, "mode": "stream-one", "noSSEHeader": True,
        "xPaddingBytes": "100-500", "xPaddingObfsMode": True, "xPaddingKey": "X-Amz-Meta-Trace",
        "xmux": {"maxConcurrency": "0", "maxConnections": "1-3", "cMaxReuseTimes": "300-600", "hKeepAlivePeriod": 600}
    },
    "security": "none",
    "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "chrome", "remark": "VLESS xHTTP"}]
}
upsert_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS xHTTP", x_obj, xt_obj)

# 4. Hysteria 2
if os.environ.get("ENABLE_HY2") == "1":
    hp = int(os.environ["HY2_PORT"])
    ssl_dir = os.environ["SSL_BASE_DIR"]
    h_obj = {"clients": [{"id": unified_hy2_pass, "auth": unified_hy2_pass, "email": "Client-Unified", "subId": unified_sub_id, "enable": True}], "version": 2}
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
    upsert_inbound(hp, "hysteria", "in-hysteria2", "Hysteria 2", h_obj, ht_obj, listen="0.0.0.0")

# 5. AmneziaWG v3.1 (WG3) - Безопасный MTU 1320 (компенсация ContentPaddingAddition)
if os.environ.get("ENABLE_AWG_V3") == "1":
    a3p = int(os.environ["AWG_V3_PORT"])
    a3_obj = {
        "clients": [{"privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub, "allowedIPs": ["10.8.1.2/32"], "email": "Client-Unified", "subId": unified_sub_id, "enable": True}],
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
    upsert_inbound(a3p, "amneziawg", "in-8443-udp", "AmneziaWG v3", a3_obj, a3t_obj, listen="0.0.0.0")

# 6. AmneziaWG v2.0 (Legacy)
if os.environ.get("ENABLE_AWG_V2") == "1":
    a2p = int(os.environ["AWG_V2_PORT"])
    a2_obj = {
        "clients": [{"privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub, "allowedIPs": ["10.8.2.2/32"], "email": "Client-Unified", "subId": unified_sub_id, "enable": True}],
        "server": {
            "h1": "149419586", "h2": "878791997", "h3": "1251051976", "h4": "1657628296",
            "jc": 4, "jmin": 50, "jmax": 160, "s1": 45, "s2": 60, "s3": 24, "s4": 16, "mtu": 1360,
            "primaryDns": "8.8.8.8", "secondaryDns": "8.8.4.4",
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "subnetCidr": 24, "subnetIp": "10.8.2.0"
        }
    }
    a2t_obj = {"externalProxy": [{"dest": domain, "port": a2p, "remark": "AmneziaWG v2"}]}
    upsert_inbound(a2p, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2", a2_obj, a2t_obj, listen="0.0.0.0")

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = set(r[0] for r in cur.fetchall())
if "client_traffics" in tables:
    cur.execute("SELECT id FROM client_traffics WHERE email = 'Client-Unified'")
    if not cur.fetchone():
        cur.execute("INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (1, 1, 'Client-Unified', 0, 0, 0, 0, 0)")

conn.commit()
conn.close()

with open("/tmp/vpn_unified_creds.txt", "w") as f:
    f.write(f"UNIFIED_SUB_ID={unified_sub_id}\n")
    f.write(f"UNIFIED_UUID={unified_uuid}\n")
EOF_PY_ENGINE

# Синхронизация логина и пароля через бинарник x-ui для сброса токенов входа
XUI_CLI=""
for c in "/usr/local/x-ui/x-ui" "/usr/bin/x-ui"; do
    [ -x "$c" ] && XUI_CLI="$c" && break
done
if [ -n "$XUI_CLI" ]; then
    "$XUI_CLI" setting -username "$ADMIN_USER" -password "$ADMIN_PASS" >/dev/null 2>&1 || true
fi

systemctl restart x-ui
ok "Служба 3X-UI перезапущена со всеми инбаундами и Единым клиентом."

UNIFIED_SUB_ID=""
if [ -f "/tmp/vpn_unified_creds.txt" ]; then
    . /tmp/vpn_unified_creds.txt
    rm -f /tmp/vpn_unified_creds.txt
fi

# =============================================================
#  ЭТАП 10: PORT HOPPING, TCP MSS CLAMPING И ФАЕРВОЛ UFW
# =============================================================
echo
log "Этап 10: Настройка Port Hopping, TCP MSS Clamping и фаервола UFW..."

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

# 1. Port Hopping для Hysteria 2 (UDP 20000:50000 -> HY2_PORT)
if [ "${ENABLE_HY2:-0}" -eq 1 ]; then
    log "Активация Port Hopping для Hysteria 2 (UDP 20000:50000)..."
    ufw allow 20000:50000/udp comment 'Hy2 Port Hopping' >/dev/null 2>&1 || true

    iptables -t nat -C PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports "$HY2_PORT" 2>/dev/null || \
        iptables -t nat -A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports "$HY2_PORT"

    if ! grep -q "Hy2 Port Hopping" /etc/ufw/before.rules 2>/dev/null; then
        sed -i '1i *nat\n:PREROUTING ACCEPT [0:0]\n-A PREROUTING -p udp --dport 20000:50000 -j REDIRECT --to-ports '"$HY2_PORT"' # Hy2 Port Hopping\nCOMMIT\n' /etc/ufw/before.rules
    fi
fi

# 2. TCP MSS Clamping в таблице mangle
log "Активация TCP MSS Clamping (--clamp-mss-to-pmtu)..."
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

if ! grep -q "TCPMSS --clamp-mss-to-pmtu" /etc/ufw/before.rules 2>/dev/null; then
    cat << 'EOF_MANGLE' >> /etc/ufw/before.rules
*mangle
:FORWARD ACCEPT [0:0]
-A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
COMMIT
EOF_MANGLE
fi

# Изоляция внутренних портов
DENIED_PORTS=(10443 55443 50443 9443 45443 46443 3000)
for dp in "${DENIED_PORTS[@]}"; do
    ufw deny "${dp}/tcp" >/dev/null 2>&1 || true
done

if [ "${BLOCK_PING:-0}" -eq 1 ] && [ -f /etc/ufw/before.rules ]; then
    sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
fi

ufw --force enable >/dev/null 2>&1 || true
ok "Фаервол UFW активен. Port Hopping и MSS Clamping настроены."

# =============================================================
#  ЭТАП 11: АВТООБНОВЛЕНИЕ GEOSITE И GEOIP ПО РАСПИСАНИЮ
# =============================================================
echo
log "Этап 11: Настройка службы автоматического обновления баз geosite/geoip..."

cat << 'EOF' > /usr/local/bin/update-xray-geo.sh
#!/bin/bash
set -e
GEO_DIR="/usr/local/x-ui/bin"
[ -d "$GEO_DIR" ] || GEO_DIR="/etc/x-ui/bin"
mkdir -p "$GEO_DIR"

curl -fsSL --connect-timeout 15 "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" -o "$GEO_DIR/geosite.dat.tmp" 2>/dev/null || true
curl -fsSL --connect-timeout 15 "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" -o "$GEO_DIR/geoip.dat.tmp" 2>/dev/null || true

if [ -s "$GEO_DIR/geosite.dat.tmp" ]; then
    mv -f "$GEO_DIR/geosite.dat.tmp" "$GEO_DIR/geosite.dat"
fi
if [ -s "$GEO_DIR/geoip.dat.tmp" ]; then
    mv -f "$GEO_DIR/geoip.dat.tmp" "$GEO_DIR/geoip.dat"
fi
systemctl restart x-ui >/dev/null 2>&1 || true
EOF
chmod +x /usr/local/bin/update-xray-geo.sh

cat << 'EOF' > /etc/systemd/system/xray-geo-update.service
[Unit]
Description=Weekly update of Xray GeoSite and GeoIP databases
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-xray-geo.sh
EOF

cat << 'EOF' > /etc/systemd/system/xray-geo-update.timer
[Unit]
Description=Weekly timer for Xray GeoSite and GeoIP databases update

[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now xray-geo-update.timer >/dev/null 2>&1 || true
ok "Таймер еженедельного обновления geosite.dat и geoip.dat активен."

# =============================================================
#  ФИНАЛ: СОХРАНЕНИЕ УЧЕТНЫХ ДАННЫХ И ВЫВОД ДАШБОРДА
# =============================================================
CRED_FILE="/root/vpn_credentials.txt"
cat << EOF > "$CRED_FILE"
=====================================================================
  УЧЕТНЫЕ ДАННЫЕ ВАШЕГО СЕРВЕРА (All-in-One v7.1.0 Beta 2 Universal)
  Дата развертывания: $(date '+%Y-%m-%d %H:%M:%S')
=====================================================================

[ ВЕБ-ПАНЕЛЬ 3X-UI ]
URL панели:            https://${PRIMARY_DOMAIN}${PANEL_PATH}
Логин администратора:  ${ADMIN_USER}
Пароль администратора: ${ADMIN_PASS}
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
[ ПОДПИСКИ КЛИЕНТОВ ]
Единый клиент:         Client-Unified (все 6 протоколов в 1 ссылке)
Прямая ссылка (Base64):https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}
Прямая ссылка (JSON):  https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}
(Для Happ Proxy, Streisand, FoXray, Karing, NekoBox, v2rayNG)

[ НОВЫЕ ТЕХНОЛОГИИ BETA 2 ]
Port Hopping (Hy2):    ${PRIMARY_DOMAIN}:443,20000-50000
TCP MSS Clamping:      Активирован (защита мобильного интернета)
Classic Reality SNI:   ${EXT_SNI} (Выбран по минимальному RTT)
Geo-базы:              Автообновление каждое воскресенье в 03:30

[ СЕТЕВЫЕ ПАРАМЕТРЫ ]
SSH порт:              ${TARGET_SSH_PORT}
Основной домен:        ${PRIMARY_DOMAIN}
Сайт-маскировка:       https://${PRIMARY_DOMAIN}/
=====================================================================
EOF
chmod 600 "$CRED_FILE"

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}  СИСТЕМА УСПЕШНО РАЗВЕРНУТА И ГОТОВА К РАБОТЕ (BETA 2 v7.1.0)!     ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  Панель управления 3X-UI:     ${CYAN}https://${PRIMARY_DOMAIN}${PANEL_PATH}${NC}"
echo -e "  Логин: ${WHITE}${ADMIN_USER}${NC} | Пароль: ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
echo
if [ "${ENABLE_AGH:-0}" -eq 1 ]; then
echo -e "  Панель AdGuard Home:         ${CYAN}https://${AGH_DOMAIN}/${NC}"
echo -e "  Приватный DoH для роутера:   ${GREEN}https://${AGH_DOMAIN}/dns-query/${AGH_CLIENT_ID}${NC}"
echo
fi
echo -e "  ${BOLD}Единая ссылка подписки (Base64):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${BOLD}Единая ссылка подписки (JSON для Happ/Streisand/NekoBox):${NC}"
echo -e "  ${GREEN}https://${PRIMARY_DOMAIN}${SUB_JSON_PATH}${UNIFIED_SUB_ID}${NC}"
echo
echo -e "  ${WHITE}Port Hopping (Hysteria 2):${NC}    ${CYAN}${PRIMARY_DOMAIN}:443,20000-50000${NC}"
echo -e "  ${WHITE}Выбранный SNI для Reality:${NC}    ${CYAN}${EXT_SNI}${NC}"
echo
echo -e "  Все доступы сохранены в файл: ${CYAN}${CRED_FILE}${NC} (chmod 600)"
echo -e "${GREEN}=====================================================================${NC}"

exit 0
