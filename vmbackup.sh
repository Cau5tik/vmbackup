#!/bin/bash

if [ "$#" -ne  3 ]; then

	echo "This script will make a backup of a VM by copying its logical volume and backing up its qemu XML file"
	echo -e "\e[1;32m"
	echo "Syntax:"
	echo "	vmbackup.sh [VM name] [path to logical volume group] [path to backup folder]"
	echo -e "\e[0m"
	echo "Trailing slashes should not be used on paths"

	exit 1
fi

# $1 = name of the logical volue/VM
# $2 = path to logical volume
# $3 = path to backup folder
create_snapshot(){
	lvcreate -L2G -s -n $1"_s" $2
	dd if=$2"_s" of=$3/$1.img
	
	if [ ! -s $3/$1.img ]; then
		echo "Error creating  logical volume backup"
		exit 1
	fi

	lvremove $2"_s" -f
	if [ ! $? ]; then
		echo "Snapshot removal failed"
	fi
	echo "$2 backed up to $3/$1.img"
}

# $1 = name of logical volume/VM
# $2 = path to backup folder
backup_qemu() {
	virsh dumpxml $1 > $2/$1.xml
	if [ ! $? ]; then
		echo "Error dumping VM XML definition"
		exit 1
	fi
	echo "qemu XML backed up to $2/$1.xml"
}

# $1 = path to logical volume
# $2 = vm name
is_it_safe(){
	if [ ! -h $1 ]; then
		echo "A logical volume does not exist at $1"
		exit 1
	fi
	if ! virsh list --all --name | grep -q $2; then
		echo "A virtual machine named $2 does not exist"
		exit 1
	fi
}

vm_name=$1
logical_volume=$2/$1
backup_folder=$3/$1

is_it_safe $logical_volume $vm_name

if [ ! -d $backup_folder ]; then
	mkdir -p $backup_folder
fi

create_snapshot $vm_name $logical_volume $backup_folder

backup_qemu $vm_name $backup_folder
