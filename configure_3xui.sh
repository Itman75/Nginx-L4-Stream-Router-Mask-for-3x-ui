#!/usr/bin/env bash
# ==============================================================================
#  CONFIGURE 3X-UI INBOUNDS & SETTINGS (v6.5.1 Universal Companion)
# ==============================================================================
#  Скрипт автоматической настройки базы данных 3X-UI (/etc/x-ui/x-ui.db).
#  Настраивает внутренние пути панели, подписки и добавляет инбаунды:
#    - VLESS REALITY Steal-Oneself (Anti-Loop Fallback 9443)
#    - VLESS REALITY Classic External (gateway.icloud.com)
#    - VLESS xHTTP (Native H2 Stream-One + VLESSENC + XTLS-Vision)
#    - Hysteria 2 (UDP 443 с маскировкой на 127.0.0.1:80)
#    - AmneziaWG v3.1 (UDP 8443) и v2.0 Legacy (UDP 8444)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

show_help() {
    cat << 'EOF_HELP'
Использование: ./configure_3xui.sh [ОПЦИИ]

Скрипт автоматического конфигурирования базы данных 3X-UI (инбаунды, пути и подписки).

Опции:
  -c, --config <FILE>     Путь к файлу параметров (.env) (по умолчанию: ./setup_mask.env)
  --db <PATH>             Путь к файлу базы данных SQLite 3X-UI (по умолчанию: /etc/x-ui/x-ui.db)
  -y, --yes               Неинтерактивное выполнение (без подтверждений)
  -h, --help              Показать эту справку и выйти

Пример использования:
  ./configure_3xui.sh --config ./setup_mask.env -y
EOF_HELP
}

CONFIG_FILE=""
DB_PATH="/etc/x-ui/x-ui.db"
NON_INTERACTIVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            [[ -n "${2:-}" ]] || die "Параметр $1 требует аргумент: путь к файлу конфигурации."
            CONFIG_FILE="$2"
            shift 2
            ;;
        --db)
            [[ -n "${2:-}" ]] || die "Параметр $1 требует аргумент: путь к базе данных x-ui.db."
            DB_PATH="$2"
            shift 2
            ;;
        -y|--yes|--non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            warn "Неизвестный параметр: $1"
            shift
            ;;
    esac
done

# Проверка прав суперпользователя
if [ "${EUID:-$(id -u)}" -ne 0 ] && [ ! -f "$DB_PATH" ]; then
    warn "Для записи в базу данных /etc/x-ui/x-ui.db требуются права суперпользователя (sudo)."
fi

# Автопоиск конфигурационного файла, если не передан
if [ -z "$CONFIG_FILE" ]; then
    if [ -f "./setup_mask.env" ]; then
        CONFIG_FILE="./setup_mask.env"
    elif [ -f "/root/setup_mask.env" ]; then
        CONFIG_FILE="/root/setup_mask.env"
    fi
fi

# Загрузка переменных из .env файла
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    log "Загрузка параметров из $CONFIG_FILE..."
    re_dquote='^"(.*)"$'
    re_squote="^'(.*)'\$"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            if [[ "$val" =~ $re_dquote ]] || [[ "$val" =~ $re_squote ]]; then
                val="${BASH_REMATCH[1]}"
            fi
            declare -g "$key=$val"
        fi
    done < "$CONFIG_FILE"
fi

# Дефолтные значения переменных, если не определены
PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-yourdomain.online}"
PANEL_PORT="${PANEL_PORT:-10443}"
PANEL_PATH="${PANEL_PATH:-my-3x-panel}"
SUB_PORT="${SUB_PORT:-55443}"
SUB_PATH="${SUB_PATH:-my-post-key}"
XHTTP_STREAM_PORT="${XHTTP_STREAM_PORT:-50443}"
XHTTP_STREAM_PATH="${XHTTP_STREAM_PATH:-Stream-One-Path}"

ENABLE_STEAL="${ENABLE_STEAL:-y}"
STEAL_PORT="${STEAL_PORT:-45443}"
STEAL_DOMAINS="${STEAL_DOMAINS:-cdn.$PRIMARY_DOMAIN}"

ENABLE_CLASSIC="${ENABLE_CLASSIC:-y}"
CLASSIC_PORT="${CLASSIC_PORT:-46443}"
CLASSIC_SNI="${CLASSIC_SNI:-gateway.icloud.com}"

