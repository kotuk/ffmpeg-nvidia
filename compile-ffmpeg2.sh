#!/bin/sh -e

#This script will compile and install a static ffmpeg build with support for nvenc un ubuntu.
#See the prefix path and compile options if edits are needed to suit your needs.

# Based on:  https://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu
# Based on:  https://gist.github.com/Brainiarc7/3f7695ac2a0905b05c5b
# Based on:  https://github.com/ilyaevseev/ffmpeg-build-static/


# Globals
NASM_VERSION="2.15.05"
YASM_VERSION="1.3.0"
LAME_VERSION="3.100"
OPUS_VERSION="1.2.1"
CUDA_VERSION="10.0.130-1"
CUDA_REPO_KEY="http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub"
CUDA_DIR="/usr/local/cuda"
WORK_DIR="$HOME/ffmpeg-build-static-sources"
DEST_DIR="$HOME/ffmpeg-build-static-binaries"

mkdir -p "$WORK_DIR" "$DEST_DIR" "$DEST_DIR/bin"

export PATH="$DEST_DIR/bin:$PATH"

MYDIR="$(cd "$(dirname "$0")" && pwd)"  #"

####  Routines  ################################################

Wget() { wget -cN "$@"; }

PKGS="autoconf automake libtool patch make cmake bzip2 unzip wget git mercurial"

installAptLibs() {
    sudo apt-get update
    sudo apt-get -y --force-yes install $PKGS \
      build-essential pkg-config texi2html software-properties-common libssl-dev \
      libass-dev libfreetype6-dev libgpac-dev libsdl1.2-dev libtheora-dev libva-dev \
      libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev zlib1g-dev \
      liblilv-0-0 liblilv-dev lilv-utils libdrm-dev libxml2-dev
}

installLibs() {
    echo "Installing prerequisites"
    . /etc/os-release
    case "$ID" in
        ubuntu | linuxmint ) installAptLibs ;;
        * ) echo "ERROR: only Ubuntu are supported now."; exit 1;;
    esac
}

installCUDASDKdeb() {
    UBUNTU_VERSION="$1"
    local CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-repo-ubuntu${UBUNTU_VERSION}_${CUDA_VERSION}_amd64.deb"
    Wget "$CUDA_REPO_URL"
    sudo dpkg -i "$(basename "$CUDA_REPO_URL")"
    sudo apt-key adv --fetch-keys "$CUDA_REPO_KEY"
    sudo apt-get -y update
    sudo apt-get -y install cuda --allow-unauthenticated

    sudo env LC_ALL=C.UTF-8 add-apt-repository -y ppa:graphics-drivers/ppa
    sudo apt-get -y update
    sudo apt-get -y upgrade
}

installCUDASDK() {
    echo "Installing CUDA and the latest driver repositories from repositories"
    cd "$WORK_DIR/"

    . /etc/os-release
    case "$ID-$VERSION_ID" in
        ubuntu-14.04 ) installCUDASDKdeb 1404 ;;
        ubuntu-16.04 ) installCUDASDKdeb 1604 ;;
        ubuntu-18.04 ) installCUDASDKdeb 1804 ;;
        ubuntu-20.04 ) installCUDASDKdeb 2004 ;;
        ubuntu-22.04 ) installCUDASDKdeb 2204 ;;
        linuxmint-19.1)installCUDASDKdeb 1804 ;;
        * ) echo "ERROR: only Ubuntu are supported now."; exit 1;;
    esac
}

installNvidiaSDK() {
    echo "Installing the nVidia NVENC SDK."
    cd "$WORK_DIR/"
    test -d nv-codec-headers || git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    cd nv-codec-headers
    git pull
    make
    make install PREFIX="$DEST_DIR"
    patch --force -d "$DEST_DIR" -p1 < "$MYDIR/dynlink_cuda.h.patch" || :
}

compileNasm() {
    echo "Compiling nasm"
    cd "$WORK_DIR/"
    Wget "http://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.gz"
    tar xzvf "nasm-$NASM_VERSION.tar.gz"
    cd "nasm-$NASM_VERSION"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    make -j$(nproc)
    make install distclean
}

compileYasm() {
    echo "Compiling yasm"
    cd "$WORK_DIR/"
    Wget "http://www.tortall.net/projects/yasm/releases/yasm-$YASM_VERSION.tar.gz"
    tar xzvf "yasm-$YASM_VERSION.tar.gz"
    cd "yasm-$YASM_VERSION/"
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin"
    make -j$(nproc)
    make install distclean
}

