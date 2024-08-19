#!/bin/sh
# WARNING: This setup script does NOT support humbird rootfs!!!
# Supported: bianbu-linux, bianbu-desktop

name=`basename $0`
SCRIPT_VERSION="v0.4"
CONFIG_FILE=$HOME/.usb_config

# USB Descriptors
VENDOR_ID="0x361c"
PRODUC_ID="0x0007"
MANUAF_STR="Spacemit"
PRODUC_STR="K1 Composite Device"
SERNUM_STR="20211102"
[ "$ADB_BOARD_SN" ] || ADB_BOARD_SN=$( [ -e /proc/device-tree/serial-number ] && tr -d '\000' < /proc/device-tree/serial-number )
[ "$ADB_BOARD_SN" ] && SERNUM_STR=$ADB_BOARD_SN

# Select default_udc as UDC from DTS if exist, use the first in sysfs otherwise
USB_UDC_DTS=$( [ -e /proc/device-tree/default_udc ] && tr -d '\000' < /proc/device-tree/default_udc )
[ "$USB_UDC" ] || USB_UDC=$USB_UDC_DTS
[ "$USB_UDC" ] || USB_UDC=$(ls /sys/class/udc | awk "NR==1{print}")

[ "$MAXPACKAGESIZE" ] || MAXPACKAGESIZE=1024
CONFIGFS=/sys/kernel/config
GADGET_PATH=$CONFIGFS/usb_gadget/spacemit
GFUNC_PATH=$GADGET_PATH/functions
GCONFIG=$GADGET_PATH/configs/c.1

# Debug Ramdisk for MSC without any argument
RAMDISK_PATH=/var/sdcard
TMPFS_FOUND=`mount | grep tmpfs | grep -v devtmpfs | awk '{print $3}' | grep '/dev/shm' | wc -l`
[ "$TMPFS_FOUND" -eq 1 ] && RAMDISK_PATH=/dev/shm/sdcard
TMPFS_FOUND=`mount | grep tmpfs | grep -v devtmpfs | awk '{print $3}' | grep '/tmp' | wc -l`
[ "$TMPFS_FOUND" -eq 1 ] && RAMDISK_PATH=/tmp/sdcard

# SCSI Target
NAA="naa.6001405c3214b06a"
CORE_DIR=$CONFIGFS/target/core
USB_GDIR=$CONFIGFS/target/usb_gadget

print_info()
{
	echo "SpacemiT gadget-setup tool $SCRIPT_VERSION"
	echo
	echo "Board Model: `tr -d '\000' < /proc/device-tree/model`"
	echo "General Config Info: $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."
	echo "Config File Path: $CONFIG_FILE"
	echo "MSC Ramdisk Path (selected from tmpfs mounting point): $RAMDISK_PATH"
	echo "UASP SCSI NAA: $NAA"
	echo "UASP Target Dir: $USB_GDIR"
	echo "Available UDCs: `ls  -1 /sys/class/udc/ |  tr '\n' ' '`"
	echo "DTS default UDC: $USB_UDC_DTS"
	echo "DTS Serial Number: $ADB_BOARD_SN"
	echo
}

# Global variables to record configured functions
MSC=disabled
UAS=disabled
UAS_ARG=""
MSC_ARG=""
ADB=disabled
UVC=disabled
UVCH=disabled
RNDIS=disabled
FUNCTION_CNT=0
DEBUG=okay

usage()
{
	echo "$name usage: "
	echo ""
	echo -e "Support Select functions in $CONFIG_FILE:"
	echo -e "\tWrite <func>:<arg> line in $CONFIG_FILE, then run:"
	echo -e "\t$name [start|stop|reload|config]"
	echo -e "Or Select functions manually:"
	echo -e "\t$name <function1>(,<function2>...)"
	echo -e "Set USB connection:"
	echo -e "\t$name [pause|resume]"
	echo -e "\n$name info: show gadget info"
	echo -e "\nhint: udc is automatically selected, you can"
	echo -e "\toverride udc idx with env USB_UDC_IDX="
	echo ""
	echo "Functions and arguments supported:"
	echo -e "\tmsc(:dev/file)  Mass Storage(Bulk-Only)."
	echo -e "\tuas(:dev/file)       Mass Storage(UASP)."
	echo -e "\tadb       Android Debug Bridge over USB."
	echo -e "\tuvc                              Webcam."
	# uvc1, uvc2 are for debug usage
	echo -e "\trndis                RNDIS NIC function."
	echo -e "\nSpacemiT gadget-setup tool $SCRIPT_VERSION"
	echo ""
}

