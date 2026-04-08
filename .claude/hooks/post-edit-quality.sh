#!/bin/bash
# Post-tool hook: run lint/typecheck on edited Swift files
# Advisory only — exits 0 regardless (non-blocking)

FILE="$1"

# Only process Swift files
if [[ "$FILE" != *.swift ]]; then
    exit 0
fi

# Skip if file doesn't exist
if [[ ! -f "$FILE" ]]; then
    exit 0
fi

# Run swiftlint if available
if command -v swiftlint &>/dev/null; then
    OUTPUT=$(swiftlint lint --path "$FILE" --quiet 2>/dev/null)
    if [[ -n "$OUTPUT" ]]; then
        echo "--- swiftlint issues in $(basename "$FILE") ---"
        echo "$OUTPUT"
        echo "---"
    fi
fi

# Run swift-format lint if available (and swiftlint wasn't)
if ! command -v swiftlint &>/dev/null && command -v swift-format &>/dev/null; then
    OUTPUT=$(swift-format lint "$FILE" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "--- swift-format issues in $(basename "$FILE") ---"
        echo "$OUTPUT"
        echo "---"
    fi
fi

# Always exit 0 — this is advisory, not blocking
exit 0
