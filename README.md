# makertai
Building and testing RTAI-patched linux kernels.

- `makertaikernel.sh`: bash-script for building and testing RTAI-patched linux kernels
- `testreport.py`: python script for analyzing and summarizing test
  reports produced by the `makertaikernel.sh` script (work in progress).
- `alive.sh`: script producing some output on your console to
  indicate that the machine is still alive.
- `cpulatency`: kernel module for setting CPU latencies to zero via the PM-QoS kernel 
  interface.
- `poll`: kernel module intended to poll on a single CPU to keep it in C0 state 
  (not working yet).


## Content
- [Install an RTAI-patched linux kernel][quickinstall]
- [Testing the RTAI-patched kernel][testrtai]
- [Improve the RTAI-patched kernel][configurekernel]
- [Test results][testresults]


## Install an RTAI-patched linux kernel, RTAI, and comedi

The `makertaikernel.sh` script executes all the commands needed to
download and build an RTAI-patched linux kernel, the newlib library
(needed for math support), and the RTAI and comedi kernel modules.

Check
```
./makertaikernel.sh help
```
for an overview.

The script is so far only used and tested on debian/ubuntu based
systems and is likely to fail on other Linux distributions. Feel free
to adapt the script to your Linux distribution; in particular check
the `setup_*` functions.


### Preparations

When you use `makertaikernel.sh` for the first time, then follow these instructions:

1. Change into the directory with the `makertaikernel.sh` script.

2. Write the default configuration file
   ```
   ./makertaikernel.sh config
   ```

3. Check the settings by running
   ```
   ./makertaikernel.sh info settings
   ```
   In particular the RTAI source, i.e. the value assinged to the `RTAI_DIR` variable.
   
   If you want to change the RTAI source, then open the configuration
   file `makertaikernel.cfg` in your favourite text editor and select
   an RTAI source by modifying the value assinged to the `RTAI_DIR`
   variable.  See comments in the configuration file for options.

4. Run
   ```
   sudo ./makertaikernel.sh init
   ```
   to make sure you have `/var/log/messages` (needed for RTAI switch
   tests), get a visible boot menu, can pass kernel parameter to the
   RTAI kernel, have comedi devices assigned to the `iocard` group,
   and have the RTAI sources downloaded.

   This command ends with showing you the RTAI kernel patches
   available for your machine.


### Building the first kernel

1. Select a Linux kernel and the corresponding RTAI patch from the displayed list.

   Modify the variables `LINUX_KERNEL`, `RTAI_PATCH`, and
   `KERNEL_PATH` variables in the `makertaikernel.cfg` configuration
   file to match the kernel version, rtai patch you want to use, and
   the directory where to build the linux kernel (you need up to 2 GB
   space there for a kernel with most device drivers disabled
   (e.g. via localmodconf) or 5-10GB for a full kernel).

   Recheck for available RTAI patches and linux kernels:
   ```
   sudo ./makertaikernel.sh info rtai
   ```

2. You should start out with a kernel
   configuration of a kernel image from your linux distribution
   closest to the kernel version you selected. On a Debian-based
   system install a matching kernel by executing
   ```
   sudo apt-get install linux-image-4.4.0-79
   ```
   Modify the name of the kernel image to the kernel version you want, use the tab-key for
   autocompletion. If autocompletion does not work run
   ```
   apt-cache search -n linux-image-XXX | awk -F ' - ' '{if ( $1 !~ "-dbg" ) print $1}'
   ```
   where `XXX` is replaced by the kernel version you are looking for.
   Then boot into this kernel. Either restart your computer
   and select the kernel from the grub boot menu or check the grub menu with
   ```
   sudo ./makertaikernel.sh info grub
   ```
   and reboot directly into this kernel by using
   ```
   ./makertaikernel.sh reboot 3
   ```
   Replace `3` by the index of the appropriate menu entry. The latter
   approach has the advantage that it doesn't matter to miss the boot menu.

   Starting out with a kernel matching the one from the selected RTAI
   patch ensures that `makertaikernel.sh` will use this kernel's
   configuration and deselect all kernel modules that are not used
   (localmodconfig). This dramatically shortens the compile time (5-15min).

   If you use `makertaikernel.sh` with the `-l` switch or the
   version of the running kernel does not match the one of the
   selected kernel (major or minor version number differ),
   localmodconfig is not applied, resulting in a much larger kernel
   (takes much more time to compile - about one full hour or more).

3. Once you booted into the kernel on which you want to base your RTAI
   kernel run
   ```
   sudo ./makertaikernel.sh
   ```

   This will download the required sources (takes a while...) and
   build the kernel using the kernel configuration of the running
   kernel (takes even more time...). 

   With the `-c` flag you can provide a different kernel configuration
   on which the kernel configuration should be based (see
   `makertaikernel.sh help` for details).

4. You will get the menu for configuring the kernel. You need to
   change a few settings to get a running RTAI-patched kernel. See the
   next section [Basic kernel configuration][basickernelconfiguration] for instructions.

5. Reboot into the new kernel by executing
   ```
   ./makertaikernel.sh reboot
   ```

### Basic kernel configuration
For making the Linux kernel work with RTAI you should check the following settings 
in the kernel configuration dialog. 

This list is updated for RTAI 5.1. For other RTAI versions read
`/usr/local/src/rtai/README.CONF_RMRKS` !

- "General setup":
  - Disable "Enable sytem-call auditing support" (`AUDITSYSCALL`)
  - Important: set "Stack Protector buffer overflow detection" (at the bottom of the menu) to
    "Regular" (`CC_STACKPROTECTOR_REGULAR`)  - 
    or even "None" (`CC_STACKPROTECTOR_NONE`) if the latency test crashes.
  
