#!/bin/bash
set -euo pipefail

#####################################
# PROD VPS HARDENING (Ubuntu 24.04)
# + Optional System Upgrade & Clean
# + BBR + Disable IPv6 + Block Ping
# + IPv4 ONLY Firewall Rules
# + SSH Keys (Auto-gen or Paste)
# + 3x-ui (Выбор версии)
# + Extended Utilities
#####################################

DEFAULT_SSH_PORT=22
MIN_SSH_PORT=22
MAX_SSH_PORT=65535

export DEBIAN_FRONTEND=noninteractive

# Проверка root-прав
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: Запусти скрипт от пользователя root (sudo)" >&2
    exit 1
fi

#####################################
# ФУНКЦИИ ВАЛИДАЦИИ И ПОДДЕРЖКИ
#####################################

prompt_yes_no() {
    while true; do
        local ans=""
        if ! read -rp "$1 (yes/no): " ans; then
            echo "" # Перенос строки при EOF
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

    # Принудительно устанавливаем владельца root перед проверкой visudo
    chown root:root "$file" 2>/dev/null || true
    chmod 440 "$file" || return 1
    if ! visudo -cf "$file"; then
        echo "Критическая ошибка: Создан невалидный файл sudoers! Удаление файла во избежание поломки sudo." >&2
        rm -f "$file"
        return 1
    fi
    return 0
}

# Функция настройки SSH ключей
setup_ssh_keys() {
    local target_user="$1"
    local user_home

    # Безопасное динамическое определение домашней директории пользователя в режиме set -e
    user_home=$(getent passwd "$target_user" | cut -d: -f6) || user_home=""
    if [[ -z "$user_home" ]]; then
        echo "Ошибка: Не удалось определить домашний каталог для пользователя $target_user" >&2
        return 1
    fi

    echo "-------------------------------------"
    echo "НАСТРОЙКА SSH КЛЮЧЕЙ ДЛЯ: $target_user"
    echo "1) Сгенерировать новую пару ключей на сервере (НЕ РЕКОМЕНДУЕТСЯ из соображений безопасности)"
    echo "2) Ввести (вставить) уже существующий Public Key (РЕКОМЕНДУЕТСЯ)"
    echo "3) Пропустить"

    local choice=""
    if ! read -rp "Ваш выбор (1-3): " choice; then
        choice=3
    fi

    case "$choice" in
        1)
            echo "ВНИМАНИЕ: Generation ключей на сервере менее безопасна, так как приватный ключ отображается в консоли."
            if ! prompt_yes_no "Вы действительно хотите сгенерировать ключ на сервере?"; then
                return 1
            fi

            mkdir -p "$user_home/.ssh"
            chmod 700 "$user_home/.ssh" || true

            # Очистка старых ключей генерации по умолчанию
            rm -f "$user_home/.ssh/id_ed25519" "$user_home/.ssh/id_ed25519.pub"

            echo "Генерируем ключи Ed25519..."
            if ! ssh-keygen -t ed25519 -f "$user_home/.ssh/id_ed25519" -C "vps-$target_user" -N "" -q; then
                echo "Ошибка при генерации ключа." >&2
                return 1
            fi

            # Добавление в authorized_keys
            cat "$user_home/.ssh/id_ed25519.pub" >> "$user_home/.ssh/authorized_keys"

            # Настройка прав
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
            echo "Вставьте ваш публичный ключ (начинается с ssh-rsa или ssh-ed25519):"
            local pub_key=""
            if ! read -r pub_key; then
                pub_key=""
            fi

            if [[ -z "$pub_key" ]]; then
                echo "Ключ не введен."
                return 1
            fi

            mkdir -p "$user_home/.ssh"
            chmod 700 "$user_home/.ssh" || true
            echo "$pub_key" >> "$user_home/.ssh/authorized_keys"

            chmod 600 "$user_home/.ssh/authorized_keys" || true
            chown -R "$target_user":"$target_user" "$user_home/.ssh" 2>/dev/null || chown -R "$target_user" "$user_home/.ssh" || true

            echo "Публичный ключ добавлен."
            return 0
            ;;
        *)
            echo "Пропуск настройки ключей."
            return 1
            ;;
    esac
}

#####################################
# НАЧАЛО ВЫПОЛНЕНИЯ И ОБНОВЛЕНИЕ APT
#####################################
echo "Обновление локальной базы пакетов..."
apt-get update -y || echo "Предупреждение: Не удалось обновить локальный кэш пакетов. Попытка продолжить..."

