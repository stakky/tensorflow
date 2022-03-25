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

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf \
	$script_basedir/Bert					\
	$DOWNLOAD_PATH/$PIP_PACKAGE_PATH			\
	$DOWNLOAD_PATH/sentencepiece
	# Keep the training data because it is costly to download.
    	#$script_basedir/cased_L-12_H-768_A-12*			\
    	#$script_basedir/sample_text.txt			\
	#$script_basedir/finetuning_glue_data			\
	fjenv_safe_exit 0
fi

#
# Download models
# Model and data reside in the current directory,
# while other modules are stored uner $DOWNLOAD_PATH.
#

if [ ! -d cased_L-12_H-768_A-12 ]; then
    if [ ! -f cased_L-12_H-768_A-12.tar.gz ]; then
	wget ${WGET_OPTIONS} https://storage.googleapis.com/cloud-tpu-checkpoints/bert/keras_bert/cased_L-12_H-768_A-12.tar.gz
    fi
    tar -xpzf cased_L-12_H-768_A-12.tar.gz
fi

if [ ! -d Bert ]; then
    git clone $GIT_OPTIONS \
    	-b v2.7.0 \
	--depth 1 \
    	http://github.com/tensorflow/models Bert
    (cd Bert; patch -p1 < ../Bert.patch)
fi

if [ ! -f sample_text.txt ]; then
    wget ${WGET_OPTIONS} http://raw.githubusercontent.com/google-research/bert/master/sample_text.txt
fi

# if [ ! -d finetuning_glue_data ]; then
#     mkdir finetuning_glue_data
#     pushd finetuning_glue_data
#     wget ${WGET_OPTIONS} http://gist.githubusercontent.com/W4ngatang/60c2bdb54d156a41194446737ce03e2e/raw/1502038877f6a88c225a34450793fbc3ea87eaba/download_glue_data.py
#     patch -u < ../download_glue_data.py.patch
#     python3 download_glue_data.py --tasks MRPC
#     popd
# fi

# Sentencepiece in github.com is downloaded during the
# instalation of sentecepiee for pip3
# (both "sentencepiece" is distinct)
# Download in advance, for offline compilation.

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

if [ "$fjenv_offline_install" = "true" ]; then
    if [ ! -d sentencepiece ]; then
	 git clone $GIT_OPTIONS \
	     -b v0.1.96 \
	     --depth 1 \
	     https://github.com/google/sentencepiece.git
    fi
fi

if [ ! -d addons ]; then
    git clone $GIT_OPTIONS \
    	-b v0.15.0 \
	--depth 1 \
    	http://github.com/tensorflow/addons
fi

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
if [ -d sentencepiece ]; then
     cd sentencepiece
     mkdir -p build
     (cd build;
      cmake .. -DSPM_ENABLE_SHARED=OFF -DCMAKE_INSTALL_PREFIX=$PREFIX;
      make -j ${MAX_JOBS} install)
    export PKG_CONFIG_PATH=$PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}
fi

pip3 install ${PIP3_OPTIONS} sentencepiece
pip3 install ${PIP3_OPTIONS} gin-config
pip3 install ${PIP3_OPTIONS} tensorflow-hub

## tensorflow-addons

unset CC CXX

cd $DOWNLOAD_PATH/addons
python3 ./configure.py

export JAVA_HOME=${PREFIX}/java
CONFIG="--enable_runfiles"
bazel $CONFIG_BAZEL_STARTUP build ${CONFIG} ${CONFIG_BAZEL} build_pip_pkg
bazel-bin/build_pip_pkg artifacts
pip3 install ${PIP3_OPTIONS} artifacts/tensorflow_addons-*.whl

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
