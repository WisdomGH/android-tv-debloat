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