echo "Проверка и подключение репозитория universe..."
apt-get install -y software-properties-common || true
add-apt-repository -y universe || true

# Интерактивное полное обновление и очистка системы
if prompt_yes_no "Выполнить полное обновление системы (apt upgrade) и очистку?"; then
    echo "Запуск полного обновления пакетов (это может занять некоторое время)..."
    
    export APT_LISTCHANGES_FRONTEND=none
    
    # Защищаем вызов update от падения по set -e
    apt-get update -y || echo "Предупреждение: Не удалось обновить индексы пакетов, пробуем продолжить обновление..."
    
    # Флаги force-confdef и force-confold исключают зависания при конфликтах конфигурационных файлов (APT сохранит старые конфиги)
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    apt-get autoremove -y
    apt-get autoclean -y
    
    echo "Обновление и очистка успешно завершены."
    echo "ВНИМАНИЕ: Если были обновлены важные системные библиотеки или ядро, рекомендуется перезагрузить сервер после завершения работы скрипта."
    echo ""
else
    echo "Пропуск обновления пакетов."
fi

#####################################
# ОПТИМИЗАЦИЯ СЕТИ (PROXY TUNING)
#####################################
echo "==========================================================="
echo "Применение сетевых оптимизаций ядра (Proxy Tuning)..."
echo "==========================================================="

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
sysctl --system >/dev/null 2>&1 || echo "Предупреждение: Не все параметры sysctl применены (нормально для контейнеров LXC/OpenVZ)."
echo "Оптимизации сети успешно добавлены."
echo ""

#####################################
# УСТАНОВКА СИСТЕМНЫХ УТИЛИТ И МОНИТОРИНГА
#####################################
if prompt_yes_no "Установить системные утилиты и инструменты мониторинга (htop, btop, tcpdump, jq, tmux и др.)"; then
    echo "Установка системных утилит..."
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
        openssh-client || echo "Предупреждение: Не все утилиты были успешно установлены."
    echo "Системные утилиты успешно установлены."
else
    echo "Пропуск установки дополнительных утилит."
fi

#####################################
# СЕТЕВЫЕ НАСТРОЙКИ (BBR + Полное отключение IPv6)
#####################################
if prompt_yes_no "Включить TCP BBR и отключить IPv6"; then
    SYSCTL_CONF="/etc/sysctl.d/99-vps-hardening.conf"
    mkdir -p /etc/sysctl.d/

    # 1. Записываем настройки в sysctl.d
    cat > "$SYSCTL_CONF" <<EOF
# TCP BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    # Применяем sysctl прямо сейчас
    sysctl --system || echo "Предупреждение: Не все параметры sysctl были успешно применены. Это нормально для сред LXC/OpenVZ."

    # 2. МЕТОД GRUB (Для полноценных серверов и KVM-виртуализации)
    if [ -f /etc/default/grub ]; then
        if ! grep -q "ipv6.disable=1" /etc/default/grub; then
            # Делаем резервную копию перед внесением изменений
            cp /etc/default/grub /etc/default/grub.bak
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1 /' /etc/default/grub
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='ipv6.disable=1 /" /etc/default/grub
            sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
            sed -i "s/GRUB_CMDLINE_LINUX='/GRUB_CMDLINE_LINUX='ipv6.disable=1 /" /etc/default/grub
            update-grub || true
            echo "IPv6 отключен в загрузчике GRUB (применится после перезагрузки). Резервная копия сохранена в /etc/default/grub.bak"
        fi
    fi

    # 3. МЕТОД CRON (Безопасное добавление без использования деструктивного sort -u)
    if command -v crontab &>/dev/null; then
        cron_job="@reboot sleep 10 && sysctl --system"
        if ! crontab -l 2>/dev/null | grep -Fq "$cron_job"; then
            (crontab -l 2>/dev/null || true; echo "$cron_job") | crontab - || echo "Предупреждение: Не удалось обновить crontab."
            echo "Создано отложенное правило применения sysctl в Cron для защиты от сброса настроек сетью."
        else
            echo "Правило автозапуска sysctl уже присутствует в Cron."
        fi
    else
        echo "Предупреждение: утилита crontab не найдена. Настройка Cron-правила пропущена."
    fi

    echo "Сетевые настройки успешно применены и защищены от сброса после перезагрузки!"
fi

