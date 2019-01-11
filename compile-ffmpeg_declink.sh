#!/bin/bash

#This script will compile and install a static ffmpeg build with support for nvenc un ubuntu.
#See the prefix path and compile options if edits are needed to suit your needs.

#install required things from apt
installLibs(){
echo "Installing prerequisites"
sudo apt-get update
sudo apt-get -y --force-yes install autoconf automake build-essential libass-dev \
  libtool pkg-config texinfo zlib1g-dev cmake mercurial libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev \
  libxcb-xfixes0-dev pkg-config texi2html zlib1g-dev libssl-dev
}

#install CUDA SDK
InstallCUDASDK(){
echo "Installing CUDA and the latest driver repositories from repositories"
cd ~/ffmpeg_sources
wget -c -v -nc https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_10.0.130-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu1604_10.0.130-1_amd64.deb
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
sudo apt-get -y update
sudo apt-get -y install cuda --allow-unauthenticated
echo /usr/local/cuda/lib64 >> /etc/ld.so.conf.d/cuda.conf
sudo ldconfig -vvvv
echo CUDA_HOME=/usr/local/cuda >> /etc/environment
echo /usr/local/cuda/bin:$HOME/bin >> /etc/environment
source /etc/environment
}

#Install nvidia SDK
installSDK(){
echo "Installing the nVidia NVENC SDK."
cd ~/ffmpeg_sources
git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
cd nv-codec-headers
make
sudo make install
}

#Compile nasm
compileNasm(){
echo "Compiling nasm"
cd ~/ffmpeg_sources
wget http://www.nasm.us/pub/nasm/releasebuilds/2.14rc0/nasm-2.14rc0.tar.gz
tar xzvf nasm-2.14rc0.tar.gz
cd nasm-2.14rc0
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin"
make -j$(nproc)
make -j$(nproc) install
make -j$(nproc) distclean
}

#Compile libx264
compileLibX264(){
echo "Compiling libx264"
cd ~/ffmpeg_sources
wget http://download.videolan.org/pub/x264/snapshots/last_x264.tar.bz2
tar xjvf last_x264.tar.bz2
cd x264-snapshot*
PATH="$HOME/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/bin" --enable-static
PATH="$HOME/bin:$PATH" make -j$(nproc)
make -j$(nproc) install
make -j$(nproc) distclean
}

#Compile libx265
compileLibX265(){
echo "Compiling libx265"
cd ~/ffmpeg_sources
hg clone https://bitbucket.org/multicoreware/x265
cd ~/ffmpeg_sources/x265/build/linux
PATH="$HOME/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source
make -j$(nproc) VERBOSE=1
make -j$(nproc) install
make -j$(nproc) clean
}

#Compile libfdk-acc
compileLibfdkcc(){
echo "Compiling libfdk-cc"
sudo apt-get install unzip
cd ~/ffmpeg_sources
wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
unzip fdk-aac.zip
cd mstorsjo-fdk-aac*
autoreconf -fiv
./configure --prefix="$HOME/ffmpeg_build" --disable-shared
make -j$(nproc)
make -j$(nproc) install
make -j$(nproc) distclean
}

#Compile ffmpeg
compileFfmpeg(){
echo "Compiling ffmpeg"
cd ~/ffmpeg_sources
git clone https://github.com/FFmpeg/FFmpeg -b master
cd FFmpeg
PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
  --prefix="$HOME/ffmpeg_build" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$HOME/ffmpeg_build/include" \
  --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
  --bindir="$HOME/bin" \
  --enable-openssl \
  --enable-cuda-sdk \
  --enable-cuvid \
  --enable-libnpp \
  --extra-cflags="-I/usr/local/cuda/include/" \
  --extra-ldflags=-L/usr/local/cuda/lib64/ \
  --enable-decklink \
  --extra-cflags=-I/usr/src/Blackmagic-SDK/Linux/include/ \
  --extra-ldflags=-L/usr/src/Blackmagic-SDK/Linux/include/ \
  --enable-gpl \
  --enable-libass \
  --enable-libfdk-aac \
  --enable-libx264 \
  --enable-libx265 \
  --enable-nvenc \
  --extra-libs=-lpthread \
  --enable-nonfree
PATH="$HOME/bin:$PATH" make -j$(nproc) VERBOSE=1
make -j$(nproc) install
make -j$(nproc) distclean
hash -r
}

#The process
cd ~
mkdir ffmpeg_sources
installLibs
InstallCUDASDK
installSDK
compileNasm
compileLibX264
compileLibX265
compileLibfdkcc
compileFfmpeg
echo "Complete!"

