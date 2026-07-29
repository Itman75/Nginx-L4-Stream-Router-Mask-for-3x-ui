#!/bin/bash
set -euo pipefail

#################################################################
# PROD VPS HARDENING (Ubuntu 20.04+ & Debian 11+)
# + BBR + Disable IPv6 + Block Ping
# + IPv4 ONLY Firewall Rules
# + SSH Keys (Auto-gen or Paste)
# + 3x-ui (Выбор версии)
# + Extended Utilities
################################---------------------------------

DEFAULT_SSH_PORT=22
MIN_SSH_PORT=1024
MAX_SSH_PORT=65535

export DEBIAN_FRONTEND=noninteractive

# ─────────────────────────── Цвета ───────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[+]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗] $*${NC}" >&2; exit 1; }

# Проверка root-прав
if [[ $EUID -ne 0 ]]; then
    die "Запустите скрипт от имени root (через sudo)."
fi

# Проверка совместимости ОС
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        die "Данный скрипт оптимизирован строго под семейства Ubuntu и Debian."
    fi
    log "Обнаружена ОС: $PRETTY_NAME"
else
    die "Не удалось определить дистрибутив ОС."
fi

#####################################
# ФУНКЦИИ ВАЛИДАЦИИ И ПОДДЕРЖКИ
#####################################

prompt_yes_no() {
    while true; do
        local ans=""
        if ! read -rp "$1 (yes/no): " ans; then
            echo ""
            return 1
        fi
        case "$ans" in
            yes|y|Y) return 0 ;;
            no|n|N) return 1 ;;
            *) echo "Введите yes или no" ;;
        esac
    done
}

validate_password() {
    local p="$1"
    [[ ${#p} -ge 12 ]] &&
    [[ "$p" =~ [a-z] ]] &&
    [[ "$p" =~ [A-Z] ]] &&
    [[ "$p" =~ [0-9] ]] &&
    [[ "$p" =~ [^a-zA-Z0-9] ]]
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] &&
    (( "$1" >= MIN_SSH_PORT && "$1" <= MAX_SSH_PORT ))
}

safe_sudoers() {
    local target_user="$1"
    local file="/etc/sudoers.d/$target_user"
    
    chown root:root "$file" 2>/dev/null || true
    chmod 440 "$file" || return 1
    if ! visudo -cf "$file"; then
        warn "Критическая ошибка: Создан невалидный файл sudoers! Удаление файла во избежание поломки sudo."
        rm -f "$file"
        return 1
    fi
    return 0
}

# Функция настройки SSH ключей
setup_ssh_keys() {
    local target_user="$1"
    local user_home

    user_home=$(getent passwd "$target_user" | cut -d: -f6) || user_home=""
    if [[ -z "$user_home" ]]; then
        warn "Не удалось определить домашний каталог для пользователя $target_user"
        return 1
    fi

    echo "-------------------------------------"
    echo "НАСТРОЙКА SSH КЛЮЧЕЙ ДЛЯ: $target_user"
    echo "1) Сгенерировать новую пару ключей на сервере (НЕ РЕКОМЕНДУЕТСЯ)"
    echo "2) Ввести (вставить) уже существующий Public Key (РЕКОМЕНДУЕТСЯ)"
    echo "3) Пропустить"

    local choice=""
    if ! read -rp "Ваш выбор (1-3): " choice; then
        choice=3
    fi

    case "$choice" in
        1)
            warn "Генерация ключей на сервере менее безопасна, так как приватный ключ отображается в консоли."
            if ! prompt_yes_no "Вы действительно хотите сгенерировать ключ на сервере?"; then
                return 1
            fi
            
            mkdir -p "$user_home/.ssh"
            chmod 700 "$user_home/.ssh"

            rm -f "$user_home/.ssh/id_ed25519" "$user_home/.ssh/id_ed25519.pub"

            log "Генерируем ключи Ed25519..."
            if ! ssh-keygen -t ed25519 -f "$user_home/.ssh/id_ed25519" -C "vps-$target_user" -N "" -q; then
                warn "Ошибка при генерации ключа."
                return 1
            fi

            cat "$user_home/.ssh/id_ed25519.pub" >> "$user_home/.ssh/authorized_keys"

            chmod 600 "$user_home/.ssh/authorized_keys" || true
            chown -R "$target_user":"$target_user" "$user_home/.ssh" 2>/dev/null || chown -R "$target_user" "$user_home/.ssh" || true

            echo ""
            echo "==========================================================="
            echo "!!! СОХРАНИТЕ ЭТОТ ПРИВАТНЫЙ КЛЮЧ ПРЯМО СЕЙЧАС !!!"
            echo "Скопируйте всё между линиями и сохраните в файл (например: myserver.key)"
            echo "==========================================================="
            cat "$user_home/.ssh/id_ed25519"
            echo "==========================================================="
            echo ""
            read -rp "Нажмите Enter, когда сохраните ключ..." || true
            return 0
            ;;
        2)
            log "Вставьте ваш публичный ключ (начинается с ssh-rsa или ssh-ed25519):"
            local pub_key=""
            if ! read -r pub_key; then
                pub_key=""
            fi

            if [[ -z "$pub_key" ]]; then
                warn "Ключ не введен."
                return 1
            fi

            mkdir -p "$user_home/.ssh"
            chmod 700 "$user_home/.ssh" || true
            echo "$pub_key" >> "$user_home/.ssh/authorized_keys"

            chmod 600 "$user_home/.ssh/authorized_keys" || true
            chown -R "$target_user":"$target_user" "$user_home/.ssh" 2>/dev/null || chown -R "$target_user" "$user_home/.ssh" || true

            ok "Публичный ключ успешно добавлен."
            return 0
            ;;
        *)
            log "Пропуск настройки ключей."
            return 1
            ;;
    esac
}

