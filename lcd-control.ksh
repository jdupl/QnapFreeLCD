#!/usr/bin/ksh
#
# lcd-control, version 0.6
# Copyright (C) 2014, written by Dirk Brenken (dibdot@gmail.com)
#
# LICENSE
# ========
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# WARNING
# ========
# This is a developer version, at the time of writing it was only tested on a few QNAP devices (TS-439, TS-459, TS-509).
# Even though I use it in my productive environment, I strongly recommend that you only use it for further testing and debugging.
# This script is only for QNAP-devices which running debian (stock QNAP firmware currently not supported!).
#
# SCOPE
# ======
# Main script features:
# - read input for LCD status messages from a separate helper script (see sample function library)
# - display status messages on LCD panel
# - auto-cycling through status messages
# - non-blocking manual navigation via LCD frontpanel buttons between messages
# - error handling & logging to stdout/logfile (incl. logfile housekeeping)
# - fully configurable input-, message-,display- cycles & timeouts
#
# REQUIREMENTS
# =============
# - QNAP device with LCD display, migrated to debian
# - required debian package: ksh
# - optional debian package: hddtemp (to use function library sample)
#
# GET STARTED
# ============
# Make this script executable (chmod 755)
# Adjust script parameters to your needs (see comments for all configurable options below)
# Rename & adjust distributed sample function library script to your needs
# Start the script ...
#
# AUTOSTART
# ==========
# To start the script automatically during boot, simply add an appropriate entry to /etc/rc.local
# example: /<path>/lcd-control.ksh &
# Please modify INP_DIR and LOG_DIR to <path> accordingly
#
# CHANGELOG
# ==========
# version 0.1: initial test release
# version 0.2: fix trap/exit issues
# version 0.3: add automatic reload of message array after lights come back (thanks to Justin Duplessis)
# version 0.4: add GNU General Public License
# version 0.5: add/enhance rolling index navigation with frontpanel buttons
# version 0.6: add error handling & logging to stdout/logfile (incl. logfile housekeeping) plus various fixes/enhancements
#
# TODO
# =====
# - bugfixes
# - handle external events (command line mode)
# - ...
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

# script basics
#
SCRIPT_VER="0.6"
SCRIPT_PID=$$

# tty settings
# TTY_PRG     => reference to stty program (default: /bin/stty)
# TTY_TIMEOUT => tty read timeout in tenths of a second (default: 10)
#
TTY_PRG="/bin/stty"
TTY_TIMEOUT=10
TTY_MIN=0

# input settings
# INP_DIR     => reference to input directory (default: current directory)
# INP_FILE    => reference to function library (default: _lcd-functions.ksh)
# INP_PIPE    => reference to named pipe (default: /var/run/lcd.pipe)
# INP_TIMEOUT => input refresh timeout in seconds (default: 60), "0" (without quotes) to disable input auto-refresh
# INP_FD      => number of used file descriptor for named pipe (default: 5)
#
INP_DIR="."
INP_FILE="_lcd-functions.ksh"
INP_PIPE="/var/run/lcd.pipe"
INP_TIMEOUT=60
INP_FD=5
INP_BUFFER=""
INP_RT=0
INP_ID=0

# display environment/control codes
# LCD_DEV     => LCD device node (default: /dev/ttyS1)
# LCD_BAUD    => BAUD rate for LCD display (default: 1200)
# LCD_MAXROW  => number of display rows (default: 2)
# LCD_MAXCOL  => number of display cols (default:16)
# LCD_TIMEOUT => timeout of the LCD in seconds (default: 300), "0" (without quotes) to disable LCD timeout
#
LCD_DEV="/dev/ttyS1"
LCD_BAUD=1200
LCD_MAXROW=2
LCD_MAXCOL=16
LCD_TIMEOUT=300
LCD_ON="M\x5E\x1"
LCD_OFF="M\x5E\x0"
LCD_CODE="M\x0C\x"
LCD_CLEAR="M\x0D"
LCD_RESET="M\xFF"
LCD_RT=0
LCD_ID=0

# message settings
# MSG_TIMEOUT => timeout between the message blocks (default: 5), "0" (without quotes) to disable message auto-cycling
#
MSG_TIMEOUT=5
MSG_FILLER=" "
MSG_RT=0
MSG_ID=0

