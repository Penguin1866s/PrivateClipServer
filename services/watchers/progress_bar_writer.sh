#!/bin/bash

FILENAME="$1"
PROGRESS_PIPE_FILE="$2" #"/tpm/ffmpep_progress_data.txt"
QUEUE_JSON="${3:-[]}"   # third optional arg: JSON array of pending filenames, default empty
STATUS_FILE="/data/processed/status.json"
QUEUE_DIR="/tmp/pcs_queue" # Directory where pending video files are stored.

# Same pure-bash builder as queue_processor (duplicated to keep scripts independent)
build_queue_json() {
    local json="["
    local sep=""
    local entry name
    while IFS= read -r entry; do
        # The IFS= is for store filenames with the exact content(to preserve spaces and special chars), even with spaces. The read -r is to avoid interpreting backslashes.
        [ -f "$entry" ] || continue
        name=$(cat "$entry" 2>/dev/null)
        [ -z "$name" ] && continue
        name="${name//\\/\\\\}"   # escape backslashes (searching '/' and replace with '\\').
        name="${name//\"/\\\"}"   # escape double-quotes (searching '"' and replace with '\"').
        json="${json}${sep}\"${name}\""
        sep=","
    done < <(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort)
    # The first '<' is for redirecting the output of the command to the while loop
    # and the second '<()' is for process substitution, which allows us to use the output of the command as if it were a file.
    # In tecnical terms, the second '<()' is to create a temporary file descriptor that contains the output of the command, and the first '<' is to read from that file descriptor in the while loop.
    echo "${json}]"
}

# Get total duration (seconds).
DURATION=$(ffprobe -v error \
    -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 \
    "/data/raw/$FILENAME" 2>/dev/null
    # -v error --> shows only the imprtant erros info(to show few info).
    # -show_entries format=duration ---> obtain only the duration field.
    # -of default=noprint_wrappers=1:nokey=1 ---> filter, to obtain only the number value.
)

DURATION=${DURATION%.*} # Remove decimals(its in seconds), remove all comes after the spot.
[ -z "$DURATION" ] && DURATION=0 # if the value of duration is void, asigns 0 value.

echo "[progress_bar_writer] Starting: $FILENAME | Duration: ${DURATION}s"

# ETA --> Estimated Time of Arrival.
printf '{"active":true,"state":"encoding","filename":"%s","percent":0,"elapsed":"00:00:00","eta":"--:--:--","speed":"...","queue":%s}' \
    "$FILENAME" "$QUEUE_JSON" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    # We write to a temporary file to "atomic write".
    # The atomic write is a technique to prevent to crash the widget by an incomplete write of the status file.
    # [INFO]: In the system, when we overwrite a file, the system first set the file content to empty(0 bytes), and then write the new content, but if the widget read the file in the moment that is empty, it will crash by bad json format, for that we write to a temporary file, and then we rename it to the final name, because the rename is atomic, so the widget will never read an incomplete file.

