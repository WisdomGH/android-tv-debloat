#!/usr/bin/env bash
# tv-debloat.sh - staged, reversible Android TV cleanup over ADB.
# Uses ONLY `pm disable-user --user 0`. Never uninstalls. Never roots.
set -uo pipefail

TV_IP="${TV_IP:-192.168.86.245}"
PORT="${PORT:-5555}"
DEV="${TV_IP}:${PORT}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGDIR="$HERE/packages"
MEAS="$HERE/measurements"
RECORD="$HERE/kapatilanlar.txt"
LOG="$HERE/DEBLOAT-LOG.md"
BATCH_MAX=10
A=(adb -s "$DEV")

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_bld=$'\033[1m'; c_rst=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yel" "$c_rst" "$*"; }
die()  { printf '%s✗ %s%s\n' "$c_red" "$*" "$c_rst" >&2; exit 1; }
hdr()  { printf '\n%s== %s ==%s\n' "$c_bld" "$*" "$c_rst"; }

pats() { grep -vE '^[[:space:]]*(#|$)' "$PKGDIR/protected.txt"; }

is_protected() { # $1=pkg -> 0 if protected
  printf '%s\n' "$1" | grep -qE -f <(pats)
}

need_device() {
  "${A[@]}" get-state >/dev/null 2>&1 || die "TV not connected. Run: $0 connect"
}

# ---------------------------------------------------------------- setup
cmd_setup() {
  hdr "Step A - toolchain"
  if command -v adb >/dev/null 2>&1; then
    ok "adb already installed: $(adb version | head -1)"
  else
    warn "adb not found. Installing for your OS..."
    case "$(uname -s)" in
      Darwin) command -v brew >/dev/null || die "Install Homebrew first: https://brew.sh"
              brew install android-platform-tools ;;
      Linux)  sudo apt-get update && sudo apt-get install -y adb ;;
      MINGW*|MSYS*|CYGWIN*)
              die "Windows: download https://dl.google.com/android/repository/platform-tools-latest-windows.zip
     unzip it (e.g. to C:\\platform-tools) and add that folder to PATH, then re-run." ;;
      *)      die "Unknown OS. Install Android platform-tools manually." ;;
    esac
    command -v adb >/dev/null || die "adb still not on PATH."
    ok "adb installed."
  fi
}

cmd_pair() { # Android 11+ wireless debugging
  hdr "Wireless debugging pairing (Android 11+)"
  say "On the TV: Settings > System > Developer options > Wireless debugging"
  say "         > 'Pair device with pairing code'."
  read -r -p "Pairing PORT shown on TV: " pp
  read -r -p "6-digit pairing CODE: " pc
  adb pair "${TV_IP}:${pp}" "$pc" || die "Pairing failed."
  ok "Paired."
}

cmd_connect() {
  hdr "Connecting to $DEV"
  adb start-server >/dev/null 2>&1
  adb connect "$DEV" || true
  sleep 2
  local st; st="$("${A[@]}" get-state 2>&1)"
  if [ "$st" != "device" ]; then
    warn "State: $st"
    say ""
    say "${c_bld}LOOK AT YOUR TV NOW.${c_rst} It should be showing:"
    say "    \"Allow debugging from this computer?\""
    say "Tick 'Always allow from this computer' and choose OK, then re-run:"
    say "    $0 connect"
    say ""
    say "If instead the TV asks for a PAIRING CODE, run:  $0 pair"
    exit 1
  fi
  ok "Connected. Device: $("${A[@]}" shell getprop ro.product.model | tr -d '\r')"
  say "  Android: $("${A[@]}" shell getprop ro.build.version.release | tr -d '\r')  (SDK $("${A[@]}" shell getprop ro.build.version.sdk | tr -d '\r'))"
  say "  Vendor : $("${A[@]}" shell getprop ro.product.manufacturer | tr -d '\r')"
}

