
function stdout {
  echo "[$(date +'%Y/%m/%d-%H:%M:%S')] $@"
  if [[ ! -z "${LOG}" ]]
  then
    echo "[$(date +'%Y/%m/%d-%H:%M:%S')] $@" >> ${LOG}
  fi
}

function stderr {
  echo "[$(date +'%Y/%m/%d-%H:%M:%S')] ERROR: $@"
  if [[ ! -z "${LOG}" ]]
  then
    echo "[$(date +'%Y/%m/%d-%H:%M:%S')] ERROR: $@" >> ${LOG}
    echo "[$(date +'%Y/%m/%d-%H:%M:%S')] ERROR: $@" >> ${LOG}.err
  fi
}

# Credits: http://www.linuxquestions.org/questions/programming-9/bash-cidr-calculator-646701/

function mask2cidr {
    nbits=0
    IFS=.
    for dec in $1 ; do
        case $dec in
            255) let nbits+=8;;
            254) let nbits+=7;;
            252) let nbits+=6;;
            248) let nbits+=5;;
            240) let nbits+=4;;
            224) let nbits+=3;;
            192) let nbits+=2;;
            128) let nbits+=1;;
            0);;
            *) echo "Error: $dec is not recognised"; exit 1
        esac
    done
    echo "$nbits"
}

# Credits: http://www.linuxquestions.org/questions/programming-9/bash-cidr-calculator-646701/

function cidr2mask() {
  local i mask=""
  local full_octets=$(($1/8))
  local partial_octet=$(($1%8))

  for ((i=0;i<4;i+=1)); do
    if [ $i -lt $full_octets ]; then
      mask+=255
    elif [ $i -eq $full_octets ]; then
      mask+=$((256 - 2**(8-$partial_octet)))
    else
      mask+=0
    fi  
    test $i -lt 3 && mask+=.
  done

  echo $mask
}

function wait4reboot {
  IP=$1
  RC=1
  while [[ ${RC} -ne 0 ]]
  do
    ssh -o StrictHostKeyChecking=no root@${IP} 'hostname' >/dev/null 2>/dev/null
    RC=$?
  done
}

function kvm_snapshot {
  VM=$1
  SNAP_INFO=$2
  MAX_SNAP=10

  SUDO=''

  if [[ "$(whoami)" != "root" ]]
  then
    if [[ "$(sudo whoami)" != "root" ]]
    then
      stderr 'Can not create snapshot, need root capabilities.'
      return
    else
      SUDO='sudo'
    fi
  fi

  if [[ ! -z "$(${SUDO} virsh snapshot-list undercloud | grep ${SNAP_INFO})" ]]
  then
    X=1
    while [[ ! -z "$(${SUDO} virsh snapshot-list undercloud | grep ${SNAP_INFO}-${X})" ]]
    do
      X=$(( ${X} + 1 ))
      if [[ ${X} -eq ${MAX_SNAP} ]]
      then
        stderr "More than ${MAX_SNAP} exist with the info ${SNAP_INFO} for ${VM}."
        stderr "Not taking snapshot."
        return
      fi
    done
    SNAP_INFO="${SNAP_INFO}-${X}"
  fi

  if [[ -z "$(${SUDO} virsh snapshot-list undercloud | grep ${SNAP_INFO})" ]]
  then
    stdout "Taking snapshot of ${VM} as ${SNAP_INFO}."
    ${SUDO} virsh snapshot-create-as ${VM} ${SNAP_INFO}
    ${SUDO} virsh snapshot-list ${VM}
  fi

}