- "Power management and ACPI options":
  - In "ACPI (Advanced Configuration and Power Interface) Support":
    - Disable "Processor" (`ACPI_PROCESSOR`)
  - Disable "CPU Frequency scaling" (`CPU_FREQ`)
  - In "CPU Idle":
    - Disable "CPU idle PM support" (`CPU_IDLE`)

- "Device Drivers":
  - In "Staging drivers":
    - Deselect "Data acquisition support (comedi)" (`COMEDI`)

- "Kernel hacking": 
  - In "Compile-time checks and compiler options":
    - Disable "Compile the kernel with debug info" (`DEBUG_INFO`)
    Disabling debugging information makes the kernel much
    smaller. So unless you know that you need it disable it.
  - Disable "Tracers" (`FTRACE`)

Leave the configuration dialog by pressing "Exit" until you are asked "Save kernel config?".
Select "Yes".

Then the new kernel is being compiled - be patient.


### Testing and improving

1. Test and improve your RTAI kernel as described in sections
   [Testing the RTAI-patched kernel][testrtai] and [Improve the
   RTAI-patched kernel][configurekernel] below.
   
2. If you did not start out with a kernel version matching the version
   of your RTAI-patched kernel, and you are going to change the kernel
   configuration, then you should run
   ```
   sudo ./makertaikernel.sh -c mod
   ```
   in order to deselect all unused kernel modules from compilation.
   This speeds up the following kernel builds dramatically! Reboot
   into the new kernel.


## Testing the RTAI-patched kernel

Testing your RTAI patched kernel is crucial for a good real-time performance!

The `makertaikernel.sh` script can also be used for testing with the
advantage that it writes the test results and the kernel configuration
into files. It is also possible to run whole test batches
automatically.

See
```
./makertaikernel.sh help test
```
for a summary of test options that are described in more detail in the following sections.

The script will first ask for a short description of your kernel
configuration and parameter. This string is then used for naming the
files for the test results.

First test whether the RTAI modules can be loaded:
```
sudo ./makertaikernel.sh test none
```
If you only want to check insmodding `rtai_hal` then call
```
sudo ./makertaikernel.sh test hal none
```
Equivalently, you can use the `sched` and `math` option.

If this fails:
- Make sure you have the `STACKPROTECTOR` set to "None" or "Regular" (see [Basic kernel configuration][basickernelconfiguration])
- Check the output of
  ```
  dmesg
  ```
  for some hints.

Once the RTAI modules load flawlessly you can proceed with running
the kernel tests from the RTAI test suite by calling
```
sudo ./makertaikernel.sh test
```
This runs the kernel latency, switch, and preempt tests.

Each of the tests need to be manually terminated by pressing `CTRL-C`.

All three tests are available for kernel, kernel threads, and user space.
They can be selected in the following way:
```
sudo ./makertaikernel.sh test kern     # runs the kern tests
sudo ./makertaikernel.sh test kthreads # runs the kernel threads tests
sudo ./makertaikernel.sh test user     # runs the user tests
sudo ./makertaikernel.sh test all      # runs all tests
```


### Test results

The result of the tests are written into files named
`latencies-HOST-RTAI-KERNEL-NNN-DATE-NAME-QUALITY` in the current
directory. HOST is replaced by the hostname of your machine, RTAI by
your choice of an RTAI source (the value of the RTAI_DIR variable,
e.g. magma, rtai-5.1, etc.), KERNEL is the kernel version
(the value of the LINUX_KERNEL variable), NNN is replaced by a
consecutive number, DATE is the current date, NAME and QUALITY are
strings describing your kernel configuration and the test
performance that is retrieved from the latency test.

View the test results with a text editor or with
```
less -S latencies-aeshna-rtai-5.1-4.4.115-004-2018-03-29-regularnohz-good
```

Along with the test results the configuration of the tested kenel is
saved in the `config-*` files of the same name. This file can later be used in a test
batch (see below) or to recreate this particular kernel configuration by means of
```
sudo ./makertaikernel.sh -c <config-file> reconfigure
```
(simply leave the kernel menu without changing anything).

The first few lines in a `latencies-*` file summarize the test
results. This summary is used for test reports 
(see below [Test reports][testreport]):
```
Test summary (in nanoseconds):

RTH| general                                           | kern latencies                           | kern switches      | kern preempt                   | kthreads latencies                       | kthreads switches  | kthreads preempt               | user latencies                           | user switches      | user preempt                   | kernel
RTH| description                             | progress|  ovlmax|  avgmax|     std|     n| maxover|  susp|   sem|   rpc|       max|   jitfast|   jitslow|  ovlmax|  avgmax|     std|     n| maxover|  susp|   sem|   rpc|       max|   jitfast|   jitslow|  ovlmax|  avgmax|     std|     n| maxover|  susp|   sem|   rpc|       max|   jitfast|   jitslow| configuration
RTD| smp4smtmulticore-idle-highres-plain     | hsmk    |   17156|    2838|     824|   599|       0|   217|   240|   284|      2482|      5852|      5491|       -|       -|       -|     -|       -|     -|     -|     -|         -|         -|         -|       -|       -|       -|     -|       -|     -|     -|     -|         -|         -|         -| config-4.4.115-rtai-5.1-aeshna-025-2018-04-17-smp4smtmulticore-idle-highres-plain-ok
```

This is followed by a summary of the load that was applied during the tests:
```
Load: 8.03 7.34 4.25
  cpu: stress -c 2
  io : stress --hdd-bytes 128M -d 2
  mem: stress -m 2
  net: ping -f localhost
```

Then the output of the RTAI tests is listed.

This is followed by a list of loaded modules
```
loaded modules (lsmod):
  Module                  Size  Used by
  btrfs                 819200  0 
  xor                    24576  1 btrfs
  raid6_pq              102400  1 btrfs
  ufs                    69632  0 
  ...
```

