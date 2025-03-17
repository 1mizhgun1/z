#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

get_target_id() {
    local filename="$1"
    local target_id_hex=""

    for ((i=2; i<${#filename}; i+=4)); do
        target_id_hex+=${filename:i:2}
    done

    echo -n "$target_id_hex" | xxd -r -p
}

filename="4a3377664c34323869664132367256"
target_id=$(get_target_id "$filename")

echo "target_id=$target_id"
