#!/bin/sh
# SPDX-License-Identifier: MIT


CONFIGFS="/sys/kernel/config"
GADGET="$CONFIGFS/usb_gadget"
VID="0x361C"
PID="0x0007"
SERIAL="20211102"
MANUF="Spacemit"
PRODUCT="Spacemit K1 UVC Webcam"
UDC=$(ls /sys/class/udc) # will identify the 'first' UDC

echo "  udc   : $UDC"

create_frame() {
	# Example usage:
	# create_frame <function name> <width> <height> <format> <name>

	FUNCTION=$1
	WIDTH=$2
	HEIGHT=$3
	FORMAT=$4
	NAME=$5

	wdir=functions/$FUNCTION/streaming/$FORMAT/$NAME/${HEIGHT}p

	mkdir -p $wdir
	echo $WIDTH > $wdir/wWidth
	echo $HEIGHT > $wdir/wHeight
	echo $(( $WIDTH * $HEIGHT * 2 )) > $wdir/dwMaxVideoFrameBufferSize
	cat <<EOF > $wdir/dwFrameInterval
666666
1000000
5000000
EOF
}

create_uvc() {
	# Example usage:
	#	create_uvc <target config> <function name>
	#	create_uvc config/c.1 uvc.0
	CONFIG=$1
	FUNCTION=$2
	INTV=$3
	MXPKT=$4


	echo "	Creating UVC gadget functionality : $FUNCTION"
	mkdir functions/$FUNCTION

	create_frame $FUNCTION 640 360 uncompressed u
	create_frame $FUNCTION 1280 720 uncompressed u
	create_frame $FUNCTION 320 180 uncompressed u
	create_frame $FUNCTION 1920 1080 mjpeg m
	create_frame $FUNCTION 640 480 mjpeg m
	create_frame $FUNCTION 640 360 mjpeg m

	mkdir functions/$FUNCTION/streaming/header/h
	cd functions/$FUNCTION/streaming/header/h
	ln -s ../../uncompressed/u
	ln -s ../../mjpeg/m
	cd ../../class/fs
	ln -s ../../header/h
	cd ../../class/hs
	ln -s ../../header/h
	cd ../../class/ss
	ln -s ../../header/h
	cd ../../../control
	mkdir header/h
	ln -s header/h class/fs
	ln -s header/h class/ss
	cd ../../../

	# Include an Extension Unit if the kernel supports that
	if [ -d functions/$FUNCTION/control/extensions ]; then
		mkdir functions/$FUNCTION/control/extensions/xu.0
		pushd functions/$FUNCTION/control/extensions/xu.0

		# Set the bUnitID of the Processing Unit as the XU's source
		echo 2 > baSourceID

		# Set this XU as the source for the default output terminal
		cat bUnitID > ../../terminal/output/default/bSourceID

		# Flag some arbitrary controls. This sets alternating bits of the
		# first byte of bmControls active.
		echo 0x55 > bmControls

		# Set the GUID
		echo -e -n "\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10" > guidExtensionCode

		popd
	fi

	# Set the packet size: uvc gadget max size is 3k...
	echo 3072 > functions/$FUNCTION/streaming_maxpacket
	echo 2048 > functions/$FUNCTION/streaming_maxpacket
	echo 1024 > functions/$FUNCTION/streaming_maxpacket
	if test "$MXPKT" -eq "$MXPKT" 2>/dev/null; then
		echo "Set streaming_interval to $MXPKT."
		echo $MXPKT > functions/$FUNCTION/streaming_maxpacket
	else
		echo "Set streaming_maxpacket to 1024 by default."
	fi
	if test "$INTV" -eq "$INTV" 2>/dev/null; then
		echo "Set streaming_interval to $INTV."
	else
		echo "Set streaming_interval to 1 by default."
		INTV=1
	fi
	echo $INTV > functions/$FUNCTION/streaming_interval

	ln -s functions/$FUNCTION configs/c.1
}

