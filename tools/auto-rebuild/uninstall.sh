#!/bin/bash
#
# Removes the LaunchAgent. Leaves the config and the log alone — they are
# yours, and reinstalling should not make you set the topic up again.

set -uo pipefail

for LABEL in com.tally.rebuild com.tally.rebuild.retry; do
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

    launchctl bootout "gui/$UID/$LABEL" 2>/dev/null && echo "stopped $LABEL" \
        || echo "$LABEL was not running"

    if [ -f "$PLIST" ]; then
        rm -f "$PLIST"
        echo "removed $PLIST"
    fi
done

echo
echo "left in place:"
echo "  ~/.config/tally-rebuild/config"
echo "  ~/Library/Logs/tally-rebuild.log"
echo "  ~/.local/state/tally-rebuild/   (build cache, safe to delete)"