and the output of `/proc/interrupts`:
```
interrupts (/proc/interrupts):
             CPU0       CPU1       CPU2       CPU3       
    0:         26          0          0          0   IO-APIC   2-edge      timer
    1:         10          0          0          0   IO-APIC   1-edge      i8042
    8:          1          0          0          0   IO-APIC   8-edge      rtc0
    9:        169          0          0          0   IO-APIC   9-fasteoi   acpi
   12:       1949          0          0          0   IO-APIC  12-edge      i8042
   16:        254          0          0          0   IO-APIC  16-fasteoi   ehci_hcd:usb1, mmc0
   19:         13          0          0          0   IO-APIC  19-fasteoi 
   23:         34          0          0          0   IO-APIC  23-fasteoi   ehci_hcd:usb2
   24:          0          0          0          0   PCI-MSI 327680-edge      xhci_hcd
   25:          7          0        397          0   PCI-MSI 409600-edge      eth0
   26:      21558          0        919          0   PCI-MSI 512000-edge      0000:00:1f.2
   27:         74          0          0          0   PCI-MSI 32768-edge      i915
   28:         25          0          0          0   PCI-MSI 360448-edge      mei_me
   29:        371          0          0          0   PCI-MSI 442368-edge      snd_hda_intel
   30:      28553          0          0          0   PCI-MSI 1572864-edge      iwlwifi
  NMI:          0          0          0          0   Non-maskable interrupts
  LOC:     685217     666148     642070     652469   Local timer interrupts
  SPU:          0          0          0          0   Spurious interrupts
  ...
```
Ideally you do not want any interrupt on the CPU where the RTAI test
runs. When playing around with NO_HZ look at the `LOC` interrupts
(second last line in the snippet above).

Then various information about the system, the CPU, the grub menu, and
the settings used by `makertaikernel.sh` is printed.

Finally the output of `rtai_info` and `dmesg` during the tests is shown.


#### Test reports

You can generate a summary report from all your tested kernels by means of
```
./makertaikernel.sh report | less -S                    # report of all latencies-* files
./makertaikernel.sh report tests/latencies-* | less -S  # report of all latencies-* files in tests/
```

The python script `testreport.py` also summarizes test results. It is meant
as an improvement of the `makertaikernel.sh report` function, but it
is work in progress. Check
```
python testreport.py --help
```


### Interpreting test results

Read
`https://www.rtai.org/userfiles/documentation/documents/RTAI_User_Manual_34_03.pdf`,
for more information on the RTAI tests.

#### Latency tests

The first test that is run is the latency test.
The output looks like this:
```
RTAI Testsuite - KERNEL latency (all data in nanoseconds)
RTH|    lat min|    ovl min|    lat avg|    lat max|    ovl max|   overruns
RTD|         60|         60|        141|       1040|       1040|          0
RTD|         61|         60|        126|        372|       1040|          0
RTD|         66|         60|        127|        364|       1040|          0
RTD|         66|         60|        128|        748|       1040|          0
RTD|         92|         60|        129|        719|       1040|          0
```

- Overuns are bad - you want a configuration without overuns! 

  Note that the "overruns" column shows the total overruns counted from
  the start of the latency test. So if the overruns do not increase
  any more this might be tolerable.

- "lat max" minus "lat min" should definitely be smaller than your period
  (default of the latency test is 100 000 ns)

- As a rough rule of thumb, "lat max" minus "lat min"
  - less than 1000 ns is awesome
  - less than 5 000 ns is good
  - less than 10 000 ns is kind of ok
  - longer than 10 000 ns is bad
  on an idle machine (only running the latency test and nothing
  else). Under load (see below) these numbers will usually increase by
  several microsenconds (1000 ns).

In order to reduce latency jitter you need to improve your kernel
configuration (see [Improve the RTAI-patched kernel][configurekernel]).


#### Switch test

Then the switch test is run:

The output looks like this:
```
Apr  7 16:08:45 knifefish kernel: [  178.940333] 
Apr  7 16:08:45 knifefish kernel: [  178.940333] Wait for it ...
Apr  7 16:08:45 knifefish kernel: [  178.959986] 
Apr  7 16:08:45 knifefish kernel: [  178.959986] 
Apr  7 16:08:45 knifefish kernel: [  178.959986] FOR 10 TASKS: TIME 5 (ms), SUSP/RES SWITCHES 40000, SWITCH TIME (INCLUDING FULL FP SUPPORT) 145 (ns)
Apr  7 16:08:45 knifefish kernel: [  178.959988] 
Apr  7 16:08:45 knifefish kernel: [  178.959988] FOR 10 TASKS: TIME 6 (ms), SEM SIG/WAIT SWITCHES 40000, SWITCH TIME (INCLUDING FULL FP SUPPORT) 158 (ns)
Apr  7 16:08:45 knifefish kernel: [  178.959990] 
Apr  7 16:08:45 knifefish kernel: [  178.959990] FOR 10 TASKS: TIME 7 (ms), RPC/RCV-RET SWITCHES 40000, SWITCH TIME (INCLUDING FULL FP SUPPORT) 186 (ns)
```
The reported switching times should be well below 1000ns.


#### Preemption test

Finally the preempt test is run.


### Run tests under load

To really check out the performance of the kernel you should run the tests 
under heavy load. This can be easily controlled by adding one or several of the following keywords to the test options:
- `cpu`: run heavy computations on each core.
- `io` : do some heavy file reading and writing.
- `mem`: do some heavy memory access.
- `net`: produce network traffic.
- `full`: all of the above.
For example
```
./makertaikernel.sh test cpu net
```
will run the kern tests with cpu and network load.


### Run tests on a specific CPU core

