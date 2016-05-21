#!/bin/bash

source ${DIRECTOR_TOOLS}/environment/undercloud.env
source ${DIRECTOR_TOOLS}/functions/common.sh

SCRIPT_NAME=create_vm-configure

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""
stdout "Gathering relevant information to install the undercloud."
stdout ""

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

stdout "Storing password in ${DIRECTOR_TOOLS}/environment/undercloud.env"
sed -i "s/^UNDERCLOUD_ROOT_PW=.*$/UNDERCLOUD_ROOT_PW=${USER_INPUT}/" ${DIRECTOR_TOOLS}/environment/undercloud.env
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

stdout "Storing user in ${DIRECTOR_TOOLS}/environment/undercloud.env"
sed -i "s/^UNDERCLOUD_USER=.*$/UNDERCLOUD_USER=${USER_INPUT}/" ${DIRECTOR_TOOLS}/environment/undercloud.env
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

stdout "Storing user password in ${DIRECTOR_TOOLS}/environment/undercloud.env"
sed -i "s/^UNDERCLOUD_USER_PW=.*$/UNDERCLOUD_USER_PW=${USER_INPUT}/" ${DIRECTOR_TOOLS}/environment/undercloud.env
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

stdout "Storing FQDN in ${DIRECTOR_TOOLS}/environment/undercloud.env"
sed -i "s/^UNDERCLOUD_FQDN=.*$/UNDERCLOUD_FQDN=${USER_INPUT}/" ${DIRECTOR_TOOLS}/environment/undercloud.env
echo ""

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
  stdout "Storing user in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^LIBVIRT_USER=.*$|LIBVIRT_USER=${LIBVIRT_USER}|" ${DIRECTOR_TOOLS}/environment/undercloud.env
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
  stdout "Storing user in ${DIRECTOR_TOOLS}/environment/undercloud.env"
  sed -i "s|^LIBVIRT_USER_PW=.*$|LIBVIRT_USER_PW=${LIBVIRT_USER_PW}|" ${DIRECTOR_TOOLS}/environment/undercloud.env

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