compileLibX264() {
    echo "Compiling libx264"
    cd "$WORK_DIR/"
    Wget https://code.videolan.org/videolan/x264/-/archive/master/x264-master.tar.gz
    rm -rf x264-mast*/ || :
    tar xvzf x264-master.tar.gz
    cd x264-mast*
    ./configure --prefix="$DEST_DIR" --bindir="$DEST_DIR/bin" --enable-static --enable-pic
    make -j$(nproc)
    make install distclean
}

compileLibX265() {
    if cd "$WORK_DIR/x265_git/"; then
        git pull
    else
        cd "$WORK_DIR/"
        git clone https://bitbucket.org/multicoreware/x265_git.git
    fi

    cd "$WORK_DIR/x265_git/build/linux/"
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED:bool=off ../../source
    make -j$(nproc)
    make install

    # forward declaration should not be used without struct keyword!
    sed -i.orig -e 's,^ *x265_param\* zoneParam,struct x265_param* zoneParam,' "$DEST_DIR/include/x265.h"
}

compileLibAom() {
    cd "$WORK_DIR/"
    test -d aom/.git || git clone --depth 1 https://aomedia.googlesource.com/aom
    cd aom
    git pull
    mkdir ../aom_build
    cd ../aom_build
    cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEST_DIR" -DENABLE_SHARED=off -DENABLE_NASM=on ../aom
    make -j$(nproc)
    make install
}

compileLibfdkaac() {
    echo "Compiling libfdk-aac"
    cd "$WORK_DIR/"
    Wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
    unzip -o fdk-aac.zip
    cd mstorsjo-fdk-aac*
    autoreconf -fiv
    ./configure --prefix="$DEST_DIR" --disable-shared
    make -j$(nproc)
    make install distclean
}

compileLibMP3Lame() {
    echo "Compiling libmp3lame"
    cd "$WORK_DIR/"
    Wget "http://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
    tar xzvf "lame-$LAME_VERSION.tar.gz"
    cd "lame-$LAME_VERSION"
    ./configure --prefix="$DEST_DIR" --enable-nasm --disable-shared
    make -j$(nproc)
    make install distclean
}

compileLibOpus() {
    echo "Compiling libopus"
    cd "$WORK_DIR/"
    Wget "http://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz"
    tar xzvf "opus-$OPUS_VERSION.tar.gz"
    cd "opus-$OPUS_VERSION"
    #./autogen.sh
    ./configure --prefix="$DEST_DIR" --disable-shared
    make -j$(nproc)
    make install distclean
}

compileLibVpx() {
    echo "Compiling libvpx"
    cd "$WORK_DIR/"
    test -d libvpx || git clone https://chromium.googlesource.com/webm/libvpx
    cd libvpx
    git pull
    ./configure --prefix="$DEST_DIR" --disable-examples --enable-runtime-cpu-detect --enable-vp9 --enable-vp8 \
    --enable-postproc --enable-vp9-postproc --enable-multi-res-encoding --enable-webm-io --enable-better-hw-compatibility \
    --enable-vp9-highbitdepth --enable-onthefly-bitpacking --enable-realtime-only \
    --cpu=native --as=nasm
    make -j$(nproc)
    make install clean
}

compileFfmpeg(){
    echo "Compiling ffmpeg"
    cd "$WORK_DIR/"
    test -d FFmpeg || git clone https://github.com/FFmpeg/FFmpeg -b master
    cd FFmpeg
    git pull

    export PATH="$CUDA_DIR/bin:$PATH"  # ..path to nvcc
    PKG_CONFIG_PATH="$DEST_DIR/lib/pkgconfig" \
    ./configure \
      --pkg-config-flags="--static" \
      --prefix="$DEST_DIR" \
      --bindir="$DEST_DIR/bin" \
      --extra-cflags="-I $DEST_DIR/include -I $CUDA_DIR/include/" \
      --extra-ldflags="-L $DEST_DIR/lib -L $CUDA_DIR/lib64/" \
      --extra-libs="-lpthread" \
      --enable-openssl \
      --enable-cuda-nvcc \
      --enable-cuvid \
      --enable-libnpp \
      --enable-gpl \
      --enable-libass \
      --enable-libfdk-aac \
      --enable-vaapi \
      --enable-libfreetype \
      --enable-libtheora \
      --enable-libvorbis \
      --enable-libvpx \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libmp3lame \
      --enable-libopus \
      --enable-nonfree \
      --enable-libaom \
      --enable-nvenc
    make -j$(nproc)
    make install distclean
    hash -r
}

installLibs
installCUDASDK
installNvidiaSDK

compileNasm
compileYasm
compileLibX264
compileLibX265
compileLibAom
compileLibVpx
compileLibfdkaac
compileLibMP3Lame
compileLibOpus
# TODO: libogg
# TODO: libvorbis
compileFfmpeg

echo "Complete!"

## END ##
