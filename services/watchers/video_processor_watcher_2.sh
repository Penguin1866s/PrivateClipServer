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



        # --- FIX CORRUPTED VIDEOS: Fix corrupted videos (by missing I-frames, and subsequently by broken NALs) ---
        # This is a workaround for the issue of some videos that are missing I-frames, which causes that the resulting videos to be corrupted.

        # Brief contextual explanation:
        ## Terms:
        ### GOP (Group of Pictures): is a group of frames in a video, formed by I-frames, P-frames and B-frames.
        ### I-frames (Intra-coded frames): the keyframes in a video, they contain the full image which start every GOP.
        ### P-frames (Predictive frames): they look ONLY BACKWARDS, frames storing only the changes from the previous I or P-frame.
        ### B-frames (Bi-predictive frames): they look BOTH BACKWARDS AND FORWARDS, calculating  the image by comparing the previous and the next I or P-frame

        # [INFO]: the difference between the P-frames and the B-frames, is that the P-frames calculate the image by comparing ONLY the previous I-frame or P-frame, while the B-frames calculate the image by comparing both the previous and the next I-frame or P-frame.
        # [INFO]: The P-frames only calculate with one past point of view by reference, while the B-frames calculate with two points of view, making the B-frames to be more efficient in compression avoiding too many high-risk error frames.

        # Hierarchy: GOP -> Frame -> NAL

        # NAL (Network Abstraction Layer): is the basic unit of data, of what is formed the frames, there are two types of NALs, the VCL (Video Coding Layer) NALs, the VCL NAL Units and Non-VCL Units.
        ## VCL NAL Units(Picture/Pixel data): They contain the actual compressed video payload. This is the pure mathematical data (pixels, colors, and motion vectors) that physically make up the I, P, and B-frames.
        ## Non-VCL NAL Units(Assembly instructions): They are NAL units that do not contain pixels, they contain metadata. They contain the rules of how to decode the video, they are essential for the correct decoding.

        # Context: Nvidia Instant Replay (where this project was initially designed and tested) saves clips from a circular buffer.
        # (not just missing I-frame references), causing cabac_init_idc overflows,
        # many errors due to Invalid NAL units, and FMO/data-partitioning errors that ffprobe's
        # packet-level scan cannot detect — it only checks container metadata,
        # not the actual bitstream.
    
        #[INFO]: CABAC(context-adaptive binary arithmetic coding) -> The final compression engine.


        # The strategy solution: scan the video in 1-second steps, probing a small window
        # of frames at each position. The first second that produces zero
        # decode errors is used as the seek point for the real encode.
        # Each probe is cheap: 0.5s of video, at most 4 frames decoded.

        # Start of the fix:

        SEEK_FLAG=""
        FIRST_CLEAN_S=-1

        # I use a while loop instead of a for loop to avoid the use of a break statement, because it's very harmful for the cpu at low level.
        PROBE_T=0
        while [ "$FIRST_CLEAN_S" -eq -1 ] && [ "$PROBE_T" -lt 60 ]; do
            ERRORS=$(ffmpeg \
                -ss "$PROBE_T" \
                -t 0.5 \
                -v error \
                -fflags +discardcorrupt \
                -i "$INPUT" \
                -frames:v 4 \
                -f null /dev/null 2>&1 | \
                grep -cE "overflow|Invalid NAL|no frame!|corrupt decoded|decode_slice_header error")

            if [ "$ERRORS" -eq 0 ]; then
                FIRST_CLEAN_S=$PROBE_T
            fi
            PROBE_T=$((PROBE_T + 1))
        done

        if [ "$FIRST_CLEAN_S" -eq 0 ]; then
            echo "[watcher] No corruption detected in first 60s. Processing from start."
        elif [ "$FIRST_CLEAN_S" -gt 0 ]; then
            echo "[watcher] Bitstream corruption detected. First clean second: ${FIRST_CLEAN_S}s. Trimming."
            SEEK_FLAG="-ss $FIRST_CLEAN_S"
        else
            echo "[watcher] WARNING: Corruption found throughout first 60s. Processing anyway."
        fi
        # --- END FIX CORRUPTED VIDEOS ---



        echo "[watcher] Detecting new file: $FILENAME. Processing..."

        # Kill any leftover progress_bar_writer from a previous failed run
        pkill -f "progress_bar_writer.sh" 2>/dev/null
        sleep 0.2

        # Create the file
        > "$PROGRESS_PIPE_FILE"
        # Execute the script for the progress bar, it runs in the background for the '&' symbol, and it continues with the script without stop that background execution.
        /app/progress_bar_writer.sh "$FILENAME" "$PROGRESS_PIPE_FILE" &

        #With the -y option will automatically overwrite if output already exists
        #ffmpeg -y -i "$RAW_DIR/$FILENAME" -map 0 -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p "$PROCESSED_DIR/${FILENAME%.*}_(processed).mp4"
        #ffmpeg -y -i "$INPUT" -progress "$PROGRESS_PIPE_FILE" -nostats -map 0 -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p "$OUTPUT"(extra we add the -progress and the -nostats for the progress_bar_writer function)
        ffmpeg -y \
            $SEEK_FLAG \
            -fflags +discardcorrupt \
            -i "$INPUT" \
            -progress "$PROGRESS_PIPE_FILE" \
            -nostats \
            -map 0 \
            -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p \
            "$OUTPUT"

        # Optional: Move the original to a folder of trash, or remove it.
        # rm "$RAW_DIR/$FILENAME"
        echo "[watcher] Processing completed."
    fi
done

# ffmpeg -i input.mp4 -map 0 -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -pix_fmt yuv420p output.mp4
# -fflags +discardcorrupt -> to discard the corrupted frames, this the end user may notice this as a small glitch/skips in the video due to corrupted frames.
# -map 0 # To obtain all the audio tracks.
# -c:v libx264 # Compression engine.
# -crf 23 # (Constant Rate Factor) the value that determines the maintenance of visual quality.
# -preset medium # CPU usage for compression: [ ultrafast | veryfast/faster | medium | slow/slower | veryslow ]
# -c:a aac # The audio format.
# -b:a 192k # The audio bitrate.
# -pix_fmt yuv420p # Most compatible web format.