# Poll every 2 seconds until ffmpeg finishes (= PROGRESS_PIPE_FILE contains "progress=end")
while ! grep -q "^progress=end" "$PROGRESS_PIPE_FILE" 2>/dev/null; do

    OUT_TIME_MS=$(grep "^out_time_ms=" "$PROGRESS_PIPE_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
    SPEED=$(grep "^speed=" "$PROGRESS_PIPE_FILE" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d ' ')
    # The cut is to obtain the second value, cut from '=' value.(example: from "out_time_ms=47000000" obtain "47000000")
    # The tr -d, is for remove the spaces(translate command)

    if [ -n "$OUT_TIME_MS" ] && [ "$OUT_TIME_MS" -gt 0 ] 2>/dev/null; then # Check if the variable is not null and if is grater than 0.
        ELAPSED_S=$((OUT_TIME_MS / 1000000)) # convert the microseconds to seconds.
        
        # Format as HH:MM:SS
        ELAPSED=$(printf "%02d:%02d:%02d" \
            $((ELAPSED_S / 3600)) \
            $(( (ELAPSED_S % 3600) / 60 )) \
            $((ELAPSED_S % 60)))
            # hours, minutes, seconds
            # The "%02d", printf format any number to minimun be 2 digits.(example: 2, format into 02).

        if [ "$DURATION" -gt 0 ] 2>/dev/null; then
            PERCENT=$((ELAPSED_S * 100 / DURATION)) # Calculate the percent of video proccessed.
            
            [ "$PERCENT" -gt 100 ] && PERCENT=100 # To fix that sometimes ffmpeg, have a littlebit more than 100%, this it fixed.


            # The next lines are for avoid the need of use the awk, because is to cost to call awk procces every two seconds, because the rest of the code use entirel bash,
            # but awk is a diferent procces. To eliminate the need of run awk, we need to eliminate the need of make operations with decimals(floating points operations), and for
            # and to achive that, we are going to do fixed-point arithmetic.

            #The previos uneficient form to calculate the EAT_S:
            # ETA_S=$(awk -v remaining_time="$((DURATION - ELAPSED_S))" -v speed="$SPEED_NUM" 'BEGIN { if (speed+0>0) printf "%d", remaining_time/speed; else print 0 }')

            #(info): The reason because call awk is to cost, is because, every time, bash need to use awk, this appens:
            #1 Find the executable on the system.
            #2 Create a new process (fork).
            #3 Load awk into memory.
            #4 Execute it
            #5 Destroy the process


            # Delete the x X and spaces charactes.
            SPEED_NUM=$(echo "$SPEED" | tr -d 'xX ')

            #1. Count decimals ONLY if there is a decimal point (this prevents bugs when speed=2x)
            if [[ "$SPEED_NUM" == *.* ]]; then
                # Extract how many decimal places the speed has.
                AFTER_DOT="${SPEED_NUM#*.}"        # example: of "1.80" -> "80"
                DECIMAL_COUNT="${#AFTER_DOT}"      # example: length of "80" -> 2
            else
                DECIMAL_COUNT=0
            fi

            # Remove the decimal point -> whole number.
            SPEED_INT="${SPEED_NUM//./}"       # example: "1.80" -> "180"

            # 2. Force the base to 10 (10#) to avoid octal errors with numbers like “0956”
            SPEED_INT=$((10#${SPEED_INT:-0}))

            # SHIELD: avoid division 0().
            if [ "$SPEED_INT" -gt 0 ] 2>/dev/null; then
                # Scale factor = 10^decimal places -> 100.
                SCALE=$((10 ** DECIMAL_COUNT))

                # ETA without floating-point, without awk, pure bash.
                ETA_S=$(( ((DURATION - ELAPSED_S) * SCALE) / SPEED_INT ))
                ETA=$(printf "%02d:%02d:%02d" \
                    $((ETA_S / 3600)) \
                    $(( (ETA_S % 3600) / 60 )) \
                    $((ETA_S % 60)))

            else
                # if the speed is 0 or N/A(or any non-numeric value), We don't calculate the ETA so that Bash doesn't break.
                ETA="--:--:--"
            fi
        else
            PERCENT=0
            ETA="--:--:--"
        fi

        # Re-read queue (new videos may have arrived during encode)
        CURRENT_QUEUE=$(build_queue_json)

        # The "-..." is to replace with that default value("...") if the variable of SPEED is void.––
        printf '{"active":true,"state":"encoding","filename":"%s","percent":%d,"elapsed":"%s","eta":"%s","speed":"%s","queue":%s}' \
            "$FILENAME" "$PERCENT" "$ELAPSED" "$ETA" "${SPEED:-...}" "$CURRENT_QUEUE" \
            > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
            # We write to a temporary file to "atomic write".
    fi

    sleep 2
done

# ffmpeg finish. Show 100% briefly then clean up temporal files.
printf '{"active":true,"state":"encoding","filename":"%s","percent":100,"elapsed":"","eta":"00:00:00","speed":"done","queue":[]}' \
    "$FILENAME" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
    # We write to a temporary file to "atomic write".
sleep 4

rm -f "$STATUS_FILE"
rm -f "$PROGRESS_PIPE_FILE"
echo "[progress_bar_writer] Done, status cleared."