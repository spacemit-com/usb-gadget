INSTALL = install
PREFIX = $(HUMBIRD_ROOTFS_DIR)/usr
SBINDIR = $(PREFIX)/bin

TARGET          = uvc-gadget-new
INCLUDES        += -I./lib \
				   -I./include \
				   -I./include/uvcgadget \
				   -L.
#LDFLAGS       += -DDEBUG

SRCS := src/main.c
LIBSRCS :=   lib/configfs.c \
  lib/events.c \
  lib/jpg-source.c \
  lib/slideshow-source.c \
  lib/stream.c \
  lib/test-source.c \
  lib/timer.c \
  lib/uvc.c \
  lib/v4l2.c \
  lib/v4l2-source.c \
  lib/video-buffers.c \
  lib/video-source.c

OBJS    = $(SRCS:.c=.o)

LIBOBJS = $(LIBSRCS:.c=.o)

%.o: %.c
	$(CC) $(CFLAGS) $(LOCAL_CFLAGS) $(INCLUDES) -c -o $@ $<

all: $(TARGET)

libuvcgadget.a: $(LIBOBJS)
	ar r $@ $(LIBOBJS)

LOCAL_CFLAGS := -O2 -g -Wimplicit-function-declaration -Wno-unused-parameter
LOCAL_CFLAGS += -D_GNU_SOURCE

$(TARGET): $(OBJS) libuvcgadget.a
	$(CC) $(LDFLAGS) $(INCLUDES) $(OBJS) -luvcgadget  -o $@

install:
	$(INSTALL) -d $(SBINDIR)
	$(INSTALL) -m 755 -s --strip-program=$(STRIP) $(TARGET) $(SBINDIR)/
	$(INSTALL) -m 777 scripts/uvc-gadget-setup.sh $(SBINDIR)/uvc-gadget-setup
	$(INSTALL) -m 777 scripts/gadget-setup.sh $(SBINDIR)/gadget-setup

clean:
	rm -f lib/*.o
	rm -f src/*.o
	rm -f $(TARGET)
	rm -f libuvcgadget.a

distclean: clean
	-rm -rf .stamp_*

uninstall:
	-rm -rf $(SBINDIR)/$(TARGET)

.PHONY:all clean install uninstall $(TARGET)
