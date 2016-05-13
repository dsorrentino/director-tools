#!/bin/bash

source config/director-tools.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_configure.log

source ${DIRECTOR_TOOLS}/functions/common.sh

source ${DIRECTOR_TOOLS}/config/undercloud.env

stdout ""
stdout "This script will gather the data for the undercloud deployment and install all"
stdout "necessary packages to do the undercloud install."
stdout ""

source  ${DIRECTOR_TOOLS}/functions/undercloud/configure.sh

kvm_snapshot undercloud configure_undercloud_complete

stdout "At this point you should be ready to deploy your undercloud. You may want to review"
stdout "the undercloud.conf file in the ${UNDERCLOUD_USER} home directory before continuing."
stdout ""
stdout "When you're ready, you can either run the undercloud_deploy.sh script or execute"
stdout "the following on the undercloud VM as the ${UNDERCLOUD_USER}"
stdout ""
stdout "openstack undercloud install"
stdout ""
