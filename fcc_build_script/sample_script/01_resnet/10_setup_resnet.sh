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
    rm -rf $script_basedir/models
    fjenv_safe_exit 0
fi

#
# Download models
# Model and data reside in the current directory,
# while other modules are stored uner $DOWNLOAD_PATH.
#

cd $script_basedir

if [ ! -d models ]; then
    git clone $GIT_OPTIONS \
	-b v2.0 \
	--depth 1 \
	http://github.com/tensorflow/models
    (cd models; patch -p1 < ../resnet.patch)
fi

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Switch to VENV
#

if [ "$fjenv_use_venv" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
