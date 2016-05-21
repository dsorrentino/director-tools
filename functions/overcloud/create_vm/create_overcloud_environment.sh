#!/bin/bash

source ${DIRECTOR_TOOLS}/environment/undercloud.env
source ${DIRECTOR_TOOLS}/environment/overcloud.env
source ${DIRECTOR_TOOLS}/functions/common.sh

SCRIPT_NAME=create_overcloud_vms

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log


LIBVIRT_IMAGE_DIR=/var/lib/libvirt/images

SUDO=''
if [[ "$(whoami)" != "root" ]]
then
  stdout "WARNING: Expected this to be run as root."
  if [[ "$(sudo whoami)" != "root" ]]
  then
    stderr 'Terminating deployment.'
    exit 1
  else
    stdout "Verified user has sudo capabilities.  Will use sudo as needed."
    SUDO="sudo"
  fi
fi

if [[ -z "${NETWORK_LIST}" ]]
then
  NETWORK_LIST=provisioning
else
  if [[ -z "$(echo ${NETWORK_LIST} | grep provisioning)" ]]
  then
    NETWORK_LIST="${NETWORK_LIST},provisioning"
  fi
fi


stdout "Deployment of the overcloud requires at least 2 networks, one of them being the provisioning"
stdout "network.  This is the current list of networks saved for the overcloud:"
stdout ""
stdout "${NETWORK_LIST}"
stdout ""

USER_INPUT=''
if [[ $(echo ${NETWORK_LIST} | sed 's/,/ /g' | wc -w) -ge 2 ]]
then
  stdout "You meet the minimum required networks."
else
  stdout "You do not meet the minimum required networks."
  while [[ $(echo ${NETWORK_LIST} | sed 's/,/ /g' | wc -w) -lt 2 ]]
  do
    USER_INPUT=''
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter the name of the new network: " USER_INPUT
    if [[ ! -z "${USER_INPUT}" ]]
    then
      NETWORK_LIST="${NETWORK_LIST},${USER_INPUT}"
    fi
  done
fi

stdout ""


stdout "First validate the current list of networks.  You'll be prompted to add new"
stdout "networks afterwards."
stdout ""
stdout "The following is a list of networks defined for the overcloud."
stdout ""
NEW_NETWORK_LIST=''
REMOVED_NETWORK_LIST=''
USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  stdout "Overcloud networks: $(echo ${NETWORK_LIST})"
  stdout ""
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Did you want to remove any of these networks [y/N]? " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT='N'
  fi
  USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
  if [[ "${USER_INPUT}" == 'Y' ]]
  then
    for NETWORK_NAME in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
    do
      if [[ "${NETWORK_NAME}" == "provisioning" ]]
      then
        stdout "Network: '${NETWORK_NAME}' **REQUIRED NETWORK, CAN NOT REMOVE**"
        NEW_NETWORK_LIST="${NEW_NETWORK_LIST} provisioning"
      else
        USER_INPUT=''
        while [[ -z "${USER_INPUT}" ]]
        do
          read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Network: '${NETWORK_NAME}' Keep or Delete [K/d]? " USER_INPUT
          if [[ -z "${USER_INPUT}" ]]
          then
            USER_INPUT='K'
          fi
          USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(K|D)')
          if [[ "${USER_INPUT}" == 'K' ]]
          then
            NEW_NETWORK_LIST="${NEW_NETWORK_LIST} ${NETWORK_NAME}"
          else
            REMOVED_NETWORK_LIST="${REMOVED_NETWORK_LIST} ${NETWORK_NAME}"
          fi
        done
      fi
    done
    stdout ""
    NETWORK_LIST=$(echo ${NEW_NETWORK_LIST} | sed 's/^  *//g;s/  *$//g;s/  */,/g')
    USER_INPUT=''
  fi
done

USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  stdout ""
  stdout "Overcloud networks: $(echo ${NETWORK_LIST})"
  stdout ""
  if [[ $(echo ${NETWORK_LIST} | sed 's/,/ /g' | wc -w) -lt 2 ]]
  then
    stdout "You do not meet the required minimum number of networks.  You must add some."
    USER_INPUT='Y'
  else
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Add an additional network [y/N]? " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT='N'
    fi
    USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
  fi
  while [[ "${USER_INPUT}" == 'Y' ]]
  do
    USER_INPUT=''
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter the name of the new network [BLANK TO EXIT]: " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT='DONE'
    else
      NETWORK_LIST="${NETWORK_LIST},${USER_INPUT}"
      USER_INPUT=''
    fi
  done
  if [[ $(echo ${NETWORK_LIST} | sed 's/,/ /g' | wc -w) -lt 2 ]]
  then
    USER_INPUT=''
  fi
done

for NETWORK_NAME in $(echo " ${REMOVED_NETWORK_LIST} " | sed 's/ provisioning //g;s/ default //g')
do
  if [[ ! -z "$(${SUDO} virsh net-list ${NETWORK_NAME} 2>/dev/null)" ]]
  then
    stdout "Deleting network: ${NETWORK_NAME}"
    stdout "$(${SUDO} virsh net-destroy ${NETWORK_NAME} 2>&1)"
    stdout "$(${SUDO} virsh net-undefine ${NETWORK_NAME} 2>&1)"
  else
    stdout "Deleting network: ${NETWORK_NAME} (did not exist)"
  fi
  SUBNET_VAR="NETWORK_$(echo ${NETWORK_NAME} | tr '[:lower:]' '[:upper:]')_SUBNET"
  sed -i "/^${SUBNET_VAR}=/d" ${DIRECTOR_TOOLS}/environment/overcloud.env
done

# Remove the provisioning network from the overcloud
# configuration since that was created as part of
# the undercloud
NETWORK_LIST=$(echo ",${NETWORK_LIST}," | sed 's/,provisioning,/,/g' | sed 's/,/ /g;s/^  *//g;s/  *$//g;s/  */,/g')
sed -i "s/^NETWORK_LIST=.*/NETWORK_LIST=${NETWORK_LIST}/" ${DIRECTOR_TOOLS}/environment/overcloud.env

for NETWORK_NAME in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
do
  SUBNET_VAR="NETWORK_$(echo ${NETWORK_NAME} | tr '[:lower:]' '[:upper:]')_SUBNET"
  if [[ -z "$(grep "^${SUBNET_VAR}=" ${DIRECTOR_TOOLS}/environment/overcloud.env)" ]]
  then
    echo "${SUBNET_VAR}=" >> ${DIRECTOR_TOOLS}/environment/overcloud.env
  fi
done

