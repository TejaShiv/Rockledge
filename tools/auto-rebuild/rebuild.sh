#!/bin/bash
#
# Re-signs Tally before its free Personal Team profile runs out.
#
# A free profile lasts seven days and the app is SIGKILLed the moment it
# lapses — no warning from inside, because nothing of ours gets to run. This
# job rebuilds and reinstalls over wireless debugging while there is still
# time, so that never happens.
#
# The subtlety worth knowing: Xcode reuses an unexpired profile, so a plain
# rebuild usually does NOT push the expiry out. The cached profile has to be
# deleted first, and the new expiry has to be checked afterwards, or the job
# would cheerfully report success while the clock kept running down.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)

CONFIG_DIR="$HOME/.config/tally-rebuild"
CONFIG="$CONFIG_DIR/config"
STATE="$HOME/.local/state/tally-rebuild"
LOG="$HOME/Library/Logs/tally-rebuild.log"
DERIVED="$STATE/DerivedData"
CHECKOUT="$STATE/checkout"

BUNDLE_ID="steps.anynameyoulike"
SCHEME="anynameyoulike"
PROJECT="anynameyoulike.xcodeproj"
BRANCH="main"

# Only act inside the last two days of the profile's life. Twice-daily runs
# then give four chances before the deadline, so one sleeping Mac or absent
# phone costs nothing.
REBUILD_WITHIN=$((48 * 3600))
LOG_MAX=$((512 * 1024))

# Backups live beside the config, not in the repo.
BACKUP_DIR="$CONFIG_DIR/backups"
BACKUP_KEEP=30

NTFY_SERVER="https://ntfy.sh"
NTFY_TOPIC=""
DEVICE_UDID=""

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

mkdir -p "$STATE" "$(dirname "$LOG")"

# ---------------------------------------------------------------- logging

rotate_log() {
    [ -f "$LOG" ] || return 0
    local size
    size=$(/usr/bin/stat -f%z "$LOG" 2>/dev/null || echo 0)
    [ "$size" -gt "$LOG_MAX" ] || return 0
    /bin/mv -f "$LOG" "$LOG.1"
}