# ------------------------------------------------------------- measure
cmd_measure() {
  local label="${1:?usage: measure <label>   e.g. before | after}"
  need_device
  local d="$MEAS/$label"; mkdir -p "$d"
  hdr "Step B - measurements ($label)"
  "${A[@]}" shell dumpsys meminfo            > "$d/meminfo.txt"      2>&1
  "${A[@]}" shell pm list packages -s        > "$d/packages-system.txt"   2>&1
  "${A[@]}" shell pm list packages -d        > "$d/packages-disabled.txt" 2>&1
  "${A[@]}" shell pm list packages -e        > "$d/packages-enabled.txt"  2>&1
  "${A[@]}" shell pm list packages -3        > "$d/packages-thirdparty.txt" 2>&1
  sed -i.bak 's/\r$//' "$d"/*.txt 2>/dev/null; rm -f "$d"/*.bak
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$d/timestamp.txt"
  ok "Saved to measurements/$label/"
  say "  Total RAM : $(grep -m1 'Total RAM' "$d/meminfo.txt" | sed 's/^[[:space:]]*//')"
  say "  Free  RAM : $(grep -m1 'Free RAM'  "$d/meminfo.txt" | sed 's/^[[:space:]]*//')"
  say "  Used  RAM : $(grep -m1 'Used RAM'  "$d/meminfo.txt" | sed 's/^[[:space:]]*//')"
  say "  system pkgs=$(wc -l < "$d/packages-system.txt")  disabled=$(wc -l < "$d/packages-disabled.txt")  enabled=$(wc -l < "$d/packages-enabled.txt")"
}

# ------------------------------------------------------------ classify
cmd_classify() {
  need_device
  local d="$MEAS/before"
  [ -f "$d/packages-enabled.txt" ] || die "Run '$0 measure before' first."
  hdr "Step C - sorting packages into three groups"
  local live="$MEAS/_live.txt"
  sed 's/^package://' "$d/packages-enabled.txt" | sort -u > "$live"

  local g1="$PKGDIR/group1-junk.txt" g2="$PKGDIR/group2-ask-me.txt" g3="$PKGDIR/group3-untouchable.txt"
  : > "$g1"; : > "$g2"; : > "$g3"

  # group 3: anything matching a protected pattern
  grep -E -f <(pats) "$live" > "$g3" || true

  # group 1: catalogue entries that exist AND are not protected
  while IFS='|' read -r pkg desc; do
    case "$pkg" in ''|\#*) continue;; esac
    grep -qxF "$pkg" "$live" || continue
    is_protected "$pkg" && continue
    printf '%s|%s\n' "$pkg" "$desc" >> "$g1"
  done < "$PKGDIR/junk.txt"

  # group 2: everything else
  comm -23 "$live" <(cut -d'|' -f1 "$g1" | sort -u) \
    | grep -vE -f <(pats) > "$g2" || true

  say ""
  printf '%-46s %s\n' "GROUP" "COUNT"
  printf '%-46s %s\n' "---------------------------------------------" "-----"
  printf '%-46s %s\n' "1. definitely junk (safe, reversible)" "$(wc -l < "$g1")"
  printf '%-46s %s\n' "2. depends on you (I will ask)"        "$(wc -l < "$g2")"
  printf '%-46s %s\n' "3. untouchable (blocked by protected.txt)" "$(wc -l < "$g3")"
  say ""
  say "${c_bld}GROUP 1 - proposed for disabling:${c_rst}"
  awk -F'|' '{printf "  %-52s %s\n",$1,$2}' "$g1"
  say ""
  say "Group 2 written to packages/group2-ask-me.txt - review it and tell me"
  say "which ones you actually use. Nothing in group 2 is touched without you."
  say ""
  say "Next: split group 1 into batches of $BATCH_MAX:   $0 batches"
}

