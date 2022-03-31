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

JDK_VER=jdk-15
JDK_ARCHIVE_URL="https://download.java.net/java/GA/jdk15/779bf45e88a44cbd9ea6621d33e33db1/36/GPL/open${JDK_VER}_linux-aarch64_bin.tar.gz"

#
# Clean up
#

if [ -v fjenv_clean ]; then
    rm -rf $DOWNLOAD_PATH/`basename "$JDK_ARCHIVE_URL"` $PREFIX/$JDK_VER
    fjenv_safe_exit 0
fi

#
# Download OpenJDK
#

[ -d $DOWNLOAD_PATH ] || mkdir -p ${DOWNLOAD_PATH}
cd ${DOWNLOAD_PATH}

if [ ! -f `basename "$JDK_ARCHIVE_URL"` ]; then
    wget ${WGET_OPTIONS} $JDK_ARCHIVE_URL
fi

#
# Download bazel
#

BAZEL_VER=4.2.2
BAZEL_NAME=bazel-${BAZEL_VER}-linux-arm64

# The patch applied to bazel is to workaround Luster Filesystem
#   Cf. See https://github.com/bazelbuild/bazel/issues/2647
# For FX1000, this must be set to 'true' since it uses FEFS (Luster-based)
# For Fugaku and FX700, either true or false is OK (as of 2022-Mar.)
fjenv_use_fjpatched_bazel=true

if [ ! -f $BAZEL_NAME ]; then
    if [ "$fjenv_use_fjpatched_bazel" != "true" ]; then
	wget ${WGET_OPTIONS} https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VER/$BAZEL_NAME
	chmod +x $BAZEL_NAME
    fi
fi

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Install bazel
#

if [ ! -d $PREFIX/$JDK_VER ]; then
    mkdir -p $PREFIX
    (cd $PREFIX; tar xfzp $DOWNLOAD_PATH/`basename $JDK_ARCHIVE_URL`)
    ln -sf $JDK_VER $PREFIX/java
fi

if [ -v fjenv_rebuild ]; then
    rm -f $PREFIX/bin/bazel
fi

if [ ! -x $PREFIX/bin/bazel ]; then
    [ ! -d $PREFIX/bin ] && mkdir -p $PREFIX/bin
    if [ "$fjenv_use_fjpatched_bazel" != "true" ]; then
	cp -p $BAZEL_NAME $PREFIX/bin
	ln -s $BAZEL_NAME $PREFIX/bin/bazel
    else
	if [ ! -f $script_basedir/bazel-4.2.2-fjpatch.bin ]; then
	    cat $script_basedir/.bazel-4.2.2-fjpatch.bin.a? \
	        > $script_basedir/bazel-4.2.2-fjpatch.bin
	    chmod a+x $script_basedir/bazel-4.2.2-fjpatch.bin
	fi
	cp -p $script_basedir/bazel-4.2.2-fjpatch.bin $PREFIX/bin
        ln -s bazel-4.2.2-fjpatch.bin $PREFIX/bin/bazel
    fi
fi

fjenv_safe_exit 0

### NOTREACHED

####
#### Note on patched bazel
####
#### Patched bazel (bazel-4.2.2-fjpatch.bin) is created in the following steps.
####   See also: https://docs.bazel.build/versions/4.2.2/install-compile-source.html#build-bazel-using-bazel
#### Please notice that we follow the "Build Bazel using Bazel",
#### as we haven't succeeded "bootstrapping" so far.
####

cd $YOUR_BAZEL_SOZURCE_TOP_DIRECTORY

export JAVA_HOME=${PREFIX}/java
export EXTRA_BAZEL_ARGS="--host_javabase=@local_jdk//:jdk"
export SOURCE_DATA_EPOCH=`date +%s`	# For "bootstrapping" 

(cd src; patch -p1 < $script_basedir/bazel-4.2.2.patch)

(cd $PREFIX/bin; ln -s python3 python)

bazel \
    --host_jvm_args=-Djdk.http.auth.tunneling.disabledSchemes= \
    build \
    --verbose_failures \
    //src:bazel-dev

cp -p bazel-bin/src/bazel-dev $script_basedir/bazel-4.2.2-fjpatch.bin

fjenv_safe_exit 0
