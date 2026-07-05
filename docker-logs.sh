#!/bin/bash

# ================= НАЛАШТУВАННЯ ІГНОРУВАННЯ =================
IGNORE_CONTAINERS="custom-test-container"
# ============================================================

CFG_DIR="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.d"
TMP_FILE="/tmp/cw_docker.json"
FINAL_FILE="$CFG_DIR/docker_auto.json"
AGENT_CTL="/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"
LOG_FILE="/var/log/cw-docker-auto.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "=== Запуск скрипта автоматизації Docker логів ==="

if [ ! -f "$AGENT_CTL" ]; then
    log_message "ПОМИЛКА: Бінарник агента не знайдено за шляхом $AGENT_CTL. Вихід."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_message "ПОМИЛКА: Утиліту 'jq' не встановлено. Встановіть її."
    exit 1
fi

JSON_ITEMS=$(jq -n '[]')
found_containers=""

# Опитуємо всі контейнери (-a)
for id in $(docker ps -a -q); do
    name=$(docker inspect --format '{{.Name}}' "$id" | sed 's/\///')
    log=$(docker inspect --format '{{.LogPath}}' "$id")
    
    # Якщо шлях до логу пустий (наприклад, інший лог-драйвер), пропускаємо
    if [ -z "$log" ] || [ "$log" = "<no value>" ]; then
        log_message "Попередження: Контейнер $name не має шляху до лог-файлу (можливо, не json-file драйвер)."
        continue
    fi

    # Перевіряємо список ігнорування
    should_ignore=false
    for skip in $IGNORE_CONTAINERS; do
        if [ "$name" = "$skip" ]; then
            should_ignore=true
            break
        fi
    done
    
    if [ "$should_ignore" = true ]; then
        log_message "Інфо: Контейнер $name пропущено (в списку ігнорування)."
        continue
    fi
    
    # Формуємо об'єкт БЕЗ перевірки [ -f "$log" ], довіряючи Docker та CloudWatch Agent
    ITEM=$(jq -n \
        --arg file "$log" \
        --arg stream "{instance_id}/$name" \
        '{file_path: $file, log_group_name: "/aws/ec2/docker-containers", log_stream_name: $stream, retention_in_days: 30}')
    
    JSON_ITEMS=$(echo "$JSON_ITEMS" | jq --argjson item "$ITEM" '. += [$item]')
    found_containers="$found_containers $name"
done

jq -n --argjson list "$JSON_ITEMS" '{"logs":{"logs_collected":{"files":{"collect_list": $list}}}}' > "$TMP_FILE"

if [ "$found_containers" = "" ]; then
    log_message "Iнфо: Жодного активного контейнера для збору логів не знайдено."
else
    log_message "Знайдено контейнери для відправки в AWS:$found_containers"
fi

if ! cmp -s "$TMP_FILE" "$FINAL_FILE"; then
    log_message "Зміни виявлено! Оновлюємо конфігурацію CloudWatch Agent..."
    mv "$TMP_FILE" "$FINAL_FILE"
    
    CMD_OUT=$("$AGENT_CTL" -a append-config -m ec2 -s -c file:"$FINAL_FILE" 2>&1)
    if [ $? -eq 0 ]; then
        log_message "УСПІХ: Нову конфігурацію Docker успішно додано до CloudWatch Agent."
    else
        log_message "ПОМИЛКА при виконанні append-config: $CMD_OUT"
    fi
else
    log_message "Змін немає. Поточна конфігурація актуальна."
    rm -f "$TMP_FILE"
fi

log_message "=== Роботу скрипта завершено ==="
echo "" >> "$LOG_FILE"
