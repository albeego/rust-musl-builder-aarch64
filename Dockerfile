# Use Ubuntu 18.04 LTS as our base image.
FROM ubuntu:18.04

# The Rust toolchain to use when building our image.  Set by `hooks/build`.
ARG TOOLCHAIN=stable

# The OpenSSL version to use. We parameterize this because many Rust
# projects will fail to build with 1.1.
ARG OPENSSL_VERSION=1_0_2r

# Make sure we have basic dev tools for building C libraries.  Our goal
# here is to support the musl-libc builds and Cargo builds needed for a
# large selection of the most popular crates.
#
# We also set up a `rust` user by default, in whose account we'll install
# the Rust toolchain.  This user has sudo privileges if you need to install
# any more software.
#
# `mdbook` is the standard Rust tool for making searchable HTML manuals.
RUN apt-get update
RUN apt-get install -y \
		sudo \
		curl \
        build-essential \
        libssl-dev \
        linux-libc-dev \
        gcc-aarch64-linux-gnu \
        software-properties-common \
        crossbuild-essential-arm64

RUN useradd rust --user-group --create-home --shell /bin/bash --groups sudo

# Allow sudo without a password.
ADD sudoers /etc/sudoers.d/nopasswd

ENV RUSTUP_HOME=/usr/local/rustup \
        CARGO_HOME=/usr/local/cargo \
        PATH=/usr/local/cargo/bin:$PATH
RUN mkdir -p /usr/local/cargo/bin

# Set up our path with all our binary directories, including those for the
# musl-gcc toolchain and for our Rust toolchain.
ENV PATH=/usr/local/cargo/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install our Rust toolchain and the `musl` target.  We patch the
# command-line we pass to the installer so that it won't attempt to
# interact with the user or fool around with TTYs.  We also set the default
# `--target` to musl so that our users don't need to keep overriding it
# manually.
RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- -y --default-toolchain $TOOLCHAIN && \
    rustup target add aarch64-unknown-linux-gnu
ADD cargo-config.toml /usr/local/.cargo/config

RUN mkdir /build

RUN echo "Building OpenSSL" && \
    cd /build && \
    curl -LO "https://github.com/openssl/openssl/archive/OpenSSL_$OPENSSL_VERSION.tar.gz" && \
    tar xvzf "OpenSSL_$OPENSSL_VERSION.tar.gz" && cd "openssl-OpenSSL_$OPENSSL_VERSION" && \
    env ./Configure no-shared no-zlib -fPIC \
    --prefix=/build/openssl-OpenSSL_$OPENSSL_VERSION/target \
    --cross-compile-prefix=aarch64-linux-gnu- \
    linux-aarch64 && \
    make depend && \
    make && \
    sudo make install

RUN echo "Building zlib" && \
    cd /build && \
    ZLIB_VERSION=1.2.11 && \
    curl -LO "http://zlib.net/zlib-$ZLIB_VERSION.tar.gz" && \
    tar xzf "zlib-$ZLIB_VERSION.tar.gz" && cd "zlib-$ZLIB_VERSION" && \
    CC=aarch64-linux-gnu-gcc ./configure --static && \
    make && sudo make install

ENV OPENSSL_DIR=/build/openssl-OpenSSL_$OPENSSL_VERSION/target \
    PKG_CONFIG_ALLOW_CROSS=true \
    LIBZ_SYS_STATIC=1 \
    CC="aarch64-linux-gnu-gcc -static -Os"

WORKDIR /home/rust/src