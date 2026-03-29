#!/bin/bash
# ==============================================================================
# RunPod Download Manager (Desktop & Extract Version)
# Usage: ./manager.sh <SSH_HOST> <WIN_USER>
# ==============================================================================

REMOTE_HOST="${1:-$RUNPOD_SSH_HOST}"
USER_WIN="${2:-$WINDOWS_USER}"

if [ -z "$REMOTE_HOST" ] || [ -z "$USER_WIN" ]; then
    echo "Usage: $0 <SSH_HOST> <WIN_USER>"
    echo "Or set RUNPOD_SSH_HOST and WINDOWS_USER environment variables."
    exit 1
fi

TIMESTAMP_LOCAL=$(date +%Y%m%d_%H%M%S)
DEST_BASE="/mnt/c/Users/$USER_WIN/Desktop/runpod_output"
DEST_WIN="$DEST_BASE/$TIMESTAMP_LOCAL"
LOCAL_REMOTE_SCRIPT="$(dirname "$0")/remote_cleanup.sh"
STAGING_DIR="/runpod-volume/transfer_staging"

mkdir -p "$DEST_WIN"

# Upload and execute remote script
echo "Host: $REMOTE_HOST"
echo "Destination: $DEST_WIN"

echo "Uploading remote worker script..."
scp "$LOCAL_REMOTE_SCRIPT" "$REMOTE_HOST:/tmp/remote_cleanup.sh"

echo "Executing remote batch processing..."
ssh "$REMOTE_HOST" "bash /tmp/remote_cleanup.sh && rm /tmp/remote_cleanup.sh"

if [ $? -eq 0 ]; then
    echo "Remote archiving complete. Downloading archives..."
    
    # Check if there are archives before scp
    HAS_ARCHIVES=$(ssh "$REMOTE_HOST" "ls $STAGING_DIR/*.tar.gz >/dev/null 2>&1 && echo 'yes' || echo 'no'")
    if [ "$HAS_ARCHIVES" == "yes" ]; then
        scp "$REMOTE_HOST:$STAGING_DIR/*.tar.gz" "$DEST_WIN/"
        
        if [ $? -eq 0 ]; then
            echo "Download successful. Extracting archives..."
            
            # Extract archives in the destination folder
            # Using -C to ensure relative paths are handled correctly
            find "$DEST_WIN" -maxdepth 1 -name "*.tar.gz" -exec tar -xzf {} -C "$DEST_WIN" \;
            
            echo "Extraction complete. Cleaning up archives (.tar.gz) on local..."
            rm "$DEST_WIN"/*.tar.gz
            
            echo "Cleaning up remote staging archives..."
            ssh "$REMOTE_HOST" "rm -rf $STAGING_DIR"
            
            echo "Done! Files are ready on your Desktop: $DEST_WIN"
        else
            echo "Error: Download failed."
        fi
    else
        echo "No archives found to download."
    fi
else
    echo "Error: Remote processing failed."
fi
