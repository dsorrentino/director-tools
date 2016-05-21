#!/bin/bash

# This script will tag nodes according to their role provided their role is contained
# within their name

source ~/stackrc

for FLAVOR_NAME in $(nova flavor-list | egrep -v -- '(----|RXTX_Factor)' | awk '{print $4}')
do
  if [[ ! -z "$(ironic node-list | grep ${FLAVOR_NAME})" ]]
  then
    for NODE_DATA in $(ironic node-list | grep ${FLAVOR_NAME} | awk '{print $2","$4}')
    do
      UUID=$(echo ${NODE_DATA} | awk -F, '{print $1}')
      NODE_NAME=$(echo ${NODE_DATA} | awk -F, '{print $2}')
      echo "Tagging node '${NODE_NAME}' as node type: ${FLAVOR_NAME}"
      ironic node-update ${UUID} add properties/capabilities="profile:${FLAVOR_NAME},boot_option:local"
    done
  fi
done
