#! /bin/bash

set -euo pipefail

function fjenv_banner() {
    local header=$1; shift
    echo "### $header at $(date), ${0##*/} $*"
}

function fjenv_safe_exit() {
    local status=${1:-1}
    [ $status -ne 0 ] && exit $status
    trap - EXIT
    fjenv_banner "End"
    exit $status
}

fjenv_banner "Start" $*
trap 'fjenv_banner "Abend!!" $*' EXIT

for arg in $@; do
    case $arg in
    clean)      fjenv_clean=true;;
    debug)      fjenv_debug=true;;
    download)   fjenv_download=true;;
    help)       fjenv_show_usage=true;;
    rebuild)    fjenv_rebuild=true;;
    *)          echo "Unknown command: $arg"; fjenv_show_usage=true;;
    esac
done

if [ -v fjenv_show_usage ]; then
    echo "Usage: $0 [clean|debug|download|rebuild]"
    fjenv_safe_exit 1
fi

script_basedir=$(cd $(dirname $0); pwd)
source $script_basedir/env.src

if [ -v fjenv_debug ]; then set -x; fi

#
# Clean up
#

BATCHED_BLAS_VER=1.0

if [ -v fjenv_clean ]; then
    rm -rf BatchedBLAS-${BATCHED_BLAS_VER}.tar.gz BatchedBLAS-${BATCHED_BLAS_VER}
    fjenv_safe_exit 0
fi

#
# Download BatchedBlas
#

mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

if [ ! -f BatchedBLAS-${BATCHED_BLAS_VER}.tar.gz ]; then
    wget ${WGET_OPTIONS} https://www.r-ccs.riken.jp/labs/lpnctrt/projects/batchedblas/BatchedBLAS-1.0.tar.gz
fi

if [ -v fjenv_download ]; then fjenv_safe_exit 0; fi

#
# Unpack the archive
#

# To make this script idempotent, always rebuild
#if [ -v fjenv_rebuild ]; then
    rm -rf BatchedBLAS-${BATCHED_BLAS_VER}
#fi

if [ ! -d BatchedBLAS-${BATCHED_BLAS_VER} ]; then
    tar xfpz BatchedBLAS-${BATCHED_BLAS_VER}.tar.gz
fi

#
# Build BatchedBlas
#

cd ${TENSORFLOW_TOP}

# To make this script idempotent, always rebuild
if [ -v fjenv_rebuild ]; then
   git checkout -- tensorflow/workspace2.bzl
fi

sed -i "/INSTALL_PATH/s!/INSTALL_PATH/!${DOWNLOAD_PATH}/BatchedBLAS-1.0/!" tensorflow/workspace2.bzl

cd ${DOWNLOAD_PATH}/BatchedBLAS-${BATCHED_BLAS_VER}

# Preperation to make use of older version.
sed -ie "/shutil\.copy/s!'./!'include/!;/constants\.c/d" old/batched_blas.py
python3 old/batched_blas.py data/batched_blas_data.csv

cd batched_blas_src

# Small correction of auto-generated files by old/batched_blas.py
sed -i '16d' batched_blas_common.h
sed -i '1,2d' Makefile
sed -i "1i CC=$CC" Makefile
sed -i "2i CCFLAG=-Kopenmp -O3 -D_CBLAS_ -I./" Makefile
sed -i "3i CCFLAG+=-I${TCSDS_PATH}/include" Makefile

make -j ${MAX_JOBS}

fjenv_safe_exit 0
