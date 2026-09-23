<div align="center">

<img src="assets/logo.png" alt="Hardened Master Engine Logo" width="180" style="max-width: 100%;">

# 🛡️ Hardened Master Engine v1.1.0 Universal
### Production AutoSetup Monoscript: OS Hardening + BBR + Nginx L4 Stream + 3X-UI + Zero-Touch SQLite + Grouped Hosts + AdGuard DoH + Port Hopping

[![OS: Ubuntu & Debian](https://img.shields.io/badge/OS-Ubuntu%2020.04--26.04%20%7C%20Debian%2011--13-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Xray Core](https://img.shields.io/badge/Xray--core-24.9%2B%20%7C%2025.x%20%7C%2026.x-2962FF?style=for-the-badge&logo=shield&logoColor=white)](https://github.com/XTLS/Xray-core)
[![3X-UI](https://img.shields.io/badge/Panel-3X--UI%20Zero--Touch-009688?style=for-the-badge&logo=awesomelists&logoColor=white)](https://github.com/mhsanaei/3x-ui)
[![Security: Hardened](https://img.shields.io/badge/Security-ML--KEM--768%20%7C%20BBR%20%7C%20UFW-4CAF50?style=for-the-badge&logo=auth0&logoColor=white)](https://github.com/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

<p align="center">
  <b>Комплексный монолитный автоустановщик высокопроизводительной, отказоустойчивой и скрытной прокси-инфраструктуры корпоративного уровня.</b><br>
  Разворачивается «из коробки» за 5 минут в одну команду без ручной настройки веб-интерфейса панели.
</p>

[Спецификация конвейера](#-спецификация-архитектурного-конвейера-фазы-04) •
[Схема движения трафика](#-архитектурная-схема-движения-трафика) •
[Быстрый старт](#-быстрый-старт-развертывание-в-одну-команду) •
[Ключевые технологии](#-ключевые-технологические-преимущества) •
[Инструкции для клиентов](#-клиентские-подключения-и-экосистема) •
[Диагностика](#-экспресс-диагностика-и-аудит)

</div>

---

## 🌟 Ключевые технологические преимущества v1.1.0 Universal

* **Полный Zero-Touch автопилот:** Пользователю больше не нужно вручную создавать инбаунды, прописывать порты или настраивать пути в веб-панели 3X-UI. Скрипт напрямую оркестрирует локальную базу SQLite (`/etc/x-ui/x-ui.db`), развертывая готовую рабочую конфигурацию с единым профилем `Client-Unified`.
* **Гео-адаптивный конвейер (RU vs EU/Global):** Автоматическое определение геолокации VPS. Для узлов внутри РФ автоматически подключаются CDN-зеркала GitHub, оптимизированные резолверы Яндекс DNS и изолированный DoH-пул по порту 443 для надежного обхода ТСПУ/РКН. Для зарубежных узлов активируется скоростной Турбо-пул (DNS-over-QUIC / HTTP/3).
* **Сквозное постквантовое шифрование VLESS Encryption (ML-KEM-768):** Автоматическая генерация симметричной квантово-устойчивой ключевой пары через нативный бинарник Xray (`xray vlessenc`).
* **VLESS xHTTP Stream-One + XTLS-Vision:** Прямое H2C-проксирование через Nginx Mainline (`proxy_http_version 2`) без буферизации (`proxy_buffering off`), с архитектурным пулом соединений XMUX (`maxConcurrency: 0`, `maxConnections: 1-3`, `noSSEHeader: true`) и динамическим рандомизированным паддингом пакетов (`xPaddingBytes: 100-500`).
* **Steal-Oneself REALITY с защитой Anti-Loop (Port 9443):** Безопасный камуфляж под собственный домен. Сканеры активного зондирования и обычные веб-браузеры перенаправляются Xray на изолированный локальный слушатель `127.0.0.1:9443` с Proxy Protocol (`xver: 1`), полностью исключая петлю бесконечной пересылки пакетов.
* **Автоматизация сгруппированных хостов (Host Groups):** Автоматическое заполнение таблицы `hosts` в 3X-UI с поддержкой полной схемы GORM:
  * **Группа `ALL_443`:** Объединяет все протоколы (Steal REALITY, Classic REALITY, Hysteria 2) в одну универсальную карточку подписки на порту 443.
  * **Группа `xHTTP`:** Выделенная карточка с принудительным `TLS`, SNI, ALPN `["h2"]` и браузерным фингерпринтом Chrome.
* **Персистентный Port Hopping для Hysteria 2:** Защита от троттлинга UDP-трафика со стороны провайдеров через динамический трансляционный пул `20000:50000/udp -> 443/udp`, персистентно вшиваемый в таблицу `*nat` брандмауэра UFW.
* **TCP MSS Clamping:** Персистентное ограничение максимального размера сегмента (`--clamp-mss-to-pmtu` в таблице `*mangle`), предотвращающее зависание и фрагментацию TLS-хендшейков в мобильных и туннельных сетях.
* **Аппаратное отключение IPv6 и оптимизация ядра:** Переключение алгоритма перегрузки на TCP BBR + fq, расширение очередей сокетов (`somaxconn = 65535`), лимит файловых дескрипторов 524 288 и отключение IPv6 на уровне `sysctl` и ядра через параметры GRUB (`ipv6.disable=1`).
* **Приватный DoH AdGuard Home:** Интегрированный DNS-over-HTTPS резолвер со Split-DNS и авторизацией по токенам `ClientID` для защиты от несанкционированного сканирования (Open Resolver).

---

## 📊 Архитектурная схема движения трафика

```mermaid
graph TD
    Client443TCP[Клиент: TCP 443 / 8443] --> NginxStream(Nginx L4 Stream Router)
    ClientUDP[Клиент: UDP 443 / 20000-50000 / 8443 / 8444] --> UFW_NAT{UFW Firewall / NAT}

    subgraph UFW_Engine ["Персистентная фильтрация и NAT"]
        UFW_NAT -->|UDP 20000-50000 PREROUTING REDIRECT| XrayHy2[Hysteria 2 :443 UDP]
        UFW_NAT -->|UDP 443 Прямой| XrayHy2
        UFW_NAT -->|UDP 8443| XrayAWG3[AmneziaWG v3.1 :8443 UDP]
        UFW_NAT -->|UDP 8444| XrayAWG2[AmneziaWG v2.0 :8444 UDP]
    end

    NginxStream -->|SNI: Главный / WWW / Доп. домены| NginxSock[Unix Socket в RAM: /dev/shm/nginx-http.sock]
    NginxStream -->|SNI: DoH dns.domain.online| NginxSock
    NginxStream -->|SNI: Steal cdn.domain.online| XraySteal[Xray Steal REALITY :45443]
    NginxStream -.->|L4 Failover Backup: Xray остановлен| NginxSock
    NginxStream -->|SNI: Внешний SNI swdist.microsoft.com| XrayClassic[Xray Classic REALITY :46443]

    XraySteal -->|Fallback не-REALITY / Активный зонд xver=1| NginxAntiLoop[Nginx HTTP Anti-Loop :9443]
    XrayClassic -->|Fallback / Direct xver=0| ExtMirror[Внешний легитимный сервер :443]

    NginxSock --> NginxL7[Nginx Mainline HTTP L7 Engine]
    NginxAntiLoop --> NginxL7

    subgraph Internal_Services ["Изолированные службы (Строго 127.0.0.1)"]
        NginxL7 -->|Корень / | DecoyFront[Decoy Маскировка: DataSphere SPA / CosmosCloud]
        NginxL7 -->|Путь /my-3x-panel/| PanelCore[3X-UI Веб-панель :10443]
        NginxL7 -->|Путь подписок /my-post-key/| SubServer[3X-UI Сервер подписок :55443]
        NginxL7 -->|H2C Стрим /Stream-One-Path/| XrayXHTTP[Xray VLESS xHTTP :50443]
        NginxL7 -->|Домен dns.domain.online /dns-query/| AGH_DoH[AdGuard Home DoH Core :3000 / :53]
    end

🧩 Спецификация архитектурного конвейера (Фазы 0–4)

Фаза 0: Детекция сетевого гео-профиля

  - Автоматический запрос локации IP (ipinfo.io / ip-api.com).
  - Профиль [1] RU: Резолверы Яндекс DNS (77.88.8.8, 77.88.8.1), пулы зеркал
    GitHub (ghfast.top, ghproxy.net), принудительный DoH over TCP.
  - Профиль [2] EU/Global: Прямые апстримы Cloudflare (1.1.1.1), Google
    (8.8.8.8), Quad9 (9.9.9.9), DoQ/QUIC турбо-пул.

Фаза 1: Системный Hardening ОС

  - Ядро: Алгоритм bbr + планировщик fq, увеличение буферов сокетов tcp_rmem /
    tcp_wmem до 16 МБ, защита tcp_syncookies = 1, обратная фильтрация rp_filter
    = 1.
  - Защита от утечек IPv6: Полное аппаратное отключение IPv6 в sysctl и на
    уровне ядра через загрузчик GRUB (ipv6.disable=1).
  - Безопасность SSH: Автоматический переход с системных сокетов ssh.socket на
    классический демон ssh.service, гарантированное включение
    /etc/ssh/sshd_config.d/*.conf, генерация ключей Ed25519, защита Fail2ban
    (maxretry = 5, bantime = 1h).

Фаза 2: Внешний шлюз, SSL и AdGuard Home

  - Nginx Mainline: Подключение официального репозитория nginx.org с бесшовным
    откатом на дистрибутивный пакет.
  - Межпроцессная связь в RAM: Трафик между L4 Stream и L7 пересылается через
    сокет оперативной памяти /dev/shm/nginx-http.sock без сетевых оверхедов.
  - Нативный Certbot без Snapd: Выпуск сертификатов Let's Encrypt через
    системный пакет APT с деплой-хуками нормализации прав (chmod 755 / 644) или
    через acme.sh (Cloudflare DNS-01 API).
  - Decoy Fronts: Генерация адаптивного SPA-сайта DataSphere Analytics
    Enterprise с живой телеметрией SLA (±10%), эмуляцией сессий и защитой от
    сканеров безопасности (nikto, sqlmap, censys, shodan блокируются мгновенно).

Фаза 3: Ядро 3X-UI и Zero-Touch SQLite

  - Автоматическая установка последней версии панели 3X-UI.
  - Нативная генерация постквантового ключа ML-KEM-768 через команду $XRAY_BIN
    vlessenc.
  - Direct SQLite Injection: Внедрение учетных записей, параметров шаблона Xray,
    инбаундов и настроек роутинга напрямую в /etc/x-ui/x-ui.db.
  - Автоматическое создание GORM Host Groups: Полная очистка и пересборка
    таблицы hosts с автоматической генерацией групп ALL_443 и xHTTP.
  - Единый профиль: Создание унифицированного клиента Client-Unified с
    генерацией готовых ссылок подписки во всех форматах (Base64, JSON, Clash).

Фаза 4: Финальный замок брандмауэра

  - UFW & NAT Port Hopping: Персистентная инъекция цепочек *nat и *mangle в
    /etc/ufw/before.rules. Диапазон 20000:50000/udp транслируется в порт
    Hysteria 2.
  - TCP MSS Clamping: Правило -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j
    TCPMSS --clamp-mss-to-pmtu.
  - Абсолютная изоляция внутренних портов: Порты 10443, 55443, 50443, 9443,
    3000, 45443, 46443 закрываются фаерволом снаружи и доступны исключительно
    через внутренние прокси Nginx.
  - Экспорт реквизитов доступа в защищенный файл /root/vpn_credentials.txt
    (chmod 600).

🚀 Быстрый старт: Развертывание в одну команду

Требования к серверу:

  - ОС: Чистая установка Ubuntu (20.04 / 22.04 / 24.04 / 26.04) или Debian (11
    / 12 / 13).
  - Права: Суперпользователь root.
  - Домен: Привязанный к IP сервера домен.

[!CAUTION]

⚠️ Критическое требование к Cloudflare (Только «Серое облако» / DNS-Only)

Все DNS-записи доменов и поддоменов (A-записи для основного домена, поддомена
DoH dns. и поддомена Steal cdn.) в Cloudflare обязаны находиться в режиме
DNS-Only (Серое облако)!
Включение проксирования Cloudflare (Оранжевое облако) заблокирует L4
SNI-маршрутизацию, REALITY и работу xHTTP.

Запуск установщика:

Выполните команду на Вашем сервере:

bash <(curl -fsSL https://raw.githubusercontent.com/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui/main/install.sh)

или через wget:

wget -qO- https://raw.githubusercontent.com/Itman75/Nginx-L4-Stream-Router-Mask-for-3x-ui/main/install.sh | bash

📋 Пошаговый интерактивный опросник параметров

Мастер установки интерактивно запросит параметры развертывания (в скобках
указаны значения по умолчанию, применяемые нажатием Enter):

| Шаг   | Параметр                     | Значение по умолчанию         | Описание                                                                                |
| :---- | :--------------------------- | :---------------------------- | :-------------------------------------------------------------------------------------- |
| **0** | **Сетевой профиль**          | Автодетект (`1` или `2`)      | `1` — РФ (Яндекс DNS, DoH TCP, зеркала), `2` — Зарубежный (Cloudflare DNS, DoQ).        |
| **1** | **Основной домен**           | —                             | Ваш домен (например, `yourdomain.online`).                                              |
| **1** | **Email для Let's Encrypt**  | Enter для пропуска            | Email для сервисных уведомлений срока сертификатов.                                     |
| **2** | **Системный Hardening**      | `y`                           | Полное обновление системы (`apt upgrade`), BBR, отключение IPv6, утилиты.               |
| **2** | **Порт SSH**                 | Текущий активный              | Возможность сменить порт SSH (например, на `60022`) с генерацией ключей Ed25519.        |
| **3** | **Порты и URI панели 3X-UI** | `:10443`, `/my-3x-panel/`     | Внутренний порт и секретный URI-префикс веб-интерфейса панели.                          |
| **3** | **Сервер подписок 3X-UI**    | `:55443`, `/my-post-key/`     | Внутренний порт и секретный URI-путь раздачи клиентских подписок.                       |
| **3** | **VLESS xHTTP Inbound**      | `:50443`, `/Stream-One-Path/` | Локальный H2C-порт инбаунда xHTTP и путь стрима.                                        |
| **4** | **Steal-Oneself REALITY**    | `y` (`:45443`)                | Поддомен `cdn.yourdomain.online`, маскировка под свой сайт с защитой Anti-Loop `:9443`. |
| **4** | **Classic REALITY**          | `y` (`:46443`)                | Автоматический выбор оптимального SNI с наименьшим RTT (`gateway.icloud.com` и др.).    |
| **6** | **Hysteria 2 (UDP)**         | `y` (`:443`, Mode 2)          | Скоростной QUIC-транспорт. Режим 2 активирует Port Hopping (`20000-50000/udp`).         |
| **6** | **AmneziaWG v3.1 / v2.0**    | `y` (`:8443` / `:8444`)       | WG3 для ПК/смартфонов (MTU 1320) и Legacy для роутеров Keenetic/OpenWrt (MTU 1360).     |
| **7** | **Привратный AdGuard DoH**   | `y` (`dns.yourdomain.online`) | Приватный DoH-резолвер с защитой ClientID (`home-router`) и Split-DNS.                  |
| **8** | **Сайт-маскировка**          | `1`                           | `1` — DataSphere Analytics Enterprise (SPA), `2` — CosmosCloud, `3` — Nginx Stub.       |
| **8** | **Движок SSL**               | `1`                           | `1` — Нативный Certbot HTTP-01 без Snapd (рекомендуется), `2` — acme.sh DNS-01.         |

[!IMPORTANT] Обязательное действие после завершения скрипта:

1.  Откройте новое окно терминала и проверьте подключение по SSH к заданному
    порту.
2.  В основном терминале выполните команду: reboot.
    После перезагрузки сетевые оптимизации ядра, правила фаервола и служба 3X-UI
    активируются в штатном режиме.

📱 Клиентские подключения и экосистема

Скрипт формирует единую мультиформатную подписку Client-Unified, в которую
автоматически упаковываются все сгенерированные протоколы. Все реквизиты доступа
сохраняются в файл: /root/vpn_credentials.txt.

Ссылки подписок:

  - Прямая подписка (Base64): https://yourdomain.online/my-post-key/ВАШ_SUB_ID
    (Для v2rayNG, v2rayN, FoXray, Karing)
  - JSON-подписка: https://yourdomain.online/my-post-key/json/ВАШ_SUB_ID
    (Специально для Happ Proxy, Streisand, NekoBox, Sing-box)
  - Clash / Mihomo YAML:
    https://yourdomain.online/my-post-key/ВАШ_SUB_ID?clash=1
    (Для Clash Verge Rev, Flclash, Mihomo Party)

Матрица поддержки клиентов:

| Платформа        | Рекомендуемое ПО                               | VLESS xHTTP + Vision | VLESS REALITY | Hysteria 2 | AmneziaWG | DoH |
| :--------------- | :--------------------------------------------- | :------------------: | :-----------: | :--------: | :-------: | :-: |
| **iOS / iPadOS** | **Happ Proxy** / **Streisand** / **FoXray**    |                      |               |            | (v3.1)    |     |
| **Android**      | **v2rayNG** / **NekoBox** / **Sing-box**       |                      |               |            |           |     |
| **Windows**      | **v2rayN** (v6.40+) / **NekoBox** / **Mihomo** |                      |               |            |           |     |
| **macOS**        | **V2RayXS** / **FoXray** / **NekoBox**         |                      |               |            | (v3.1)    |     |
| **Роутеры**      | **Keenetic** / **OpenWrt (Podkop)**            |                      |               | (клиент)   | (v2.0)    |     |

🌐 Настройка роутеров для приватного AdGuard Home DoH

При установке AdGuard Home защищается уникальным идентификатором ClientID (по
умолчанию home-router). Неавторизованные запросы ботов и сканеров отбрасываются
с кодом REFUSED.

  - URL веб-интерфейса: https://dns.yourdomain.online/
  - URL DoH для роутеров: https://dns.yourdomain.online/dns-query/home-router

1. Keenetic (KeeneticOS 3.x / 4.x):

1.  Перейдите в веб-интерфейс Keenetic (192.168.1.1) -> «Сетевые правила» ->
    «Интернет-фильтр» (или свойства подключения -> «Серверы DNS»).
2.  Нажмите «Добавить сервер DNS»:
      - Адрес DNS (Bootstrap): 77.88.8.8 или 9.9.9.9 (не вводите IP сервера:
        порт 53 закрыт фаерволом снаружи);
      - Протокол: DNS-over-HTTPS (DoH);
      - URL-адрес DoH: https://dns.yourdomain.online/dns-query/home-router;
      - Доменное имя (SNI): dns.yourdomain.online.
3.  Включите опцию «Игнорировать DNS провайдера» и сохраните.

2. OpenWrt (Пакет Podkop):

1.  Откройте LuCI -> «Службы» -> «Podkop» -> вкладка «Настройки».
2.  В блоке параметров DNS укажите:
      - Тип протокола: DNS через HTTPS (DoH);
      - DNS-сервер: (без https://) dns.yourdomain.online/dns-query/home-router;
      - Bootstrap DNS: 77.88.8.8 или 1.1.1.1.
3.  Нажмите «Сохранить и применить». Все DNS-запросы клиентов локальной сети
    будут шифроваться и фильтроваться на Вашем VPS.

🩺 Экспресс-диагностика и аудит

Команды быстрой проверки состояния всех компонентов системы:

# 1. Проверка синтаксиса и статуса Nginx
nginx -t && systemctl status nginx --no-pager

# 2. Проверка активности сокета Nginx в RAM
ls -la /dev/shm/nginx-http.sock

# 3. Тест ответа веб-маскировки (HTTP/2 TLS)
curl -Iv --http2 https://yourdomain.online

# 4. Проверка защищенного шлюза xHTTP (должен отдавать 404 Not Found без тела)
curl -Iv --http2 https://yourdomain.online/Stream-One-Path/

# 5. Тестирование работы приватного DoH AdGuard Home
curl -Iv "https://dns.yourdomain.online/dns-query/home-router?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB"

# 6. Проверка активности службы и локального сокета 3X-UI
ss -tlnp | grep -E '10443|55443|50443|45443|46443|9443|3000'

# 7. Проверка правил UFW и активных перенаправлений NAT Port Hopping
ufw status verbose
iptables -t nat -L PREROUTING -n -v
iptables -t mangle -L FORWARD -n -v

🔄 Автоматическое продление SSL-сертификатов

Продление сертификатов полностью автоматизировано:

  - Certbot: Системный таймер certbot.timer запускается дважды в сутки. При
    успешном продлении вызывается деплой-хук
    /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh, который устанавливает
    права 755 / 644 для беспрепятственного чтения сертификатов демонами nginx и
    nobody (Xray), после чего безопасно перезагружает конфигурацию: systemctl
    reload nginx.
  - acme.sh: Обновление сертификатов контролируется встроенным заданием cron с
    перезагрузкой Nginx.

Ручная проверка продления сертификатов:

# Для Certbot (dry-run тест):
certbot renew --dry-run

# Для acme.sh:
~/.acme.sh/acme.sh --cron --home ~/.acme.sh

💾 Резервное копирование и восстановление

Для исключения повреждения базы данных SQLite (x-ui.db) и WAL-журналов резервное
копирование и восстановление осуществляются с кратковременной остановкой служб:

Создание резервной копии:

# Остановка служб для консистентного слепка БД
systemctl stop x-ui AdGuardHome 2>/dev/null || true

# Создание архива конфигураций
tar -czvf /root/backup_vpn_$(date +%F).tar.gz \
  /etc/nginx \
  /etc/letsencrypt \
  /etc/ssl/acme \
  /opt/AdGuardHome/AdGuardHome.yaml \
  /etc/x-ui \
  /var/www/html \
  /etc/ufw/before.rules

# Запуск служб
systemctl start x-ui AdGuardHome 2>/dev/null || true

Восстановление из архива:

# Остановка служб
systemctl stop x-ui nginx AdGuardHome 2>/dev/null || true

# Удаление временных файлов WAL и блокировок
rm -f /etc/x-ui/x-ui.db-wal /etc/x-ui/x-ui.db-shm

# Распаковка резервной копии
tar -xzvf /root/backup_vpn_YYYY-MM-DD.tar.gz -C /

# Проверка конфигурации Nginx и запуск
nginx -t && systemctl start nginx x-ui AdGuardHome

📄 Лицензия

Проект распространяется под свободной лицензией MIT. Подробная информация
содержится в файле LICENSE.


---
