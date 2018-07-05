define PROJECT_HELP_MSG
Usage:
    make help                   show this message
    make build                  build docker image
    make push					 push container
    make run					 run benchmarking container
endef
export PROJECT_HELP_MSG


image_name:=masalvar/batchai-retinanet-control
PWD:=$(shell pwd)

# Variables for Batch AI - change as necessary
ID:=cocoretinanet
LOCATION:=eastus
GROUP_NAME:=batch${ID}rg
STORAGE_ACCOUNT_NAME:=batch${ID}st
CONTAINER_NAME:=batch${ID}container
FILE_SHARE_NAME:=batch${ID}share
VM_SIZE:=Standard_NC24rs_v3
NUM_NODES:=2
CLUSTER_NAME:=cococluster
JOB_NAME:=cocoretinanet
#MODEL:=resnet50
SELECTED_SUBSCRIPTION:="Team Danielle Internal"
WORKSPACE:=workspace
EXPERIMENT:=experiment
PROCESSES_PER_NODE:=4
GPU_TYPE:=v100
DATA_PATH='/'



define generate_job_local
 python ../generate_job_spec.py masalvar/horovod-batchai-bench:9-1.8-0.13.2 local \
 	--filename job.json \
 	--node_count 1 \
 	--model $(1) \
 	--ppn $(2)
endef


define stream_stdout
	az batchai job file stream -w $(WORKSPACE) -e $(EXPERIMENT) \
	--j $(1) --output-directory-id stdouterr -f stdout.txt
endef


define submit_job
	az batchai job create -n $(1) --cluster ${CLUSTER_NAME} -w $(WORKSPACE) -e $(EXPERIMENT) -f job.json
endef

define delete_job
	az batchai job delete -w $(WORKSPACE) -e $(EXPERIMENT) --name $(1) -y
endef


help:
	echo "$$PROJECT_HELP_MSG" | less

build:
	docker build -t $(image_name) Docker

run:
	docker run -v $(PWD):/workspace -it $(image_name) bash

push:
	docker push $(image_name)

select-subscription:
	az login -o table
	az account set --subscription $(SELECTED_SUBSCRIPTION)

create-resource-group:
	az group create -n $(GROUP_NAME) -l $(LOCATION) -o table

create-storage:
	@echo "Creating storage account"
	az storage account create -l $(LOCATION) -n $(STORAGE_ACCOUNT_NAME) -g $(GROUP_NAME) --sku Standard_LRS

set-storage:
	$(eval azure_storage_key:=$(shell az storage account keys list -n $(STORAGE_ACCOUNT_NAME) -g $(GROUP_NAME) | jq '.[0]["value"]'))
	$(eval azure_storage_account:= $(STORAGE_ACCOUNT_NAME))
	$(eval file_share_name:= $(FILE_SHARE_NAME))
	export AZURE_STORAGE_ACCOUNT ${STORAGE_ACCOUNT_NAME}
	export AZURE_STORAGE_KEY ${azure_storage_key}

set-az-defaults:
	az configure --defaults location=${LOCATION}
	az configure --defaults group=${GROUP_NAME}


create-fileshare: set-storage
	@echo "Creating fileshare"
	az storage share create -n $(file_share_name) --account-name $(azure_storage_account) --account-key $(azure_storage_key)

create-directory: create-fileshare set-storage
	az storage directory create --share-name $(file_share_name)  --name scripts --account-name $(azure_storage_account) --account-key $(azure_storage_key)

create-container: set-storage
	@echo "Creating container"
	az storage container create --account-name ${STORAGE_ACCOUNT_NAME} --account-key $storage_account_key --name ${CONTAINER_NAME}

upload-training-data: set-storage
	azcopy --source ${DATA_PATH}/images/train2017 \
	--destination  https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${CONTAINER_NAME}/images/train2017 \
    --dest-key $storage_account_key --quiet --recursive

upload-annotations: set-storage
	azcopy --source ${DATA_PATH}/annotations \
	--destination  https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${CONTAINER_NAME}/annotations \
    --dest-key $storage_account_key --quiet --recursive

upload-validation: set-storage
	azcopy --source ${DATA_PATH}/images/val2017 \
	--destination  https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${CONTAINER_NAME}/images/val2017 \
    --dest-key $storage_account_key --quiet --recursive


upload-script:
	az storage file upload --share-name ${FILESHARE_NAME} --source train.py --path scripts


create-workspace:
	az batchai workspace create -n $(WORKSPACE) -g $(GROUP_NAME)

create-experiment:
	az batchai experiment create -n $(EXPERIMENT) -g $(GROUP_NAME) -w $(WORKSPACE)

create-cluster: set-storage
	az batchai cluster create \
	-w $(WORKSPACE) \
	--name ${CLUSTER_NAME} \
	--image UbuntuLTS \
	--vm-size ${VM_SIZE} \
	--min ${NUM_NODES} --max ${NUM_NODES} \
	--afs-name ${FILE_SHARE_NAME} \
	--afs-mount-path extfs \
	--container-name ${CONTAINER_NAME} \
	--container-mount-path extcn \
	--user-name mat \
	--password dnstvxrz \
	--storage-account-name $(STORAGE_ACCOUNT_NAME) \
	--storage-account-key $(azure_storage_key)

show-cluster:
	az batchai cluster show -n ${CLUSTER_NAME} -w $(WORKSPACE)

list-clusters:
	az batchai cluster list -w $(WORKSPACE) -o table

list-nodes:
	az batchai cluster list-nodes -n ${CLUSTER_NAME} -w $(WORKSPACE) -o table


run-bait-intel:
	$(call generate_job_intel, $(NUM_NODES), $(MODEL), $(PROCESSES_PER_NODE))
	$(call submit_job, ${JOB_NAME})

run-bait-openmpi:
	$(call generate_job_openmpi, $(NUM_NODES), $(MODEL), $(PROCESSES_PER_NODE))
	$(call submit_job, ${JOB_NAME})

run-bait-local:
	$(call generate_job_local, $(MODEL), $(PROCESSES_PER_NODE))
	$(call submit_job, ${JOB_NAME})

list-jobs:
	az batchai job list -w $(WORKSPACE) -e $(EXPERIMENT) -o table

list-files:
	az batchai job file list -w $(WORKSPACE) -e $(EXPERIMENT) --j ${JOB_NAME} --output-directory-id stdouterr

stream-stdout:
	$(call stream_stdout, ${JOB_NAME})


stream-stderr:
	az batchai job file stream -w $(WORKSPACE) -e $(EXPERIMENT) --j ${JOB_NAME} --output-directory-id stdouterr -f stderr.txt

delete-job:
	$(call delete_job, ${JOB_NAME})

delete-cluster:
	az configure --defaults group=''
	az configure --defaults location=''
	az batchai cluster delete -w $(WORKSPACE) --name ${CLUSTER_NAME} -g ${GROUP_NAME} -y

delete: delete-cluster
	az batchai experiment delete -w $(WORKSPACE) --name ${experiment} -g ${GROUP_NAME} -y
	az batchai workspace delete -w ${WORKSPACE} -g ${GROUP_NAME} -y
	az group delete --name ${GROUP_NAME} -y


setup: select-subscription create-resource-group create-workspace create-storage set-storage set-az-defaults create-fileshare create-cluster list-clusters
	@echo "Cluster created"


###### Submit Jobs ######

submit-job:
	az batchai job create -n ${JOB_NAME} --cluster ${CLUSTER_NAME} -w $(WORKSPACE) -e $(EXPERIMENT) -f training_job.json

.PHONY: help build push