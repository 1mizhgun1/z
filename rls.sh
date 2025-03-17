#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

target_dir="/Users/m.ugryumov/study/voenka/rls/GenTargets/Targets"
db_file="targets.db"
LOG_FILE="rls.log"

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

    echo "В $(date +"%T") запущена РЛС-$rls_number с параметрами: x=$rls_x, y=$rls_y, azimuth=$rls_azimuth, view_angle=$rls_view_angle, radius=$rls_radius" >> "$LOG_FILE"

    rls_x=$(( rls_x * 1000 ))
    rls_y=$(( rls_y * 1000 ))
    rls_view_angle=$(( rls_view_angle / 2 ))
    rls_radius=$(( rls_radius * 1000 ))
}

parse_args "$@"

# Функция для выполнения SQL-запросов
query_db() {
    sqlite3 "$db_file" "$1"
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
    target_files=($(find "$target_dir" -type f))

    for target_file in "${target_files[@]}"; do
        filename="$(basename "$target_file")"

        # Проверка, обработан ли файл
        if [ $(query_db "SELECT COUNT(*) FROM processed_files WHERE filename='$filename';") -gt 0 ]; then
            continue
        fi

        # Добавляем файл в обработанные
        query_db "INSERT INTO processed_files (filename) VALUES ('$filename');"

        # Извлечение координат из файла
        read -r _ current_x _ current_y < "$target_file"

        # Проверка попадания цели в сектор обзора РЛС
        if is_target_in_view "$current_x" "$current_y" "$rls_x" "$rls_y" "$rls_azimuth" "$rls_view_angle" "$rls_radius"; then
            time=$(date +"%T")
            target_id=$(get_target_id "$filename")
            IFS='|' read -r prev_x prev_y <<< "$(query_db "SELECT x, y FROM targets WHERE id='$target_id';")"

            if [ -z "$prev_x" ]; then
                # query_db "INSERT INTO targets (id, x, y, updated_at) VALUES ('$target_id', $current_x, $current_y, CURRENT_TIMESTAMP);"
                echo "В $time обнаружена цель ID:$target_id с координатами $current_x $current_y" >> "$LOG_FILE"
            else
                speed=$(get_target_speed "$current_x" "$current_y" "$prev_x" "$prev_y")
                type=$(get_target_type "$speed")
                # query_db "UPDATE targets SET x=$current_x, y=$current_y, speed=$speed, target_type='$type', updated_at=CURRENT_TIMESTAMP WHERE id='$target_id';"
                echo "В $time цель ID:$target_id типа '$type' движется со скоростью ${speed} м/с" >> "$LOG_FILE"
            fi
        fi
    done

    # Пауза на 0.5 секунды перед следующей итерацией
    sleep 0.5
done
