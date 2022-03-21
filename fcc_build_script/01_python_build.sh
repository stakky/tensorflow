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

PYTHON_VER=3.9
PYTHON_DIR=cpython

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $DOWNLOAD_PATH/$PYTHON_DIR
    fjenv_safe_exit 0
fi

#
# Download
#

[ -d ${DOWNLOAD_PATH} ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

[ -d $PYTHON_DIR ] ||
    git clone ${GIT_OPTIONS} -b $PYTHON_VER \
	https://github.com/python/cpython.git $PYTHON_DIR

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Build
#

cd $DOWNLOAD_PATH/$PYTHON_DIR

export ac_cv_opt_olimit_ok=no
export ac_cv_olimit_ok=no
export ac_cv_cflags_warn_all=''

if [ "$fjenv_use_fcc" = "true" ]; then
    export ac_cv_c_compiler_gnu=no
    # -Kfast produces binary that doens't conform to IEEE-754,
    #  which probably causes infite loop in _Py_HashDouble().
    # export OPT="-Kfast"
    export OPT="-O3"
    # TODO: $ORIGIN sometimes parsed as 'RIGIN'.
    # perhaps more backslashs are needed to protect $ORIGIN from parsing in shell.
    # export LDFLAGS="-Wl,-rpath,\$ORIGIN/../lib"
    export LDFLAGS="-Wl,-rpath,${PREFIX}/lib -Wl,-rpath,${TCSDS_PATH}/lib64 -lpthread"
else
    # Ditto.
    #export LDFLAGS="-Wl,-rpath,\$ORIGIN/../lib"
    export LDFLAGS="-Wl,-rpath,${PREFIX}/lib"
fi

if [ ! -f Makefile -o -v fjenv_rebuild ]; then
    configure_args="--enable-shared --disable-ipv6 --target=aarch64 --build=aarch64"
    if [ ! -z "${PREFIX}" ]; then
        configure_args="$configure_args --prefix=${PREFIX}"
    fi
    ./configure $configure_args
    make clean
fi

make -j ${MAX_JOBS}
if [ "${fjenv_use_fcc}" = "true" ]; then
    ${CXX} --linkfortran -SSL2 -Kopenmp -Nlibomp -o python Programs/python.o -L. -lpython$PYTHON_VER $LDFLAGS
fi

make install

hash -r

# During pip3 install, new setuptools ended up in the following error.
#    AttributeError: module 'distutils' has no attribute 'version'
# Workaround is found in:
#    See https://stackoverflow.com/questions/70520120/attributeerror-module-setuptools-distutils-has-no-attribute-version
# Note that python 3.9 buildles setuptools 58.1.
#pip3 uninstall -y setuptools

pip3 install $PIP3_OPTIONS 'setuptools<59.6.0'

# Show configuration

echo "Output of python3-config:"
python3_config_args="prefix exec-prefix includes libs cflags ldflags extension-suffix abiflags configdir embed"
for arg in $python3_config_args; do printf "  %-20s" $arg; python3-config --$arg; done
echo "\n"

fjenv_safe_exit 0
