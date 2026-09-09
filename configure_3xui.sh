#!/usr/bin/env bash
# ==============================================================================
#  CONFIGURE 3X-UI INBOUNDS & SETTINGS (v6.5.2 Universal Companion & Smart Reconcile)
# ==============================================================================
#  Скрипт автоматического конфигурирования и самовосстановления базы 3X-UI.
#  Безопасен для повторного запуска:
#    1. 100% сохранность существующих клиентов (UUID, пароли Hy2, ключи AWG, лимиты);
#    2. 100% сохранность действующих серверных ключей REALITY и AmneziaWG;
#    3. Самоисправление скрытых ошибок (reality settings.publicKey, мертвый SNI swdist);
#    4. Автоматическая настройка externalProxy :443 для корректных ссылок подписок;
#    5. Защита существующей кастомной подписки (не затирает кастомный домен/путь);
#    6. Режим безопасного аудита (--dry-run) и авто-бэкап базы перед записью.
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

Скрипт автоматического конфигурирования и самовосстановления базы 3X-UI (инбаунды, пути, подписки).
Безопасен для повторного запуска: сохраняет существующих клиентов, ключи и кастомные подписки.

Опции:
  -c, --config <FILE>     Путь к файлу параметров (.env) (по умолчанию: ./setup_mask.env)
  --db <PATH>             Путь к файлу базы данных SQLite 3X-UI (по умолчанию: /etc/x-ui/x-ui.db)
  --dry-run               Только аудит и проверка (без внесения изменений)
  --force-sub             Принудительно перезаписать кастомные параметры подписки из .env
  -y, --yes               Неинтерактивное выполнение (без подтверждений)
  -h, --help              Показать эту справку и выйти

Примеры использования:
  # 1. Обычная настройка / обновление:
  ./configure_3xui.sh --config ./setup_mask.env -y

  # 2. Безопасный аудит (посмотреть, что изменится, без записи):
  ./configure_3xui.sh --dry-run
EOF_HELP
}

CONFIG_FILE=""
DB_PATH="/etc/x-ui/x-ui.db"
DRY_RUN=0
FORCE_SUB=0
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
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force-sub)
            FORCE_SUB=1
            shift
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

# Проверка root
if [ "${EUID:-$(id -u)}" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    warn "Для записи в базу данных /etc/x-ui/x-ui.db могут потребоваться права суперпользователя (sudo)."
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}>>> РЕЖИМ ПРЕДВАРИТЕЛЬНОГО АУДИТА (--dry-run). ИЗМЕНЕНИЯ НЕ ЗАПИСЫВАЮТСЯ <<<${NC}\n"
fi

