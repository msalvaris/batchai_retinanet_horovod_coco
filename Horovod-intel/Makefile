define PROJECT_HELP_MSG
Usage:
    make help                   show this message
    make build                  make Horovod Keras image with Open MPI
    make run-mpi				run training using Open MPI image
    make run					run training in non-distributed mode
    make push					push Horovod Keras image with Open MPI
endef
export PROJECT_HELP_MSG

PWD:=$(shell pwd)
PROJ_ROOT:=$(shell dirname $(PWD))
DATA_DIR:=/mnt/coco
numproc:=2 # Number of precesses/GPUs
name_prefix:=masalvar
tag:=9-1.8-0.13.2 # Cuda - TF version - Horovod version

setup_environment:=--env AZ_BATCHAI_MOUNT_ROOT='/mnt/output' \
	--env AZ_BATCHAI_INPUT_SCRIPT='/mnt/script' \
	--env AZ_BATCHAI_OUTPUT_OUTPUTFILES='/mnt/output' \
	--env AZ_BATCHAI_INPUT_DATA='/mnt/data'

setup_volumes:=-v $(PROJ_ROOT):/mnt/script \
	-v $(DATA_DIR):/mnt/data \
	-v $(PWD)/temp/output:/mnt/output

define execute_mpi
 nvidia-docker run -it \
 $(setup_environment) \
 $(setup_volumes) \
 --privileged \
 $(1) bash -c "mpirun -n $(numproc) -host localhost -ppn $(numproc) -env NCCL_DEBUG=INFO \
 			   -env NCCL_IB_DISABLE=1 \
 			   -envlist LD_LIBRARY_PATH,PATH \
 			   -env I_MPI_DEBUG=6 \
 			   -env I_MPI_HYDRA_DEBUG=on \
 			   -env AZ_BATCHAI_INPUT_DATA=$$AZ_BATCHAI_INPUT_DATA \
 			   -env AZ_BATCHAI_INPUT_SCRIPT=$$AZ_BATCHAI_INPUT_SCRIPT \
 			   python $$AZ_BATCHAI_INPUT_SCRIPT/train.py --steps 500 --tensorboard-dir $$AZ_BATCHAI_OUTPUT_OUTPUTFILES/tensorboard --snapshot-path $$AZ_BATCHAI_OUTPUT_OUTPUTFILES --no-evaluation coco $AZ_BATCHAI_INPUT_DATA"
endef

#define execute
# nvidia-docker run -it \
# $(setup_environment) \
# $(setup_volumes) \
# --privileged \
# $(1) bash -c "python $AZ_BATCHAI_INPUT_SCRIPT/train.py --steps 500 --tensorboard-dir $AZ_BATCHAI_OUTPUT_OUTPUTFILES/tensorboard --snapshot-path $AZ_BATCHAI_OUTPUT_OUTPUTFILES --no-evaluation coco $AZ_BATCHAI_INPUT_DATA""
#endef

help:
	echo "$$PROJECT_HELP_MSG" | less

build:
	docker build -t $(name_prefix)/horovod-batchai-coco-retinanet:$(tag) Docker

run-mpi:
	$(call execute_mpi, $(name_prefix)/horovod-batchai-coco-retinanet:$(tag))

#run:
#	$(call execute, $(name_prefix)/horovod-batchai-coco-retinanet:$(tag))

push:
	docker push $(name_prefix)/horovod-batchai-coco-retinanet:$(tag)


.PHONY: help build push
