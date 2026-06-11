#!/bin/bash
INBOX_DIR="/data/keys_inbox"

echo "Keys watcher started in $INBOX_DIR..."

inotifywait -m -e close_write,moved_to,create --format '%f' "$INBOX_DIR" | while IFS= read -r FILENAME
do
    FILE_PATH="$INBOX_DIR/$FILENAME"
    
    # Read the key and remove the spacces and line breaks.
    # The "tr -d ' \n\r'" command delete (for the -d option)the next characters(in this case, spaces, newlines and carriage return)
    NEW_KEY=$(cat "$FILE_PATH" | tr -d ' \n\r')
    
    if [ -n "$NEW_KEY" ]; then
        echo "New key detected in $FILENAME. Processing..."
        /app/add_peer.sh "$NEW_KEY"
        
        # Remove the .txt of the mailbox of FileBrowser for leaves him clean.
        rm "$FILE_PATH"
    fi
done