cmd_batches() {
  local g1="$PKGDIR/group1-junk.txt"
  [ -s "$g1" ] || die "Run '$0 classify' first."
  rm -f "$PKGDIR"/batch-*.txt
  cut -d'|' -f1 "$g1" | split -l "$BATCH_MAX" - "$PKGDIR/batch-"
  for f in "$PKGDIR"/batch-*; do mv "$f" "$f.txt"; done
  hdr "Batches created (max $BATCH_MAX packages each)"
  for f in "$PKGDIR"/batch-*.txt; do printf '  %-28s %s packages\n' "$(basename "$f")" "$(wc -l < "$f")"; done
  say ""
  say "Run them ONE AT A TIME:   $0 disable packages/batch-aa.txt"
}

# ------------------------------------------------------------- disable
cmd_disable() {
  local file="${1:?usage: disable <file-of-packages>}"
  [ -f "$file" ] || file="$HERE/$file"
  [ -f "$file" ] || die "No such file: $1"
  need_device
  mapfile -t list < <(grep -vE '^[[:space:]]*(#|$)' "$file" | cut -d'|' -f1)
  [ "${#list[@]}" -le "$BATCH_MAX" ] || die "Batch has ${#list[@]} packages; rule 4 caps it at $BATCH_MAX."

  hdr "Disabling batch: $(basename "$file") (${#list[@]} packages)"
  local done_any=0
  for p in "${list[@]}"; do
    if is_protected "$p"; then warn "REFUSED (protected): $p"; continue; fi
    local out; out="$("${A[@]}" shell pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')"
    if printf '%s' "$out" | grep -q 'new state: disabled'; then
      ok "disabled  $p"
      grep -qxF "$p" "$RECORD" 2>/dev/null || printf '%s\n' "$p" >> "$RECORD"
      local desc; desc="$(grep -m1 "^$p|" "$PKGDIR/junk.txt" | cut -d'|' -f2)"
      printf -- '- `%s` — %s  \n  undo: `adb -s %s shell pm enable %s`\n' \
        "$p" "${desc:-(no description on file)}" "$DEV" "$p" >> "$LOG"
      done_any=1
    else
      warn "skipped   $p  ($out)"
    fi
  done
  [ "$done_any" = 1 ] && printf '\n' >> "$LOG"

  cat <<TEST

${c_bld}STOP. Rule 4 - test the TV now, before the next batch.${c_rst}
  [ ] Remote's Inputs / Source button opens the input list
  [ ] You can switch to an HDMI input and see a picture
  [ ] Netflix opens
  [ ] YouTube opens
  [ ] Sound works
  [ ] The on-screen keyboard appears when you search

All good  -> run the next batch.
Something broke -> ${c_red}$0 rollback $(basename "$file")${c_rst}   (re-enables this batch only)
TEST
}

cmd_rollback() {
  local file="${1:?usage: rollback <batch-file>}"
  [ -f "$file" ] || file="$PKGDIR/$(basename "$file")"
  need_device
  hdr "Rolling back $(basename "$file")"
  while read -r p; do
    [ -n "$p" ] || continue
    "${A[@]}" shell pm enable "$p" >/dev/null 2>&1 && ok "re-enabled $p"
    sed -i.bak "/^$(printf '%s' "$p" | sed 's/\./\\./g')$/d" "$RECORD" 2>/dev/null; rm -f "$RECORD.bak"
  done < <(grep -vE '^[[:space:]]*(#|$)' "$file" | cut -d'|' -f1)
  say ""
  say "Now narrow it down one package at a time (rule 7): disable them singly,"
  say "testing after each, until you find the one that broke it."
}

# ---------------------------------------------------------- tweaks etc
cmd_tweak() {
  need_device
  hdr "Step D - halving animation speeds"
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    "${A[@]}" shell settings put global "$k" 0.5
    ok "$k = $("${A[@]}" shell settings get global "$k" | tr -d '\r')"
  done
  say "Undo: set all three back to 1.0"
}

cmd_trim() {
  need_device
  hdr "Step E - trimming caches"
  "${A[@]}" shell pm trim-caches 999G 2>&1 | tr -d '\r'
  ok "Cache trim requested."
}

