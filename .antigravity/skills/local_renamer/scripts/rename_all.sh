#!/bin/bash
# ==============================================================================
# Local Image Renamer (4-Digit Sequential)
# Usage: ./rename_all.sh <FOLDER_PATH>
# ==============================================================================

FOLDER_PATH="$1"

if [ -z "$FOLDER_PATH" ] || [ ! -d "$FOLDER_PATH" ]; then
    echo "Usage: $0 <FOLDER_PATH>"
    exit 1
fi

cd "$FOLDER_PATH" || exit 1

# Supported extensions (case-insensitive)
shopt -s nocaseglob

# 1. Get image files to rename, naturally sorted
# Using ls -v for natural sort (1, 2, 11 etc)
FILES=$(ls -v *.{png,jpg,jpeg,webp} 2>/dev/null)

if [ -z "$FILES" ]; then
    echo "No image files found in $FOLDER_PATH"
    exit 0
fi

echo "Renaming files in $FOLDER_PATH to sequential format..."

# 1st PASS: Rename to temporary names to avoid collisions
# For example: file1.png -> temp_0001.png
i=1
echo "$FILES" | while read -r f; do
    ext="${f##*.}"
    printf -v new "temp_%04d.%s" $i "$ext"
    if [ "$f" != "$new" ]; then
        mv "$f" "$new"
    fi
    ((i++))
done

# 2nd PASS: Final names
# temp_0001.png -> 0001.png
for f in temp_*{png,jpg,jpeg,webp}; do
    [ -f "$f" ] || continue
    new=$(echo "$f" | sed 's/^temp_//')
    mv "$f" "$new"
done

shopt -u nocaseglob
echo "Done! Final files renamed to 0001 format."
