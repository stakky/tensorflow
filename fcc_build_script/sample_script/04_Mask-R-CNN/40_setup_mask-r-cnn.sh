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
source $script_basedir/../../env.src

if [ -v fjenv_debug ]; then set -x; fi

JPEG_ARCHIVE_NAME=jpegsrc.v9d
JPEG_DIR=jpeg-9d
PILLOW_VER=7.2.0
PILLOW_DIR=Pillow
MASK_RCNN_DIR=MaskRCNN

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $DOWNLOAD_PATH/protobuf.zip		\
	$DOWNLOAD_PATH/$JPEG_ARCHIVE_NAME.tar.gz \
	$DOWNLOAD_PATH/$JPEG_DIR		\
	$DOWNLOAD_PATH/$PILLOW_DIR		\
	$DOWNLOAD_PATH/opencv			\
	$script_basedir/$MASK_RCNN_DIR		\
	$DOWNLOAD_PATH/xdg_cache
    fjenv_safe_exit 0;
fi

#
# Download models
# Model and data reside in the current directory,
# while other modules are stored uner $DOWNLOAD_PATH.
#

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

# Protocol Buffer

PROTOC_VER=3.12.4
if [ ! -f protobuf.zip ]; then 
    wget $WGET_OPTIONS -O protobuf.zip https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VER}/protoc-${PROTOC_VER}-linux-aarch_64.zip
fi

# Download jpeg
if [ ! -f $JPEG_ARCHIVE_NAME.tar.gz ]; then
    curl -O http://www.ijg.org/files/jpegsrc.v9d.tar.gz
fi
if [ ! -d $JPEG_DIR ]; then
    tar xfzp ${JPEG_ARCHIVE_NAME}.tar.gz
fi

# Download Pillow
if [ ! -d $PILLOW_DIR ]; then
    git clone ${GIT_OPTIONS} \
	-b $PILLOW_VER \
	--depth 1 \
    	https://github.com/python-pillow/Pillow.git
fi

# OpenCV
if [ ! -d opencv ]; then
    git clone $GIT_OPTIONS \
    	-b 4.5.5 \
    	--depth 1 \
    	https://github.com/opencv/opencv.git
fi

# Mask RCNN

cd $script_basedir

if [ ! -d MaskRCNN ]; then
    git clone $GIT_OPTIONS \
    	https://github.com/tensorflow/models.git $MASK_RCNN_DIR
    cd $MASK_RCNN_DIR
    git checkout $GIT_OPTIONS dc4d11216b738920d
    patch -p1 < ../MASK-R-CNN.patch
    cd ..
fi

# # Matplot is downloading FreeType duling build
# # For offline installation, prefetch it into dedicated cache
# # Matplotlib fetch FreeType from XDG_CACHE_HOME
# if [ "$fjenv_offline_install" = "true" ]; then
#     export XDG_CACHE_HOME=$DOWNLOAD_PATH/xdg_cache
#     # Ver, sha256, and urls are pick up from setupext.py in Matplot Lib
#     ver=2.6.1
#     sha256="0a3c7dfbda6da1e8fce29232e8e96d987ababbbf71ebc8c75659e4132c367014"
#     url="https://downloads.sourceforge.net/project/freetype/freetype2/$ver/freetype-$ver.tar.gz"
#     if [ ! -f "$XDG_CACHE_HOME/matplotlib/$sha256" ]; then
# 	mkdir -p $XDG_CACHE_HOME/matplotlib
# 	wget ${WGET_OPTIONS} $url -O $XDG_CACHE_HOME/matplotlib/$sha256
#     fi
# fi

if [ -v fjenv_download ]; then fjenv_safe_exit 0; fi

#
# Switch to VENV
#

if [ "$fjenv_use_venv" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

#
# Build
#

cd ${DOWNLOAD_PATH}

# Install Protocol Buffer

unzip -n -d $PREFIX -o protobuf.zip
hash -r

#
# Build and Install JPEG
#

cd $JPEG_DIR
if [ ! -f Makefile -o -v fjenv_rebuild ]; then
    configure_args="--enable-shared"
    if [ "${PREFIX}" ]; then
	configure_args="$configure_args --prefix=${PREFIX}"
    fi
    ./configure $configure_args
    make clean
fi

make -j ${MAX_JOBS}
make install

#
# Build and Install Pillow
#

cd ${DOWNLOAD_PATH}/Pillow
export MAX_CONCURRENCY=$MAX_JOBS
export CFLAGS="-I${PREFIX}/include"
export LDFLAGS="-Wl,-rpath,${PREFIX}/lib"
if [ -v fjenv_rebuild ]; then
    python3 setup.py clean
fi
python3 setup.py install

# Install Matplotlib

pip3 install $PIP3_OPTIONS cppy
pip3 install $PIP3_OPTIONS matplotlib

# Install OpenCV

cd $DOWNLOAD_PATH/opencv

mkdir -p build; cd build
cmake .. -DCMAKE_INSTALL_PREFIX=${PREFIX} \
      -DBUILD_opencv_python3=ON \
      -DPYTHON3_PACKAGES_PATH=${VENV_PATH}/lib/python3.9/site-packages \

make -j32
make install

# Other Python modules

pip3 install ${PIP3_OPTIONS} pycocotools dataclasses tf_slim lxml contextlib2
pip3 install ${PIP3_OPTIONS} lvis --no-deps	# -no-deps  is necessary to avoid installing latest opencv, which may require libGL.so

# Mask RCNN

cd $script_basedir

export PYTHONPATH=${PYTHONPATH:-}:$(pwd):$(pwd)/research:$(pwd)/research/slim
(cd $MASK_RCNN_DIR/research; protoc object_detection/protos/*.proto --python_out=.)

# Patch config

config="config/mask_rcnn_resnet50_fpn_coco.config"
cwd=`pwd`
if [ ! -f $config.bk ]; then
    sed -i.bk "/INSTALL_PATH/s!/INSTALL_PATH!$script_basedir!" $config
fi

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
