#!/bin/bash

SCRIPT_NAME=remote_undercloud_deploy

source ~/common.sh

LOG="${SCRIPT_NAME}.log"

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

if [[ ! -f ~/undercloud.conf ]]
then
  stderr "No undercloud.conf found. Exiting."
  exit 500
fi

stdout "Starting deployment."

openstack undercloud install | tee -a ${LOG}

if [[ ! -z "$(grep keystone /etc/passwd)" ]]
then
  stdout "Adding keystone cronjob per: https://access.redhat.com/solutions/968883"
  ${SUDO} crontab -l -u keystone 2>/dev/null; echo '01 * * * * /usr/bin/keystone-manage token_flush >/dev/null 2>&1' | ${SUDO} crontab -u keystone -
  if [[ $? -ne 0 ]]
  then
    stderr "Something went wrong with adding the cronjob."
  fi
fi

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
