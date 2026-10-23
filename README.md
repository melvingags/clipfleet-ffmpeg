# ffmpeg for Clipfleet

`ffmpeg` and `ffprobe` for Clipfleet's Mac and Linux apps, built from the official sources, each checked against its published fingerprint, with every library built in: captions (libass, FreeType, FriBidi, HarfBuzz), H.264 (x264) and AV1 decoding (dav1d).

- **Apple-chip Macs, macOS 14 or later**: `build.sh` (fonts through Core Text, plus Apple's VideoToolbox and AudioToolbox). Releases `v…`.
- **Linux on x86-64**: `build-linux.sh`, run in Alpine Linux so each program is self-contained, the C library included (fonts through fontconfig, reading the computer's own /etc/fonts). Releases `linux-v…`.
- `verify.sh` checks the result on the computer it runs on: nothing needed beyond the system itself, every feature present, and a captioned test video made with a font from a fonts folder.
- Each release holds the two programs, their fingerprints (`SHA256SUMS`) and the exact sources they were built from.

License: GPL v2 or later, as x264 is built in.
