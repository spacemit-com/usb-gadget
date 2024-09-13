## 编译

导出交叉工具链到环境变量

```
$ make
//copy scripts/gadget-setup.sh and uvc-gadget-new to k1 board
```

## 配置脚本
本仓库提供两个 usb gadget 配置脚本，分别是：
1. 用于配置 uvc gadget 的 uvc-gadget-setup.sh 和
2. 支持 adb、rndis、uvc、mass storage 的 gadget-setup.sh。

具体使用方法可以查看对应脚本 help 命令及参考本文档的后续章节。

查看脚本使用帮助：
```
uvc-gadget-setup.sh help
gadget-setup.sh help
```


## UVC
UVC配置可选用两种方法：

1. 使用专用uvc脚本，支持更多uvc配置，独立USB PID（推荐）：
```
$ /etc/init.d/S50adb-setup stop
$ uvc-gadget-setup.sh start
$ uvc-gadget-new
```

2. 使用composite gadget脚本，支持uvc与其他功能同时使用。
```
$ /etc/init.d/S50adb-setup stop
$ gadget-setup.sh uvc
$ uvc-gadget-new
```



## RNDIS

```
gadget-setup.sh rndis
```

### PC端设置

![img_v3_02dr_d968d898-83fe-4f63-a236-1dade8dc0c4g](20240819-112732.jpg)

## ADB
gadget-setup.sh 通用脚本集成了 ADB。

注：不能和系统集成的同时使用。
```
# 配置 adb
gadget-setup.sh adb
# 停止 adb
gadget-setup.sh stop
```

## Mass Storage （BOT协议）
```
gadget-setup.sh msc:<镜像或设备节点>
# 举例
gadget-setup.sh msc:/dev/nvme0n1
```

## Mass Storage （支持UASP协议）
UASP协议提升了传输效率。
```
gadget-setup.sh uas:<镜像或设备节点>
# 举例
gadget-setup.sh uas:/dev/nvme0n1
```


## 复合设备
举例：rndis + adb：
```
gadget-setup.sh rndis,adb
```

## 手动切换控制器角色
在usb控制器支持手动切换的方案中，可以通过以下命令来查看支持切换的控制器：
```
gadget-setup.sh info
```
通过以下命令来切换控制器角色 host 或 device：
```
gadget-setup.sh role <控制器/otg名称> <device或者host>
# 举例：
gadget-setup.sh role c0a00000.dwc3 device
```
注：切换至device模式时如果对应USB接口存在额外的vbus配置，需要手动关闭，见具体方案文档。