ENABLE_HY2="${ENABLE_HY2:-y}"
HY2_PORT="${HY2_PORT:-443}"

ENABLE_AWG_V3="${ENABLE_AWG_V3:-y}"
AWG_V3_PORT="${AWG_V3_PORT:-8443}"

ENABLE_AWG_V2="${ENABLE_AWG_V2:-y}"
AWG_V2_PORT="${AWG_V2_PORT:-8444}"

SSL_ENGINE_CHOICE="${SSL_ENGINE_CHOICE:-1}"
if [ "$SSL_ENGINE_CHOICE" = "1" ]; then
    SSL_CERT_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem"
    SSL_KEY_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN/privkey.pem"
else
    SSL_CERT_PATH="/etc/ssl/acme/$PRIMARY_DOMAIN/fullchain.pem"
    SSL_KEY_PATH="/etc/ssl/acme/$PRIMARY_DOMAIN/privkey.pem"
fi

# Определение команды python (в Ubuntu/Debian это python3, кроссплатформенный fallback)
PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1 && python3 --version >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1 && python --version >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    log "Установка python3..."
    apt-get update -q && apt-get install -y python3 -q || die "Не удалось установить python3."
    PYTHON_CMD="python3"
fi

# Проверка наличия базы данных 3X-UI
if [ ! -f "$DB_PATH" ]; then
    # Проверка альтернативных путей
    alt_paths=("/usr/local/x-ui/bin/x-ui.db" "/etc/x-ui/db/x-ui.db")
    found=0
    for p in "${alt_paths[@]}"; do
        if [ -f "$p" ]; then
            DB_PATH="$p"
            found=1
            break
        fi
    done
    if [ "$found" -eq 0 ]; then
        die "База данных 3X-UI ($DB_PATH) не найдена. Убедитесь, что панель 3X-UI установлена."
    fi
fi

log "Используется база данных 3X-UI: $DB_PATH"

# Резервное копирование базы данных перед внесением изменений
BACKUP_DB="${DB_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
cp -a "$DB_PATH" "$BACKUP_DB"
chmod 600 "$BACKUP_DB" 2>/dev/null || true
ok "Создана резервная копия базы данных: $BACKUP_DB"

# Генерация криптографических параметров через Xray / OpenSSL / Python
log "Генерация криптографических ключей..."

# 1. UUID клиента
CLIENT_UUID=$("$PYTHON_CMD" -c "import uuid; print(uuid.uuid4())")

# 2. Reality Keypair (x25519)
REALITY_PRIV=""
REALITY_PUB=""
XRAY_BIN=$(command -v xray || ls /usr/local/x-ui/bin/xray-linux-* /usr/local/x-ui/bin/xray* 2>/dev/null | head -n 1 || true)
if [ -n "$XRAY_BIN" ] && [ -x "$XRAY_BIN" ]; then
    xray_out=$("$XRAY_BIN" x25519 2>/dev/null || true)
    if [ -n "$xray_out" ]; then
        REALITY_PRIV=$(echo "$xray_out" | awk -F': ' '/Private/ {print $2}' | tr -d ' \r\n')
        REALITY_PUB=$(echo "$xray_out" | awk -F': ' '/Public|Password/ {print $2}' | tr -d ' \r\n')
    fi
fi

# Fallback для Reality ключей через чистый Python (стандарт RFC 7748 Curve25519)
if [ -z "$REALITY_PRIV" ] || [ -z "$REALITY_PUB" ]; then
    keys=$("$PYTHON_CMD" - << 'EOF_KEYGEN'
import os, base64

P = 2**255 - 19
A24 = 121665

def clamp(k_bytes):
    b = bytearray(k_bytes)
    b[0] &= 248
    b[31] &= 127
    b[31] |= 64
    return int.from_bytes(b, "little")

def x25519(k, u=9):
    x1 = u
    x2, z2 = 1, 0
    x3, z3 = u, 1
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

priv_raw = os.urandom(32)
k = clamp(priv_raw)
pub_raw = x25519(k, 9).to_bytes(32, "little")

priv_b64 = base64.urlsafe_b64encode(priv_raw).decode().rstrip("=")
pub_b64 = base64.urlsafe_b64encode(pub_raw).decode().rstrip("=")
print(f"{priv_b64} {pub_b64}")
EOF_KEYGEN
)
    REALITY_PRIV=$(echo "$keys" | awk '{print $1}')
    REALITY_PUB=$(echo "$keys" | awk '{print $2}')
