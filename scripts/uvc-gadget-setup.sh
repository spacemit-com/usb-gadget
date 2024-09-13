#!/bin/bash
# In busybox ash, should use /bin/sh, but bianbu cannot use /bin/sh

name=`basename $0`
SCRIPT_VERSION="v0.2-MULTIPROFILE"
CONFIG_FILE=$HOME/.uvcg_config

# USB Descriptors
VENDOR_ID="0x361c"
PRODUC_ID="0x0009"
MANUAF_STR="SpacemiT"
PRODUC_STR="SpacemitT UVC Webcam"
SERNUM_STR="20211102"
SN_PATH="/proc/device-tree/serial-number"
[ "$BOARD_SN" ] || BOARD_SN=$( [ -e $SN_PATH ] && tr -d '\000' < $SN_PATH )
[ "$BOARD_SN" ] && SERNUM_STR=$BOARD_SN

CONFIGFS=/sys/kernel/config
GADGET_PATH=$CONFIGFS/usb_gadget/spacemit_webcam
GFUNC_PATH=$GADGET_PATH/functions
GCONFIG=$GADGET_PATH/configs/c.1
SYSFS_UDC=/sys/class/udc
UVC_INSTANCE="uvc.0"
[ "$USB_UDC" ] || USB_UDC=$(ls $SYSFS_UDC | awk "NR==1{print}")

DEBUG="disabled"

usage()
{
	echo -e "SpacemiT uvc gadget setup tool $SCRIPT_VERSION"
	echo ""
	echo "Usage: "
	echo -e "\t$name {start (<profile>)|stop|pause|resume}"
	echo -e "Select uvc profile:"
	echo -e "\t$name start: start a default profile"
	echo -e "\t$name start <profile name>: select "
	echo -e "Set USB connection:"
	echo -e "\t$name [pause|resume]"
	echo -e "Specific dwMaxVideoFrameBufferSize:"
	echo -e "\t$name config: open vi to edit $CONFIG_FILE"
	echo -e "\tFor MJPEG format using a V4L2 source with uvc-gadget app,"
	echo -e "\tyou need to make sure the dwMaxVideoFrameBufferSize matches the"
	echo -e "\tframe size of the fmt in your camera provide via V4L2."
	echo -e "Show gadget info of the platform:"
	echo -e "\t$name info"
	echo -e "\nNotice: udc is automatically selected, you can override it"
	echo -e "\twith env USB_UDC_IDX=[integer] or USB_UDC=[str]"
	echo ""
	echo "Profiles supported:"
	echo -e "\tdefault        List common resolutions with 30fps"
	echo -e "\tuvc            profile of Low Bandwidth Usage"
	echo -e "\tuvch           profile of High Bandwidth(mc=2) Usage"
	echo -e "\tuvchh          profile of High Bandwidth(mc=3) Usage"
	echo -e "\tuvcss          profile requires SuperSpeed connection"
	echo -e "\tcustom         custom profile"
	echo ""
	echo -e "\tThese profiles have different formats, each with its own"
	echo -e "\tresolutions of a default frame rate. All resolution have"
	echo -e "\tframe rates ranging from 10fps to 60fps can be choosen"
	echo -e "\tfrom host camera app."
	echo ""
}

setup_custom_profile()
{
	## edit your custom profile here
	add_uvc_fmt_resolution uncompressed/y 640 360 30
	add_uvc_fmt_resolution uncompressed/y 1280 480 30
	add_uvc_fmt_resolution uncompressed/y 960 640 30
	add_uvc_fmt_resolution uncompressed/y 1280 720 10
	add_uvc_fmt_resolution mjpeg/m 640 360 30
	add_uvc_fmt_resolution mjpeg/m  960 640 30
	add_uvc_fmt_resolution mjpeg/m  1280 480 30
	add_uvc_fmt_resolution mjpeg/m 1280 720 10
	set_uvc_isoc_bandwidth 3072 15
}

