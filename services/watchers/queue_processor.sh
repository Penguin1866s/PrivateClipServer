#!/bin/bash
RAW_DIR="/data/raw"
PROCESSED_DIR="/data/processed"
PROGRESS_PIPE_FILE="/tmp/ffmpeg_progress_data.txt"
QUEUE_DIR="/tmp/pcs_queue"
TEST_FILE="/tmp/pcs_test_probe.mp4"
TRIMMED_INPUT="/tmp/pcs_trimmed_input.mp4"
STATUS_FILE="/data/processed/status.json"

mkdir -p "$QUEUE_DIR"

# Pure-bash JSON array builder.
# Reads all *_pending files in QUEUE_DIR sorted by name (= arrival order)
# and builds: ["file1.mp4","file2.mp4"]
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

# --- VIDEO ENCODER SELECTION (auto / vaapi / cpu) ---
# Context: libx264 is the "brute force" software encoder (runs on the CPU cores).
# h264_vaapi uses the dedicated encode silicon of the Intel iGPU (the Quick Sync hardware)
# through VAAPI (Video Acceleration API), the standard Linux interface for GPU video work.
# Same visual result, but the encode runs in the iGPU -> much faster and a fraction of the power.

# The encoder is selected with the VIDEO_ENCODER environment variable (see docker-compose.yml):
#   auto  -> test the iGPU with a real 1-frame encode, use vaapi if it works, fallback to cpu. (default)
#   vaapi -> force the Intel iGPU hardware encoder.
#   cpu   -> force libx264 (brute force).
VIDEO_ENCODER="${VIDEO_ENCODER:-auto}" # If the env var is not set, use 'auto' as default value.
RENDER_DEVICE="/dev/dri/renderD128"    # The render node of the Intel iGPU (mapped in docker-compose.yml with 'devices:').

if [ "$VIDEO_ENCODER" = "auto" ]; then
    # Real probe: encode a tiny generated black clip with the iGPU.
    # If this exits 0, the whole chain (device + driver + ffmpeg encoder) really works.
    # We don't trust only the existence of $RENDER_DEVICE because it can exist without a working encode driver (example: WSL2).
    if ffmpeg -v error -vaapi_device "$RENDER_DEVICE" \
        -f lavfi -i color=black:s=64x64:d=0.1 \
        -vf format=nv12,hwupload -c:v h264_vaapi \
        -f null /dev/null 2>/dev/null; then
        VIDEO_ENCODER="vaapi"
    else
        VIDEO_ENCODER="cpu"
    fi
fi

if [ "$VIDEO_ENCODER" = "vaapi" ]; then
    HW_INIT_ARGS="-vaapi_device $RENDER_DEVICE"       # Open the iGPU device (must go BEFORE the -i input).
    VIDEO_CHAIN="format=nv12,hwupload"                # Convert the frames to nv12 (the pixel format the iGPU expects) and upload them to GPU memory.
    VIDEO_ENCODE_ARGS="-c:v h264_vaapi -qp 24 -g 60"  # -qp 24 -> the hardware quality knob (equivalent role to '-crf 23' in libx264).
else
    HW_INIT_ARGS=""                                   # Nothing to init for the CPU path.
    VIDEO_CHAIN="format=yuv420p"                      # Same effect as the old '-pix_fmt yuv420p' (most compatible web format), expressed as a filter.
    VIDEO_ENCODE_ARGS="-c:v libx264 -crf 23 -preset medium -g 60"
fi
echo "[queue_processor] Video encoder selected: $VIDEO_ENCODER"

echo "[queue_processor] Started."