# logfile settings
# LOG_DIR     => reference to logfile directory (default: current directory)
# LOG_FILE    => reference to logfile (default: lcd-control.log), keep it empty to write to stdout
# LOG_HISTORY => delete logfiles older than n days (default: 5)
#
LOG_DIR="."
LOG_FILE="lcd-control.log"
LOG_HISTORY=5
LOG_COUNT=0

#===============================================================================#
# please do not change anything after this line!                                #
#===============================================================================#

#===============================================================================#
# functions                                                                     #
#===============================================================================#
# function for basic trap handling
#
function f_trap_exit
{
    #set -x
    # kill nav_pipe process
    kill -9 ${BG_PID}
    # close custom file descriptor
    exec {INP_FD}<&-
    exec {INP_FD}>&-
    # remove pipe from filesystem
    if [[ -f "${INP_PIPE}" || -p "${INP_PIPE}" ]]
    then
        rm -f "${INP_PIPE}"
    fi
    # clear LCD display & lights out
    printf "${LCD_CLEAR}" > "${LCD_DEV}"
    printf "${LCD_OFF}" > "${LCD_DEV}"
    # write message to log device and kill script
    LOG_MSG[0]="Info  => normal program termination!"
    f_logwrite
    kill -9 ${SCRIPT_PID}
}

# function to get button input and write it to nav pipe
#
function f_nav_pipe
{
    #set -x
    while :
    do
        # read button input
        INP_NAV=$(cat -vet "${LCD_DEV}")
        if [[ -n "${INP_NAV}" ]]
        then
            # filter/replace input stream
            INP_NAV="${INP_NAV//[!A-B]/}"
            INP_NAV="${INP_NAV//A/UP }"
            INP_NAV="${INP_NAV//B/DOWN }"
            # send only vaild input to nav pipe/custom file descriptor
            if [[ -n "${INP_NAV}" ]]
            then
                NAV_RT=0
                printf "%s\n" "${INP_NAV}" >&${INP_FD}
                printf "%s\n" "" >&${INP_FD}
            fi
        fi
    done
}

