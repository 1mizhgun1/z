#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

BASE="/Users/m.ugryumov/study/voenka/pro"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --n) rls_number="$2"; shift 2 ;;
            --x) rls_x="$2"; shift 2 ;;
            --y) rls_y="$2"; shift 2 ;;
            --azimuth) rls_azimuth="$2"; shift 2 ;;
            --view_angle) rls_view_angle="$2"; shift 2 ;;
            --radius) rls_radius="$2"; shift 2 ;;
            *)
                echo "Ошибка: Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done

    # Проверяем, переданы ли все обязательные параметры
    if [[ -z "$rls_number" || -z "$rls_x" || -z "$rls_y" || -z "$rls_azimuth" || -z "$rls_view_angle" || -z "$rls_radius" ]]; then
        echo "Ошибка: Необходимо передать все параметры!"
        echo "Использование: $0 --n <value> --x <value> --y <value> --azimuth <value> --view_angle <value> --radius <value>"
        exit 1
    fi
}

parse_args "$@"

TARGETS_DIR="$BASE/GenTargets/Targets"
MESSAGES_DIR="$BASE/Messages"
STORAGE_DIR="$BASE/rls/storage"
DB_FILE="$STORAGE_DIR/rls_$rls_number.db"

declare -A prev_coords
mkdir -p "$STORAGE_DIR"
messages_sent=0

# Инициализация базы данных SQLite
initialize_db() {
    sqlite3 "$DB_FILE" <<EOF
DROP TABLE IF EXISTS processed_files;
CREATE TABLE IF NOT EXISTS processed_files (
    filename TEXT PRIMARY KEY
);
EOF
}

initialize_db

echo "$(date +"%T") $rls_number $rls_x, $rls_y, $rls_azimuth, $rls_view_angle, $rls_radius" >> "${MESSAGES_DIR}/rls_${rls_number}_start_${messages_sent}"
messages_sent=$(( messages_sent + 1 ))

rls_x=$(( rls_x * 1000 ))
rls_y=$(( rls_y * 1000 ))
rls_view_angle=$(( rls_view_angle / 2 ))
rls_radius=$(( rls_radius * 1000 ))

# Функция для выполнения SQL-запросов
query_db() {
    sqlite3 "$DB_FILE" "$1"
}

# Функция для получения ID цели из имени файла
get_target_id() {
    local filename="$1"
    local target_id_hex=""

    for ((i=2; i<${#filename}; i+=4)); do
        target_id_hex+=${filename:i:2}
    done

    echo -n "$target_id_hex" | xxd -r -p
}

arctangens() {
    local target_x="$1"
    local target_y="$2"
    local rls_x="$3"
    local rls_y="$4"

    angle=0.0
    if (( $(echo "$target_x == $rls_x" | bc -l) )); then
        if (( $(echo "$target_y >= $rls_y") | bc -l )); then
            angle=90
        else
            angle=270
        fi
    else
        angle=$(echo "scale=4; a(($target_y - $rls_y)/($target_x - $rls_x))*180/3.1415927" | bc -l)
        angle=$(echo "scale=4; if($angle < 0) direction_angle+=360; $angle" | bc -l)
    fi

    echo "$angle"
}

# Функция для проверки попадания цели в сектор обзора РЛС
is_target_in_view() {
    local target_x="$1"
    local target_y="$2"
    local rls_x="$3"
    local rls_y="$4"
    local rls_azimuth="$5"
    local rls_view_angle="$6"
    local rls_radius="$7"

    # Вычисление угла между РЛС и целью в градусах
    angle=$(arctangens "$current_x" "$current_y" "$rls_x" "$rls_y")

    # Вычисление угла обзора РЛС
    rls_view_angle_left=$(echo "scale=4; $rls_azimuth - $rls_view_angle" | bc -l)
    rls_view_angle_right=$(echo "scale=4; $rls_azimuth + $rls_view_angle" | bc -l)

    # Корректировка углов обзора в диапазон [0, 360)
    if (( $(echo "$rls_view_angle_left < 0" | bc -l) )); then
        rls_view_angle_left=$(echo "scale=4; $rls_view_angle_left + 360" | bc -l)
    fi
    if (( $(echo "$rls_view_angle_right >= 360" | bc -l) )); then
        rls_view_angle_right=$(echo "scale=4; $rls_view_angle_right - 360" | bc -l)
    fi

    # Проверка расстояния цели от РЛС
    distance=$(echo "scale=4; sqrt(($target_x - $rls_x)^2 + ($target_y - $rls_y)^2)" | bc -l)
    if (( $(echo "$distance > $rls_radius" | bc -l) )); then
        return 1
    else
        # Проверка попадания угла цели в угол обзора РЛС
        if (( $(echo "$rls_view_angle_left < $rls_view_angle_right" | bc -l) )); then
            if (( $(echo "$angle >= $rls_view_angle_left && $angle <= $rls_view_angle_right" | bc -l) )); then
                return 0
            else
                return 1
            fi
        else
            if (( $(echo "$angle >= $rls_view_angle_left || $angle <= $rls_view_angle_right" | bc -l) )); then
                return 0
            else
                return 1
            fi
        fi
    fi
}

# Функция для определения скорости цели
get_target_speed() {
    local current_x="$1"
    local current_y="$2"
    local prev_x="$3"
    local prev_y="$4"

    speed=$(echo "scale=4; sqrt(($current_x - $prev_x)^2 + ($current_y - $prev_y)^2)" | bc -l)

    echo "$speed"
}

# Функция для определения типа цели по ее скорости
get_target_type() {
    local type=""
    if (( $(echo "$speed >= 8000 && $speed <= 10000" | bc -l) )); then
        type="ББ БР"
    elif (( $(echo "$speed >= 250 && $speed <= 1000" | bc -l) )); then
        type="крылатая ракета"
    elif (( $(echo "$speed >= 50 && $speed <= 249" | bc -l) )); then
        type="самолет"
    else
        type="неизвестный тип"
    fi

    echo "$type"
}

# Основной цикл скрипта
while true; do
    # Получение списка файлов в директории
    target_files=($(find "$TARGETS_DIR" -type f))

    for target_file in "${target_files[@]}"; do
        filename="$(basename "$target_file")"

        if [[ $(query_db "SELECT COUNT(*) FROM processed_files WHERE filename='$filename';") -gt 0 ]]; then
            continue
        fi

        query_db "INSERT INTO processed_files (filename) VALUES ('$filename');"

        read -r _ current_x _ current_y < "$target_file"

        if is_target_in_view "$current_x" "$current_y" "$rls_x" "$rls_y" "$rls_azimuth" "$rls_view_angle" "$rls_radius"; then
            time=$(date +"%T")
            target_id=$(get_target_id "$filename")

            if [[ ! -v prev_coords[$target_id] ]]; then
                echo "first: $filename"
                echo "$time $target_id $current_x $current_y" >> "${MESSAGES_DIR}/rls_${rls_number}_detect_${messages_sent}" 
            else
                echo "second: $filename"
                prev_x=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 1)
                prev_y=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 2)
                speed=$(get_target_speed "$current_x" "$current_y" "$prev_x" "$prev_y")
                type=$(get_target_type "$speed")
                echo "$time $target_id '$type' $speed" >> "${MESSAGES_DIR}/rls_${rls_number}_update_${messages_sent}"
            fi

            prev_coords[$target_id]="$current_x $current_y"
            messages_sent=$(( messages_sent + 1 ))
        fi
    done

    # Пауза на 0.5 секунды перед следующей итерацией
    sleep 0.5
done
