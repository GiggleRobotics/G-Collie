#!/bin/sh
# Build in an empty directory with the original upstream archive alongside this script.
# Ubuntu 20.04 amd64; no additional system packages installed by this script.
set -eu
src=ffmpeg-7.0.2
archive="$src.tar.xz"
printf '%s\n' 'Source: https://ffmpeg.org/releases/ffmpeg-7.0.2.tar.xz'
printf '%s  %s\n' '8646515b638a3ad303e23af6a3587734447cb8fc0a0c064ecdb8e95c4fd8b389' "$archive" | sha256sum -c -
tar -xf "$archive"
cd "$src"
./configure --disable-autodetect --disable-network --disable-doc --disable-debug --disable-ffplay --disable-ffprobe --disable-x86asm --disable-shared --enable-static --enable-zlib
make -j4
cp ffmpeg ../ffmpeg
cp COPYING.LGPLv2.1 ../COPYING.LGPLv2.1
