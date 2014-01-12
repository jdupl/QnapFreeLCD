#!/usr/bin/ksh
#
# lcd-control, version 0.3
# original author Dirk Brenken (dibdot@gmail.com)
# modified by Justin Duplessis (drfoliberg@gmail.com)
#

# enable shell debug mode
#
#set -x

# treats unset variables as an error
#
set -u

# tty settings
# TTY_PRG => reference to stty program (default: /bin/stty)
# TTY_TIMEOUT => tty read timeout in tenths of a second (default: 10)
#
TTY_PRG="/bin/stty"
TTY_TIMEOUT=10
TTY_MIN=0

# input settings
# INP_DIR => reference to input directory (default: script directory)
# INP_FILE => reference to function library (default: _lcd-functions.ksh)
# INP_PIPE => reference to named pipe (default: /var/run/lcd.pipe)
# INP_TIMEOUT => input refresh timeout in seconds (default: 60), "0" (without quotes) to disable input auto-refresh
# INP_FD => number of used file descriptor for named pipe (default: 5)
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
# LCD_DEV => LCD device node (default: /dev/ttyS1)
# LCD_BAUD => BAUD rate for LCD display (default: 1200)
# LCD_MAXROW => number of display rows (default: 2)
# LCD_MAXCOL => number of display cols (default:16)
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


# function for basic trap handling
#
function f_trap_exit
{
    #set -x
    # kill nav_pipe function
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
    exit 2
}

# function to get button input and write it to nav pipe
#
function f_nav_pipe
{
    #set -x
    while :
    do
        # read LCD button input
        INP_NAV=$(cat -vet "${LCD_DEV}")
        if [[ -n "${INP_NAV}" ]]
        then
            # filter/replace input stream
            INP_NAV="${INP_NAV//[!A-B]/}"
            INP_NAV="${INP_NAV//A/UP }"
            INP_NAV="${INP_NAV//B/DOWN }"
            # send vaild input to nav pipe/custom file descriptor
            if [[ -n "${INP_NAV}" ]]
            then
                NAV_RT=0
                printf "%s\n" "${INP_NAV}" >&${INP_FD}
                printf "%s\n" "" >&${INP_FD}
            fi
        fi
    done
}

# call basic trap function (SIGHUP, SIGINT, SIGQUIT, SIGTERM)
#
trap "f_trap_exit" 1 2 3 15

# prepare serial communication (send & receive)
#
"${TTY_PRG}" -F "${LCD_DEV}" ${LCD_BAUD} cread cbreak olcuc time ${TTY_TIMEOUT} min ${TTY_MIN}

# create named pipe
#
if [[ ! -p "${INP_PIPE}" ]]
then
    mkfifo "${INP_PIPE}"
fi

# assign nav pipe to custom file descriptor
#
exec {INP_FD}<> "${INP_PIPE}"

# start nav pipe function in background and get PID
#
f_nav_pipe &
BG_PID=$!

# reset LCD display at beginning
#
printf "${LCD_RESET}" > "${LCD_DEV}"

# main loop
#
while :
do
    # prepare input/update message array
    #
    if (( INP_ID == 0 ))
    then
        INP_ID=1
        if [[ -f "${INP_DIR}/${INP_FILE}" ]]
        then
            # source/execute functions library
            . ${INP_DIR}/${INP_FILE}
            # prepare messages for LCD output
            for INDEX in "${!ROW[@]}"
            do
                MSG="${ROW[${INDEX}]}"
                MSG_LEN=${#MSG}
                # set/cut message to max display length
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
                # wrote modified message back to array
                ROW[${INDEX}]="${MSG}"
                (( INDEX ++ ))
            done
            # reset index
            INDEX=0
        else
            printf "%s\n" "Error: LCD functions library not found!"
            f_trap_exit
        fi
    fi

    # message output
    #
    if (( MSG_ID == 0 ))
    then
        MSG_ID=1
        LCD_ROW=0
        INDEX_OLD=$(( INDEX ))
        INDEX_NEW=$(( LCD_MAXROW + INDEX ))
        # lights on
        printf "${LCD_ON}" > "${LCD_DEV}"
        until (( INDEX == INDEX_NEW ))
        do
            # for fast LCD output send message twice per row
            printf "${LCD_CODE}${LCD_ROW} ${ROW[${INDEX}]}" > "${LCD_DEV}"
            printf "${LCD_CODE}${LCD_ROW} ${ROW[${INDEX}]}" > "${LCD_DEV}"
            (( INDEX ++ ))
            (( LCD_ROW ++ ))
        done
        # reset index at the end of the array
        if (( INDEX == ${#ROW[@]} ))
        then
            INDEX=0
        fi
    fi

    # read nav pipe/custom file descriptor and change message index accordingly
    #
    read -t1 INP_BUFFER <&${INP_FD}
    if [[ -n "${INP_BUFFER}" ]]
    then
        INDEX=$(( INDEX_OLD ))
        for BUTTON in ${INP_BUFFER}
        do
			#if lcd was off, read data again and lights on
			if (( LCD_ID == 1))
			then
			    # source/execute functions library
				. ${INP_DIR}/${INP_FILE}
				#turn lcd on 
				printf "${LCD_ON}" > "${LCD_DEV}"
			fi
			
            # nav up
            if [[ "${BUTTON}" == "UP" ]]
            then
                LCD_ID=0
                LCD_RT=0
                INP_RT=0
                if (( INDEX < ${#ROW[@]} - LCD_MAXROW ))
                then
                    MSG_ID=0
                    MSG_RT=0
                    (( INDEX = INDEX + LCD_MAXROW ))
                fi
            # nav down
            elif [[ "${BUTTON}" == "DOWN" ]]
            then
                LCD_ID=0
                LCD_RT=0
                INP_RT=0
                if (( INDEX > 0 ))
                then
                    MSG_ID=0
                    MSG_RT=0
                   (( INDEX = INDEX - LCD_MAXROW ))
                fi
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

