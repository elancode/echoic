#!/bin/bash
# Pre-tool hook: block dangerous commands
# Exit 2 = block the command, Exit 0 = allow

COMMAND="$1"

# Patterns to block
DANGEROUS_PATTERNS=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf \."
    "git push --force"
    "git push -f "
    "git reset --hard"
    "security delete-keychain"
    "security delete-generic-password"
    "defaults delete com.echoic"
    "xcodebuild clean"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qF "$pattern"; then
        echo "BLOCKED: Command contains dangerous pattern: '$pattern'"
        echo "If you really need to run this, do it manually outside Claude."
        exit 2
    fi
done

# Block any rm -rf that isn't targeting build/ or DerivedData/
if echo "$COMMAND" | grep -qE "rm\s+-rf\s+" ; then
    if ! echo "$COMMAND" | grep -qE "rm\s+-rf\s+(build/|DerivedData/|\./build/|\./DerivedData/)" ; then
        echo "BLOCKED: rm -rf only allowed on build/ or DerivedData/ directories."
        echo "Attempted: $COMMAND"
        exit 2
    fi
fi

exit 0