In particular when checking the `isolcpu` kernel parameter you may
want to run the latency test on a specific CPU. You can specify the
CPU id on which you want to run the tests with `cpu=<id>`, where
`<id>` is the CPU id, first CPU is 0. For example:
```
./makertaikernel.sh test cpu=2
```
will run the kern tests on the third CPU.


### Automatized testing

For automatic termination of the tests (no `CTRL-C` required) provide the duration for the
latency test as a simple number (in seconds):
```
sudo ./makertaikernel.sh test 60       # run the kern latency test for 60 seconds
```

For preventing any user interaction you can also provide the test
description after the "auto" keyword (here "basic"):
```
sudo ./makertaikernel.sh test 60 auto basic
```


#### Test batches

For a completely automized series of tests of various kernel
parameters and kernel configurations under different loads you can
prepare a file with the necessary instructions (see below) and pass it
to the sript with the `batch` option:
```
sudo ./makertaikernel.sh test batch <test-batch-file>
```
This will successively reboot into the RTAI kernel with the kernel
parameter set to the ones specified by the KERNEL_PARAM variable and
as specified in <test-batch-file>, and runs the tests as specified by
the previous commands (without the "auto" command). 

For example,
```
sudo ./makertaikernel.sh test sched kern kthreads 240 batch <test-batch-file>
```
would test loading of the `rtai_hal` and `rtai_sched` modules,
run both the `kern` and `kthreads` tests, and abort the `latency`
tests after 240 seconds for each configuration specified in the file
<test-batch-file>.

Special lines in <test-batch-file> cause reboots into the default
kernel and building an RTAI-patched kernel with a new configuration.


#### Format of test-batch files
In a batch file
- everything behind a hash ('#') is a comment that is completely ignored
- empty lines are ignored
- a line of the format
  ```
  <descr> : <load/cpu> : <params>
  ```
  describes a configuration to be tested:
  - `<descr>` is a one-word string describing the kernel parameter 
     (a description of the load settings is added automatically to the description)
  - `<load/cpu>` defines the load processes to be started before testing (cpu io mem net full, see above) and/or the CPUs on which the test should be run (cpu=<CPUIDS>, see above)
  - `<param>` is a list of kernel parameter to be used.
  .
- a line of the format
  ```
  <descr> : CONFIG : <file>
  ```
  specifies a new kernel configuration stored in `<file>`,
  that is compiled after booting into the default kernel.
  `<descr>` describes the kernel configuration; it is used for naming successive tests.

  Actually, `<file>` can be everything the -c otion is accepting. This
  will mostly be actual kernel configuration files, for example from
  the `/boot/` directory, the `config-*` files saved along with the test results,
  or configuration files generated and saved by `makertaikernel.sh prepare`. In particular
  ```
  <descr> : CONFIG : backup
  ```
  compiles a kernel with the configuration of the kernel at the beginning of the tests.
  This is particularly usefull as the last line of a batch file.
- The first line  of the batch file can be just
  ```
  <descr> : CONFIG :
  ```
  this sets `<descr>` as the description of the already existing RTAI kernel for the following tests.

Example batch file:
```
  lowlatency : CONFIG :
  idlenohz : : idle=poll nohz=off
  nodyntics : CONFIG : config-nodyntics
  idleisol : cpu io : idle=poll isolcpus=0,1
  isol2 : io cpu=2 : isolcpus=2
```

Use 
```
./makertaikernel.sh prepare
```
to quickly generate various kernel configurations that you can use in a batch file.

**Note:** Running a test batch makes your computer practially unuseable, because it
will repeatedly reboot.

If you reboot or restart your computer during a running test batch
(because a test hangs), the test batch stops itself automatically.
If you want to abort a running test batch then log in and run
```
sudo killall makertaikernel.sh      # to kill the already scheduled reboot
makertaikernel.sh restore testbatch # to really stop the test batch
```


## Improve the RTAI-patched kernel

If your test results are not satisfactory, then you need to pass
kernel parameters to the RTAI kernel or reconfigure the kernel,
probably disabling some devices, compile and install the kernel again,
and compile and install rtai again. The main culprits are power saving
modes, frequency scaling, interrupts, some devices and their
drivers. Which ones are bad usually depends on your specific machine.

Read the file `/usr/local/src/rtai/README.CONF_RMRKS` for some hints.
The notes below cite the `README.CONF_RMRKS` of RTAI-5.1.


### How to modify your system

There are four levels, at which you can modify your system:
1. The running kernel, e.g. by using the `/sys` interface of the kernel.
2. On boot by passing parameter to the kernel via the boot loader.
3. When compiling the kernel by setting a new kernel configuration.
4. In the BIOS.

BIOS settings will affect all the kernels you run on your computer.
Better is if you can achieve the same effect via a kernel
configuration that will be specific for your kernel. But for this you
need to compile a new kernel. Even better is if there is a kernel
parameter that allows you to set the configuration at boot time. This
only requires a reboot. Use these three options to find a
configuration with the lowest latency jitters.  

Some configurations can be achieved even in the running kernel. For
conveniently using them one should write a little wrapper around the
real time application (e.g. RELACS) the sets these parameters only
when running the application, maybe even specific for the CPU on which
the real-time task runs.

Simply check your BIOS whether there is anything of interest
(e.g. hyperthreading, powersaving, force all fans to run at full
speed) that you might want to try.


#### Modify the kernel configuration

The kernel configuration is changed in the menu that you get when
building a new kernel. That is when running
```
sudo ./makertaikernel.sh reconfigure
```
or
```
sudo ./makertaikernel.sh prepare
```
for generating kernel configurations to be used in a test batch.

If you do not want to override your RTAI-patched kernel when
reconfiguring you can give it a new name via the `-n` switch. You also
need to supply this setting to the `reboot` and `test` action:
```
sudo ./makertaikernel.sh -n 2 reconfigure
sudo ./makertaikernel.sh -n 2 reboot
...
sudo ./makertaikernel.sh -n 2 test
```
Note that `makertaikernel.sh reconfigure` will first uninstall an
already existing kernel with the same name.

