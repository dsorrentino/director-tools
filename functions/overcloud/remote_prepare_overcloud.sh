#!/bin/bash

source ~/common.sh
source ~/undercloud.env
source ~/overcloud.env
source ~/stackrc

SCRIPT_NAME=remote_prepare_overcloud

LOG=${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

IPMI_IP=$(cat ~/overcloud-servers.txt | awk -F\| '{print $2}' | sort -u)
USER=$(cat ~/overcloud-servers.txt | awk -F\| '{print $4}' | sort -u)

stdout "Obtaining the images. This may take a bit."

sudo yum install rhosp-director-images rhosp-director-images-ipa libguestfs-tools -y

cp /usr/share/rhosp-director-images/overcloud-full-latest-8.0.tar ~/images/
cp /usr/share/rhosp-director-images/ironic-python-agent-latest-8.0.tar ~/images/

stdout "Extracting the images."
cd ~/images
for TARFILE in $(ls *.tar)
do
  tar -xf ${TARFILE}
  rm -f ${TARFILE}
done
cd -

sudo systemctl start libvirtd
export LIBGUESTFS_BACKEND=direct

stdout "Updating the root password on the overcloud node images."
echo "Setting password to: ${UNDERCLOUD_ROOT_PW}"

cd ~/images
virt-customize -a overcloud-full.qcow2 --root-password password:${UNDERCLOUD_ROOT_PW}
cd -

cd ~/images
stdout "Uploading images into glance."
stdout "$(openstack overcloud image upload --image-path ~/images/)"
cd -

stdout "Upload complete."
stdout "$(openstack image list)"

stdout "Setting nameserver on the undercloud neutron subnet to the KVM host."

SUBNET_ID=$(neutron subnet-list | egrep -v -- '(----|cidr)' | awk '{print $2}')
neutron subnet-update ${SUBNET_ID} --dns-nameserver ${IPMI_IP}

if [[ ! -f ~/.ssh/id_rsa ]]
then
  ssh-keygen -q -N '' -f ~/.ssh/id_rsa 2>/dev/null
fi

stdout "Creating the instackenv.json file."

SSH_KEY=$(sed ':a;N;$!ba;s/\n/\\n/g' ~/.ssh/id_rsa)

cat >~/instackenv.json <<EOF
{
  "ssh-user": "${USER}",
  "ssh-key": "${SSH_KEY}",
  "power_manager": "nova.virt.baremetal.virtual_power_driver.VirtualPowerManager",
  "host-ip": "${IPMI_IP}",
  "arch": "x86_64",
  "nodes": [
EOF

CLOSE=''
for SERVER in $(cat ~/overcloud-servers.txt)
do
  NAME=$(echo ${SERVER} | awk -F\| '{print $1}')
  IPMI_IP=$(echo ${SERVER} | awk -F\| '{print $2}')
  MAC=$(echo ${SERVER} | awk -F\| '{print $3}')
  USER=$(echo ${SERVER} | awk -F\| '{print $4}')

cat >>~/instackenv.json <<EOF
${CLOSE}
    {
      "name": "${NAME}",
      "pm_addr": "${IPMI_IP}",
      "pm_password": "${SSH_KEY}",
      "pm_type": "pxe_ssh",
      "mac": [
        "${MAC}"
      ],
      "cpu": "1",
      "memory": "1024",
      "disk": "10",
      "arch": "x86_64",
      "pm_user": "${USER}"
EOF
CLOSE='    },'
done

cat >>~/instackenv.json <<EOF
    }
  ]
}
EOF

stdout "Copying SSH key for $(whoami) to the ${LIBVIRT_USER} on ${IPMI_IP}."
stdout "You will be prompted for a password."
echo "When prompted, enter: ${LIBVIRT_USER_PW}"

ssh-copy-id ${LIBVIRT_USER}@${IPMI_IP}

if [[ $? -ne 0 ]]
then
  stderr "Please check iptables/firewalld on your KVM host and ensure the undercloud VM can SSH to the KVM host."
  stderr "Once this is working, log into the undercloud as ${UNDERCLOUD_USER} and execute:"
  stderr ""
  stderr "ssh-copy-id ${LIBVIRT_USER}@${IPMI_IP}"
  stderr ""
fi

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""