###
# $1 uncompressed/u
# $2 Width
# $3 Height
clean_uvc_format_()
{
    FORMAT=$1
    UVC_DISPLAY_W=$2
    UVC_DISPLAY_H=$3
    UVC_MJPEG_PRE_PATH=/sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/$FORMAT
    UVC_FRAME_WDIR=${UVC_MJPEG_PRE_PATH}/${UVC_DISPLAY_H}p
    rmdir $UVC_FRAME_WDIR
    # rmdir ${UVC_MJPEG_PRE_PATH}
}

clean_uvc_format_all_()
{
    clean_uvc_format_ uncompressed/u 640 360
    clean_uvc_format_ uncompressed/u 1280 720
    clean_uvc_format_ uncompressed/u 320 180
    rmdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/uncompressed/u
    clean_uvc_format_ mjpeg/m 640 360
    clean_uvc_format_ mjpeg/m 640 480
    clean_uvc_format_ mjpeg/m 1280 720
    clean_uvc_format_ mjpeg/m 1920 1080
    rmdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/mjpeg/m
}

configure_uvc_link_()
{
    mkdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h

    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/mjpeg/m /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h/
    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/uncompressed/u /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h/

    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/fs
    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/hs
    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/ss

    mkdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/header/h
    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/header/h /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/class/fs/
    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/header/h /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/class/ss/

    ln -s /sys/kernel/config/usb_gadget/g1/functions/uvc.0/ /sys/kernel/config/usb_gadget/g1/configs/c.1/
}

clean_uvc_link_()
{
    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/class/fs/h
    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/class/ss/h
    rmdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/control/header/h

    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/ss/h
    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/hs/h
    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/class/fs/h

    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h/m
    rm /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h/u

    rmdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0/streaming/header/h

}

clean_uvc()
{
    rm -f /sys/kernel/config/usb_gadget/g1/configs/c.1/uvc.0
    clean_uvc_link_
    clean_uvc_format_all_
    rmdir /sys/kernel/config/usb_gadget/g1/functions/uvc.0
}

delete_uvc() {
	clean_uvc
}

case "$1" in
	start)
		echo "Creating the USB gadget"
		echo "Creating gadget directory g1"

		configfs_mounted=$(mount | grep -c "configfs")
		if [ "$configfs_mounted" -eq 0 ]; then
			mount -t configfs none /sys/kernel/config
		fi
		mkdir /sys/kernel/config/usb_gadget/g1

		cd $GADGET/g1
		if [ $? -ne 0 ]; then
			echo "Error creating usb gadget in configfs"
			exit 1;
		else
			echo "OK"
		fi

		echo "Setting Vendor and Product ID's"
		echo $VID > idVendor
		echo $PID > idProduct
		echo "OK"

		echo "Setting English strings"
		mkdir -p strings/0x409
		echo $SERIAL > strings/0x409/serialnumber
		echo $MANUF > strings/0x409/manufacturer
		echo $PRODUCT > strings/0x409/product
		echo "OK"

		echo "Creating Config"
		mkdir configs/c.1
		mkdir configs/c.1/strings/0x409

		echo "Creating functions..."
		create_uvc configs/c.1 uvc.0 $2 $3
		echo "OK"

		echo "Binding USB Device Controller"
		echo $UDC > UDC
		echo "OK"
		;;

	stop)
		echo "Stopping the USB gadget"

		set +e # Ignore all errors here on a best effort

		cd $GADGET/g1

		if [ $? -ne 0 ]; then
			echo "Error: no configfs gadget found"
			exit 1;
		fi

		echo "Unbinding USB Device Controller"
		echo "" > UDC
		echo "OK"

		delete_uvc

		echo "Clearing English strings"
		rmdir strings/0x409
		echo "OK"

		echo "Cleaning up configuration"
		rmdir configs/c.1/strings/0x409
		rmdir configs/c.1
		echo "OK"

		echo "Removing gadget directory"
		cd $GADGET
		rmdir g1
		cd /
		echo "OK"
		;;
	*)
		echo "Usage : $0 {start|stop}"
		echo "Optional: {start} {streaming_interval} {streaming_maxpacket}"
		echo -e "\tdefault:1\tdetault:1024"
esac
