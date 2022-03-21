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

[ -v fjenv_clean ] && fjenv_safe_exit 0

#
# Download
#

if [ "${fjenv_offline_install}" = "true" -a ! -d "${PIP_PACKAGE_PATH}" ]; then
    mkdir "${PIP_PACKAGE_PATH}"
    (cd "${PIP_PACKAGE_PATH}";      \
     sed -e "s/#.*$//;/^$/d"	\
	${script_basedir}/pip_packages.list | \
	sort | uniq | wget ${WGET_OPTIONS} -i -)
fi

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Create VENV
#

if [ "${fjenv_use_venv}" = "true" ]; then
    if [ ! -d "${VENV_PATH}" -o -v fjenv_rebuild ]; then
	rm -rf ${VENV_PATH}
	python3 -m venv ${VENV_PATH}
    fi
    source ${VENV_PATH}/bin/activate
fi

#
# Install pip packages
# These should be installed reagrdless of venv use.
#

# During pip3 install, new setuptools ended up in the following error.
#    AttributeError: module 'distutils' has no attribute 'version'
# Workaround is found in:
#    See https://stackoverflow.com/questions/70520120/attributeerror-module-setuptools-distutils-has-no-attribute-version

pip3 install 'setuptools<59.6.0'

pip3 install --upgrade ${PIP3_OPTIONS} pip future six wheel

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
