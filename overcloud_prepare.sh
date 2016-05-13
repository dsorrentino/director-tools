#!/bin/bash

source config/director-tools.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-overcloud_prepare.log

source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/config/overcloud.env

source ${DIRECTOR_TOOLS}/functions/config/overcloud_vms.sh

chmod 600 ${DIRECTOR_TOOLS}/config/overcloud.env