# Автопоиск конфигурационного файла, если не передан
if [ -z "$CONFIG_FILE" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/setup_mask.env" ]; then
        CONFIG_FILE="$script_dir/setup_mask.env"
    elif [ -f "./setup_mask.env" ]; then
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
else
    warn "Конфигурационный файл .env не найден. Параметры будут считаны из базы данных 3X-UI."
fi

# Дефолтные значения переменных, если не определены в .env
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

# Определение работоспособной команды Python
PYTHON_CMD=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="$candidate"
        break
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        log "Установка python3..."
        apt-get update -q && apt-get install -y python3 -q || die "Не удалось установить python3."
        PYTHON_CMD="python3"
    else
        die "Работоспособный Python 3 не найден в системе. Необходим для анализа базы SQLite."
    fi
fi

# Проверка наличия базы данных 3X-UI
if [ ! -f "$DB_PATH" ]; then
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
if [ "$DRY_RUN" -eq 0 ]; then
    BACKUP_TS="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DB="${DB_PATH}.bak.${BACKUP_TS}"
    cp -a "$DB_PATH" "$BACKUP_DB"
    chmod 600 "$BACKUP_DB" 2>/dev/null || true
    ok "Создана резервная копия базы данных: $BACKUP_DB"
fi

# Экспорт переменных окружения для Python
export DB_PATH
export DRY_RUN
export FORCE_SUB
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

# Приостановка службы x-ui на время реальной транзакции во избежание блокировок SQLite
WAS_ACTIVE=0
if [ "$DRY_RUN" -eq 0 ]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet x-ui 2>/dev/null; then
        log "Приостановка службы 3X-UI на время обновления конфигурации базы..."
        systemctl stop x-ui
        WAS_ACTIVE=1
    fi
fi

log "Конфигурирование таблиц settings и inbounds (Smart Reconcile Engine)..."

"$PYTHON_CMD" - << 'EOF_PYTHON_CONFIG'
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import sqlite3
import json
import uuid
import secrets
import base64

db_path = os.environ["DB_PATH"]
dry_run = os.environ.get("DRY_RUN", "0") == "1"
force_sub = os.environ.get("FORCE_SUB", "0") == "1"

conn = sqlite3.connect(db_path, timeout=30.0)
cur = conn.cursor()

# Извлечение существующих параметров из таблицы settings
existing_settings = {}
try:
    cur.execute("SELECT key, value FROM settings")
    for k, v in cur.fetchall():
        existing_settings[k] = v
except Exception as e:
    print(f"[!] Предупреждение: ошибка чтения таблицы settings: {e}")

domain = os.environ.get("PRIMARY_DOMAIN") or existing_settings.get("subDomain") or "localhost"
panel_port = os.environ.get("PANEL_PORT") or existing_settings.get("webPort") or "10443"
panel_path = (os.environ.get("PANEL_PATH") or existing_settings.get("webBasePath") or "my-3x-panel").strip("/")

sub_port = os.environ.get("SUB_PORT") or existing_settings.get("subPort") or "55443"
sub_path = (os.environ.get("SUB_PATH") or existing_settings.get("subPath") or "my-post-key").strip("/")

xhttp_port = int(os.environ.get("XHTTP_STREAM_PORT") or "50443")
xhttp_raw_path = os.environ.get("XHTTP_STREAM_PATH") or "Stream-One-Path"
xhttp_path = "/" + xhttp_raw_path.strip("/") + "/"

enable_steal = os.environ.get("ENABLE_STEAL", "y").lower() in ("1", "y", "true")
steal_port = int(os.environ.get("STEAL_PORT") or "45443")
steal_dom = os.environ.get("STEAL_DOMAINS") or f"cdn.{domain}"
steal_dom = steal_dom.split()[0] if steal_dom.strip() else f"cdn.{domain}"

enable_classic = os.environ.get("ENABLE_CLASSIC", "y").lower() in ("1", "y", "true")
classic_port = int(os.environ.get("CLASSIC_PORT") or "46443")
classic_sni = os.environ.get("CLASSIC_SNI") or "gateway.icloud.com"
classic_sni = classic_sni.split()[0] if classic_sni.strip() else "gateway.icloud.com"

enable_hy2 = os.environ.get("ENABLE_HY2", "y").lower() in ("1", "y", "true")
hy2_port = int(os.environ.get("HY2_PORT") or "443")

enable_awg_v3 = os.environ.get("ENABLE_AWG_V3", "y").lower() in ("1", "y", "true")
awg_v3_port = int(os.environ.get("AWG_V3_PORT") or "8443")

enable_awg_v2 = os.environ.get("ENABLE_AWG_V2", "y").lower() in ("1", "y", "true")
awg_v2_port = int(os.environ.get("AWG_V2_PORT") or "8444")

ssl_cert = os.environ.get("SSL_CERT_PATH", "")
ssl_key = os.environ.get("SSL_KEY_PATH", "")

# Определение ID администратора
cur.execute("SELECT id FROM users LIMIT 1")
user_row = cur.fetchone()
admin_id = user_row[0] if user_row else 1

# Curve25519 helper (RFC 7748) для генерации, валидации и починки ключей
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

def curve25519_pubkey(priv_b64):
    try:
        raw_priv = base64.b64decode(priv_b64)
        k = clamp(raw_priv)
        pub_raw = x25519(k, 9).to_bytes(32, "little")
        return base64.b64encode(pub_raw).decode()
    except Exception:
        return None

def curve25519_reality_pubkey(priv_b64url):
    try:
        padding = "=" * ((4 - len(priv_b64url) % 4) % 4)
        raw_priv = base64.urlsafe_b64decode(priv_b64url + padding)
        k = clamp(raw_priv)
        pub_raw = x25519(k, 9).to_bytes(32, "little")
        return base64.urlsafe_b64encode(pub_raw).decode().rstrip("=")
    except Exception:
        return None

def generate_reality_keypair():
    priv_raw = os.urandom(32)
    k = clamp(priv_raw)
    pub_raw = x25519(k, 9).to_bytes(32, "little")
    priv_b64 = base64.urlsafe_b64encode(priv_raw).decode().rstrip("=")
    pub_b64 = base64.urlsafe_b64encode(pub_raw).decode().rstrip("=")
    return priv_b64, pub_b64

def generate_wg_keypair():
    priv_raw = os.urandom(32)
    k = clamp(priv_raw)
    pub_raw = x25519(k, 9).to_bytes(32, "little")
    priv_b64 = base64.b64encode(priv_raw).decode()
    pub_b64 = base64.b64encode(pub_raw).decode()
    return priv_b64, pub_b64

# ----------------- 1. Настройки панели и подписок (settings) -----------------
print("\n[+] Синхронизация системных настроек панели и подписок...")

old_sub_domain = existing_settings.get("subDomain", "").strip()
old_sub_uri = existing_settings.get("subURI", "").strip()
old_sub_path = existing_settings.get("subPath", "").strip()

# Проверка: настроена ли кастомная подписка
is_custom_sub = bool(old_sub_uri and (old_sub_domain != domain or old_sub_path.strip("/") != sub_path))

if is_custom_sub and not force_sub:
    print(f"  [СОХРАНЕНО] Кастомная подписка сохранена: {old_sub_uri}")
    target_sub_uri = old_sub_uri
    target_sub_domain = old_sub_domain
    target_sub_path = old_sub_path
else:
    target_sub_uri = f"https://{domain}/{sub_path}/"
    target_sub_domain = domain
    target_sub_path = f"/{sub_path}/"

settings_updates = {
    "webPort": panel_port,
    "webBasePath": f"/{panel_path}/",
    "subPort": sub_port,
    "subPath": target_sub_path,
    "subURI": target_sub_uri,
    "subDomain": target_sub_domain,
    "subCertFile": "",
    "subKeyFile": ""
}

for k, v in settings_updates.items():
    current_val = existing_settings.get(k)
    if current_val != v:
        if not dry_run:
            cur.execute("SELECT id FROM settings WHERE key = ?", (k,))
            if cur.fetchone():
                cur.execute("UPDATE settings SET value = ? WHERE key = ?", (str(v), k))
            else:
                cur.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (k, str(v)))
        print(f"  [ИСПРАВЛЕНО] Настройка {k}: '{current_val}' -> '{v}'")
    else:
        print(f"  [В ПОРЯДКЕ] Настройка {k}: '{v}'")

