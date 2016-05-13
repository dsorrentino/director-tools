#!/bin/bash

SCRIPT_NAME=create_overcloud_vms

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

source ${DIRECTOR_TOOLS}/config/undercloud.env

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
  sed -i "/^${SUBNET_VAR}=/d" ${DIRECTOR_TOOLS}/config/overcloud.env
done

# Remove the provisioning network from the overcloud
# configuration since that was created as part of
# the undercloud
NETWORK_LIST=$(echo ",${NETWORK_LIST}," | sed 's/,provisioning,/,/g' | sed 's/,/ /g;s/^  *//g;s/  *$//g;s/  */,/g')
sed -i "s/^NETWORK_LIST=.*/NETWORK_LIST=${NETWORK_LIST}/" ${DIRECTOR_TOOLS}/config/overcloud.env

for NETWORK_NAME in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
do
  SUBNET_VAR="NETWORK_$(echo ${NETWORK_NAME} | tr '[:lower:]' '[:upper:]')_SUBNET"
  if [[ -z "$(grep "^${SUBNET_VAR}=" ${DIRECTOR_TOOLS}/config/overcloud.env)" ]]
  then
    echo "${SUBNET_VAR}=" >> ${DIRECTOR_TOOLS}/config/overcloud.env
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
        sed -i "s|^${SUBNET_VAR}=.*|${SUBNET_VAR}=${SUBNET}/${NETMASK}|" ${DIRECTOR_TOOLS}/config/overcloud.env
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
    sed -i "s|^${SUBNET_VAR}=.*|${SUBNET_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/config/overcloud.env
  fi
done

source ${DIRECTOR_TOOLS}/config/overcloud.env

declare -A NETWORK_TYPE

NETWORK_TYPE[InternalAPI]=''
NETWORK_TYPE[InternalAPI_desc]='The Internal API network is used for communication between the OpenStack services via API communication, RPC messages, and database communication. '
NETWORK_TYPE[Tenant]=''
NETWORK_TYPE[Tenant_desc]='Neutron provides each tenant with their own networks using either VLAN segregation, where each tenant network is a network VLAN, or tunneling through VXLAN or GRE. Network traffic is isolated within each tenant network. Each tenant network has an IP subnet associated with it, and multiple tenant networks may use the same addresses.'
NETWORK_TYPE[Storage]=''
NETWORK_TYPE[Storage_desc]='Block Storage, NFS, iSCSI, and others. Ideally, this would be isolated to an entirely separate switch fabric for performance reasons.'
NETWORK_TYPE[StorageMgmt]=''
NETWORK_TYPE[StorageMgmt_desc]='OpenStack Object Storage (swift) uses this network to synchronize data objects between participating replica nodes. The proxy service acts as the intermediary interface between user requests and the underlying storage layer. The proxy receives incoming requests and locates the necessary replica to retrieve the requested data. Services that use a Ceph backend connect over the Storage Management network, since they do not interact with Ceph directly but rather use the frontend service. Note that the RBD driver is an exception; this traffic connects directly to Ceph.'
NETWORK_TYPE[External]=''
NETWORK_TYPE[External_desc]='Hosts the OpenStack Dashboard (horizon) for graphical system management, Public APIs for OpenStack services, and performs SNAT for incoming traffic destined for instances. If the external network uses private IP addresses (as per RFC-1918), then further NAT must be performed for traffic originating from the internet. '
NETWORK_TYPE[FloatingIP]=''
NETWORK_TYPE[FloatingIP_desc]='Allows incoming traffic to reach instances using 1-to-1 IP address mapping between the floating IP address, and the IP address actually assigned to the instance in the tenant network. If hosting the Floating IPs on a VLAN separate from External, trunk the Floating IP VLAN to the Controller nodes and add the VLAN through Neutron after Overcloud creation. This provides a means to create multiple Floating IP networks attached to multiple bridges. The VLANs are trunked but not configured as interfaces. Instead, Neutron creates an OVS port with the VLAN segmentation ID on the chosen bridge for each Floating IP network. '

stdout ""
stdout "To implement network isolation, you need to associate each KVM network with a specific Network Type."
stdout "Details on network types can be found here:"
stdout ""
stdout "http://docs.openstack.org/developer/tripleo-docs/advanced_deployment/network_isolation.html"
stdout ""
stdout "If you don't wish to isolate traffic, feel free to select the same KVM network for multiple Network Types."
stdout ""

