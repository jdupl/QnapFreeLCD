#!/usr/bin/ksh
#
# function library sample for lcd-control, version 0.1
# written by Dirk Brenken (dibdot@gmail.com)
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
#
# Have fun!
# Dirk
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
# 1. example
# get host and ip address
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
HOST="$(hostname)"
IP="$(hostname -i)"
# result
ROW[${INDEX}]="${HOST}"
(( INDEX ++ ))
ROW[${INDEX}]="${IP}"

#-------------------------------------------------------------------------------
# 2. example
# get kernel information
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
KERNEL=$(uname -r)
# result
ROW[${INDEX}]="DEBIAN/SID"
(( INDEX ++ ))
ROW[${INDEX}]="${KERNEL}"

#-------------------------------------------------------------------------------
# 3. example
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
# 4. example
# get raid status
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
MDADM_INFO=$(mdadm -D /dev/md0)
R_LEVEL=$(echo "$MDADM_INFO"| grep -o "raid[0-9].*")
R_STATE=$(echo "$MDADM_INFO"| grep -o "State :.*")
R_DEVICES=$(echo "$MDADM_INFO"| grep -o " /dev/s.*")
# result
ROW[${INDEX}]="MD0 : ${R_LEVEL}"
(( INDEX ++ ))
ROW[${INDEX}]="${R_STATE}"
(( INDEX ++ ))

#-------------------------------------------------------------------------------
# 5. example
# get hdd temperature (re-use raid device information)
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
DEVICES="${R_DEVICES}"
DRIVE_TEMPS=$(echo $(hddtemp -n ${DEVICES}))
DRIVE_TEMPS="${DRIVE_TEMPS// /  }"
# result
ROW[${INDEX}]="Drive Temp."
(( INDEX ++ ))
ROW[${INDEX}]="${DRIVE_TEMPS}"
(( INDEX ++ ))

#-------------------------------------------------------------------------------
# 6. example
# get current cpu load
#-------------------------------------------------------------------------------
#
# get current index count as start value
INDEX=${#ROW[@]}
# query
PREV_TOTAL=0
PREV_IDLE=0
cat /proc/stat | grep "^cpu " | \
while read scrap user nice system idle iowait irq softirq stealtime virtual1 virtual2
do
    (( CPU_TOTAL = user + nice + system + idle + iowait + irq + softirq + stealtime + virtual1 + virtual2 ))
    (( CPU_IDLE = idle ))
done
(( DIFF_IDLE= CPU_IDLE - PREV_IDLE ))
(( DIFF_TOTAL= CPU_TOTAL - PREV_TOTAL ))
(( DIFF_USAGE= 1000 * (DIFF_TOTAL - DIFF_IDLE) / DIFF_TOTAL ))
(( DIFF_USAGE_UNITS = DIFF_USAGE / 10 ))
(( DIFF_USAGE_DECIMAL = DIFF_USAGE % 10 ))
(( PREV_TOTAL = CPU_TOTAL ))
(( PREV_IDLE = CPU_IDLE ))
# result
ROW[${INDEX}]="CPU load"
(( INDEX ++ ))
ROW[${INDEX}]="${DIFF_USAGE_UNITS}.${DIFF_USAGE_DECIMAL}"
(( INDEX ++ ))