gadget_info()
{
	echo "$name: $1"
}

gadget_debug()
{
	[ $DEBUG ] && echo "$name: $1"
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

## MSC
msc_ramdisk_()
{
	gadget_info "msc: ramdisk: $RAMDISK_PATH/disk.img"
	mkdir -p $RAMDISK_PATH/sda
	dd if=/dev/zero of=$RAMDISK_PATH/disk.img bs=1M count=1038
	mkdosfs -F 32 $RAMDISK_PATH/disk.img
}

msc_config()
{
	gadget_debug "add a msc function instance"
	MSC_DIR=$GFUNC_PATH/mass_storage.usb0
	mkdir -p $MSC_DIR
	DEVICE=$1
	[ $DEVICE ] || DEVICE=$MSC_ARG
	# Create a backstore
	if [ -z "$DEVICE" ]; then
		echo "$name: no device specificed, select ramdisk as backstore"
		msc_ramdisk_
		echo "tmp files would be created in: $RAMDISK_PATH"
		echo "$RAMDISK_PATH/disk.img" >  $MSC_DIR/lun.0/file
	elif [ -b $DEVICE ]; then
		echo "$name: block device"
		echo "$DEVICE" > $MSC_DIR/lun.0/file
	else
		echo "$name: other path, regular file"
		echo "$DEVICE" > $MSC_DIR/lun.0/file
	fi

	echo 1 > $MSC_DIR/lun.0/removable
	echo 0 > $MSC_DIR/lun.0/nofua
}

msc_link()
{
	gadget_debug "add msc to usb config"
	ln -s $MSC_DIR $GCONFIG/mass_storage.usb0
}

msc_unlink()
{
	gadget_debug "remove msc from usb config"
	g_remove $GCONFIG/mass_storage.usb0
}

msc_clean()
{
	gadget_debug "clean msc"
	g_remove $GFUNC_PATH/mass_storage.usb0
	g_remove $RAMDISK_PATH/disk.img
	g_remove $RAMDISK_PATH/sda
}

## UAS

uas_config()
{
	gadget_debug "add a uas function instance"
	# Load the target modules and mount the add a file function instance system
	# Uncomment these if modules not built-in:
	# lsmod | grep -q configfs || modprobe configfs
	# lsmod | grep -q target_core_mod || modprobe target_core_mod
	DEVICE=$1
	[ $DEVICE ] || DEVICE=$UAS_ARG
	mkdir -p $GADGET_PATH/functions/tcm.0
	# Create a backstore
	if [ -z "$DEVICE" ]; then
		echo "$name: no device specificed, select rd_mcp as backstore"
		BACKSTORE_DIR=$CORE_DIR/rd_mcp_0/ramdisk
		mkdir -p $BACKSTORE_DIR
		# 128MB pure ramdisk
		if [ $UAS_PERFORMACE ]; then
			gadgdet_info "Warning: user asked for performance test, uasp storage will broke rw reqs"
		else
			echo rd_pages=200000 > $BACKSTORE_DIR/control
		fi
	elif [ -b $DEVICE ]; then
		echo "$name: block device, select iblock as backstore"
		BACKSTORE_DIR=$CORE_DIR/iblock_0/iblock
		mkdir -p $BACKSTORE_DIR
		echo "udev_path=${DEVICE}" > $BACKSTORE_DIR/control
	else
		echo "$name: other path, select fileio as backstore"
		BACKSTORE_DIR=$CORE_DIR/fileio_0/fileio
		mkdir -p $BACKSTORE_DIR
		DEVICE_SIZE=$(du -b $DEVICE | cut -f1)
		echo "fd_dev_name=${DEVICE},fd_dev_size=${DEVICE_SIZE}" > $BACKSTORE_DIR/control
		# echo 1 > $BACKSTORE_DIR/attrib/emulate_write_cache
	fi
	[ -n "$DEVICE" ] && umount $DEVICE
	echo 1 > $BACKSTORE_DIR/enable
	echo "$name: NAA of target: $NAA"
	# Create an NAA target and a target portal group (TPG)
	mkdir -p $USB_GDIR/$NAA/tpgt_1/
	echo "$name tpgt_1 has lun_0"
	# Create a LUN
	mkdir $USB_GDIR/$NAA/tpgt_1/lun/lun_0
	# Nexus initiator on target port 1 to $NAA
	echo $NAA > $USB_GDIR/$NAA/tpgt_1/nexus

	# Allow write access for non authenticated initiators
	# echo 0 > $USB_GDIR/$NAA/tpgt_1/attrib/demo_mode_write_protect
	ln -s $BACKSTORE_DIR $USB_GDIR/$NAA/tpgt_1/lun/lun_0/data
	#ln -s $BACKSTORE_DIR $USB_GDIR/$NAA/tpgt_1/lun/lun_0/virtual_scsi_port
	# echo 15 > $USB_GDIR/$NAA/tpgt_1/maxburst

	# Enable the target portal group, with 1 lun
	echo 1 > $USB_GDIR/$NAA/tpgt_1/enable
}

uas_link()
{
	gadget_debug "add uas to usb config"
	ln -s $GADGET_PATH/functions/tcm.0 $GCONFIG/tcm.0
}

uas_unlink()
{
	gadget_debug "remove uas from usb config"
	g_remove $GCONFIG/tcm.0
}

uas_clean()
{
	gadget_debug "clean uas"
	[ -d "$USB_GDIR/$NAA/tpgt_1/enable" ] && echo 0 > $USB_GDIR/$NAA/tpgt_1/enable
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0/data
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0/virtual_scsi_port
	g_remove $USB_GDIR/$NAA/tpgt_1/lun/lun_0
	g_remove $USB_GDIR/$NAA/tpgt_1/
	g_remove $USB_GDIR/$NAA/
	g_remove $USB_GDIR
	BACKSTORE_DIR=$CORE_DIR/iblock_0/iblock
	g_remove $BACKSTORE_DIR
	BACKSTORE_DIR=$CORE_DIR/fileio_0/fileio
	g_remove $BACKSTORE_DIR
	BACKSTORE_DIR=$CORE_DIR/rd_mcp_0/ramdisk
	g_remove $BACKSTORE_DIR
	g_remove $GADGET_PATH/functions/tcm.0
}

## ADB

adb_config()
{
	gadget_debug "add a adb function instance"
	mkdir $GFUNC_PATH/ffs.adb
}

adb_link()
{
	gadget_debug "add adb to usb config"
	ln -s $GFUNC_PATH/ffs.adb/ $GCONFIG/ffs.adb
	mkdir /dev/usb-ffs
	mkdir /dev/usb-ffs/adb
	mount -o uid=2000,gid=2000 -t functionfs adb /dev/usb-ffs/adb/
	#mkdir /dev/pts
	#mount -t devpts -o defaults,mode=644,ptmxmode=666 devpts /dev/pts
	adbd &
	sleep 1
}

adb_unlink()
{
	gadget_debug "remove adb from usb config"
	killall adbd
	g_remove $GCONFIG/ffs.adb
	[ -e /dev/usb-ffs/adb/ ] && umount /dev/usb-ffs/adb/
	#[ -e /dev/pts ] && umount /dev/pts
	#g_remove /dev/pts
	g_remove /dev/usb-ffs/adb
	g_remove /dev/usb-ffs
}

adb_clean()
{
	gadget_debug "clean adb"
	g_remove $GFUNC_PATH/ffs.adb
}

## UVC
### UVC Common
### Setup uvc frame interval for yuv 360p with 15fps (7MBps).
uvc_frame_1_(){
	UVC_FRAME_WDIR=$1
	echo 1000000 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	echo 49152000 > $UVC_FRAME_WDIR/dwMinBitRate
	echo 55296000 > $UVC_FRAME_WDIR/dwMaxBitRate
}

### Setup uvc frame interval for at most yuv 360p with 60fps (13MBps)
uvc_frame_2_(){
	UVC_FRAME_WDIR=$1
	echo 333333 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	echo 110592000 > $UVC_FRAME_WDIR/dwMinBitRate
	echo 221184000 > $UVC_FRAME_WDIR/dwMaxBitRate
}

### Setup uvc frame interval for at most yuv 720p with 60fps (14~52MBps)
uvc_frame_3_(){
	UVC_FRAME_WDIR=$1
	echo 333333 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	echo 110592000 > $UVC_FRAME_WDIR/dwMinBitRate
	echo 442276000 > $UVC_FRAME_WDIR/dwMaxBitRate
}

### Setup uvc frame interval for at most yuv 1080p with 30fps (14~52MBps)
uvc_frame_4_(){
	UVC_FRAME_WDIR=$1
	echo 333333 > $UVC_FRAME_WDIR/dwDefaultFrameInterval
	echo 110592000 > $UVC_FRAME_WDIR/dwMinBitRate
	echo 442276000 > $UVC_FRAME_WDIR/dwMaxBitRate
}

### Setup streaming/ directory.
configure_uvc_format_()
{
	FORMAT=$1 # $1 format "uncompressed/y" / "mjpeg/m"
	UVC_DISPLAY_W=$2 # $2 Width
	UVC_DISPLAY_H=$3 # $3 Height
	HIGH_FRAMERATE=$4 # $4 HIGH_FRAMERATE 0/1
	#https://docs.kernel.org/usb/gadget_uvc.html
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	UVC_FRAME_WDIR=${UVC_MJPEG_PRE_PATH}/${UVC_DISPLAY_H}p
	mkdir -p $UVC_FRAME_WDIR
	echo $UVC_DISPLAY_W > $UVC_FRAME_WDIR/wWidth
	echo $UVC_DISPLAY_H > $UVC_FRAME_WDIR/wHeight
	echo $(( $UVC_DISPLAY_W * $UVC_DISPLAY_H * 2 )) > $UVC_FRAME_WDIR/dwMaxVideoFrameBufferSize
	if [ "$HIGH_FRAMERATE" -eq 1 ]; then
		uvc_frame_1_ $UVC_FRAME_WDIR
	else
		uvc_frame_1_ $UVC_FRAME_WDIR
	fi
	cat <<EOF > $UVC_FRAME_WDIR/dwFrameInterval
166666
333333
416667
500000
666666
1000000
1333333
2000000
EOF
}

clean_uvc_format_()
{
	FORMAT=$1
	UVC_DISPLAY_W=$2
	UVC_DISPLAY_H=$3
	UVC_MJPEG_PRE_PATH=$GFUNC_PATH/$UVC_INSTANCE/streaming/$FORMAT
	UVC_FRAME_WDIR=${UVC_MJPEG_PRE_PATH}/${UVC_DISPLAY_H}p
	g_remove $UVC_FRAME_WDIR
}

clean_uvc_format_all_()
{
	clean_uvc_format_ uncompressed/y 640 360
	clean_uvc_format_ uncompressed/y 640 480
	clean_uvc_format_ uncompressed/y 1280 720
	clean_uvc_format_ uncompressed/y 1920 1080
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y
	clean_uvc_format_ mjpeg/m 640 360
	clean_uvc_format_ mjpeg/m 640 480
	clean_uvc_format_ mjpeg/m 1280 720
	clean_uvc_format_ mjpeg/m 1920 1080
	g_remove $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m
}

configure_uvc_link_()
{
	mkdir $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/mjpeg/m/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/m
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/uncompressed/y/ $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/y
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/fs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/hs
	ln -s $GFUNC_PATH/$UVC_INSTANCE/streaming/header/h/ $GFUNC_PATH/$UVC_INSTANCE/streaming/class/ss
	mkdir $GFUNC_PATH/$UVC_INSTANCE/control/header/h
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/fs/
	ln -s $GFUNC_PATH/$UVC_INSTANCE/control/header/h/ $GFUNC_PATH/$UVC_INSTANCE/control/class/ss/
}

clean_uvc_link_()
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

clean_uvc_()
{
	clean_uvc_link_
	clean_uvc_format_all_
	g_remove $GFUNC_PATH/$UVC_INSTANCE
}

configure_uvc_maxpacket_()
{
	MAX=$1 ## $1 1024/2048/3072
	FUNCTION=$GFUNC_PATH/$UVC_INSTANCE
	gadget_info "Setting streaming_maxpacket to $MAX"
	echo $MAX > $FUNCTION/streaming_maxpacket
	echo 15  > $FUNCTION/streaming_maxburst
}

configure_uvc_xu_()
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
	gadget_debug "add a uvc function instance"
	UVC_INSTANCE=uvc.usb0
	mkdir -p $GFUNC_PATH/$UVC_INSTANCE
	configure_uvc_format_ uncompressed/y 640 360 0
	configure_uvc_format_ uncompressed/y 640 480 0
	configure_uvc_format_ uncompressed/y 1280 720 1
	configure_uvc_format_ uncompressed/y 1920 1080 1
	configure_uvc_format_ mjpeg/m 640 360 1
	configure_uvc_format_ mjpeg/m 1280 720 1
	configure_uvc_format_ mjpeg/m 1920 1080 1
	## TODO: H.264 and HEVC(265)
	## Latest Ongoing: https://patchwork.kernel.org/project/linux-usb/patch/20240711082304.1363-1-quic_akakum@quicinc.com/# configure_uvc_format_ h264/h 640 360 1
	# configure_uvc_format_ h264/h 1280 720 1
	# configure_uvc_format_ h264/h 1920 1080 1
	# configure_uvc_format_ hevc/h 640 360 1
	# configure_uvc_format_ hevc/h 1280 720 1
	# configure_uvc_format_ hevc/h 1920 1080 1
	configure_uvc_maxpacket_ $MAXPACKAGESIZE
	configure_uvc_link_
}

