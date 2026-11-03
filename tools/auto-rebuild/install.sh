#!/bin/bash
#
# Installs the LaunchAgent, and creates the config file if it is missing.
# Run it again any time to pick up changes to the plist template.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LABEL="com.tally.rebuild"
RETRY_LABEL="com.tally.rebuild.retry"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
RETRY_PLIST="$HOME/Library/LaunchAgents/$RETRY_LABEL.plist"
CONFIG_DIR="$HOME/.config/tally-rebuild"
CONFIG="$CONFIG_DIR/config"

mkdir -p "$HOME/Library/LaunchAgents" "$CONFIG_DIR"

# -- config, which stays out of the repo because the repo is public --------

if [ ! -f "$CONFIG" ]; then
    udid=$(xcrun xctrace list devices 2>/dev/null \
           | grep -v Simulator \
           | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1 || true)

    topic="tally-$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-' | cut -c1-16)"

    cat > "$CONFIG" <<CONF
# Read by rebuild.sh. Not in the repo: the repo is public, and an ntfy topic
# is effectively a password — anyone who knows it can read your pushes.

# The phone's hardware UDID, as Xcode shows it under Devices and Simulators.
DEVICE_UDID="$udid"

# Subscribe to this topic in the ntfy app to get the pushes.
NTFY_TOPIC="$topic"
NTFY_SERVER="https://ntfy.sh"
CONF
    chmod 600 "$CONFIG"
    echo "wrote $CONFIG"
    [ -n "$udid" ] && echo "  device:  $udid" || echo "  device:  NOT FOUND — fill in DEVICE_UDID by hand"
    echo "  ntfy:    $topic   <- subscribe to this"
else
    echo "config already at $CONFIG, left alone"
fi

# -- the agent ------------------------------------------------------------

sed -e "s|__SCRIPT__|$SCRIPT_DIR/rebuild.sh|g" \
    -e "s|__HOME__|$HOME|g" \
    "$SCRIPT_DIR/com.tally.rebuild.plist.template" > "$PLIST"

sed -e "s|__SCRIPT__|$SCRIPT_DIR/rebuild.sh|g" \
    -e "s|__HOME__|$HOME|g" \
    "$SCRIPT_DIR/com.tally.rebuild.retry.plist.template" > "$RETRY_PLIST"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL"

launchctl bootout "gui/$UID/$RETRY_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$RETRY_PLIST"
launchctl enable "gui/$UID/$RETRY_LABEL"

echo "installed $PLIST"
echo "installed $RETRY_PLIST"
echo "runs at 03:00, 20:00 and at login; retries every 30 min while armed"
echo
# Does launchd actually have the access it needs? A repo under Desktop,
# Documents or Downloads is walled off from background jobs, and the only
# symptom is "Operation not permitted" in the error log. Easier to find out
# here than to wonder in a week why nothing has run.
ERR="$HOME/Library/Logs/tally-rebuild.err.log"
: > "$ERR"
sleep 3

if grep -q "Operation not permitted" "$ERR" 2>/dev/null; then
    echo
    echo "!! launchd cannot reach this script: it is in a folder macOS"
    echo "   protects, so the scheduled runs will not happen."
    echo
    echo "   System Settings > Privacy & Security > Full Disk Access"
    echo "   > + > press Cmd-Shift-G > type /bin/bash > Open > switch on"
    echo
    echo "   Then run ./install.sh again. Running rebuild.sh by hand in"
    echo "   Terminal works either way."
    echo
else
    echo "launchd can run it (no permission errors)"
fi

echo "check it:  launchctl print gui/$UID/$LABEL | head -20"
echo "run now:   $SCRIPT_DIR/rebuild.sh --force"
echo "log:       tail -f ~/Library/Logs/tally-rebuild.log"