for NETWORK_NAME in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
do
  if [[ ! -z "$(${SUDO} virsh net-info ${NETWORK_NAME} 2>/dev/null)" ]]
  then
    stdout "WARNING: Network '${NETWORK_NAME}' already exists."
    stdout "XML:"
    stdout ""
    ${SUDO} virsh net-dumpxml ${NETWORK_NAME}
    stdout ""
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Network: '${NETWORK_NAME}' Keep or Delete [K/d]? " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT='K'
      fi
      USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(K|D)')
      if [[ "${USER_INPUT}" == 'D' ]]
      then
        stdout "Deleting network: ${NETWORK_NAME}"
        stdout "$(${SUDO} virsh net-destroy ${NETWORK_NAME} 2>&1)"
        stdout "$(${SUDO} virsh net-undefine ${NETWORK_NAME} 2>&1)"
      else
        stdout "Updating CIDR settings for ${NETWORK_NAME} to match existing network."
        ${SUDO} virsh net-dumpxml ${NETWORK_NAME} >/tmp/${NETWORK_NAME}.xml
        SUBNET_VAR="NETWORK_$(echo ${NETWORK_NAME} | tr '[:lower:]' '[:upper:]')_SUBNET"
        SUBNET=$(grep 'ip address' /tmp/${NETWORK_NAME}.xml | awk -F\' '{print $2}')
        NETMASK=$(grep 'ip address' /tmp/${NETWORK_NAME}.xml | awk -F\' '{print $4}')
        NETMASK=$(mask2cidr ${NETMASK})
        stdout "CIDR for network '${NETWORK_NAME}': ${SUBNET}/${NETMASK}"
        sed -i "s|^${SUBNET_VAR}=.*|${SUBNET_VAR}=${SUBNET}/${NETMASK}|" ${DIRECTOR_TOOLS}/environment/overcloud.env
      fi
    done
  fi
  SUBNET_VAR=''
  SUBNET=''
  if [[ -z "$(${SUDO} virsh net-info ${NETWORK_NAME} 2>/dev/null)" ]]
  then
    USER_INPUT=''
    SUBNET_VAR="NETWORK_$(echo ${NETWORK_NAME} | tr '[:lower:]' '[:upper:]')_SUBNET"
    SUBNET=$(eval echo \$${SUBNET_VAR})
    DEFAULT=''
    if [[ ! -z "${SUBNET}" ]]
    then
      DEFAULT="[${SUBNET}]"
    fi
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter CIDR for network: '${NETWORK_NAME}' ${DEFAULT}? " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${SUBNET}
      fi
      #  Very rudimentary CIDR pattern matching
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,3}')
      if [[ -z "${USER_INPUT}" ]]
      then
        stdout "Invalid CIDR entered."
      fi
    done
    eval "${SUBNET_VAR}='${USER_INPUT}'"
    sed -i "s|^${SUBNET_VAR}=.*|${SUBNET_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/environment/overcloud.env
  fi
done

stdout ""
stdout "Creating networks."
stdout ""

for NETWORK in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
do
  SUBNET="NETWORK_$(echo ${NETWORK} | tr '[:lower:]' '[:upper:]')_SUBNET"
  SUBNET=$(eval echo \$${SUBNET})
  NETMASK=$(echo ${SUBNET} | awk -F/ '{print $2}')
  SUBNET=$(echo ${SUBNET} | awk -F/ '{print $1}')
  NETMASK=$(cidr2mask ${NETMASK})
  IP_ADDRESS=${SUBNET}
  if [[ $(echo ${IP_ADDRESS} | awk -F\. '{print $NF}') -eq 0 ]]
  then
    IP_ADDRESS=$(echo ${IP_ADDRESS} | awk -F\. '{print $1"."$2"."$3".1"}')
  fi

if [[ "${NETWORK}" == "${NETWORK_TYPE[External]}" || "${NETWORK}" == "${NETWORK_TYPE[FloatingIP]}" ]]
then
cat > /tmp/${NETWORK}.xml <<EOF
<network>
  <name>${NETWORK}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='${IP_ADDRESS}' netmask='${NETMASK}'/>
</network>
EOF

else
cat > /tmp/${NETWORK}.xml <<EOF
<network>
  <name>${NETWORK}</name>
  <ip address="${SUBNET}" netmask="${NETMASK}"/>
</network>
EOF
fi

  if [[ -z "$(${SUDO} virsh net-info ${NETWORK} 2>/dev/null)" ]]
  then
    stdout "Creating network: ${NETWORK}"
    stdout "$(${SUDO} virsh net-define /tmp/${NETWORK}.xml)"
    stdout "$(${SUDO} virsh net-autostart ${NETWORK})"
    stdout "$(${SUDO} virsh net-start ${NETWORK})"
  else
    stdout "Network '${NETWORK}' already exists."
  fi

done

if [[ ! -z "$(${SUDO} virsh list --all | grep overcloud)" ]]
then
  stdout "There are existing virtual machines which appear to be overcloud"
  stdout "virtual machines as they have 'overcloud' in the name:"
  stdout ""
  ${SUDO} virsh list --all | egrep -- "(^ Id|----|overcloud)"
  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Did you want to delete these before continuing [Y/n]? " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT='Y'
    fi
    USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
    if [[ "${USER_INPUT}" == 'Y' ]]
    then
      for VM in $(${SUDO} virsh list --all | grep overcloud | awk '{print $2}')
      do
        USER_INPUT=''
        while [[ -z "${USER_INPUT}" ]]
        do
          read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] VM: ${VM} Delete [Y/n]? " USER_INPUT
          if [[ -z "${USER_INPUT}" ]]
          then
            USER_INPUT='Y'
          fi
          USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
          if [[ "${USER_INPUT}" == 'Y' ]]
          then
            stdout "Deleting: ${VM}"
            VM_DISKS=$(${SUDO} virsh dumpxml ${VM} | egrep 'source file=.*qcow2' | awk -F\' '{print $2}')
            stdout "$(${SUDO} virsh destroy ${VM} 2>/dev/null)"
            stdout "$(${SUDO} virsh undefine ${VM})"
            for QCOW in ${VM_DISKS}
            do
              if [[ ! -z "$(${SUDO} ls ${QCOW} 2>/dev/null)" ]]
              then
                stdout "Deleting disk: ${QCOW}"
                ${SUDO} rm -f ${QCOW} 2>/dev/null
              fi
            done
          fi
        done
      done
    fi
  done
fi

if [[ ! -z "$(${SUDO} ls ${LIBVIRT_IMAGE_DIR}/ | grep overcloud 2>/dev/null)" ]]
then
  stdout "Cleaning images."
  ${SUDO} rm -f ${LIBVIRT_IMAGE_DIR}/*overcloud*
fi

stdout ""

declare -A QUESTION
for NODE_TYPE in controller compute ceph 
do
  QUESTION[COUNT]="How many ${NODE_TYPE} nodes should be in the overcloud"
  QUESTION[VCPU]="How many VCPU's should each ${NODE_TYPE} node be configured with (must be greater than 0)"
  QUESTION[RAM]="How much RAM (in MB) should each ${NODE_TYPE} node be configured with (must be greater than 0, number only)"
  QUESTION[DISK_COUNT]="How many disks should each ${NODE_TYPE} node be configured with (must be greater than 0)"
  QUESTION[DISK_SIZE]="What is the size (in GB) of each disk in each ${NODE_TYPE} node (must be greater than 0, number only)"
  QUESTION[NIC_PORTS]="How many NIC ports in each ${NODE_TYPE} node (must be 2 or greater)"

  if [[ "${NODE_TYPE}" == "ceph" ]]
  then
    QUESTION[DISK_COUNT]="How many disks should each ${NODE_TYPE} node be configured with (must be greater than 0, exclude OSDs)"
    QUESTION[DISK_SIZE]="What is the size (in GB) of each disk in each ${NODE_TYPE} node (must be greater than 0, number only, exclude OSDs)"
  fi

  SKIP_CONFIG='N'

  stdout ""
  stdout "Configure: ${NODE_TYPE}"
  stdout ""
  for SETTING in COUNT VCPU RAM DISK_COUNT DISK_SIZE NIC_PORTS
  do
    if [[ "${SKIP_CONFIG}" == 'N' ]]
    then
      NODE_SETTING="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_${SETTING}"
      DEFAULT_SETTING=$(eval echo \$${NODE_SETTING})
      USER_INPUT=''
      USER_QUESTION=${QUESTION[${SETTING}]}
      while [[ -z "${USER_INPUT}" ]]
      do
        read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] ${USER_QUESTION} [${DEFAULT_SETTING}]: " USER_INPUT
        if [[ -z "${USER_INPUT}" ]]
        then
          USER_INPUT=${DEFAULT_SETTING}
        fi
        USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9][0-9]*')
        if [[ ! -z "${USER_INPUT}" ]]
       then
          if [[ "${SETTING}" == "NIC_PORTS" && ${USER_INPUT} -lt 2 ]]
          then
            USER_INPUT=''
          fi
          if [[ ${USER_INPUT} -eq 0 ]]
          then
            if [[ "${SETTING}" == "COUNT" ]]
            then
              SKIP_CONFIG='Y'
            else
              USER_INPUT=''
            fi
          fi
        fi
      done
  
      stdout "Setting ${NODE_TYPE} node $(echo ${SETTING} | tr '[:upper:]' '[:lower:]') to: ${USER_INPUT}"
      sed -i "s|^${NODE_SETTING}=.*|${NODE_SETTING}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/environment/overcloud.env

    fi
  done
done

source ${DIRECTOR_TOOLS}/environment/overcloud.env

if [[ ${CEPH_COUNT} -gt 0 ]]
then
  NODE_TYPE='ceph'
  QUESTION[OSD_DISK_COUNT]="How many OSD drives should each of the ${NODE_TYPE} nodes have (must be greater than 0)"
  QUESTION[OSD_DISK_SIZE]="What is the size (in GB) of each OSD disk in each ${NODE_TYPE} node (must be greater than 0, number only)"
  for SETTING in OSD_DISK_COUNT OSD_DISK_SIZE
  do
    NODE_SETTING="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_${SETTING}"
    DEFAULT_SETTING=$(eval echo \$${NODE_SETTING})
    USER_INPUT=''
    USER_QUESTION=${QUESTION[${SETTING}]}
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] ${USER_QUESTION} [${DEFAULT_SETTING}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${DEFAULT_SETTING}
      fi
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[1-9][0-9]*')
    done

    stdout "Setting ${NODE_TYPE} node $(echo ${SETTING} | tr '[:upper:]' '[:lower:]') to: ${USER_INPUT}"
    sed -i "s|^${NODE_SETTING}=.*|${NODE_SETTING}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/environment/overcloud.env

  done
fi

source ${DIRECTOR_TOOLS}/environment/overcloud.env


DATE=$(date +'%Y%m%d-%H%M')

stdout ""
stdout "Creating disk images for Virtual Machines."
stdout ""

for NODE_TYPE in controller compute ceph 
do
  COUNT="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_COUNT"
  COUNT=$(eval echo \$${COUNT})
  DISK_COUNT="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_DISK_COUNT"
  DISK_COUNT=$(eval echo \$${DISK_COUNT})
  DISK_SIZE="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_DISK_SIZE"
  DISK_SIZE=$(eval echo \$${DISK_SIZE})

  if [[ ${COUNT} -gt 0 ]]
  then
    for X in $(seq 1 ${COUNT})
    do
      for Y in $(seq 1 ${DISK_COUNT})
      do
       ${SUDO} qemu-img create -f qcow2 -o preallocation=metadata ${LIBVIRT_IMAGE_DIR}/overcloud-${NODE_TYPE}${X}-${Y}-${DATE}.qcow2 ${DISK_SIZE}G
      done
    done
  fi
done


if [[ ${CEPH_COUNT} -gt 0 ]]
then
  stdout ""
  stdout "Creating disk images for OSD drives"
  stdout ""
  for X in $(seq 1 ${CEPH_COUNT})
  do
    for Y in $(seq 1 ${CEPH_OSD_DISK_COUNT})
    do
     ${SUDO} qemu-img create -f qcow2 -o preallocation=metadata ${LIBVIRT_IMAGE_DIR}/overcloud-ceph${X}-osd${Y}-${DATE}.qcow2 ${CEPH_OSD_DISK_SIZE}G
    done
  done
fi

declare -A NETWORK_CONNECTIONS

for NODE_TYPE in controller compute ceph 
do
  NETWORK_CONNECTIONS[${NODE_TYPE}]=''
done

for NODE_TYPE in controller compute ceph 
do
  NODE_COUNT="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_COUNT"
  NODE_COUNT=$(eval echo \$${NODE_COUNT})
  if [[ ${NODE_COUNT} -gt 0 ]]
  then
    stdout ""
    stdout "Configure the NIC ports for '${NODE_TYPE}' nodes."
    stdout ""
    NIC_COUNT="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_NIC_PORTS"
    NIC_COUNT=$(eval echo \$${NIC_COUNT})
    NIC_COUNT=$(( ${NIC_COUNT} - 1 ))
    for ETH in $(seq 0 ${NIC_COUNT})
    do
      USER_INPUT=''
      while [[ -z "${USER_INPUT}" ]]
      do
        stdout "For all ${NODE_TYPE} nodes, connect eth${ETH} to:"
        stdout ""
        NET_INDEX=1
        for NETWORK in provisioning $(echo ${NETWORK_LIST} | sed 's/,/ /g')
        do
          echo "[$(date +'%Y/%m/%d-%H:%M:%S')] ${NET_INDEX} - ${NETWORK}"
          NET_INDEX=$(( ${NET_INDEX} + 1 ))
        done
        stdout ""
  
        read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] For all ${NODE_TYPE} nodes, connect eth${ETH} to: " USER_INPUT
        USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9][0-9]*')
        if [[ ${USER_INPUT} -lt 1 || ${USER_INPUTE} -ge ${NET_INDEX} ]]
        then
          USER_INPUT=''
        fi
      done
      NET_INDEX=1
      for NETWORK in provisioning $(echo ${NETWORK_LIST} | sed 's/,/ /g')
      do
        if [[ ${NET_INDEX} -eq ${USER_INPUT} ]]
        then
          stdout ""
          stdout "Connecting eth${ETH} to ${NETWORK}."
          stdout ""
          NETWORK_CONNECTIONS[${NODE_TYPE}]="${NETWORK_CONNECTIONS[${NODE_TYPE}]} ${NETWORK}"
        fi
        NET_INDEX=$(( ${NET_INDEX} + 1 ))
      done
    done
  fi
done

stdout ""
stdout "Creating Virtual Machines."
stdout ""

if [[ ${CONTROLLER_COUNT} -gt 0 ]]
then
  NET_LIST=''
  for NETWORK in ${NETWORK_CONNECTIONS[controller]}
  do
    NET_LIST="${NET_LIST} --network network:${NETWORK}"
  done

  for X in $(seq 1 ${CONTROLLER_COUNT})
  do
    DISKS=''
    for Y in $(seq 1 ${CONTROLLER_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-controller${X}-${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    ${SUDO} virt-install --ram ${CONTROLLER_RAM} --vcpus ${CONTROLLER_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NET_LIST} --name overcloud-controller${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-controller${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-controller${X}-${DATE}.xml
  done
fi

if [[ ${COMPUTE_COUNT} -gt 0 ]]
then
  NET_LIST=''
  for NETWORK in ${NETWORK_CONNECTIONS[compute]}
  do
    NET_LIST="${NET_LIST} --network network:${NETWORK}"
  done

  for X in $(seq 1 ${COMPUTE_COUNT})
  do
    DISKS=''
    for Y in $(seq 1 ${COMPUTE_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-compute${X}-${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    ${SUDO} virt-install --ram ${COMPUTE_RAM} --vcpus ${COMPUTE_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NET_LIST} --name overcloud-compute${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-compute${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-compute${X}-${DATE}.xml
  done
fi

if [[ ${CEPH_COUNT} -gt 0 ]]
then
  NET_LIST=''
  for NETWORK in ${NETWORK_CONNECTIONS[ceph]}
  do
    NET_LIST="${NET_LIST} --network network:${NETWORK}"
  done

  for X in $(seq 1 ${CEPH_COUNT})
  do
    DISKS=''
    for Y in $(seq 1 ${CEPH_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-ceph${X}-${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    for Y in $(seq 1 ${CEPH_OSD_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-ceph${X}-osd${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    ${SUDO} virt-install --ram ${CEPH_RAM} --vcpus ${CEPH_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NET_LIST} --name overcloud-ceph${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-ceph${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-ceph${X}-${DATE}.xml
  done
fi

source ${DIRECTOR_TOOLS}/environment/undercloud.env
KVM_IP=${UNDERCLOUD_GATEWAY}

cat /dev/null > ${DIRECTOR_TOOLS}/run/overcloud-servers.txt
for VM in $(${SUDO} virsh list --all | grep overcloud.*${DATE} | awk '{print $2}')
do
  MAC=$(${SUDO} virsh domiflist ${VM} | awk '/provisioning/ {print $5}' | head -1);
  echo "${VM}|${KVM_IP}|${MAC}|${LIBVIRT_USER}" >>${DIRECTOR_TOOLS}/run/overcloud-servers.txt
done

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