uvc_link()
{
	gadget_debug "add uvc to usb config, unlike adb, you have to run ur own uvc-gadget app"
	UVC_INSTANCE=uvc.usb0
	ln -s $GFUNC_PATH/$UVC_INSTANCE/ $GCONFIG/$UVC_INSTANCE
}

uvc_unlink()
{
	gadget_debug "remove uvc from usb config"
	UVC_INSTANCE=uvc.usb0
	g_remove $GCONFIG/$UVC_INSTANCE
}

uvc_clean()
{
	gadget_debug "clean uvc"
	UVC_INSTANCE=uvc.usb0
	clean_uvc_
}

## RNDIS

rndis_config()
{
	OVERRIDE_VENDOR_FOR_WINDOWS=$1
	# create function instance
	# functions/<f_function allowed>.<instance name>
	# f_function allowed: rndis
	mkdir -p $GFUNC_PATH/rndis.0
}

rndis_link()
{
	ln -s $GFUNC_PATH/rndis.0 $GCONFIG
	HOST_ADDR=`cat $GFUNC_PATH/rndis.0/host_addr`
	DEV_ADDR=`cat $GFUNC_PATH/rndis.0/dev_addr`
	IFNAME=`cat $GFUNC_PATH/rndis.0/ifname`
	gadget_info "rndis function enabled, mac(h): $HOST_ADDR, mac(g): $DEV_ADDR, ifname: $IFNAME."
	gadget_info "execute ifconfig $IFNAME up to enable rndis iface."
}

