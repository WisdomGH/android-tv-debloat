# DEBLOAT-LOG.md — Hisense 4K ATV4 (192.168.86.245)

## Status: prepared, NOT yet executed

The assistant session that built this toolkit runs in an isolated cloud
container. `192.168.86.245` is a private address on a home LAN, so there is no
network path from that container to the TV. This was verified, not assumed:

```
$ adb connect 192.168.86.245:5555     -> no response
$ adb devices                          -> List of devices attached   (empty)
$ /dev/tcp/192.168.86.245/5555         -> unreachable
$ /dev/tcp/192.168.86.245/5037         -> unreachable
```

Every command below therefore has to be run by the TV's owner, from a computer
on the same network as the TV. The scripts enforce the safety rules mechanically
so that running them is mostly pressing enter and testing the TV between batches.

## Ground rules encoded in the tooling

| Rule | How it is enforced |
|---|---|
| Never uninstall | The string `pm uninstall` appears nowhere. Only `pm disable-user --user 0`. |
| No root / bootloader / custom ROM | Never invoked, never suggested. Widevine L1 stays intact. |
| Measure first | `measure before` / `measure after` capture `dumpsys meminfo`, `pm list packages -s`, `-d`, `-e`, `-3`. |
| Batches of ≤10 | `disable` hard-fails on an 11th package and prints a test checklist before you may continue. |
| Never disable the protected set | `packages/protected.txt`, matched by regex; `disable` refuses a match even if passed by hand. |
| Keep a record | Every success appends to `kapatilanlar.txt` and to this log with its exact undo command. |
| Break → roll back the batch, then bisect | `rollback <batch-file>` re-enables one batch and tells you to narrow down singly. |

## Brand correction: TCL names → Hisense equivalents

The rules named TCL packages. This TV is a **Hisense**, so those exact names
almost certainly do not exist on it — a protection list of TCL names would have
protected nothing at all. Each rule was translated:

| Rule said (TCL) | Its job | Protected on this Hisense as |
|---|---|---|
| `com.tcl.suspension` | Inputs/Source quick panel | `com.mediatek.wwtv.tvcenter`, `com.hisense.tvui`, `com.hisense.suspension`, `com.hisense.quickpanel` |
| `com.tcl.tv`, `com.tcl.tvinput` | HDMI / antenna input services | `com.mediatek.tvinput`, `com.mstar.tv`, `com.hisense.signal`, plus suffix rules `\.tvinput`, `\.inputsource`, `\.tvsource` |
| `com.tcl.tcl_bt_rcu_service`, `com.tcl.autopair` | Remote control | `com.google.android.tv.remote.service`, `com.android.bluetooth`, suffix rules `\.rcu`, `\.autopair` |

`com.mediatek.wwtv.tvcenter` is the one to be most careful about: on MediaTek-based
Hisense sets it *is* the input/source and live-TV surface. It looks like vendor
junk and is not.

Netflix, YouTube and all audio packages were added to the protected set too,
because the batch acceptance test depends on them.

Anything not in the junk catalogue and not protected lands in **group 2** and is
never touched without an explicit decision. The classifier fails closed.

## Verification performed without a TV

The classifier was run against a simulated Hisense package list. All rule-5
equivalents, Netflix, YouTube and core Android were correctly placed in group 3;
`com.google.android.katniss`, `com.google.android.videos`, `com.hisense.appstore`
and `com.spotify.tv.android` were correctly deferred to group 2 rather than
auto-disabled.

## Packages disabled

_None yet — no device has been reached. Each `disable` run appends here._

## Undo everything

```bash
cd tv-debloat && ./undo.sh
```

or as a single command:

```bash
grep -v '^#' tv-debloat/kapatilanlar.txt | tr -d '\r' \
  | xargs -n1 -I{} adb -s 192.168.86.245:5555 shell pm enable {}
```

---

## Classification against the real device (108 enabled packages)

Baseline `packages-enabled.txt` received from the TV. Result: **18 junk / 36 ask / 54 untouchable** (18+36+54 = 108, nothing unaccounted for).

### Two corrections the real list forced

**1. This is classic Android TV, not Google TV.** There is no
`com.google.android.apps.tv.launcherx` on this set. The home screen is
`com.google.android.tvlauncher`, and `com.google.android.leanbacklauncher` and
`com.hisense.tv.customerlauncher` are also present. The `launcher` command was
rewritten to resolve the actual HOME owner at runtime instead of hardcoding a
package that does not exist. `com.android.boot.fallbackhome` was added to the
protected set — it is the emergency home when no launcher resolves, i.e. the
thing that prevents a black screen.

**2. The TCL→Hisense translation was correct.** `com.mediatek.wwtv.tvcenter`
is present and is this TV's `com.tcl.suspension` equivalent (inputs/source).
Protected.

### Protection additions prompted by the real list

- `com.android.vpndialogs` — required for the VPN consent prompt. NordVPN is installed; disabling this can stop it connecting.
- `com.hisense.kpad` — the physical key panel on the TV chassis; the only control path if the remote fails.
- `com.mstar.netflixobserver`, `com.google.android.sss.authbridge` — Netflix support/auth on MStar silicon.
- `com.mediatek.network`, `com.android.proxyhandler`, `com.android.pacprocessor` — connectivity plumbing.
- `com.android.companiondevicemanager`, `com.android.defcontainer`, `com.android.boot.fallbackhome`.
- `org.xbmc.kodi`, `org.videolan.vlc`, `com.nordvpn.android` — user-installed apps, never touched.