setup_uvc_profile()
{
	UVC_PROFILE=$1
	# H.264 and HEVC(265) is Not Supported yet.
	case "$UVC_PROFILE" in
		"lo" | "low" | "uvc" | "sd" | "p1")
			add_uvc_fmt_resolution uncompressed/y 480 240 30
			add_uvc_fmt_resolution uncompressed/y 640 360 15
			add_uvc_fmt_resolution mjpeg/m 640 360 30
			add_uvc_fmt_resolution mjpeg/m 1280 720 15
			add_uvc_fmt_resolution mjpeg/m 720 480 30
			set_uvc_isoc_bandwidth 1024 15
			;;
		"m" | "med" | "uvch" | "hd" | "p2")
			add_uvc_fmt_resolution uncompressed/y 640 360 30
			add_uvc_fmt_resolution uncompressed/y 1280 720 15
			add_uvc_fmt_resolution mjpeg/m 1280 720 30
			add_uvc_fmt_resolution mjpeg/m 1920 1080 30
			set_uvc_isoc_bandwidth 2048 15
			;;
		"h" | "hi" | "uvchh" | "fhd" | "p3")
			add_uvc_fmt_resolution uncompressed/y 640 360 30
			add_uvc_fmt_resolution uncompressed/y 640 480 30
			add_uvc_fmt_resolution uncompressed/y 640 640 30
			add_uvc_fmt_resolution uncompressed/y 1280 720 10
			add_uvc_fmt_resolution mjpeg/m 640 360 60
			add_uvc_fmt_resolution mjpeg/m 640 480 60
			add_uvc_fmt_resolution mjpeg/m 1280 720 60
			add_uvc_fmt_resolution mjpeg/m 1920 1080 30
			set_uvc_isoc_bandwidth 3072 15
			;;
		"s" | "uvcss" | "4k" | "qhd" | "p4")
			add_uvc_fmt_resolution uncompressed/y 640 360 60
			add_uvc_fmt_resolution uncompressed/y 640 480 60
			add_uvc_fmt_resolution uncompressed/y 640 640 60
			add_uvc_fmt_resolution uncompressed/y 1280 720 60
			add_uvc_fmt_resolution uncompressed/y 1920 1080 60
			add_uvc_fmt_resolution uncompressed/y 3840 2160 30
			add_uvc_fmt_resolution mjpeg/m 640 360 60
			add_uvc_fmt_resolution mjpeg/m 640 480 60
			add_uvc_fmt_resolution mjpeg/m 1280 720 60
			add_uvc_fmt_resolution mjpeg/m 1920 1080 60
			add_uvc_fmt_resolution mjpeg/m 3840 2160 30
			set_uvc_isoc_bandwidth 3072 15
			;;
		"custom")
			setup_custom_profile
			;;
		*)
			# General 30fps profile
			add_uvc_fmt_resolution uncompressed/y 480 240 30
			add_uvc_fmt_resolution uncompressed/y 640 360 30
			add_uvc_fmt_resolution uncompressed/y 640 480 30
			add_uvc_fmt_resolution uncompressed/y 640 640 30
			add_uvc_fmt_resolution uncompressed/y 1280 720 30
			add_uvc_fmt_resolution uncompressed/y 1920 1080 30
			add_uvc_fmt_resolution mjpeg/m 640 360 30
			add_uvc_fmt_resolution mjpeg/m 640 480 30
			add_uvc_fmt_resolution mjpeg/m 1280 720 30
			add_uvc_fmt_resolution mjpeg/m 1920 1080 30
			set_uvc_isoc_bandwidth 3072 15
			;;
	esac
}

gadget_info()
{
	echo "$name: $1"
}

gadget_debug()
{
	[ $DEBUG == "okay" ] && echo "$name: $1"
}

die()
{
	gadget_info "$1"
	exit 1
}

g_remove()
{
	[ -h $1 ] && rm -f $1
	[ -d $1 ] && rmdir $1
	[ -e $1 ] && rm -f $1
}