#####################################
# ROOT PASSWORD
#####################################
if prompt_yes_no "Сменить пароль root"; then
    while true; do
        rp=""
        rp2=""
        if ! read -rsp "Новый пароль root: " rp; then
            echo -e "\nВвод прерван."
            break
        fi
        echo
        if ! read -rsp "Повтор: " rp2; then
            echo -e "\nВвод прерван."
            break
        fi
        echo

        [[ "$rp" == "$rp2" ]] || { echo "Пароли не совпадают"; continue; }
        validate_password "$rp" || { echo "Слабый пароль. Требуется: минимум 12 symbols, заглавные, строчные, цифры и спецсимволы."; continue; }
        echo "root:$rp" | chpasswd
        echo "Пароль root изменен успешно."
        break
    done
fi

#####################################
# СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
#####################################
CREATED_USER=""

if prompt_yes_no "Создать обычного пользователя"; then
    uname=""
    if ! read -rp "Имя пользователя: " uname; then
        uname=""
    fi

    if [[ -z "$uname" ]]; then
        echo "Имя пользователя не может быть пустым."
    elif id "$uname" &>/dev/null; then
        echo "Пользователь уже существует"
        CREATED_USER="$uname"
    else
        # Обработка возможного падения на невалидных именах пользователей в adduser
        if ! adduser --disabled-password --gecos "" "$uname"; then
            echo "Ошибка: Не удалось создать пользователя с именем '$uname'." >&2
            echo "Проверьте формат имени (должно начинаться со строчной латинской буквы и содержать только строчные буквы и цифры)." >&2
        else
            while true; do
                up=""
                up2=""
                if ! read -rsp "Пароль для $uname: " up; then
                    echo -e "\nВвод прерван."
                    break
                fi
                echo
                if ! read -rsp "Повтор: " up2; then
                    echo -e "\nВвод прерван."
                    break
                fi
                echo

                [[ "$up" == "$up2" ]] || { echo "Пароли не совпадают"; continue; }
                validate_password "$up" || { echo "Слабый пароль. Требуется: минимум 12 symbols, заглавные, строчные, цифры и спецсимволы."; continue; }
                echo "$uname:$up" | chpasswd
                usermod -aG sudo "$uname"
                CREATED_USER="$uname"
                echo "Пользователь $uname успешно создан и добавлен в группу sudo."
                break
            done
        fi
    fi

    if [[ -n "$CREATED_USER" ]] && prompt_yes_no "Разрешить sudo без пароля для $CREATED_USER"; then
        echo "$CREATED_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$CREATED_USER"
        if ! safe_sudoers "$CREATED_USER"; then
            echo "Аварийное завершение работы из-за ошибки в файле sudoers." >&2
            exit 1
        fi
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

# Переключаем Ubuntu 24.04 с socket activation на стандартную службу ssh.service.
echo "Переключаем SSH на классический режим работы (отключение socket activation)..."
systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl enable ssh.service 2>/dev/null || true
systemctl start ssh.service 2>/dev/null || true

if prompt_yes_no "Изменить порт SSH"; then
    while true; do
        p=""
        if ! read -rp "Новый порт SSH (диапазон $MIN_SSH_PORT-$MAX_SSH_PORT): " p; then
            p=""
        fi
        if [[ -z "$p" ]]; then
            echo "Порт не изменен. Будет использован порт: $SSH_PORT"
            break
        fi
        validate_port "$p" || { echo "Недопустимый порт (выберите в диапазоне $MIN_SSH_PORT-$MAX_SSH_PORT)"; continue; }
        SSH_PORT="$p"
        break
    done
fi

# Проверим, подключена ли директория drop-in в основном файле sshd_config.
if [ -f /etc/ssh/sshd_config ]; then
    if ! grep -q "^Include /etc/ssh/sshd_config.d/\*\.conf" /etc/ssh/sshd_config; then
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    fi
fi

# Пишем конфигурацию в drop-in файл вместо изменения основного sshd_config
SSH_DROPIN="/etc/ssh/sshd_config.d/99-hardening.conf"
mkdir -p /etc/ssh/sshd_config.d/

cat > "$SSH_DROPIN" <<EOF
# Настройки, созданные автоматическим скриптом
Port $SSH_PORT
AddressFamily inet
PubkeyAuthentication yes
EOF

# Отключение входа по паролю (Только если ключи были успешно установлены)
if [ "$KEYS_INSTALLED" = "true" ]; then
    if prompt_yes_no "Отключить вход по паролю (PasswordAuthentication no)?"; then
        cat >> "$SSH_DROPIN" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