# function for log writing and logfile housekeeping
#
function f_logwrite
{
    #set -x
    if [[ -n "${LOG_FILE}" ]]
    then
        # generate separate logfile per day
        LOG_DATE=$(date "+%Y%m%d")
        LOG_DEVICE="${LOG_DIR}/${LOG_FILE}.${LOG_DATE}"
        # logfile housekeeping
        if [[ ! -f "${LOG_DEVICE}" ]]
        then
            DELETE_COUNT=$(find "${LOG_DIR}" -maxdepth 1 -type f  -mtime +${LOG_HISTORY} -name "${LOG_FILE}.*" 2>/dev/null | wc -l)
            if (( DELETE_COUNT > 0 ))
            then
                # delete logfiles older than n days
                find "${LOG_DIR}" -maxdepth 1 -type f  -mtime +${LOG_HISTORY} -name "${LOG_FILE}.*" -print0 2>/dev/null | xargs -0 rm -f >/dev/null 2>&1
                if (( $? == 0 ))
                then
                    LOG_MSG[0]="Info  => ${DELETE_COUNT} logfiles deleted!"
                else
                    LOG_MSG[0]="Error => old logfiles could not be deleted!"
                fi
            fi
            # reset log counter
            LOG_COUNT=0
        fi
    else
        # no logfile defined, redirect to stdout
        LOG_DEVICE="/dev/stdout"
    fi
    # write static header
    if (( LOG_COUNT == 0 ))
    then
        printf "%s\n" "lcd-control, version ${SCRIPT_VER}" >> "${LOG_DEVICE}"
        printf "%s\n" "Copyright (C) 2014, written by Dirk Brenken (dibdot@gmail.com)" >> "${LOG_DEVICE}"
        printf "%s\n" "This program is distributed in the hope that it will be useful," >> "${LOG_DEVICE}"
        printf "%s\n" "but WITHOUT ANY WARRANTY; without even the implied warranty of" >> "${LOG_DEVICE}"
        printf "%s\n" "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the" >> "${LOG_DEVICE}"
        printf "%s\n" "GNU General Public License for more details." >> "${LOG_DEVICE}"
        printf "%s\n" "==============================================================" >> "${LOG_DEVICE}"
        LOG_COUNT=1
    fi
    # write log message array
    LOG_INDEX=0
    MAX_INDEX=${#LOG_MSG[@]}
    while (( LOG_INDEX < MAX_INDEX ))
    do
        if [[ -n "${LOG_MSG[${LOG_INDEX}]}" ]]
        then
            LOG_DATE=$(date "+%Y%m%d %H:%M:%S")
            printf "%s\n" "${LOG_DATE}   ${LOG_MSG[${LOG_INDEX}]}" >> "${LOG_DEVICE}"
        fi
        (( LOG_INDEX++ ))
    done
    # write static footer and reset log message array
    printf "%s\n" "--------------------------------------------------------------" >> "${LOG_DEVICE}"
    unset LOG_MSG
}

#===============================================================================#
# main program                                                                  #
#===============================================================================#
# call trap function (EXIT, HUP, INT, QUIT, BUS, SEGV, TERM)
#
trap "f_trap_exit" 0 1 2 3 10 11 15

# prepare serial communication (send & receive)
#
"${TTY_PRG}" -F "${LCD_DEV}" ${LCD_BAUD} cread cbreak olcuc time ${TTY_TIMEOUT} min ${TTY_MIN}
if (( $? == 0 ))
then
    LOG_MSG[0]="Info  => serial port initialized!"
    f_logwrite
else
    LOG_MSG[0]="Error => serial port could not be initialized!"
    f_logwrite
    f_trap_exit
fi

# create named pipe
#
if [[ ! -p "${INP_PIPE}" ]]
then
    mkfifo "${INP_PIPE}"
    if (( $? == 0 ))
    then
        LOG_MSG[0]="Info  => named pipe initialized!"
        f_logwrite
    else
        LOG_MSG[0]="Error => named pipe could not be initialized!"
        f_logwrite
        f_trap_exit
    fi
else
    LOG_MSG[0]="Error => named pipe already running!"
    f_logwrite
    f_trap_exit
fi

# assign nav pipe to custom file descriptor
#
exec {INP_FD}<> "${INP_PIPE}"

# start nav pipe function in background and get PID
#
f_nav_pipe &
BG_PID=$!

# initialize LCD display at beginning
#
printf "${LCD_RESET}" > "${LCD_DEV}"
printf "${LCD_ON}" > "${LCD_DEV}"
LOG_MSG[0]="Info  => startup LCD display!"
f_logwrite

#===============================================================================#
# main (endless) loop                                                           #
#===============================================================================#
while :
do
    # input preparation
    #
    if (( INP_ID == 0 ))
    then
        INP_ID=1
        if [[ -f "${INP_DIR}/${INP_FILE}" ]]
        then
            # source/execute function library
            #
            . ${INP_DIR}/${INP_FILE}
            LOG_MSG[0]="Info  => (re-)read input!"
            f_logwrite

            # prepare raw messages for log writing
            #
            LOG_INDEX=0
            for (( INDEX=0; INDEX <= (( ${#ROW[@]} - LCD_MAXROW )); ))
            do
                LOG_MSG[${LOG_INDEX}]=
                INDEX_NEW=$(( INDEX + LCD_MAXROW ))
                until (( INDEX == INDEX_NEW ))
                do
                    if [[ -n "${LOG_MSG[${LOG_INDEX}]}" ]]
                    then
                        LOG_MSG[${LOG_INDEX}]="${LOG_MSG[${LOG_INDEX}]} => ${ROW[${INDEX}]}"
                    else
                        LOG_MSG[${LOG_INDEX}]="$(printf "%-${LCD_MAXCOL}s" "${ROW[${INDEX}]}")"
                    fi
                    (( INDEX++ ))
                done
                (( LOG_INDEX++ ))
            done
            f_logwrite

            # prepare messages for LCD output
            #
            for INDEX in "${!ROW[@]}"
            do
                MSG="${ROW[${INDEX}]}"
                # set/cut message to max display length
                MSG_LEN=${#MSG}
                if (( MSG_LEN < LCD_MAXCOL ))
                then
                    until (( MSG_LEN == LCD_MAXCOL ))
                    do
                        MSG="${MSG}${MSG_FILLER}"
                        (( MSG_LEN ++ ))
                    done
                elif (( MSG_LEN > LCD_MAXCOL ))
                then
                    MSG="${MSG:0:${LCD_MAXCOL}}"
                fi
                # escape special message characters
                MSG="${MSG//\%/\\%}"
                # write modified message back to array
                ROW[${INDEX}]="${MSG}"
            done
            # reset index
            INDEX=0
        else
            # write error to log device and exit
            LOG_MSG[0]="Error => function library not found!"
            f_logwrite
            f_trap_exit
        fi
    fi

    # message output
    #
    if (( MSG_ID == 0 ))
    then
        MSG_ID=1
        LCD_ROW=0
        # reset index at the end of the array
        if (( INDEX == ${#ROW[@]} ))
        then
            INDEX=0
        fi
        INDEX_OLD=$(( INDEX ))
        INDEX_NEW=$(( INDEX + LCD_MAXROW ))
        while (( INDEX < INDEX_NEW ))
        do
            # due to LCD timing issues send message twice per row
            printf "${LCD_CODE}${LCD_ROW} ${ROW[${INDEX}]}" > "${LCD_DEV}"
            printf "${LCD_CODE}${LCD_ROW} ${ROW[${INDEX}]}" > "${LCD_DEV}"
            (( LCD_ROW ++ ))
            (( INDEX ++ ))
        done
    fi

    # read nav pipe/custom file descriptor
    #
    read -t1 INP_BUFFER <&${INP_FD}

    # check input buffer and change message index accordingly
    #
    if [[ -n "${INP_BUFFER}" ]]
    then
        INDEX=$(( INDEX_OLD ))
        for BUTTON in ${INP_BUFFER}
        do
            # lights on
            if (( LCD_ID == 1 ))
            then
                INP_ID=0
                LCD_ID=0
                MSG_ID=0
                MSG_RT=0
                INP_RT=0
                LCD_RT=0
                printf "${LCD_ON}" > "${LCD_DEV}"
                LOG_MSG[0]="Info  => button pressed (lights on)!"
                f_logwrite
                continue
            fi
            MSG_ID=0
            MSG_RT=0
            INP_RT=0
            LCD_RT=0
            # nav up
            if [[ "${BUTTON}" == "UP" ]]
            then
                if (( INDEX < ${#ROW[@]} - LCD_MAXROW ))
                then
                    (( INDEX = INDEX + LCD_MAXROW ))
                elif (( INDEX == ${#ROW[@]} - LCD_MAXROW ))
                then
                    (( INDEX = 0 ))
                fi
                LOG_MSG[0]="Info  => button pressed (up)!"
                f_logwrite
            # nav down
            elif [[ "${BUTTON}" == "DOWN" ]]
            then
                if (( INDEX > 0 ))
                then
                   (( INDEX = INDEX - LCD_MAXROW ))
                elif (( INDEX == 0 ))
                then
                    (( INDEX = ${#ROW[@]} - LCD_MAXROW ))
                fi
                LOG_MSG[0]="Info  => button pressed (down)!"
                f_logwrite
            fi
        done
    fi

    # lights out
    #
    if (( LCD_RT >= LCD_TIMEOUT && LCD_TIMEOUT > 0 ))
    then
        if (( LCD_ID == 0 ))
        then
            LCD_ID=1
            printf "${LCD_OFF}" > "${LCD_DEV}"
            LOG_MSG[0]="Info  => lcd timeout, lights out!"
            f_logwrite
        else
            # reduce workload during LCD sleep mode
            sleep 1
        fi
    else
        # re-initialize timers
        if (( INP_RT >= INP_TIMEOUT && INP_TIMEOUT > 0 ))
        then
            INP_ID=0
            INP_RT=0
        elif (( MSG_RT >= MSG_TIMEOUT && MSG_TIMEOUT > 0 ))
        then
            MSG_ID=0
            MSG_RT=0
        fi
    fi

    # raise runtime counters
    #
    (( INP_RT ++ ))
    (( MSG_RT ++ ))
    (( LCD_RT ++ ))
done
