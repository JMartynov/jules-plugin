#!/bin/bash
OUTPUT="Task created: 123456789012345678"
SESSION_ID=""
if [[ "$OUTPUT" =~ Task\ created:\ ([0-9]{18,20}) ]]; then
    SESSION_ID="${BASH_REMATCH[1]}"
elif [[ "$OUTPUT" =~ Session:\ ([0-9]{18,20}) ]]; then
    SESSION_ID="${BASH_REMATCH[1]}"
elif [[ "$OUTPUT" =~ ([0-9]{18,20}) ]]; then
    SESSION_ID="${BASH_REMATCH[1]}"
fi
echo "SESSION_ID: $SESSION_ID"