# Add a uvc resolution fmt in configfs
# Usage:
#	add_uvc_fmt_resolution <format> <width> <height> <framerate>
# e.g.
#	add_uvc_fmt_resolution uncompressed/y 480 240 30
add_uvc_fmt_resolution()
{
	FORMAT=$1 # $1 format "uncompressed/y" / "mjpeg/m"
	UVC_DISPLAY_W=$2 # $2 Width
	UVC_DISPLAY_H=$3 # $3 Height
	FRAMERATE=$4 # $4 HIGH_FRAMERATE 0/1
	#https://docs.kernel.org/usb/gadget_uvc.html
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	UVC_FRAME_WDIR=${UVC_MJPEG_PRE_PATH}/${UVC_DISPLAY_H}p
	gadget_debug "UVC_FRAME_WDIR: $UVC_FRAME_WDIR"
	mkdir -p $UVC_FRAME_WDIR
	echo $UVC_DISPLAY_W > $UVC_FRAME_WDIR/wWidth
	echo $UVC_DISPLAY_H > $UVC_FRAME_WDIR/wHeight
	DW_MAX_VD_FB_SZ=$(( $UVC_DISPLAY_W * $UVC_DISPLAY_H * 2 ))
	if [ "$FORMAT"=="mjpeg/m" ]; then
		if [ -e "$CONFIG_FILE" ]; then
			# Attempt to parse the dwMaxVideoFrameBufferSize from ~/.uvcg_config
			parsed_value=$(grep "^mjpeg $UVC_DISPLAY_W $UVC_DISPLAY_H" ~/.uvcg_config | awk '{print $4}')
			# Check if the value was found; if not, keep the pre-calculated value
			if [ ! -z "$parsed_value" ]; then
				DW_MAX_VD_FB_SZ="$parsed_value"
			fi
			gadget_debug "format: $FORMAT, dw_max_video_fb_size: $DW_MAX_VD_FB_SZ"
		fi
	fi
	echo $DW_MAX_VD_FB_SZ > $UVC_FRAME_WDIR/dwMaxVideoFrameBufferSize
	# Many camera host app only shows the default framerate of a format in their list
	# So we set it here.
	if [ "$FRAMERATE" -eq 20 ]; then
		echo 500000 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 15 ]; then
		echo 666666 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 30 ]; then
		echo 333333 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 60 ]; then
		echo 166666 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	elif [ "$FRAMERATE" -eq 10 ]; then
		echo 1000000 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	fi
	# lowest framerate in this script is 10fps
	DW_MIN_BITRATE=$(( 10 * $DW_MAX_VD_FB_SZ * 8 ))
	DW_MAX_BITRATE=$(( $FRAMERATE * $DW_MAX_VD_FB_SZ * 8 ))
	if [ "$FORMAT"=="mjpeg/m" ]; then
		# MJPEG can compress the data at least 5:1,
		# let's set the ratio to 4
		DW_MIN_BITRATE=$(( $DW_MIN_BITRATE / 4 ))
		gadget_debug "format: $FORMAT, dw_min_br: $DW_MIN_BITRATE"
	fi
	echo $DW_MIN_BITRATE > $UVC_FRAME_WDIR/dwMinBitRate
	echo $DW_MAX_BITRATE > $UVC_FRAME_WDIR/dwMaxBitRate
	echo -e "\t$UVC_INSTANCE will support ${FORMAT} ${UVC_DISPLAY_W}x${UVC_DISPLAY_H}@${FRAMERATE}p"
	cat <<EOF > $UVC_FRAME_WDIR/dwFrameInterval
166666
333333
416667
500000
666666
1000000
EOF
}

destroy_one_uvc_format_()
{
	FORMAT=$1
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	for ppath in ${UVC_MJPEG_PRE_PATH}/*p; do
		g_remove $ppath
	done
}

destroy_all_uvc_format_()
{

	destroy_one_uvc_format_ uncompressed/y
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y
	destroy_one_uvc_format_ mjpeg/m
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m
}

create_uvc_link_()
{
	mkdir -p $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/m
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/y
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/fs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/hs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/ss
	mkdir -p $GFUNC_PATH/$UVC_INSTANCE/control/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/fs/
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/ss/
}

destroy_uvc_link_()
{
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/class/fs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/class/ss/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/control/header/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/ss/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/hs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/class/fs/h
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/m
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/y
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h
}

destroy_uvc_()
{
	destroy_uvc_link_
	destroy_all_uvc_format_
	g_remove $GFUNC_PATH/$UVC_INSTANCE
}

# set_uvc_isoc_bandwidth 3072 15
set_uvc_isoc_bandwidth()
{
	MAX=$1 ## $1 1024/2048/3072
	BURST=$2 ## $2 1-15
	FUNCTION=$GFUNC_PATH/$UVC_INSTANCE
	echo -e "\t$UVC_INSTANCE set streaming_maxpacket=$MAX, streaming_maxburst=$BURST"
	echo $MAX > $FUNCTION/streaming_maxpacket
	echo $BURST  > $FUNCTION/streaming_maxburst
}

create_uvc_xu_()
{
	# Include an Extension Unit if the kernel supports that
	CONTROL_PATH=$GFUNC_PATH/$UVC_INSTANCE/control/
	if [ -d $CONTROL_PATH/extensions ]; then
		mkdir $CONTROL_PATH/extensions/xu.0
		pushd $CONTROL_PATH/extensions/xu.0
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
}

### End UVC Common
## UVC
uvc_config()
{
	UVC_PROFILE=$1
	gadget_info "Adding a uvc function instance $UVC_INSTANCE..."
	mkdir -p $GFUNC_PATH/$UVC_INSTANCE
	# add_uvc_fmt_resolution <format> <width> <height> <framerate>
	setup_uvc_profile $UVC_PROFILE
	create_uvc_link_
}

uvc_link()
{
	gadget_debug "add uvc to usb config, unlike adb, you have to run ur own uvc-gadget app"
	ln -s $GFUNC_PATH/$UVC_INSTANCE/ $GCONFIG/$UVC_INSTANCE
}

uvc_unlink()
{
	gadget_debug "remove uvc from usb config"
	g_remove $GCONFIG/$UVC_INSTANCE
}

## GADGET
no_udc()
{
	gadget_info "Echo none to udc"
	gadget_info "We are now trying to echo None to UDC......"
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && echo "" > $GADGET_PATH/UDC
	gadget_info "echo none to UDC successfully done"
	gadget_info "echo none to UDC done."
}

give_hint_to_which_have_udc_()
{
	for config_path in "/sys/kernel/config/usb_gadget/"*; do
		udc_path="$config_path/UDC"
		is_here=$(cat $udc_path | grep $selected_udc | wc -l)
		if [ "$is_here" -gt 0 ]; then
			gadget_info "ERROR: Your udc is occupied by: $udc_path"
		fi
	done
}

echo_udc()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && die "UDC `cat $GADGET_PATH/UDC` already been set"
	if [ "$USB_UDC_IDX" ]; then
		selected_udc=$(ls /sys/class/udc | awk "NR==$USB_UDC_IDX{print}")
	else
		selected_udc=$USB_UDC
		gadget_info "Selected udc by name: $selected_udc"
		gadget_info "We are now trying to echo $selected_udc to UDC......"
	fi
	our_udc_occupied=$(cat /sys/kernel/config/usb_gadget/*/UDC | grep $selected_udc | wc -l)
	if [ "$our_udc_occupied" -gt 0 ]; then
		give_hint_to_which_have_udc_
		gadget_info "ERROR: configfs preserved, run $name resume after conflict resolved"
		exit 127
	fi
	echo  $selected_udc > $GADGET_PATH/UDC
	gadget_info "echo $selected_udc to UDC done"
}

