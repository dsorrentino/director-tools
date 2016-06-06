#!/bin/bash

source environment/director-tools.env
source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/environment/overcloud.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-overcloud_create_vms.log

stdout ""
stdout "This script will create Virtual Machines on a KVM host to be used as Overcloud nodes."
stdout ""

${DIRECTOR_TOOLS}/functions/overcloud/create_vm/create_overcloud_environment.sh

chmod 600 ${DIRECTOR_TOOLS}/environment/overcloud.env
