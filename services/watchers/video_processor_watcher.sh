#!/bin/bash
RAW_DIR="/data/raw"
QUEUE_DIR="/tmp/pcs_queue"
mkdir -p "$QUEUE_DIR"

# Monitor the folder raw in search of closed files (finished copying)
inotifywait -m -e close_write --format '%f' "$RAW_DIR" | while IFS= read -r FILENAME
do
    if [[ "$FILENAME" == *.mp4 || "$FILENAME" == *.mkv || "$FILENAME" == *.mov || "$FILENAME" == *.avi ]]; then
        INPUT="$RAW_DIR/$FILENAME"

        # --- GUARD: skip if file is not yet complete (moov atom missing) ---
        PROBE=$(ffprobe -v error \
            -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 \
            "$INPUT" 2>/dev/null)
        if [ -z "$PROBE" ]; then
            echo "[watcher] '$FILENAME' not ready yet (incomplete upload), skipping."
            continue
        fi
        # --- END GUARD ---

        # Add to queue: use timestamp as prefix to preserve arrival order.
        # The queue entry file contains the filename on its first (and only) line.
        QUEUE_ENTRY="$QUEUE_DIR/$(date +%s%N)_pending"
        echo "$FILENAME" > "$QUEUE_ENTRY"
        echo "[watcher] '$FILENAME' added to queue."
    fi
done