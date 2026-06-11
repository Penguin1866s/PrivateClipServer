#!/bin/bash
RAW_DIR="/data/raw"
PROCESSED_DIR="/data/processed"
PROGRESS_PIPE_FILE="/tmp/ffmpeg_progress_data.txt"
QUEUE_DIR="/tmp/pcs_queue"
TEST_FILE="/tmp/pcs_test_probe.mp4"
TRIMMED_INPUT="/tmp/pcs_trimmed_input.mp4"

mkdir -p "$QUEUE_DIR"

echo "[queue_processor] Started. Watching queue at $QUEUE_DIR ..."

while true; do

    # Find the oldest pending entry (sort by filename = sort by timestamp prefix)
    NEXT_ENTRY=$(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort | head -1)

    if [ -z "$NEXT_ENTRY" ]; then
        sleep 1
        continue
    fi

    FILENAME=$(cat "$NEXT_ENTRY")
    INPUT="$RAW_DIR/$FILENAME"
    OUTPUT="$PROCESSED_DIR/${FILENAME%.*}_(processed).mp4"

    # Remove entry from queue now (we own it)
    rm -f "$NEXT_ENTRY"

    # Build the current queue list for the status widget (what comes after this one)
    QUEUE_LIST=$(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort | while read -r e; do cat "$e"; done | \
        python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null)
    [ -z "$QUEUE_LIST" ] && QUEUE_LIST="[]"

    echo "[queue_processor] Processing: $FILENAME | Queue: $QUEUE_LIST"

    # -----------------------------------------------------------------------
    # PROBE duration (reused below)
    PROBE=$(ffprobe -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$INPUT" 2>/dev/null)

    if [ -z "$PROBE" ]; then
        echo "[queue_processor] '$FILENAME' disappeared or unreadable, skipping."
        continue
    fi

    # -----------------------------------------------------------------------
    # FIX CORRUPTED VIDEOS (BRUTE FORCE)
    # remux-trim at each second -> fresh avcC -> test-decode the fresh file.
    DURATION_S=$(echo "$PROBE" | cut -d. -f1)
    [ -z "$DURATION_S" ] && DURATION_S=120

    ENCODE_INPUT="$INPUT"
    FOUND_CLEAN=0

    for PROBE_T in $(seq 0 1 "$DURATION_S"); do
        ffmpeg -y \
            -ss "$PROBE_T" \
            -i "$INPUT" \
            -c copy \
            -avoid_negative_ts make_zero \
            "$TEST_FILE" 2>/dev/null

        if [ ! -f "$TEST_FILE" ] || [ ! -s "$TEST_FILE" ]; then
            echo "[queue_processor] Position ${PROBE_T}s: remux empty, skipping."
            continue
        fi

        ERROR_LINES=$(ffmpeg \
            -v error \
            -t 2.0 \
            -i "$TEST_FILE" \
            -frames:v 60 \
            -f null /dev/null 2>&1 | wc -l)

        if [ "$ERROR_LINES" -eq 0 ]; then
            FOUND_CLEAN=1
            if [ "$PROBE_T" -eq 0 ]; then
                echo "[queue_processor] No corruption detected. Processing from start."
                ENCODE_INPUT="$INPUT"
            else
                echo "[queue_processor] First clean position: ${PROBE_T}s. Trimming."
                cp "$TEST_FILE" "$TRIMMED_INPUT"
                ENCODE_INPUT="$TRIMMED_INPUT"
            fi
            break
        else
            echo "[queue_processor] Position ${PROBE_T}s corrupt (${ERROR_LINES} lines), trying next..."
        fi
    done

    rm -f "$TEST_FILE"

    if [ "$FOUND_CLEAN" -eq 0 ]; then
        echo "[queue_processor] WARNING: No clean position found. Encoding anyway."
        ENCODE_INPUT="$INPUT"
    fi
    # END FIX CORRUPTED VIDEOS

    # -----------------------------------------------------------------------
    # Rebuild queue list just before encoding (may have changed during scan)
    QUEUE_LIST=$(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort | while read -r e; do cat "$e"; done | \
        python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null)
    [ -z "$QUEUE_LIST" ] && QUEUE_LIST="[]"

    # -----------------------------------------------------------------------
    # Launch progress bar writer, passing the queue list so it writes it to status.json
    pkill -f "progress_bar_writer.sh" 2>/dev/null
    sleep 0.2

    > "$PROGRESS_PIPE_FILE"
    /app/progress_bar_writer.sh "$FILENAME" "$PROGRESS_PIPE_FILE" "$QUEUE_LIST" &

    # -----------------------------------------------------------------------
    # Encode
    echo "[queue_processor] Encoding: $FILENAME"
    ffmpeg -y \
        -fflags +discardcorrupt \
        -i "$ENCODE_INPUT" \
        -progress "$PROGRESS_PIPE_FILE" \
        -nostats \
        -map 0 \
        -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p \
        "$OUTPUT"

    [ -f "$TRIMMED_INPUT" ] && rm -f "$TRIMMED_INPUT"
    echo "[queue_processor] Done: $FILENAME"

done