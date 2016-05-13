#!/bin/bash

source ${DIRECTOR_TOOLS}/functions/common.sh
SCRIPT_NAME=configure-overcloud
LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

source ${DIRECTOR_TOOLS}/functions/kvm/create_overcloud_vms.sh
source ${DIRECTOR_TOOLS}/config/undercloud.env

UNDERCLOUD_IP_ADDRESS=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $1}')

scp ${DIRECTOR_TOOLS}/config/overcloud-servers.txt ${DIRECTOR_TOOLS}/config/*cloud.env ${DIRECTOR_TOOLS}/functions/overcloud/remote_prepare*.sh stack@${UNDERCLOUD_IP_ADDRESS}:~

ssh stack@${UNDERCLOUD_IP_ADDRESS} 'chmod 600 ~/*cloud.env; chmod 775 ~/remote_prepare_overcloud.sh'
ssh -t stack@${UNDERCLOUD_IP_ADDRESS} '~/remote_prepare_overcloud.sh'
scp stack@${UNDERCLOUD_IP_ADDRESS}:~/remote_prepare_overcloud*log* ${DIRECTOR_TOOLS}/logs
ssh stack@${UNDERCLOUD_IP_ADDRESS} 'rm -f ~/*cloud.env ~/remote_prepare_overcloud* ~/overcloud-servers.txt ~/common.sh'

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
