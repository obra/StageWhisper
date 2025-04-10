#!/bin/bash
# Debug run script for StageWhisper with detailed logging

LOG_FILE="/tmp/stagewhisper_log.txt"

# Build the project
echo "Building StageWhisper..."
swift build || exit 1

# Run the app with output redirected to the log file
echo "Running StageWhisper with logging to $LOG_FILE"
echo "Press Ctrl+C to stop the app"
echo "App started at $(date)" > "$LOG_FILE"
./.build/debug/StageWhisper >> "$LOG_FILE" 2>&1