#! /bin/bash

set -euo pipefail

script_basedir=$(cd $(dirname $0); pwd)
source $script_basedir/../../env.src
[ -v VENV_PATH ] && source $VENV_PATH/bin/activate

set -x

export OMP_PROC_BIND=false			# Mandatory
export OMP_NUM_THREADS=11
#export KMP_SETTINGS=1				# For debug. Show OMP/KMP setting
export KMP_BLOCKTIME=1

export TF_ENABLE_MKL_NATIVE_FORMAT=false	# Mandatory
#export TF_CPP_MIN_LOG_LEVEL=0			# For debug.
#export TF_CPP_MAX_VLOG_LEVEL=1			# For debug.
#export TF_CPP_VLOG_FILENAME=vlog.out		# For debug.
#export DNNL_VERBOSE=1				# For debug.
#export DNNL_VERBOSE_TIMESTAMP=1		# For debug.

#export HOROVOD_MPI_THREADS_DISABLE=1
#export HOROVOD_STALL_SHUTDOWN_TIME_SECONDS=300

# PMIX_RANK is defined under mpirun.
if [ -v PMIX_RANK ]; then
    # Options for multiple instance run.
    num_procs=$OMPI_MCA_orte_ess_num_procs
    rank=$PMIX_RANK
    # MPI_OPTIONS="$MPI_OPTIONS add-something"
else
    # For single instance run, numactl is used.
    # The numbering rule for NUMA node is different in FX1000 and FX700.
    #           # of cores      Numa Node nuber
    #                           OS      Computing
    #	-----------------------------------------------------------
    #   FX1000  50 or 52        0       4-7     (Including Fugaku)
    #   FX700   48              N/A     0-3
    num_procs=$(grep -c '^processor' /proc/cpuinfo)
    if [ $num_procs -eq 48 ]; then numa_node="3"; else numa_node="7"; fi
    NUMACTL="numactl --membind=$numa_node --cpunodebind=$numa_node"
fi

export PYTHONPATH=$script_basedir/models:${PYTHONPATH:-}
source_dir=$script_basedir/models/official/r1/resnet
model_dir=$script_basedir/run_$(date +%Y%m%d_%H%M%S)

ulimit -s 8192

${NUMACTL:-} python3 $source_dir/imagenet_main.py \
	--model_dir=$model_dir	\
	--num_gpus=0		\
	--max_train_steps=20	\
	--print_every=1		\
	--train_epochs=1	\
	--intra=1		\
	--inter=1		\
	--batch_size=48		\
	--synth			\
	${MPI_OPTIONS:-}
