#!/bin/bash

source ${DIRECTOR_TOOLS}/functions/common.sh

SCRIPT_NAME=create_overcloud_vms-configure
LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

${DIRECTOR_TOOLS}/functions/overcloud/create_vm/create_overcloud_environment.sh


stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
