# SpacemiT FFS Demo

## Custom Feature

The code is modified based on `tools/usb/ffs-aio-example/simple/device_app` in linux kernel repo.

1. Support Windows WCID automatically bind WINUSB driver by adding Microsoft
    os descriptor.
2. Provide easily customizable setup script.
3. Add some meaningful demo data and log printing.

## Usage
The default app name is "demod", this is defined in `setup()` of
ffs-setup.sh.

1. Install libaio-dev package on Bianbu OS first:

```bash
sudo apt update && apt install libaio-dev
```

2. Compile the device service app:

```bash
make
make install
```

Once commands finished, a binary named `demod` will be added to `/usr/bin/` directory.

3. Pull-up the gadget.

To pull-up the ffs-demo gadget, we need to stop the Bianbu built-in adb
ffs service which ocuppied the UDC.

```bash
systemctl stop adbd
```

Then run:

```bash
bash ffs-setup.sh start
```

4. Clean the gadget, resume Bianbu built-in adb service
```bash
bash ffs-setup.sh stop
systemctl start adbd
```

5. Plug the usb cable connected to PC host,
   you will see a new USB Device named "K1 AIO". 
   
   Then you can use `host_app` in `tools/usb/ffs-aio-example/` on Linux Host PC or userspace application based on WINUSB and libusb (the host_demo.py python script for example) on Windows PC to communicate with the ffs bulk demo gadget.