#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

DB_FILE="targets.db"
LOG_FILE="rls.log"
OFFSET_FILE="offset.dat"
TARGETS_DIR="/Users/m.ugryumov/study/voenka/rls/GenTargets/Targets"

# Инициализация базы данных SQLite
initialize_db() {
    sqlite3 "$DB_FILE" <<EOF
DROP TABLE IF EXISTS targets;
DROP TABLE IF EXISTS processed_files;
CREATE TABLE IF NOT EXISTS targets (
    id TEXT PRIMARY KEY,
    x INTEGER,
    y INTEGER,
    speed FLOAT,
    target_type TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS processed_files (
    filename TEXT PRIMARY KEY
);
EOF
}

prepare_directory() {
    rm "$LOG_FILE"
    rm "$OFFSET_FILE"
    rm -rf "$TARGETS_DIR"

    touch "$LOG_FILE"
    touch "$OFFSET_FILE"
    mkdir "$TARGETS_DIR"
}

initialize_db
prepare_directory
