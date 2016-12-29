#!/usr/bin/ksh
#
# function library sample for lcd-control, version 0.2
# original author Dirk Brenken (dibdot@gmail.com)
# modified by Justin Duplessis (drfoliberg@gmail.com)
#
#   LICENSE
#   ============
#   QnapFreeLcd Copyright (C) 2014 Dirk Brenken and Justin Duplessis
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see <http://www.gnu.org/licenses/>.
#
#
# GET STARTED
# ============
# This is a sample script to gather and prepare system information for a QNAP TS-439 box with 2x16 LCD display.
# It's a helper script which will be automatically sourced by lcd-control.ksh during runtime as input.
# All query results have to fill up the "ROW" array and increment the array index accordingly.
# Please make sure, that the result sets match your LCD dimensions/rows,
# For most QNAP boxes (maybe all?) every single result set should consist of two rows.
# Please keep in mind, that this function library acts as a normal shell script,
# therefore it might be a good idea to test your queries and result sets stand alone before lcd-control.ksh integration.
# Feel free to build your own system queries and result sets (see examples below).
# Contributions for other QNAP boxes or better examples to enlarge this function library are very welcome!
#
# CHANGELOG
# ==========
# version 0.1: initial test release
# version 0.2: added usable functions for out-of-box usage
#
# Have fun!
# 

# enable shell debug mode
#
#set -x

# treats unset variables as an error
#
set -u

# reset pre-defined message array
#
set -A ROW

#-------------------------------------------------------------------------------
# 1. network
# get host and ip address
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
HOST="$(hostname)"
IP=$(ifconfig | grep "inet addr" | cut -d: -f2 | cut -f 1 -d " " | grep -v "127.0.")
# result
ROW[${INDEX}]="${HOST}"
(( INDEX ++ ))
ROW[${INDEX}]="${IP}"

#-------------------------------------------------------------------------------
# 2. os/kernel
# get kernel and OS information
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
OS_LINE="Unknown";
if [ -f /etc/lsb-release ];then
	OS_LINE=$(cat /etc/lsb-release | grep -i DISTRIB_DESCRIPTION | cut -d "\"" -f 2)
elif [ -f /etc/os-release ];then
	echo "/etc/lsb-release not found, using /etc/os-release !"
	OS_NAME=$(cat /etc/os-release | grep ^ID= | cut -c 4-)
	OS_VERSION=$(cat /etc/os-release | grep -i ^Version= | cut -d "\"" -f 2)
	OS_LINE="$OS_NAME $OS_VERSION"
else
	echo "Could not find proper file to retreive OS info."
fi
#kernel info
KERNEL=$(uname -r)
# result
ROW[${INDEX}]=$OS_LINE
(( INDEX ++ ))
ROW[${INDEX}]="${KERNEL}"

#-------------------------------------------------------------------------------
# 3. root disk space
# get volume/space information
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
df -hlT |\
egrep "^/dev.*(ext3|ext4)" |\
sort -k7 |\
while read device type space used free percent mount
do
    # result
    ROW[${INDEX}]="${mount}  ${type}"
    (( INDEX ++ ))
    ROW[${INDEX}]="${space}  ${free}  ${percent}"
    (( INDEX ++ ))
done

#-------------------------------------------------------------------------------
# 4. Pool info (zfs or mdadm)
# detect which is installed and hoe many pools are present
#-------------------------------------------------------------------------------
#
ZFS_POOLS=0
MDADM_POOLS=0
R_DEVICES=""

if (( $(whereis zfs | wc -w) != 1 ))
then
	ZFS_POOLS=$(zpool list -H | wc -l)
	echo "Found $ZFS_POOLS zfs pools !"
fi

if (( $(whereis mdadm | wc -w) != 1 ))
then
	MDADM_POOLS=$(ls -1 /dev/md*  | egrep /dev/md'[0-9]+' | wc -l)
	echo "Found $MDADM_POOLS mdadm pools !"
fi