log() {
    printf '%s  %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

# --------------------------------------------------------------- notifying

push() {        # push <title> <body>
    [ -n "$NTFY_TOPIC" ] || { log "no ntfy topic configured, push skipped"; return 0; }
    /usr/bin/curl -fsS --max-time 15 \
        -H "Title: $1" \
        -d "$2" \
        "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null 2>&1 \
        || log "ntfy push failed"
}

# Failures also surface on the Mac, in case the phone is the thing that is
# missing.
banner() {
    /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" \
        > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------- dates

# The profile is CMS-signed with an XML plist in the middle. Cut it out by
# its own delimiters rather than decoding the signature: no crypto, and —
# the point — no Keychain prompt in the middle of an unattended run.
expiry_of() {   # expiry_of <path to .mobileprovision> -> epoch seconds
    /usr/bin/python3 -I - "$1" <<'PY'
import datetime, plistlib, sys
try:
    raw = open(sys.argv[1], "rb").read()
except OSError:
    sys.exit(1)
start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
if start < 0 or end < 0:
    sys.exit(1)
try:
    found = plistlib.loads(raw[start:end + 8]).get("ExpirationDate")
except Exception:
    sys.exit(1)
if not found:
    sys.exit(1)
print(int(found.replace(tzinfo=datetime.timezone.utc).timestamp()))
PY
}

# Whether a profile belongs to Tally. Matches the UITests bundle too, which
# shares the prefix and would otherwise be left stale.
is_tally_profile() {
    /usr/bin/python3 -I - "$1" "$BUNDLE_ID" <<'PY'
import plistlib, sys
raw = open(sys.argv[1], "rb").read()
start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
if start < 0 or end < 0:
    sys.exit(1)
try:
    found = plistlib.loads(raw[start:end + 8])
except Exception:
    sys.exit(1)
app_id = found.get("Entitlements", {}).get("application-identifier", "")
# "TEAMID.steps.anynameyoulike"
sys.exit(0 if ".%s" % sys.argv[2] in app_id else 1)
PY
}

when() { /bin/date -r "$1" '+%A %-d %B, %-I:%M %p'; }
when_short() { /bin/date -r "$1" '+%A %-I:%M %p'; }

# ---------------------------------------------------------------- backing up

# The version this build of the app understands, read from the source so the
# two cannot drift apart. A document from a newer build must not be kept as
# though it were readable.
known_version() {
    local found
    found=$(/usr/bin/grep -oE 'currentVersion *= *[0-9]+' \
                "$REPO/anynameyoulike/Store.swift" 2>/dev/null \
            | /usr/bin/grep -oE '[0-9]+$' | /usr/bin/head -1)
    echo "${found:-1}"
}

# Same check the app makes on import: read `version` out of the raw JSON
# before trusting any of it. The app's decoder is deliberately tolerant and
# would turn any JSON object into an empty document, so a truncated or
# half-written pull has to be caught here rather than decoded into silence.
validate_pull() {      # validate_pull <file> <highest known version>
    /usr/bin/python3 -I - "$1" "$2" <<'PY'
import json, sys
try:
    doc = json.load(open(sys.argv[1], "rb"))
except Exception:
    sys.exit(1)
if not isinstance(doc, dict):
    sys.exit(1)
version = doc.get("version")
if not isinstance(version, int) or isinstance(version, bool):
    sys.exit(1)
if version > int(sys.argv[2]):
    sys.exit(1)
print(version)
PY
}

BACKUP_PROBLEM=""

# Runs on every pass, whether or not a rebuild was due. The rebuild only acts
# in the last 48 hours; losing the data is the thing with no deadline at all.
back_up_data() {
    /bin/mkdir -p "$BACKUP_DIR"

    local tmp stamp dest version
    tmp=$(/usr/bin/mktemp -d -t tally-backup) || {
        BACKUP_PROBLEM="no temporary space on the Mac"; return 1
    }

    # Pulled to a scratch file first. Nothing already good is touched until
    # the new copy has been read and believed.
    if ! /usr/bin/xcrun devicectl device copy from \
            --device "$DEVICE_UDID" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --source Documents/kalla.json \
            --destination "$tmp/kalla.json" \
            --timeout 90 > /dev/null 2>&1; then
        /bin/rm -rf "$tmp"
        BACKUP_PROBLEM="could not copy kalla.json off the phone"
        return 1
    fi

    if ! version=$(validate_pull "$tmp/kalla.json" "$(known_version)"); then
        /bin/rm -rf "$tmp"
        BACKUP_PROBLEM="the file pulled off the phone did not look like a Tally document"
        return 1
    fi

    stamp=$(/bin/date '+%Y-%m-%d-%H%M')
    dest="$BACKUP_DIR/kalla-$stamp.json"
    /bin/mv -f "$tmp/kalla.json" "$dest" || {
        /bin/rm -rf "$tmp"
        BACKUP_PROBLEM="could not write the backup to $BACKUP_DIR"
        return 1
    }
    /bin/rm -rf "$tmp"

    local size
    size=$(/usr/bin/stat -f%z "$dest" 2>/dev/null || echo 0)
    log "backed up $(/usr/bin/basename "$dest") (${size} bytes, document version $version)"

    prune_backups
    return 0
}

# Newest thirty kept. Pruned only after a good copy has landed, so a run that
# could not pull anything never costs you history.
prune_backups() {
    local dropped=0 old
    while IFS= read -r old; do
        [ -n "$old" ] || continue
        /bin/rm -f "$old" && dropped=$((dropped + 1))
    done < <(/bin/ls -t "$BACKUP_DIR"/kalla-*.json 2>/dev/null | /usr/bin/tail -n +$((BACKUP_KEEP + 1)))

    [ "$dropped" -gt 0 ] && log "pruned $dropped old backup(s), keeping $BACKUP_KEEP"
    return 0
}

newest_backup_age() {   # days since the newest backup, or 9999 if there is none
    local newest when
    newest=$(/bin/ls -t "$BACKUP_DIR"/kalla-*.json 2>/dev/null | /usr/bin/head -1)
    [ -n "$newest" ] || { echo 9999; return; }
    when=$(/usr/bin/stat -f%m "$newest" 2>/dev/null || echo 0)
    echo $(( ($(/bin/date +%s) - when) / 86400 ))
}

# ---------------------------------------------------------------- failing

OLD_EXPIRY=0

die() {         # die <short reason>
    log "FAILED: $1"
    local deadline="your next Xcode build"
    [ "$OLD_EXPIRY" -gt 0 ] && deadline=$(when_short "$OLD_EXPIRY")
    push "Tally couldn't rebuild itself" "$1. Rebuild from Xcode before $deadline."
    banner "Tally couldn't rebuild itself" "$1"
    cleanup
    exit 1
}

cleanup() {
    [ -d "$CHECKOUT" ] && /usr/bin/git -C "$REPO" worktree remove --force "$CHECKOUT" > /dev/null 2>&1
    /usr/bin/git -C "$REPO" worktree prune > /dev/null 2>&1
    return 0
}

# ================================================================== run

# Only one at a time. A build takes minutes, and launchd firing a second
# run into the middle of one would have two xcodebuilds fighting over the
# same derived data and the same profile cache.
LOCK="$STATE/lock"
if ! /bin/mkdir "$LOCK" 2>/dev/null; then
    held=$(/usr/bin/stat -f%m "$LOCK" 2>/dev/null || echo 0)
    if [ "$(( $(/bin/date +%s) - held ))" -gt 3600 ]; then
        log "stale lock from a killed run, taking it"
        /bin/rm -rf "$LOCK" && /bin/mkdir "$LOCK"
    else
        log "another run is in progress, skipping"
        exit 0
    fi
fi
trap '/bin/rmdir "$LOCK" 2>/dev/null' EXIT

rotate_log
log "--- run started${FORCE:+ }$([ $FORCE -eq 1 ] && echo '(forced)')"

# -- config ------------------------------------------------------------

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG"
else
    log "no config at $CONFIG — see tools/auto-rebuild/README.md"
fi

if [ -z "$DEVICE_UDID" ]; then
    log "FAILED: DEVICE_UDID is not set in $CONFIG"
    exit 1
fi

# -- 1. is the phone there? --------------------------------------------

# `devicectl device info details` is NOT a reachability test: it answers
# from cached pairing data and exits 0 for a phone that is asleep or on
# another network, which would send the job on to a build that then fails
# on the destination and push a failure that was never one. Asking for the
# lock state needs a live tunnel, so it fails when the phone really is away.
if ! /usr/bin/xcrun devicectl device info lockState \
        --device "$DEVICE_UDID" --timeout 45 > /dev/null 2>&1; then
    # Not a failure. The phone is asleep, out of the house, or on another
    # network, and the next run will find it.
    log "phone not reachable, leaving it for the next run"
    exit 0
fi
log "phone is reachable"

# -- 2. the backup, every run ------------------------------------------

# Deliberately before the expiry check, which exits early on most runs. A
# backup that only happened when a rebuild was due would be a backup twice a
# week at best.
if ! back_up_data; then
    log "backup failed: $BACKUP_PROBLEM"
    # Not fatal. Re-signing is what keeps the app running at all, and a
    # failed copy must not stop it — but it is still worth being told.
    age=$(newest_backup_age)
    if [ "$age" -ge 9999 ]; then
        push "Tally couldn't back up" "$BACKUP_PROBLEM. There is no saved backup at all yet."
    else
        push "Tally couldn't back up" "$BACKUP_PROBLEM. Last good backup was $age day(s) ago."
    fi
fi

# -- 3. how long is left? ----------------------------------------------

BUILT_APP="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
if [ -f "$BUILT_APP/embedded.mobileprovision" ]; then
    OLD_EXPIRY=$(expiry_of "$BUILT_APP/embedded.mobileprovision" || echo 0)
elif [ -f "$STATE/last-expiry" ]; then
    OLD_EXPIRY=$(cat "$STATE/last-expiry" 2>/dev/null || echo 0)
fi

NOW=$(/bin/date +%s)
if [ "$OLD_EXPIRY" -gt 0 ]; then
    LEFT=$((OLD_EXPIRY - NOW))
    log "current build expires $(when "$OLD_EXPIRY") ($((LEFT / 3600))h left)"

    if [ "$FORCE" -eq 0 ] && [ "$LEFT" -gt "$REBUILD_WITHIN" ]; then
        log "more than 48h left, nothing to do"
        exit 0
    fi
else
    log "no record of a previous build, rebuilding"
fi

# -- 4. a clean copy of main -------------------------------------------

cleanup                                   # any wreckage from a killed run
if ! /usr/bin/git -C "$REPO" worktree add --detach "$CHECKOUT" "$BRANCH" \
        > /dev/null 2>&1; then
    die "could not check out $BRANCH"
fi
log "checked out $BRANCH at $(/usr/bin/git -C "$CHECKOUT" rev-parse --short HEAD)"

# -- 5. force a new profile --------------------------------------------

# Without this the build reuses the profile it already has and the expiry
# never moves, which is the whole failure this job exists to prevent.
PURGED=0
for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
           "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    while IFS= read -r profile; do
        [ -n "$profile" ] || continue
        if is_tally_profile "$profile"; then
            /bin/rm -f "$profile" && PURGED=$((PURGED + 1))
            log "deleted cached profile $(/usr/bin/basename "$profile")"
        fi
    done < <(/usr/bin/find "$dir" -maxdepth 1 -name '*.mobileprovision' 2>/dev/null)
done
log "purged $PURGED cached profile(s)"

# -- 6. build, install, launch -----------------------------------------

BUILD_LOG=$(/usr/bin/mktemp -t tally-rebuild)
log "building…"

if ! /usr/bin/xcrun xcodebuild \
        -project "$CHECKOUT/$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS,id=$DEVICE_UDID" \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        build > "$BUILD_LOG" 2>&1; then
    log "last lines of the build:"
    /usr/bin/tail -n 25 "$BUILD_LOG" >> "$LOG"
    /bin/rm -f "$BUILD_LOG"
    die "the build failed"
fi
/bin/rm -f "$BUILD_LOG"
log "built"

if ! /usr/bin/xcrun devicectl device install app \
        --device "$DEVICE_UDID" "$BUILT_APP" > /dev/null 2>&1; then
    die "could not install on the phone"
fi
log "installed"

# A locked phone refuses the launch, and that is fine: the install is what
# matters, and the in-app reminders reschedule next time it is opened.
if /usr/bin/xcrun devicectl device process launch \
        --device "$DEVICE_UDID" "$BUNDLE_ID" > /dev/null 2>&1; then
    log "launched"
else
    log "could not launch (phone probably locked) — install still counts"
fi

# -- 7. did the expiry actually move? ----------------------------------

NEW_EXPIRY=$(expiry_of "$BUILT_APP/embedded.mobileprovision" || echo 0)
if [ "$NEW_EXPIRY" -le 0 ]; then
    die "could not read the new profile's expiry"
fi

if [ "$NEW_EXPIRY" -le "$OLD_EXPIRY" ]; then
    # Apple handed back the same profile. Reporting success here would be
    # worse than failing: the countdown would look handled and would not be.
    die "Apple reissued the same profile, expiry did not move"
fi

echo "$NEW_EXPIRY" > "$STATE/last-expiry"
log "SUCCEEDED: now good until $(when "$NEW_EXPIRY")"
push "Tally rebuilt" "Good until $(when "$NEW_EXPIRY")."

cleanup
exit 0