You can recreate a kernel or use this kernel's configuration for
further modifications by specifying the kernel configuration file
saved by `makertaikernel.sh test` using the `-c` option
```
sudo ./makertaikernel.sh -c config-3.14.17-rtai-4.1-002-basic-good reconfigure
```

The `KERNEL_MENU` variable in the `makertaikernel.cfg` configuration
file lets you choose which menu type you get.


#### Set kernel parameter

Kernel parameter can be passed directly to the reboot command:
```
./makertaikernel.sh reboot param1=xxx param2=yyy
```
boots the RTAI-patched kernel and passes the kernel parameter "param1=xxx param2=yyy" to it.
See
```
./makertaikernel.sh help reboot
```
for further options and details.

Kernel parameter that you want to set all the time while testing can
be specified via the `KERNEL_PARAM` variable in the
`makertaikernel.cfg` configuration file. Also describe these parameter
in the `KERNEL_PARAM_DESCR` variable by a single word, so that the
test results can be appropriately named.

For applying the kernel parameter permanently add them to the
`GRUB_CMDLINE_RTAI` variable in `/etc/defaults/grub` and run
`update-grub`.

There are several interesting kernel parameter that influence the
real-time performance.  See the file
`Documentation/kernel-parameters.txt` in your linux kernel source tree
(usually in `/usr/src`) for a documentation of all available kernel parameter.

The following is a collection of hints on influential configuration
parameter from all levels.


### Disable CPU power saving modes

Most importantly, for CPUs like Intel i3/i5/i7 CPUs,
disabling CPU power saving modes improves real-time performance
dramatically. Before you try anything else do:
- Add the kernel parameter `idle=poll` to disable C-state transitions completely.
  This is usually sufficient for a godd RTAI performance.
.


### Hyperthreading

`README.CONF_RMRKS` says: 
- Under SMP set the number of CPUs equal to the real
  ones and have it matched in RTAI, no hyperthreading intended.
- Even if RTAI can work with hyperthreading enabled, such an option is deprecated
  as a possible cause of latency; in any case try and verify if it is acceptable,
  with your hardware and for your applications.

So, check whether you have hyperthreading. Run
```
./makertaikernel.sh info cpus
```
The top of the output looks like this (Intel i7-4770):
```
CPU topology, frequencies, and idle states (/sys/devices/system/cpu/*):
cpu topology                   cpu frequency scaling
logical  socket  core  online  freq/MHz      governor
  cpu0        0     0       1     0.800      ondemand
  cpu1        0     1       1     0.800      ondemand
  cpu2        0     2       1     0.800      ondemand
  cpu3        0     3       1     0.800      ondemand
  cpu4        0     0       1     0.800      ondemand
  cpu5        0     1       1     1.000      ondemand
  cpu6        0     2       1     1.200      ondemand
  cpu7        0     3       1     1.400      ondemand
```
If in the "core_id" column the numbers appear twice or more
often, then you run in hyperthreading mode (as is the case in the example).

By reducing the number of CPUs to four, you can eliminate
hyperthreading (see below).

If the topology looks like this (Intel i7-3520M):
```
CPU topology, frequencies, and idle states (/sys/devices/system/cpu/*):
cpu topology                   cpu frequency scaling
logical  socket  core  online  freq/MHz      governor
  cpu0        0     0       1     2.700      ondemand
  cpu1        0     0       1     2.901      ondemand
  cpu2        0     1       1     2.901      ondemand
  cpu3        0     1       1     2.901      ondemand
```
the trick to simply reduce the number of cpus to the number of actual
cores does not work. You need to switch off hyperthreading in the BIOS.

This is an example of a machine without hyperthreading (Intel i5-3570):
```
CPU topology, frequencies, and idle states (/sys/devices/system/cpu/*):
cpu topology                   cpu frequency scaling
logical  socket  core  online  freq/MHz      governor
  cpu0        0     0       1     3.400     powersave
  cpu1        0     1       1     3.144     powersave
  cpu2        0     2       1     2.863     powersave
  cpu3        0     3       1     3.260     powersave
```
In this case you do not need to do anything.

This is what you need to do when configuring the kernel:
- In "Processor type and features": 
  - In case you have a uniprocessor system, deselect "Symmetric
    multi-processing support" (`SMP`)
  - Set the "Maximum numbers of CPUs" (`NR_CPUS`) to the number of
    physical cores you have in your machine. The `makertaiscript.sh
   ` automatically sets the same number of CPUs for the RTAI configuration.  

You can also do this via the kernel parameter:
- `nr_cpus=<n>` Maximum number of processors that an SMP kernel could
  support. n >= 1 limits the kernel to supporting 'n'
  processors. Later in runtime you can not use hotplug cpu feature to
  put more cpu back to online.  Just like you compile the kernel
  NR_CPUS=n.

Switch off individual CPUs:
```
echo 0 > /sys/devices/system/cpu/cpuX/online
```
This, however, crashes when inserting rtai_hal (even if
CONFIG_RTAI_CPUS is adapted to the lower CPU count).

For more information see:
- https://serverfault.com/questions/235825/disable-hyperthreading-from-within-linux-no-access-to-bios?utm_medium=organic&utm_source=google_rich_qa&utm_campaign=google_rich_qa
- https://unix.stackexchange.com/questions/33450/checking-if-hyperthreading-is-enabled-or-not

The related kernel configs in the "Processor type and features" submenu
- "SMT (Hyperthreading) scheduler support"
- "Multi-core scheduler support"

do not seem to matter.


### Cached memory disruption 