cmd_reboot() {
  need_device
  hdr "Step F - rebooting"
  "${A[@]}" reboot
  say "Waiting for the TV to come back (up to 3 min)..."
  local n=0
  until adb connect "$DEV" >/dev/null 2>&1 && [ "$("${A[@]}" get-state 2>/dev/null)" = device ]; do
    n=$((n+1)); [ "$n" -gt 36 ] && { warn "Timed out. Reconnect with: $0 connect"; return 1; }
    sleep 5
  done
  ok "TV is back."
}

# --------------------------------------------------------- the launcher
cmd_launcher() {
  need_device
  hdr "Replacing the home screen with FLauncher"
  # NOTE: this set is classic Android TV (leanback). There is no
  # com.google.android.apps.tv.launcherx here. We detect the real HOME owner
  # instead of hardcoding a package name.
  local fl; fl="$("${A[@]}" shell pm list packages 2>/dev/null | tr -d '\r' | grep -i flauncher)"
  if [ -z "$fl" ]; then
    say "${c_red}FLauncher is not installed yet.${c_rst}"
    say "  TV > Play Store > search 'FLauncher' > Install > open it once >"
    say "  press Home > choose FLauncher > Always."
    say "Then re-run: $0 launcher"
    return 1
  fi
  ok "FLauncher present: ${fl#package:}"

  local cur; cur="$("${A[@]}" shell cmd package resolve-activity -c android.intent.category.HOME --user 0 2>/dev/null | tr -d '\r' | grep -m1 packageName= | cut -d= -f2)"
  say "  Current HOME handler: ${cur:-unknown}"
  if ! printf '%s' "$cur" | grep -qi flauncher; then
    say ""
    say "${c_red}FLauncher is installed but does NOT own Home.${c_rst}"
    say "Set it on the TV first. Disabling the stock launcher before that is"
    say "exactly what leaves you staring at a black screen."
    return 1
  fi
  ok "FLauncher owns Home. Safe to disable the stock launchers."

  # Candidates actually present on this TV, minus whatever now owns Home.
  local cands=() p
  for p in com.google.android.tvlauncher com.google.android.leanbacklauncher com.hisense.tv.customerlauncher; do
    "${A[@]}" shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx "package:$p" || continue
    printf '%s' "$cur" | grep -qx "$p" && continue
    cands+=("$p")
  done
  [ "${#cands[@]}" -gt 0 ] || { warn "No stock launcher left to disable."; return 0; }

  say ""
  say "Will disable: ${cands[*]}"
  say "${c_yel}com.android.boot.fallbackhome stays enabled - it is your safety net.${c_rst}"
  read -r -p "Proceed? [y/N] " a
  [ "$a" = y ] || { say "Skipped."; return 0; }
  for p in "${cands[@]}"; do
    local out; out="$("${A[@]}" shell pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')"
    if printf '%s' "$out" | grep -q 'new state: disabled'; then
      ok "disabled $p"
      grep -qxF "$p" "$RECORD" 2>/dev/null || printf '%s\n' "$p" >> "$RECORD"
      printf -- '- `%s` — stock Android TV launcher (ad + recommendation rows), replaced by FLauncher.  \n  undo: `adb -s %s shell pm enable %s`\n' "$p" "$DEV" "$p" >> "$LOG"
    else
      warn "skipped $p ($out)"
    fi
  done
  say ""
  ok "Now: $0 reboot   then $0 status   to confirm FLauncher still owns Home."
}

# ------------------------------------------------------------- report
mem() { grep -m1 "$2" "$MEAS/$1/meminfo.txt" 2>/dev/null | grep -oE '[0-9,]+K' | head -1; }
cnt() { [ -f "$MEAS/$1/$2" ] && wc -l < "$MEAS/$1/$2" | tr -d ' ' || echo "-"; }

