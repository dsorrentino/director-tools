#!/bin/bash

source environment/director-tools.env
source ${DIRECTOR_TOOLS}/functions/common.sh
chmod 600 ${DIRECTOR_TOOLS}/environment/undercloud.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_create_vm.log

stdout "This script will gather the data for the undercloud virtual machine."
stdout ""
stdout "The expection is that the VM does not exist and this script will create it."

${DIRECTOR_TOOLS}/functions/undercloud/create_vm/configure_vm.sh

source ${DIRECTOR_TOOLS}/environment/undercloud.env

${DIRECTOR_TOOLS}/functions/kvm/configure_kvm.sh
${DIRECTOR_TOOLS}/functions/undercloud/create_vm/create_vm.sh

if [[ -z "$(grep undercloud /etc/hosts)" ]]
then
  stderr "Expected /etc/hosts to be configured for the undercloud.  Please check that."
else
  scp ${DIRECTOR_TOOLS}/tools/subscribe_*.sh root@undercloud:~ >/dev/null 2>/dev/null
  ssh root@undercloud 'chmod 775 ~/subscribe_*.sh'
fi

kvm_snapshot undercloud prepare_undercloud_complete

stdout "At this point you have a VM up and running to install the undercloud on."
stdout ""
stdout "Server: ${UNDERCLOUD_IP}"
stdout "Undercloud User: ${UNDERCLOUD_USER}"
stdout ""
stdout "The following scripts were copied to the root home directory.  Login and execute"
stdout "the appropriate one to register your system.  Or register your system manually."
stdout ""
stdout "$(ls ${DIRECTOR_TOOLS}/tools/subscribe_*.sh)"
stdout ""
stdout "Once registered, execute the undercloud_configure.sh to install the appropriate"
stdout "packages and create the necessary configuration files to deploy your Undercloud."
stdout ""

