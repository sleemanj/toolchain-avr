#!/bin/bash -ex

export PATH=/opt/local/libexec/gnubin/:$PATH

CC="gcc -arch i386" CXX="g++ -arch i386" ./build.all.bash

rm -f avr-toolchain-*.zip
cd objdir
zip -r -9 ../avr-toolchain-mac32-gcc-4.3.2.zip .

