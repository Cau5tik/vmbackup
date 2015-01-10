#!/bin/bash

if [ "$#" -ne  3 ]; then

	echo "This script will make a backup of VMs in the same volume group by copying their logical volumes and backing up their qemu XML files."
	echo "It will also backup the config/metadata of the volume group in case it needs to be restored as well."
	echo -e "\e[1;32m"
	echo "Syntax:"
	echo "	vmbackup.sh [path to logical volume group] [path to backup folder] [backup_targets]"
	echo -e "\e[0m"
	echo "Where backup_targets is a newline separated list of VM names."
	echo "This script makes the assumption that a VM's logical volume has the same name as the VM and each VM has one logical volume."
	echo "Trailing slashes should not be used on paths"

	exit 1
fi

# $1 = name of the logical volue/VM
# $2 = path to logical volume
# $3 = path to backup folder
create_snapshot(){
	backup_file=$temp_folder/$vm_name".img"
	
	echo $backup_file
	
	lvcreate -L2G -s -n $vm_name"_s" $logical_volume

	dd if=$lvg_path/$vm_name"_s" of=$backup_file

	if [ ! $? ]; then
		echo "dd failed running: !!"
		return 1
	fi
	
	if [ ! -s $backup_file ]; then
		echo "$backup_file could not be created"
		return 1
	fi

	lvremove $logical_volume"_s" -f
	if [ ! $? ]; then
		echo "Snapshot removal failed"
	fi
	echo "Logical volume $vmname backed up to $backup_file"
}

backup_qemu() {
	virsh dumpxml $vm_name > $temp_folder/$vm_name.xml
	if [ ! $? ]; then
		echo "Error dumping VM XML definition"
		return 1
	fi
	echo "qemu XML backed up to $temp_folder/$vm_name.xml"
}

does_vm_exist(){
	if [ ! -h $logical_volume ]; then
		echo "A logical volume does not exist at $logical_volume"
		return 1
	fi
	if ! virsh list --all --name | grep -q -i $vm_name; then
		echo "A virtual machine named $vm_name does not exist"
		return 1
	fi
}

compress_vm(){
	cd $temp_folder
	
	echo "Compressing $vm_name in $backup_folder"
	tar -zcvf $vm_name.tar.gz $vm_name".img" $vm_name".xml"
	
	if [ ! $? ]; then
		echo "Compression failed running: !!"
		echo "Exiting to preserve backup files"
		return 1
	fi
	rm $vm_name".img" -f
	rm $vm_name".xml" -f
}

cycle_backups(){
	echo "Cycling backups in $backup_folder"
	echo ""

	cd $backup_folder
	rm weekly3 -rf
	mv weekly2 weekly3
	mv weekly1 weekly2
	mv temp weekly1
}

create_folders(){
	if [ ! -d $backup_folder/weekly3 ]; then
		mkdir -p $backup_folder/weekly3
	fi
	if [ ! -d $backup_folder/weekly2 ]; then
		mkdir -p $backup_folder/weekly2
	fi
	if [ ! -d $backup_folder/weekly1 ]; then
		mkdir -p $backup_folder/weekly1
	fi
	if [ ! -d $temp_folder ]; then
		mkdir -p $temp_folder
	fi
}

backup_vm(){
	logical_volume=$lvg_path/$vm_name
	
	echo "Backing up $vm_name..."
	if ! does_vm_exist; then
		echo "Aborting backup of $vm_name"
		backup_success=0
		return
	fi
	
	if ! create_snapshot; then
		echo "Snapshot of $logical_volume failed"
		backup_success=0
		return
	fi
	
	if ! backup_qemu; then
		echo "Could not dump XML definition of VM $vm_name"
		backup_success=0
		return
	fi
	
	compress_vm
	
	echo "Backup of $vm_name completed."
	echo ""
}

backup_lvg_config(){
	vgcfgbackup -f $temp_folder/vgcfgbackup $lvg_path
	echo ""
}


### Execution Starts Here ###

lvg_path=$1
backup_folder=$2
temp_folder=$backup_folder/temp
backup_targets=$3
backup_success=1

create_folders

while read vm_name
do
	backup_vm 
done < $backup_targets

backup_lvg_config

if [ $backup_success -eq 1 ]; then
	cycle_backups
	echo "Backup complete."
fi

if [ $backup_success -eq 0 ]; then
	echo "BACKUP FAILED: backups not cycled"
fi
