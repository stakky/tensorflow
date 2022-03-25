#! /bin/bash

set -euo pipefail

script_basedir=$(cd $(dirname $0); pwd)
source $script_basedir/../../env.src
[ -v VENV_PATH ] && source $VENV_PATH/bin/activate

set -x

export OMP_PROC_BIND=false			# Mandatory
export OMP_NUM_THREADS=8
#export KMP_SETTINGS=1				# For debug. Show OMP/KMP setting
export KMP_BLOCKTIME=1

export TF_ENABLE_MKL_NATIVE_FORMAT=false	# Mandatory
export TF_NUM_INTEROP_THREADS=2
export TF_NUM_INTRAOP_THREADS=24
#export TF_CPP_MIN_LOG_LEVEL=0			# For debug.
#export TF_CPP_MAX_VLOG_LEVEL=2			# For debug.
#export TF_CPP_VLOG_FILENAME=vlog.out		# For debug.
#export DNNL_VERBOSE=1				# For debug.
#export DNNL_VERBOSE_TIMESTAMP=1		# For debug.

export HOROVOD_MPI_THREADS_DISABLE=1
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
    if [ $num_procs -eq 48 ]; then numa_node="2,3"; else numa_node="6,7"; fi
    NUMACTL="numactl --membind=$numa_node --cpunodebind=$numa_node"
fi

export PYTHONPATH=$script_basedir/Bert

data_dir=$script_basedir/pretraining_data
model_dir=$script_basedir/run_pretraining_$(date +%Y%m%d_%H%M%S)
bert_dir=$script_basedir/cased_L-12_H-768_A-12

ulimit -s 8192

${NUMACTL:-} python3 Bert/official/nlp/bert/run_pretraining.py \
  --input_files=$data_dir/tf_examples_*.tfrecord \
  --model_dir=$model_dir                         \
  --bert_config_file=$bert_dir/bert_config.json  \
  --init_checkpoint=$bert_dir/bert_model.ckpt    \
  --train_batch_size=48                          \
  --max_seq_length=128                           \
  --max_predictions_per_seq=20                   \
  --num_train_epochs=1                           \
  --warmup_steps=10                              \
  --num_steps_per_epoch=20                       \
  --steps_per_loop=1                             \
  --log_steps=1					 \
  ${MPI_OPTIONS:-}
