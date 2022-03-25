#! /bin/bash
#PJM -L node=1
#PJM --mpi proc=2

set -euo pipefail

script_basedir=$(cd $(dirname $0); pwd)
source $script_basedir/../../env.src	# Only for TCSDS_PATH.

set -x

NUM_NODES=2

# MPI under TCS doens't take options as argument
num_procs=$(grep -c '^processor' /proc/cpuinfo)
if [ $num_procs -eq 48 ]; then
    host_1node2ppn="-np $NUM_NODES --host localhost:2 --map-by slot:pe=24"
    mpi_args="--prefix $TCSDS_PATH $host_1node2ppn"
    mpi_args="$mpi_args -mca pml ob1"
    #mpi_args="$mpi_args -mca btl openib"				# Infiniband
    mpi_args="$mpi_args --display-map --display-allocation"		# For debug
fi

export MPI_OPTIONS="--batch_size $((2 * $NUM_NODES)) --num_workers $NUM_NODES --use_horovod"
#export TF_CONFIG_PATH=$script_basedir/config/tf_config_2proc.json # horovod doesn't use it.

mpirun $mpi_args -x MPI_OPTIONS run1proc.sh
