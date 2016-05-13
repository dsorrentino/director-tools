#!/bin/bash

SCRIPT_NAME=create_undercloud_vm

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

source ${DIRECTOR_TOOLS}/config/undercloud.env

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

INF_SUBNET=100

while [[ ! -z "$(ip a | grep 192.168.${INF_SUBNET})" ]]
do
  INF_SUBNET=$(( ${INF_SUBNET} + 1 ))
  if [[ ${INF_SUBNET} -eq 255 ]]
  then
    stderr "Unable to find an external network range between 192.168.100.X-192.168.255.X."
    exit 255
  fi
done

INF_SUBNET=192.168.${INF_SUBNET}

stdout "Creating infrastructure network '${INF_NET}' with CIDR '${INF_SUBNET}.0/24'"

cat > /tmp/${INF_NET}.xml <<EOF
<network>
  <name>${INF_NET}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='${INF_SUBNET}.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='${INF_SUBNET}.2' end='${INF_SUBNET}.254'/>
    </dhcp>
  </ip>
</network>
EOF

stdout "$(${SUDO} virsh net-define /tmp/${INF_NET}.xml)"
stdout "$(${SUDO} virsh net-autostart ${INF_NET})"
stdout "$(${SUDO} virsh net-start ${INF_NET})"

sed -i "s|^UNDERCLOUD_GATEWAY=.*$|UNDERCLOUD_GATEWAY=${INF_SUBNET}.1|" ${DIRECTOR_TOOLS}/config/undercloud.env

echo ""
USER_INPUT=''
UNDERCLOUD_IP_ADDRESS=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $1}')
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What IP address did you want to use for the Undercloud.  Must be between ${INF_SUBNET}.2 - ${INF_SUBNET}.254  [${INF_SUBNET}.254]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${INF_SUBNET}.254
  fi
done

UNDERCLOUD_IP_ADDRESS=${USER_INPUT}
stdout "Storing IP in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s|^UNDERCLOUD_IP=.*$|UNDERCLOUD_IP=${UNDERCLOUD_IP_ADDRESS}/24|" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

if [[ ! -z "$(${SUDO} virsh net-list | grep provisioning)" ]]
then
  stdout "Provisioning network already exists.  Deleting it and re-creating it."
  ${SUDO} virsh net-destroy provisioning
  ${SUDO} virsh net-undefine provisioning
fi

USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Provide the Network for the Provisioning network, example 172.16.100.0. Network is assumed to be a /24 [${UNDERCLOUD_PROVISIONING}]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${UNDERCLOUD_PROVISIONING}
  fi
done

PROVISIONING_NETWORK=$(echo ${USER_INPUT} | awk -F\. '{print $1"."$2"."$3".254"}')
stdout "Storing IP in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s|^UNDERCLOUD_PROVISIONING=.*$|UNDERCLOUD_PROVISIONING=${PROVISIONING_NETWORK}|" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

cat > /tmp/provisioning.xml <<EOF
<network>
  <name>provisioning</name>
  <ip address="${PROVISIONING_NETWORK}" netmask="255.255.255.0"/>
</network>
EOF

stdout "$(${SUDO} virsh net-define /tmp/provisioning.xml)"
stdout "$(${SUDO} virsh net-autostart provisioning)"
stdout "$(${SUDO} virsh net-start provisioning)"

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
  sed -i "s|^${SETTING_VAR}=.*|${SETTING_VAR}=${USER_INPUT}|" ${DIRECTOR_TOOLS}/config/undercloud.env
done

source ${DIRECTOR_TOOLS}/config/undercloud.env


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
stdout "$(${SUDO} virt-install --ram ${UNDERCLOUD_RAM} --vcpus ${UNDERCLOUD_VCPU} --os-variant rhel7 --disk path=${LIBVIRT_IMAGE_DIR}/${UNDERCLOUD_IMAGE},device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network network:provisioning --network network:${INF_NET} --name undercloud)"

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

sed -i "/${UNDERCLOUD_IP_ADDRESS}/d" ~/.ssh/known_hosts
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

scp ${DIRECTOR_TOOLS}/config/undercloud.env ${DIRECTOR_TOOLS}/functions/common.sh ${DIRECTOR_TOOLS}/functions/kvm/remote_configure_undercloud_vm*.sh root@${UNDERCLOUD_DHCP_IP}:~ >/dev/null

ssh root@${UNDERCLOUD_DHCP_IP} 'chmod 775 ~/remote_configure_undercloud_vm*.sh'

stdout "Starting the undercloud VM base configuration."

ssh root@${UNDERCLOUD_DHCP_IP} '~/remote_configure_undercloud_vm.sh'

rm -f ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud_vm*log*

scp root@${UNDERCLOUD_DHCP_IP}:~/remote_configure_undercloud_vm*log* ${DIRECTOR_TOOLS}/logs

ssh root@${UNDERCLOUD_DHCP_IP} 'rm ~/remote_configure_undercloud_vm*'

if [[ -f ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud_vm*.err ]]
  then
    stderr "There was an error running remote_configure_undercloud_vm.sh."
    cat ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud_vm*.err
    exit 1
fi

stdout "Rebooting undercloud VM. Connection refused messages are normal.  Disregard."

ssh root@${UNDERCLOUD_DHCP_IP} 'reboot'

wait4reboot ${UNDERCLOUD_IP_ADDRESS}

UNDERCLOUD_DHCP_IP=${UNDERCLOUD_IP_ADDRESS}

stdout "Undercloud is back up."

ssh root@${UNDERCLOUD_IP_ADDRESS} 'rm ~/common.sh ~/undercloud.env'

stdout "Configuring /etc/hosts: "

${SUDO} cp -p /etc/hosts /etc/hosts-$(date +'%Y%m%d-%H%M')
${SUDO} sed -i '/undercloud.redhat.local/d' /etc/hosts
${SUDO} sed -i '/undercloud/d' /etc/hosts

echo -e "${UNDERCLOUD_IP_ADDRESS}\tundercloud.redhat.local\tundercloud" | ${SUDO} tee -a /etc/hosts

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
