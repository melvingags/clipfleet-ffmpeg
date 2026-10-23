#!/bin/bash
# Builds ffmpeg and ffprobe for Linux on x86-64, from the official sources,
# each checked against its published fingerprint. Run inside Alpine Linux
# (see .github/workflows/linux.yml): every library, the C library included,
# is built in, so the two programs run on any Linux without anything else.
#
# In: captions (libass, with FreeType, FriBidi, HarfBuzz, and fontconfig,
# which reads the computer's own font settings in /etc/fonts), H.264
# encoding (x264), AV1 decoding (dav1d). Out: ./out/ffmpeg, ./out/ffprobe.
set -euo pipefail

FFMPEG_VERSION=9.0.2
FREETYPE_VERSION=2.15.0
FRIBIDI_VERSION=1.0.17
HARFBUZZ_VERSION=14.6.0
LIBASS_VERSION=0.17.5
EXPAT_VERSION=2.9.0
FONTCONFIG_VERSION=2.17.1
DAV1D_VERSION=1.5.4
DAV1D_COMMIT=54706fc6bc0cdecab7e9593974a4039cc038fca7
X264_COMMIT=b35605ace3ddf7c1a5d67a2eb553f034aef41d55

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work"
PREFIX="$WORK/prefix"
SRC="$WORK/src"
OUT="$ROOT/out"
rm -rf "$WORK" "$OUT"
mkdir -p "$PREFIX" "$SRC" "$OUT" "$ROOT/sources"

export CFLAGS="-O2"
export CXXFLAGS="$CFLAGS"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
JOBS="$(nproc)"
MESON=(meson setup build --prefix="$PREFIX" --libdir=lib --default-library=static --buildtype=release --wrap-mode=nodownload)

# fetch <url> <sha256>: download, check the fingerprint, keep a copy, unpack
fetch() {
  local file="$ROOT/sources/$(basename "$1")"
  curl -fsSL --retry 3 -o "$file" "$1"
  echo "$2  $file" | sha256sum -c -
  tar -xf "$file" -C "$SRC"
}

# clone <url> <ref> <commit> <name>: a git source, checked by its commit
clone() {
  git clone --quiet --branch "$2" "$1" "$SRC/$4"
  git -C "$SRC/$4" checkout --quiet "$3"
  test "$(git -C "$SRC/$4" rev-parse HEAD)" = "$3"
  git -C "$SRC/$4" archive --format=tar.gz --prefix="$4/" -o "$ROOT/sources/$4.tar.gz" HEAD
}

fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
fetch "https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz" 93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5
fetch "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz" 6949dcde27d41cebad1fd741fcafc36d55a1020d2d872d4a6eb3914caabbada2
fetch "https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz" d07a007327277708a2a73ae437887cdbaf282937f6d03ca5467723e9099af586
fetch "https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.xz" 2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc
fetch "https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_VERSION//./_}/expat-$EXPAT_VERSION.tar.xz" 1e6371862cc31999b368c3b89b49994f0677e1bab5f1b2b85ae3741f5d803051
# fontconfig's own site turns away downloads by script; Debian's copy of the
# same release is used, checked against Debian's signed record of it.
fetch "https://deb.debian.org/debian/pool/main/f/fontconfig/fontconfig_$FONTCONFIG_VERSION.orig.tar.gz" f07504cef87f171ee1748352e2df9b9f125352f620fa0d03a9284306ea2c40a4
clone https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" "$DAV1D_COMMIT" "dav1d-$DAV1D_VERSION"
clone https://code.videolan.org/videolan/x264.git stable "$X264_COMMIT" x264

cd "$SRC/x264"
./configure --prefix="$PREFIX" --enable-static --enable-pic --disable-cli --disable-opencl \
  --disable-avs --disable-swscale --disable-lavf --disable-ffms --disable-gpac --disable-lsmash
make -j"$JOBS"
make install-lib-static

cd "$SRC/dav1d-$DAV1D_VERSION"
"${MESON[@]}" -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false
ninja -C build install

cd "$SRC/expat-$EXPAT_VERSION"
./configure --prefix="$PREFIX" --enable-static --disable-shared \
  --without-docbook --without-examples --without-tests --without-xmlwf
make -j"$JOBS"
make install

cd "$SRC/freetype-$FREETYPE_VERSION"
"${MESON[@]}" -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled
ninja -C build install

# The computer's own font settings and cache, where every Linux keeps them.
cd "$SRC"/fontconfig-"$FONTCONFIG_VERSION"*
"${MESON[@]}" -Ddoc=disabled -Dnls=disabled -Dtests=disabled -Dtools=disabled -Dcache-build=disabled \
  -Dxml-backend=expat -Dbaseconfig-dir=/etc/fonts -Dconfig-dir=/etc/fonts/conf.d \
  -Dcache-dir=/var/cache/fontconfig
ninja -C build install

cd "$SRC/fribidi-$FRIBIDI_VERSION"
"${MESON[@]}" -Ddocs=false -Dbin=false -Dtests=false
ninja -C build install

cd "$SRC/harfbuzz-$HARFBUZZ_VERSION"
"${MESON[@]}" -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
  -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dcoretext=disabled -Draster=disabled -Dvector=disabled \
  -Dgpu=disabled -Dgpu_demo=disabled -Dsubset=disabled -Dtests=disabled -Dintrospection=disabled \
  -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled
ninja -C build install

cd "$SRC/libass-$LIBASS_VERSION"
"${MESON[@]}" -Dfontconfig=enabled -Dcoretext=disabled -Ddirectwrite=disabled -Dlibunibreak=disabled \
  -Drequire-system-font-provider=true -Dtest=disabled -Dcompare=disabled -Dprofile=disabled \
  -Dfuzz=disabled -Dcheckasm=disabled
ninja -C build install

cd "$SRC/ffmpeg-$FFMPEG_VERSION"
./configure --prefix="$PREFIX" \
  --pkg-config-flags=--static \
  --extra-cflags="-I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib -static" \
  --extra-libs="-lstdc++ -lm" \
  --enable-gpl \
  --disable-autodetect \
  --enable-pthreads \
  --enable-zlib --enable-bzlib --enable-iconv \
  --enable-libx264 --enable-libdav1d --enable-libass \
  --disable-ffplay --disable-doc --disable-debug
# what the app relies on, or stop here: every core, captions, PNG pictures, H.264
for want in HAVE_PTHREADS CONFIG_LIBASS CONFIG_ZLIB CONFIG_LIBX264 CONFIG_LIBDAV1D; do
  grep -q "#define $want 1" config.h || { echo "ffmpeg was configured without $want"; exit 1; }
done
make -j"$JOBS"
cp ffmpeg ffprobe "$OUT/"

"$OUT/ffmpeg" -hide_banner -version | head -n 1
