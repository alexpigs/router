#!/bin/sh

wanx_dir=$(nvram get wanx_dir)
$wanx_dir/wanx.sh pppup2 

idx=$(echo $IFNAME | grep -o "[0-9]\+")
if [ -z "$idx" ] ; then
	echo idx=$idx dialup idx=$idx,ifname=$IFNAME > /dev/kmsg
	exit
fi

echo "dialup $IFNAME idx=$idx" > /dev/kmsg

x=$(($idx))
key_ipaddr=wan${x}_ipaddr
key_gateway_get=wan${x}_gateway_get
key_hwaddr=wan${x}_hwaddr
key_netmask=wan${x}_netmask
key_proto=wan${x}_proto
key_run_mtu=wan${x}_run_mtu
key_pppd=wan${x}_pppd_pid
key_status=wan${x}_status
key_uptime=wan${x}_uptime
key_conntime=wan${x}_conntime
key_iface=wan${x}_iface

nvram set $key_ipaddr=$IPLOCAL
nvram set $key_gateway_get=$IPREMOTE
nvram set $key_hwaddr=$(ifconfig mc$idx | grep HWaddr | awk '{print $5}')
nvram set $key_netmask=255.255.255.255
nvram set $key_proto=pppoe
nvram set $key_run_mtu=1492
nvram set $key_pppd=$PPPD_PID
nvram set $key_status=connected
nvram set $key_uptime=$(date +%s)
nvram set $key_iface=$1

killall httpd
cd /www && httpd 

