#!/bin/bash

echo "Starting watchers daemons(video_processor_watcher, keys_watcher and queue_processor)..."

# We launch the video processor and keys_watcher in the background (with the & symbol).
/app/video_processor_watcher.sh &
/app/keys_watcher.sh &
/app/queue_processor.sh &

# 'wait' make don't shutdown the container
wait -n