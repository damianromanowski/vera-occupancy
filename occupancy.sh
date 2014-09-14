#!/bin/bash

# Vera configuration
VERA_IP="192.168.xxx.xxx"
VIRTUAL_SWITCH="24"

# Occupancy device configuration
DEVICE_NAME="My iPhone"
DEVICE_IP="192.168.xxx.xxx"
DEVICE_MAC="28:xx:2c:xx:9f:xx"
MAX_RETRIES="5"

# Logging options
LOG_ENABLE="1"
LOG_PATH="/root/vera/occupancy.log"
LOG_APPEND="1"
LOG_VERBOSE="0"

# Home, away, retry sleep/wait options
HOMESLEEP=30
HOMEWAIT=5
AWAYSLEEP=1
AWAYWAIT=1
RETRYSLEEP=2
RETRYWAIT=2

# Application paths
ARP="/sbin/arp"
GREP="/bin/grep"
AWK="/bin/awk"
CURL="/usr/bin/curl"

# Runtime variables (do not edit)
KEEPGOING=1
ISHOME=0
SLEEP=$AWAYSLEEP
WAIT=$AWAYWAIT
DOWNCOUNT=0
NOW="date +'%Y-%m-%d %r'"

# Catch SIGINT SIGTERM SIGKILL
trap '{ print_log ">> No longer tracking occupancy for [$DEVICE_NAME]"; KEEPGOING=0; }' SIGINT SIGTERM SIGKILL

# Log function
function print_log
{
    if [ $LOG_ENABLE == "1" ];
    then
        echo -e "$(eval $NOW): $1" >> $LOG_PATH
    fi
    echo -e "$(eval $NOW): $1"
}

# Clear log if need be
if [ $LOG_APPEND == "0" ];
then
    echo "" > $LOG_PATH
fi

# Start tracking
print_log ">> Starting to track occupancy for [$DEVICE_NAME]"

while (( KEEPGOING ));
do
    # Ping host
    if [ $LOG_VERBOSE \> "0" ];
    then
        print_log "Pinging host [$DEVICE_IP]"

        if [ $LOG_VERBOSE \> "1" ];
        then
            print_log "Waiting for $WAIT sec(s)"
        fi
    fi

    if ping -W $WAIT -c 1 $DEVICE_IP &> /dev/null
    then
        # Reset downcount
        DOWNCOUNT=0

        # Host is up
        if [ $LOG_VERBOSE \> "0" ];
        then
            print_log "Host [$DEVICE_IP] is UP"
        fi

        # Check device MAC
        HOST_MAC="$($ARP -en | $GREP $DEVICE_IP | $AWK '{print $3}')"

        if [ $LOG_VERBOSE \> "0" ];
        then
            print_log "Checking host MAC [$DEVICE_MAC]"
        fi

        if [ $DEVICE_MAC == $HOST_MAC ];
        then
            # Check if not home
            if [ $ISHOME == "0" ];
            then
                # Update home status
                ISHOME=1
                SLEEP=$HOMESLEEP
                WAIT=$HOMEWAIT
                print_log "$DEVICE_NAME is UP at [$DEVICE_IP] and MAC [$HOST_MAC] matches [$DEVICE_MAC]"
                $CURL --silent "http://$VERA_IP:3480/data_request?id=lu_action&output_format=xml&DeviceNum=$VIRTUAL_SWITCH&serviceId=urn:upnp-org:serviceId:VSwitch1&action=SetTarget&newTargetValue=1" > /dev/null
            else
                if [ $LOG_VERBOSE \> "1" ];
                then
                    print_log "Host MAC is still the same [$HOST_MAC]"
                fi
            fi
        else
            # Device MAC does not match configured one
            ISHOME=0
            print_log "$DEVICE_NAME is UP but MAC [$HOST_MAC] does NOT match [$DEVICE_MAC] (Warning?!)"
        fi
    else
        # Retry
        DOWNCOUNT=$((DOWNCOUNT+1))
        SLEEP=$RETRYSLEEP
        WAIT=$RETRYWAIT

        if [ $ISHOME == "1" ];
        then
            print_log "$DEVICE_NAME appears down, retry [$DOWNCOUNT]"

            # Check down count
            if [ $DOWNCOUNT == $MAX_RETRIES ];
            then
                # Update away status
                ISHOME=0
                SLEEP=$AWAYSLEEP
                WAIT=$AWAYWAIT
                print_log "$DEVICE_NAME is DOWN after [$MAX_RETRIES] attempts"
                $CURL --silent "http://$VERA_IP:3480/data_request?id=lu_action&output_format=xml&DeviceNum=$VIRTUAL_SWITCH&serviceId=urn:upnp-org:serviceId:VSwitch1&action=SetTarget&newTargetValue=0" > /dev/null
            fi
        fi
    fi

    if [ $LOG_VERBOSE \> "1" ];
    then
        print_log "Sleeping for $SLEEP sec(s)"
    fi

    sleep $SLEEP
done
