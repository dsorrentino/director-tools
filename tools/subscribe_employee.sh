#!/bin/bash


# Make sure we are running this on a RHEL server....

if [[ -z "$(grep 'Red Hat Enterprise Linux Server' /etc/redhat-release 2>/dev/null)" ]]
then
  echo "Error: Not a Red Hat Enterprise Linux Server. Exiting."
  exit 1
fi

which subscription-manager >/dev/null 2>&1

if [[ $? -ne 0 ]]
then
  echo "Error: Can't find program subscription-manager.  You have bigger issues."
  echo "Good luck!"
  exit 1
fi


# Get the subscription status

SM_STATUS=$(subscription-manager status | grep '^Overall Status' | awk '{print $NF}')

# See if we are creating or deleting or providing usage info

if [[ ! -z "$(echo $@ | grep delete)" ]]
then
  # Removing system. Really don't care about the state, so unsubscribe/unregsiter
  echo "Unsubscribing all channels."
  subscription-manager remove --all 2>/dev/null
  echo "Unregistering system."
  subscription-manager unregister 2>/dev/null
elif [[ ! -z "$(echo $@ | grep create)" ]]
then
  # See if we are registered or not.  If not, register.
  if [[ "${SM_STATUS}" == "Unknown" ]]
  then
    echo "Warning: This system is not registered with RHN.  Registering now."
    echo "         Provide appropriate credentials when prompted."
    subscription-manager register
    SM_STATUS=$(subscription-manager status | grep '^Overall Status' | awk '{print $NF}')
  fi

  # An Invalid state means registered but not subscribed.  So subscribe.
  if [[ "${SM_STATUS}" == "Invalid" ]]
  then
    echo "Obtaining Employee SKU Pool ID."
    POOL_ID=$(subscription-manager list --available | egrep 'Subscription Name|Pool ID' | grep -A1 'Employee SKU' | grep 'Pool ID' | head -1 | awk '{print $NF}')

    echo "Employee SKU Pool ID: ${POOL_ID}"
    echo "Attaching this system. If you experience a timeout, simply re-run this script with the 'create' argument."
    subscription-manager attach --pool ${POOL_ID}
    echo "Done."
  fi
else
  echo ""
  echo "Usage:"
  echo "  $0 create # Registers/subscribes to Employee SKU for your RHN account."
  echo "  $0 delete # Unsubscribes/unregisters from your RHN account."
  echo ""
fi

echo "Subscription status:"

subscription-manager status
