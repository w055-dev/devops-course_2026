#!/usr/bin/env bash

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1.Разбор аргумента --dry-run

DRY_RUN_ARG=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN_ARG="--dry-run"
elif [[ -n "${1:-}" ]]; then
    echo "Неизвестный аргумент: $1" >&2
    exit 1
fi


# 2.Проверки по требованиям 4 и 5

# Требование 4: Проверка наличия index.html
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html не найден!" >&2
    exit 1
fi

# Требование 5: Проверка незафиксированных изменений
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения!" >&2
    exit 1
fi

# 3. Синхронизация каталога
echo "Синхронизация ${LOCAL_DIR} -> ${REMOTE}:${REMOTE_DIR}..."
rsync -avz ${DRY_RUN_ARG} --delete --chmod=D755,F644 \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ -n "${DRY_RUN_ARG}" ]]; then
    echo "Пробный запуск завершен. Изменения на сервере не применены."
    exit 0
fi


# 5. Проверка доступности ${SITE_URL} и завершение с корректным кодом возврата
echo "Проверка доступности ${SITE_URL}..."
if ! curl -f -s -o /dev/null --cacert "${CA_CERT}" "${SITE_URL}"; then
    echo "Ошибка: проверка доступности ресурса не пройдена!" >&2
    exit 1
fi

COMMIT_HASH=$(git rev-parse --short HEAD)
echo "Успешно развернуто. Коммит: ${COMMIT_HASH}"
exit 0
