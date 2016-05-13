#!/bin/bash

SCRIPT_NAME=remote_configure_undercloud-1

source undercloud.env
source common.sh

LOG="${SCRIPT_NAME}.log"

stdout ""
stdout "${SCRIPT_NAME} start"
stdout ""

if [[ -z "$(sudo subscription-manager status | grep 'Overall Status: Current')" ]]
then
  stderr ""
  stderr "You must subscribe the Undercloud VM to repositories before continuing."
  stderr ""
  stderr "Exiting."
  stderr ""
  exit 300
fi
stdout "Creating images and templates directory in the '${UNDERCLOUD_USER}' home directory."

mkdir ~/images
mkdir ~/templates

stdout "Configuring repositories."
stdout "$(sudo subscription-manager repos --disable=*)"
stdout $(sudo subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-extras-rpms --enable=rhel-7-server-openstack-8-rpms --enable=rhel-7-server-openstack-8-director-rpms --enable rhel-7-server-rh-common-rpms)

stdout "Performing a 'clean all' then an update."
stdout "$(sudo yum clean all)"
stdout "$(sudo yum update -y)"

stdout ""
stdout "${SCRIPT_NAME} end"
stdout ""