#####################################
# НАЧАЛО ВЫПОЛНЕНИЯ И ОБНОВЛЕНИЕ APT
#####################################
log "Обновление локальной базы пакетов..."
apt-get update -y || warn "Не удалось полностью обновить кэш apt."

if [[ "$ID" == "ubuntu" ]]; then
    log "Проверка и подключение репозитория universe (актуально для Ubuntu)..."
    apt-get install -y software-properties-common || true
    add-apt-repository -y universe || true
fi

#####################################
# ОПТИМИЗАЦИЯ СЕТИ (PROXY TUNING)
#####################################
log "Применение сетевых оптимизаций ядра (Proxy Tuning)..."
mkdir -p /etc/sysctl.d/
cat << EOF > /etc/sysctl.d/99-proxy-tuning.conf
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
sysctl --system >/dev/null 2>&1 || warn "Некоторые параметры sysctl не применились (нормально для контейнеров LXC/OpenVZ)."

#####################################
# УСТАНОВКА СИСТЕМНЫХ УТИЛИТ И МОНИТОРИНГА
#####################################
if prompt_yes_no "Установить расширенные системные утилиты и мониторинг (htop, btop, tcpdump, jq, tmux и др.)"; then
    log "Установка системных утилит..."
    apt-get install -y \
        curl \
        build-essential \
        btop \
        htop \
        iperf3 \
        iftop \
        net-tools \
        tcpdump \
        dnsutils \
        mtr-tiny \
        jq \
        tmux \
        ncdu \
        vnstat \
        openssh-client || warn "Не все утилиты были установлены."
    ok "Системные утилиты установлены."
else
    log "Пропуск установки утилит."
fi

#####################################
# СЕТЕВЫЕ НАСТРОЙКИ (BBR + IPv6)
#####################################
if prompt_yes_no "Включить TCP BBR и отключить IPv6"; then
    SYSCTL_CONF="/etc/sysctl.d/99-vps-hardening.conf"
    
    cat > "$SYSCTL_CONF" <<EOF
