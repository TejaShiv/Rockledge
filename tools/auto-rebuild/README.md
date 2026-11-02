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
2. Reads the expiry of the last build it made. More than 48 hours left means
   there is nothing to do. `--force` skips this.
3. Checks out `main` into a throwaway git worktree, so whatever you have
   half-finished in your own folder is never what lands on the phone. It
   never commits, pushes or touches your working tree.
4. Deletes the cached profiles for `steps.anynameyoulike` (and its UITests
   bundle, which shares the prefix).
5. Builds for the phone's UDID, installs with `devicectl`, and tries to
   launch so the in-app reminders reschedule. A locked phone refuses the
   launch; the install still counts.
6. Confirms the new expiry moved. If it did not, the run fails loudly.
7. Pushes to ntfy — on success and on failure only, never on the quiet
   "nothing to do" runs. Failures also raise a macOS notification, in case
   the phone is the thing that is missing.

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
./rebuild.sh --force                         # rebuild right now
launchctl print gui/$UID/com.tally.rebuild   # is the agent loaded
```

A healthy quiet run looks like:

```
2026-11-02 20:00:01  --- run started
2026-11-02 20:00:02  phone is reachable
2026-11-02 20:00:02  current build expires Monday 9 November, 1:03 AM (148h left)
2026-11-02 20:00:02  more than 48h left, nothing to do
```

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