### Two over-broad patterns found and anchored

- `com\.google\.android\.leanbacklauncher` was swallowing
  `com.google.android.leanbacklauncher.recommendations` — the ad-row provider,
  the single most-wanted removal. Anchored with `$` so the launcher stays
  protected while the recommendations sub-package became targetable.
- `com\.google\.android\.youtube\.tv` was swallowing `youtube.tvkids` and
  `youtube.tvmusic`. Anchored so only the main YouTube app is protected; the
  Kids and Music variants moved to group 2 for the owner to decide.

### Batches

- `packages/batch-01.txt` — 10 packages, zero user-visible function. Kills the ad/recommendation rows.
- `packages/batch-02.txt` — 8 packages, pending batch 1 passing the test checklist.

Verified: no package in either batch matches a protected pattern.

---

## Group 2 resolved by the owner

**Keeping (8):** `com.google.android.katniss`, `com.google.android.speech.pumpkin`,
`com.hisense.tv.ota`, `com.hisense.remoteupgrade`, `com.mediatek.wwtv.setupwizard`,
`com.google.android.videos`, `com.google.android.youtube.tvmusic`,
`com.google.android.apps.mediashell`.

Katniss and pumpkin are kept together, which is correct — pumpkin is the offline
speech recogniser katniss depends on.

**Held back, not scheduled (10):** see `packages/hold-uncertain.txt`. These are the
packages flagged as unidentified when group 2 was presented. The owner's reply
established that they are unused, not what they do, so rule 5 ("if you are not
sure what a package does, ask before disabling") still applies. They get an
optional one-at-a-time pass at the end rather than being folded into a batch.

One is a live dependency risk worth restating: `com.hisense.hitv.hicloud.account`
is the Hisense cloud account service, and the owner is **keeping** OTA and
remoteupgrade. Hisense firmware updates may authenticate through it, so disabling
it could silently break the updates they chose to retain.

**Batched for disabling (18 from group 2):** `batch-03.txt` (10 preinstalled
apps and vendor media services), `batch-04.txt` (8 low-level leftovers).

### Batch plan

| Batch | Count | Contents |
|---|---|---|
| batch-01 | 10 | Ad/recommendation rows, screensavers, telemetry |
| batch-02 | 8 | Sync adapters, ANT+, demo modes, Google setup wizard |
| batch-03 | 10 | Unused preinstalled apps, DLNA, Hisense push messaging |
| batch-04 | 8 | CTS shims, backup transports, disclaimer screen |

Verified before commit: no batch contains a protected package, a keep-list
package, or a hold-list package. 36 batched + 8 keep + 10 hold = 54 = group 1
(18) + group 2 (36).

Caveats carried forward:
- `com.google.android.tungsten.setupwraith` (batch-02) is what runs after a
  factory reset. Re-enable it before ever resetting the TV.
- `com.google.android.marvin.talkback` (batch-03) is the screen reader. Only
  disable if nobody using the TV needs accessibility.
- `com.google.android.backuptransport` (batch-04) ends cloud backup of app data.

---

## Batches 1 and 2 — APPLIED and verified 2026-09-03

Run from Windows PowerShell. Owner confirmed all six checks passed:
inputs/source, HDMI switch, Netflix, YouTube, sound, on-screen keyboard.

### batch-01

- `com.google.android.tvrecommendations` — Feeds the "Recommended for you" / sponsored rows on the home screen.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.tvrecommendations`
- `com.google.android.leanbacklauncher.recommendations` — Older recommendation-row provider for the leanback home screen.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.leanbacklauncher.recommendations`
- `com.google.android.backdrop` — Google TV ambient screensaver (the photo/art slideshow).  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.backdrop`
- `com.android.dreams.basic` — Basic "Daydream" screensavers (clock, colours).  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.android.dreams.basic`
- `com.android.wallpaperbackup` — Backs up wallpapers; a TV has no wallpaper worth backing up.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.android.wallpaperbackup`
- `com.android.printspooler` — Printing subsystem. There is no printer.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.android.printspooler`
- `com.google.android.feedback` — Sends crash + usage feedback reports to Google.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.feedback`
- `com.google.android.tv.bugreportsender` — TV-specific bug report uploader.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.tv.bugreportsender`
- `com.google.android.partnersetup` — Reports partner/OEM attribution data to Google.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.partnersetup`
- `com.google.android.onetimeinitializer` — One-shot first-boot initialiser, dead weight afterwards.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.onetimeinitializer`

### batch-02

- `com.android.statementservice` — Verifies app-link statements; harmless to lose on a TV.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.android.statementservice`
- `com.google.android.syncadapters.contacts` — Syncs Google Contacts to the TV.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.syncadapters.contacts`
- `com.google.android.syncadapters.calendar` — Syncs Google Calendar to the TV.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.syncadapters.calendar`
- `com.dsi.ant.service.socket` — ANT+ fitness-sensor radio socket service. A TV has no ANT+ radio.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.dsi.ant.service.socket`
- `com.dsi.ant.plugins.antplus` — ANT+ plugin service for heart-rate straps etc. Useless on a TV.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.dsi.ant.plugins.antplus`
- `com.hisense.storemode` — Hisense shop-floor demo mode.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.hisense.storemode`
- `fusion.android.tv.demo` — In-store demo loop app.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable fusion.android.tv.demo`
- `com.google.android.tungsten.setupwraith` — Google TV setup wizard; only runs at first boot / factory reset.  
  undo: `adb -s 192.168.86.245:5555 shell pm enable com.google.android.tungsten.setupwraith`

