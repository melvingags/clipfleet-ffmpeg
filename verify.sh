#!/bin/bash
# verify.sh <folder with ffmpeg and ffprobe>: checks that they run on this
# Mac or Linux computer, need nothing it does not have, and do everything
# Clipfleet asks of them — captions in the system's font from a fonts folder,
# a picture on top, H.264 and AAC out.
set -euo pipefail
BIN="$(cd "$1" && pwd)"
FF="$BIN/ffmpeg"
FP="$BIN/ffprobe"

if [ "$(uname)" = Darwin ]; then
  echo "macOS $(sw_vers -productVersion), $(uname -m)"
  for b in "$FF" "$FP"; do
    lipo -archs "$b" | grep -qx arm64
    bad="$(otool -L "$b" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' || true)"
    [ -z "$bad" ] || { echo "$(basename "$b") needs files a Mac does not have: $bad"; exit 1; }
    otool -l "$b" | grep -A4 LC_BUILD_VERSION | grep -q "minos 14.0" || { echo "$(basename "$b") is not for macOS 14"; exit 1; }
  done
  FONT="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
  FAMILY="Arial"
  FACE="Arial-Bold"
  OWN="encoder=h264_videotoolbox"
else
  . /etc/os-release
  echo "$PRETTY_NAME, $(uname -m)"
  for b in "$FF" "$FP"; do
    file "$b" | grep -qE "x86-64.*(statically|static-pie) linked" || { echo "$(basename "$b") is not one self-contained x86-64 program: $(file "$b")"; exit 1; }
  done
  FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
  FAMILY="DejaVu Sans"
  FACE="DejaVuSans-Bold"
  OWN=""
fi
conf="$("$FF" -hide_banner -buildconf)"
[[ "$conf" == *--enable-pthreads* ]] || { echo "ffmpeg was built without threads"; exit 1; }

for need in filter=ass filter=subtitles filter=overlay filter=boxblur filter=silencedetect filter=volumedetect \
  encoder=libx264 $OWN encoder=aac encoder=png encoder=pcm_s16le \
  decoder=h264 decoder=hevc decoder=vp9 decoder=libdav1d decoder=aac decoder=opus decoder=png \
  demuxer=hls muxer=hls demuxer=concat muxer=mp4 muxer=segment; do
  # The first line names it ("Filter overlay", "Encoder libx264 [...]") or says it is unknown.
  name="${need#*=}"
  first="$("$FF" -hide_banner -h "$need" 2>&1 | head -n 1 || true)"
  case "$first" in
    "Filter $name" | "Encoder $name "* | "Decoder $name "* | "Demuxer $name "* | "Muxer $name "*) ;;
    *) echo "missing: $need ($first)"; exit 1 ;;
  esac
done

# A folder with a space in its name, as the Mac's "Application Support" has.
T="$(mktemp -d)/check folder"
mkdir -p "$T/fonts"
cd "$T"
cp "$FONT" fonts/
printf '%s\n' "[Script Info]" "ScriptType: v4.00+" "PlayResX: 1280" "PlayResY: 720" "" \
  "[V4+ Styles]" "Format: Name, Fontname, Fontsize, PrimaryColour, Bold" "Style: Default,$FAMILY,64,&H00FFFFFF,-1" "" \
  "[Events]" "Format: Layer, Start, End, Style, Text" "Dialogue: 0,0:00:00.00,0:00:03.00,Default,Caption check" > subs.ass
"$FF" -hide_banner -loglevel error -f lavfi -i "color=c=red:s=64x64:d=1" -frames:v 1 badge.png
"$FF" -hide_banner -loglevel verbose -y \
  -f lavfi -i "testsrc2=s=1280x720:r=30:d=3" -f lavfi -i "sine=f=440:d=3" -i badge.png \
  -filter_complex "[0:v]ass=subs.ass:fontsdir='$T/fonts'[c];[c][2:v]overlay=10:10[v]" \
  -map "[v]" -map 1:a -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -shortest out.mp4 2> log.txt
grep -o "fontselect:.*" log.txt || true
grep -qE "fontselect: \($FAMILY, 700, 0\) -> .*$FACE" log.txt || { echo "the captions did not get the font from the folder"; exit 1; }
if grep -i "fontconfig error" log.txt; then echo "fontconfig could not read this computer's font settings"; exit 1; fi
if [ "$(uname)" != Darwin ]; then
  # ...and a font only the computer has (fonts-liberation), found through its own settings
  sed "s/Default,$FAMILY,/Default,Liberation Sans,/" subs.ass > system.ass
  "$FF" -hide_banner -loglevel verbose -f lavfi -i "color=s=320x240:d=0.5" -vf "ass=system.ass" -f null - 2> system.txt
  grep -o "fontselect:.*" system.txt || true
  grep -qE "fontselect: \(Liberation Sans, 700, 0\) -> .*LiberationSans-Bold" system.txt || { echo "fontconfig did not find the computer's own fonts"; exit 1; }
fi
streams="$("$FP" -v error -show_entries stream=codec_name -of csv=p=0 out.mp4 | sort | tr '\n' ' ')"
[ "$streams" = "aac h264 " ] || { echo "unexpected streams: $streams"; exit 1; }
echo "verify: all good"
