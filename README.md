The initial purpose of these scripts is to make it easy to get an undercloud VM and overcloud VM's up and running on a KVM host.

Eventually I'd like to expand these scripts so they can possibly provide some of the functionality below to a cloud utilizing
physical hosts.

The function of each script is broken down below.  The framework is driven off of the 3 environmental files located in the
config directory which contain all of the base settings for the environment:

environment/director-tools.env
environment/undercloud.env
environment/overcloud.env

As a "to do", I'd like to have each script take a '--default' argument which will disable the prompting systems and just drive
everything off of the 2 environmental files in the config directory.

Before running any of these files, you must configure DIRECTOR_TOOLS variable in environment/director-tools.env to point to where you
installed these scripts.

Script: undercloud_create_vm.sh
Description: To be used to create the VM which Director will be installed on
Functions:
  - Configures KVM
    - Configures nested virtualization
    - On Intel CPU's, enables the following additional options:
        enable_shadow_vmcs=1
        enable_apicv=1
        ept=1
    - Configures rp_filter settings
    - Configures policy kit file for the user Ironic will use for power management
    - Installs all necessary virtualization packages
  - Configured networking for the undercloud
    - Can create the KVM networks if this is a LAB/all virtual setup
    -  BETA (needs to be tested): Can configure the VM to use physical networks by either using existing network bridges
       or creating the necessary bridges.  
  - Gather specs (CPU, Memory, Disk, IP addresses for both infrastructure & provisioning networks) for the Undercloud VM
  - Obtains base RHEL image from specified source
  - Creates disk for undercloud VM to spec
  - Removes cloud-init package from the undercloud image
  - Sets the root password for the undercloud VM in the undercloud image
  - Configures the network interface files in the undercloud image
  - Boots undercloud VM using DHCP
  - Copies SSH keys to the undercloud VM
  - Configures static networking on the undercloud VM
  - Updates /etc/host on undercloud VM
  - Adds the undercloud user to the VM
  - Sets the password for the undercloud user
  - Configures sudo for the undercloud user
  - Reboots the VM
  - Takes a snapshot of the VM at completion
  - Copies all logs into the logs directory

Script: undercloud_configure.sh
Description: This script will configure the VM to install the Director packages.  The VM may or may not have been created
             by the undercloud_create_vm.sh script.  If it was not created by that script, ensure you've configured the
             environment/undercloud.env by hand for the following variables:
            
             UNDERCLOUD_IP
             UNDERCLOUD_USER
             UNDERCLOUD_USER_PW

Functions:
  - Copies SSH key to the Undercloud user
  - Creates the images and templates directory in the Undercloud user home directory
  - Configures repositories to install the undercloud packages
  - Performs a yum update
  - Reboots the Undercloud VM
  - Installs the python-tripleoclient package
  - Creates the undercloud.conf file through a guided prompting system
  - Copies the undercloud.conf to the Undercloud user home directory
  - Takes a snapshot of the VM at completion
  - Copies all logs into the logs directory

Script: undercloud_deploy.sh
Description: This runs the 'openstack undercloud install' command and logs the output.  Upon completion
             it copies the logs back down to the DIRECTOR_INSTALL/logs directory.
Functions:
  - Execute openstack undercloud install
  - Takes a snapshot of the VM at completion
  - Copies all logs into the logs directory

Script: overcloud_create_vms.sh
Description: Used for creating a lab-like environment on a single KVM host. The defaults for number and
             size of the VM's is obtained from environment/overcloud.env.  User is prompted for settings
             and changes are persisted to the file for future runs.
Functions:
  - Prompts & creates the various networks for the overcloud
  - Number of NIC's is configureable for each node type (control, compute, ceph-storage)
  - Configures NAT for networks designated as External or Floating IP networks
  - Prompts and deletes any previous VM's with *overcloud* in the name
  - Gather specs (CPU, Memory, Disk count, Disk size and node count) for each node type (controller, compute, ceph)
  - Gather specs (Disk count, Disk size) for OSD drives for ceph
  - Creates all necessary disk files
  - Connects KVM networks to specific NIC ports to help in replicating a customer environment
  - Creates an instackenv.json file in the Undercloud user home directory that is ready for introspection
  - Installs the overcloud images RPM and extracts the images into the appropriate images directory in the Undercloud user home directory
  - Sets the root password on the overcloud image
  - Uploads the images into glance
  - Configures the DNS nameserver on the Neutron network to point to the KVM host
  - Copies the SSH key back down to the KVM host for Ironic to use for power management
    NOTE:  You must have iptables/firewalld configured on your KVM host to allow this connection to occur
  - Takes a snapshot of the VM at completion
  - Copies all logs into the logs directory