gconfig()
{
	PROFILE=$1
	gadget_info "config $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."
	mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
	[ -e $GADGET_PATH ] && die "ERROR: gadget already configured, should run stop first"
	mkdir -p $GADGET_PATH
	echo $VENDOR_ID > $GADGET_PATH/idVendor
	echo $PRODUC_ID > $GADGET_PATH/idProduct
	mkdir -p $GADGET_PATH/strings/0x409
	echo $SERNUM_STR > $GADGET_PATH/strings/0x409/serialnumber
	echo $MANUAF_STR > $GADGET_PATH/strings/0x409/manufacturer
	echo $PRODUC_STR > $GADGET_PATH/strings/0x409/product
	mkdir -p $GCONFIG
	echo 0xc0 > $GCONFIG/bmAttributes
	echo 500 > $GCONFIG/MaxPower
	mkdir -p $GCONFIG/strings/0x409
	uvc_config $PROFILE
}

gclean()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured, no need to clean"
	gadget_debug "clean uvc"
	destroy_uvc_
	# Remove string in gadget
	gadget_info "remove strings of $GADGET_PATH."
	g_remove $GADGET_PATH/strings/0x409
	# Remove gadget
	gadget_info "remove $GADGET_PATH."
	g_remove $GADGET_PATH
}

gunlink()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	uvc_unlink
	# Remove strings:
	gadget_info "remove strings of c.1."
	g_remove $GCONFIG/strings/0x409
	# Remove config:
	gadget_info "remove configs c.1."
	g_remove $GCONFIG
}

print_info()
{
	echo "SpacemiT uvc gadget setup tool $SCRIPT_VERSION"
	echo
	echo "Board Model: `tr -d '\000' < /proc/device-tree/model`"
	echo "General Config Info: $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."
	echo "Available UDCs: `ls  -1 /sys/class/udc/ |  tr '\n' ' '`"
	# echo "DTS default UDC: $USB_UDC_DTS"
	echo "DTS Serial Number: $BOARD_SN"
	echo
}

## MAIN
case "$1" in
	stop|clean)
		no_udc
		gunlink
		gclean
		;;
	pause|disconnect)
		no_udc
		;;
	resume|connect)
		USB_UDC_IDX=$2
		echo_udc
		;;
	help)
		usage
		;;
	info)
		print_info
		;;
	config)
		if [ ! -e "$CONFIG_FILE" ]; then
			echo "# .uvcg_config for spacemit-uvcg, config line format:" > $CONFIG_FILE
			echo "#     <format:[mjpeg]> <width> <height> <dwMaxVideoFrameBufferSize>" >> $CONFIG_FILE
			echo "# e.g. mjpeg 640 360 251733" >> $CONFIG_FILE
		fi
		vi $CONFIG_FILE
		;;
	start)
		gconfig $2
		uvc_link
		echo_udc
		;;
	*)
		usage
		;;
esac

exit $?
