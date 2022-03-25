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
    rm -rf pretraining_data
    fjenv_safe_exit 0
fi

#
# Download models
#

if [ -v fjenv_download ]; then fjenv_safe_exit 0; fi

#
# Switch to VENV
#

if [ "${fjenv_use_venv}" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

#
# Build
#

# Use same CC and CXX in Python build
unset CC CXX

DATA_DIR=$script_basedir/pretraining_data
BERT_DIR=$script_basedir/cased_L-12_H-768_A-12

if [ ! -d "$DATA_DIR" ]; then mkdir -p $DATA_DIR; fi

TFRNUM=32
for ((i=0 ; i<${TFRNUM}; i++))
do
  if [ $i -eq 0 ]; then
    TFRNAME="${DATA_DIR}/tf_examples_$(($i + 1))-${TFRNUM}.tfrecord"
  else
    TFRNAME="${TFRNAME},${DATA_DIR}/tf_examples_$(($i + 1))-${TFRNUM}.tfrecord"
  fi
  cat sample_text.txt >> $DATA_DIR/sample_text_${TFRNUM}.txt
done

cd $script_basedir/Bert
export PYTHONPATH=`pwd`
cd official/nlp/bert

python3 ../data/create_pretraining_data.py         \
  --input_file=$DATA_DIR/sample_text_${TFRNUM}.txt \
  --output_file=$TFRNAME                           \
  --vocab_file=$BERT_DIR/vocab.txt                 \
  --do_lower_case=False                            \
  --max_seq_length=128                             \
  --max_predictions_per_seq=20                     \
  --masked_lm_prob=0.15                            \
  --random_seed=12345

fjenv_safe_exit 0