rndis_unlink()
{
	[ -e $GFUNC_PATH/rndis.0/ifname ] && ifconfig `cat $GFUNC_PATH/rndis.0/ifname` down
	g_remove $GCONFIG/rndis.0
}

rndis_clean()
{
	g_remove $GFUNC_PATH/rndis.0
}

## MTP

mtp_config()
{
	die "MTP Not Supported yet."
}

mtp_link()
{
	die "MTP Not Supported yet."
}

mtp_unlink()
{
	die "MTP Not Supported yet."
}

mtp_clean()
{
   die "MTP Not Supported yet."
}

## GADGET
no_udc()
{
	gadget_info "Echo none to udc"
	logger "We are now trying to echo None to UDC......"
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && echo "" > $GADGET_PATH/UDC
	gadget_info "echo none to UDC successfully done"
	logger "echo none to UDC done."
}

echo_udc()
{
	[ $USBDEV_IDX ] || USBDEV_IDX=1
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	[ `cat $GADGET_PATH/UDC` ] && die "UDC `cat $GADGET_PATH/UDC` already been set"
	if [ "$USB_UDC_IDX" ]; then
		selected_udc=$(ls /sys/class/udc | awk "NR==$USBDEV_IDX{print}")
	else
		selected_udc=$USB_UDC
		gadget_info "Selected udc idx $USBDEV_IDX: $selected_udc"
		gadget_info "We are now trying to echo $selected_udc to UDC......"
	fi
	echo  $selected_udc > $GADGET_PATH/UDC
	gadget_info "echo $selected_udc to UDC done"
}

