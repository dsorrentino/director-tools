#!/bin/bash

source ${DIRECTOR_TOOLS}/functions/common.sh
source ${DIRECTOR_TOOLS}/environment/undercloud.env

SCRIPT_NAME=create_undercloud_vm

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""


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

USER_INPUT=''

while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Create networks for the Director VM [Y/n]? " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=Y
  fi
  USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|n)')
done

VM_NETWORK_CONFIG=''

if [[ "${USER_INPUT}" == 'Y' ]]
then
  INF_NET=infrastructure-net

  if [[ ! -z "$(${SUDO} virsh net-info ${INF_NET} 2>/dev/null)" ]]
  then
    X=1
    while [[ ! -z "$(${SUDO} virsh net-info ${INF_NET}-${X} 2>/dev/null)" ]]
    do
      X=$(( ${X} + 1 ))
    done
    INF_NET="${INF_NET}-${X}"
  fi

  INF_SUBNET=''
  INF_PREFIX=''
  USER_INPUT=''
  stdout ""
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] [A]utoselect infrastructure CIDR in the 192.168.100-192.168.255 range or set [m]anually [A/m]? " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT='A'
    fi
    USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(A|M)')
  done

  if [[ "${USER_INPUT}" == 'A' ]]
  then
    INF_PREFIX='24'
    INF_SUBNET=100
    UNDERCLOUD_IP=254
    UNDERCLOUD_INFRASTRUCTURE_DHCP_START=2
    UNDERCLOUD_INFRASTRUCTURE_DHCP_END=253

    while [[ ! -z "$(ip a | grep inet | grep 192.168.${INF_SUBNET})" ]]
    do
      INF_SUBNET=$(( ${INF_SUBNET} + 1 ))
      if [[ ${INF_SUBNET} -eq 255 ]]
      then
        stderr "Unable to find an external network range between 192.168.100.X-192.168.255.X."
        exit 255
      fi
    done
    UNDERCLOUD_IP=192.168.${INF_SUBNET}.${UNDERCLOUD_IP}
    UNDERCLOUD_INFRASTRUCTURE_DHCP_START=192.168.${INF_SUBNET}.${UNDERCLOUD_INFRASTRUCTURE_DHCP_START}
    UNDERCLOUD_INFRASTRUCTURE_DHCP_END=192.168.${INF_SUBNET}.${UNDERCLOUD_INFRASTRUCTURE_DHCP_END}
    INF_SUBNET=192.168.${INF_SUBNET}.1
  else
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter the CIDR for the infrastructure network [${UNDERCLOUD_INFRASTRUCTURE_NETWORK}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${UNDERCLOUD_INFRASTRUCTURE_NETWORK}
      fi
      #  Very rudimentary CIDR pattern matching
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,3}')
      if [[ ! -z "${USER_INPUT}" ]]
      then
        INF_SUBNET=$(echo ${USER_INPUT} | awk -F\. '{print $1"."$2"."$3}')
        if [[ ! -z "$(ip a | grep inet | grep ${INF_SUBNET})" ]]
        then
          stdout "It looks like ${INF_SUBNET} may already on an interface:"
          stdout ""
          ip a | grep -A2 -B2 ${INF_SUBNET}
          stdout ""
          USER_INPUT_2=''
          read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Use ${USER_INPUT} as the ${INF_NET} network anyway [y/N] " USER_INPUT_2
          USER_INPUT_2=$(echo ${USER_INPUT_2} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
          if [[ -z "${USER_INPUT_2}" || "${USER_INPUT_2}" -eq 'N' ]]
          then
            USER_INPUT=''
          fi
        fi
      else
        stdout ""
        stdout "Invalid CIDR of '${USER_INPUT}' entered.  Example: 192.168.100.0/24"
        stdout ""
      fi
    done
    UNDERCLOUD_INFRASTRUCTURE_NETWORK=${USER_INPUT}
    INF_SUBNET=$(echo ${UNDERCLOUD_INFRASTRUCTURE_NETWORK} | awk -F/ '{print $1}' | awk -F\. '{print $NF}')
    INF_SUBNET=$(( ${INF_SUBNET} + 1 ))
    INF_SUBNET=$(echo ${UNDERCLOUD_INFRASTRUCTURE_NETWORK} | awk -F/ '{print $1}' | awk -F\. '{print $1"."$2"."$3}').${INF_SUBNET}
    INF_PREFIX=$(echo ${UNDERCLOUD_INFRASTRUCTURE_NETWORK} | awk -F/ '{print $NF}')
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter the IP for the Director VM on the infrastructure network [${UNDERCLOUD_IP}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${UNDERCLOUD_IP}
      fi
      #  Very rudimentary CIDR pattern matching
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
    done
    UNDERCLOUD_IP=${USER_INPUT}
    stdout ""
    stdout "DHCP is enabled for the first boot of the VM on the infrastructure network so you must"
    stdout "define a DHCP range for KVM to pull from for the first boot of the undercloud VM"
    stdout ""
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] DHCP start IP [${UNDERCLOUD_INFRASTRUCTURE_DHCP_START}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${UNDERCLOUD_INFRASTRUCTURE_DHCP_START}
      fi
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
    done
    UNDERCLOUD_INFRASTRUCTURE_DHCP_START=${USER_INPUT}
  
    stdout ""
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] DHCP end IP [${UNDERCLOUD_INFRASTRUCTURE_DHCP_END}]: " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=${UNDERCLOUD_INFRASTRUCTURE_DHCP_END}
      fi
      USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
    done
    UNDERCLOUD_INFRASTRUCTURE_DHCP_END=${USER_INPUT}
    
  fi
  
  INF_NETMASK=$(cidr2mask ${INF_PREFIX})
  
  echo ""
  stdout "Creating infrastructure network '${INF_NET}' with CIDR '${INF_SUBNET}/${INF_PREFIX}'"
  
  INF_NET_DHCP="<range start='${UNDERCLOUD_INFRASTRUCTURE_DHCP_START}' end='${UNDERCLOUD_INFRASTRUCTURE_DHCP_END}'/>"
  
  cat > /tmp/${INF_NET}.xml <<EOF
<network>
  <name>${INF_NET}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='${INF_SUBNET}' netmask='${INF_NETMASK}'>
    <dhcp>
      ${INF_NET_DHCP}
    </dhcp>
  </ip>
</network>
EOF
  
  stdout "$(${SUDO} virsh net-define /tmp/${INF_NET}.xml)"
  stdout "$(${SUDO} virsh net-autostart ${INF_NET})"
  stdout "$(${SUDO} virsh net-start ${INF_NET})"
  
  stdout "Storing infrastructure network in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_INFRASTRUCTURE_NETWORK=.*$|UNDERCLOUD_INFRASTRUCTURE_NETWORK=${UNDERCLOUD_INFRASTRUCTURE_NETWORK}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  
  stdout "Storing gateway in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_GATEWAY=.*$|UNDERCLOUD_GATEWAY=${INF_SUBNET}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  
  stdout "Storing IP in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_IP=.*$|UNDERCLOUD_IP=${UNDERCLOUD_IP}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  
  stdout "Storing DHCP start in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_INFRASTRUCTURE_DHCP_START=.*$|UNDERCLOUD_INFRASTRUCTURE_DHCP_START=${UNDERCLOUD_INFRASTRUCTURE_DHCP_START}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  
  stdout "Storing DHCP end in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_INFRASTRUCTURE_DHCP_END=.*$|UNDERCLOUD_INFRASTRUCTURE_DHCP_END=${UNDERCLOUD_INFRASTRUCTURE_DHCP_END}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  
  stdout ""
  
  if [[ ! -z "$(${SUDO} virsh net-list | grep provisioning)" ]]
  then
    stdout "Provisioning network already exists.  Deleting it and re-creating it."
    ${SUDO} virsh net-destroy provisioning
    ${SUDO} virsh net-undefine provisioning
  fi
  
  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Provide the Network for the Provisioning network, example 172.16.100.0. Network should be at least a /24 [${UNDERCLOUD_PROVISIONING}]: " USER_INPUT
    #  Very rudimentary CIDR pattern matching
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT=${UNDERCLOUD_PROVISIONING}
    fi
    USER_INPUT=$(echo ${USER_INPUT} | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,3}')
    if [[ ! -z "${USER_INPUT}" ]]
    then
      if [[ $(echo ${UNDERCLOUD_PROVISIONING} | awk -F/ '{print $NF}') -gt 24 ]]
      then
        stdout "Warning:  Network should be at least a /24."
        USER_INPUT=''
      fi
    fi
  done
  
  UNDERCLOUD_PROVISIONING=${USER_INPUT}
  
  PROVISIONING_NETWORK=$(echo ${UNDERCLOUD_PROVISIONING} | awk -F/ '{print $1}')
  PROVISIONING_NETMASK=$(echo ${UNDERCLOUD_PROVISIONING} | awk -F/ '{print $NF}')
  PROVISIONING_NETMASK=$(cidr2mask ${PROVISIONING_NETMASK})
  
  stdout "Storing Provisioning IP in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^UNDERCLOUD_PROVISIONING=.*$|UNDERCLOUD_PROVISIONING=${UNDERCLOUD_PROVISIONING}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
  echo ""
  
  cat > /tmp/provisioning.xml <<EOF
<network>
  <name>provisioning</name>
  <ip address="${PROVISIONING_NETWORK}" netmask="${PROVISIONING_NETMASK}"/>
</network>
EOF

  stdout "$(${SUDO} virsh net-define /tmp/provisioning.xml)"
  stdout "$(${SUDO} virsh net-autostart provisioning)"
  stdout "$(${SUDO} virsh net-start provisioning)"

  VM_NETWORK_CONFIG="--network network:provisioning --network network:${INF_NET}"
else
  stdout "###########################################"
  stdout "# BETA CODE - THIS CODE IS UNTESTED UNTIL #"
  stdout "# I HAVE SOME REAL WORLD HARDWARE TO TEST #"
  stdout "# ON                                      #"
  stdout "###########################################"
  which brctl >/dev/null 2>&1
  if [[ $? -ne 0 ]]
  then
    stdout "Bridge utils not installed.  Installing them now."
    ${SUDO} yum install bridge-utils -y
  fi

  CREATE_BRIDGE=N

  if [[ -z "$(brctl show | egrep -v 'bridge name')" ]]
  then
    stdout "No bridges found."
    CREATE_BRIDGE=N
  else
    stdout "Following bridge configuration found:"
    stdout ""
    brctl show
    stdout ""
    USER_INPUT=''
    while [[ -z "${USER_INPUT}" ]]
    do
      read -p "Do you want to create new bridges for the undercloud VM [Y/n]? " USER_INPUT
      if [[ -z "${USER_INPUT}" ]]
      then
        USER_INPUT=Y
      fi
      USER_INPUT=$(echo ${USER_INPUT} | tr '[:lower:]' '[:upper:]' | cut -c1 | egrep '(Y|N)')
    done
    CREATE_BRIDGES=${USER_INPUT}
  fi

  if [[ "${CREATE_BRIDGES}" == "Y" ]]
  then
    stdout "Creating a bridge for infrastructure network and provisioning."
    ${SUDO} brctl addbr infr-br
    ${SUDO} brctl addbr prov-br
    for NETWORK in infrastructure provisioning
    do
      USER_INPUT=''
      while [[ -z "${USER_INPUT}" ]]
      do
        stdout "Please select the interface you'd like to use for the ${NETWORK} bridge:"
        stdout ""
        ip link show | grep -B1 'link/ether' | grep -v 'link/ether' | awk '{print $1" "$2}' | sed 's/:$//g'
        stdout ""
        read -p "Select interface: " USER_INPUT
        if [[ ! -z "${USER_INPUT}" ]]
        then
          USER_INPUT=$(ip link show | grep -B1 'link/ether' | grep -v 'link/ether' | awk '{print $1" "$2}' | sed 's/:$//g' | egrep "^${USER_INPUT}: " | awk '{print $2}')
        fi
      done
      BRIDGE_NAME="$(echo ${NETWORK} | cut -c1-4)-br"
      stdout "Adding interface ${USER_INPUT} to ${BRIDGE_NAME} bridge."
      brctl addif ${BRIDGE_NAME} ${USER_INPUT}
    done
  fi

  stdout ""
  stdout "Which bridge should be used as the infrastructure network:"
  stdout ""
  BR_NDX=0
  INF_NET=''
  while [[ -z "${INF_NET}" ]]
  do
    for BRIDGE in $(brctl show | egrep -v 'bridge name' | awk '{print $1}' | sort -u)
    do
      BR_NDX=$(( ${BR_NDX} + 1 ))
      echo "[${BR_NDX}] ${BRIDGE}"
    done
    USER_INPUT=''
    read -p "Select the bridge to be used for the infrastructure network [1-${BR_NDX}]: " USER_INPUT
    USER_INPUT=$(echo ${USER_INPUT} | egrep -o '[0-9][0-9]*')
    if [[ ! -z "${USER_INPUT}" && ${USER_INPUT} ]]
    then
      if [[ ${USER_INPUT} -gt 0 && ${USER_INPUT} -le ${BR_NDX} ]]
      then
        for BRIDGE in $(brctl show | egrep -v 'bridge name' | awk '{print $1}' | sort -u)
        do
          BR_NDX=$(( ${BR_NDX} + 1 ))
          if [[ ${BR_NDX} -eq ${USER_INPUT} ]]
          then
            INF_NET=${BRIDGE}
          fi
        done
      fi
    fi
  done
  stdout ""
  stdout "Using bridge ${INF_NET} for the infrastructure network."
  stdout ""
  stdout "Which bridge should be used as the provisioning network:"
  stdout ""
  BR_NDX=0
  PROV_NET=''
  while [[ -z "${PROV_NET}" ]]
  do
    for BRIDGE in $(brctl show | egrep -v 'bridge name' | awk '{print $1}' | sort -u)
    do
      BR_NDX=$(( ${BR_NDX} + 1 ))
      echo "[${BR_NDX}] ${BRIDGE}"
    done
    USER_INPUT=''
    read -p "Select the bridge to be used for the provisioning network [1-${BR_NDX}]: " USER_INPUT
    USER_INPUT=$(echo ${USER_INPUT} | egrep -o '[0-9][0-9]*')
    if [[ ! -z "${USER_INPUT}" && ${USER_INPUT} ]]
    then
      if [[ ${USER_INPUT} -gt 0 && ${USER_INPUT} -le ${BR_NDX} ]]
      then
        for BRIDGE in $(brctl show | egrep -v 'bridge name' | awk '{print $1}' | sort -u)
        do
          BR_NDX=$(( ${BR_NDX} + 1 ))
          if [[ ${BR_NDX} -eq ${USER_INPUT} ]]
          then
            PROV_NET=${BRIDGE}
          fi
        done
      fi
    fi
  done
  stdout ""
  stdout "Using bridge ${PROV_NET} for the provisioning network."
  stdout ""
  VM_NETWORK_CONFIG="--network bridge:${PROV_NET} --network bridge:${INF_NET}"
fi
  
  stdout ""
stdout "Using base image from ${RHEL_KVM_IMAGE_SOURCE}"

OUTPUT_IMAGE=$(mktemp)

if [[ ! -z "$(echo ${RHEL_KVM_IMAGE_SOURCE} | grep ^http)" ]]
then
  curl -o ${OUTPUT_IMAGE} ${RHEL_KVM_IMAGE_SOURCE}
elif [[ ! -z "$(echo ${RHEL_KVM_IMAGE_SOURCE} | grep ^file)" ]]
then
  RHEL_KVM_IMAGE_SOURCE=$(echo ${RHEL_KVM_IMAGE_SOURCE} | sed 's|^file://*|/|g')
  ${SUDO} cp ${RHEL_KVM_IMAGE_SOURCE} ${OUTPUT_IMAGE}
else
  stderr "Don't know how to pull image from: ${RHEL_KVM_IMAGE_SOURCE}"
  exit 150
fi

if [[ -f ${OUTPUT_IMAGE} && -s ${OUTPUT_IMAGE} ]]
then
  stdout "Image obtained."
else
  stderr "Unable to obtain image for the undercloud VM from ${RHEL_KVM_IMAGE_SOURCE}"
  exit 200
fi
stdout ""

LIBVIRT_IMAGE_DIR=/var/lib/libvirt/images

OFFICIAL_IMAGE=rhel7-guest-official
MODIFIED_IMAGE=rhel7-guest
UNDERCLOUD_IMAGE=undercloud

for IMAGE in OFFICIAL_IMAGE MODIFIED_IMAGE UNDERCLOUD_IMAGE
do
  IMAGE_NAME=$(eval echo \$${IMAGE})
  if [[ ! -z "$(${SUDO} ls ${LIBVIRT_IMAGE_DIR}/${IMAGE_NAME}.qcow2 2>/dev/null)" ]]
  then
    NDX=1
    while [[ ! -z "$(${SUDO} ls ${LIBVIRT_IMAGE_DIR}/${IMAGE_NAME}-${NDX}.qcow2 2>/dev/null)" ]]
    do
      NDX=$(( ${NDX} + 1 ))
    done
    IMAGE_NAME="${IMAGE_NAME}-${NDX}"
    eval "${IMAGE}='${IMAGE_NAME}'"
  fi
  stdout "For the ${IMAGE}, using the filename of: ${IMAGE_NAME}"
done

OFFICIAL_IMAGE="${OFFICIAL_IMAGE}.qcow2"
MODIFIED_IMAGE="${MODIFIED_IMAGE}.qcow2"
UNDERCLOUD_IMAGE="${UNDERCLOUD_IMAGE}.qcow2"

${SUDO} cp ${OUTPUT_IMAGE} ${LIBVIRT_IMAGE_DIR}/${OFFICIAL_IMAGE}
${SUDO} rm ${OUTPUT_IMAGE}

declare -A QUESTION
QUESTION[VCPU]="How many VCPU's should the undercloud VM be configured with (must be greater than 0)"
QUESTION[RAM]="How much RAM (in MB) should the undercloud VM be configured with (must be greater than 5120, number only)"
QUESTION[DISK]="What is the size (in GB) of the disk for the undercloud VM (must be greater than 0, number only)"

for SETTING in VCPU RAM DISK
do
  SETTING_VAR="UNDERCLOUD_${SETTING}"
  DEFAULT_SETTING=$(eval echo \$${SETTING_VAR})
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
    if [[ "${SETTING}" == "RAM" && ! -z "${USER_INPUT}" ]]
    then
      if [[ ${USER_INPUT} -lt 5120 ]]
      then
        stdout "Need a minimum of 5120MB in order for virt-customize to work."
      fi
    fi
  done

  stdout "Setting Undercloud $(echo ${SETTING} | tr '[:upper:]' '[:lower:]') to: ${USER_INPUT}"
  sed -i "s|^${SETTING_VAR}=.*|${SETTING_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
done

source ${DIRECTOR_TOOLS}/environment/undercloud.env


stdout "Creating an expanded image of size ${UNDERCLOUD_DISK}"

stdout "$(${SUDO} qemu-img create -f qcow2 ${LIBVIRT_IMAGE_DIR}/${MODIFIED_IMAGE} ${UNDERCLOUD_DISK}G)"
stdout "Resizing the image."
stdout "$(${SUDO} virt-resize --expand /dev/sda1 ${LIBVIRT_IMAGE_DIR}/${OFFICIAL_IMAGE} ${LIBVIRT_IMAGE_DIR}/${MODIFIED_IMAGE})"
stdout "Checking filesystems."
stdout "$(${SUDO} virt-filesystems --long -h --all -a ${LIBVIRT_IMAGE_DIR}/${MODIFIED_IMAGE})"
stdout "Creating undercloud.qcow2 image"
stdout "$(${SUDO} qemu-img create -f qcow2 -b ${LIBVIRT_IMAGE_DIR}/${MODIFIED_IMAGE} ${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE})"
stdout "Removing cloud-init packages as they are not needed."
stdout "$(${SUDO} virt-customize -a ${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE} --run-command 'yum remove cloud-init* -y')"
stdout "Setting the root password."
stdout "$(${SUDO} virt-customize -a ${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE} --root-password password:${UNDERCLOUD_ROOT_PW})"
stdout "Setting up network interface files."
stdout "$(${SUDO} virt-customize -a ${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE} --run-command 'cp /etc/sysconfig/network-scripts/ifcfg-eth{0,1} && sed -i s/DEVICE=.*/DEVICE=eth1/g /etc/sysconfig/network-scripts/ifcfg-eth1')"
stdout "Launching VM"
stdout "$(${SUDO} virt-install --ram ${UNDERCLOUD_RAM} --vcpus ${UNDERCLOUD_VCPU} --os-variant rhel7 --disk path=${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE},device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc ${VM_NETWORK_CONFIG} --name undercloud)"

stdout "Looking for the IP assigned from DHCP. One moment, please." 

EXTERNAL_MAC=''
UNDERCLOUD_DHCP_IP=''

while [[ -z "${EXTERNAL_MAC}" ]]
do
  EXTERNAL_MAC=$(${SUDO} virsh domiflist undercloud 2>/dev/null | grep ${INF_NET} 2>/dev/null | awk '{print $NF}' 2>/dev/null)
done

while [[ -z "${UNDERCLOUD_DHCP_IP}" ]]
do
  UNDERCLOUD_DHCP_IP=$(${SUDO} virsh net-dhcp-leases ${INF_NET} | grep ${EXTERNAL_MAC} | awk '{print $5}' | awk -F/ '{print $1}')
done

stdout "Undercloud VM is currently using IP: ${UNDERCLOUD_DHCP_IP}"

sed -i "/${UNDERCLOUD_IP}/d" ~/.ssh/known_hosts
sed -i "/undercloud/d" ~/.ssh/known_hosts
sed -i "/${UNDERCLOUD_DHCP_IP}/d" ~/.ssh/known_hosts

if [[ ! -f ~/.ssh/id_rsa ]]
then
  stdout "Generating keypair."
  ssh-keygen
fi

stdout ""
stdout "You may be prompted for the root password."
echo "[$(date +'%Y/%m/%d-%H:%M:%S')] When you are, enter the root password of: ${UNDERCLOUD_ROOT_PW}"
stdout ""

RC=1
while [[ ${RC} -ne 0 ]]
do
  ssh-copy-id -o StrictHostKeyChecking=no root@${UNDERCLOUD_DHCP_IP} 2>/dev/null
  RC=$?
done

stdout "Copying configuration files to the undercloud VM."

scp ${DIRECTOR_TOOLS}/environment/undercloud.env ${DIRECTOR_TOOLS}/functions/common.sh ${DIRECTOR_TOOLS}/functions/undercloud/create_vm/remote_configure_undercloud_vm.sh root@${UNDERCLOUD_DHCP_IP}:~ >/dev/null

ssh root@${UNDERCLOUD_DHCP_IP} 'chmod 775 ~/remote_configure_undercloud_vm.sh'

stdout "Starting the undercloud VM base configuration."

ssh root@${UNDERCLOUD_DHCP_IP} '~/remote_configure_undercloud_vm.sh'

rm -f ${DIRECTOR_TOOLS}/logs/create_vm-remote_configure*log*

scp root@${UNDERCLOUD_DHCP_IP}:~/create_vm-remote_configure*log* ${DIRECTOR_TOOLS}/logs

ssh root@${UNDERCLOUD_DHCP_IP} 'rm ~/remote_configure_undercloud_vm* ~/create_vm-remote_configure*log*'

if [[ -f ${DIRECTOR_TOOLS}/logs/create_vm-remote_configure*.err ]]
  then
    stderr "There was an error running remote_configure_undercloud_vm.sh."
    cat ${DIRECTOR_TOOLS}/logs/create_vm-remote_configure*.err
    exit 1
fi

stdout "Stopping undercloud VM."

ssh root@${UNDERCLOUD_DHCP_IP} 'shutdown -hP now'

while [[ ! -z "$(${SUDO} virsh list | grep undercloud)" ]]
do
  sleep 5
done

stdout "Removing DHCP from the infrastructure network."

${SUDO} virsh net-update --network ${INF_NET} --section ip-dhcp-range --command delete --live --xml "${INF_NET_DHCP}"

stdout "Restarting undercloud VM."

${SUDO} virsh start undercloud

wait4reboot ${UNDERCLOUD_IP}

stdout "Undercloud is back up."

ssh root@${UNDERCLOUD_IP} 'rm ~/common.sh ~/undercloud.env'

stdout "Configuring /etc/hosts: "

${SUDO} cp -p /etc/hosts /etc/hosts-$(date +'%Y%m%d-%H%M')
${SUDO} sed -i "/${UNDERCLOUD_FQDN}/d" /etc/hosts

echo -e "${UNDERCLOUD_IP}\tundercloud.redhat.local\tundercloud" | ${SUDO} tee -a /etc/hosts

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
