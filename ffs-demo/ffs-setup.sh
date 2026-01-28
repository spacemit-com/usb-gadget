#!/bin/sh

VENDOR_ID="0x1d6b"
PRODUC_ID="0x0109"
SERNUM_STR="20211102"
MANUAF_STR="Spacemit"
PRODUC_STR="K1 AIO"

[ -e  /sys/class/net/eth0 ] && demo_MAC_SN=$(sed 's/://g' /sys/class/net/eth0/address)
[ "$demo_MAC_SN" ] && SERNUM_STR=$demo_MAC_SN
[ "$demo_BOARD_SN" ] || demo_BOARD_SN=$(cat /proc/device-tree/serial-number)
[ "$demo_BOARD_SN" ] && SERNUM_STR=$demo_BOARD_SN

config_gadget()
{
    echo "$0: config $VENDOR_ID/$PRODUC_ID/$SERNUM_STR/$MANUAF_STR/$PRODUC_STR."

    # mount /dev/mmcblk0 /mnt/SDCARD

    mount -t configfs none /sys/kernel/config

    mkdir /sys/kernel/config/usb_gadget/ffs-demo

    echo $VENDOR_ID > /sys/kernel/config/usb_gadget/ffs-demo/idVendor
    echo $PRODUC_ID > /sys/kernel/config/usb_gadget/ffs-demo/idProduct

    mkdir /sys/kernel/config/usb_gadget/ffs-demo/strings/0x409
    echo $SERNUM_STR > /sys/kernel/config/usb_gadget/ffs-demo/strings/0x409/serialnumber
    echo $MANUAF_STR > /sys/kernel/config/usb_gadget/ffs-demo/strings/0x409/manufacturer
    echo $PRODUC_STR > /sys/kernel/config/usb_gadget/ffs-demo/strings/0x409/product

    mkdir /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1
    echo 0xc0 > /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/bmAttributes
    echo 500 > /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/MaxPower
    mkdir /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/strings/0x409

    # os_desc
    echo "1" > "/sys/kernel/config/usb_gadget/ffs-demo/os_desc/use"
    echo "0x1" > "/sys/kernel/config/usb_gadget/ffs-demo/os_desc/b_vendor_code"
    echo "MSFT100" > "/sys/kernel/config/usb_gadget/ffs-demo/os_desc/qw_sign"
    ln -s "/sys/kernel/config/usb_gadget/ffs-demo/configs/c.1" "/sys/kernel/config/usb_gadget/ffs-demo/os_desc/"

}

clean_gadget()
{
    # Remove strings:
    echo "gadget-setup: remove strings of c.1."
    rmdir /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/strings/0x409

	rm /sys/kernel/config/usb_gadget/ffs-demo/os_desc/c.1

    # Remove config:
    echo "gadget-setup: remove configs c.1."
    rmdir /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1
    # Remove string in gadget
    echo "gadget-setup: remove strings of ffs-demo."
    rmdir /sys/kernel/config/usb_gadget/ffs-demo/strings/0x409

    # Remove gadget
    echo "gadget-setup: remove ffs-demo."
    rmdir /sys/kernel/config/usb_gadget/ffs-demo
}

setup()
{
    mkdir /sys/kernel/config/usb_gadget/ffs-demo/functions/ffs.demo
    ln -s /sys/kernel/config/usb_gadget/ffs-demo/functions/ffs.demo/ /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/ffs.demo
    mkdir -p /dev/usb-ffs
    mkdir -p /dev/usb-ffs/demo
    mount -o uid=2000,gid=2000 -t functionfs demo /dev/usb-ffs/demo/
    demod /dev/usb-ffs/demo &
}

udc()
{
    selected_udc=$(ls /sys/class/udc | awk "NR==1{print}")
    echo $selected_udc > /sys/kernel/config/usb_gadget/ffs-demo/UDC
}

noudc()
{
    echo  > /sys/kernel/config/usb_gadget/ffs-demo/UDC
}

clean()
{
    killall demod
    rm -f /sys/kernel/config/usb_gadget/ffs-demo/configs/c.1/ffs.demo
    rmdir /sys/kernel/config/usb_gadget/ffs-demo/functions/ffs.demo
    umount /dev/usb-ffs/demo/
    rmdir /dev/usb-ffs/demo
    rmdir /dev/usb-ffs
}

OPT=$1

case "$1" in
    start)
        config_gadget
        setup
        sleep 1
        udc
        ;;
    stop)
        noudc
        clean
        clean_gadget
        ;;
    restart|reload)
        noudc
        clean
        clean_gadget
        config_gadget
        setup
	sleep 1
        udc
        ;;
    *)
        echo "Usage: $0 {start|stop|reload}"
        exit 1
esac

exit $?