cmd_report() {
  [ -d "$MEAS/before" ] || die "No 'before' measurement."
  [ -d "$MEAS/after"  ] || die "No 'after' measurement. Run: $0 measure after"
  hdr "BEFORE / AFTER"
  printf '| %-22s | %-14s | %-14s |\n' "Metric" "Before" "After"
  printf '|%s|%s|%s|\n' "------------------------" "----------------" "----------------"
  printf '| %-22s | %-14s | %-14s |\n' "Total RAM"        "$(mem before 'Total RAM')" "$(mem after 'Total RAM')"
  printf '| %-22s | %-14s | %-14s |\n' "Free RAM"         "$(mem before 'Free RAM')"  "$(mem after 'Free RAM')"
  printf '| %-22s | %-14s | %-14s |\n' "Used RAM"         "$(mem before 'Used RAM')"  "$(mem after 'Used RAM')"
  printf '| %-22s | %-14s | %-14s |\n' "Lost RAM"         "$(mem before 'Lost RAM')"  "$(mem after 'Lost RAM')"
  printf '| %-22s | %-14s | %-14s |\n' "System packages"  "$(cnt before packages-system.txt)"   "$(cnt after packages-system.txt)"
  printf '| %-22s | %-14s | %-14s |\n' "Disabled packages" "$(cnt before packages-disabled.txt)" "$(cnt after packages-disabled.txt)"
  printf '| %-22s | %-14s | %-14s |\n' "Enabled packages"  "$(cnt before packages-enabled.txt)"  "$(cnt after packages-enabled.txt)"
  say ""
  say "Packages disabled this run: $(grep -cvE '^[[:space:]]*(#|$)' "$RECORD" 2>/dev/null || echo 0)"
}

cmd_undo() {
  need_device
  [ -s "$RECORD" ] || die "Nothing recorded in kapatilanlar.txt."
  hdr "UNDO - re-enabling everything"
  while read -r p; do
    [ -n "$p" ] || continue
    "${A[@]}" shell pm enable "$p" >/dev/null 2>&1 && ok "re-enabled $p" || warn "failed $p"
  done < <(grep -vE '^[[:space:]]*(#|$)' "$RECORD")
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    "${A[@]}" shell settings put global "$k" 1.0
  done
  ok "Animation scales restored to 1.0."
  say "Reboot to be safe: $0 reboot"
}

cmd_status() {
  need_device
  hdr "Status"
  say "Device      : $("${A[@]}" shell getprop ro.product.model | tr -d '\r')"
  say "Home handler: $("${A[@]}" shell cmd package resolve-activity -c android.intent.category.HOME --user 0 2>/dev/null | tr -d '\r' | grep -m1 packageName= | cut -d= -f2)"
  say "Disabled by me: $(grep -cvE '^[[:space:]]*(#|$)' "$RECORD" 2>/dev/null || echo 0)"
}

usage() {
  cat <<USAGE
tv-debloat.sh - staged, fully reversible Android TV cleanup (TV_IP=$TV_IP)

  setup                 check/install adb for your OS
  pair                  Android 11+ wireless-debugging pairing code flow
  connect               adb connect + approve-on-TV guidance
  measure before|after  capture meminfo + package lists
  classify              sort packages into the 3 groups, print the table
  batches               split group 1 into batches of $BATCH_MAX
  disable <file>        disable one batch (<=$BATCH_MAX), then STOP for testing
  rollback <file>       re-enable one batch
  tweak                 animation scales -> 0.5
  trim                  pm trim-caches
  reboot                reboot and wait for reconnect
  launcher              FLauncher checks, then disable the stock launcher(s)
  report                before/after table
  undo                  re-enable EVERYTHING + restore animations
  status                quick health check
USAGE
}

case "${1:-}" in
  setup) cmd_setup ;; pair) cmd_pair ;; connect) cmd_connect ;;
  measure) shift; cmd_measure "$@" ;; classify) cmd_classify ;; batches) cmd_batches ;;
  disable) shift; cmd_disable "$@" ;; rollback) shift; cmd_rollback "$@" ;;
  tweak) cmd_tweak ;; trim) cmd_trim ;; reboot) cmd_reboot ;;
  launcher) cmd_launcher ;; report) cmd_report ;; undo) cmd_undo ;; status) cmd_status ;;
  *) usage ;;
esac
