#!/bin/bash

source config/director-tools.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_deploy.log

source ${DIRECTOR_TOOLS}/functions/common.sh

source ${DIRECTOR_TOOLS}/config/undercloud.env

stdout ""
stdout "This script will execute the undercloud deployment and copy all output logs"
stdout "back to ${DIRECTOR_TOOLS}/logs"
stdout ""

UNDERCLOUD_IP_ADDRESS=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $1}')

ssh -t ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} 'openstack undercloud install | tee -a undercloud_install.log'

rm -f ${DIRECTOR_TOOLS}/logs/undercloud_install.log*

scp ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:undercloud_install.log* ${DIRECTOR_TOOLS}/logs

if [[ -z "$(ls ${DIRECTOR_TOOLS}/logs/undercloud_install.*err 2>/dev/null)" ]]
then
  stdout "Undercloud installation completed successfully."
  kvm_snapshot undercloud undercloud_deploy_complete
else
  stderr "There appears to have been a problem witht he deployment."
fi

stdout "At this point you should be ready to prepare your overcloud."
stdout ""
stdout "When you're ready, execute the overcloud_prepare.sh script"
stdout "to continue."
stdout ""
