#!/bin/bash

source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/environment/undercloud.env

SCRIPT_NAME=configure-overcloud
LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

scp ${DIRECTOR_TOOLS}/run/overcloud-servers.txt ${DIRECTOR_TOOLS}/environment/*cloud.env ${DIRECTOR_TOOLS}/functions/common.sh ${DIRECTOR_TOOLS}/functions/overcloud/remote_prepare*.sh stack@${UNDERCLOUD_IP}:~

ssh stack@${UNDERCLOUD_IP} 'chmod 600 ~/*cloud.env; chmod 775 ~/remote_prepare_overcloud.sh'
ssh -t stack@${UNDERCLOUD_IP} '~/remote_prepare_overcloud.sh'
scp stack@${UNDERCLOUD_IP}:~/remote_prepare_overcloud*log* ${DIRECTOR_TOOLS}/logs
ssh stack@${UNDERCLOUD_IP} 'rm -f ~/*cloud.env ~/remote_prepare_overcloud* ~/overcloud-servers.txt ~/common.sh'

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