gconfig()
{
	gadget_info "config $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."
	mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
	[ -e $GADGET_PATH ] && die "ERROR: gadget already configured, should run stop first"
	mkdir $GADGET_PATH
	echo $VENDOR_ID > $GADGET_PATH/idVendor
	echo $PRODUC_ID > $GADGET_PATH/idProduct
	mkdir $GADGET_PATH/strings/0x409
	echo $SERNUM_STR > $GADGET_PATH/strings/0x409/serialnumber
	echo $MANUAF_STR > $GADGET_PATH/strings/0x409/manufacturer
	echo $PRODUC_STR > $GADGET_PATH/strings/0x409/product
	mkdir $GCONFIG
	echo 0xc0 > $GCONFIG/bmAttributes
	echo 500 > $GCONFIG/MaxPower
	mkdir $GCONFIG/strings/0x409
	[ $MSC = okay ] &&  msc_config
	[ $UAS = okay ] &&  uas_config
	[ $RNDIS = okay ] && rndis_config
	[ $ADB = okay ] &&  adb_config
	[ $UVC = okay ] &&  uvc_config
}

gclean()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured, no need to clean"
	msc_clean
	uas_clean
	rndis_clean
	adb_clean
	uvc_clean
	# Remove string in gadget
	gadget_info "remove strings of $GADGET_PATH."
	g_remove $GADGET_PATH/strings/0x409
	# Remove gadget
	gadget_info "remove $GADGET_PATH."
	g_remove $GADGET_PATH
}

