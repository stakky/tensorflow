#! /bin/bash
#PJM -L node=1
#PJM --mpi proc=4

set -euo pipefail

script_basedir=$(cd $(dirname $0); pwd)
source $script_basedir/../../env.src	# Only for TCSDS_PATH.

set -x

NUM_NODES=4

# MPI under TCS doens't take options as argument
num_procs=$(grep -c '^processor' /proc/cpuinfo)
if [ $num_procs -eq 48 ]; then
    host_1node4ppn="-np $NUM_NODES --host localhost:4 --bynode"
    mpi_args="--prefix $TCSDS_PATH $host_1node4ppn"
    mpi_args="$mpi_args -mca pml ob1"
    #mpi_args="$mpi_args -mca btl openib"				# Infiniband
    mpi_args="$mpi_args --display-map --display-allocation"		# For debug
fi

export MPI_OPTIONS="--horovod"

set -x

mpirun $mpi_args -x MPI_OPTIONS run1proc.sh