`README.CONF_RMRKS` says: 
- Cached memory disruption can add significant
  latencies, till the cache becomes hot again, experienced first hand
  after a far jump in the code and data in a digital controller.
.
???


### CPU power management and frequency scaling

`README.CONF_RMRKS` says:
- Power management, see CONFIG_CPU_FREQ and CONFIG_CPU_IDLE below; on portables 
  battery management too.
- Recent Intel SpeedStepping and Boosting.
- Disable CPU_FREQ.
- Disable CPU_IDLE and INTEL_IDLE, or boot with "intel_idle.max_cstate=0". If you
  want to be sure to have a never sleeping CPU execute, at the lowest priority, 
  your own, per cpu, idle task, i.e. one just doing "while(1);".
- Disable APM and CONFIG_ACPI_PROCESSOR, but not everything related to power management.
  Take also into account that without ACPI enabled you might not see more than 
  a single CPU.
.

See
```
./makertaikernel.sh info cpu
```
for information on frequency scaling and idle states of your CPUs.

The output might look like this:
```
CPU topology, frequencies, and idle states (/sys/devices/system/cpu/*):
CPU topology                   CPU frequency scaling                CPU idle states (enabled fraction%)
logical  socket  core  online  freq/MHz      governor  transitions  POLL     C1-IVB   C1E-IVB  C3-IVB   C6-IVB   C7-IVB 
  cpu0        0     0       1     2.901      ondemand       278047  0  0.0%  0  3.5%  0  6.9%  0  5.8%  0  0.0%  0 83.6%
  cpu1        0     0       1     1.800      ondemand       303763  0  0.0%  0  6.1%  0  7.2%  0  3.6%  0  0.0%  0 82.9%
  cpu2        0     1       1     1.200      ondemand       251421  0  0.0%  0  3.5%  0  6.6%  0  4.3%  0  0.0%  0 85.4%
  cpu3        0     1       1     1.800      ondemand       297520  0  0.0%  0  6.1%  0  7.1%  0  3.6%  0  0.0%  0 83.1%

...

CPU (/proc/cpuinfo):
  model name        :  Intel(R) Core(TM) i7-3520M CPU @ 2.90GHz
  number of CPUs    : 4
  max CPU frequency : 2.901 MHz
  CPU family        : 6
  machine (uname -m): x86_64
  memory (free -h)  : 7.5G RAM
```
Here, CPU frequency scaling is active ("ondemand" governor and different frequencies in the 5-th column, that are below the maximum possible CPU frequency at "max CPU frequency" below).
Also, CPU powersaving is enabled because there are "CPU idle states" available ("POLL", "C1-IVB", etc.).

#### Disable powermanagement and frequency scaling completely
You are on the safe side when you configure the ACPI properties of your kernel as follows
(as you did according to [Basic kernel configuration][basickernelconfiguration]):

In "Power management and ACPI options":
- In "ACPI (Advanced Configuration and Power Interface) Support":
  - Disable "Processor" (`ACPI_PROCESSOR`)
- Disable "CPU Frequency scaling" (`CPU_FREQ`)
- In "CPU Idle":
  - Disable "CPU idle PM support" (`CPU_IDLE`)

#### Disable power management only
Instead you can try to only disable
in "Power management and ACPI options":
- Disable "CPU Frequency scaling" (`CPU_FREQ`)

In addition, make sure your CPU stays in C0 idle state by passing
`idle=poll` to the kernel parameter to keep the CPUs in C0 state via
an polling idle loop, or write a zero to the `/dev/cpu_dma_latency`
file (the DynamicClampAnalogInput plugin of RELACS can do that). This
also keeps the CPU frequency at its maximum but makes the system run
hot.

#### Further aspects of power saving options
Also check the BIOS for disabling CPU power management.

All the other kernel parameter that control CPU idle states are usually not sufficient:
- `idle=halt` idle cpus enter at maximum the C1 state, higher C-states are disabled. CPU frequency stays close at maximum.
- `intel_idle.max_cstate=1` this leaves us with TWO C-states (POLL and C1)!
- `intel_idle.max_cstate=0` this disables the intel_idle driver and switches to acpi_idle with several C-states
- `processor.max_cstate=1` on its own has no effect when the intel_idle driver is active
- `intel_idle.max_cstate=0 processor.max_cstate=0` sames as `processor.max_cstate=1`
- `intel_idle.max_cstate=0 processor.max_cstate=1` disables C-states higher than C1 like `idle=halt` but cpu frequency might go lower.
- `intel_idle.max_cstate=0 processor.max_cstate=2` this leaves you with three C-states (POLL, C1, C2)
- `intel_pstate=disable` seems to disable frequency scaling ???

C-states can be nicely monitored with the `i7z` or `powertop` programs
(as root). They also show CPU core temperature (they should be well
below 100 degrees celsius). For these programs to work, make sure that
you have the following options enabled in the kernel configuration:

In "Processor type and features":
- Enable "/dev/cpu/ * /msr - Model-specific register support"
- Enable "/dev/cpu/ * /cpuid - CPU information support"

Check frequency scaling of CPUs with `cpufreq-info` from the `cpufrequtils` package.

With
```
./makertaikernel.sh test batch cstates
```
you can generate a test-batch file to check these kernel parameter.

For more information on CPU power management and frequency scaling read in the `Documentation/` folder in the kernel source
- `cpuidle/sysfs.txt`
- `cpu-freq/cpufreq-stats.txt`
- `cpu-freq/boost.txt`
- `cpu-freq/user-guide.txt`
- `cpu-freq/governors.txt`
- `cpu-freq/intel-pstate.txt`
- `power/pm_qos_interface.txt`

More infos:
- The C-states can also be dynamically controlled by writing the
  maximum allowable latency in microseconds (as an 32-bit(?) `int`, not as
  text) to the file `/dev/cpu_dma_latency` . Writing a zero keeps the
  system in `cstate=0`.