glink()
{
	[ $MSC  = okay ] && msc_link
	[ $UAS  = okay ] && uas_link
	[ $RNDIS  = okay ] && rndis_link
	[ $ADB  = okay ] && adb_link
	[ $UVC  = okay ] && uvc_link
	[ $UVCH  = okay ] && uvch_link
}

gunlink()
{
	[ -e $GADGET_PATH/UDC ] || die "gadget not configured yet"
	msc_unlink
	uas_unlink
	rndis_unlink
	# adb_unlink
	uvc_unlink
	# Remove strings:
	gadget_info "remove strings of c.1."
	g_remove $GCONFIG/strings/0x409
	# Remove config:
	gadget_info "remove configs c.1."
	g_remove $GCONFIG
}

select_one()
{
	func=$1
	
	if [[ "$func" == "#"* ]];then
		gadget_debug "met hashtag, skip"
		return
	fi

	case "$func" in
		msc*|mass*|storage*)
			MSC=okay
			MSC_ARG=$(echo $func | awk -F: '{print $2}')
			;;
		"uvc"|"video|webcam")
			UVC=okay
			;;
		"uvch"|"videoh")
			UVCH=okay
			;;
		uas*|uasp*)
			UAS=okay
			UAS_ARG=$(echo $func | awk -F: '{print $2}')
			;;
		"rndis"|"network"|"net"|"if")
			RNDIS=okay
			;;
		"mtp")
			MTP=okay
			;;
		"adb"|"fastboot"|"adbd")
			ADB=okay
			;;
		*)
			die "not supported function: $func"
			;;
	esac
	gadget_info "Selected function $func"
	let FUNCTION_CNT=FUNCTION_CNT+1
}

handle_select() {
	local input_str=$1
	local IFS=,  # split via comma
	OLDIFS=$IFS  # split functions
	IFS=,
	for token in $input_str; do
		[ $DEBUG ]
		select_one $token
	done
	IFS=$OLDIFS
}

parse_config()
{
	[ -e  $CONFIG_FILE ] || die "$CONFIG_FILE not found, abort."
	while read line
	do
		select_one $line
	done < $CONFIG_FILE
}

gstart()
{
	gconfig
	glink
	[ $FUNCTION_CNT -lt 1 ] && die "No function selected, will not pullup."
	echo_udc $1
}

gstop()
{
	no_udc
	gunlink
	gclean
}

## MAIN
case "$1" in
	stop|clean)
		gstop
		;;
	restart|reload)
		gstop
		parse_config
		gstart
		;;
	start)
		parse_config
		gstart $2
		;;
	pause|disconnect)
		no_udc
		;;
	resume|connect)
		USBDEV_IDX=$2
		echo_udc
		;;
	config)
		vi $CONFIG_FILE
		[ -e $CONFIG_FILE ] && gadget_info ".usb_config updated"
		;;
	help)
		usage
		;;
	info)
		print_info
		;;
	[a-z]*) 
		handle_select $1
		gstart $2
		;;
	*)
		usage
		;;
esac

exit $?
