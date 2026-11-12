#!/usr/bin/env bash
# Builds site/assets/demo.mp4: a crossfading tour of the app screenshots.
# Usage: tool/make_demo_video.sh <screens-dir> <out.mp4>
set -euo pipefail
DIR="$1"; OUT="$2"
ORDER=(home mushaf_sepia mushaf_night quran_index prayers adhkar reminders settings home_dark)
HOLD=2.6; FADE=0.6
inputs=(); names=()
for n in "${ORDER[@]}"; do
  f="$DIR/$n.png"
  [ -f "$f" ] && { inputs+=(-loop 1 -t $(echo "$HOLD + $FADE" | bc) -i "$f"); names+=("$n"); }
done
count=${#names[@]}
[ "$count" -ge 2 ] || { echo "need at least 2 screenshots"; exit 1; }
filter=""
for i in $(seq 0 $((count-1))); do
  filter+="[$i:v]scale=720:-2,setsar=1,fps=30,format=yuv420p[v$i];"
done
prev="v0"; offset=0
for i in $(seq 1 $((count-1))); do
  offset=$(echo "$offset + $HOLD" | bc)
  filter+="[$prev][v$i]xfade=transition=slideleft:duration=$FADE:offset=$offset[x$i];"
  prev="x$i"
done
filter="${filter%;}"
ffmpeg -y "${inputs[@]}" -filter_complex "$filter" -map "[$prev]" \
  -c:v libx264 -preset veryfast -crf 26 -movflags +faststart -an "$OUT"
