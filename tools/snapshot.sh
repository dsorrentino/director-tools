#!/bin/bash

SNAP_ID=""

while [[ -z "${SNAP_ID}" ]]
do
  read -p "REQUIRED: Identifier for the snapshot: " SNAP_ID
done

SNAP_ID=$(echo ${SNAP_ID} | sed 's/ /-/g')

for VM_TYPE in undercloud ceph control compute
do
  for VM in $(sudo virsh list --all | grep ${VM_TYPE} | awk '{print $2}')
  do
    echo "Snapping ${VM}"
    sudo virsh snapshot-create-as ${VM} ${SNAP_ID}
    sudo virsh snapshot-list ${VM}
    echo ""
  done
done