if [[ $(echo ${NETWORK_LIST} | sed 's/,/ /g' | wc -w) -eq 1 ]]
then
  for NET_TYPE in InternalAPI Tenant Storage StorageMgmt External FloatingIP
  do
    stdout "Setting '${NET_TYPE}' network to use '${NETWORK_LIST}'."
    NETWORK_TYPE[${NET_TYPE}]=${NETWORK_LIST}
  done
else
  for NET_TYPE in InternalAPI Tenant Storage StorageMgmt External FloatingIP
  do
    stdout ""
    stdout "== ${NET_TYPE} =="
    stdout ""
    while [[ -z "${NETWORK_TYPE[${NET_TYPE}]}" ]]
    do
      DEFAULT=''
      stdout ""
      X=0
      for NETWORK in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
      do
        X=$(( ${X} + 1 ))
        stdout "[${X}] ${NETWORK}"
        if [[ "$(echo ${NETWORK} | tr '[:upper:]' '[:lower:'])" == "$(echo ${NET_TYPE} | tr '[:upper:]' '[:lower:'])" ]]
        then
          DEFAULT=${X}
        fi
      done
      stdout ""
      USER_INPUT=''
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Select a KVM network 1-${X} for the ${NET_TYPE} network or enter I for additional information on the network type [${DEFAULT}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${DEFAULT}
      fi
      USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]')
      if [[ "${USER_INPUT}" == 'I' ]]
      then
        stdout ""
        stdout "============================================================="
        stdout "${NET_TYPE} description: ${NETWORK_TYPE[${NET_TYPE}_desc]}"
        stdout "============================================================="
        stdout ""
      fi
      USER_INPUT=$(echo ${USER_INPUT} | egrep -o '^[1-9][0-9]*')
      if [[ ! -z "${USER_INPUT}" ]]
      then
        if [[ ${USER_INPUT} -ge 1 && ${USER_INPUT} -le ${X} ]]
        then
          X=0
          for NETWORK in $(echo ${NETWORK_LIST} | sed 's/,/ /g')
          do
            X=$(( ${X} + 1 ))
            if [[ ${X} -eq ${USER_INPUT} ]]
            then
              NETWORK_TYPE[${NET_TYPE}]=${NETWORK}
            fi
          done
        fi
      fi
    done
  done
fi

stdout ""

for NET_TYPE in InternalAPI Tenant Storage StorageMgmt External FloatingIP
do
  stdout "Network type ${NET_TYPE} set to use ${NETWORK_TYPE[${NET_TYPE}]}."
done

stdout ""
stdout "These networks will be plumbed to the following node types:"
stdout ""

declare -A NETWORK_MAP

NETWORK_MAP[controller]='External InternalAPI Tenant Storage StorageMgmt FloatingIP'
NETWORK_MAP[compute]='InternalAPI Tenant Storage'
NETWORK_MAP[ceph]='InternalAPI Storage StorageMgmt'

NETWORK_TYPE[controller]=''
NETWORK_TYPE[compute]=''
NETWORK_TYPE[ceph]=''

