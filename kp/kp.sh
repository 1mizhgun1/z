#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

BASE="/Users/m.ugryumov/study/voenka/pro"

DB_FILE="$BASE/kp/kp.db"
LOG_FILE="$BASE/pro.log"
MESSAGES_DIR="$BASE/Messages"

# Функция для выполнения SQL-запросов
query_db() {
    sqlite3 "$DB_FILE" "$1"
}

while true; do
    files=($(find "$MESSAGES_DIR" -type f))

    for file in "${files[@]}"; do
        filename="$(basename "$file")"

        if [[ $filename =~ ^rls_([0-9]+)_detect_([0-9]+)$ ]]; then
            rls_number="${BASH_REMATCH[1]}"
            read -r timestamp target_id x y < "$file"
            query_db "INSERT INTO targets (id, x, y, updated_at) VALUES ('$target_id', $x, $y, '$timestamp');"
            echo "В $timestamp РЛС-$rls_number обнаружила цель ID=$target_id с координатами X=$x Y=$y" >> "$LOG_FILE"
        elif [[ filename =~ ^rls_([0-9]+)_update_([0-9]+)$ ]]; then
            read -r timestamp target_id type speed < "$file"
            query_db "UPDATE targets SET speed=$speed, target_type='$type', updated_at='$timestamp' WHERE id='$target_id';"
            echo "В $time РЛС-$rls_number обновила цель ID=$target_id тип=$type скорость=$speed" >> "$LOG_FILE"
        fi

        rm "$MESSAGES_DIR/$filename"
    done

    sleep 0.2
done