#-------------------------------------------------------------------------------
# 4.1 Pool info zfs
# TODO add support for multiple pools ?
#-------------------------------------------------------------------------------
#
# get current index count as start value
if (( $ZFS_POOLS > 0 ))
then
	INDEX=${#ROW[@]}
	# query
	PREV_TOTAL=0
	PREV_IDLE=0
	FREE=$(zpool list -H | cut -f 4)
	HEALTH=$(zpool list -H | cut -f 7)
	CAP=$(zpool list -H | cut -f 5)
	# result
	ROW[${INDEX}]="$(zpool list -H | cut -f 1) $(zpool list -H | cut -f 2)"
	(( INDEX ++ ))
	ROW[${INDEX}]="$FREE $CAP-$HEALTH"
	(( INDEX ++ ))
	R_DEVICES=$(zpool status | grep sd | awk '{print "/dev/"$1}')
fi

#-------------------------------------------------------------------------------
# 4.2 Mdadm info
# get mdadm info (btw you should use ZFS or Btrfs)
# TODO add support for multiple pools ?
#-------------------------------------------------------------------------------
#
# get current index count as start value
if (( $MDADM_POOLS > 0 ))
then
	for ARRAY in $(ls -1 /dev/md*  | egrep /dev/md'[0-9]+')
	do
		INDEX=${#ROW[@]}
		# query
		MDADM_INFO=$(mdadm -D $ARRAY)
		R_LEVEL=$(echo "$MDADM_INFO"| grep -o "raid[0-9].*")
		R_STATE=$(echo "$MDADM_INFO"| grep -o "State :.*")
		R_DEVICES=$(echo "$MDADM_INFO"| grep -o " /dev/s.*")
		# result
		ROW[${INDEX}]="$(echo $ARRAY | cut -d "/" -f 3) : ${R_LEVEL}"
		(( INDEX ++ ))
		ROW[${INDEX}]="${R_STATE}"
		(( INDEX ++ ))
	done
fi


#-------------------------------------------------------------------------------
# 5. HDD temps
# get hdd temperature (re-use device information from zfs)
#-------------------------------------------------------------------------------
#
# get current index count as start value
if [ "$R_DEVICES" != "" ]; then
	INDEX=${#ROW[@]}
	# query
	DEVICES="${R_DEVICES}"
	DRIVE_TEMPS=$(echo $(hddtemp -n ${DEVICES}))
	TEMP_MAX=$(echo $DRIVE_TEMPS | sed -e 's/\s\+/\n/g' | sort -n | tail -n 1)
	TEMP_MIN=$(echo $DRIVE_TEMPS | sed -e 's/\s\+/\n/g' | sort -n | head -n 1)
	# result
	ROW[${INDEX}]="Drive Temp"
	(( INDEX ++ ))
	ROW[${INDEX}]="MIN: $TEMP_MIN MAX: $TEMP_MAX"
	(( INDEX ++ ))
else
	echo "No devices were found to probe for temperature !"
fi
#-------------------------------------------------------------------------------
# 6. CPU load
# get current cpu load
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
PREV_TOTAL=0
PREV_IDLE=0
# result
ROW[${INDEX}]="Load Average"
(( INDEX ++ ))
ROW[${INDEX}]=$(cat /proc/loadavg | cut -d " " -f 1,2,3)
(( INDEX ++ ))

#-------------------------------------------------------------------------------
# 7. update
# display uptime
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
PREV_TOTAL=0
PREV_IDLE=0
# result
ROW[${INDEX}]="Uptime"
(( INDEX ++ ))
ROW[${INDEX}]=$(uptime | grep -ohe 'up .*' | sed 's/,//g' | awk '{ print $2" "$3 }')
(( INDEX ++ ))

#-------------------------------------------------------------------------------
# 8. last update
# display the data update time
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
PREV_TOTAL=0
PREV_IDLE=0
# result
ROW[${INDEX}]="Last Updated"
(( INDEX ++ ))
ROW[${INDEX}]=$(date +"%T %D")
(( INDEX ++ ))