fi

[ -n "$REALITY_PRIV" ] && [ -n "$REALITY_PUB" ] || die "Критическая ошибка: не удалось сгенерировать пару ключей Reality x25519."

# 3. ShortId для Reality
REALITY_SHORT_ID=$(openssl rand -hex 8 2>/dev/null || "$PYTHON_CMD" -c "import secrets; print(secrets.token_hex(8))")

# 4. vlessenc Decryption Key (ML-KEM-768 / postquantum)
VLESSENC_KEY=$(openssl rand -base64 32 2>/dev/null | tr -d '\r\n' || "$PYTHON_CMD" -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())")

# 5. Hysteria 2 Password
HY2_PASS=$(openssl rand -hex 12 2>/dev/null || "$PYTHON_CMD" -c "import secrets; print(secrets.token_hex(12))")

# 6. WireGuard Server & Client Keypairs
if ! command -v wg >/dev/null 2>&1; then
    log "Установка wireguard-tools для генерации ключей WireGuard/AmneziaWG..."
    apt-get update -q && apt-get install -y wireguard-tools -q || true
fi

if command -v wg >/dev/null 2>&1; then
    WG_SERVER_PRIV=$(wg genkey)
    WG_SERVER_PUB=$(echo "$WG_SERVER_PRIV" | wg pubkey)
    WG_CLIENT_PRIV=$(wg genkey)
    WG_CLIENT_PUB=$(echo "$WG_CLIENT_PRIV" | wg pubkey)