EOF
        echo "Вход по паролю ОТКЛЮЧЕН. Используйте ключи для авторизации."
    fi
fi

# Обеспечиваем наличие директории привилегий перед проверкой sshd -t
mkdir -p /run/sshd

# Проверка конфигурации SSH на ошибки перед перезапуском
echo "Проверка конфигурации SSH..."
if /usr/sbin/sshd -t; then
    systemctl daemon-reload
    systemctl restart ssh.service || echo "Предупреждение: Не удалось автоматически перезапустить ssh.service"
    echo "Служба SSH успешно перезапущена на порту $SSH_PORT"
else
    echo "Критическая ошибка конфигурации SSH! Откат изменений во избежание потери доступа." >&2
    rm -f "$SSH_DROPIN"
    systemctl restart ssh.service || true
fi

#####################################
# UFW (FIREWALL) 
#####################################
echo "Установка и настройка фаервола UFW..."
apt-get install -y ufw

# Безопасное отключение IPv6 в UFW (с проверкой существования параметра)
if grep -q "^IPV6=" /etc/default/ufw; then
    sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
else
    echo "IPV6=no" >> /etc/default/ufw
fi

ufw default deny incoming
ufw default allow outgoing

echo "Настраиваем порты (только IPv4)..."

# SSH
ufw allow "$SSH_PORT"/tcp comment 'SSH'

# Дополнительные TCP порты
TCP_PORTS=(80 443 8443 10443)
for port in "${TCP_PORTS[@]}"; do
    ufw allow "$port"/tcp
done

# Дополнительные UDP порты
UDP_PORTS=(443 8443)
for port in "${UDP_PORTS[@]}"; do
    ufw allow "$port"/udp
done

# Опциональная блокировка Ping (ICMP)
if prompt_yes_no "Блокировать входящие ICMP (Ping) запросы?"; then
    if [ -f /etc/ufw/before.rules ]; then
        sed -i 's/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/g' /etc/ufw/before.rules
        echo "Ping запросы заблокированы в настройках UFW."
    fi
fi

ufw --force enable

#####################################
# FAIL2BAN
#####################################
echo "Установка и настройка Fail2ban..."
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
if prompt_yes_no "Установить 3x-ui (потребуется интерактивная настройка панели)"; then
    if ! command -v curl &> /dev/null; then
        apt-get install -y curl
    fi

    XUI_VERSION=""

    echo "-------------------------------------"
    echo "ВЫБОР ВЕРСИИ 3X-UI"
    echo "1) Последняя стабильная версия (Latest) - РЕКОМЕНДУЕТСЯ"
    echo "2) Указать конкретную версию вручную (например, v2.9.4)"

    v_choice=1
    if ! read -rp "Ваш выбор (1-2): " v_choice; then
        v_choice=1
    fi

    if [[ "$v_choice" == "2" ]]; then
        while true; do
            tag=""
            if ! read -rp "Введите тег версии (например, v2.9.4): " tag; then
                tag=""
            fi
            if [[ "$tag" =~ ^v[0-9]+ ]]; then
                XUI_VERSION="$tag"
                break
            else
                echo "Неверный формат. Версия должна начинаться со строчной буквы 'v' (например, v2.9.4)."
            fi
        done
    fi

    echo "Запуск установки 3x-ui..."
    curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh -o /tmp/3x-ui-install.sh

    if [[ -n "$XUI_VERSION" ]]; then
        echo "Установка версии $XUI_VERSION..."
        bash /tmp/3x-ui-install.sh "$XUI_VERSION"
    else
        echo "Установка версии latest..."
        bash /tmp/3x-ui-install.sh
    fi

    rm -f /tmp/3x-ui-install.sh
fi

#####################################
# ФИНАЛ
#####################################
echo
echo "======================================"
echo "✔ НАСТРОЙКА VPS ЗАВЕРШЕНА УСПЕШНО"
echo "SSH порт: $SSH_PORT"
echo "IPv6: отключён (System + UFW)"
echo "UFW: включён (только v4 правила)"
echo "BBR: активирован"
echo "Fail2ban: активен"
if [ "$KEYS_INSTALLED" = "true" ]; then
    echo "SSH Ключи: УСТАНОВЛЕНЫ (вход по паролю отключен, если было выбрано)"
else
    echo "SSH Ключи: НЕ установлены"
fi
echo "======================================"