# ----------------- 2. Интеллектуальное согласование инбаундов (Smart Reconcile) -----------------
print("\n[+] Аудит и согласование инбаундов (Smart Reconcile Engine)...")

def smart_reconcile_inbound(port, protocol, tag, remark, default_settings, default_stream, listen="127.0.0.1"):
    cur.execute("SELECT id, settings, stream_settings, protocol, tag, remark, listen FROM inbounds WHERE port = ? OR tag = ?", (port, tag))
    row = cur.fetchone()
    
    if not row:
        # Инбаунд отсутствует -> создаем под ключ
        settings_json = json.dumps(default_settings, ensure_ascii=False)
        stream_json = json.dumps(default_stream, ensure_ascii=False)
        sniffing_json = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})
        if not dry_run:
            cur.execute("""
                INSERT INTO inbounds (
                    user_id, up, down, total, remark, enable, expiry_time,
                    listen, port, protocol, settings, stream_settings, tag, sniffing
                ) VALUES (?, 0, 0, 0, ?, 1, 0, ?, ?, ?, ?, ?, ?, ?)
            """, (admin_id, remark, listen, port, protocol, settings_json, stream_json, tag, sniffing_json))
        print(f"  [СОЗДАНО] Отсутствующий инбаунд: {remark} ({protocol.upper()} на порту {port}) добавлен.")
        return

    inbound_id, raw_s, raw_st, proto, cur_tag, cur_remark, cur_listen = row
    try:
        cur_settings = json.loads(raw_s) if raw_s else {}
    except Exception:
        cur_settings = {}
    try:
        cur_stream = json.loads(raw_st) if raw_st else {}
    except Exception:
        cur_stream = {}

    target_settings = json.loads(json.dumps(default_settings))
    target_stream = json.loads(json.dumps(default_stream))
    repairs = []
    preserved = []

    # А. Сохранение пользователей (UUID, пароли, лимиты)
    existing_clients = cur_settings.get("clients", [])
    if existing_clients and len(existing_clients) > 0:
        target_settings["clients"] = existing_clients
        preserved.append(f"клиенты ({len(existing_clients)} польз.)")
    else:
        repairs.append("добавлен клиент по умолчанию")

    # Б. Проверка и ремонт VLESS REALITY
    if protocol == "vless" and "realitySettings" in target_stream:
        cur_reality = cur_stream.get("realitySettings", {})
        
        # Сохранение privateKey
        priv = cur_reality.get("privateKey")
        if priv:
            target_stream["realitySettings"]["privateKey"] = priv
            preserved.append("privateKey Reality")
        
        # Сохранение shortIds
        sids = cur_reality.get("shortIds")
        if sids:
            target_stream["realitySettings"]["shortIds"] = sids
            preserved.append("shortIds")

        # Ремонт / сохранение settings.publicKey
        pub = cur_reality.get("settings", {}).get("publicKey") or cur_reality.get("publicKey")
        if pub:
            target_stream["realitySettings"]["settings"]["publicKey"] = pub
            if not cur_reality.get("settings", {}).get("publicKey"):
                repairs.append("исправлен отсутствующий settings.publicKey (устранена ошибка empty password)")
            else:
                preserved.append("publicKey")
        else:
            derived_pub = curve25519_reality_pubkey(target_stream["realitySettings"]["privateKey"])
            if derived_pub:
                target_stream["realitySettings"]["settings"]["publicKey"] = derived_pub
                repairs.append("восстановлен settings.publicKey по x25519")

        # Ремонт мертвого swdist.microsoft.com SNI
        old_snis = cur_reality.get("serverNames", [])
        old_dest = cur_reality.get("dest", "")
        if any("swdist.microsoft.com" in s for s in old_snis) or "swdist.microsoft.com" in old_dest:
            repairs.append(f"заменен мертвый SNI swdist.microsoft.com -> {classic_sni}")
            target_stream["realitySettings"]["serverNames"] = [classic_sni]
            target_stream["realitySettings"]["dest"] = f"{classic_sni}:443"
        elif old_snis:
            target_stream["realitySettings"]["serverNames"] = old_snis
            target_stream["realitySettings"]["dest"] = old_dest or target_stream["realitySettings"]["dest"]
            preserved.append(f"SNI ({','.join(old_snis)})")

        # Проверка Anti-Loop для Steal-Oneself
        if tag == "in-steal-reality":
            if cur_reality.get("dest") != "127.0.0.1:9443":
                repairs.append("установлен dest: 127.0.0.1:9443 (защита от петли Steal-Oneself)")
                target_stream["realitySettings"]["dest"] = "127.0.0.1:9443"
            else:
                preserved.append("anti-loop dest 9443")

    # В. Проверка и ремонт xHTTP
    if protocol == "vless" and "xhttpSettings" in target_stream:
        cur_xh = cur_stream.get("xhttpSettings", {})
        if cur_xh.get("path"):
            target_stream["xhttpSettings"]["path"] = cur_xh["path"]
            preserved.append(f"path ({cur_xh['path']})")
        target_stream["xhttpSettings"]["mode"] = "stream-one"

    # Г. Проверка и ремонт Hysteria 2
    if protocol == "hysteria":
        if cur_settings.get("clients"):
            target_settings["clients"] = cur_settings["clients"]
            preserved.append("пароль Hysteria 2")
        
        cur_certs = cur_stream.get("tlsSettings", {}).get("certificates", [])
        if cur_certs and cur_certs[0].get("certificateFile") and os.path.exists(cur_certs[0]["certificateFile"]):
            target_stream["tlsSettings"]["certificates"] = cur_certs
            preserved.append("действующие SSL-сертификаты Hy2")

    # Д. Проверка и ремонт AmneziaWG
    if protocol == "amneziawg":
        cur_srv = cur_settings.get("server", {})
        if cur_srv.get("privateKey"):
            target_settings["server"]["privateKey"] = cur_srv["privateKey"]
            preserved.append("серверный privateKey AWG")
            
            # Валидация Curve25519
            expected_pub = curve25519_pubkey(cur_srv["privateKey"])
            actual_pub = cur_srv.get("publicKey")
            if actual_pub and expected_pub and actual_pub == expected_pub:
                target_settings["server"]["publicKey"] = actual_pub
                preserved.append("валидный publicKey AWG (Handshake OK)")
            elif expected_pub:
                target_settings["server"]["publicKey"] = expected_pub
                repairs.append("исправлен поврежденный publicKey сервера Curve25519")
        
        # Сохранение параметров обфускации
        for param in ["jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "mtu", "subnetIp", "subnetCidr"]:
            if param in cur_srv:
                target_settings["server"][param] = cur_srv[param]

    # Е. Проверка и сохранение externalProxy (:443 и кастомных хостов узлов)
    cur_ext = cur_stream.get("externalProxy", [])
    expected_ext_port = 443 if protocol in ("vless", "hysteria") and port != hy2_port else (hy2_port if protocol == "hysteria" else port)

    # Сохраняем кастомный хост узла (dest), если он был настроен и не равен localhost
    target_dest = domain
    if cur_ext and len(cur_ext) > 0 and cur_ext[0].get("dest"):
        ext_dest = str(cur_ext[0]["dest"]).strip()
        if ext_dest and ext_dest not in ("127.0.0.1", "localhost", "0.0.0.0"):
            target_dest = ext_dest
            if ext_dest != domain:
                preserved.append(f"кастомный хост узла ({ext_dest})")

    if not cur_ext or cur_ext[0].get("port") != expected_ext_port or cur_ext[0].get("dest") != target_dest:
        force_tls_val = "same" if protocol == "vless" and "realitySettings" in target_stream else "tls"
        target_stream["externalProxy"] = [{
            "dest": target_dest,
            "port": expected_ext_port,
            "forceTls": force_tls_val,
            "remark": remark
        }]
        repairs.append(f"исправлен externalProxy -> {target_dest}:{expected_ext_port}")
    else:
        target_stream["externalProxy"] = cur_ext
        preserved.append(f"externalProxy :{expected_ext_port}")

    # Запись в SQLite
    settings_json = json.dumps(target_settings, ensure_ascii=False)
    stream_json = json.dumps(target_stream, ensure_ascii=False)
    sniffing_json = json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic", "fakedns"]})

    if not dry_run:
        cur.execute("""
            UPDATE inbounds
            SET protocol = ?, tag = ?, remark = ?, settings = ?, stream_settings = ?, listen = ?, sniffing = ?, enable = 1
            WHERE id = ?
        """, (protocol, tag, remark, settings_json, stream_json, listen, sniffing_json, inbound_id))

    status_str = f"  [ОБНОВЛЕН] {remark} (порт {port}):"
    if repairs:
        status_str += f"\n    -> Исправлено: {', '.join(repairs)}"
    if preserved:
        status_str += f"\n    -> Сохранено: {', '.join(preserved)}"
    print(status_str)

# --- Генерация дефолтных эталонных профилей (для отсутствующих инбаундов) ---
def_uuid = str(uuid.uuid4())
def_reality_priv, def_reality_pub = generate_reality_keypair()
def_reality_sid = secrets.token_hex(8)
def_hy2_pass = secrets.token_hex(12)
def_wg_s_priv, def_wg_s_pub = generate_wg_keypair()
def_wg_c_priv, def_wg_c_pub = generate_wg_keypair()

# 1. Steal-Oneself REALITY (45443)
if enable_steal:
    s_set = {"clients": [{"id": def_uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"}
    s_str = {
        "network": "tcp",
        "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False, "xver": 1, "dest": "127.0.0.1:9443",
            "serverNames": [steal_dom], "privateKey": def_reality_priv,
            "shortIds": [def_reality_sid],
            "settings": {"publicKey": def_reality_pub, "fingerprint": "chrome", "spiderX": f"/{def_reality_sid}"}
        },
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": "VLESS_STEAL"}]
    }
    smart_reconcile_inbound(steal_port, "vless", "in-steal-reality", "VLESS_STEAL", s_set, s_str, listen="127.0.0.1")

# 2. Classic REALITY (46443)
if enable_classic:
    c_set = {"clients": [{"id": def_uuid, "flow": "xtls-rprx-vision"}], "decryption": "none"}
    c_str = {
        "network": "tcp",
        "tcpSettings": {"acceptProxyProtocol": True},
        "security": "reality",
        "realitySettings": {
            "show": False, "xver": 0, "dest": f"{classic_sni}:443",
            "serverNames": [classic_sni], "privateKey": def_reality_priv,
            "shortIds": [def_reality_sid],
            "settings": {"publicKey": def_reality_pub, "fingerprint": "chrome", "spiderX": f"/{def_reality_sid}"}
        },
        "externalProxy": [{"dest": domain, "port": 443, "forceTls": "same", "remark": "VLESS_CLASSIC"}]
    }
    smart_reconcile_inbound(classic_port, "vless", "in-classic-reality", "VLESS_CLASSIC", c_set, c_str, listen="127.0.0.1")

# 3. VLESS xHTTP (50443)
x_set = {"clients": [{"id": def_uuid}], "decryption": "none"}
x_str = {
    "network": "xhttp",
    "xhttpSettings": {
        "path": xhttp_path, "host": domain, "mode": "stream-one",
        "xPaddingBytes": "100-500", "xPaddingObfsMode": True, "xPaddingKey": "X-Amz-Meta-Trace"
    },
    "security": "none",
    "externalProxy": [{"dest": domain, "port": 443, "forceTls": "tls", "sni": domain, "fingerprint": "chrome", "remark": "VLESS_XHTTP"}]
}
smart_reconcile_inbound(xhttp_port, "vless", "in-xhttp-stream", "VLESS_XHTTP", x_set, x_str, listen="127.0.0.1")

# 4. Hysteria 2 (443)
if enable_hy2:
    h_set = {"clients": [{"id": def_hy2_pass}], "version": 2}
    h_str = {
        "network": "hysteria",
        "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60, "masquerade": {"type": "proxy", "url": "http://127.0.0.1:80"}},
        "security": "tls",
        "tlsSettings": {
            "serverName": domain, "minVersion": "1.3", "maxVersion": "1.3",
            "certificates": [{"certificateFile": ssl_cert, "keyFile": ssl_key}], "alpn": ["h3"]
        },
        "externalProxy": [{"dest": domain, "port": hy2_port, "forceTls": "tls", "remark": "Hysteria 2"}]
    }
    smart_reconcile_inbound(hy2_port, "hysteria", "in-hysteria2", "Hysteria 2", h_set, h_str, listen="0.0.0.0")

# 5. AmneziaWG v3.1 (8443)
if enable_awg_v3:
    a3_set = {
        "clients": [{
            "privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub,
            "allowedIPs": ["10.8.1.2/32"], "email": "Client-1", "enable": True
        }],
        "server": {
            "contentPaddingAddition": "3-16", "disableCookies": True,
            "h1": "", "h2": "", "h3": "", "h4": "", "jc": 4, "jmax": 160, "jmin": 50,
            "keepaliveTimeout": "8-10", "maxHandshakeAttempts": "21-26", "mtu": 1360,
            "primaryDns": "8.8.8.8", "secondaryDns": "8.8.4.4",
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "randomTrailers": False, "rejectAfterTime": "178-211", "rekeyAfterTime": "107-135",
            "rekeyTimeout": "3-4", "s1": 45, "s2": 60, "s3": 24, "s4": 16,
            "subnetCidr": 24, "subnetIp": "10.8.1.0"
        }
    }
    a3_str = {"externalProxy": [{"dest": domain, "port": awg_v3_port, "remark": "AmneziaWG v3.1"}]}
    smart_reconcile_inbound(awg_v3_port, "amneziawg", "in-8443-udp", "AmneziaWG v3.1", a3_set, a3_str, listen="0.0.0.0")

# 6. AmneziaWG v2.0 Legacy (8444)
if enable_awg_v2:
    a2_set = {
        "clients": [{
            "privateKey": def_wg_c_priv, "publicKey": def_wg_c_pub,
            "allowedIPs": ["10.8.2.2/32"], "email": "Legacy-Router", "enable": True
        }],
        "server": {
            "h1": "149419586", "h2": "878791997", "h3": "1251051976", "h4": "1657628296",
            "jc": 4, "jmax": 160, "jmin": 50, "mtu": 1360, "primaryDns": "8.8.8.8",
            "privateKey": def_wg_s_priv, "publicKey": def_wg_s_pub,
            "s1": 45, "s2": 60, "s3": 24, "s4": 16, "subnetCidr": 24, "subnetIp": "10.8.2.0"
        }
    }
    a2_str = {"externalProxy": [{"dest": domain, "port": awg_v2_port, "remark": "AmneziaWG v2.0"}]}
    smart_reconcile_inbound(awg_v2_port, "amneziawg", "in-awg-v2-legacy", "AmneziaWG v2.0", a2_set, a2_str, listen="0.0.0.0")

if not dry_run:
    try:
        cur.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    except Exception:
        pass
    conn.commit()

conn.close()
EOF_PYTHON_CONFIG

# Нормализация прав доступа и перезапуск служб
if [ "$DRY_RUN" -eq 0 ]; then
    chmod 644 "$DB_PATH" 2>/dev/null || true

    # Возобновление/перезапуск службы 3X-UI
    if [ "${WAS_ACTIVE:-0}" -eq 1 ] || (command -v systemctl >/dev/null 2>&1 && systemctl is-enabled --quiet x-ui 2>/dev/null); then
        log "Перезапуск службы 3X-UI..."
        systemctl restart x-ui && ok "Служба 3X-UI успешно перезапущена." || warn "Не удалось перезапустить службу x-ui."
    fi

    # Проверка Nginx на наличие мертвого SNI и мягкий reload
    if command -v nginx >/dev/null 2>&1; then
        if [ -d /etc/nginx ] && grep -rq "swdist\.microsoft\.com" /etc/nginx/ 2>/dev/null; then
            log "Обновление устаревшего SNI в конфигурационных файлах Nginx..."
            find /etc/nginx/ -type f -name "*.conf" -exec sed -i 's/swdist\.microsoft\.com/gateway\.icloud\.com/g' {} + 2>/dev/null || true
            ok "Nginx: SNI swdist.microsoft.com заменен на gateway.icloud.com."
        fi

        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx 2>/dev/null && ok "Nginx успешно применил конфигурацию (Zero Downtime reload)." || true
        fi
    fi
fi

echo
echo -e "${GREEN}=====================================================================${NC}"
if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "${YELLOW}               АУДИТ УСПЕШНО ЗАВЕРШЕН (DRY-RUN)                      ${NC}"
    echo -e "${CYAN}  Для применения изменений выполните:                                ${NC}"
    echo -e "  ${BOLD}./configure_3xui.sh --config \"${CONFIG_FILE:-./setup_mask.env}\" -y${NC}"
else
    echo -e "${GREEN}      БАЗА ДАННЫХ 3X-UI УСПЕШНО СКОНФИГУРИРОВАНА И ИСЦЕЛЕНА!         ${NC}"
    echo -e "  - ${BOLD}Подключения клиентов:${NC}   ${GREEN}Сохранены без разрыва и сброса ключей${NC}"
    echo -e "  - ${BOLD}Панель управления:${NC}      ${CYAN}https://${PRIMARY_DOMAIN}/${PANEL_PATH}/${NC}"
    echo -e "  - ${BOLD}Ссылка на подписку:${NC}     ${CYAN}https://${PRIMARY_DOMAIN}/${SUB_PATH}/${NC}"
fi
echo -e "${GREEN}=====================================================================${NC}"
echo
exit 0
