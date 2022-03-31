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

if [ -v fjenv_clean ]; then
    rm -rf ${TF_DISTDIR}
    fjenv_safe_exit 0
fi

#
# Download python packages that TensorFlow is requiring
#

if [ "$fjenv_offline_install" = "true" ]; then		# {

if [ ! -d "${TF_DISTDIR}" ]; then
    mkdir "${TF_DISTDIR}" 
    (cd "${TF_DISTDIR}";	\
     sed -e "/#/d;s/#.*$//" $script_basedir/tf_dist.list | wget ${WGET_OPTIONS} -i -)
fi

if [ ! -d $DOWNLOAD_PATH/io_bazel_rules_docker ]; then
    pushd $DOWNLOAD_PATH
    # Bazel 4.2.2 still fetches docker rules during build phase with the following command
    #     git fetch https://github.com/bazelbuild/rules_docker.git 'refs/heads/*:refs/remotes/origin/*' 'refs/tags/*:refs/tags/*'
    # which requires the system being online.
    # Here is a tricky workaround to make offline build possible.
    # Note: Option (shallow-since) and commit hash are taken from the output of online build with using verbose option,
    #       and the contents of the marker file is obtained from the cahce file (under $OUTBASE/external).
    # Note2: The second 'git clone' is for one that doesn't support 'shallow-since' (typically git version 1).
    git clone https://github.com/bazelbuild/rules_docker.git --shallow-since "1596824487 -0400" io_bazel_rules_docker || \
        git clone https://github.com/bazelbuild/rules_docker.git io_bazel_rules_docker
    (cd io_bazel_rules_docker; git checkout 9bfcd7dbf0294ed9d11a99da6363fc28df904502)
    cat <<EOF>'@io_bazel_rules_docker.marker'
46fc418cc25637e9fe8b7b25416330d0f38dcfae25a00613666fa63af6a15d30
STARLARK_SEMANTICS -1438583352
\$MANAGED
EOF
    popd
fi

fi							# }

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Switch to VENV
#

if [ "$fjenv_use_venv" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

#
# Install pre-required modules
#

pip3 install $PIP3_OPTIONS Keras-Preprocessing --no-deps

#
# Build TensorFlow
#

export JAVA_HOME=${PREFIX}/java

cd ${TENSORFLOW_TOP}

# Environment variable for Tensorflow build.
export PYTHON_BIN_PATH="$VENV_PATH/bin/python3"
export PYTHON_LIB_PATH="$VENV_PATH/lib/python3.9/site-packages"
export TF_ENABLE_XLA=0
export TF_NEED_OPENCL_SYCL=0
export TF_NEED_ROCM=0
export TF_DOWNLOAD_CLANG=0
export TF_SET_ANDROID_WORKSPACE=0

if [ "$fjenv_use_fcc" == "true" ]; then
    # Bazel doesn't allow whitespace in CC or CXX
    # export CC=fcc
    export CC=$script_basedir/cc_bazel
    unset CXX
fi

CONFIG="--config=noaws --config=nogcp --config=nohdfs --config=nonccl --config=mkl_aarch64"
#CONFIG_CC="--copt=-O0 --config=dbg"			# OK
#CONFIG_CC="--copt=-O0 --copt=-fopenmp --config=dbg"	# OK
#CONFIG_CC="--copt=-march=armv8.2-a+sve --copt=-O2"	# OK, gcc compatible
CONFIG_CC="--copt=-march=armv8.2-a+sve --copt=-O3"	# NG with fcc, clang core dumped @ resize_area_op.cc and cpu_runtime.cc
if [ "$fjenv_use_fcc" == "true" ]; then
    # Workarond for fcc, on which an internal error occurs with the following files.
    CONFIG_CC="$CONFIG_CC --per_file_copt=+tensorflow/core/kernels/image/resize_area_op.cc@-O2 --per_file_copt=+tensorflow/compiler/xla/service/cpu/cpu_runtime.cc@-O2"
fi
CONFIG_CPP="--cxxopt=-D_GLIBCXX_USE_CXX11_ABI=0"	# needed ?
#CONFIG_LINK="--linkopt=-Nlibomp"			# NG, options specified here directly feeds to ld, not fcc
#CONFIG_LINK="--linkopt=-Wl,-rpath,$PREFIX/lib --linkopt=-Wl,-rpath,$VENV_PATH/lib"
#CONFIG_CC="$CONFIG_CC --config=monolithic"

if [ "$fjenv_use_fcc" != "true" ]; then
    # Less parallelism for GCC, which uses much more memory than fcc or llvm.
    CONFIG_BAZEL="$CONFIG_BAZEL --jobs=20"
fi
#CONFIG_BAZEL="$CONFIG_BAZEL --color=yes --curses=yes"
#CONFIG_BAZEL="$CONFIG_BAZEL --subcommands=pretty_print"
#CONFIG_BAZEL="$CONFIG_BAZEL --local_ram_resources=$((24*1024))"
#CONFIG_BAZEL="$CONFIG_BAZEL --local_cpu_resources=24"

if [ "$fjenv_offline_install" = "true" ]; then
    OUTPUT_BASE="$PREFIX/.output_base"
    CONFIG_BAZEL_STARTUP="${CONFIG_BAZEL_STARTUP-} --output_base=$OUTPUT_BASE"
    CONFIG_BAZEL="$CONFIG_BAZEL --distdir=${TF_DISTDIR}"
fi

if [ -v fjenv_rebuild ]; then
    bazel ${CONFIG_BAZEL_STARTUP-} clean --expunge
fi

if [ "$fjenv_offline_install" = "true" ]; then
    if [ ! -d "$OUTPUT_BASE/external/io_bazel_rules_docker" ]; then
	# This is another trick part for offline build, injecting io_base_rule_docker into cache.
	# This requires cache directory name is known prior to running bazel.
	# https://docs.bazel.build/versions/main/output_directories.html says md5 of the workspace directory is used for output_base,
	# but the output of `echo $TENSORFLOW_TOP | md5sum` is not same hash that bazel uses,
	# so for the time being I intentianally uses --output_base.
	mkdir -p $OUTPUT_BASE/external
	cp -pr $DOWNLOAD_PATH/io_bazel_rules_docker $DOWNLOAD_PATH/'@io_bazel_rules_docker.marker' $OUTPUT_BASE/external
    fi
fi

bazel	${CONFIG_BAZEL_STARTUP-}			\
	build ${CONFIG} ${CONFIG_CC-} ${CONFIG_CPP-} ${CONFIG_BAZEL-} \
	//tensorflow/tools/pip_package:build_pip_package

#
# Install TensorFlow
#

if [ -d $script_basedir/tf_pkg_tmp ]; then rm -rf $script_basedir/tf_pkg_tmp; fi
bazel-bin/tensorflow/tools/pip_package/build_pip_package --src $script_basedir/tf_pkg_tmp $script_basedir/tf_pkg
rm -rf $script_basedir/tf_pkg_tmp

pip3 uninstall tensorflow -y
pip3 install ${PIP3_OPTIONS} $script_basedir/tf_pkg/*.whl

pip3 list | tee $script_basedir/pip3_list.txt

fjenv_safe_exit 0
