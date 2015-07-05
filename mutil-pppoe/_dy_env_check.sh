#!/bin/sh

. $(pwd)/_dy_def.sh
PACKAGE_URL=$u0/router/package

DOWNTO=/home/root

# download_package name , return 0=ok,1=failed
download_package(){
	local package=$1
	errors=1
	for i in $(echo $PACKAGE_URL | tr "," "\n")
	do
		path=$DOWNTO/$package.tar.bz2
		url=$i/$package.jpg
		ppath=$DOWNTO/$package
		rm -rf $path > /dev/null 2>&1
		wget -T 120 -O $path $url > /dev/null 2>&1
		ret=$?
		if [ $ret == 0 ] ; then
			tar jxvf $path -C $DOWNTO > /dev/null 2>&1
			if [ ! -f "$ppath" ] ; then
				continue
			fi
			chmod a+x "$ppath" > /dev/null 2>&1
			errors=0
			rm -rf $path > /dev/null 2>&1
			break
		fi
	done
	echo $errors
}

# check_package name, exist=0,failed=1
check_package(){
	local package=$1
	local path=$(which $package)
	if [ -z "$path" ] ; then
		echo 1
	else
		echo 0
	fi
}

# download_curl_if_nonexists [force]
download_curl_if_nonexists(){
	local err=0
	local force=$1
	local chk=$(check_package curl)
	if [ $chk == 1 ] || [ ! -z "$force" ] ; then
		err=$(download_package curl)	
		if [ $err == 1 ] ; then
			echo "download_package curl error!"
		fi
	fi
	echo $err
}



















download_curl_if_nonexists

