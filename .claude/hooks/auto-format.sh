#!/bin/bash
# Post-tool hook: auto-format Swift files after edit/write
# Receives the file path as argument

FILE="$1"

# Only process Swift files
if [[ "$FILE" != *.swift ]]; then
    exit 0
fi

# Skip if file doesn't exist (was deleted)
if [[ ! -f "$FILE" ]]; then
    exit 0
fi

# Try swiftlint --fix first (most common in Swift projects)
if command -v swiftlint &>/dev/null; then
    swiftlint --fix --path "$FILE" --quiet 2>/dev/null
    exit 0
fi

# Fall back to swift-format
if command -v swift-format &>/dev/null; then
    swift-format format -i "$FILE" 2>/dev/null
    exit 0
fi

# No formatter available — that's okay, skip silently
exit 0
