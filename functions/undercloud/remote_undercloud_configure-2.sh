#!/bin/bash

SCRIPT_NAME=remote_undercloud_configure-2

LOG=${SCRIPT_NAME}.log

source ~/undercloud.env
source ~/common.sh

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""
echo ""

stdout "$(sudo yum install -y python-tripleoclient)"

if [[ -z "$(rpm -qa | grep python-tripleoclient)" ]]
then
  stderr "There was a problem with installing the python-tripleoclient package."
  exit 1
fi

if [[ -f ~/undercloud.conf ]]
then
  cp -p ~/undercloud.conf ~/$(date +'%Y%m%d-%H%M')-undercloud.conf.backup
fi

stdout "Undercloud package installed."

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
