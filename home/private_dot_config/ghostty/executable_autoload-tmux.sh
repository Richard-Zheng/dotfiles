#!/bin/bash
SESSION_NAME="term"

# Check if the session already exists
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? -eq 0 ]; then
  # Reattach if it exists
  tmux attach-session -t $SESSION_NAME
else
  # Create and attach if it doesn't
  tmux new-session -s $SESSION_NAME -d
  tmux attach-session -t $SESSION_NAME
fi
