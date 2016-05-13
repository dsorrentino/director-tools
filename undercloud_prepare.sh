#!/bin/bash

source config/director-tools.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_prepare.log

source ${DIRECTOR_TOOLS}/functions/common.sh

chmod 600 ${DIRECTOR_TOOLS}/config/undercloud.env

stdout "This script will gather the data for the undercloud virtual machine."
stdout "This VM could exist or not.  The script has the capability to create"
stdout "The VM if needed."

source ${DIRECTOR_TOOLS}/functions/config/undercloud_vm.sh

source ${DIRECTOR_TOOLS}/config/undercloud.env

if [[ "${UNDERCLOUD_CREATE_VM}" == 'Y' ]]
then
  source ${DIRECTOR_TOOLS}/functions/kvm/configure_kvm.sh
  source ${DIRECTOR_TOOLS}/functions/kvm/create_undercloud_vm.sh
fi

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

