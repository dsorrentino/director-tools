#!/bin/bash

SCRIPT_NAME=create_vm-remote_configure
LOG=${SCRIPT_NAME}.log

source ~/undercloud.env
source ~/common.sh

if [[ -z "${UNDERCLOUD_IP}" ]]
then
  stderr "No undercloud IP provided."
  touch $0.error
fi

UNDERCLOUD_PREFIX=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $2}')
UNDERCLOUD_IP=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $1}')

stdout "Configuring networking:"
stdout "IPADDR=\"${UNDERCLOUD_IP}\""
stdout "PREFIX=\"${UNDERCLOUD_PREFIX}\""
stdout "GATEWAY=\"${UNDERCLOUD_GATEWAY}\""

cd /etc/sysconfig/network-scripts

cp -p ifcfg-eth1 $(date +'%Y%m%d-%H%M')-backup.ifcfg-eth1
sed -i 's/BOOTPROTO=.*$/BOOTPROTO="none"/g' ifcfg-eth1
echo "IPADDR=\"${UNDERCLOUD_IP}\"" >>ifcfg-eth1
echo "PREFIX=\"${UNDERCLOUD_PREFIX}\"" >>ifcfg-eth1
echo "GATEWAY=\"${UNDERCLOUD_GATEWAY}\"" >>ifcfg-eth1


UNDERCLOUD_SHORT_NAME=$(echo ${UNDERCLOUD_FQDN} | awk -F\. '{print $1}')

stdout "Updating /etc/hosts:"

sed -i "/^${UNDERCLOUD_IP} /d" /etc/hosts
echo "${UNDERCLOUD_IP}	${UNDERCLOUD_FQDN} ${UNDERCLOUD_SHORT_NAME}" >>/etc/hosts

stdout "$(cat /etc/hosts)"

stdout "Setting hostname to ${UNDERCLOUD_FQDN}"
hostnamectl set-hostname ${UNDERCLOUD_FQDN}
hostnamectl set-hostname ${UNDERCLOUD_FQDN} --transient

if [[ -z "$(grep ${UNDERCLOUD_USER} /etc/passwd)" ]]
then
  stdout "Adding user ${UNDERCLOUD_USER}."
  useradd ${UNDERCLOUD_USER}
fi

echo ${UNDERCLOUD_USER_PW} | passwd ${UNDERCLOUD_USER} --stdin

if [[ ! -f /etc/sudoers.d/${UNDERCLOUD_USER} ]]
then
  stdout "Setting sudoers for ${UNDERCLOUD_USER}"
  echo "${UNDERCLOUD_USER} ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/${UNDERCLOUD_USER}
  chmod 0440 /etc/sudoers.d/${UNDERCLOUD_USER}
else
  stdout "Sudoers already set for ${UNDERCLOUD_USER}"
fi

touch $0.done