# TCP BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    sysctl --system || warn "Параметры sysctl применились частично."

    # Отключение IPv6 в GRUB (для полноценных VPS/KVM)
    if [ -f /default/grub ] || [ -f /etc/default/grub ]; then
        GRUB_FILE="/etc/default/grub"
        if ! grep -q "ipv6.disable=1" "$GRUB_FILE"; then
            cp "$GRUB_FILE" "${GRUB_FILE}.bak"
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 /' "$GRUB_FILE"
            update-grub 2>/dev/null || update-grub2 2>/dev/null || true
            log "IPv6 отключен через GRUB. Резервная копия сохранена."
        fi
    fi

    # Защита через cron при перезагрузке
    if command -v crontab &>/dev/null; then
        cron_job="@reboot sleep 10 && sysctl --system"
        if ! crontab -l 2>/dev/null | grep -Fq "$cron_job"; then
            (crontab -l 2>/dev/null || true; echo "$cron_job") | crontab - || true
        fi
    fi
    ok "TCP BBR активирован, IPv6 заблокирован."
fi

#####################################
# ROOT PASSWORD
#####################################
if prompt_yes_no "Сменить пароль root"; then
    while true; do
        local rp="" rp2=""
        read -rsp "Новый пароль root: " rp; echo
        read -rsp "Повтор: " rp2; echo
        [[ "$rp" == "$rp2" ]] || { warn "Пароли не совпадают"; continue; }
        validate_password "$rp" || { warn "Слабый пароль. Требуется: минимум 12 символов, заглавные, строчные, цифры и спецсимволы."; continue; }
        echo "root:$rp" | chpasswd
        ok "Пароль root изменен."
        break
    done
fi

#####################################
# СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
#####################################
CREATED_USER=""

if prompt_yes_no "Создать обычного пользователя с правами sudo"; then
    local uname=""
    read -rp "Имя пользователя: " uname || uname=""
    if [[ -z "$uname" ]]; then
        warn "Имя пользователя не может быть пустым."
    elif id "$uname" &>/dev/null; then
        warn "Пользователь уже существует."
        CREATED_USER="$uname"
    else
        if adduser --disabled-password --gecos "" "$uname"; then
            while true; do
                local up="" up2=""
                read -rsp "Пароль для $uname: " up; echo
                read -rsp "Повтор: " up2; echo
                [[ "$up" == "$up2" ]] || { warn "Пароли не совпадают"; continue; }
                validate_password "$up" || { warn "Слабый пароль (мин. 12 символов, разный регистр, цифры, спецсимволы)."; continue; }
                echo "$uname:$up" | chpasswd
                break
            done
            usermod -aG sudo "$uname"
            CREATED_USER="$uname"
            ok "Пользователь $uname создан."
        else
            warn "Не удалось создать пользователя."
        fi
    fi

    if [[ -n "$CREATED_USER" ]] && prompt_yes_no "Разрешить беспарольный sudo для $CREATED_USER"; then
        echo "$CREATED_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CREATED_USER"
        safe_sudoers "$CREATED_USER"
    fi
fi

#####################################
# НАСТРОЙКА SSH КЛЮЧЕЙ
#####################################
KEYS_INSTALLED="false"

if [ -n "$CREATED_USER" ]; then
    if prompt_yes_no "Настроить SSH ключи для пользователя $CREATED_USER"; then
        if setup_ssh_keys "$CREATED_USER"; then
            KEYS_INSTALLED="true"
        fi
    fi
else
    if prompt_yes_no "Настроить SSH ключи для ROOT"; then
        if setup_ssh_keys "root"; then
            KEYS_INSTALLED="true"
        fi
    fi
fi

#####################################
# SSH HARDENING
#####################################
SSH_PORT="$DEFAULT_SSH_PORT"

# Универсальное переключение службы SSH для Ubuntu / Debian
log "Проверка и настройка конфигурации службы SSH..."
if systemctl list-unit-files | grep -q ssh.socket; then
    systemctl stop ssh.socket 2>/dev/null || true
    systemctl disable ssh.socket 2>/dev/null || true
