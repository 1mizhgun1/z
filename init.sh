#!/opt/homebrew/Cellar/bash/5.2.37/bin/bash

BASE="/Users/m.ugryumov/study/voenka/pro"

KP_DB_FILE="$BASE/kp/kp.db"
LOG_FILE="$BASE/pro.log"
TARGETS_DIR="$BASE/GenTargets/Targets"
MESSAGES_DIR="$BASE/Messages"

initialize_db() {
    sqlite3 "$DB_FILE" <<EOF
DROP TABLE IF EXISTS targets;
CREATE TABLE IF NOT EXISTS targets (
    id TEXT PRIMARY KEY,
    x INTEGER,
    y INTEGER,
    speed FLOAT,
    target_type TEXT,
    updated_at TEXT
);
EOF
}

prepare_directory() {
    rm "$LOG_FILE"
    rm -rf "$TARGETS_DIR"
    rm -rf "$MESSAGES_DIR"

    touch "$LOG_FILE"
    mkdir "$TARGETS_DIR"
    mkdir "$MESSAGES_DIR"
}

initialize_db
prepare_directory
