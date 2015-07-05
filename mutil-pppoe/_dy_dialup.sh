#!/bin/sh
nvram set nwan_${IFNAME}_status=up
nvram set nwan_${IFNAME}_up_time=$(date +%s)
nvram set nwan_${IFNAME}_ip=$IPLOCAL
nvram set nwan_${IFNAME}_gw=$IPREMOTE
nvram set nwan_${IFNAME}_pppd_pid=$PPPD_PID

