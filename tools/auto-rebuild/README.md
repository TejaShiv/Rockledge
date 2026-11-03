# auto-rebuild

Keeps Tally installed and signed, so it never dies on you mid-week.

## Why this exists

Tally is signed with a free Personal Team. Those profiles last **seven
days**, and when one lapses iOS kills the app with SIGKILL before a single
line of our code runs — no crash screen, no warning, just a black screen on
open. There is no way to handle that from inside the app, which is why the
signing strip on the home screen warns beforehand and why this job exists to
make the warning unnecessary.

## The trap this is built around

Rebuilding is **not** enough. Xcode reuses a provisioning profile until it
actually expires, so a plain rebuild on day 5 reinstalls the app with the
same day-7 deadline and nothing is gained.

So the script does two things a manual rebuild does not:

1. **Deletes the cached profile first**, forcing `-allowProvisioningUpdates`
   to fetch a fresh one from the Apple account already signed into Xcode.
2. **Checks the new expiry is genuinely later** than the old one. If Apple
   hands back the same profile, that is reported as a failure. Saying
   "rebuilt" while the clock keeps running would be worse than saying
   nothing.

## What a run does

1. Checks the phone answers over wireless debugging. If not, logs it and
   exits quietly — asleep or out of the house is normal, not a failure.
2. **Copies `kalla.json` off the phone** into `~/.config/tally-rebuild/backups/`,
   keeping the last 30. See below.
3. Reads the expiry of the last build it made. More than 48 hours left means
   there is nothing to do. `--force` skips this.
4. Checks out `main` into a throwaway git worktree, so whatever you have
   half-finished in your own folder is never what lands on the phone. It
   never commits, pushes or touches your working tree.
5. Deletes the cached profiles for `steps.anynameyoulike` (and its UITests
   bundle, which shares the prefix).
6. Builds for the phone's UDID, installs with `devicectl`, and tries to
   launch so the in-app reminders reschedule. A locked phone refuses the
   launch; the install still counts.
7. Confirms the new expiry moved. If it did not, the run fails loudly.
8. Pushes to ntfy — on success and on failure only, never on the quiet
   "nothing to do" runs. Failures also raise a macOS notification, in case
   the phone is the thing that is missing.

## The backup

Every run, before the expiry check short-circuits it — so twice a day rather
than only when a rebuild happens to be due.

The copy is pulled to a scratch file and **validated before anything good is
touched**: it has to parse as JSON, be an object, and carry a `version` the
app understands. That is the same check `Backup.inspect` makes on import, and
for the same reason — the app's decoder is deliberately tolerant and would
turn any JSON object into an empty document, so a truncated pull has to be
caught here rather than quietly kept as if it were real. A failed pull leaves
every existing backup alone, and pruning only runs after a good copy lands.

A backup failure does **not** fail the run. Re-signing is what keeps the app
running at all; a missed copy is worth telling you about, not worth blocking
the rebuild over. You get a push either way.

Two things that were measured rather than assumed:

- **The copy works with the phone locked.** `Store` writes `kalla.json` with
  `completeFileProtectionUntilFirstUserAuthentication` — chosen originally so
  Siri could log things while locked — which also means the Mac can read it
  while locked, provided the phone has been unlocked once since it last
  booted. Verified with `passcodeRequired: true` either side of the copy.
- **A rebuild keeps your data.** A full rebuild and reinstall on the same
  signing certificate left `kalla.json` byte-for-byte identical. The container
  is keyed to the bundle id and signing identity, so a routine re-sign is
  invisible to it. Only a *certificate* change gives the app a new container,
  which is the event that lost everything the first time.

The one case where the copy will fail: the phone has rebooted and nobody has
unlocked it yet. Until the first unlock, the file is unreadable by design.
The failure push says how old the last good backup is, so an overnight reboot
reads as "0 day(s) ago" rather than as an emergency.

## Setup

```
./install.sh
```

That writes `~/.config/tally-rebuild/config` (outside the repo, because the
repo is public) with your phone's UDID and a freshly generated ntfy topic,
then installs and starts the LaunchAgent.

**Subscribe to the topic it prints**, in the ntfy app or at
`https://ntfy.sh/<topic>`. The topic is effectively a password: anyone who
knows it can read your pushes, so do not paste it anywhere public.

## Schedule

03:00, 20:00, and at login. Because the script only acts inside the last 48
hours, that is four chances before any deadline — one sleeping Mac or absent
phone costs nothing. launchd also runs a missed calendar job once the Mac
wakes.

## Checking on it

```
tail -f ~/Library/Logs/tally-rebuild.log     # what it has been doing
ls -lt ~/.config/tally-rebuild/backups/      # the copies it has pulled
./rebuild.sh --force                         # rebuild right now
launchctl print gui/$UID/com.tally.rebuild   # is the agent loaded
```

A healthy quiet run looks like:

```
2026-11-02 20:00:01  --- run started
2026-11-02 20:00:02  phone is reachable
2026-11-02 20:00:02  backed up kalla-2026-11-02-2000.json (57263 bytes, document version 1)
2026-11-02 20:00:02  current build expires Monday 9 November, 1:03 AM (148h left)
2026-11-02 20:00:02  more than 48h left, nothing to do
```

Note the backup on a run that did nothing else. That is the point of it.

The log rotates at 512 KB to a single `.log.1`.

## Removing it

```
./uninstall.sh
```

Leaves the config and log alone, so reinstalling does not make you set the
topic up again.

## Things that can still need you

- **The Apple account must stay signed in to Xcode.** If its session
  expires, the build fails and you get the failure push. Open Xcode,
  re-enter the Apple ID, and the next run recovers.
- **A Keychain prompt.** Signing reads the certificate's private key. It is
  normally already unlocked, but if macOS ever asks, click "Always Allow" so
  unattended runs stop being blocked.
- **The phone has to be on the same network** and paired for wireless
  debugging (globe icon in Devices and Simulators).
- **Seven days is Apple's limit, not a setting.** This does not extend it;
  it just keeps renewing before it bites.
