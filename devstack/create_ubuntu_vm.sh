#!/bin/bash

# This script creates an ubuntu VM, ready for devstack installation.
# How to use the script?
# Make sure all dependencies installed: libvirt, libvirt-utils, libosinfo, libguestfs-tools, virt-install
# Put it in a directory where a generic ubuntu cloud image file is located and make the script executable.
# Adjust parameters (if needed) and run the script.
# Recommended to run from /var/lib/libvirt/images directory.

GENERIC_CLOUD_IMAGE=focal-server-cloudimg-amd64.img
DISK_SIZE=25
RAM_SIZE=6144
NUM_CPUS=8
VM_OS=ubuntu
VM_OS_VERSION=20.04
VM_ROOT_PASS=$VM_OS
TIMESTAMP=-$(date +%m%d-%H%M)
VM_NAME="${VM_OS}${TIMESTAMP}"

[ ! -e $GENERIC_CLOUD_IMAGE ] && echo Please make sure you have file $GENERIC_CLOUD_IMAGE in current directory && exit 1

echo This is going to create an ${VM_OS}${VM_OS_VERSION} VM with memory size ${RAM_SIZE}MB, disk size ${DISK_SIZE}GB and $NUM_CPUS CPUs
read -p "Are you going to proceed with existing parameters[y/n]? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then

  echo Creating a disk image for a new VM
  qemu-img create -f qcow2 ${VM_NAME}.qcow2 ${DISK_SIZE}G
  
  echo Resizing file system
  virt-resize --expand /dev/sda1 ${GENERIC_CLOUD_IMAGE} ${VM_NAME}.qcow2
  
  echo Modifying root user credentials
  virt-customize -a ${VM_NAME}.qcow2 --root-password password:${VM_ROOT_PASS} --uninstall cloud-init
  
  # For some reason ssh service was failing to start in ubuntu 20.04. Reinstalling ssh service fixes the issue.
  echo Modifying ssh installation
  virt-customize -a ${VM_NAME}.qcow2 --run-command 'apt-get purge openssh-server -y && apt-get install openssh-server -y'
  
  echo Create user stack
  virt-customize -a ${VM_NAME}.qcow2 --run-command 'useradd -s /bin/bash -d /opt/stack -m stack'
  
  echo Add user stack to sudoers
  virt-customize -a ${VM_NAME}.qcow2 --run-command 'echo "stack ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/stack '
  
  echo Set password 'stack' for user 'stack'
  virt-customize -a ${VM_NAME}.qcow2 --run-command 'echo "stack:stack" | chpasswd'
  
  echo Injecting ssh key for user 'stack'
  virt-customize -a ${VM_NAME}.qcow2 --ssh-inject stack:file:$HOME/.ssh/id_rsa.pub
  
  echo Setting hostname
  virt-customize -a ${VM_NAME}.qcow2 --hostname $VM_NAME
  
  # For some reason the resizing of file systems (see above) breaks image boot. This step fixes VM boot. 
  echo Updating grub in the VM image
  virt-customize -a ${VM_NAME}.qcow2 --run-command 'grub-install /dev/sda'
  
  osinfo-query os | grep -q ${VM_OS}${VM_OS_VERSION}
  if [ $? -eq 0 ]; then
    OS_PARAM="--os-variant ${VM_OS}${VM_OS_VERSION}"
    INTERFACE="enp1s0"
  else
    INTERFACE="ens3"
  fi

  echo Create netplan config file
  /bin/cat <<EOF > /tmp/config.yaml 
network:
    version: 2
    renderer: networkd
    ethernets:
        $INTERFACE:
            dhcp4: true
EOF
  
  echo Adding netplan config
  virt-customize -a ${VM_NAME}.qcow2 --copy-in  /tmp/config.yaml:/etc/netplan
 
  echo Starting VM
  sudo virt-install --ram $RAM_SIZE --vcpus $NUM_CPUS $OS_PARAM --disk path=${VM_NAME}.qcow2,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network network:default --name $VM_NAME

  echo Waiting until VM completes boot and get an ip address
  num_attempts=0
  while true; do
      num_attempts=$((num_attempts+1))
      sleep 5
      IP=$(sudo virsh net-dhcp-leases default | grep $VM_NAME | awk '{print $5}' | sed 's/\(.*\)\/.*/\1/g')
      if [ "$IP" != "" ]; then
          break
      else
          [ $num_attempts -gt 12 ] && echo "Unable to get VMs IP within 60 seconds. Something went wrong." && exit 1
      fi
  done
 
  echo Now you can connect to the VM using ssh stack@$IP. Trying to connect...
  ssh -o StrictHostKeyChecking=no  -o UserKnownHostsFile=/dev/null  stack@$IP

fi

