#!/bin/bash
# verify.sh <folder with ffmpeg and ffprobe>: checks that they run on this
# Mac, need nothing macOS does not have, and do everything Clipfleet asks of
# them — captions in a Mac font from a fonts folder, a picture on top, H.264
# and AAC out.
set -euo pipefail
BIN="$(cd "$1" && pwd)"
FF="$BIN/ffmpeg"
FP="$BIN/ffprobe"
echo "macOS $(sw_vers -productVersion), $(uname -m)"

for b in "$FF" "$FP"; do
  lipo -archs "$b" | grep -qx arm64
  bad="$(otool -L "$b" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' || true)"
  [ -z "$bad" ] || { echo "$(basename "$b") needs files a Mac does not have: $bad"; exit 1; }
  otool -l "$b" | grep -A4 LC_BUILD_VERSION | grep -q "minos 14.0" || { echo "$(basename "$b") is not for macOS 14"; exit 1; }
done
"$FF" -hide_banner -buildconf | grep -q -- --enable-pthreads

for need in filter=ass filter=subtitles filter=overlay filter=boxblur filter=silencedetect filter=volumedetect \
  encoder=libx264 encoder=h264_videotoolbox encoder=aac encoder=png encoder=pcm_s16le \
  decoder=h264 decoder=hevc decoder=vp9 decoder=libdav1d decoder=aac decoder=opus decoder=png \
  demuxer=hls muxer=hls demuxer=concat muxer=mp4 muxer=segment; do
  out="$("$FF" -hide_banner -h "$need" 2>&1 || true)"
  if [ -z "$out" ] || echo "$out" | grep -qiE "unknown|not recognized"; then echo "missing: $need"; exit 1; fi
done

# A folder with a space in its name, as the Mac's "Application Support" has.
T="$(mktemp -d)/check folder"
mkdir -p "$T/fonts"
cd "$T"
cp "/System/Library/Fonts/Supplemental/Arial Bold.ttf" fonts/
printf '%s\n' "[Script Info]" "ScriptType: v4.00+" "PlayResX: 1280" "PlayResY: 720" "" \
  "[V4+ Styles]" "Format: Name, Fontname, Fontsize, PrimaryColour, Bold" "Style: Default,Arial,64,&H00FFFFFF,-1" "" \
  "[Events]" "Format: Layer, Start, End, Style, Text" "Dialogue: 0,0:00:00.00,0:00:03.00,Default,Caption check" > subs.ass
"$FF" -hide_banner -loglevel error -f lavfi -i "color=c=red:s=64x64:d=1" -frames:v 1 badge.png
"$FF" -hide_banner -loglevel verbose -y \
  -f lavfi -i "testsrc2=s=1280x720:r=30:d=3" -f lavfi -i "sine=f=440:d=3" -i badge.png \
  -filter_complex "[0:v]ass=subs.ass:fontsdir='$T/fonts'[c];[c][2:v]overlay=10:10[v]" \
  -map "[v]" -map 1:a -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -shortest out.mp4 2> log.txt
grep -o "fontselect:.*" log.txt || true
grep -qE "fontselect: \(Arial, 700, 0\) -> .*Arial-Bold" log.txt || { echo "the captions did not get the font from the folder"; exit 1; }
streams="$("$FP" -v error -show_entries stream=codec_name -of csv=p=0 out.mp4 | sort | tr '\n' ' ')"
[ "$streams" = "aac h264 " ] || { echo "unexpected streams: $streams"; exit 1; }
echo "verify: all good"
