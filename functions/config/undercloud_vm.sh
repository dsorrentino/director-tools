#!/bin/bash

SCRIPT_NAME=config_undercloud_vm

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""
stdout "Gathering relevant information to install the undercloud."
stdout ""

source ${DIRECTOR_TOOLS}/config/undercloud.env

stdout "Need some basic information around the server to where the Undercloud will be installed."
   
USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Enter the root password for the Undercloud [${UNDERCLOUD_ROOT_PW}]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${UNDERCLOUD_ROOT_PW}
  fi
  if [[ $(echo ${USER_INPUT} | wc -c) -lt 6 ]]
  then
    stderr "Password must be at least 6 characters.  Put some effort in."
    USER_INPUT=''
  fi
done

stdout "Storing password in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s/^UNDERCLOUD_ROOT_PW=.*$/UNDERCLOUD_ROOT_PW=${USER_INPUT}/" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What is the user name that the Undercloud should run under [${UNDERCLOUD_USER}]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${UNDERCLOUD_USER}
  fi
done

stdout "Storing user in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s/^UNDERCLOUD_USER=.*$/UNDERCLOUD_USER=${USER_INPUT}/" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Set the password for the Undercloud user [${UNDERCLOUD_USER_PW}]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${UNDERCLOUD_USER_PW}
  fi
  if [[ $(echo ${USER_INPUT} | wc -c) -lt 6 ]]
  then
    stderr "Password must be at least 6 characters.  Put some effort in."
    USER_INPUT=''
  fi
done

stdout "Storing user password in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s/^UNDERCLOUD_USER_PW=.*$/UNDERCLOUD_USER_PW=${USER_INPUT}/" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

USER_INPUT=''
while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What should the FQDN for the Undercloud system be [${UNDERCLOUD_FQDN}]: " USER_INPUT
  if [[ -z "${USER_INPUT}" ]]
  then
    USER_INPUT=${UNDERCLOUD_FQDN}
  fi
done

stdout "Storing FQDN in ${DIRECTOR_TOOLS}/config/undercloud.env"
sed -i "s/^UNDERCLOUD_FQDN=.*$/UNDERCLOUD_FQDN=${USER_INPUT}/" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

USER_DATA=''
while [[ -z "${USER_DATA}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Should this script create the Undercloud VM [Y/n]? " USER_DATA
  if [[ -z "${USER_DATA}" ]]
  then
    USER_DATA=Y
  fi
  USER_DATA=$(echo ${USER_DATA} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
  if [[ -z "${USER_DATA}" ]]
  then
    stdout "Invalid entry. Try again."
  fi
done

sed -i "s/^UNDERCLOUD_CREATE_VM=.*$/UNDERCLOUD_CREATE_VM=${USER_DATA}/" ${DIRECTOR_TOOLS}/config/undercloud.env
echo ""

if [[ "${UNDERCLOUD_CREATE_VM}" == "Y" ]]
then
  stdout "Base configuration data gathered to create the VM."
else
  stdout "Since the VM already exists, we will need connection information."
  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What is the IP address of the system to install the Undercloud on: " USER_INPUT
    ping -c 1 ${USER_INPUT} >/dev/null 2>&1
    if [[ $? -ne 0 ]]
    then
      stderr "Can not ping ${USER_INPUT}.  Try again."
      USER_INPUT=''
    fi
  done
  UNDERCLOUD_IP=${USER_DATA}

  stdout "Copying SSH key to root@${UNDERCLOUD_IP}. Enter credentials as needed."

  ssh-copy-id root@${UNDERCLOUD_IP}

  OS_HOSTNAME=$(ssh root@{UNDERCLOUD_IP} 'hostname')

  stdout "Current hostname: ${OS_HOSTNAME}"
  
fi

stdout ""
stdout "If this undercloud VM will be deploying to Virtual Overcloud nodes on the same KVM host,"
stdout "it will need a user/password for Ironic to login with to perform power function."
stdout ""

USER_INPUT=''

while [[ -z "${USER_INPUT}" ]]
do
  read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Will the Overcloud nodes be deployed as VM's on this KVM host? " USER_INPUT
  USER_INPUT=$(echo ${USER_INPUT} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N)')
done

if [[ "${USER_INPUT}" == 'Y' ]]
then
  echo ""
  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What user should Ironic use to connect to KVM [${LIBVIRT_USER}]: " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT=${LIBVIRT_USER}
    fi
  done

  LIBVIRT_USER=${USER_INPUT}
  stdout "Storing user in ${DIRECTOR_TOOLS}/config/undercloud.env"
  sed -i "s|^LIBVIRT_USER=.*$|LIBVIRT_USER=${LIBVIRT_USER}|" ${DIRECTOR_TOOLS}/config/undercloud.env
  echo ""

  USER_INPUT=''
  while [[ -z "${USER_INPUT}" ]]
  do
    read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] What password should be set for this user [${LIBVIRT_USER_PW}]: " USER_INPUT
    if [[ -z "${USER_INPUT}" ]]
    then
      USER_INPUT=${LIBVIRT_USER_PW}
    fi
  done

  LIBVIRT_USER_PW=${USER_INPUT}
  stdout "Storing user in ${DIRECTOR_TOOLS}/config/undercloud.env"
  sed -i "s|^LIBVIRT_USER_PW=.*$|LIBVIRT_USER_PW=${LIBVIRT_USER_PW}|" ${DIRECTOR_TOOLS}/config/undercloud.env

  if [[ -z "$(grep ${LIBVIRT_USER} /etc/passwd)" ]]
  then
    stdout "Adding user: ${LIBVIRT_USER}"
    ${SUDO} useradd ${LIBVIRT_USER}
    echo ${LIBVIRT_USER_PW} | ${SUDO} passwd ${LIBVIRT_USER} --stdin
    for GROUP in libvirt kvm
    do
      if [[ ! -z "$(grep "^${GROUP}:" /etc/group)" ]]
      then
        ${SUDO} usermod -aG ${GROUP} ${LIBVIRT_USER}
      fi
    done
  fi

  
fi

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