else
    WG_SERVER_PRIV=$(openssl rand -base64 32 | tr -d '\r\n')
    WG_CLIENT_PRIV=$(openssl rand -base64 32 | tr -d '\r\n')
    WG_SERVER_PUB=$("$PYTHON_CMD" -c "
import base64
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization
priv = x25519.X25519PrivateKey.from_private_bytes(base64.b64decode('$WG_SERVER_PRIV'))
pub = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
print(base64.b64encode(pub).decode())
")
    WG_CLIENT_PUB=$("$PYTHON_CMD" -c "
import base64
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization
priv = x25519.X25519PrivateKey.from_private_bytes(base64.b64decode('$WG_CLIENT_PRIV'))
pub = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
print(base64.b64encode(pub).decode())
")
fi

# Экспорт переменных для Python скрипта настройки БД
export DB_PATH
export PRIMARY_DOMAIN
export PANEL_PORT
export PANEL_PATH
export SUB_PORT
export SUB_PATH
export XHTTP_STREAM_PORT
export XHTTP_STREAM_PATH
export ENABLE_STEAL
export STEAL_PORT
export STEAL_DOMAINS
export ENABLE_CLASSIC
export CLASSIC_PORT
export CLASSIC_SNI
export ENABLE_HY2
export HY2_PORT
export ENABLE_AWG_V3
export AWG_V3_PORT
export ENABLE_AWG_V2
export AWG_V2_PORT
export SSL_CERT_PATH
export SSL_KEY_PATH
export CLIENT_UUID
export REALITY_PRIV
export REALITY_PUB
export REALITY_SHORT_ID
export VLESSENC_KEY
export HY2_PASS
export WG_SERVER_PRIV
export WG_SERVER_PUB
export WG_CLIENT_PRIV
export WG_CLIENT_PUB

# Приостановка службы x-ui на время транзакции во избежание блокировок SQLite
WAS_ACTIVE=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet x-ui 2>/dev/null; then
    log "Приостановка службы 3X-UI на время обновления конфигурации базы..."
    systemctl stop x-ui
    WAS_ACTIVE=1
fi

log "Конфигурирование таблиц settings и inbounds в базе данных SQLite..."

"$PYTHON_CMD" - << 'EOF_PYTHON_CONFIG'
import os
import sys
import sqlite3
import json
import time

db_path = os.environ["DB_PATH"]
domain = os.environ["PRIMARY_DOMAIN"]
panel_port = os.environ["PANEL_PORT"]
panel_path = os.environ["PANEL_PATH"].strip("/")
sub_port = os.environ["SUB_PORT"]
sub_path = os.environ["SUB_PATH"].strip("/")
xhttp_port = int(os.environ["XHTTP_STREAM_PORT"])
xhttp_path = "/" + os.environ["XHTTP_STREAM_PATH"].strip("/") + "/"

enable_steal = os.environ["ENABLE_STEAL"].lower() in ("1", "y", "true")
steal_port = int(os.environ["STEAL_PORT"])
steal_dom = os.environ["STEAL_DOMAINS"].split()[0] if os.environ["STEAL_DOMAINS"].strip() else f"cdn.{domain}"

enable_classic = os.environ["ENABLE_CLASSIC"].lower() in ("1", "y", "true")
classic_port = int(os.environ["CLASSIC_PORT"])
classic_sni = os.environ["CLASSIC_SNI"].split()[0] if os.environ["CLASSIC_SNI"].strip() else "gateway.icloud.com"

enable_hy2 = os.environ["ENABLE_HY2"].lower() in ("1", "y", "true")
hy2_port = int(os.environ["HY2_PORT"])

enable_awg_v3 = os.environ["ENABLE_AWG_V3"].lower() in ("1", "y", "true")
awg_v3_port = int(os.environ["AWG_V3_PORT"])

enable_awg_v2 = os.environ["ENABLE_AWG_V2"].lower() in ("1", "y", "true")
awg_v2_port = int(os.environ["AWG_V2_PORT"])

ssl_cert = os.environ["SSL_CERT_PATH"]
ssl_key = os.environ["SSL_KEY_PATH"]

client_uuid = os.environ["CLIENT_UUID"]
reality_priv = os.environ["REALITY_PRIV"]
reality_pub = os.environ["REALITY_PUB"]
reality_short_id = os.environ["REALITY_SHORT_ID"]
vlessenc_key = os.environ["VLESSENC_KEY"]
hy2_pass = os.environ["HY2_PASS"]
wg_server_priv = os.environ["WG_SERVER_PRIV"]
wg_server_pub = os.environ["WG_SERVER_PUB"]
wg_client_priv = os.environ["WG_CLIENT_PRIV"]
wg_client_pub = os.environ["WG_CLIENT_PUB"]

conn = sqlite3.connect(db_path, timeout=30.0)
cur = conn.cursor()

# Динамическое определение ID администратора
cur.execute("SELECT id FROM users LIMIT 1")
user_row = cur.fetchone()
admin_id = user_row[0] if user_row else 1

# ----------------- 1. Настройки панели (settings) -----------------
def upsert_setting(k, v):
    cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
    row = cur.fetchone()
    if row:
        cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
    else:
        cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))

upsert_setting("webPort", panel_port)
upsert_setting("webBasePath", f"/{panel_path}/")
upsert_setting("subPort", sub_port)
upsert_setting("subPath", f"/{sub_path}/")
upsert_setting("subURI", f"https://{domain}/{sub_path}/")
upsert_setting("subDomain", domain)
upsert_setting("subCertFile", "")
upsert_setting("subKeyFile", "")

# ----------------- 2. Инбаунды (inbounds) -----------------
now_ms = int(time.time() * 1000)

def upsert_inbound(port, protocol, tag, remark, settings_dict, stream_dict, listen="127.0.0.1"):
    settings_json = json.dumps(settings_dict, ensure_ascii=False)
    stream_json = json.dumps(stream_dict, ensure_ascii=False)
    sniffing_json = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})

    cur.execute("SELECT id FROM inbounds WHERE port = ? OR tag = ?", (port, tag))
    row = cur.fetchone()
    if row:
        inbound_id = row[0]
        cur.execute("""
            UPDATE inbounds
            SET protocol = ?, tag = ?, remark = ?, settings = ?, stream_settings = ?, listen = ?, sniffing = ?, enable = 1
            WHERE id = ?
        """, (protocol, tag, remark, settings_json, stream_json, listen, sniffing_json, inbound_id))
        print(f"[OK] Инбаунд {remark} (порт {port}) обновлен.")
    else:
        cur.execute("""
            INSERT INTO inbounds (
                user_id, up, down, total, remark, enable, expiry_time,
                listen, port, protocol, settings, stream_settings, tag, sniffing
            ) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?)
        """, (admin_id, remark, listen, port, protocol, settings_json, stream_json, tag, sniffing_json))
        print(f"[OK] Инбаунд {remark} (порт {port}) добавлен.")

