ifneq ($(KERNELRELEASE),)

EXTRA_CFLAGS += -Wall

obj-m := poll.o

else

KERNELDIR ?= /lib/modules/$(shell uname -r)/build

PWD := $(shell pwd)

all: module

module:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules 

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean 

endif
