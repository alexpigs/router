#!/bin/sh
wanx_dir=$(nvram get wanx_dir)
$wanx_dir/wanx.sh pppdown2
	
idx=$(echo $IFNAME | grep -o "[0-9]\+")
if [ -z "$idx" ] ; then
	exit
fi

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
nvram unset $key_ipaddr
nvram unset $key_gateway_get
nvram unset $key_hwaddr
nvram unset $key_netmask
nvram unset $key_proto
nvram unset $key_run_mtu
nvram unset $key_pppd
nvram unset $key_status
nvram unset $key_uptime
nvram unset $key_conntime
nvram unset $key_iface