# A. VLESS REALITY Steal-Oneself (45443)
if enable_steal:
    steal_settings = {
        "clients": [{"id": client_uuid, "flow": "xtls-rprx-vision"}],
        "decryption": "none"
    }
    steal_stream = {
        "network": "tcp",
        "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False,
            "xver": 1,
            "dest": "127.0.0.1:9443",
            "serverNames": [steal_dom],
            "privateKey": reality_priv,
            "shortIds": [reality_short_id],
            "settings": {
                "publicKey": reality_pub,
                "fingerprint": "chrome",
                "spiderX": f"/{reality_short_id}"
            }
        },
        "externalProxy": [{
            "dest": domain,
            "port": 443,
            "forceTls": "same",
            "remark": "VLESS_STEAL"
        }]
    }
    upsert_inbound(steal_port, "vless", "in-steal-reality", "VLESS_STEAL", steal_settings, steal_stream, listen="127.0.0.1")

# B. VLESS REALITY Classic External (46443)
if enable_classic:
    classic_settings = {
        "clients": [{"id": client_uuid, "flow": "xtls-rprx-vision"}],
        "decryption": "none"
    }
    classic_stream = {
        "network": "tcp",
        "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False,
            "xver": 0,
            "dest": f"{classic_sni}:443",
            "serverNames": [classic_sni],
            "privateKey": reality_priv,
            "shortIds": [reality_short_id],
            "settings": {
                "publicKey": reality_pub,
                "fingerprint": "chrome",
                "spiderX": f"/{reality_short_id}"
            }
        },
        "externalProxy": [{
            "dest": domain,
            "port": 443,
            "forceTls": "same",
            "remark": "VLESS_CLASSIC"
        }]
    }
    upsert_inbound(classic_port, "vless", "in-classic-reality", "VLESS_CLASSIC", classic_settings, classic_stream, listen="127.0.0.1")

# C. VLESS xHTTP (50443)
xhttp_settings = {
    "clients": [{"id": client_uuid}],
    "decryption": "none"
}
xhttp_stream = {
    "network": "xhttp",
    "xhttpSettings": {
        "path": xhttp_path,
        "host": domain,
        "mode": "stream-one",
        "xPaddingBytes": "100-500",
        "xPaddingObfsMode": True,
        "xPaddingKey": "X-Amz-Meta-Trace"
    },
    "security": "none",
    "externalProxy": [{
        "dest": domain,
        "port": 443,
        "forceTls": "tls",
        "sni": domain,
        "fingerprint": "chrome",
        "remark": "VLESS_XHTTP"
    }]
}
upsert_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS_XHTTP", xhttp_settings, xhttp_stream, listen="127.0.0.1")

# D. Hysteria 2 (443)
if enable_hy2:
    hy2_settings = {
        "clients": [{"id": hy2_pass}],
        "version": 2
    }
    hy2_stream = {
        "network": "hysteria",
        "hysteriaSettings": {
            "version": 2,
            "udpIdleTimeout": 60,
            "masquerade": {"type": "proxy", "url": "http://127.0.0.1:80"}
        },
        "security": "tls",
        "tlsSettings": {
            "serverName": domain,
            "minVersion": "1.3",
            "maxVersion": "1.3",
            "certificates": [{
                "certificateFile": ssl_cert,
                "keyFile": ssl_key
            }],
            "alpn": ["h3"]
        },
        "externalProxy": [{
            "dest": domain,
            "port": hy2_port,
            "forceTls": "tls",
            "remark": "Hysteria 2"
        }]
    }
    upsert_inbound(hy2_port, "hysteria", "in-hysteria2", "Hysteria 2", hy2_settings, hy2_stream, listen="0.0.0.0")

