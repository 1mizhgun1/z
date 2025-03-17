#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

DB_FILE="targets.db"
LOG_FILE="rls.log"
OFFSET_FILE="offset.dat"

# Функция для выполнения SQL-запросов
query_db() {
    sqlite3 "$DB_FILE" "$1"
}

while true; do
    offset=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)
    log_size=$(stat -f %z "$LOG_FILE")
    # log_size=$(stat -c%s "$LOG_FILE")
    if [[ $offset -ge $log_size ]]; then
        sleep 0.1
        continue
    fi

    # exec 3< "$LOG_FILE"
    # seek "$offset" 3

#    tail -c +$((offset+1)) "$LOG_FILE" | while IFS= read -r line; do
    # while IFS= read -r line <&3; do
    awk -v offset="$offset" '
        NR==1 {seek = offset}
        NR>1 {seek += length($0) + 1}
        {print $0}
        END {print seek > "'$OFFSET_FILE'"}
    ' "$LOG_FILE" | while IFS= read -r line; do
        if [[ $line =~ ^"В "([0-9]{2}:[0-9]{2}:[0-9]{2})"обнаружена цель ID:"([0-9a-zA-Z]+)" с координатами "([0-9]+)" "([0-9]+)$ ]]; then
            timestamp="${BASH_REMATCH[1]}"
            target_id="${BASH_REMATCH[2]}"
            x="${BASH_REMATCH[3]}"
            y="${BASH_REMATCH[4]}"
            query_db "INSERT INTO targets (id, x, y, updated_at) VALUES ('$target_id', $x, $y, '$timestamp');"
        elif [[ $line =~ ^"В "([0-9]{2}:[0-9]{2}:[0-9]{2})" цель ID:"([0-9a-zA-Z]+)" типа '"(.+?)"' движется со скоростью "([0-9]+(?:\.[0-9]+)?)" м/с"$ ]]; then
            timestamp="${BASH_REMATCH[1]}"
            target_id="${BASH_REMATCH[2]}"
            type="${BASH_REMATCH[3]}"
            speed="${BASH_REMATCH[4]}"
            query_db "UPDATE targets SET speed=$speed, target_type='$type', updated_at='$timestamp' WHERE id='$target_id';"
        fi
    done

#    offset=$(stat -f %z "$LOG_FILE")
#    # offset=$(stat -c%s "$LOG_FILE")
#    echo "$offset" > "$OFFSET_FILE"

    sleep 0.1
done