for NODE_TYPE in controller compute ceph
do
  stdout "Node type: ${NODE_TYPE}"
  stdout "Network types: ${NETWORK_MAP[${NODE_TYPE}]}"
  for NET_TYPE in ${NETWORK_MAP[${NODE_TYPE}]}
  do
    stdout "KVM Network: ${NETWORK_TYPE[${NET_TYPE}]} (${NET_TYPE})"
  done
  stdout ""
  stdout "Besides the networks listed above, do you want any additional"
  stdout "networks connected to this VM, such as a network connection for a"
  stdout "provider network."
  stdout ""

  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Connect an additional network to all ${NODE_TYPE} nodes [y/N]? " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT='N'
    fi
    USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
    if [[ "${USER_INPUT}" == 'Y' ]]
    then
     stdout ""
      X=0
      for NETWORK in $(${SUDO} virsh net-list --all | egrep -v -- '(Autostart|------|^$)' | awk '{print $1}' | sort -u)
      do
        X=$(( ${X} + 1 ))
        stdout "[${X}] ${NETWORK}"
      done
      stdout ""
      USER_INPUT=''
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Select network (1-${X})? " USER_INPUT
      USER_INPUT=$(echo ${USER_INPUT} | egrep -o '^[1-9][0-9]*')
      if [[ ! -z "${USER_INPUT}" ]]
      then
        if [[ ${USER_INPUT} -ge 1 && ${USER_INPUT} -le ${X} ]]
        then
          X=0
          for NETWORK in $(${SUDO} virsh net-list --all | egrep -v -- '(Autostart|------|^$)' | awk '{print $1}' | sort -u)
          do
            X=$(( ${X} + 1 ))
            if [[ ${X} -eq ${USER_INPUT} ]]
            then
              stdout "Attaching ${NETWORK} to all ${NODE_TYPE} nodes."
              NETWORK_TYPE[${NODE_TYPE}]="${NETWORK_TYPE[${NODE_TYPE}]} ${NETWORK}"
            fi
          done
          USER_INPUT=''
        fi
      fi
      stdout ""
    fi
  done
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
  if [[ "${NODE_TYPE}" == "ceph" ]]
  then
    QUESTION[DISK_COUNT]="How many disks should each ${NODE_TYPE} node be configured with (must be greater than 0, exclude OSDs)"
    QUESTION[DISK_SIZE]="What is the size (in GB) of each disk in each ${NODE_TYPE} node (must be greater than 0, number only, exclude OSDs)"
  fi

  SKIP_CONFIG='N'

  stdout ""
  stdout "Configure: ${NODE_TYPE}"
  stdout ""
  for SETTING in COUNT VCPU RAM DISK_COUNT DISK_SIZE
  do
    if [[ "${SKIP_CONFIG}" == 'N' ]]
    then
      COUNT_VAR="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_${SETTING}"
      DEFAULT_COUNT=$(eval echo \$${COUNT_VAR})
      USER_INPUT=''
      USER_QUESTION=${QUESTION[${SETTING}]}
      while [[ -z "${USER_INPUT}" ]]
      do
        read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] ${USER_QUESTION} [${DEFAULT_COUNT}]: " USER_INPUT
        if [[ -z "${USER_INPUT}" ]]
        then
          USER_INPUT=${DEFAULT_COUNT}
        fi
        USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9][0-9]*')
        if [[ ${USER_INPUT} -eq 0 ]]
        then
          if [[ "${SETTING}" == "COUNT" ]]
          then
            SKIP_CONFIG='Y'
          else
            USER_INPUT=''
          fi
        fi
      done
  
      stdout "Setting ${NODE_TYPE} node $(echo ${SETTING} | tr '[:upper:]' '[:lower:]') to: ${USER_INPUT}"
      sed -i "s|^${COUNT_VAR}=.*|${COUNT_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/config/overcloud.env

    fi
  done
done

source ${DIRECTOR_TOOLS}/config/overcloud.env

