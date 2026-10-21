# ffmpeg for Apple-chip Macs

`ffmpeg` and `ffprobe` for Apple-chip Macs (macOS 14 or later), built for Clipfleet's Mac app.

- `build.sh` builds them from the official sources, each checked against its published fingerprint, with every library built in: captions (libass, FreeType, FriBidi, HarfBuzz, fonts through Core Text), H.264 (x264), AV1 decoding (dav1d), and Apple's VideoToolbox and AudioToolbox.
- `verify.sh` checks the result on a Mac: nothing needed beyond macOS itself, every feature present, and a captioned test video made with a font from a fonts folder.
- Each release holds the two programs, their fingerprints (`SHA256SUMS`) and the exact sources they were built from.

License: GPL v2 or later, as x264 is built in.