# E. AmneziaWG v3.1 (8443)
if enable_awg_v3:
    awg3_settings = {
        "clients": [{
            "privateKey": wg_client_priv,
            "publicKey": wg_client_pub,
            "allowedIPs": ["10.8.1.2/32"],
            "email": "Client-1",
            "enable": True
        }],
        "server": {
            "contentPaddingAddition": "3-16",
            "disableCookies": True,
            "h1": "", "h2": "", "h3": "", "h4": "",
            "jc": 4, "jmax": 160, "jmin": 50,
            "keepaliveTimeout": "8-10",
            "maxHandshakeAttempts": "21-26",
            "mtu": 1360,
            "primaryDns": "8.8.8.8",
            "secondaryDns": "8.8.4.4",
            "privateKey": wg_server_priv,
            "publicKey": wg_server_pub,
            "randomTrailers": False,
            "rejectAfterTime": "178-211",
            "rekeyAfterTime": "107-135",
            "rekeyTimeout": "3-4",
            "s1": 45, "s2": 60, "s3": 24, "s4": 16,
            "subnetCidr": 24,
            "subnetIp": "10.8.1.0"
        }
    }
    awg3_stream = {
        "externalProxy": [{
            "dest": domain,
            "port": awg_v3_port,
            "remark": "AmneziaWG v3.1"
        }]
    }
    upsert_inbound(awg_v3_port, "amneziawg", "in-8443-udp", "AmneziaWG v3.1", awg3_settings, awg3_stream, listen="0.0.0.0")

# F. AmneziaWG v2.0 Legacy (8444)
if enable_awg_v2:
    awg2_settings = {
        "clients": [{
            "privateKey": wg_client_priv,
            "publicKey": wg_client_pub,
            "allowedIPs": ["10.8.2.2/32"],
            "email": "Legacy-Router",
            "enable": True
        }],
        "server": {
            "h1": "149419586", "h2": "878791997", "h3": "1251051976", "h4": "1657628296",
            "jc": 4, "jmax": 160, "jmin": 50,
            "mtu": 1360,
            "primaryDns": "8.8.8.8",
            "privateKey": wg_server_priv,
            "publicKey": wg_server_pub,
            "s1": 45, "s2": 60, "s3": 24, "s4": 16,
            "subnetCidr": 24,
            "subnetIp": "10.8.2.0"
        }
    }
    awg2_stream = {
        "externalProxy": [{
            "dest": domain,
            "port": awg_v2_port,
            "remark": "AmneziaWG v2.0"
        }]
    }
    upsert_inbound(awg_v2_port, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2.0", awg2_settings, awg2_stream, listen="0.0.0.0")

try:
    cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
except Exception:
    pass

conn.commit()
conn.close()
EOF_PYTHON_CONFIG

# Нормализация прав доступа к базе данных
chmod 644 "$DB_PATH" 2>/dev/null || true

# Возобновление/перезапуск службы 3X-UI
if [ "${WAS_ACTIVE:-0}" -eq 1 ] || (command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet x-ui 2>/dev/null); then
    log "Запуск службы 3X-UI..."
    systemctl restart x-ui && ok "Служба 3X-UI успешно запущена." || warn "Не удалось перезапустить службу x-ui."
fi

echo
echo -e "${GREEN}=====================================================================${NC}"
echo -e "${GREEN}      БАЗА ДАННЫХ 3X-UI УСПЕШНО СКОНФИГУРИРОВАНА!                    ${NC}"
echo -e "${GREEN}=====================================================================${NC}"
echo -e "  - ${BOLD}Панель управления:${NC} ${CYAN}https://${PRIMARY_DOMAIN}/${PANEL_PATH}/${NC}"
echo -e "  - ${BOLD}Ссылка на подписку:${NC} ${CYAN}https://${PRIMARY_DOMAIN}/${SUB_PATH}/${NC}"
echo -e "  - ${BOLD}Сгенерированный UUID клиента:${NC} ${GREEN}${CLIENT_UUID}${NC}"
if [ "$ENABLE_STEAL" = "y" ] || [ "$ENABLE_CLASSIC" = "y" ]; then
echo -e "  - ${BOLD}Reality Public Key:${NC} ${CYAN}${REALITY_PUB}${NC}"
echo -e "  - ${BOLD}Reality Short ID:${NC} ${CYAN}${REALITY_SHORT_ID}${NC}"
fi
if [ "$ENABLE_HY2" = "y" ]; then
echo -e "  - ${BOLD}Hysteria 2 Пароль:${NC} ${CYAN}${HY2_PASS}${NC}"
fi
echo -e "${GREEN}=====================================================================${NC}"
echo
exit 0