if [[ ${CEPH_COUNT} -gt 0 ]]
then
  NODE_TYPE='ceph'
  QUESTION[OSD_DISK_COUNT]="How many OSD drives should each of the ${NODE_TYPE} nodes have (must be greater than 0)"
  QUESTION[OSD_DISK_SIZE]="What is the size (in GB) of each OSD disk in each ${NODE_TYPE} node (must be greater than 0, number only)"
  for SETTING in OSD_DISK_COUNT OSD_DISK_SIZE
  do
    COUNT_VAR="$(echo ${NODE_TYPE} | tr '[:lower:]' '[:upper:]')_${SETTING}"
    DEFAULT_COUNT=$(eval echo \$${COUNT_VAR})
    USER_INPUT=''
    USER_QUESTION=${QUESTION[${SETTING}]}
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] ${USER_QUESTION} [${DEFAULT_COUNT}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${DEFAULT_COUNT}
      fi
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[1-9][0-9]*')
    done

    stdout "Setting ${NODE_TYPE} node $(echo ${SETTING} | tr '[:upper:]' '[:lower:]') to: ${USER_INPUT}"
    sed -i "s|^${COUNT_VAR}=.*|${COUNT_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/config/overcloud.env

  done
fi

source ${DIRECTOR_TOOLS}/config/overcloud.env


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

stdout ""
stdout "Creating Virtual Machines."
stdout ""

if [[ ${CONTROLLER_COUNT} -gt 0 ]]
then
  NET_LIST=${NETWORK_TYPE[External]}
  for NET_TYPE in InternalAPI Tenant Storage StorageMgmt FloatingIP
  do
    if [[ -z "$(echo ${NET_LIST} | grep ${NETWORK_TYPE[${NET_TYPE}]})" ]]
    then
      NET_LIST="${NET_LIST} ${NETWORK_TYPE[${NET_TYPE}]}"
    fi
  done
  NETWORK_CONNECTIONS="--network network:provisioning"
  for NETWORK in ${NET_LIST}
  do
    NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
  done

  if [[ ! -z "${NETWORK_TYPE[controller]}" ]]
  then
    for NETWORK in ${NETWORK_TYPE[controller]}
    do
      NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
    done
  fi

  for X in $(seq 1 ${CONTROLLER_COUNT})
  do
    DISKS=''
    for Y in $(seq 1 ${CONTROLLER_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-controller${X}-${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    ${SUDO} virt-install --ram ${CONTROLLER_RAM} --vcpus ${CONTROLLER_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NETWORK_CONNECTIONS} --name overcloud-controller${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-controller${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-controller${X}-${DATE}.xml
  done
fi

if [[ ${COMPUTE_COUNT} -gt 0 ]]
then
  NET_LIST=''
  for NET_TYPE in InternalAPI Tenant Storage 
  do
    if [[ -z "$(echo ${NET_LIST} | grep ${NETWORK_TYPE[${NET_TYPE}]})" ]]
    then
      NET_LIST="${NET_LIST} ${NETWORK_TYPE[${NET_TYPE}]}"
    fi
  done
  NETWORK_CONNECTIONS="--network network:provisioning"
  for NETWORK in ${NET_LIST}
  do
    NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
  done

  if [[ ! -z "${NETWORK_TYPE[compute]}" ]]
  then
    for NETWORK in ${NETWORK_TYPE[compute]}
    do
      NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
    done
  fi

  for X in $(seq 1 ${COMPUTE_COUNT})
  do
    DISKS=''
    for Y in $(seq 1 ${COMPUTE_DISK_COUNT})
    do
      DISKS="${DISKS} --disk path=${LIBVIRT_IMAGE_DIR}/overcloud-compute${X}-${Y}-${DATE}.qcow2,device=disk,bus=virtio,format=qcow2"
    done
    ${SUDO} virt-install --ram ${COMPUTE_RAM} --vcpus ${COMPUTE_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NETWORK_CONNECTIONS} --name overcloud-compute${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-compute${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-compute${X}-${DATE}.xml
  done
fi

if [[ ${CEPH_COUNT} -gt 0 ]]
then
  NET_LIST=''
  for NET_TYPE in InternalAPI Storage StorageMgmt
  do
    if [[ -z "$(echo ${NET_LIST} | grep ${NETWORK_TYPE[${NET_TYPE}]})" ]]
    then
      NET_LIST="${NET_LIST} ${NETWORK_TYPE[${NET_TYPE}]}"
    fi
  done
  NETWORK_CONNECTIONS="--network network:provisioning"
  for NETWORK in ${NET_LIST}
  do
    NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
  done

  if [[ ! -z "${NETWORK_TYPE[ceph]}" ]]
  then
    for NETWORK in ${NETWORK_TYPE[ceph]}
    do
      NETWORK_CONNECTIONS="${NETWORK_CONNECTIONS} --network network:${NETWORK}"
    done
  fi

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
    ${SUDO} virt-install --ram ${CEPH_RAM} --vcpus ${CEPH_VCPU} --os-variant rhel7 ${DISKS} --noautoconsole --vnc ${NETWORK_CONNECTIONS} --name overcloud-ceph${X}-${DATE} --dry-run --print-xml > /tmp/overcloud-ceph${X}-${DATE}.xml
    ${SUDO} virsh define --file /tmp/overcloud-ceph${X}-${DATE}.xml
  done
fi

source ${DIRECTOR_TOOLS}/config/undercloud.env
KVM_IP=${UNDERCLOUD_GATEWAY}

cat /dev/null > ${DIRECTOR_TOOLS}/config/overcloud-servers.txt
for VM in $(${SUDO} virsh list --all | grep overcloud.*${DATE} | awk '{print $2}')
do
  MAC=$(${SUDO} virsh domiflist ${VM} | awk '/provisioning/ {print $5}');
  echo "${VM}|${KVM_IP}|${MAC}|${LIBVIRT_USER}" >>${DIRECTOR_TOOLS}/config/overcloud-servers.txt
done

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
