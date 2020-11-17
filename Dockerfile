# Copyright 2020 Coinbase, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build LBRYCrdd
FROM ubuntu:18.04 as lbrycrdd-builder
ENV LANG C.UTF-8

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

# Source: https://github.com/lbryio/lbrycrd/blob/v19_master/packaging/docker-for-gcc/Dockerfile
RUN set -xe; \
    apt-get update; \
    apt-get install --no-install-recommends -y build-essential libtool autotools-dev automake pkg-config git wget apt-utils \
        librsvg2-bin libtiff-tools cmake imagemagick libcap-dev libz-dev libbz2-dev python-setuptools python3-setuptools xz-utils ccache g++-multilib \
        g++-mingw-w64-i686 mingw-w64-i686-dev bsdmainutils curl ca-certificates g++-mingw-w64-x86-64 mingw-w64-x86-64-dev \
        clang-8 lldb-8 lld-8 libc++-8-dev libboost-all-dev libcurl4-openssl-dev libssl-devlibdb++-dev libevent-dev \
        libssl-dev libtool pkg-config python python-pip libzmq3-dev; \
    rm -rf /var/lib/apt/lists/*;

RUN update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang-cpp-8 80; \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-8 80; \
    update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++ 80; \
    update-alternatives --install /usr/bin/cc cc /usr/bin/clang 80; \
    update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix; \
    update-alternatives --set i686-w64-mingw32-g++ /usr/bin/i686-w64-mingw32-g++-posix; \
    /usr/sbin/update-ccache-symlinks; \
    cd /usr/include/c++ && ln -s /usr/lib/llvm-8/include/c++/v1; \
    cd /usr/lib/llvm-8/lib && ln -s libc++abi.so.1 libc++abi.so;

# VERSION: LBRYcrd 0.17.4.6
RUN git clone https://github.com/lbryio/lbrycrd \
  && cd lbrycrd \
  && git checkout v17_master

RUN cd lbrycrd \
  && ./autogen.sh \
  && ./configure --enable-glibc-back-compat --disable-tests --without-miniupnpc --without-gui --with-incompatible-bdb --disable-hardening --disable-zmq --disable-bench --disable-wallet \
  && make

RUN mv lbrycrd/src/lbrycrdd /app/lbrycrdd \
  && rm -rf lbrycrd

# Build Rosetta Server Components
FROM ubuntu:18.04 as rosetta-builder

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

RUN apt-get update && apt-get install -y curl make gcc g++
ENV GOLANG_VERSION 1.15.5
ENV GOLANG_DOWNLOAD_SHA256 9a58494e8da722c3aef248c9227b0e9c528c7318309827780f16220998180a0d
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz

RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
  && echo "$GOLANG_DOWNLOAD_SHA256  golang.tar.gz" | sha256sum -c - \
  && tar -C /usr/local -xzf golang.tar.gz \
  && rm golang.tar.gz

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

# Use native remote build context to build in any directory
COPY . src
RUN cd src \
  && go build \
  && cd .. \
  && mv src/rosetta-lbry /app/rosetta-lbry \
  && mv src/assets/* /app \
  && rm -rf src

## Build Final Image
FROM ubuntu:18.04

RUN apt-get update && \
  apt-get install --no-install-recommends -y libevent-dev libboost-system-dev libboost-filesystem-dev libboost-test-dev libboost-thread-dev && \
  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app \
  && mkdir -p /data \
  && chown -R nobody:nogroup /data

WORKDIR /app

# Copy binary from lbrycrdd-builder
COPY --from=lbrycrdd-builder /app/lbrycrdd /app/lbrycrdd

# Copy binary from rosetta-builder
COPY --from=rosetta-builder /app/* /app/

# Set permissions for everything added to /app
RUN chmod -R 755 /app/*

CMD ["/app/rosetta-lbry"]