- Check out
  https://gitlab.eurecom.fr/oai/openairinterface5g/wikis/OpenAirKernelMainSetup
  for more hints on disabling power-management and frequency scaling
  stuff.
- turning off frequency scaling on a specific CPU: https://wiki.archlinux.org/index.php/CPU_frequency_scaling
- Control C-states also on individual CPUs: https://wiki.linuxfoundation.org/realtime/documentation/howto/applications/cpuidle
- http://stackoverflow.com/questions/12111954/context-switches-much-slower-in-new-linux-kernels


### Select processor family

`README.CONF_RMRKS` says: 
- If unsure on the CPU to choose, care of setting one
  featuring the Time Stamp Clock (TSC), which means no 486 and "false"
  i586, since generic INTEL i586 compatibles often do not have a TSC,
  while true INTEL ones do have it.

Check your processor by running
```
./makertaikernel.sh info cpus
```
The last part looks like this:
```
CPU (/proc/cpuinfo):
  model name    : Intel(R) Core(TM) i7-3520M CPU @ 2.90GHz
  number of cpus: 4
  cpu family: 6
  cpuidle driver: intel_idle
  machine (uname -m): x86_64
  memory (free -h)  : 7.5G RAM
```

Select your processor in the kernel configuration:
- "Processor type and features":
  - "Processor family"
In the kernel menu check "help" to find out, which processor family you have to select.
Processors with "cpu family : 6" are "Core 2/newer Xeon".


### Low-latency kernel configuration

So-called low-latency kernels have the following two settings:

- "Processor type and features":
  - Select "Preemption Model (Preemptible kernel (Low-Latency Desktop))" (`PREEMPT`)
  - Set "Timer frequency" to 1000Hz (`CONFIG_HZ_1000=y` and `CONFIG_HZ=1000`)
This has, however, no effect on the RTAI performance! The two
parameter control how responsive Linux processes are, but not how
quickly RTAI can intersept the Linux kernel.


### Disable device drivers you do not need
A good strategy is to disable as many as possible device drivers.
See
```
lsmod
```
for listing all the currently loaded kernel modules. Or
```
lsmod -k
```
for a list of PCI devices on your system and their associated kernel modules.

When configuring the kernel you can hit '/', enter a search term (the
module name) and you get a list of matching configuration parameters.

More information on how select/deselect device drivers for RTAI kernel can be found at
`https://github.com/ShabbyX/RTAI/blob/master/README.INSTALL`.

Devices to consider are:
- Disable DRM:
  - Device Drivers:
    - Graphics support:
      - Disable "Direct Rendering Manager"

- Check video cards and graphic acceleration
  
  `README.CONF_RMRKS` says: 
  - Some peripherals, e.g. video cards, may stall CPUs attempting to
    access IO space.  Verify "what ifs" related to graphic
    acceleration, likely better if disabled.  Consider also if X term
    usage is really needed. If possible avoid it, especially in
    production work.
  - Any initialization of the device drivers, or anything related to
    the hardware, may lead to high latencies, e.g., but not
    always. doing "startx &" while a real time application is
    running. Once it is started there should be no major problems.  If
    the truoble persists and you really need X, concurrently with your
    RTAI tasks, try disabling hardware graphic acceleration. The best
    latencies usually come with no graphic application running.

- Disable 'Error Detection and Correction (EDAC) units' (https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/7/html-single/tuning_guide/index):
  - Device Drivers:
    - Disable "EDAC (Error Detection And Correction) reporting"

- Disabling the thermal sysfs driver is sometimes great for latencies
  but has no effect on periodic tasks ? ...:
  - Device Drivers:
    - Graphics support:
      - Disable "Backlight & LCD device support"
    - Disable "Generic Thermal sysfs driver"
  
- Device Drivers:
  - Keep "Real Time Clock"
  - "Generic Dynamic Voltage and Frequency Scaling (DVFS) support" does not matter
  - sound might be ok

- You probably do not need bluetooth or WLAN! (but as long as you do
  not use it it might not hurt...):
  - Device Drivers:
    - Network device support:
      - Disable "Wireless LAN"
  - Networking support:
    - Disable "Bluetooth subsystem support"
    - Disable "Wireless"

- USB: 
  - According to `README.CONF_RMRKS` from rtai-5.0.1:
    "Do not disable USB, but just any legacy support, possibly in the
    BIOS also. Once upon a time old USB was a source of high RTAI
    latencies. Now that should be legacy support."
  - If you get the error "usb: device not accepting address" add 
    `noapic` to the kernel parameter.

### Some more hints for kernel configuration parameters
Here is a list of some kernel configuration parameter that you might try to improve your
real-time perfomance (low latencies):

- In "Device drivers" keep "Multiple devices driver support (RAID and LVM)" 
  and in there keep "Device mapper support" (somehow needed for grub).

- In "Processor type and features": disabling the following seems to have an effect: 
  - Disable "Supervisor Mode Access Prevention"
  - Disable "EFI runtime service support"
  - Disable "Enable seccomp to safely compute untrusted bytecode"

- NUMA (disabling seems to improve maximum latencies):
  - General setup:
    - Disabel "Memory placement aware NUMA scheduler"
  - Processor type and features: 
    - Disable "Numa Memory Allocation and Scheduler Support"

- HPET Timer (disabling it improves preempt jitter):
  - Device Drivers:
    - Character devices:
      - Disable "HPET - High Precision Event Timer"

- Disable IOMMU (no effect?):
  - Processor type and features: 
    - Disable "Old AMD GART IOMMU support"
    - Disable "IBM Calgary IOMMU support"
  - Device Drivers:
    - Disable IOMMU Hardware Support

