#!/bin/bash

SCRIPT_NAME="undercloud-configure"

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

UNDERCLOUD_IP_ADDRESS=$(echo ${UNDERCLOUD_IP} | awk -F/ '{print $1}')

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

stdout "Copying ssh-key to ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}. When prompted, enter the password."
echo "This should be: ${UNDERCLOUD_USER_PW}"
ssh-copy-id ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}

scp ${DIRECTOR_TOOLS}/functions/undercloud/remote_configure_undercloud*.sh ${DIRECTOR_TOOLS}/config/undercloud.env ${DIRECTOR_TOOLS}/functions/common.sh ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:~

ssh ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} 'chmod 600 undercloud.env'
ssh ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} 'chmod 775 ~/remote_configure_undercloud*.sh'
ssh -t ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} '~/remote_configure_undercloud-1.sh'

rm -f ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-1*log*

scp ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:~/remote_configure_undercloud-1*log* ${DIRECTOR_TOOLS}/logs
ssh ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} 'rm -f ~/remote_configure_undercloud-1*'

if [[ ! -z "$(ls ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-1*.err 2>/dev/null)" ]]
then
  stderr "There was an error executing the remote script.  Please check logs:"
  cat ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-1*.err
  exit 1
fi

ssh root@${UNDERCLOUD_IP_ADDRESS} 'reboot'

wait4reboot ${UNDERCLOUD_IP_ADDRESS}

ssh -t ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} '~/remote_configure_undercloud-2.sh'

rm -f ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-2*log*

scp ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:~/remote_configure_undercloud-2*log* ${DIRECTOR_TOOLS}/logs

ssh ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS} 'rm -f ~/remote_configure_undercloud-2*'

if [[ ! -z "$(ls ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-2*.err 2>/dev/null)" ]]
then
  stderr "There was an error executing the remote script.  Please check logs:"
  cat ${DIRECTOR_TOOLS}/logs/remote_configure_undercloud-2*.err
  exit 1
fi

scp ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:/usr/share/instack-undercloud/undercloud.conf.sample ${DIRECTOR_TOOLS}/config/undercloud.conf.sample

cp ${DIRECTOR_TOOLS}/config/undercloud.conf.sample ${DIRECTOR_TOOLS}/config/undercloud.conf

UNDERCLOUD_CONF=${DIRECTOR_TOOLS}/config/undercloud.conf

stdout ""
stdout "Configure undercloud.conf"
stdout ""

for SETTING in $(grep ' = ' ${UNDERCLOUD_CONF} | awk '{print $1}' | sed 's/^##*//g')
do

  stdout ""

  SETTING_ENTRY=$(egrep "^[#]*${SETTING} " ${UNDERCLOUD_CONF})
  ANSWER=""

  SETTING_VARIABLE=$(echo ${SETTING} | tr '[:lower:]' '[:upper:]')
  if [[ ! -z "$(eval echo \$${SETTING_VARIABLE})" ]]
  then
    ANSWER="Y"
  fi

  stdout "Setting: ${SETTING_ENTRY}"
  if [[ ! -z "$(echo ${SETTING_ENTRY} | grep ^#)" ]]
  then
    while [[ -z "${ANSWER}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Uncomment setting or [i]nfo [y/N/i]? " ANSWER
      ANSWER=$(echo ${ANSWER} | cut -c1 | tr '[:lower:]' '[:upper:]' | egrep '(Y|N|I)')

      if [[ -z "${ANSWER}" ]]
      then
        ANSWER='N'
      fi

      if [[ "${ANSWER}" == "I" ]]
      then
        echo ""
        awk "/#${SETTING}/" RS= ${UNDERCLOUD_CONF}.sample
        echo ""
        ANSWER=""
      fi
    done
 
    if [[ "${ANSWER}" == "Y" ]]
    then
      sed -i "s/^#${SETTING} /${SETTING} /g" ${UNDERCLOUD_CONF}
    fi
   
  fi
  SETTING_ENTRY=$(egrep "^[#]*${SETTING} " ${UNDERCLOUD_CONF})
  if [[ -z "$(echo ${SETTING_ENTRY} | grep ^#)" ]]
  then
    SETTING_VALUE=$(echo ${SETTING_ENTRY} | awk -F= '{print $2}' | sed 's/^  *//g;s/  *$//g')
    if [[ ! -z "$(eval echo \$${SETTING_VARIABLE})" ]]
    then
      SETTING_VALUE=$(eval echo \$${SETTING_VARIABLE})
    fi

    NEW_SETTING_VALUE=''

    while [[ -z "${NEW_SETTING_VALUE}" ]]
    do
      read -p "[$(date +'%Y/%m/%d-%H:%M:%S')] Set '${SETTING}' or enter '#' to get description of variable [${SETTING_VALUE}]: " NEW_SETTING_VALUE
      if [[ -z "${NEW_SETTING_VALUE}" ]]
      then
        NEW_SETTING_VALUE=${SETTING_VALUE}
      fi

      if [[ "${NEW_SETTING_VALUE}" == "#" ]]
      then
        echo ""
        awk "/#${SETTING}/" RS= ${UNDERCLOUD_CONF}.sample
        echo ""
        NEW_SETTING_VALUE=''
      fi
    done
    stdout ""
    stdout "Configuring: ${SETTING} = ${NEW_SETTING_VALUE}"
    sed -i "s|^${SETTING} = .*|${SETTING} = ${NEW_SETTING_VALUE}|g" ${UNDERCLOUD_CONF}
  fi
done

stdout "Copying undercloud.conf to the ${UNDERCLOUD_USER} users home directory on the undercloud."

scp ${UNDERCLOUD_CONF} ${UNDERCLOUD_USER}@${UNDERCLOUD_IP_ADDRESS}:~

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