fi
systemctl enable ssh.service 2>/dev/null || systemctl enable ssh 2>/dev/null || true

if prompt_yes_no "Изменить стандартный порт SSH"; then
    while true; do
        local p=""
        read -rp "Новый порт SSH (диапазон $MIN_SSH_PORT-$MAX_SSH_PORT): " p || p=""
        validate_port "$p" || { warn "Недопустимый порт."; continue; }
        SSH_PORT="$p"
        break
    fi
fi

SSH_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
mkdir -p /etc/ssh/sshd_config.d/

cat > "$SSH_DROPIN" <<EOF
# Hardened SSH Configuration
Port $SSH_PORT
AddressFamily inet
PubkeyAuthentication yes
EOF

if [ "$KEYS_INSTALLED" = "true" ]; then
    if prompt_yes_no "Отключить вход по паролю (PasswordAuthentication no)?"; then
        cat >> "$SSH_DROPIN" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
EOF
        ok "Аутентификация по паролю для SSH отключена."
    fi
fi

mkdir -p /run/sshd
log "Тестирование конфигурации SSH..."
if sshd -t; then
    systemctl daemon-reload
    systemctl restart ssh.service || systemctl restart ssh || warn "Не удалось перезапустить SSH автоматически."
    ok "Служба SSH успешно переведена на порт $SSH_PORT"
else
    warn "Обнаружена ошибка в конфигурации SSH! Откат изменений..."
    rm -f "$SSH_DROPIN"
    systemctl restart ssh.service || systemctl restart ssh || true
fi

#####################################
# UFW (FIREWALL) 
#####################################
log "Установка и настройка межсетевого экрана UFW..."
apt-get install -y ufw

if grep -q "^IPV6=" /etc/default/ufw; then
    sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
else
    echo "IPV6=no" >> /etc/default/ufw
fi

ufw default deny incoming
ufw default allow outgoing

log "Применение правил брандмауэра (IPv4)..."
ufw allow proto tcp from any to any port "$SSH_PORT" comment 'SSH'

TCP_PORTS=(80 443 10443 5201 4500 4501 4502)
for port in "${TCP_PORTS[@]}"; do
    ufw allow proto tcp from any to any port "$port"
done

UDP_PORTS=(443 8443 5201)
for port in "${UDP_PORTS[@]}"; do
    ufw allow proto udp from any to any port "$port"
done

if prompt_yes_no "Блокировать входящие ICMP (Ping) запросы?"; then
    if [ -f /etc/ufw/before.rules ]; then
        sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
        ok "Ping-запросы заблокированы."
    fi
fi

ufw --force enable

#####################################
# FAIL2BAN
#####################################
log "Установка и настройка Fail2ban..."
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
findtime = 10m
bantime = 1h
backend = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

#####################################
# 3X-UI 
#####################################
if prompt_yes_no "Установить панель 3x-ui"; then
    if ! command -v curl &> /dev/null; then
        apt-get install -y curl
    fi
    log "Запуск установки 3x-ui..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
fi

#####################################
# ФИНАЛ
#####################################
echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}✔ НАСТРОЙКА VPS ЗАВЕРШЕНА УСПЕШНО${NC}"
echo -e "  • ОС:           ${CYAN}$PRETTY_NAME${NC}"
echo -e "  • SSH порт:     ${CYAN}$SSH_PORT${NC}"
echo -e "  • IPv6:         ${RED}отключён${NC}"
echo -e "  • UFW:          ${GREEN}активен (IPv4 only)${NC}"
echo -e "  • TCP BBR:      ${GREEN}активирован${NC}"
echo -e "  • Fail2ban:     ${GREEN}активен${NC}"
echo -e "  • SSH Ключи:    ${CYAN}$KEYS_INSTALLED${NC}"
echo -e "${GREEN}======================================${NC}"
exit 0
