#!/bin/sh
# Delete the timelapses in /mnt/sdcard/timelapse (the <job>.avi videos and the <job>/ photo folders), except
# the one a print is still writing. task buddy:timelapse:clean copies this to /tmp and runs it over ssh.
#
# Usage: sh timelapse-clean.sh [-n]
#   -n  dry run: list what would be deleted or kept, change nothing
#
# A job is in progress when any process (lp_app) has a file open under <job>.avi or <job>/; its video and
# photos are kept. The timelapse/ directory itself stays: lp_app does not create it, the card's boot hook does.
# .timelapse_videos.csv ("<job>.avi:D" lines) keeps only the lines whose video is still there.
# Nothing here walks the photo folders (find/du over thousands of files on vfat takes minutes).

DIR="${TIMELAPSE_DIR:-/mnt/sdcard/timelapse}"
CSV=.timelapse_videos.csv
DRY=0
case "$1" in
  -n) DRY=1 ;;
  "") ;;
  *) echo "usage: $0 [-n]" >&2; exit 2 ;;
esac

# On low memory the OOM killer should pick this script, not lp_app.
echo 1000 > /proc/self/oom_score_adj 2>/dev/null

log() { echo "timelapse-clean: $*"; }
cd "$DIR" 2>/dev/null || { log "no $DIR, nothing to do"; exit 0; }
[ "$DRY" = 0 ] || log "dry run, nothing is deleted"

# Jobs with an open file: first path component below $DIR, without .avi.
busy=$(ls -l /proc/[0-9]*/fd 2>/dev/null | sed -n "s#.* -> $DIR/##p" | sed 's#/.*##; s#\.avi$##' | sort -u)
is_busy() { [ -n "$busy" ] && echo "$busy" | grep -qxF "$1"; }

failed=0
for e in *; do
  [ -e "$e" ] || continue          # empty directory: the glob stays "*"
  job=${e%.avi}
  if is_busy "$job"; then
    log "keeping $e: a print is still writing this timelapse"
    continue
  fi
  if [ -d "$e" ]; then what="photos $e/"; else what="$e ($(ls -l "$e" | awk '{print $5}') bytes)"; fi
  if [ "$DRY" = 1 ]; then
    log "would delete $what"
  elif rm -rf "$e"; then
    log "deleted $what"
  else
    log "FAILED to delete $what"
    failed=1
  fi
done

if [ -f "$CSV" ]; then
  if [ "$DRY" = 1 ]; then
    log "would drop the lines of deleted videos from $CSV"
  else
    while IFS= read -r line; do
      [ -e "${line%:*}" ] && echo "$line"
    done < "$CSV" > "$CSV.new"
    mv "$CSV.new" "$CSV"
    log "$CSV now lists $(grep -c . "$CSV") video(s)"
  fi
fi

sync
exit "$failed"
