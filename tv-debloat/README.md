# TV debloat runbook — Hisense 4K ATV4

Run every command from inside this `tv-debloat/` folder, on a computer on the
same network as the TV. Nothing here uninstalls anything; every change is undone
by `./undo.sh`.

```bash
cd tv-debloat
export TV_IP=192.168.86.245     # already the default
```

## a) adb + connect

```bash
./tv-debloat.sh setup      # installs adb: brew on macOS, apt on Linux, guidance on Windows
./tv-debloat.sh connect    # WATCH THE TV: approve "Allow debugging from this computer?"
```

Tick **"Always allow from this computer"**, then re-run `connect`.
If the TV instead shows a **pairing code** (Android 11+ wireless debugging):

```bash
./tv-debloat.sh pair       # asks for the port + 6-digit code shown on the TV
./tv-debloat.sh connect
```

## b) Measure first

```bash
./tv-debloat.sh measure before
```

## c) Classify, approve, then batch

```bash
./tv-debloat.sh classify   # prints the 3-group table
```

Read `packages/group2-ask-me.txt` and decide which of those you actually use.
Then:

```bash
./tv-debloat.sh batches
./tv-debloat.sh disable packages/batch-aa.txt
```

After each batch the script stops and prints the test checklist: **Inputs/Source
button, HDMI switching, Netflix, YouTube, sound, on-screen keyboard.** Only run
the next batch once all six pass.

If something breaks:

```bash
./tv-debloat.sh rollback packages/batch-aa.txt
```

then re-disable that batch's packages one at a time to find the culprit.

## d, e, f) Speed, caches, reboot

```bash
./tv-debloat.sh tweak      # animation scales -> 0.5
./tv-debloat.sh trim       # pm trim-caches
./tv-debloat.sh reboot
./tv-debloat.sh measure after
./tv-debloat.sh report     # before/after table
```

## Replacing the home screen with FLauncher

Order matters — disabling Google's launcher before FLauncher owns Home leaves a
black screen. The script refuses to do it in the wrong order.

1. On the TV: Play Store → **FLauncher** → Install.
2. Open it once.
3. Press **Home** → choose FLauncher → **Always**.
   (Or Settings → Apps → Default apps → Home app → FLauncher.)
4. Then:

```bash
./tv-debloat.sh launcher   # verifies FLauncher owns Home, only then disables launcherx
./tv-debloat.sh reboot
./tv-debloat.sh status     # confirm the Home handler is still FLauncher
```

## Undo everything

```bash
./undo.sh
```