# Main loop: continuously check the queue for new entries and process them.
while true; do
    NEXT_ENTRY=$(ls "$QUEUE_DIR"/*_pending 2>/dev/null | sort | head -1)

    if [ -z "$NEXT_ENTRY" ]; then
        sleep 1
        continue
    fi

    # We stop the `progress_bar_writer.sh` from the previous video, if it exists, to prevent it from waking up from its “sleep 4” and removing the `status.json` file for the new video, which causes the widget to disappear for a moment before reappearing with the new video info.
    pkill -f "progress_bar_writer.sh" 2>/dev/null

    FILENAME=$(cat "$NEXT_ENTRY")
    INPUT="$RAW_DIR/$FILENAME"
    OUTPUT="$PROCESSED_DIR/${FILENAME%.*}_(processed).mp4"

    rm -f "$NEXT_ENTRY"

    PROBE=$(ffprobe -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$INPUT" 2>/dev/null)

    if [ -z "$PROBE" ]; then
        echo "[queue_processor] '$FILENAME' unreadable, skipping."
        continue
    fi

    # --- FIX CORRUPTED VIDEOS (BRUTE FORCE) ---
    # Root cause: the avcC atom in the container header contains corrupted SPS/PPS.
    # ffmpeg reads avcC at file-open time, poisoning the decoder before any seek.
    # Solution: remux-trim at each candidate second -> creates a fresh avcC from
    # that position -> test-decode the fresh file (no poisoning possible).
    # Slow (1 remux per second of corruption) but immune to avcC corruption.

    # --- FIX CORRUPTED VIDEOS: Fix corrupted videos (by missing I-frames, broken NALs, and poisoned avcC headers) ---
    # This is a workaround for the issue of some videos that are missing I-frames or have corrupted headers, which causes that the resulting videos to be corrupted.

    # Brief contextual explanation:
    ## Terms:
    ### GOP (Group of Pictures): is a group of frames in a video, formed by I-frames, P-frames and B-frames.
    ### I-frames (Intra-coded frames): the keyframes in a video, they contain the full image which start every GOP.
    ### P-frames (Predictive frames)(image data): they look ONLY BACKWARDS, frames storing only the changes from the previous I or P-frame.
    ### B-frames (Bi-predictive frames)(image data): they look BOTH BACKWARDS AND FORWARDS, calculating  the image by comparing the previous and the next I or P-frame

    ### avcC (AVC Configuration Box): The master header atom in an MP4 container for H.264 video. It stores the global decoding parameters needed to initialize the decoder BEFORE reading any frames.
    ### SPS (Sequence Parameter Set)(metadata): A Non-VCL NAL unit inside the avcC. Contains global video info (resolution, profile, frame rate).
    ### PPS (Picture Parameter Set)(metadata): A Non-VCL NAL unit inside the avcC. Contains rules for decoding specific pictures (entropy coding mode, slice groups).

    # [INFO]: the difference between the P-frames and the B-frames, is that the P-frames calculate the image by comparing ONLY the previous I-frame or P-frame, while the B-frames calculate the image by comparing both the previous and the next I-frame or P-frame.
    # [INFO]: The P-frames only calculate with one past point of view by reference, while the B-frames calculate with two points of view, making the B-frames to be more efficient in compression avoiding too many high-risk error frames.

    # Hierarchy: Container (MP4) -> avcC -> GOP -> Frame -> NAL

    # NAL (Network Abstraction Layer): is the basic unit of data, of what is formed the frames, there are two types of NALs, the VCL (Video Coding Layer) NALs, the VCL NAL Units and Non-VCL Units.
    ## VCL NAL Units(Picture/Pixel data): They contain the actual compressed video payload. This is the pure mathematical data (pixels, colors, and motion vectors) that physically make up the I, P, and B-frames.
    ## Non-VCL NAL Units(Assembly instructions): They are NAL units that do not contain pixels, they contain metadata. They contain the rules of how to decode the video, they are essential for the correct decoding.

    # Context: Nvidia Instant Replay (where this project was initially designed and tested) saves clips from a circular buffer.
    # When it cuts the video abruptly mid-GOP, it not only misses I-frame references, but it also writes a corrupted 'avcC' header containing broken SPS/PPS data.
    # This causes cabac_init_idc overflows, Invalid NAL units, and FMO/data-partitioning errors.
    # Because ffmpeg reads the 'avcC' header at file-open time, the decoder gets "poisoned" immediately, making simple seeking (-ss) fail.


    #[INFO]: CABAC(context-adaptive binary arithmetic coding) -> The final compression engine.


    # The strategy solution:
    # 1. scan the video in 1-second steps.
    # 2. At each second, perform a stream copy (remux) of a tiny chunk into a temporary file.
    #    -> WHY? Because remuxing forces ffmpeg to generate a BRAND NEW, clean 'avcC' header based ONLY on the frames from that specific second forward, ignoring the original poisoned header.
    # 3. Test-decode this fresh temporary file.
    # 4. The first second that produces zero decode errors is our first clean GOP. We use this clean remuxed file as the starting point for the final encode.


    DURATION_S=$(echo "$PROBE" | cut -d. -f1)
    [ -z "$DURATION_S" ] && DURATION_S=120
    # The cut command is used to extract the integer part of the duration in seconds(example: "123.45" becomes "123").
    # The -d.(delimiter-> '.') and -f1 selects the first field (the part before the dot).

    ENCODE_INPUT="$INPUT"
    FOUND_CLEAN=0
    CORRUPTION_FOUND=0

    # ── Scan loop ────────────────────────────────────────────────────────
    for PROBE_T in $(seq 0 1 "$DURATION_S"); do
        QUEUE_JSON=$(build_queue_json)

        # Write scanning state to status.json so the widget shows it
        printf '{"active":true,"state":"scanning","filename":"%s","scan_pos":%d,"queue":%s}' \
            "$FILENAME" "$PROBE_T" "$QUEUE_JSON" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
            # We write to a temporary file to "atomic write".

        # Step 1: remux from PROBE_T with stream copy.
        # -ss before -i = fast demux seek to nearest keyframe at or after PROBE_T.
        # -c copy = no re-encode, just repackage.
        # Result: a new MP4 whose avcC is built from the stream at PROBE_T,
        # completely independent of the original corrupted avcC.
        ffmpeg -y \
            -ss "$PROBE_T" \
            -i "$INPUT" \
            -map 0 \
            -c copy \
            -avoid_negative_ts make_zero \
            "$TEST_FILE" 2>/dev/null

        if [ ! -f "$TEST_FILE" ] || [ ! -s "$TEST_FILE" ]; then
            echo "[queue_processor] Position ${PROBE_T}s: remux empty, skipping."
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
        # The '2>&1' -> redirects the standard error (stderr) to standard output (stdout), to count all error lines.
        # The 'wc -l' -> word count lines.

        if [ "$ERROR_LINES" -eq 0 ]; then
            FOUND_CLEAN=1
            if [ "$PROBE_T" -eq 0 ]; then
                echo "[queue_processor] No corruption. Processing from start."
                ENCODE_INPUT="$INPUT"
            else
                CORRUPTION_FOUND=1
                echo "[queue_processor] First clean position: ${PROBE_T}s. Trimming."

                # Write correcting state so the widget shows it
                QUEUE_JSON=$(build_queue_json)
                printf '{"active":true,"state":"correcting","filename":"%s","corrupt_at":%d,"queue":%s}' \
                    "$FILENAME" "$PROBE_T" "$QUEUE_JSON" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
                    # We write to a temporary file to "atomic write".

                # Reuse the already-created TEST_FILE as the encode input.
                cp "$TEST_FILE" "$TRIMMED_INPUT"
                ENCODE_INPUT="$TRIMMED_INPUT"
            fi
            break
        else
            echo "[queue_processor] Position ${PROBE_T}s corrupt (${ERROR_LINES} error lines), trying next..."
        fi
    done

    rm -f "$TEST_FILE"

    if [ "$FOUND_CLEAN" -eq 0 ]; then
        echo "[queue_processor] WARNING: No clean position found. Encoding anyway."
        ENCODE_INPUT="$INPUT"
    fi
    # ── End scan ─────────────────────────────────────────────────────────
    # --- END FIX CORRUPTED VIDEOS ---

    echo "[queue_processor] Encoding: $FILENAME"

    pkill -f "progress_bar_writer.sh" 2>/dev/null
    sleep 0.2

    QUEUE_JSON=$(build_queue_json)
    > "$PROGRESS_PIPE_FILE"
    /app/progress_bar_writer.sh "$FILENAME" "$PROGRESS_PIPE_FILE" "$QUEUE_JSON" &

    # --- MIXED AUDIO TRACK (web playback fix) ---
    # Context: browsers (the FileBrowser HTML5 player) only play ONE audio track (the one marked as 'default'),
    # so with separated system+mic tracks you only hear one of them in the web UI.
    # VLC can play all tracks at once, but that is a VLC-only feature, not a browser feature.

    # The strategy solution:
    # 1. If the video has exactly 2 audio tracks (system + mic), generate a 3rd track mixing both.
    # 2. Place the mix FIRST (a:0) and mark it as 'default' -> browsers and normal players reproduce ONLY the mix (no echo).
    # 3. Keep the 2 original tracks untouched behind it (a:1, a:2) -> for editing, just mute/remove the first track (A1) in the editor.

    # Count how many audio tracks the input has.
    AUDIO_TRACKS=$(ffprobe -v error \
        -select_streams a \
        -show_entries stream=index \
        -of csv=p=0 \
        "$ENCODE_INPUT" 2>/dev/null | wc -l)
        # -select_streams a ---> inspect only the audio streams.
        # -show_entries stream=index ---> obtain only the index field of each stream (one line per track).
        # -of csv=p=0 ---> filter, plain output without headers.
        # wc -l ---> word count lines = number of audio tracks.

    if [ "$AUDIO_TRACKS" -eq 2 ]; then
        echo "[queue_processor] 2 audio tracks detected. Encoding with mixed default track."
        ffmpeg -y \
            -fflags +discardcorrupt \
            $HW_INIT_ARGS \
            -i "$ENCODE_INPUT" \
            -progress "$PROGRESS_PIPE_FILE" \
            -nostats \
            -filter_complex "[0:v]${VIDEO_CHAIN}[vout];[0:a:0][0:a:1]amix=inputs=2:duration=longest:normalize=0[mix]" \
            -map "[vout]" \
            -map "[mix]" \
            -map 0:a \
            $VIDEO_ENCODE_ARGS -c:a aac -b:a 192k \
            -disposition:a:0 default \
            -disposition:a:1 0 \
            -disposition:a:2 0 \
            -metadata:s:a:0 title="Mix (System+Mic)" \
            -metadata:s:a:1 title="System" \
            -metadata:s:a:2 title="Mic" \
            "$OUTPUT"

            # $HW_INIT_ARGS and $VIDEO_ENCODE_ARGS are expanded WITHOUT quotes on purpose -> bash splits them into separated arguments.
            # The video now travels through the filter_complex too ([0:v] -> VIDEO_CHAIN -> [vout]) so the SAME command works for cpu and vaapi.

            # -filter_complex "[0:a:0][0:a:1]amix=inputs=2:duration=longest:normalize=0[mix]" # Mix the 2 audio tracks into a new one labeled [mix]. normalize=0 keeps original volumes (default halves them).
            # -map 0:v / -map "[mix]" / -map 0:a # Track order in the output: video, mix (a:0), originals (a:1, a:2). The order of the -map defines the track order.
            # -disposition:a:0 default # Mark the mix as the 'default' track (the one browsers/players choose).
            # -metadata:s:a:N title="..." # Visible name of each track in editors/players.
    else
        # 0, 1 or 3+ audio tracks: keep the original behaviour (no mix).
        ffmpeg -y \
            -fflags +discardcorrupt \
            $HW_INIT_ARGS \
            -i "$ENCODE_INPUT" \
            -progress "$PROGRESS_PIPE_FILE" \
            -nostats \
            -map 0 \
            -vf "$VIDEO_CHAIN" \
            $VIDEO_ENCODE_ARGS -c:a aac -b:a 192k \
            "$OUTPUT"
            # -vf "$VIDEO_CHAIN" -> applies the video chain of the selected encoder (yuv420p for cpu / nv12+hwupload for vaapi).
    fi

    # Cleanup the temporary trimmed file if it was created
    [ -f "$TRIMMED_INPUT" ] && rm -f "$TRIMMED_INPUT"
    echo "[queue_processor] Done: $FILENAME"

done


# ffmpeg -i input.mp4 -map 0 -c:v libx264 -crf 23 -preset medium -g 60 -c:a aac -b:a 192k -pix_fmt yuv420p output.mp4
# -fflags +discardcorrupt -> to discard the corrupted frames, this the end user may notice this as a small glitch/skips in the video due to corrupted frames.
# -map 0 # To obtain all the audio tracks.
# -c:v libx264 # Compression engine.
# -crf 23 # (Constant Rate Factor) the value that determines the maintenance of visual quality.
# -preset medium # CPU usage for compression: [ ultrafast | veryfast/faster | medium | slow/slower | veryslow ]
# -g 60 # (GOP size) Keyframe interval in frames. At 60fps = 1 keyframe/s. Lower = smoother seek, slightly larger file. (default: 250)
# -c:a aac # The audio format.
# -b:a 192k # The audio bitrate.
# -pix_fmt yuv420p # Most compatible web format.