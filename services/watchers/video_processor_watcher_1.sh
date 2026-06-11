#!/bin/bash
RAW_DIR="/data/raw"
PROCESSED_DIR="/data/processed"
PROGRESS_PIPE_FILE="/tmp/ffmpeg_progress_data.txt" # The file where ffmpeg write the progress and where progress_bar_writer read.
# An internal channel communication between video_proccesor_watcher and progress_bar_writer.

# Monitor the folder raw in search of closed files (finished copying)
inotifywait -m -e close_write --format '%f' "$RAW_DIR" | while IFS= read -r FILENAME
do
    # Filter only video extensions to avoid processing temp files or not video files(.part, .txt, ...)
    if [[ "$FILENAME" == *.mp4 || "$FILENAME" == *.mkv || "$FILENAME" == *.mov || "$FILENAME" == *.avi ]]; then
        INPUT="$RAW_DIR/$FILENAME"
        OUTPUT="$PROCESSED_DIR/${FILENAME%.*}_(processed).mp4"

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



        # --- FIX CORRUPTED VIDEOS: Fix corrupted videos (by 
        # --- FIX CORRUPTED VIDEOS (BRUTE FORCE) ---
        # Root cause: the avcC atom in the container header contains corrupted SPS/PPS.
        # ffmpeg reads avcC at file-open time, poisoning the decoder before any seek.
        # Solution: remux-trim at each candidate second -> creates a fresh avcC from
        # that position -> test-decode the fresh file (no poisoning possible).
        # Slow (1 remux per second of corruption) but immune to avcC corruption.

        DURATION_S=$(echo "$PROBE" | cut -d. -f1)
        [ -z "$DURATION_S" ] && DURATION_S=120

        ENCODE_INPUT="$INPUT"
        FOUND_CLEAN=0
        # Fixed temp paths: avoid special characters from FILENAME in /tmp
        TEST_FILE="/tmp/pcs_test_probe.mp4"
        TRIMMED_INPUT="/tmp/pcs_trimmed_input.mp4"

        for PROBE_T in $(seq 0 1 "$DURATION_S"); do

            # Step 1: remux from PROBE_T with stream copy.
            # -ss before -i = fast demux seek to nearest keyframe at or after PROBE_T.
            # -c copy = no re-encode, just repackage.
            # Result: a new MP4 whose avcC is built from the stream at PROBE_T,
            # completely independent of the original corrupted avcC.
            ffmpeg -y \
                -ss "$PROBE_T" \
                -i "$INPUT" \
                -c copy \
                -avoid_negative_ts make_zero \
                "$TEST_FILE" 2>/dev/null

            if [ ! -f "$TEST_FILE" ] || [ ! -s "$TEST_FILE" ]; then
                echo "[watcher] Position ${PROBE_T}s: remux produced empty file, skipping."
                continue
            fi

            # Step 2: test-decode the fresh remux.
            # Count ALL stderr lines — any output means errors are present.
            # -t 2.0 and -frames:v 60 limit the test to 2 seconds max.
            ERROR_LINES=$(ffmpeg \
                -v error \
                -t 2.0 \
                -i "$TEST_FILE" \
                -frames:v 60 \
                -f null /dev/null 2>&1 | wc -l)

            if [ "$ERROR_LINES" -eq 0 ]; then
                FOUND_CLEAN=1

                if [ "$PROBE_T" -eq 0 ]; then
                    echo "[watcher] No corruption detected. Processing from start."
                    ENCODE_INPUT="$INPUT"
                else
                    echo "[watcher] First clean position: ${PROBE_T}s. Using remuxed file as encode input."
                    # Reuse the already-created TEST_FILE as the encode input
                    cp "$TEST_FILE" "$TRIMMED_INPUT"
                    ENCODE_INPUT="$TRIMMED_INPUT"
                fi
                break
            else
                echo "[watcher] Position ${PROBE_T}s corrupt (${ERROR_LINES} error lines), trying next..."
            fi

        done

        rm -f "$TEST_FILE"

        if [ "$FOUND_CLEAN" -eq 0 ]; then
            echo "[watcher] WARNING: No clean position found. Encoding from original anyway."
            ENCODE_INPUT="$INPUT"
        fi
        # --- END FIX CORRUPTED VIDEOS ---
        # --- END FIX CORRUPTED VIDEOS ---


        echo "[watcher] Detecting new file: $FILENAME. Processing..."

        pkill -f "progress_bar_writer.sh" 2>/dev/null
        sleep 0.2

        > "$PROGRESS_PIPE_FILE"
        /app/progress_bar_writer.sh "$FILENAME" "$PROGRESS_PIPE_FILE" &

        ffmpeg -y \
            -fflags +discardcorrupt \
            -i "$ENCODE_INPUT" \
            -progress "$PROGRESS_PIPE_FILE" \
            -nostats \
            -map 0 \
            -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p \
            "$OUTPUT"

        echo "[watcher] Processing completed."
        # Cleanup the temporary trimmed file if it was created
        [ -f "$TRIMMED_INPUT" ] && rm -f "$TRIMMED_INPUT"

        echo "[watcher] Processing completed."
    fi
done

# Cleanup trimmed temp file if it was used
[ -f "$TRIMMED_INPUT" ] && rm -f "$TRIMMED_INPUT"