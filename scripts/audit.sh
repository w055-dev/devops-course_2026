#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"; ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')";
((FAIL++))
 fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# Реализация TODO 1
check "Порт SSH изменён (не 22)" "not_22" "$( [[ $(sudo sshd -T | awk '/^port/{print $2}') != "22" ]] && echo "not_22" )"

# Реализация TODO 2
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"


echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# Реализация TODO 3
check "Политика по умолчанию для входящих — deny" "deny" "$(sudo ufw status verbose | grep 'Default:' | awk '{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
# а) служба nginx активна
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"

# б) конфигурация nginx синтаксически корректна
if sudo nginx -t > /dev/null 2>&1; then
    NGINX_TEST_RESULT="ok"
else
    NGINX_TEST_RESULT="error"
fi
check "Конфигурация nginx корректна" "ok" "$NGINX_TEST_RESULT"

# в) сертификат истекает не ранее чем через 30 дней (2592000 секунд)
# Флаг -checkend возвращает 0, если сертификат действителен дольше указанного времени.
if openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt > /dev/null 2>&1; then
    CERT_RESULT="valid"
else
    CERT_RESULT="expired_soon"
fi
check "Сертификат действителен более 30 дней" "valid" "$CERT_RESULT"

# г) нет файлов с правами 666 (доступных на запись всем) и права ключа 600
NO_WORLD_WRITABLE=$(sudo find /var/www/devops-site -perm -o+w | wc -l)
KEY_PERMS=$(sudo stat -c '%a' /etc/ssl/private/devops.key)

# Проверяем, что файлов, доступных на запись всем, НЕТ (0 штук), и права ключа 600
if [[ "$NO_WORLD_WRITABLE" -eq 0 && "$KEY_PERMS" == "600" ]]; then
    SECURE_RESULT="secure"
else
    SECURE_RESULT="insecure"
fi
check "Права файлов безопасны (нет 666, ключ 600)" "secure" "$SECURE_RESULT"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1