- Maybe also try:
  - CONFIG_RCU_BOOST and CONFIG_RCU_KTHREAD_PRIO


### Kernel parameter

Here is a list of potentially influential kernel parameter:

Clocks and timers:
- `nohz=off`
- `tsc=reliable`
- `highres=off`
- `hpet=disable`
- For scheduling interrupts read `Documentation/timers/NO_HZ.txt`
- Also check out "nohalt" kernel parameter.
You get these kernel parameters for a test batch file by running
```
./makertaikernel.sh test batch clocks
```

Advanced configuration and power interface (ACPI):
- acpi=off    # often very effective, but weired system behavior
- acpi=noirq
- pci=noacpi
- pci=nomsi
With disabled acpi your rtai-patched linux kernel might not properly
halt or reboot. Try `reboot=triple` as a kernel parameter.  See
`/usr/src/linux/Documentation/x86/x86_64/boot-options.txt` for more
options for the reboot parameter.

You get these kernel parameters for a test batch file by running
```
./makertaikernel.sh test batch acpi
```

Advanced programmable interrupt controller (APIC):
- `noapic`
- `nolapic` , usually not a good idea, becaus RTAI uses the lapic timer. 
- `lapic`

You get these kernel parameters for a test batch file by running
```
./makertaikernel.sh test batch apic
```

Others:
- disable all DMA transfers by setting kernel parameter `libata.dma=0`.
- What about `ide-core.nodma` parameter (it's ide not sata!)?
- What about ltpc=irq ?
- `README.CONF_RMRKS`: LINUX use of DMA can add latency, especially when
  it is supported in burst mode.

After restart, check for the number of CPUs - they might be reduced
if you disabled too much ACPI:
```
./makertaikernel.sh info cpu
```


### Isolate CPUs for real time tasks 
For further improving the RTAI performance, you might want to reserve
at least one CPU for RTAI on a multi-core machine. You can isolate
CPUs by using the kernel parameter
```
isolcpus=2,3
```
(for isolating the cores no. 2 and 3). Additional parameters are
```
isolcpus=2,3 nohz_full=2,3 rcu_nocbs=2,3
```

See the file `/usr/local/src/rtai/README.ISOLCPUS` for more details.

You should check each of your CPUs. In particular running and
isolating an RTAI task on the first CPU may result in worse
perfromance than on the other CPUs.

In addition to isolating a CPU you also need to make sure that the
RTAI tests are run on that CPU. For this you need to modify the test
sources. With the script this can be easily achieved by passing the
`cpu=<CPUID>` option:
```
sudo ./makertaikernel.sh test cpu=2
```
will run the tests on CPU 2 (the third CPU).

Running RTAI on isolated CPUs may reduce maximum jitter on an idle
machine. Under load, isolation can improve mean and maximum latencies
considerably.

You get these kernel parameters for a test batch file by running
```
./makertaikernel.sh test batch isolcpus
```
It will test RTAI performance for each of your CPUs.
Edit the file to adapt it to the number of CPUs you have on your machine.

**Note:** You cannot isolate the CPU on which the system boots (usually cpu 0).


### Disable SMI interrupts
Finally, there are the evil SMIs. They periodically produce some long latencies. See
`/usr/local/src/rtai/base/arch/x86/calibration/README.SMI` and `README.SMISPV` for details.


### Reduce OS jitter

Linux Torvalds himself has an interesting page on how to reduce OS jitter:
https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/kernel-per-CPU-kthreads.txt?h=v4.14-rc2

I have not yet tried these suggestions. Most of them are probably
dealt with by CPU isolation. Some suggestions, however, sound
interesting:
- kworker 3.a. `CONFIG_SLUB=y` rather than `CONFIG_SLAB=y`
- kworker 3.e. boot with `elevator=noop`
- rcuc 2. `CONFIG_RCU_BOOST=n`
- rcuc 3. `CONFIG_RCU_NOCB_CPU=y` with `rcu_nocbs=` boot parameter
- watchdog 1. `CONFIG_LOCKUP_DETECTOR=n`
- watchdog 2. boot with `nosoftlockup=0`
- watchdog 3. echo a zero to /proc/sys/kernel/watchdog


## Test results

In the subfolders you can store test results files generated by
`makertaikernel.sh` (the `latencies-*` files along with the
corresponding kernel configurations `config-*`). That way we can get
an overview on what is possible with RTAI and which hardware has been
used.

See the `latencies-*` files for complete test results, kernel
parameter, CPU and hardware properties, kernel messages, etc.  The
kernel configurations are stored in the corresponding `config-*`
files.

### 1. abbott rtai-5.1 4.4.115

kern/latency test for 2000seconds, all numbers in nanoseconds:

| isolcpus | load | mean jitter | stdev   | max     |
|----------|------|------------:|--------:|--------:|
|  -       | -    |         797 |     396 |   10808 |
|  -       | full |        2471 |     811 |   23088 |
|  1       | -    |         231 |     122 |    1713 |
|  1       | full |        1397 |     145 |    2831 |


### 2. mule rtai-5.1 4.4.115

kern/latency test for 2000seconds, all numbers in nanoseconds:

| isolcpus | load | mean jitter | stdev   | max     |
|----------|------|------------:|--------:|--------:|
|  -       | -    |         537 |     239 |    4322 |
|  -       | full |        5539 |     737 |   10272 |
|  1       | -    |         252 |     196 |    4476 |
|  1       | full |        5567 |     426 |    7839 |


[quickinstall]: #install-an-rtai-patched-linux-kernel-rtai-and-comedi
[basickernelconfiguration]: #basic-kernel-configuration
[testrtai]: #testing-the-rtai-patched-kernel
[testreport]: #test-reports
[configurekernel]: #improve-the-rtai-patched-kernel
[testresults]: #test-results
