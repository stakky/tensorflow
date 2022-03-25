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

DATA_DIR=dataset
MASK_RCNN_DIR=MaskRCNN

#
# Clean up
#

if [ -v fjenv_clean ]; then
    # Keep the training data because it is costly to download.
    #rm -rf $script_basedir/$DATA_DIR
    fjenv_safe_exit 0
fi

#
# Download dataset
#

cd $script_basedir

[ ! -d $DATA_DIR/coco ] && mkdir -p $DATA_DIR/coco
cd $DATA_DIR/coco
for zip in train2017.zip val2017.zip test2017.zip; do
    [ ! -f $zip ] && curl -O http://images.cocodataset.org/zips/$zip
done
for zip in annotations_trainval2017.zip image_info_test2017.zip; do
    [ ! -f $zip ] && curl -O http://images.cocodataset.org/annotations/$zip
done

[ -v fjenv_download ] && fjenv_safe_exit 0

#
# Switch to VENV
#

if [ "${fjenv_use_venv}" = "true" ]; then
    source ${VENV_PATH}/bin/activate
fi

# Extract dataset

cd $script_basedir/$DATA_DIR/coco
for zipfile in train2017 val2017 test2017; do
    if [ ! -d $zipfile ]; then
	echo "unzip $zipfile.zip"
	unzip -nq $zipfile.zip
    fi
done
if [ ! -d annotations ]; then
    echo "unzip annotations_trainval2017.zip"
    unzip -nq annotations_trainval2017.zip
    echo "unzip annotations_trainval2017.zip"
    unzip -nq image_info_test2017.zip
fi

cd $script_basedir
export PYTHONPATH=$script_basedir/$MASK_RCNN_DIR:$script_basedir/$MASK_RCNN_DIR/research:$script_basedir/$MASK_RCNN_DIR/research/slim

if [ ! -d $DATA_DIR/tf_record ]; then
    python3 $MASK_RCNN_DIR/research/object_detection/dataset_tools/create_coco_tf_record.py --logtostderr \
	   --train_image_dir="$DATA_DIR/coco/train2017" \
	   --val_image_dir="$DATA_DIR/coco/val2017" \
	   --test_image_dir="$DATA_DIR/coco/test2017" \
	   --train_annotations_file="$DATA_DIR/coco/annotations/instances_train2017.json" \
	   --val_annotations_file="$DATA_DIR/coco/annotations/instances_val2017.json" \
	   --testdev_annotations_file="$DATA_DIR/coco/annotations/image_info_test-dev2017.json" \
	   --output_dir="$DATA_DIR/tf_record" \
	   --include_masks
fi

fjenv_safe_exit 0
