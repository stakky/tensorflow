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

DATA_DIR=dataset
OPENNMT_DIR=opennmt-tf

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $script_basedir/$OPENNMT_DIR			\
	$DOWNLOAD_PATH/addons				\
	$DOWNLOAD_PATH/$PIP_PACKAGE_PATH
	# Keep the training data because it is costly to download.
	#$script_basedir/$DATA_DIR
    fjenv_safe_exit 0
fi

#
# Download models
# Model and data reside in the current directory,
# while other modules are stored uner $DOWNLOAD_PATH.
#

cd $script_basedir

# Basically v2.23.0 or higher is needed for TensorFlow 2.7
# But in order to compare the result with the previous release,
# use same version, by tweeking version constraints of the related modules.

if [ ! -d $OPENNMT_DIR ]; then
    git clone $GIT_OPTIONS \
    	-b v2.11.0 \
	--depth 1 \
	http://github.com/OpenNMT/OpenNMT-tf $OPENNMT_DIR
    (cd $OPENNMT_DIR; patch -p1 < $script_basedir/OpenNMT.patch)
    cat <<EOF>$OPENNMT_DIR/setup.cfg
[easy_install]
find_links = $PIP_PACKAGE_PATH
EOF
fi

[ -d $DATA_DIR ] || mkdir -p $DATA_DIR
cd $DATA_DIR
if [ ! -f wmt_ende_sp.tar.gz ]; then
    #wget $WGET_OPTIONS https://s3.amazonaws.com/opennmt-trainingdata/toy-ende.tar.gz
    wget $WGET_OPTIONS https://s3.amazonaws.com/opennmt-trainingdata/wmt_ende_sp.tar.gz
    tar xfpz wmt_ende_sp.tar.gz
fi

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

if [ ! -d addons ]; then
    git clone $GIT_OPTIONS  \
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

# Use same CC and CXX in Python build
unset CC CXX

## tensorflow-addons

cd $DOWNLOAD_PATH/addons
python3 ./configure.py

export JAVA_HOME=${PREFIX}/java
CONFIG="--enable_runfiles"
bazel $CONFIG_BAZEL_STARTUP build ${CONFIG} ${CONFIG_BAZEL} build_pip_pkg
bazel-bin/build_pip_pkg artifacts
pip3 install ${PIP3_OPTIONS} artifacts/tensorflow_addons-*.whl

## pyonmttok

pip3 install $PIP3_OPTIONS pyonmttok

#
# build OpenNMT-tf
#

cd $script_basedir/$OPENNMT_DIR

python3 setup.py install

# make train dataset

cd $script_basedir/$DATA_DIR

#if [ ! -f toy-ende/src-train.txt -o ! -f toy-ende/tgt-train.txt ]; then
#    tar xf toy-ende.tar.gz
#fi
#cd toy-ende
#onmt-build-vocab --size 50000 --save_vocab src-vocab.txt src-train.txt
#onmt-build-vocab --size 50000 --save_vocab tgt-vocab.txt tgt-train.txt

#onmt-build-vocab --from_format sentencepiece --from_vocab wmt$sl$tl.vocab --save_vocab data/wmt$sl$tl.vocab

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
