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



        # --- FIX CORRUPTED VIDEOS: Fix corrupted videos (by missing I-frames) ---
        # This is a workaround for the issue of some videos that are missing I-frames, which causes that the resulting videos to be corrupted.

        # Brief contextual explanation:
        ## Terms:
        ### GOP (Group of Pictures): is a group of frames in a video, formed by I-frames, P-frames and B-frames.
        ### I-frames (Intra-coded frames): the keyframes in a video, they contain the full image which start every GOP.
        ### P-frames (Predictive frames): they look ONLY BACKWARDS, frames storing only the changes from the previous I or P-frame.
        ### B-frames (Bi-predictive frames): they look BOTH BACKWARDS AND FORWARDS, calculating  the image by comparing the previous and the next I or P-frame

        # [INFO]: the difference between the P-frames and the B-frames, is that the P-frames calculate the image by comparing ONLY the previous I-frame or P-frame, while the B-frames calculate the image by comparing both the previous and the next I-frame or P-frame.
        # [INFO]: The P-frames only calculate with one past point of view by reference, while the B-frames calculate with two points of view, making the B-frames to be more efficient in compression avoiding too many high-risk error frames.

        
        # Start of the fix:

        # Find the timestamp of the first real keyframe in the file.
        # Nvidia Instant Replay files(where this proyect is initially designed and tested) often start mid-GOP, causing the decoder.
        # 1. to produce garbage frames. Starting the video from the first keyframe avoids this.
        
        FIRST_KF=$(ffprobe -select_streams v:0 \
            -show_packets -skip_frame nokey \
            -of csv=print_section=0 \
            -show_entries packet=pts_time \
            -read_intervals "%+#1" \
            "$INPUT" 2>/dev/null | head -1)
        # -select_streams v:0 --> select only the video stream(avoid audio tracks).
        # -show_packets -skip_frame nokey --> scan the compressed packets instead of decoding frames (much faster) and skip any that are not keyframes (I-frames).
        # -of csv=print_section=0 --> format the output.
        # -show_entries packet=pts_time --> extract only the value of the pts_time of the keyframe(I-frames) packets, getting the exact second in the video where the keyframe is located.
        # -read_intervals "%+#1" --> stop reading the file immediately finding exactly 1 result, saving massive amounts of CPU and time.
        # "$INPUT" 2>/dev/null | head -1 --> extract the first pts_time of the first keyframe(I-frame) in the video.

        # 2 Build the optional seek flag (empty string if keyframe is at 0 or not found)
        SEEK_FLAG=""
        if [ -n "$FIRST_KF" ] && [ "$FIRST_KF" != "0.000000" ] && [ "$FIRST_KF" != "0" ]; then # Check variable is not null, and is not 0, because if the first keyframe is at 0 seconds, we don't need to seek.
            echo "[watcher] First clean keyframe at ${FIRST_KF}s, trimming corrupted GOP."
            SEEK_FLAG="-ss $FIRST_KF" # The -ss flag(Seek Start) is for start in ffmpeg the processing from the specified time provided.
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
# -flags +discardcorrupt -> to discard the corrupted frames, this the end user may notice this as a small glitch/skips in the video due to corrupted frames.
# -map 0 # To obtain all the audio tracks.
# -c:v libx264 # Compression engine.
# -crf 23 # (Constant Rate Factor) the value that determines the maintenance of visual quality.
# -preset medium # CPU usage for compression: [ ultrafast | veryfast/faster | medium | slow/slower | veryslow ]
# -c:a aac # The audio format.
# -b:a 192k # The audio bitrate.
# -pix_fmt yuv420p # Most compatible web format.