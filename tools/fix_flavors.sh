#!/bin/bash

# This script will look at the nodes loaded into ironic
# and as long as the node name contains the associated flavor name
# this script will re-size the flavors to match the node config.


source ~/stackrc

for FLAVOR_NAME in $(nova flavor-list | egrep -v -- '(----|RXTX_Factor)' | awk '{print $4}')
do
  if [[ ! -z "$(ironic node-list | grep ${FLAVOR_NAME})" ]]
  then
    echo "Updating flavor: ${FLAVOR_NAME}"
    FLAVOR_VCPU=0
    FLAVOR_RAM=0
    FLAVOR_DISK=0

    NODE_UUID=$(ironic node-list | grep ${FLAVOR_NAME} | head -1 | awk '{print $2}')
    PROPERTY_DATA=$(ironic node-show ${NODE_UUID} --fields properties | awk -F\| '{print $3}' | egrep -v '(^ Value|^$)' | tr '\r\n' ' ' | sed 's/^  *//g;s/  *$//g;s/:  */:/g;s/,  */ /g')

    for PROPERTY in ${PROPERTY_DATA}
    do
      if [[ ! -z "$(echo ${PROPERTY} | grep "u'memory_mb'")" ]]
      then
        FLAVOR_RAM=$(echo ${PROPERTY} | awk -F: '{print $2}' | egrep -o '[0-9]*')
      elif [[ ! -z "$(echo ${PROPERTY} | grep "u'cpus'")" ]]
      then
        FLAVOR_VCPU=$(echo ${PROPERTY} | awk -F: '{print $2}' | egrep -o '[0-9]*')
      elif [[ ! -z "$(echo ${PROPERTY} | grep "u'local_gb'")" ]]
      then
        FLAVOR_DISK=$(echo ${PROPERTY} | awk -F: '{print $2}' | egrep -o '[0-9]*')
      fi
    done

    if [[ ${FLAVOR_RAM} -eq 0 || ${FLAVOR_VCPU} -eq 0 || ${FLAVOR_DISK} -eq 0 ]]
    then
      stderr "There was an error trying to configure the flavor for ${FLAVOR_NAME}."
      RC=$(( ${RC} + 1 ))
    else

      if [[ ! -z "$(nova flavor-show ${FLAVOR_NAME} 2>/dev/null)" ]]
      then
        echo "Deleting flavor: ${FLAVOR_NAME}"
        nova flavor-delete ${FLAVOR_NAME} | tee -a ${LOG}
        RC=$(( ${RC} + $? ))
      fi

      echo "Creating flavor: ${FLAVOR_NAME}"
      openstack flavor create --ram ${FLAVOR_RAM} --vcpus ${FLAVOR_VCPU} --disk ${FLAVOR_DISK} --public ${FLAVOR_NAME} | tee -a ${LOG}
      RC=$(( ${RC} + $? ))

      echo "Adding properties to flavor."
      openstack flavor set --property "cpu_arch"="x86_64" --property "capabilities:boot_option"="local" --property "capabilities:profile"="${FLAVOR_NAME}" ${FLAVOR_NAME}
      RC=$(( ${RC} + $? ))

    fi
  fi

done

