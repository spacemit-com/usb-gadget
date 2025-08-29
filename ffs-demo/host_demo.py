import usb.core
import usb.util
import usb.backend.libusb1

"""
Usage:
1. install pyusb if not already:
   pip install pyusb
2. install libusb backend for windows.(https://libusb.info/).
3. Replace the libusb backend path to your libusb-1.0.dll.
4. Run this script with python3.
"""

# Replace with your gadget's VID and PID
VID = 0x1d6b
PID = 0x0109

# Find the device
# TODO: Please replace the path to your libusb-1.0.dll
backend = usb.backend.libusb1.get_backend(find_library=lambda x: r"D:\Downloads\libusb-1.0.29\MinGW64\dll\libusb-1.0.dll")
dev = usb.core.find(idVendor=VID, idProduct=PID, backend=backend)
if dev is None:
    raise ValueError("Device not found. Check VID/PID and WinUSB binding.")

# Set the active configuration (usually config 1)
dev.set_configuration()

# Get endpoint addresses
cfg = dev.get_active_configuration()
intf = cfg[(0, 0)]

# Assume first OUT and first IN endpoint
ep_out = usb.util.find_descriptor(
    intf,
    custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_OUT
)
ep_in = usb.util.find_descriptor(
    intf,
    custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN
)

if ep_out is None or ep_in is None:
    raise ValueError("Endpoints not found. Check your gadget descriptors.")

# Send "hello world"
# pad space to 8192
data_out = b"hello world"
print("Sending:", data_out)
ep_out.write(data_out)

# Read response (expecting "spacemit")
try:
    data_in = ep_in.read(8192, timeout=2000)  # 64-byte max packet
    print("Received:", bytes(data_in).decode(errors="ignore"))
except usb.core.USBError as e:
    print("Read failed:", e)
