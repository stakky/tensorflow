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

NUMPY_VER=maintenance/1.22.x
NUMPY_DIR=numpy
SCIPY_VER=maintenance/1.7.x
SCIPY_DIR=scipy

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $DOWNLOAD_PATH/$NUMPY_DIR $DOWNLOAD_PATH/$SCIPY_DIR
    rm -rf $PIP_PACKAGE_PATH
    fjenv_safe_exit 0
fi

#
# Download
#

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

[ -d $NUMPY_DIR ] ||
    git clone ${GIT_OPTIONS} \
	-b $NUMPY_VER \
    	--depth 100 \
	https://github.com/numpy/numpy.git $NUMPY_DIR

[ -d $SCIPY_DIR ] ||
    git clone ${GIT_OPTIONS} --recursive \
	-b $SCIPY_VER \
    	--depth 100 \
	https://github.com/scipy/scipy.git $SCIPY_DIR

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Switch to VENV
#

if [ "${fjenv_use_venv}" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

#
# Build NumPy
#

# Support of Fujitsu compiler has been partially integrated with the following commits.
#	4950fd10e (2020-12-03)
#	2ae7aeb3a (2021-8-19)
# If you're trying older version of numpy, then probably you need to cherry pick the relevant part from above.

# NumPy maintenance/1.22.x requires Cythone >= 0.29.21
pip3 install ${PIP3_OPTIONS} 'Cython>=0.29.21' ||
    pip3 install ${PIP3_OPTIONS} $PIP_PACKAGE_PATH/Cython*.whl

cd $DOWNLOAD_PATH/$NUMPY_DIR

if [ -v fjenv_rebuild ]; then
    [ -d build ] && rm -r build
    [ -f site.cfg ] && rm site.cfg
fi

if [ "$fjenv_use_fcc" = "true" -a ! -f site.cfg ]; then
    cat <<EOF>site.cfg
[openblas]
libraries = fjlapackexsve
library_dirs = $TCSDS_PATH/lib64
include_dirs = $TCSDS_PATH/include
extra_link_args = -SSL2BLAMP

[lapack]
lapack_libs = fjlapackexsve
library_dirs = $TCSDS_PATH/lib64
extra_link_args = -SSL2BLAMP
EOF
fi

NPY_NUM_BUILD_JOBS=$MAX_JOBS	\
    python3 setup.py install

#
# Build SciPy
#

# SciPy maintenance/1.7.x requires Cythone >= 0.29.18, which is obviously 
# older than what NumPy is requiring, but running for reference purpose,
# such as in case of using older NumPy.

pip3 install ${PIP3_OPTIONS} 'Cython>=0.29.18'
pip3 install ${PIP3_OPTIONS} pybind11 pythran

cd $DOWNLOAD_PATH/$SCIPY_DIR

if [ -v fjenv_rebuild ]; then
    [ -d build ] && rm -r build
fi

SCIPY_NUM_CYTHONIZE_JOBS=$MAX_JOBS	\
    python3 setup.py build --fcompiler=fujitsu install

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
