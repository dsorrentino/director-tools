#!/bin/sh

SCRIPT_NAME="configure_kvm"

LOG=${DIRECTOR_TOOLS}/logs/${SCRIPT_NAME}.log

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

SUDO=''
KVM_MODULE_CONF=''
PKG_MGR='yum'
KVM_OPTION=()

if [[ "$(whoami)" != "root" ]]
then
  stdout "WARNING: Expected this to be run as root."
  if [[ "$(sudo whoami)" != "root" ]]
  then
    stderr 'Terminating deployment.'
    exit 1
  else
    stdout "Verified user has sudo capabilities.  Will use sudo as needed."
    SUDO='sudo'
  fi
fi

if [[ ! -z "$(grep 'Red Hat Enterprise Linux Server' /etc/redhat-release)" ]]
then
  PKG_MGR=yum
elif [[ ! -z "$(grep 'Fedora' /etc/redhat-release)" ]]
then
  PKG_MGR=dnf
else
  stderr "Script must be run on either RHEL or Fedora baremetal host."
  exit 10
fi


${SUDO} ${PKG_MGR} update -y

CPU_VENDOR=$(cat /proc/cpuinfo  | grep ^vendor_id | sort -u | awk '{print $NF}')

if [[ "${CPU_VENDOR}" == "GenuineIntel" ]]
then
  CPU_VENDOR=intel
  KVM_OPTION[1]='options kvm-intel nested=1'
  KVM_OPTION[2]='options kvm-intel enable_shadow_vmcs=1'
  KVM_OPTION[3]='options kvm-intel enable_apicv=1'
  KVM_OPTION[4]='options kvm-intel ept=1'
elif [[ "${CPU_VENDOR}" == "AuthenticAMD" ]]
then
  CPU_VENDOR=amd
  KVM_OPTION[1]='options kvm-amd nested=1'
else
  CPU_VENDOR=''
fi

if [[ -z "${CPU_VENDOR}" ]]
then
  stderr "Unknown CPU Vendor."
  cat /proc/cpuinfo  | grep ^vendor_id | sort -u | awk '{print $NF}'
  exit 100
fi

stdout "Detected CPU Vendor: ${CPU_VENDOR}"

KVM_MODULE_CONF=/etc/modprobe.d/kvm_${CPU_VENDOR}.conf

if [[ ! -f ${KVM_MODULE_CONF} ]]
then
  ${SUDO} touch ${KVM_MODULE_CONF}
  ${SUDO} chmod 644 ${KVM_MODULE_CONF}
fi

REBOOT=0
ERROR_COUNT=0

for X in $(seq 1 20)
do
  if [[ ! -z "${KVM_OPTION[${X}]}" ]]
  then
    OPTION=${KVM_OPTION[${X}]}
    RESULT=$(grep "${OPTION}" ${KVM_MODULE_CONF})
    if [[ -z "${RESULT}" ]]
    then
      stdout "Adding KVM option:"
      echo "${OPTION}" | ${SUDO} tee -a ${KVM_MODULE_CONF}
    else
      stdout "KVM already configured with: ${OPTION}"
    fi
    echo ""
  fi
done

RP_FILTER_CONF=/etc/sysctl.d/98-rp-filter.conf

RP_FILTER_SETTING[1]='net.ipv4.conf.default.rp_filter = 0'
RP_FILTER_SETTING[2]='net.ipv4.conf.all.rp_filter = 0'

for X in $(seq 1 10)
do
  if [[ ! -z "${RP_FILTER_SETTING[${X}]}" ]]
  then
    SETTING=${RP_FILTER_SETTING[${X}]}
    RESULT=$(grep "${SETTING}" ${RP_FILTER_CONF} 2>/dev/null)
    if [[ -z "${RESULT}" ]]
    then
      stdout "Adding rp_filter setting:"
      echo "${SETTING}" | ${SUDO} tee -a ${RP_FILTER_CONF}
      echo ""
    fi
  fi
done

CORE_COUNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo)

if [[ ${CORE_COUNT} -gt 0 ]]
then
  stdout "Core count: ${CORE_COUNT}"
else
  stderr "Hardware assisted virtualization not found.  Core count: ${CORE_COUNT}"
  ERROR_COUNT=$(( ${ERROR_COUNT} + 1 ))
fi

${SUDO} modprobe kvm && ${SUDO} modprobe kvm_intel

if [[ $? -ne 0 ]]
then
  ERROR_COUNT=$(( ${ERROR_COUNT} + 1 ))
fi

${SUDO} ${PKG_MGR} install libvirt qemu-kvm virt-manager virt-install libguestfs-tools libguestfs-xfs -y

if [[ $? -ne 0 ]]
then
  ERROR_COUNT=$(( ${ERROR_COUNT} + 1 ))
fi

${SUDO} systemctl enable libvirtd && ${SUDO} systemctl start libvirtd

if [[ $? -ne 0 ]]
then
  ERROR_COUNT=$(( ${ERROR_COUNT} + 1 ))
fi

WORKING_FILE=$(mktemp)

cat << EOF > ${WORKING_FILE}
[libvirt Management Access]
Identity=unix-user:${LIBVIRT_USER}
Action=org.libvirt.unix.manage
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

${SUDO} cp ${WORKING_FILE} /etc/polkit-1/localauthority/50-local.d/50-libvirt-user-${LIBVIRT_USER}.pkla
${SUDO} chmod 0644 /etc/polkit-1/localauthority/50-local.d/50-libvirt-user-${LIBVIRT_USER}.pkla

if [[ ${ERROR_COUNT} -gt 0 ]]
then
  stderr "Errors occurred."
  stderr 'Terminating deployment.'
  exit 100
fi

if [[ ${REBOOT} -gt 0 ]]
then
  stdout "Rebooting for changes to take effect."
  sleep 3
  stdout "configure_kvm.sh end"
  reboot --reboot
fi

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
