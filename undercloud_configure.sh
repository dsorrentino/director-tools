#!/bin/bash

source environment/director-tools.env
source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/environment/undercloud.env

LOG=${DIRECTOR_TOOLS}/logs/$(date +'%Y%m%d-%H%M')-undercloud_configure.log


stdout ""
stdout "This script will gather the data for the undercloud deployment and install all"
stdout "necessary packages to do the undercloud install."
stdout ""

stdout ""
stdout "Please confirm the following looks correct:"
stdout ""
stdout "Undercloud VM IP: ${UNDERCLOUD_IP}"
stdout "Undercloud user: ${UNDERCLOUD_USER}"
stdout ""

USER_INPUT=''

while [[ -z "${USER_INPUT}" ]]
do
  read -p "Are these values correct [Y/n]? " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT='Y'
  fi
  USER_INPUT=$(echo ${USER_INPUT} | tr '[:lower:]' '[:upper:]' | cut -c1 | egrep '(Y|N)')
done

if [[ "${USER_INPUT}" == 'N' ]]
then
  stdout ""
  stdout "Update the settings in ${DIRECTOR_TOOLS}/environment/undercloud.env and then re-run this script."
  stdout ""
  exit 2
fi

rm -f ${DIRECTOR_TOOLS}/logs/*undercloud_configure*log*
${DIRECTOR_TOOLS}/functions/undercloud/configure.sh

if [[ ! -z "$(ls ${DIRECTOR_TOOLS}/logs/*undercloud_configure*err* 2>/dev/null)" ]]
then
  stderr "There was an error configuring the undercloud."
  exit 300
fi

kvm_snapshot undercloud configure_undercloud_complete

stdout "At this point you should be ready to deploy your undercloud. You may want to review"
stdout "the undercloud.conf file in the ${UNDERCLOUD_USER} home directory before continuing."
stdout ""
stdout "When you're ready, you can either run the undercloud_deploy.sh script or execute"
stdout "the following on the undercloud VM as the ${UNDERCLOUD_USER}"
stdout ""
stdout "openstack undercloud install"
stdout ""
