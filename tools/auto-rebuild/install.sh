#!/bin/bash
#
# Installs the LaunchAgent, and creates the config file if it is missing.
# Run it again any time to pick up changes to the plist template.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LABEL="com.tally.rebuild"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
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

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL"

echo "installed $PLIST"
echo "runs at 03:00, 20:00 and at login"
echo
case "$SCRIPT_DIR" in
    "$HOME"/Desktop/*|"$HOME"/Documents/*|"$HOME"/Downloads/*)
        echo
        echo "!! The repo is in a folder macOS protects, so launchd cannot"
        echo "   reach this script on its own — runs will fail with"
        echo "   \"Operation not permitted\" until you allow it."
        echo
        echo "   System Settings > Privacy & Security > Full Disk Access"
        echo "   > + > press Cmd-Shift-G > type /bin/bash > Open > switch on"
        echo
        echo "   Then run ./install.sh again. Running rebuild.sh by hand in"
        echo "   Terminal works either way."
        echo
        ;;
esac

echo "check it:  launchctl print gui/$UID/$LABEL | head -20"
echo "run now:   $SCRIPT_DIR/rebuild.sh --force"
echo "log:       tail -f ~/Library/Logs/tally-rebuild.log"
