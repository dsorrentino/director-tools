#!/bin/bash

source environment/director-tools.env
source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/environment/undercloud.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_deploy.log

stdout ""
stdout "This script will execute the undercloud deployment and copy all output logs"
stdout "back to ${DIRECTOR_TOOLS}/logs"
stdout ""

ssh -t ${UNDERCLOUD_USER}@${UNDERCLOUD_IP} 'openstack undercloud install | tee -a undercloud_install.log'

rm -f ${DIRECTOR_TOOLS}/logs/undercloud_install.log*

scp ${UNDERCLOUD_USER}@${UNDERCLOUD_IP}:undercloud_install.log* ${DIRECTOR_TOOLS}/logs

if [[ -z "$(ls ${DIRECTOR_TOOLS}/logs/undercloud_install.*err 2>/dev/null)" ]]
then
  stdout "Undercloud installation completed successfully."
  stdout "Copying templates into ${UNDERCLOUD_USER}/templates."
  ssh -t ${UNDERCLOUD_USER}@${UNDERCLOUD_IP} 'cp -pR /usr/share/openstack-tripleo-heat-templates/* ~/templates/'
  kvm_snapshot undercloud undercloud_deploy_complete
else
  stderr "There appears to have been a problem witht he deployment."
fi



stdout "At this point you should be ready to prepare your overcloud."
stdout ""
stdout "When you're ready, execute the overcloud_prepare.sh script"
stdout "to continue."
stdout ""
