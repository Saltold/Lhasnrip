#!/bin/bash

sudo apt-get update

sudo apt-get install -y cmake git curl unzip python3 python3-pip libjudy-dev libgmp-dev libpcap-dev flex byacc libjson-c-dev gengetopt libunistring-dev

pip3 install requests

git clone https://github.com/zmap/zmap

cd zmap || { echo "Failed to change directory to zmap"; exit 1; }

cmake .

make -j4

sudo make install

echo "Zmap安装完成."
