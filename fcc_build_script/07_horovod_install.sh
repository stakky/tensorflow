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

HOROVOD_VER=v0.23.0
HOROVOD_DIR=horovod

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $DOWNLOAD_PATH/$HOROVOD_DIR
    rm -rf $PIP_PACKAGE_PATH
    fjenv_safe_exit 0
fi

# Download

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

if [ ! -d horovod ]; then
    git clone ${GIT_OPTIONS} --recursive \
        -b $HOROVOD_VER \
	--depth 1 \
    	https://github.com/horovod/horovod.git
    #(cd horovod; patch -p 1 < $script_basedir/horovod.patch)
    #cp -p horovod/examples/pytorch/pytorch_synthetic_benchmark.py $script_basedir
    #git clone --recursive -b fujitsu_v0.20.3_for_a64fx \
    #	--shallow-since "2020-01-01" \
    #	https://github.com/fujitsu/horovod.git
fi

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Switch to VENV
#

if [ "${fjenv_use_venv}" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

#
# Build and Install Horovod
#

if [ "${fjenv_use_fcc}" != "true" ]; then
    echo "$0 works for FCC only for now"
    exit 1
fi

# Install required packges
#
# Pytorch requires cffi and tries to install along with horovod installation.
# But we don't know how to tell PIP_PACKAGE_PATH to the dependency installation process in setup.py,
# so install all required packages in 'extras_require' prior to the horovod setup.
# Note: the required packages may varies on HOROVOD_WITH* in below.

pip3 install $PIP3_OPTIONS cffi pycparser cloudpickle
pip3 install $PIP3_OPTIONS pyyaml psutil

export HOROVOD_WITHOUT_MXNET=1
export HOROVOD_WITHOUT_GLOO=1
export HOROVOD_WITH_MPI=1
export HOROVOD_WITHOZUT_PYTORCH=1
export HOROVOD_WITH_TENSORFLOW=1

CC="mpi$CC -DEIGEN_DONT_VECTORIZE"
CXX="mpi$CXX -DEIGEN_DONT_VECTORIZE"

cd ${DOWNLOAD_PATH}/horovod
if [ -v fjenv_rebuild ]; then
    python3 setup.py clean
fi

# TODO: -j doesn't work. Find other ways.
python3 setup.py build -j $MAX_JOBS install

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
