#!/bin/bash

if [[ "$(whoami)" != "root" ]]
then
  echo "WARNING: Expected this to be run as root."
  if [[ "$(sudo whoami)" != "root" ]]
  then
    echo 'Terminating script.'
    exit 1
  else
    echo "Verified user has sudo capabilities.  Will use sudo as needed."
    SUDO='sudo'
  fi
fi

# First, let's clean up the overcloud

NETWORK_LIST=''
if [[ ! -z "$(${SUDO} virsh list --all | egrep '(overcloud|undercloud)')" ]]
then
  for VM in $(${SUDO} virsh list --all | egrep '(overcloud|undercloud)' | awk '{print $2}')
  do
    USER_INPUT=''
    echo ""
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "Delete VM: ${VM} [Y/n]? " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT='Y'
      fi
      USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
    done
    echo ""
    if [[ "${USER_INPUT}" == 'Y' ]]
    then
      NETWORK_LIST="${NETWORK_LIST} $(${SUDO} virsh dumpxml ${VM} | grep 'source network' | awk -F\' '{print $2}' | tr '\r\n' ' ')"
      VM_DISKS=$(${SUDO} virsh dumpxml ${VM} | egrep 'source file=.*qcow2' | awk -F\' '{print $2}')      
      if [[ ! -z "$(${SUDO} virsh snapshot-list ${VM} | egrep -v -- '(----|Creation Time)')" ]]
      then
        echo "Cleaning snapshots."
        for SNAP in $(${SUDO} virsh snapshot-list ${VM} | egrep -v -- '(----|Creation Time)' | awk '{print $1}')
        do
          ${SUDO} virsh snapshot-delete ${VM} --snapshotname ${SNAP}
        done
      fi
      ${SUDO} virsh destroy ${VM} 2>/dev/null
      ${SUDO} virsh undefine ${VM}
      for QCOW in ${VM_DISKS}
      do
        if [[ ! -z "$(${SUDO} ls ${QCOW} 2>/dev/null)" ]]
        then
          echo "Deleting disk: ${QCOW}"
          ${SUDO} rm -f ${QCOW} 2>/dev/null
        fi
      done
    else
      echo "Keeping VM: ${VM}"
    fi
  done
fi

echo ""
echo "Checking if any of the networks can be cleaned up."
echo ""

NEW_NETWORK_LIST=','

for NETWORK in ${NETWORK_LIST}
do
  if [[ -z "$(echo ${NEW_NETWORK_LIST} | grep ,${NETWORK},)" ]]
  then
    NEW_NETWORK_LIST="${NEW_NETWORK_LIST},${NETWORK},"
  fi
done

NETWORK_LIST=$(echo ${NEW_NETWORK_LIST} | sed 's/,default,/,/g;s/,/ /g;s/^  *//g;s/  *$//g;s/  */ /g')
NETWORK_DELETE_LIST=''
for NETWORK in ${NETWORK_LIST}
do 
  DELETE_NETWORK='Y'
  for VM in $(${SUDO} virsh list --all | egrep -v '(-----|^ Id|^$)' | awk '{print $2}')
  do
    if [[ ! -z "$(${SUDO} virsh dumpxml ${VM} | grep 'source network' | grep ${NETWORK})" ]]
    then
      DELETE_NETWORK='N'
    fi
  done
  if [[ "${DELETE_NETWORK}" == 'Y' ]]
  then
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "Delete network: ${NETWORK} [Y/n]? " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT='Y'
      fi
      USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
    done
    if [[ "${USER_INPUT}" == 'Y' ]]
    then
      echo "Deleting network: ${NETWORK}"
      ${SUDO} virsh net-destroy ${NETWORK}
      ${SUDO} virsh net-undefine ${NETWORK} 
    fi
  fi
done
