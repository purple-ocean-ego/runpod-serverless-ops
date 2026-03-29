#!/bin/bash
OUTPUT_DIR="/runpod-volume/output"
STAGING_DIR="/runpod-volume/transfer_staging"
mkdir -p "$STAGING_DIR"

# Count files
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -type f | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
    echo "No files found in $OUTPUT_DIR"
    exit 0
fi

echo "Found $FILE_COUNT files. Processing in batches of 100..."

while true; do
    FILES=$(find "$OUTPUT_DIR" -maxdepth 1 -type f | head -n 100)
    if [ -z "$FILES" ]; then
        break
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_PATH="$STAGING_DIR/archive_$TIMESTAMP.tar.gz"

    echo "Archiving batch to $ARCHIVE_PATH..."
    
    # Use -T to read list from stdin to handle spaces safely
    echo "$FILES" | tar -czf "$ARCHIVE_PATH" -T -

    if [ $? -eq 0 ]; then
        echo "Archive created successfully. Deleting originals..."
        echo "$FILES" | xargs -d '\n' rm
    else
        echo "Error: Archiving failed. Batch aborted."
        exit 1
    fi
done

echo "Batch processing complete."
