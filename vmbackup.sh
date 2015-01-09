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
	vm_name=$1
	lvm_path=$2
	backup_file=$3/$1".img"
	
	echo $backup_file
	
	lvcreate -L2G -s -n $vm_name"_s" $lvm_path
	dd if=$lvm_path"_s" of=$backup_file
	
	if [ ! $? ]; then
		echo "dd failed running: !!"
		return 1
	fi
	
	if [ ! -s $backup_file ]; then
		echo "$backup_file could not be created"
		return 1
	fi

	lvremove $lvm_path"_s" -f
	if [ ! $? ]; then
		echo "Snapshot removal failed"
	fi
	echo "$lvm_path backed up to $backup_file"
}

# $1 = name of logical volume/VM
# $2 = path to backup folder
backup_qemu() {
	vm_name=$1
	backup_target=$2

	virsh dumpxml $vm_name > $backup_folder/$vm_name.xml
	if [ ! $? ]; then
		echo "Error dumping VM XML definition"
		return 1
	fi
	echo "qemu XML backed up to $backup_target.xml"
}

# $1 = path to logical volume
# $2 = vm name
does_vm_exist(){
	lvm_path=$1
	vm_name=$2
	
	if [ ! -h $lvm_path ]; then
		echo "A logical volume does not exist at $lvm_path"
		return 1
	fi
	if ! virsh list --all --name | grep -q -i $vm_name; then
		echo "A virtual machine named $vm_name does not exist"
		return 1
	fi
}

# $1 = VM name
# $2 = path to VM backup folder
compress_vm(){
	vm_name=$1
	backup_folder=$2
	
	cd $backup_folder
	
	echo "Compressing $vm_name"
	tar -zcvf $vm_name.tar.gz $vm_name".img" $vm_name".xml"
	
	if [ ! $? ]; then
		echo "Compression failed running: !!"
		echo "Exiting to preserve backup files"
		return 1
	fi
	rm $vm_name".img" -f
	rm $vm_name".xml" -f
}

# $1 = backup folder
cycle_backups(){
	backup_folder=$1
	
	cd $backup_folder
	rm weekly3 -rf
	mv weekly2 weekly3
	mv weekly1 weekly2
	mkdir weekly1
	mv temp/* weekly1/
}

# $1 = backup folder
create_folders(){
	backup_folder=$1

	mkdir -p $backup_folder
	cd $backup_folder
	
	if [ ! -d weekly3 ]; then
		mkdir weekly3
	fi
	if [ ! -d weekly2 ]; then
		mkdir weekly2
	fi
	if [ ! -d weekly1 ]; then
		mkdir weekly1
	fi
	if [ ! -d temp ]; then
		mkdir temp
	fi
}

# $1 = vm name
# $2 = path to volume group
# $3 = path to backup folder
backup_vm(){
	vm_name=$1
	logical_volume=$2/$1
	temp_folder=$3/"temp"
	
	echo "Backing up $vm_name..."
	if ! does_vm_exist $logical_volume $vm_name; then
		echo "Aborting backup of $vm_name"
		return 1
	fi
	
	if ! create_snapshot $vm_name $logical_volume $temp_folder; then
		echo "Snapshot of $logical_volume failed"
		return 1
	fi
	
	if ! backup_qemu $vm_name $temp_folder; then
		echo "Could not dump XML definition of VM $vm_name"
		return 1
	fi
	
	compress_vm $vm_name $temp_folder
	
	echo "Backup of $vm_name completed."
}


### Execution Starts Here ###

lvm_path=$1
backup_folder=$2
backup_targets=$3

create_folders $backup_folder
cd $backup_folder/vmbackup

while read vm_name
do
	backup_vm $vm_name $lvm_path $backup_folder
done < $backup_targets

cycle_backups $backup_folder
