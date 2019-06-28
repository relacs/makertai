#!/bin/bash

###########################################################################
# you should modify the following parameter according to your needs:

: ${KERNEL_PATH:=/usr/src}       # where to put and compile the kernel (set with -s)
: ${LINUX_KERNEL:="4.4.115"}     # linux vanilla kernel version (set with -k)
: ${KERNEL_SOURCE_NAME:="rtai"}  # name for kernel source directory to be appended to LINUX_KERNEL
: ${KERNEL_NUM:="-1"}            # name of the linux kernel is $LINUX_KERNEL-$RTAI_DIR$KERNEL_NUM
                                 # (set with -n)

: ${LOCAL_SRC_PATH:=/usr/local/src} # directory for downloading and building 
                              # rtai, newlib and comedi

: ${RTAI_DIR="rtai-5.1"}      # name of the rtai source directory (set with -r):
                              # official relases for download (www.rtai.org):
                              # - rtai-4.1: rtai release version 4.1
                              # - rtai-5.1: rtai release version 5.1
                              # - rtai-x.x: rtai release version x.x
                              # from cvs (http://cvs.gna.org/cvsweb/?cvsroot=rtai):
                              # - magma: current development version
                              # - vulcano: stable development version
                              # Shahbaz Youssefi's RTAI clone on github:
                              # - RTAI: clone https://github.com/ShabbyX/RTAI.git
: ${RTAI_PATCH:="hal-linux-4.4.115-x86-10.patch"} # rtai patch to be used (set with -p)
                              # can be "none" if no patch should be applied

: ${KERNEL_CONFIG:="old"}  # whether and how to initialize the kernel configuration 
                           # (set with -c) 
                           # - "old" for oldconfig from the running kernel,
                           # - "def" for the defconfig target,
                           # - "mod" for the localmodconfig target, (even if kernel do not match)
                           # - "backup" for the backed up kernel configuration from the last test batch.
                           # - a kernel config file.
                           # afterwards, the localmodconfig target is executed, 
                           # if the running kernel matches LINUX_KERNEL.
: ${RUN_LOCALMOD:=true}    # run make localmodconf after selecting a kernel configuration (disable with -l)
: ${KERNEL_MENU:="menuconfig"} # the menu for editing the kernel configuration
                               # (menuconfig, gconfig, xconfig)

: ${KERNEL_PARAM:="idle=poll"}      # kernel parameter to be passed to grub
: ${KERNEL_PARAM_DESCR:="poll"}     # one-word description of KERNEL_PARAM 
                                    # used for naming test resutls
: ${BATCH_KERNEL_PARAM:="oops=panic nmi_watchdog=panic softlockup_panic=1 unknown_nmi_panic panic=-1"} # additional kernel parameter passed to grub for test batch - we want to reboot in any case!
: ${KERNEL_CONFIG_BACKUP:="config-backup"}     # stores initial kernel configuration for test batches

: ${NEWLIB_TAR:=newlib-3.1.0.tar.gz}  # tar file of current newlib version 
                                      # at ftp://sourceware.org/pub/newlib/index.html
                                      # in case git does not work
: ${MUSL_TAR:=musl-1.1.22.tar.gz}  # tar file of current musl version 
                                   # at https://git.musl-libc.org/cgit/musl
                                   # in case git does not work

: ${MAKE_NEWLIB:=true}        # for automatic targets make newlib library
: ${MAKE_MUSL:=false}         # for automatic targets make musl library
: ${MAKE_RTAI:=true}          # for automatic targets make rtai library
: ${MAKE_COMEDI:=true}        # for automatic targets make comedi library

: ${RTAI_HAL_PARAM:=""}       # parameter for the rtai_hal module used for testing
: ${RTAI_SCHED_PARAM:=""}     # parameter for the rtai_sched module used for testing
: ${TEST_TIME_DEFAULT:="600"} # default time in seconds used for latency test
: ${STARTUP_TIME:=300}        # time to wait after boot to run a batch test in seconds
: ${COMPILE_TIME:=800}        # time needed for building a kernel with reconfigure
                              # (this is only used for estimating the duration of a test batch)

: ${SHOWROOM_DIR:=showroom}   # target directory for rtai-showrom in ${LOCAL_SRC_PATH}

# columns to be hidden in the test results table:
HIDE_COLUMNS=(
tests:test_details
tests:link
)


###########################################################################
# some global variables:

FULL_COMMAND_LINE="$@"

MAKE_RTAI_KERNEL="${0##*/}"
MAKE_RTAI_CONFIG="${MAKE_RTAI_KERNEL%.*}.cfg"
LOG_FILE="${PWD}/${MAKE_RTAI_KERNEL%.*}.log"

VERSION_STRING="${MAKE_RTAI_KERNEL} version 4.2 by Jan Benda, June 2019"
DRYRUN=false                 # only show what is being done (set with -d)
RECONFIGURE_KERNEL=false
NEW_KERNEL_CONFIG=false
DEFAULT_RTAI_DIR="$RTAI_DIR"
RTAI_DIR_CHANGED=false
RTAI_PATCH_CHANGED=false
LINUX_KERNEL_CHANGED=false
RTAI_MENU=false              # enter RTAI configuration menu (set with -m)

NEW_KERNEL=false
NEW_RTAI=false
NEW_NEWLIB=false
NEW_MUSL=false
NEW_COMEDI=false

CURRENT_KERNEL=$(uname -r)

MACHINE=$(uname -m)
RTAI_MACHINE=$MACHINE
if test "x$RTAI_MACHINE" = "xx86_64"; then
    RTAI_MACHINE="x86"
elif test "x$RTAI_MACHINE" = "xi686"; then
    RTAI_MACHINE="x86"
fi

CPU_NUM=$(grep -c "^processor" /proc/cpuinfo)

KERNEL_NAME=${LINUX_KERNEL}-${RTAI_DIR}${KERNEL_NUM}
KERNEL_ALT_NAME=${LINUX_KERNEL}.0-${RTAI_DIR}${KERNEL_NUM}
REALTIME_DIR="/usr/realtime"   
# this will be reset after reading in command line parameter!


###########################################################################
# general functions:

function set_variables {
    test -n "$KERNEL_NUM" && test "x${KERNEL_NUM:0:1}" != "x-" && KERNEL_NUM="-$KERNEL_NUM"
    KERNEL_NAME=${LINUX_KERNEL}-${RTAI_DIR}${KERNEL_NUM}
    KERNEL_ALT_NAME=${LINUX_KERNEL}.0-${RTAI_DIR}${KERNEL_NUM}
    REALTIME_DIR="/usr/realtime/${KERNEL_NAME}"
}

function echo_log {
    echo "$(date +%T) $@" >> "$LOG_FILE"
    echo "$@"
}

function echo_kmsg {
    # this is for dmesg:
    echo "#### MAKERTAIKERNEL.SH: $@" > /dev/kmsg
    # this goes into the logger files: 
    # (on some systems kmsg does not end up in logger files)
    logger -p user.info "#### MAKERTAIKERNEL.SH: $@"
}

function indent {
    awk '{print "  " $0}'
}

function print_version {
    echo $VERSION_STRING
}

function help_kernel_options {
    cat <<EOF
-d    : dry run - only print out what the script would do, but do not execute any command
-k xxx: use linux kernel version xxx (LINUX_KERNEL=${LINUX_KERNEL})
-r xxx: the rtai source (RTAI_DIR=${RTAI_DIR}), one of
        magma: current rtai development version from csv
        vulcano: stable rtai development version from csv
        rtai-5.1: rtai release version 5.1 from www.rtai.org
        rtai-4.1: rtai release version 4.1 from www.rtai.org, or any other
        rtai-x.x: rtai release version x.x from www.rtai.org
        RTAI: snapshot from Shahbaz Youssefi's RTAI clone on github
-n xxx: append xxx to the name of the linux kernel (KERNEL_NUM=${KERNEL_NUM})
EOF
}

function help_info {
    cat <<EOF
$VERSION_STRING

Print some information about your system.

Usage:

sudo ${MAKE_RTAI_KERNEL} info [rtai|kernel|cpu|interrupts|grub|settings|setup|log|configs [<FILE>]]
sudo ${MAKE_RTAI_KERNEL} [-c xxx] info menu

info                 : display properties of rtai patches, loaded kernel modules, kernel, machine,
                       and grub menu (configs and menu targets are excluded)
info rtai            : list all available patches and suggest the one fitting to the kernel
info kernel          : show name and kernel parameter of the currently running kernel
info cpu             : show properties of your CPUs.
                       Information about C-states is not always available - better check the i7z programm.
info interrupts      : show /proc/interrupts
info menu            : show kernel configuration menu of the specified (-c) kernel configuration
info grub            : show grub boot menu entries
info settings        : show all configuration variables and their values
info setup           : show modifications of your system made by ${MAKE_RTAI_KERNEL} (run as root)
info log             : show content of log file - useful after test batch
info configs         : show available kernel configurations in all config-* files
info configs <FILES> : show kernel configurations contained in <FILES>
info configs > <FILE>: save kernel configurations contained in <FILES>
                       to file <FILE> usable as a test batch file.

-c xxx: specify a kernel configuration xxx:
        - old: use the kernel configuration of the currently running kernel
        - def: generate a kernel configuration using make defconfig
        - mod: simplify existing kernel configuration using make localmodconfig
               even if kernel do not match
        - backup: use the backed up kernel configuration from the last test batch.
        - <config-file>: provide a particular configuration file.
        After setting the configuration (except for mod), make localmodconfig
        is executed to deselect compilation of unused modules, but only if the
        runnig kernel matches the selected kernel version (major.minor only).

EOF
}

function help_setup {
    cat <<EOF
$VERSION_STRING

Setup and restore syslog daemon, grub menu, and kernel parameter.

Usage:

sudo ${MAKE_RTAI_KERNEL} setup [messages|grub|comedi|kernel|rtai <cpus>]

sudo ${MAKE_RTAI_KERNEL} restore [messages|grub|comedi|kernel|rtai|testbatch]

setup            : setup messages, grub, comedi, and kernel
setup messages   : enable /var/log/messages needed for RTAI tests in rsyslog settings
setup grub       : configure the grub boot menu (not hidden, no submenus, 
                   extra RTAI kernel parameter, user can reboot and set rtai kernel parameter)
setup comedi     : create "iocard" group and assign comedi devices to this group
setup kernel     : set kernel parameter for the grub boot menu to "$KERNEL_PARAM"
setup rtai <cpus>: rebuild and install rtai testsuite to run the tests on the specified cpus
                   (comma-separated list of cpu ids)

restore          : restore the original system settings (messages, grub, comedi, kernel, and testbatch)
restore messages : restore the original rsyslog settings
restore grub     : restore the original grub boot menu settings and user access
restore comedi   : do not assign comedi devices to the iocard group
restore kernel   : restore default kernel parameter for the grub boot menu
restore rtai     : restore, build, and install the original RTAI testsuite files
restore testbatch: uninstall the automatic test script from crontab and
                   remove variables from the grub environment (see help test)

EOF
}

function help_reboot {
    cat <<EOF
$VERSION_STRING

Reboot and set kernel parameter.

Usage:

${MAKE_RTAI_KERNEL} [-d] [-n xxx] [-r xxx] [-k xxx] reboot [keep|none|<XXX>|<FILE>|<N>|default]

EOF
    help_kernel_options
    cat <<EOF

reboot        : reboot into the rtai kernel ${MAKE_RTAI_KERNEL} is configured for
                with kernel parameter as specified by KERNEL_PARAM
                (currently set to "$KERNEL_PARAM")
reboot XXX    : reboot into rtai kernel ${MAKE_RTAI_KERNEL} is configured for
                with XXX passed on as kernel parameter
reboot FILE   : reboot into rtai kernel ${MAKE_RTAI_KERNEL} is configured for
                with kernel parameter taken from test results file FILE
reboot keep   : reboot into rtai kernel ${MAKE_RTAI_KERNEL} is configured for
                and keep previously set kernel parameter
reboot none   : reboot into rtai kernel ${MAKE_RTAI_KERNEL} is configured for
                without any additional kernel parameter
reboot N      : reboot into a kernel as specified by grub menu entry index N
                without additional kernel parameter,
                see "${MAKE_RTAI_KERNEL} info grub" for the grub menu.
reboot default: reboot into the default kernel of the grub menu.

Rebooting as a regular user (without sudo) has the advantage to store
the session of your window manager. With the grub environment available
(/boot/grub/grubenv) this should be possible (after an "setup grub").

EOF
}

function help_test {
    cat <<EOF
$VERSION_STRING

Test the performance of the rtai-patched linux kernel.

Usage:

sudo ${MAKE_RTAI_KERNEL} [-d] [-n xxx] [-r xxx] [-k xxx] test [[hal|sched|math|comedi] [calib]
     [kern|kthreads|user|all|none] [cpu|io|mem|net|full] 
     [cpu=<CPUIDS>] [latency|cpulatency|cpulatencyall] [performance]
     [<NNN>] [auto <XXX> | batch basics|cstates|acpi|isolcpus|dma|poll|<FILE>]]

EOF
    help_kernel_options
    cat <<EOF

Tests are performed only if the running kernel matches the one
${MAKE_RTAI_KERNEL} is configured for.

Test resluts are saved in latencies-* files in the current working
directory. The corresponding kernel configuration is saved in the
respective config-* files.

First, loading and unloading of rtai and comedi modules is tested. 
This can be controlled by the following key-words of which one can be specified:
  hal     : test loading and unloading of rtai_hal kernel module only
  sched   : test loading and unloading of rtai_hal and rtai_sched kernel modules
  math    : test loading and unloading of rtai_hal, rtai_sched, and rtai_math kernel module
  comedi  : test loading and unloading of rtai and comedi kernel modules
Additionally, you may specify:
  calib   : force calibration of scheduling latencies (default is no calibration)

Then the rtai tests (latency, switch, and preempt) are executed. You can
select what to test by specifying one or more of the following key-words:
  kern     : run the kern tests (default)
  kthreads : run the kthreads tests
  user     : run the user tests
  all      : run the kernel, kthreads, and user tests
  none     : test loading and unloading of kernel modules and do not run any tests

You may want to run some load on you system to really test the RTAI
performance. This can be controlled by the following key-words:
  cpu      : run heavy computations on each core
  io       : do some heavy file reading and writing
  mem      : do some heavy memory access
  net      : produce network traffic
  full     : all of the above

Further options specify further conditions for running the tests:
  cpu=<CPUIDS> : run tests on CPU with ids <CPUIDS>. <CPUIDS> is a comma separated
                 list of CPUs. The first CPU is 0. For example, cpu=2 runs the tests
                 on the third CPU.
  latency      : Keep all CPUs in C0 state by writing a zero to the file /dev/cpu_dma_latency .
  cpulatency   : Using PM QoS request to keep CPUs in C0 state. If a CPU was specified for 
                 running the tests (cpu=<CPUIDS> parameter), only that CPU is put into C0, 
                 if possible. Uses the cpulatency kernel module.
  cpulatencyall: Using PM QoS request to keep all CPUs in C0 state.
                 Uses the cpulatency kernel module.
  performance  : Sets the cpu freq scaling governor to performance, i.e. to the maximum frequency.

The rtai tests need to be terminated by pressing ^C and a string
describing the test scenario needs to be provided. This can be
automized by the following two options:
  NNN      : the number of seconds after which the latency test is automatically aborted,
             the preempt test will be aborted after 10 seconds.
  auto XXX : a one-word description of the kernel configuration (no user interaction)

For a completely automized series of tests of various kernel parameters and kernel configurations
under different loads you may add as the last arguments:
  batch FILE     : automatically run tests with various kernel parameter and configurations as specified in FILE
  batch basics   : write a default batch file with basic kernel parameters to be tested
  batch isolcpus : write a default batch file with load settings and isolcpus kernel parameters to be tested
  batch nohzrcu  : write a default batch file with more isolcpus kernel parameters to be tested
  batch dma      : write a default batch file with io load, dma, and isolcpus kernel parameters to be tested
  batch poll     : write a default batch file for testing run-time alternatives to idle=poll
  batch cstates  : write a default batch file with c-states related kernel parameters to be tested
  batch acpi     : write a default batch file with acpi related kernel parameters to be tested
  batch apic     : write a default batch file with apic related kernel parameters to be tested
This successively reboots into the RTAI kernel with the kernel parameter 
set to the ones specified by the KERNEL_PARAM variable and as specified in FILE,
and runs the tests as specified by the previous commands (without the "auto" command).
Special lines in FILE cause reboots into the default kernel and building an RTAI-patched kernel
with a new configuration.

In a batch FILE
- everything behind a hash ('#') is a comment that is completely ignored
- empty lines are ignored
- a line of the format
  <descr> : <specs> : <params>
  describes a configuration to be tested:
  <descr> is a one-word string describing the kernel parameter 
    (a description of the load settings is added automatically to the description)
  <specs> defines the load processes to be
    started before testing (cpu io mem net full, see above), the CPU
    on which the test should be run (cpu=<CPUIDS>, see above),
    whether CPUs should be kept in C0 state (latency, cpulatency, or cpulatencyall, see above),
    and/or whether the CPU frequency should be maximized (performance, see above).
  <param> is a list of kernel parameter to be used.
- a line of the format
  <descr> : CONFIG : <file>
  specifies a new kernel configuration stored in <file>,
  that is compiled after booting into the default kernel.
  <descr> describes the kernel configuration; it is used for naming successive tests.
  Actually, <file> can be everything the -c otion is accepting, in particular
  <descr> : CONFIG : backup
  compiles a kernel with the configuration of the kernel at the beginning of the tests.
  This is particularly usefull as the last line of a batch file.
- the first line  of the batch file can be just
  <descr> : CONFIG :
  this sets <descr> as the description of the already existing RTAI kernel for the following tests.

Use 
${MAKE_RTAI_KERNEL} prepare
to generate a file with various kernel configurations.

Example lines:
  lowlatency : CONFIG :
  pollnohz : : idle=poll nohz=off
  nohz : latency : nohz=off
  nodyntics : CONFIG : config-nodyntics
  pollisol : cpu io : idle=poll isolcpus=0,1
  isol2 : io cpu=2 : isolcpus=2
See the file written by "batch default" for suggestions, and the file
$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/Documentation/kernel-parameters.txt
for a documentation of all kernel parameter.

EOF
}

function help_report {
    cat <<EOF
$VERSION_STRING

Generate summary tables of test results.

Usage:

${MAKE_RTAI_KERNEL} report [avg|max] [<FILES>]

The summary is written to standard out. For example, redirect the
output into a file to save the summary:

${MAKE_RTAI_KERNEL} report > testsummary.dat 

or pipe it into less to view the results:

${MAKE_RTAI_KERNEL} report | less -S

The tests can be sorted by providing the avg or max key-word:
report     : do not sort
report avg : sort the tests according to the avgmax field of the kern latency test
report max : sort the tests according to the ovlmax field of the kern latency test

The remaining arguments specify files to be included in the summary,
or a directory containing latency-* files. If no file is specified,
all latency-* files in the current directory are used.

EOF
}

function help_usage {
    cat <<EOF
$VERSION_STRING

Download, build, install and test everything needed for an rtai-patched linux kernel with math and comedi support.

usage:
sudo ${MAKE_RTAI_KERNEL} [-d] [-s xxx] [-n xxx] [-r xxx] [-p xxx] [-k xxx] [-c xxx] [-l] [-D] [-m] 
     [action [target1 [target2 ... ]]]

EOF
    help_kernel_options
    cat <<EOF
-s xxx: use xxx as the base directory where to put the kernel sources (KERNEL_PATH=${KERNEL_PATH})
-p xxx: use rtai patch file xxx (RTAI_PATCH=${RTAI_PATCH})
        set to "none" if no patch should be applied
-c xxx: generate a new kernel configuration (KERNEL_CONFIG=${KERNEL_CONFIG}):
        - old: use the kernel configuration of the currently running kernel
        - def: generate a kernel configuration using make defconfig
        - mod: simplify existing kernel configuration using make localmodconfig
               even if kernel do not match
        - backup: use the backed up kernel configuration from the last test batch.
        - <config-file>: provide a particular configuration file
        After setting the configuration (except for mod), make localmodconfig
        is executed to deselect compilation of unused modules, but only if the
        runnig kernel matches the selected kernel version (major.minor only).
-l    : disable call to make localmodconf after a kernel configuration 
        has been selected via the -c switch (RUN_LOCALMOD=${RUN_LOCALMOD})
-m    : enter the RTAI configuration menu

Note: for running test batches, settings provided via the command line are lost after rebooting.

You can modify the settings by editing "$MAKE_RTAI_KERNEL" directly.
Alternatively, you can provide settings by listing them in a configuration file
in the current working directory called "$MAKE_RTAI_CONFIG". Create a configuration
file by means of the "config" action (see below).

If no action is specified, a full download and build is performed for all targets (except showroom).

For the targets one or more of:
  packages   : required packages (install only)
  kernel     : rtai-patched linux kernel
  newlib     : newlib library, needed for math support in kernel
  musl       : musl library, needed for math support in kernel
  rtai       : rtai modules
  showroom   : rtai showroom examples (supports only download, build, clean, remove)
  comedi     : comedi data acquisition driver modules
  comedilib  : comedi data acquisition user space library
  comedicalib: comedi data acquisition calibration tools
action can be one of:
  download   : download missing sources of the specified targets
  update     : update sources of the specified targets (not for kernel target)
  patch      : clean, unpack, and patch the linux kernel with the rtai patch (no target required)
  prepare    : prepare kernel configurations for a test batch (no target required)
  build      : compile and install the specified targets and the depending ones if needed
  buildplain : compile and install the kernel without the rtai patch (no target required)
  clean      : clean the source trees of the specified targets
  install    : install the specified targets
  uninstall  : uninstall the specified targets
  remove     : remove the complete source trees of the specified targets.
If no target is specified, all targets are made (except showroom).

Action can be also one of
  help       : display this help message
  help XXX   : display help message for action XXX
  info       : display properties of rtai patches, loaded kernel modules,
               kernel, cpus, machine, log file, and grub menu
               (run "${MAKE_RTAI_KERNEL} help info" for details)
  config     : write the configuration file \"${MAKE_RTAI_CONFIG}\" 
               that you can edit according to your needs
  init       : should be executed the first time you use ${MAKE_RTAI_KERNEL} -
               equivalent to install packages, setup, download rtai, info rtai.
  reconfigure: reconfigure the kernel and make a full build of all targets (without target)
  reboot     : reboot and set kernel parameter
               (run "${MAKE_RTAI_KERNEL} help reboot" for details)
  setup      : setup some basic configurations of your (debian based) system
               (run "${MAKE_RTAI_KERNEL} help setup" for details)
  restore    : restore the original system settings
               (run "${MAKE_RTAI_KERNEL} help restore" for details)
  test       : test the current kernel and write reports to the current working directory 
               (run "${MAKE_RTAI_KERNEL} help test" for details)
  report     : summarize test results from latencies* files given in FILES
               (run "${MAKE_RTAI_KERNEL} help report" for details)

Common use cases:

Start with installing required packages, setting up /var/log/messages, the grub boot menu,
and downloading an rtai source (-r option or RTAI_DIR variable):
$ sudo ${MAKE_RTAI_KERNEL} init

Select a Linux kernel and a RTAI patch from the displayed list and set
the LINUX_KERNEL and RTAI_PATCH variables in the makertaikernel.sh
script accordingly.

Check again for available patches:
$ sudo ${MAKE_RTAI_KERNEL} info rtai

Once you have decided on a patch and you have set LINUX_KERNEL and
RTAI_PATCH variables accrdingly run
$ sudo ${MAKE_RTAI_KERNEL}
to download and build all targets. A new configuration for the kernel is generated.

$ sudo ${MAKE_RTAI_KERNEL} test
  manually test the currently running kernel.

$ sudo ${MAKE_RTAI_KERNEL} test 30 auto basic
  automaticlly test the currently running kernel for 30 seconds and name it "basic".

$ sudo ${MAKE_RTAI_KERNEL} test ${TEST_TIME_DEFAULT} batch testbasics.mrk
  automaticlly test all the kernel parameter and kernel configurations specified in the file testbasics.mrk.

$ ${MAKE_RTAI_KERNEL} report avg | less -S
  view test results sorted with respect to the averaged maximum latency. 

$ sudo ${MAKE_RTAI_KERNEL} reconfigure
  build all targets using the existing configuration of the kernel.

$ sudo ${MAKE_RTAI_KERNEL} uninstall
  uninstall all targets.
EOF
}

function check_root {
    if test "x$(id -u)" != "x0"; then
	echo "You need to be root to run this script!"
	echo "Try:"
	echo "  sudo $0 ${FULL_COMMAND_LINE}"
	exit 1
    fi
}

function print_setup {
    check_root

    echo
    echo "System modifications made by ${MAKE_RTAI_KERNEL}:"
    echo
    # messages:
    if test -f /etc/rsyslog.d/50-default.conf.origmrk; then
	echo "messages : /etc/rsyslog.d/50-default.conf is modified"
	echo "           run \"${MAKE_RTAI_KERNEL} restore messages\" to restore"
    elif test -f /etc/rsyslog.d/50-default.conf; then
	echo "messages : /etc/rsyslog.d/50-default.conf is not modified"
	echo "           run \"${MAKE_RTAI_KERNEL} setup messages\" for setting up"
    fi
    # grub:
    if test -f /etc/default/grub.origmrk; then
	echo "grub     : /etc/default/grub is modified"
	echo "           run \"${MAKE_RTAI_KERNEL} restore grub\" to restore"
    else
	echo "grub     : /etc/default/grub is not modified"
	echo "           run \"${MAKE_RTAI_KERNEL} setup grub\" for setting up"
    fi
    if test -f /etc/grub.d/10_linux.origmrk; then
	echo "grub     : /etc/grub.d/10_linux is modified"
	echo "           run \"${MAKE_RTAI_KERNEL} restore grub\" to restore"
    else
	echo "grub     : /etc/grub.d/10_linux is not modified"
	echo "           run \"${MAKE_RTAI_KERNEL} setup grub\" for setting up"
    fi
    # kernel parameter:
    if test -f /boot/grub/grubenv; then
	if grub-editenv - list | grep -q "rtai_cmdline"; then
	    echo "kernel   : /boot/grub/grubenv is modified ($(grub-editenv - list | grep "rtai_cmdline"))"
	    echo "           run \"${MAKE_RTAI_KERNEL} restore kernel\" to restore"
	else
	    echo "kernel   : /boot/grub/grubenv is not modified"
	    echo "           run \"${MAKE_RTAI_KERNEL} setup kernel\" for setting up RTAI kernel parameter"
	fi
    else
	if test -f /etc/default/grub.origkp; then
	    echo "kernel   : /etc/default/grub is modified"
	    echo "           run \"${MAKE_RTAI_KERNEL} restore kernel\" to restore"
	else
	    echo "kernel   : /etc/default/grub is not modified"
	    echo "           run \"${MAKE_RTAI_KERNEL} setup kernel\" for setting up default RTAI kernel parameter"
	fi
    fi
    # rtai:
    if test -f ${LOCAL_SRC_PATH}/$RTAI_DIR/testsuite/kern/latency/latency-module.c.mrk; then
	echo "rtai     : testsuite is modified"
	echo "           run \"${MAKE_RTAI_KERNEL} restore rtai\" to restore"
    else
	echo "rtai     : testsuite is not modified"
	echo "           run \"${MAKE_RTAI_KERNEL} setup rtai <cpumask>\" for setting a CPU mask for the tests"
    fi
    # test batch:
    if crontab -l 2> /dev/null | grep -q "${MAKE_RTAI_KERNEL}"; then
	echo "testbatch: crontab is modified"
	echo "           run \"${MAKE_RTAI_KERNEL} restore testbatch\" to restore"
    else
	echo "testbatch: crontab is not modified"
    fi
    echo
}

function print_log {
    if test -r "${LOG_FILE}"; then
	echo "Content of the log-file \"${LOG_FILE}\":"
	cat "$LOG_FILE"
    else
	echo "Log-file \"${LOG_FILE}\" not available."
    fi
}

function print_kernel_configs {
    KCF=""
    test -z "$1" && KCF="config-*"
    if [ -t 1 ]; then
	echo "Available kernel configurations - add them to a test batch file."
	echo "Configurations identical with the current one are marked by an asterisk."
	echo
	for FILE in "$@" $KCF; do
	    SAME="  "
	    diff -q "$FILE" $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config> /dev/null && SAME="* "
	    echo "${SAME}${FILE##*config-} : CONFIG : $FILE"
	done
    else
	for FILE in "$@" $KCF; do
	    echo "${FILE##*config-} : CONFIG : $FILE"
	done
    fi
}

function print_grub {
    if test "x$1" = "xenv" && test -r /boot/grub/grubenv; then
	echo "Grub environment:"
	grub-editenv - list | indent
	echo
    fi
    echo "Grub menu entries:"
    IFSORG="$IFS"
    IFS=$'\n'
    N=0
    for gm in $(grep '^\s*menuentry ' /boot/grub/grub.cfg | cut -d "'" -f 2); do
	echo "  $N) $gm"
	let N+=1
    done
    IFS="$IFSORG"
    echo
}

function print_versions {
    echo "Versions:"
    echo "  kernel     : ${LINUX_KERNEL}"
    echo "  gcc        : $(gcc --version | head -n 1)"
    if test -r ${LOCAL_SRC_PATH}/${RTAI_DIR}/revision.txt; then
	echo "  rtai       : ${RTAI_DIR} from $(cat ${LOCAL_SRC_PATH}/${RTAI_DIR}/revision.txt)"
	echo "  patch      : ${RTAI_PATCH}"
    elif test -d ${LOCAL_SRC_PATH}/${RTAI_DIR}; then
	echo "  rtai       : ${RTAI_DIR} revision not available"
	echo "  patch      : ${RTAI_PATCH}"
    else
	echo "  rtai       : not available"
    fi
    if test -r ${LOCAL_SRC_PATH}/newlib/src/revision.txt; then
	echo "  newlib     : git from $(cat ${LOCAL_SRC_PATH}/newlib/src/revision.txt)"
    elif test -r ${LOCAL_SRC_PATH}/newlib/revision.txt; then
	echo "  newlib     : git from $(cat ${LOCAL_SRC_PATH}/newlib/revision.txt)"
    elif test -d ${LOCAL_SRC_PATH}/newlib; then
	echo "  newlib     : revision not available"
    else
	echo "  newlib     : not available"
    fi
    if test -r ${LOCAL_SRC_PATH}/musl/revision.txt; then
	echo "  musl       : git from $(cat ${LOCAL_SRC_PATH}/musl/revision.txt)"
    elif test -d ${LOCAL_SRC_PATH}/musl; then
	echo "  musl       : revision not available"
    else
	echo "  musl       : not available"
    fi
    if test -r ${LOCAL_SRC_PATH}/comedi/revision.txt; then
	echo "  comedi     : git from $(cat ${LOCAL_SRC_PATH}/comedi/revision.txt)"
    elif test -d ${LOCAL_SRC_PATH}/comedi; then
	echo "  comedi     : revision not available"
    else
	echo "  comedi     : not available"
    fi
    if test -r ${LOCAL_SRC_PATH}/comedilib/revision.txt; then
	echo "  comedilib  : git from $(cat ${LOCAL_SRC_PATH}/comedilib/revision.txt)"
    elif test -d ${LOCAL_SRC_PATH}/comedilib; then
	echo "  comedilib  : revision not available"
    else
	echo "  comedilib  : not available"
    fi
    if test -r ${LOCAL_SRC_PATH}/comedicalib/revision.txt; then
	echo "  comedicalib: git from $(cat ${LOCAL_SRC_PATH}/comedicalib/revision.txt)"
    elif test -d ${LOCAL_SRC_PATH}/comedicalib; then
	echo "  comedicalib: revision not available"
    else
	echo "  comedicalib: not available"
    fi
    echo
}

function print_interrupts {
    echo "Interrupts (/proc/interrupts):"
	cat /proc/interrupts | indent
    echo
}

function print_kernel {
    echo "Hostname: $(hostname)"
    echo
    echo "Running kernel (uname -r): $(uname -r)"
    echo
    echo "Kernel parameter (/proc/cmdline):"
    for param in $(cat /proc/cmdline); do
	echo "  $param"
    done
    echo
}

function print_environment {
    CPU_ID=$1

    echo "Environment:"
    echo "  tests run on cpu    : ${CPU_ID}"

    # /dev/cpu_dma_latency:
    if test "x$(id -u)" == "x0"; then
	# if we are root we can show /dev/cpu_dma_latency:
	if test -c /dev/cpu_dma_latency; then
	    echo "  /dev/cpu_dma_latency: $(hexdump -e '"%d\n"' /dev/cpu_dma_latency)"
	else
	    echo "  /dev/cpu_dma_latency: -"
	fi
    fi

    # cpulatency kernel module:
    if lsmod | grep -q cpulatency; then
	CPU_LAT_ID=$(grep -a cpulatency /var/log/messages | tail -n 1 | sed -e 's/^.*CPU=//')
	echo "  cpulatency on cpu   : $CPU_LAT_ID"
    else
	echo "  cpulatency          : not loaded"
    fi

    # frequency scaling:
    CPU=/sys/devices/system/cpu/cpu${CPU_ID}
    CPUFREQGOVERNOR="-"
    test -r $CPU/cpufreq/scaling_governor && CPUFREQGOVERNOR=$(cat $CPU/cpufreq/scaling_governor)
    echo "  governor            : $CPUFREQGOVERNOR"
    CPUFREQ=$(grep 'cpu MHz' /proc/cpuinfo | awk -F ': ' "NR==$(($CPU_ID+1)) {printf \"%.3f\", 0.001*\$2}")
    test -r $CPU/cpufreq/scaling_cur_freq && CPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/scaling_cur_freq)/1000000.0 | bc)
    echo "  cpu frequency       : $CPUFREQ GHz"
    if test -r $CPU/cpufreq/scaling_max_freq; then
	CPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/scaling_max_freq)/1000000.0 | bc)
	echo "  max cpu frequency   : $CPUFREQ GHz"
    fi
    if test -r $CPU/cpufreq/scaling_min_freq; then
	CPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/scaling_min_freq)/1000000.0 | bc)
	echo "  min cpu frequency   : $CPUFREQ GHz"
    fi

    echo
}

function store_cpus {
    rm -f results-cpufreq${1}.dat results-cpuidle${1}.dat

    # frequency statistics needs CONFIG_CPU_FREQ_STAT:
    if test -r /sys/devices/system/cpu/cpu0/cpufreq/stats/total_trans; then
	for CPU in /sys/devices/system/cpu/cpu[0-9]*; do
	    cat $CPU/cpufreq/stats/total_trans
	done > results-cpufreq${1}.dat
    fi

    CSTATEUSAGE="time" # "usage" or "time"
    if test -r /sys/devices/system/cpu/cpu0/cpuidle/state0/name; then
	for CPU in /sys/devices/system/cpu/cpu[0-9]*; do
	    for CSTATE in $CPU/cpuidle/state*; do
		echo -n "$(cat $CSTATE/$CSTATEUSAGE)  "
	    done
	    echo
	done > results-cpuidle${1}.dat
    fi
}

function print_cpus {
    echo "CPU topology, frequencies, and idle states (/sys/devices/system/cpu/*):"
    # first header line:
    printf "CPU topology                   CPU frequency scaling              "
    test -r /sys/devices/system/cpu/cpu0/cpuidle/state0/name && printf "  CPU idle states (disabled time-fraction%%)"
    printf "\n"

    # second header line:
    printf "logical  socket  core  online  freq/GHz      governor  transitions"
    if test -r /sys/devices/system/cpu/cpu0/cpuidle/state0/name; then
	for CSTATE in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
	    printf "  %-7s" $(cat $CSTATE)
	done
    fi
    printf "\n"

    # data:
    store_cpus 1
    CPU_NO=0
    for CPU in /sys/devices/system/cpu/cpu[0-9]*; do
	let CPU_NO+=1
	CPUT="$CPU/topology"
	LC_NUMERIC="en_US.UTF-8"
	ONLINE=1
	test -r $CPU/online && ONLINE=$(cat $CPU/online)
	CPUFREQ=$(grep 'cpu MHz' /proc/cpuinfo | awk -F ': ' "NR==$CPU_NO {printf \"%.3f\", 0.001*\$2}")
	test -r $CPU/cpufreq/scaling_cur_freq && CPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/scaling_cur_freq)/1000000.0 | bc)
	CPUFREQGOVERNOR="-"
	test -r $CPU/cpufreq/scaling_governor && CPUFREQGOVERNOR=$(cat $CPU/cpufreq/scaling_governor)
	CPUFREQTRANS="n.a."
	if test -r results-cpufreq1.dat; then
	    CPUFREQTRANS=$(sed -n -e "${CPU_NO}p" results-cpufreq1.dat)
	    if test -r results-cpufreq0.dat; then
		CF0=$(sed -n -e "${CPU_NO}p" results-cpufreq0.dat)
		let CPUFREQTRANS-=$CF0
	    fi
	fi
	printf "  cpu%-2d  %6d  %4d  %6d  %8.3f  %12s  %11s" ${CPU#/sys/devices/system/cpu/cpu} $(cat $CPUT/physical_package_id) $(cat $CPUT/core_id) $ONLINE $CPUFREQ $CPUFREQGOVERNOR $CPUFREQTRANS
	if test -r results-cpuidle1.dat; then
	    CPUIDLETRANS=($(sed -n -e "${CPU_NO}p" results-cpuidle1.dat))
	    if test -r results-cpuidle0.dat; then
		CI0=($(sed -n -e "${CPU_NO}p" results-cpuidle0.dat))
		for (( i=0; i<${#CPUIDLETRANS[@]}; ++i )); do
		    let CPUIDLETRANS[$i]-=${CI0[$i]}
		done
	    fi
	    SUM=0
	    for CS in ${CPUIDLETRANS[*]}; do
		let SUM+=$CS
	    done
	    CS=0
	    for CSTATE in $CPU/cpuidle/state*; do
		printf "  %1s %4.1f%%" $(cat $CSTATE/disable) $(echo "scale=1; 100.0*${CPUIDLETRANS[$CS]}/$SUM" | bc)
		let CS+=1
	    done
	fi
    printf "\n"
    done
    echo

    echo "CPU frequency scaling, idle, and boost (/sys/devices/system/cpu/{cpuidle,cpufreq}):"
    CPU_FREQ="no"
    if test -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver; then
	CPU_FREQ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver)"
    fi
    CPU_IDLE="no"
    if test -r /sys/devices/system/cpu/cpuidle/current_driver; then
	CPU_IDLE="$(cat /sys/devices/system/cpu/cpuidle/current_driver)"
    fi
    CPU_BOOST="no"
    if test -r /sys/devices/system/cpu/cpufreq/boost; then
	CPU_BOOST="$(cat /sys/devices/system/cpu/cpufreq/boost)"
    fi
    echo "  scaling driver : $CPU_FREQ"
    echo "  cpuidle driver : $CPU_IDLE"
    echo "  boost          : $CPU_BOOST"
    echo

    echo "CPU core temperatures (sensors):"
    if sensors &> /dev/null; then
	if test "$(sensors | grep Core | wc -l)" -ge 1; then
	    sensors | grep Core | indent
	else
	    sensors | grep temp | indent
	fi
	echo
    else
	echo "  sensors not available or appropriate kernel module missing - check sensors and sensors-detect manually."
	echo
    fi

    MAXCPUFREQ="n.a."
    test -r $CPU/cpufreq/cpuinfo_max_freq && MAXCPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/cpuinfo_max_freq)/1000000.0 | bc)
    test -r $CPU/cpufreq/scaling_max_freq && MAXCPUFREQ=$(echo "scale=3;" $(cat $CPU/cpufreq/scaling_max_freq)/1000000.0 | bc)

    echo "CPU (/proc/cpuinfo):"
    echo "  $(grep "model name" /proc/cpuinfo | awk -F '\t:[ ]*' 'NR==1 { printf "%-17s : %s", $1, $2}')"
    echo "  number of CPUs    : $CPU_NO"
    test "MAXCPUFREQ" != "n.a." && echo "  max CPU frequency : $MAXCPUFREQ GHz"
    echo "  CPU family        : $(grep "cpu family" /proc/cpuinfo | awk 'NR==1 { print $4}')"
    echo "  machine (uname -m): $MACHINE"
    echo "  memory (free -h)  : $(free -h | grep Mem | awk '{print $2}') RAM"
    echo
}

function print_distribution {
    if lsb_release &> /dev/null; then
	echo "Distribution (lsb_release -a):"
	lsb_release -a 2> /dev/null | awk -F ':[ \t]*' '{printf("%-15s: %s\n", $1, $2)}' | indent
    else
	echo "Distribution: unknown"
    fi
    echo
}

function print_settings {
    echo "Settings of ${VERSION_STRING}:"
    echo "  KERNEL_PATH     (-s) = $KERNEL_PATH"
    echo "  LINUX_KERNEL    (-k) = $LINUX_KERNEL"
    echo "  KERNEL_SOURCE_NAME   = $KERNEL_SOURCE_NAME"
    echo "  KERNEL_NUM      (-n) = $KERNEL_NUM"
    echo "  KERNEL_CONFIG   (-c) = $KERNEL_CONFIG"
    echo "  KERNEL_MENU          = $KERNEL_MENU"
    echo "  RUN_LOCALMOD    (-l) = $RUN_LOCALMOD"
    echo "  KERNEL_PARAM         = $KERNEL_PARAM"
    echo "  KERNEL_PARAM_DESCR   = $KERNEL_PARAM_DESCR"
    echo "  BATCH_KERNEL_PARAM   = $BATCH_KERNEL_PARAM"
    echo "  KERNEL_CONFIG_BACKUP = $KERNEL_CONFIG_BACKUP"
    echo "  TEST_TIME_DEFAULT    = $TEST_TIME_DEFAULT"
    echo "  STARTUP_TIME         = $STARTUP_TIME"
    echo "  COMPILE_TIME         = $COMPILE_TIME"
    echo "  LOCAL_SRC_PATH       = $LOCAL_SRC_PATH"
    echo "  RTAI_DIR        (-r) = $RTAI_DIR"
    echo "  RTAI_PATCH      (-p) = $RTAI_PATCH"
    echo "  RTAI_MENU       (-m) = $RTAI_MENU"
    echo "  RTAI_HAL_PARAM       = $RTAI_HAL_PARAM"
    echo "  RTAI_SCHED_PARAM     = $RTAI_SCHED_PARAM"
    echo "  SHOWROOM_DIR         = $SHOWROOM_DIR"
    echo "  NEWLIB_TAR           = $NEWLIB_TAR"
    echo "  MUSL_TAR             = $MUSL_TAR"
    echo "  MAKE_NEWLIB          = $MAKE_NEWLIB"
    echo "  MAKE_MUSL            = $MAKE_MUSL"
    echo "  MAKE_RTAI            = $MAKE_RTAI"
    echo "  MAKE_COMEDI          = $MAKE_COMEDI"
    echo
}

function print_config {
    cat <<EOF
# settings for ${MAKE_RTAI_KERNEL}:

# Path for the kernel archive and sources:
KERNEL_PATH="$KERNEL_PATH"

# Version of linux kernel:
LINUX_KERNEL="$LINUX_KERNEL"

# Name for kernel source directory to be appended to LINUX_KERNEL:
KERNEL_SOURCE_NAME="$KERNEL_SOURCE_NAME"

# Name for RTAI patched linux kernel to be appended to kernel and RTAI version:
KERNEL_NUM="$KERNEL_NUM"

# The kernel configuration to be used:
#   "old" for oldconfig from the running (or already configured kernel) kernel,
#   "def" for the defconfig target,
#   "mod" for the localmodconfig target, (even if kernel versions do not match)
#   "backup" for the backed up kernel configuration from the last test batch.
# or a full path to a config file.
KERNEL_CONFIG="$KERNEL_CONFIG"

# Menu for editing the kernel configuration (menuconfig, gconfig, xconfig):
KERNEL_MENU="$KERNEL_MENU"

# Run localmodconfig on the kernel configuration to deselect
# all kernel modules that are not currently used.
RUN_LOCALMOD=$RUN_LOCALMOD

# Default kernel parameter to be used when booting into the RTAI patched kernel:
KERNEL_PARAM="$KERNEL_PARAM"

# One-word description of the KERNEL_PARAM that is added to the test description:
KERNEL_PARAM_DESCR="$KERNEL_PARAM_DESCR"

# Kernel parameter to be added when running test batches:
BATCH_KERNEL_PARAM="$BATCH_KERNEL_PARAM"

# Name of the file used by test batches for backing up the kernel configuration:
KERNEL_CONFIG_BACKUP="$KERNEL_CONFIG_BACKUP"

# Default time in seconds to run the RTAI latency tests:
TEST_TIME_DEFAULT=$TEST_TIME_DEFAULT

# Time in seconds to wait for starting a test batch after reboot:
STARTUP_TIME=$STARTUP_TIME

# Approximate time in seconds needed to compile a linux kernel
# (watch output of ${MAKE_RTAI_KERNEL} reconfigure for a hint):
COMPILE_TIME=$COMPILE_TIME

# Base path for sources of RTAI, newlib, musl, and comedi:
LOCAL_SRC_PATH="$LOCAL_SRC_PATH"

# Name of source and folder of RTAI sources in LOCAL_SOURCE_PATH:
# official relases for download (www.rtai.org):
# - rtai-4.1: rtai release version 4.1
# - rtai-5.1: rtai release version 5.1
# - rtai-x.x: rtai release version x.x
# from cvs (http://cvs.gna.org/cvsweb/?cvsroot=rtai):
# - magma: current development version
# - vulcano: stable development version
RTAI_DIR="$RTAI_DIR"

# File name of RTAI patch to be used (check with ${MAKE_RTAI_KERNEL} info rtai):
RTAI_PATCH="$RTAI_PATCH"

# Bring up menu for configuring RTAI?
RTAI_MENU=$RTAI_MENU

# Parameter to be passed on to the rtai_hal kernel module:
RTAI_HAL_PARAM="$RTAI_HAL_PARAM"

# Parameter to be passed on to the rtai_sched kernel module:
RTAI_SCHED_PARAM="$RTAI_SCHED_PARAM"

# Name of folder for showroom sources in LOCAL_SOURCE_PATH:
SHOWROOM_DIR="$SHOWROOM_DIR"

# Build newlib math library?
MAKE_NEWLIB=$MAKE_NEWLIB

# Build musl math library?
MAKE_MUSL=$MAKE_MUSL

# Build RTAI?
MAKE_RTAI=$MAKE_RTAI

# Build comedi daq-board drivers?
MAKE_COMEDI=$MAKE_COMEDI

# Uncomment in the following list the columns you want to hide in the test report:
HIDE_COLUMNS=(
#data
#data:num
#data:kernel_parameter
#data:load
#data:quality
#data:cpuid
#data:latency
#data:performance
#data:temp
#data:freq
#data:poll
#kern_latencies
#kern_latencies:mean_jitter
#kern_latencies:stdev
#kern_latencies:max
#kern_latencies:overruns
#kern_latencies:n
#kern_switches
#kern_switches:susp
#kern_switches:sem
#kern_switches:rpc
#kern_preempt
#kern_preempt:max
#kern_preempt:jitfast
#kern_preempt:jitslow
#kern_preempt:n
tests:test_details
tests:link
)
EOF
}

function print_kernel_info {
    CPU_ID="$1"
    CPUDATA="$2"
    echo
    echo "Loaded modules (lsmod):"
    if test -r lsmod.dat; then
	cat lsmod.dat | indent
	rm -f lsmod.dat
    else
	lsmod | indent
    fi
    echo
    print_interrupts
    print_distribution
    print_kernel
    if test -n "$CPUDATA" && test -r "$CPUDATA"; then
	cat $CPUDATA
    else
	print_environment $CPU_ID
	print_cpus
    fi
    print_versions
    print_grub
    print_settings
}

function print_rtai_info {
    ORIG_RTAI_PATCH="$RTAI_PATCH"
    RTAI_PATCH=""
    check_kernel_patch "$ORIG_RTAI_PATCH"
    rm -f "$LOG_FILE"
}


###########################################################################
# packages:
function install_packages {
    # required packages:
    echo_log "install packages:"
    if ! command -v apt-get; then
	echo_log "Error: apt-get command not found!"
	echo_log "You are probably not on a Debian based Linux distribution."
	echo_log "The $MAKE_RTAI_KERNEL script will not work properly."
	echo_log "Exit"
	return 1
    fi
    PACKAGES="make gcc libncurses-dev zlib1g-dev g++ libelf-dev bc cvs git autoconf automake libtool"
    if test ${LINUX_KERNEL:0:1} -gt 3; then
	PACKAGES="$PACKAGES libssl-dev libpci-dev libsensors4-dev"
    fi
    if $MAKE_COMEDI; then
	PACKAGES="$PACKAGES bison flex libgsl0-dev libboost-program-options-dev"
    fi
    OPT_PACKAGES="kernel-package stress lm-sensors lshw openssh-server python python-numpy python-matplotlib python-tk"
    if $DRYRUN; then
	echo_log "apt-get -y install $PACKAGES"
	for PKG in $OPT_PACKAGES; do
	    echo_log "apt-get -y install $PKG"
	done
    else
	if ! apt-get -y install $PACKAGES; then
	    FAILEDPKGS=""
	    for PKG in $PACKAGES; do
		if ! apt-get -y install $PKG; then
		    FAILEDPKGS="$FAILEDPKGS $PKG"
		fi
	    done
	    if test -n "$FAILEDPKGS"; then
		echo_log "Failed to install missing packages!"
		echo_log "Maybe package names have changed ..."
		echo_log "We need the following packes, try to install them manually:"
		for PKG in $FAILEDPKGS; do
		    echo_log "  $PKG"
		done
		return 1
	    fi
	fi
	if ! apt-get -y install $OPT_PACKAGES; then
	    FAILEDPKGS=""
	    for PKG in $OPT_PACKAGES; do
		if ! apt-get -y install $PKG; then
		    FAILEDPKGS="$FAILEDPKGS $PKG"
		fi
	    done
	    if test -n "$FAILEDPKGS"; then
		echo_log "Failed to install optional packages!"
		echo_log "Maybe package names have changed ..."
		echo_log "If possible, try to install them manually:"
		for PKG in $FAILEDPKGS; do
		    echo_log "  $PKG"
		done
		return 0
	    fi
	fi
    fi
}

###########################################################################
# linux kernel:

function check_kernel_patch {
    if test -z "$RTAI_PATCH"; then
	if ! test -d "${LOCAL_SRC_PATH}/${RTAI_DIR}"; then
	    echo_log
	    echo_log "Error: RTAI source directory ${LOCAL_SRC_PATH}/${RTAI_DIR} does not exist."
	    echo_log "Download RTAI sources by running"
	    echo_log "$ ./${MAKE_RTAI_KERNEL} download rtai"
	    return 10
	fi
	# remember set kernel and patch:
	RTAI_PATCH_SET="$1"
	LINUX_KERNEL_SET=${LINUX_KERNEL}
	# list all available patches:
	cd ${LOCAL_SRC_PATH}/${RTAI_DIR}/base/arch/$RTAI_MACHINE/patches/
	echo_log
	echo_log "Available ${RTAI_DIR} patches for this machine ($RTAI_MACHINE):"
	ls -1 *.patch 2> /dev/null | sort -V | tee -a "$LOG_FILE" | indent
	echo_log
	# list patches for selected kernel version:
	LINUX_KERNEL_V=${LINUX_KERNEL%.*}
	echo_log "Available ${RTAI_DIR} patches for selected kernel's kernel version ($LINUX_KERNEL_V), latest last:"
	ls -rt -1 *-${LINUX_KERNEL_V}*.patch 2> /dev/null | tee -a "$LOG_FILE" | indent
	echo_log
	# list patches for selected kernel:
	echo_log "Available ${RTAI_DIR} patches for selected kernel ($LINUX_KERNEL), latest last:"
	ls -rt -1 *-${LINUX_KERNEL}*.patch 2> /dev/null | tee -a "$LOG_FILE" | indent
	echo_log
	# currently running kernel:
	echo_log "Currently running kernel:"
	echo_log "  $(uname -r)"
	echo_log
	# suggest a patch:
	RTAI_PATCH="$(ls -rt *-${LINUX_KERNEL}-*.patch 2> /dev/null | tail -n 1)"
	if test -z "$RTAI_PATCH"; then
	    RTAI_PATCH="$(ls -rt *-${LINUX_KERNEL_V}*.patch 2> /dev/null | tail -n 1)"
	    if test -z "$RTAI_PATCH"; then
		RTAI_PATCH="$(ls -rt *.patch 2> /dev/null | tail -n 1)"
	    fi
	fi
	if ! expr match $RTAI_PATCH ".*$LINUX_KERNEL" > /dev/null; then
	    if test "x${RTAI_PATCH:0:10}" = "xhal-linux-"; then
		LINUX_KERNEL=${RTAI_PATCH#hal-linux-}
		LINUX_KERNEL=${LINUX_KERNEL%%-*}
	    else
		LINUX_KERNEL="???"
	    fi
	fi
	cd - &> /dev/null
	echo_log "Choose a patch and set the RTAI_PATCH variable at the top of the script"
	echo_log "and the LINUX_KERNEL variable with the corresponding kernel version."
	echo_log
	echo_log "Suggested values:"
	echo_log
	echo_log "  RTAI_PATCH=\"${RTAI_PATCH}\""
	echo_log "  LINUX_KERNEL=\"${LINUX_KERNEL}\""
	echo_log
	if test "x${RTAI_PATCH}" = "x${RTAI_PATCH_SET}" && test "x${LINUX_KERNEL}" = "x${LINUX_KERNEL_SET}"; then
	    echo_log "are already set."
	else
	    echo_log "Set values:"
	    echo_log
	    echo_log "  RTAI_PATCH=\"${RTAI_PATCH_SET}\""
	    echo_log "  LINUX_KERNEL=\"${LINUX_KERNEL_SET}\""
	fi
	echo_log
	return 1
    elif ! test -f ${LOCAL_SRC_PATH}/${RTAI_DIR}/base/arch/$RTAI_MACHINE/patches/$RTAI_PATCH; then
	echo_log
	echo_log "Error: rtai patch file $RTAI_PATCH does not exist."
	echo_log "Run again with -p \"\" to see list of available patches."
	return 2
    elif ! expr match $RTAI_PATCH ".*$LINUX_KERNEL" > /dev/null; then
	echo_log
	echo_log "Error: kernel version ${LINUX_KERNEL} does not match rtai patch ${RTAI_PATCH}."
	echo_log "Specify a matching kernel with the -k option or by setting the LINUX_KERNEL variable."
	echo_log
	if test "x${RTAI_PATCH:0:10}" = "xhal-linux-"; then
	    LINUX_KERNEL=${RTAI_PATCH#hal-linux-}
	    LINUX_KERNEL=${LINUX_KERNEL%%-*}
	    echo_log "Suggested value:"
	    echo_log
	    echo_log "  LINUX_KERNEL=\"${LINUX_KERNEL}\""
	    echo_log
	fi
	return 2
    fi
    return 0
}

function download_kernel {
    if ! test -d "$KERNEL_PATH"; then
	echo_log "Path to kernel sources $KERNEL_PATH does not exist!"
	return 1
    fi
    cd $KERNEL_PATH
    if ! check_kernel_patch; then
	return 1
    fi
    if test -f linux-$LINUX_KERNEL.tar.xz; then
	echo_log "keep already downloaded linux kernel archive"
    elif test -n "$LINUX_KERNEL"; then
	echo_log "download linux kernel version $LINUX_KERNEL"
	if ! $DRYRUN; then
	    if ! wget https://www.kernel.org/pub/linux/kernel/v${LINUX_KERNEL:0:1}.x/linux-$LINUX_KERNEL.tar.xz; then
		echo_log "Failed to download linux kernel \"https://www.kernel.org/pub/linux/kernel/v${LINUX_KERNEL:0:1}.x/linux-$LINUX_KERNEL.tar.xz\"!"
		return 1
	    fi
	fi
    else
	echo_log
	echo_log "Available ${RTAI_DIR} patches for this machine ($RTAI_MACHINE):"
	ls -rt ${LOCAL_SRC_PATH}/${RTAI_DIR}/base/arch/$RTAI_MACHINE/patches/*.patch | while read LINE; do echo_log "  ${LINE#${LOCAL_SRC_PATH}/${RTAI_DIR}/base/arch/$RTAI_MACHINE/patches/}"; done
	echo_log
	echo_log "You need to specify a linux kernel version!"
	echo_log "Choose one from the above list of available rtai patches (most recent one is at the bottom)"
	echo_log "and pass it to this script via the -k option or set the LINUX_KERNEL variable directly."
	return 1
    fi
}

function unpack_kernel {
    if ! test -d "$KERNEL_PATH"; then
	echo_log "path to kernel sources $KERNEL_PATH does not exist!"
	return 1
    fi
    cd $KERNEL_PATH
    if test -d linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}; then
	echo_log "keep already existing linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME} directory."
	echo_log "  remove it with $ ./${MAKE_RTAI_KERNEL} clean kernel"
    else
	if ! test -f linux-$LINUX_KERNEL.tar.xz; then
	    echo_log "archive linux-$LINUX_KERNEL.tar.xz not found."
	    echo_log "download it with $ ./${MAKE_RTAI_KERNEL} download kernel."
	    cd - &> /dev/null
	    return 1
	fi
	# unpack:
	echo_log "unpack kernel sources from archive"
	if ! $DRYRUN; then
	    tar xof linux-$LINUX_KERNEL.tar.xz
	    mv linux-$LINUX_KERNEL linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	    cd linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	    make mrproper
	fi
	NEW_KERNEL=true
    fi
    cd - &> /dev/null

    # standard softlink to kernel:
    if ! $DRYRUN; then
	cd /usr/src
	ln -sfn $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME} linux
	cd - &> /dev/null
    fi
}

function patch_kernel {
    if test "x$RTAI_PATCH" == "xnone"; then
	echo_log "No rtai patch applied to kernel sources"
	MAKE_NEWLIB=false
	MAKE_MUSL=false
	MAKE_RTAI=false
	MAKE_COMEDI=false
    else
	cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	if $NEW_KERNEL; then
	    if ! check_kernel_patch; then
		cd - &> /dev/null
		return 1
	    fi
	    echo_log "apply rtai patch $RTAI_PATCH to kernel sources"
	    if ! $DRYRUN; then
		if ! patch -p1 < ${LOCAL_SRC_PATH}/${RTAI_DIR}/base/arch/$RTAI_MACHINE/patches/$RTAI_PATCH; then
		    echo_log "Failed to patch the linux kernel \"$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}\"!"
		    cd - &> /dev/null
		    return 1
		fi
	    fi
	fi
	cd - &> /dev/null
    fi
}

function prepare_kernel_configs {
    check_root
    if ! test -d $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}; then
	echo "Linux kernel path \"$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}\" does not exist."
	echo "Please specify an existing directory with a linux kernel source."
	exit 1
    fi

    echo "Prepare kernel configurations to be tested in a test batch."
    echo
    STEP=0

    let STEP+=1
    echo "Step $STEP: backup the original kernel configuration."
    if ! $DRYRUN; then
	cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	cp .config .config.origmrk
	cd - > /dev/null
    fi
    echo

    let STEP+=1
    echo "Step $STEP: decide on a configuration mode."
    echo "        - Incremental configurations go on with the changed configurations."
    echo "        - Absolute configurations always start out from the backed up original kernel configuration."
    read -p "        Incremental or Absolute configurations, or Cancel? (i/A/c) " MODE
    ABSOLUTE=false
    case $MODE in
	i|I ) ABSOLUTE=false ;;
	a|A ) ABSOLUTE=true ;;
	'' ) ABSOLUTE=true ;;
	* ) echo ""
	    echo "Aborted"
	    if ! $DRYRUN; then
		cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
		rm .config.origmrk
		cd - > /dev/null
	    fi
	    exit 0
	    ;;
    esac
    echo

    if $NEW_KERNEL_CONFIG; then
	let STEP+=1
	echo "Step $STEP: set initial kernel configuration from command line."
	echo
	WORKING_DIR="$PWD"
	cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	config_kernel "$WORKING_DIR"
	cd - > /dev/null
	echo
    fi

    let STEP+=1
    echo "Step $STEP: modify and store the kernel configurations."
    CONFIG_FILES=()
    if ! $DRYRUN; then
	while true; do
	    cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	    $ABSOLUTE && cp .config.origmrk .config
	    make $KERNEL_MENU
	    DESCRIPTION=""
	    echo
	    read -p "  Short description of the kernel configuration (empty: finish) " DESCRIPTION
	    echo
	    if test -z "$DESCRIPTION"; then
		break
	    fi
	    make olddefconfig
	    CONFIG_FILES+=( "config-${DESCRIPTION}" )
	    cd - > /dev/null
	    cp $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config "config-${DESCRIPTION}"
	    echo "  Saved kernel configuration \"$DESCRIPTION\" to file \"config-${DESCRIPTION}\"."
	done
	cd - > /dev/null
    fi
    echo

    # clean up:
    let STEP+=1
    echo "Step $STEP: restore the original kernel configuration."
    if ! $DRYRUN; then
	cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	cp .config.origmrk .config
	cd - > /dev/null
    fi
    echo

    let STEP+=1
    if test ${#CONFIG_FILES[@]} -gt 0; then
	echo "Step $STEP: saved ${#CONFIG_FILES[@]} kernel configuration(s)."
	echo
	let STEP+=1
	echo "Step $STEP: go on and use the kernel configurations"
	echo "        by adding the following lines to a test batch file:"
	echo
	for FILE in "${CONFIG_FILES[@]}"; do
	    echo "  ${FILE##*config-} : CONFIG : $FILE"
	done
	echo
	echo "You may pipe these lines directly into a <FILE> that you then can use for a test batch:"
	echo "\$ ${MAKE_RTAI_KERNEL} info configs > <FILE>"
	echo
    else
	echo "Step $STEP: did not save any kernel configurations."
	echo
    fi
    exit 0
}

function config_kernel {
    WORKING_DIR="$1"
    if $NEW_KERNEL_CONFIG; then
	# kernel configuration:
	if test "x$KERNEL_CONFIG" = "xdef"; then
	    echo_log "Use default configuration of kernel (defconfig)."
	    if ! $DRYRUN; then
		make defconfig
	    fi
	elif test "x$KERNEL_CONFIG" = "xold"; then
	    CF="/boot/config-${CURRENT_KERNEL}"
	    test -f "$CF" || CF="/lib/modules/$(uname -r)/build/.config"
	    echo_log "Use configuration from running kernel ($CF) and run olddefconfig."
	    if ! $DRYRUN; then
		cp $CF .config
		make olddefconfig
	    fi
	elif test "x$KERNEL_CONFIG" = "xmod"; then
	    echo_log "Run make localmodconfig."
	    if test ${CURRENT_KERNEL:0:${#LINUX_KERNEL}} != $LINUX_KERNEL ; then
		echo_log "Warning: kernel versions do not match (selected kernel is $LINUX_KERNEL, running kernel is $CURRENT_KERNEL)!"
		echo_log "Run make localmodconfig anyways"
	    fi
	    if ! $DRYRUN; then
		# we need to make sure that the necessary modules are loaded:
		sensors &> /dev/null && echo_log "  sensors available" || echo_log "  sensors not available - check sensors and sensors-detect manually!"
		yes "" | make localmodconfig
	    fi
	    RUN_LOCALMOD=false
	else
	    KCF=""
	    BKP=""
	    if test "x$KERNEL_CONFIG" = "xbackup"; then
		KCF="$KERNEL_CONFIG_BACKUP"
		BKP="backup-"
	    else
		KCF="$KERNEL_CONFIG"
	    fi
	    test "x${KCF:0:1}" !=  "x/" && KCF="$WORKING_DIR/$KCF"
	    if test -f "$KCF"; then
		echo_log "Use ${BKP}configuration from \"$KCF\" and run olddefconfig."
		if ! $DRYRUN; then
		    cp "$KCF" .config
		    make olddefconfig
		fi
	    else
		echo_log "Unknown kernel configuration file \"$KCF\"."
		return 1
	    fi
	fi

	if $RUN_LOCALMOD; then
	    if test "x$(echo $CURRENT_KERNEL | cut -f 1,2 -d '.')" = "x$(echo $LINUX_KERNEL | cut -f 1,2 -d '.')" ; then
		echo_log "Run make localmodconfig"
		if ! $DRYRUN; then
		    # we need to make sure that the necessary modules are loaded:
		    sensors &> /dev/null && echo_log "  sensors available" || echo_log "  sensors not available - check sensors and sensors-detect manually!"
		    yes "" | make localmodconfig
		fi
	    else
		echo_log "Cannot run make localmodconfig, because kernel version does not match (running kernel: ${CURRENT_KERNEL}, selected kernel: ${LINUX_KERNEL})"
	    fi
	fi
    else
	echo_log "Keep already existing .config file for linux-${KERNEL_NAME}."
    fi
}

function menu_kernel {
    check_root
    if test -d "$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}"; then
	WORKING_DIR="$PWD"
	cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}

	echo_log "Backup kernel configuration."
	$DRYRUN || cp .config .config.origmrk

	KF=$KERNEL_CONFIG
	$NEW_KERNEL_CONFIG || KF=".config"
	echo_log "Show kernel configuration menu for configuration \"$KF\"."
	config_kernel "$WORKING_DIR"
	if ! $DRYRUN; then
	    make $KERNEL_MENU
	    mv .config.origmrk .config
	fi
	echo_log "Restored original kernel configuration."
    else
	echo_log "Directory $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME} does not exist."
    fi
}

function build_kernel {
    WORKING_DIR="$PWD"
    cd $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
    echo_log "check for make-kpkg"
    HAVE_MAKE_KPKG=false
    if make-kpkg --help &> /dev/null; then
	HAVE_MAKE_KPKG=true
	echo_log "make-kpkg is available"
    fi
    if $NEW_KERNEL || $NEW_KERNEL_CONFIG || $RECONFIGURE_KERNEL; then

	if ! $RECONFIGURE_KERNEL; then
	    # clean:
	    echo_log "clean kernel sources"
	    if ! $DRYRUN; then
		if $HAVE_MAKE_KPKG; then
		    make-kpkg clean
		else
		    make clean
		fi
	    fi
	fi

	config_kernel "$WORKING_DIR"

	# build the kernel:
	echo_log "build the kernel"
	if ! $DRYRUN; then
	    export CONCURRENCY_LEVEL=$CPU_NUM
	    if $HAVE_MAKE_KPKG; then
		KM=""
		test -n "$KERNEL_MENU" && KM="--config $KERNEL_MENU"
		make-kpkg --initrd --append-to-version -${RTAI_DIR}${KERNEL_NUM} --revision 1.0 $KM kernel-image
	    else
		if test "$KERNEL_MENU" = "old"; then
		    echo "Run make olddefconfig"
		    make olddefconfig
		else
		    echo "Run make $KERNEL_MENU"
		    make $KERNEL_MENU
		fi
		make deb-pkg LOCALVERSION=-${RTAI_DIR}${KERNEL_NUM} KDEB_PKGVERSION=$(make kernelversion)-1
		# [TAR] creates a tar archive of the sources at the root of the kernel source tree
	    fi
 	    if test "x$?" != "x0"; then
		echo_log
		echo_log "Error: failed to build the kernel!"
		echo_log "Scroll up to see why."
		cd "$WORKING_DIR"
		return 1
	    fi
	fi

	cd "$WORKING_DIR"

	# install:
	install_kernel || return 1
    else
	echo_log "Keep already compiled linux ${KERNEL_NAME} kernel."
	cd "$WORKING_DIR"
    fi
}

function clean_kernel {
    cd $KERNEL_PATH
    if test -d linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}; then
	echo_log "remove kernel sources $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}"
	if ! $DRYRUN; then
	    rm -r linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}
	    rm -f linux
	fi
    fi
}

function install_kernel {
    cd "$KERNEL_PATH"
    KERNEL_PACKAGE=$(ls linux-image-${KERNEL_NAME}*.deb | tail -n 1)
    test -f "$KERNEL_PACKAGE" || KERNEL_PACKAGE=$(ls linux-image-${KERNEL_ALT_NAME}*.deb | tail -n 1)
    if test -f "$KERNEL_PACKAGE"; then
	echo_log "install kernel from debian package $KERNEL_PACKAGE"
	if ! $DRYRUN; then
	    if ! dpkg -i "$KERNEL_PACKAGE"; then
		echo_log "Failed to install linux kernel from $KERNEL_PACKAGE !"
		cd - &> /dev/null
		return 1
	    fi
	fi
    else
	echo_log "no kernel to install"
	cd - &> /dev/null
	return 1
    fi
    cd - &> /dev/null
}

function uninstall_kernel {
    # kernel:
    if test ${CURRENT_KERNEL} = ${KERNEL_NAME} -o ${CURRENT_KERNEL} = ${KERNEL_ALT_NAME}; then
	echo_log "Cannot uninstall a running kernel!"
	echo_log "First boot into a different kernel. E.g. by executing"
	echo_log "$ ./${MAKE_RTAI_KERNEL} reboot"
	return 1
    fi
    echo_log "remove comedi kernel modules"
    if ! $DRYRUN; then
	rm -rf /lib/modules/${KERNEL_NAME}/comedi
	rm -rf /lib/modules/${KERNEL_ALT_NAME}/comedi
    fi
    echo_log "uninstall kernel ${KERNEL_NAME}"
    if ! $DRYRUN; then
	if ! apt-get -y remove linux-image-${KERNEL_NAME}; then
	    if ! apt-get -y remove linux-image-${KERNEL_ALT_NAME}; then
		echo_log "Failed to uninstall linux kernel package \"linux-image-${KERNEL_NAME}\"!"
		return 1
	    fi
	fi
    fi
}

function remove_kernel {
    cd $KERNEL_PATH
    if test -f linux-$LINUX_KERNEL.tar.xz; then
	echo_log "remove kernel package $KERNEL_PATH/linux-$LINUX_KERNEL.tar.xz"
	if ! $DRYRUN; then
	    rm linux-$LINUX_KERNEL.tar.xz
	fi
    fi
    KERNEL_PACKAGES=$(ls linux-image-${KERNEL_NAME}*.deb linux-image-${KERNEL_ALT_NAME}*.deb)
    echo_log "remove kernel package(s) " $KERNEL_PACKAGES
    if ! $DRYRUN; then
	rm $KERNEL_PACKAGES
    fi
}


###########################################################################
# reboot:

function setup_kernel_param {
    if test -f /boot/grub/grubenv; then
	if ! $DRYRUN; then
	    grub-editenv - set rtai_cmdline="$*"
	fi
	if test -n "$*"; then
	    echo_log "set RTAI kernel parameter to \"$*\"."
	fi
    elif test -f /etc/default/grub; then
	echo_log "/boot/grub/grubenv not found: try /etc/default/grub"
	check_root
	if ! $DRYRUN; then
	    cd /etc/default
	    test -f grub.origkp && mv grub.origkp grub
	    cp grub grub.origkp
	    sed -e '/GRUB_CMDLINE_RTAI/s/=".*"/="'"$*"'"/' grub.origkp > grub
	    update-grub
	fi
	if test -n "$*"; then
	    echo_log "set RTAI kernel parameter to \"$*\"."
	fi
    else
	echo_log "/boot/grub/grubenv and /etc/default/grub not found: cannot set RTAI kernel parameter"
    fi
}

function restore_kernel_param {
    if test -f /boot/grub/grubenv; then
	echo_log "Remove RTAI kernel parameter from grubenv."
	if ! $DRYRUN; then
	    grub-editenv - unset rtai_cmdline
	fi
    fi
    if test -f /etc/default/grub.origkp; then
	echo_log "Restore original RTAI kernel parameter in /etc/default/grub."
	if ! $DRYRUN; then
	    cd /etc/default
	    mv grub.origkp grub
	    update-grub
	fi
    fi
}

function reboot_set_kernel {
# tell grub to reboot into a specific kernel
# if no grub menu entry is specified boot into the rtai kernel
    if ! $DRYRUN; then
	GRUBMENU="$1"
	if test -z "$GRUBMENU"; then
	    GRUBMENU="$(grep '^\s*menuentry ' /boot/grub/grub.cfg | cut -d "'" -f 2 | grep "${LINUX_KERNEL}.*-${RTAI_DIR}${KERNEL_NUM}" | head -n 1)"
	fi
	grub-reboot "$GRUBMENU" || /usr/sbin/grub-reboot "$GRUBMENU" || /sbin/grub-reboot "$GRUBMENU"
    fi
    echo_log "reboot into grub menu $GRUBMENU"
}

function reboot_unset_kernel {
    # make sure to boot into default kernel:
    if test -f /boot/grub/grubenv; then
	if grub-editenv - list | grep -q next_entry; then
	    if ! $DRYRUN; then
		grub-editenv - unset next_entry
		echo_log "unset next_entry from grubenv file"
	    fi
	fi
	echo_log "reboot into default grub menu entry"
    else
	echo_log "failed to reset default boot kernel (/boot/grub/grubenv not available)"
    fi
}

function reboot_cmd {
# reboot the computer

# reboot -f   # cold start
# reboot      # calls shutdown -r
# shutdown brings the system into the reuested runlevel (init 0/6)
# shutdown -r # reboot in a minute   
# shutdown -r now
# shutdown -r +<minutes>

    echo_log "reboot now"
    echo_log "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    if ! $DRYRUN; then
	if test "x$1" = "xcold"; then
	    echo_kmsg "REBOOT COLD (reboot -f)"
	    reboot -f
	elif test "x$(id -u)" != "x0"; then
	    if qdbus --version &> /dev/null; then
		qdbus org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 1 2 && return
	    fi
	    if gnome-session-quit --version &> /dev/null; then
		gnome-session-quit --reboot --force && return
	    fi
	    check_root
	    shutdown -r now
	else
	    if test -r /boot/grub/grubenv; then
		echo_kmsg "GRUB ENVIRONMENT:"
		grub-editenv - list | while read LINE; do echo_kmsg "$LINE"; done
	    fi
	    echo_kmsg "REBOOT (shutdown -r now)"
	    shutdown -r now
	fi
    fi
}

function reboot_kernel {
# default: boot into default kernel
# N      : boot into Nth kernel
# keep   : boot into rtai kernel and keep previous set kernel parameter 
# none   : boot into rtai kernel without additional kernel parameter
# ""     : boot into rtai kernel with additional kernel parameter as specified by KERNEL_PARAM
# XXX    : boot into rtai kernel with additional kernel parameter XXX
# FILE   : boot into rtai kernel with kernel parameter taken from test results file FILE
    echo_log ""
    chown --reference=. "$LOG_FILE"
    case $1 in
	default)
	    reboot_unset_kernel
	    sleep 2
	    reboot_cmd
	    ;;

	[0-9]*)
	    reboot_set_kernel "$1"
	    sleep 2
	    reboot_cmd
	    ;;

	keep)
	    reboot_set_kernel
	    sleep 2
	    reboot_cmd
	    ;;

	none)
	    setup_kernel_param ""
	    reboot_set_kernel
	    sleep 2
	    reboot_cmd
	    ;;

	*)
	    if test -z "$*"; then
		setup_kernel_param $KERNEL_PARAM
	    elif test -f "$1"; then
		setup_kernel_param $(sed -n -e '/Kernel parameter/,/CPU topology/p' "$1" | \
		    sed -e '1d; $d; s/^  //;' | \
		    sed -e '/BOOT/d; /^root/d; /^ro$/d; /^quiet/d; /^splash/d; /^vt.handoff/d; /panic/d;')
	    else
		setup_kernel_param $*
	    fi
	    reboot_set_kernel
	    sleep 2
	    reboot_cmd
	    ;;
    esac
    exit 0
}


###########################################################################
# tests:

function test_result {
    TESTMODE="$1"
    TEST_RESULT=""
    if test -n "$TESTMODE" && test -f "results-${TESTMODE}-latency.dat"; then
	N_DATA=$(grep RTD results-${TESTMODE}-latency.dat | wc -l)
	if test $N_DATA -lt 1; then
	    TEST_RESULT="failed"
	else
	    LINE=20
	    test "$N_DATA" -lt 60 && LINE=10
	    test "$N_DATA" -lt 20 && LINE=1
	    read LATENCY OVERRUNS < <(awk -F '\\|[ ]*' "/RTD/ {
            nd++
            if ( nd == $LINE ) {
                overruns0 = \$7
                maxjitter = \$5-\$2
            }
            if ( nd>$LINE ) { 
                overruns1 = \$7
                jitter = \$5-\$2
                if ( maxjitter < jitter ) { 
                    maxjitter = jitter }
            } 
        } END {printf(\"%.0f %d\n\", maxjitter, overruns1-overruns0)}" results-${TESTMODE}-latency.dat)
	    if test "$OVERRUNS" -gt "0"; then
		TEST_RESULT="failed"
	    else
		if test "$LATENCY" -gt 20000; then
		    TEST_RESULT="bad"
		elif test "$LATENCY" -gt 10000; then
		    TEST_RESULT="ok"
		elif test "$LATENCY" -gt 2000; then
		    TEST_RESULT="good"
		else
		    TEST_RESULT="perfect"
		fi
	    fi
	fi
    else
	TEST_RESULT="missing"
    fi
    echo $TEST_RESULT
}

function test_save {
    NAME="$1"
    REPORT="$2"
    TESTED="$3"
    PROGRESS="$4"
    CPU_ID="$5"
    CPUDATA="$6"
    HARDWARE="$7"
    {
	# summary analysis of test results:
	echo "Test summary (in nanoseconds):"
	echo
	# header 1:
	printf "RTH| %-50s| " "general"
	for TD in kern kthreads user; do
	    printf "%-41s| %-19s| %-31s| " "$TD latencies" "$TD switches" "$TD preempt"
	done
	printf "%s\n" "kernel"
	# header 2:
	printf "RTH| %-40s| %-8s| " "description" "progress"
	for TD in kern kthreads user; do
	    printf "%7s| %7s| %7s| %5s| %7s| %5s| %5s| %5s| %9s| %9s| %9s| " "ovlmax" "avgmax" "std" "n" "maxover" "susp" "sem" "rpc" "max" "jitfast" "jitslow"
	done
	printf "%s\n" "configuration"
	# data:
	printf "RTD| %-40s| %-8s| " "$NAME" "$PROGRESS"
	for TD in kern kthreads user; do
	    T=${TD:0:1}
	    test "$TD" = "kthreads" && T="t"
	    TN=latency
	    TEST_RESULTS=results-$TD-$TN.dat
	    if test -f "$TEST_RESULTS"; then
		N_DATA=$(grep RTD "$TEST_RESULTS" | wc -l)
		LINE=20
		test "$N_DATA" -lt 60 && LINE=10
		test "$N_DATA" -lt 20 && LINE=1
		awk -F '\\|[ ]*' "/RTD/ {
                    nd++
                    if ( nd == $LINE )
                        ors0=\$7
                    if ( nd >= $LINE ) {
                        d=\$5-\$2
                        sum+=d
                        sumsq+=d*d
                        n++
                        if ( maxd<d )
                            maxd=d
                        if (ors<\$7)
                            ors=\$7
                    } }
                END { if ( n > 0 ) {
                        mean = sum/n
                        printf( \"%7.0f| %7.0f| %7.0f| %5d| %7d| \", maxd, mean, sqrt(sumsq/n-mean*mean), n, ors-ors0 )
                    } }" "$TEST_RESULTS"
	    elif [[ $TESTED == *${T}* ]]; then
		printf "%7s| %7s| %7s| %5s| %7s| " "o" "o" "o" "o" "o"
	    else
		printf "%7s| %7s| %7s| %5s| %7s| " "-" "-" "-" "-" "-"
	    fi
	    TN=switches
	    TEST_RESULTS=results-$TD-$TN.dat
	    if test -f "$TEST_RESULTS" && test "$(grep -c 'SWITCH TIME' "$TEST_RESULTS")" -eq 3; then
		grep 'SWITCH TIME' "$TEST_RESULTS" | awk '{ printf( "%5.0f| ", $(NF-1) ); }'
	    elif [[ $TESTED == *${T}* ]]; then
		printf "%5s| %5s| %5s| " "o" "o" "o"
	    else
		printf "%5s| %5s| %5s| " "-" "-" "-"
	    fi
	    TN=preempt
	    TEST_RESULTS=results-$TD-$TN.dat
	    if test -f "$TEST_RESULTS"; then
		awk -F '\\|[ ]*' '/RTD/ { 
                    maxd=$4-$2
                    jfast=$5
                    jslow=$6 }
                END { 
                    printf( "%9.0f| %9.0f| %9.0f| ", maxd, jfast, jslow ) 
                }' "$TEST_RESULTS"
	    elif [[ $TESTED == *${T}* ]]; then
		printf "%9s| %9s| %9s| " "o" "o" "o"
	    else
		printf "%9s| %9s| %9s| " "-" "-" "-"
	    fi
	done
	printf "%s\n" "config-$REPORT"
	echo
	# failed modules:
	if [[ $TESTED == *h* ]] && [[ $PROGRESS != *h* ]]; then
	    echo "Failed to load rtai_hal module"
	    echo
	fi
	if [[ $TESTED == *s* ]] && [[ $PROGRESS != *s* ]]; then
	    echo "Failed to load rtai_sched module"
	    echo
	fi
	if [[ $TESTED == *m* ]] && [[ $PROGRESS != *m* ]]; then
	    echo "Failed to load rtai_math module"
	    echo
	fi
	if [[ $TESTED == *c* ]] && [[ $PROGRESS != *c* ]]; then
	    echo "Failed to load kcomedilib module"
	    echo
	fi
	# date:
	echo "Date: $(date '+%F')"
	echo
	# load processes:
	echo "Load: $(cut -d ' ' -f 1-3 /proc/loadavg)"
	if test -f load.dat; then
	    sed -e 's/^[ ]*load[ ]*/  /' load.dat
	fi
	echo
	# original test results:
	for TD in kern kthreads user; do
	    for TN in latency switches preempt; do
		TEST_RESULTS=results-$TD-$TN.dat
		if test -f "$TEST_RESULTS"; then
		    echo "$TD/$TN test:"
		    sed -e '/^\*/d' $TEST_RESULTS
		    echo "----------------------------------------"
		    echo
		    echo
		fi
	    done
	done
	print_kernel_info $CPU_ID $CPUDATA
	echo
	if test "x$HARDWARE" == "xhardware" && lshw -version &> /dev/null; then
	    echo "Hardware (lshw):"
	    lshw | sed '1d'
	    echo
	fi
	echo "rtai-info reports:"
	${REALTIME_DIR}/bin/rtai-info | sed -e '1,3d; 5d' | indent
	echo
	echo "dmesg:"
	echo
	dmesg | tac | sed '/MAKERTAIKERNEL.SH.*START/q' | tac | sed -n '/MAKERTAIKERNEL.SH.*START/,/MAKERTAIKERNEL.SH.*DONE/p'
    } > latencies-$REPORT
    cp /boot/config-${KERNEL_NAME} config-$REPORT
    chown --reference=. latencies-$REPORT
    chown --reference=. config-$REPORT
}

function test_run {
    DIR=$1
    TEST=$2
    TEST_TIME=$3
    TEST_RESULTS=results-$DIR-$TEST.dat
    TEST_DIR=${REALTIME_DIR}/testsuite/$DIR/$TEST
    rm -f $TEST_RESULTS
    if test -d $TEST_DIR; then
	echo_log "running $DIR/$TEST test"
	echo_kmsg "RUN $DIR/$TEST test"
	cd $TEST_DIR
	rm -f $TEST_RESULTS

	# setup automatic test duration:
	TTIME=$TEST_TIME
	if test -n "$TEST_TIME" && test $TEST = switches; then
	    TTIME=10
	    test $DIR = user && TTIME=""
	fi
	if test -n "$TEST_TIME" && test $TEST = preempt && test $TEST_TIME -gt 10; then
	    TTIME=10
	fi
	TIMEOUTCMD=""
	if test -n "$TTIME"; then
	    TIMEOUTCMD="timeout -s SIGINT -k 1 $TTIME"
	fi

	# run the test:
	trap true SIGINT   # ^C should terminate ./run but not this script
	$TIMEOUTCMD ./run | tee $TEST_RESULTS
	#script -c "$TIMEOUTCMD ./run" results.dat
	trap - SIGINT
	#sed -e '1d; $d; s/\^C//' results.dat > $TEST_RESULTS
	#rm results.dat
	cd - > /dev/null
	mv $TEST_DIR/$TEST_RESULTS .
	echo
    fi
}

function test_kernel {
    check_root

    echo_log "Test kernel ..."
    chown --reference=. "$LOG_FILE"

    # check for kernel log messages:
    if ! test -f /var/log/messages; then
	echo_kmsg "EXIT TEST BECAUSE /var/log/messages DOES NOT EXIST"
	echo_log "/var/log/messages does not exist!"
	echo_log "enable it by running:"
	echo_log "$ ./${MAKE_RTAI_KERNEL} setup messages"
	echo_log
	exit 1
    fi

    # test targets:
    TESTMODE=""
    LOADMODE=""
    CPUIDS=""
    LATENCY=false
    CPULATENCY=false
    CPULATENCYALL=true
    CPUGOVERNOR=false
    MAXMODULE="5"
    CALIBRATE="false"
    DESCRIPTION=""
    TESTSPECS=""
    TEST_TIME="${TEST_TIME_DEFAULT}"
    while test -n "$1"; do
	TESTSPECS="$TESTSPECS $1"
	case $1 in
	    hal) MAXMODULE="1" ;;
	    sched) MAXMODULE="2" ;;
	    math) MAXMODULE="3" ;;
	    comedi) MAXMODULE="4" ;;
	    kern) TESTMODE="$TESTMODE kern" ;;
	    kthreads) TESTMODE="$TESTMODE kthreads" ;;
	    user) TESTMODE="$TESTMODE user" ;;
	    all) TESTMODE="kern kthreads user" ;;
	    none) TESTMODE="none" ;;
	    calib) CALIBRATE="true" ;;
	    cpu) LOADMODE="$LOADMODE cpu" ;;
	    io) LOADMODE="$LOADMODE io" ;;
	    mem) LOADMODE="$LOADMODE mem" ;;
	    net) LOADMODE="$LOADMODE net" ;;
	    full) LOADMODE="cpu io mem net" ;;
	    cpu=*) CPUIDS="${1#cpu=}" ;;
	    cpulatency) CPULATENCY=true; CPULATENCYALL=false; LATENCY=false ;;
	    cpulatencyall) CPULATENCY=true; CPULATENCYALL=true; LATENCY=false ;;
	    latency) LATENCY=true; CPULATENCY=false ;;
	    performance) CPUGOVERNOR=true ;;
	    [0-9]*) TEST_TIME="$((10#$1))" ;;
	    auto) shift; test -n "$1" && { DESCRIPTION="$1"; TESTSPECS="$TESTSPECS $1"; } ;;
	    batch) shift; test_batch "$1" "$TEST_TIME" "$TESTMODE" ${TESTSPECS% batch} ;;
	    batchscript) shift; test_batch_script ;;
	    *) echo_log "test $1 is invalid"
		exit 1 ;;
	esac
	shift
    done
    test -z "$TESTMODE" && TESTMODE="kern"
    TESTMODE=$(echo $TESTMODE)  # strip whitespace
    LOADMODE=$(echo $LOADMODE)  # strip whitespace

    if test ${CURRENT_KERNEL} != ${KERNEL_NAME} && test ${CURRENT_KERNEL} != ${KERNEL_ALT_NAME}; then
	echo_kmsg "EXIT TEST BECAUSE OF RUNNING KERNEL DOES NOT MATCH CONFIGURATION"
	echo_log "Need a running rtai kernel that matches the configuration of ${MAKE_RTAI_KERNEL}!"
	echo_log
	echo_log "Either boot into the ${KERNEL_NAME} kernel, e.g. by executing"
	echo_log "$ ./${MAKE_RTAI_KERNEL} reboot"
	echo_log "or supply the right parameter to ${MAKE_RTAI_KERNEL}."
	echo_log
	echo_log "Info:"
	echo_log "  Your running kernel is: ${CURRENT_KERNEL}"
	echo_log "  LINUX_KERNEL is set to ${LINUX_KERNEL}"
	echo_log "  RTAI_DIR is set to ${RTAI_DIR}"
	echo_log "  KERNEL_NUM is set to $KERNEL_NUM"
	echo_log "Change these variables in your ${MAKE_RTAI_CONFIG} configuration file."
	return 1
    fi

    if $DRYRUN; then
	echo "run some tests on currently running kernel ${KERNEL_NAME}"
	echo "  test mode(s)             : $TESTMODE"
	echo "  max module to load       : $MAXMODULE"
	echo "  apply load               : $LOADMODE"
	echo "  CPU ids                  : $CPUIDS"
	echo "  Limit global CPU latency : $LATENCY"
	echo "  Limit CPU latency via QoS: $CPULATENCY"
	echo "            ... on all CPUs: $CPULATENCYALL"
	echo "  Set CPU freq governor    : $CPUGOVERNOR"
	echo "  rtai_sched parameter     : $RTAI_SCHED_PARAM"
	echo "  rtai_hal parameter       : $RTAI_HAL_PARAM"
	echo "  description              : $DESCRIPTION"
	return 0
    fi

    # remove old test results:
    for TD in kern kthreads user; do
	for TN in latency switches preempt; do
	    TEST_RESULTS=results-$TD-$TN.dat
	    rm -f $TEST_RESULTS
	done
    done
    rm -f load.dat
    rm -f lsmod.dat

    # report number:
    REPORT_NAME=$(hostname)-${RTAI_DIR}-${LINUX_KERNEL}
    NUM=001
    LASTREPORT="$(ls latencies-${REPORT_NAME}-*-* 2> /dev/null | tail -n 1)"
    if test -n "$LASTREPORT"; then
	LASTREPORT="${LASTREPORT#latencies-${REPORT_NAME}-}"
	N="${LASTREPORT%%-*}"
	N=$(expr $N + 1)
	NUM="$(printf "%03d" $N)"
    fi

    echo_kmsg "PREPARE TESTS NUM $NUM $DESCRIPTION"

    if $CALIBRATE; then
	# remove latency file to force calibration:
	# this is for rtai5, for rtai4 the calibration tools needs to be run manually
	# see base/arch/x86/calibration/README
	if test -f ${REALTIME_DIR}/calibration/latencies; then
	    rm ${REALTIME_DIR}/calibration/latencies
	fi
    else
	# if not calibrated yet, provide default latencies:
	if ! test -f ${REALTIME_DIR}/calibration/latencies; then
	    RTAI_SCHED_PARAM="$RTAI_SCHED_PARAM kernel_latency=0 user_latency=0"
	fi
    fi

    # description of kernel configuration:
    if test -z "$DESCRIPTION"; then
	read -p 'Please enter a short name describing the kernel configuration (empty: abort tests now, "n": do not save test results): ' NAME
	test -z "$NAME" && return 0
	test "$NAME" = "n" && DESCRIPTION="n"
    else
	NAME="$DESCRIPTION"
    fi

    # unload already loaded comedi kernel modules:
    remove_comedi_modules
    # unload already loaded rtai kernel modules:
    for MOD in msg mbx fifo sem math sched hal; do
	lsmod | grep -q rtai_$MOD && { rmmod rtai_$MOD && echo_log "removed already loaded rtai_$MOD"; }
    done

    # add CPU mask:
    CPU_ID=0
    if test -n "$CPUIDS"; then
	CPU_ID=${CPUIDS%%,*}
	NAME="${NAME}-cpu${CPU_ID}"
	if ! setup_rtai "$CPUIDS"; then
	    echo_kmsg "SETUP_RTAI FAILED BECAUSE NO VALID CPU IDS WERE SPECIFIED"
	    return 1
	fi
    fi

    echo_log
    TESTED=""
    PROGRESS=""
    echo_kmsg "START TESTS"

    # limit global CPU latency:
    if $LATENCY; then
	if test -c /dev/cpu_dma_latency; then
	    echo_log "Write zero to /dev/cpu_dma_latency ."
	    NAME="${NAME}-nolatency"
	    exec 5> /dev/cpu_dma_latency
	    echo -n -e "\x00\x00\x00\x00" >&5
	else
	    echo_log "File /dev/cpu_dma_latency does not exist."
	    LATENCY=false
	fi
    fi

    # limit CPU latency via PM QoS:
    if $CPULATENCY; then
	if test -d cpulatency; then
	    echo_log "Build and insmod cpulatency kernel module."
	    cd cpulatency
	    make clean
	    make
	    CPU_IDP=""
	    ! $CPULATENCYALL && test -n "$CPUIDS" && CPU_IDP="cpu_id=${CPU_ID}"
	    if insmod cpulatency.ko $CPU_IDP; then
		sleep 1
		CPUID=$(grep -a cpulatency /var/log/messages | tail -n 1 | sed -e 's/^.*CPU=//')
		case CPUID in
		    all ) 
			NAME="${NAME}-nocpulatency"
			echo_log "Set latency of all CPUs to zero via cpulatency kernel module."
			;;
		    none ) 
			echo_log "Failed to set latency of CPUs via cpulatency kernel module."
			;;
		    *) 
			NAME="${NAME}-nocpulatency${CPUID}"
			echo_log "Set latency of CPU ${CPUID} to zero via cpulatency kernel module."
			;;
		esac 
	    else
		CPULATENCY=false
		echo_log "Inserting cpulatency kernel module failed."
	    fi
	    cd - > /dev/null
	else
	    CPULATENCY=false
	fi
    fi

    # set CPU freq governor:
    if $CPUGOVERNOR; then
	GOVERNOR=""
	SCALING_GOVERNOR="/sys/devices/system/cpu/cpu${CPU_ID}/cpufreq/scaling_governor"
	if test -r $SCALING_GOVERNOR; then
	    echo_log "Set cpu freq performance governor for CPU ${CPU_ID} ."
	    NAME="${NAME}-performance"
	    GOVERNOR="$(cat $SCALING_GOVERNOR)"
	    exec 6> $SCALING_GOVERNOR
	    echo "performance" >&6
	else
	    echo_log "Cannot set cpu freq governor."
	    CPUGOVERNOR=false
	fi
    fi

    # add load information to description:
    if test -n "$LOADMODE"; then
	NAME="${NAME}-"
	for LOAD in $LOADMODE; do
	    NAME="${NAME}${LOAD:0:1}"
	done
    else
	NAME="${NAME}-idle"
    fi

    REPORT_NAME="${REPORT_NAME}-${NUM}-$(date '+%F')-${NAME}"
    REPORT="${REPORT_NAME}-failed"

    # store CPU info
    store_cpus 0

    # loading rtai kernel modules:
    RTAIMOD_FAILED=false

    # rtai_hal:
    if test $MAXMODULE -ge 1; then
	TESTED="${TESTED}h"
	test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"
	echo_kmsg "INSMOD ${REALTIME_DIR}/modules/rtai_hal.ko $RTAI_HAL_PARAM"
	lsmod | grep -q rtai_hal || { insmod ${REALTIME_DIR}/modules/rtai_hal.ko $RTAI_HAL_PARAM && echo_log "loaded rtai_hal $RTAI_HAL_PARAM" || RTAIMOD_FAILED=true; }
	$RTAIMOD_FAILED || PROGRESS="${PROGRESS}h"
    fi

    # rtai_sched:
    if test $MAXMODULE -ge 2; then
	TESTED="${TESTED}s"
	test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"
	echo_kmsg "INSMOD ${REALTIME_DIR}/modules/rtai_sched.ko $RTAI_SCHED_PARAM"
	lsmod | grep -q rtai_sched || { insmod ${REALTIME_DIR}/modules/rtai_sched.ko $RTAI_SCHED_PARAM && echo_log "loaded rtai_sched $RTAI_SCHED_PARAM" || RTAIMOD_FAILED=true; }
	$RTAIMOD_FAILED || PROGRESS="${PROGRESS}s"
    fi

    # rtai_math:
    if test $MAXMODULE -ge 3; then
	if test -f ${REALTIME_DIR}/modules/rtai_math.ko; then
	    TESTED="${TESTED}m"
	    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"
	    echo_kmsg "INSMOD ${REALTIME_DIR}/modules/rtai_math.ko"
	    lsmod | grep -q rtai_math || { insmod ${REALTIME_DIR}/modules/rtai_math.ko && echo_log "loaded rtai_math" && PROGRESS="${PROGRESS}m"; }
	else
	    echo_log "rtai_math is not available"
	fi
    fi
    
    if test $MAXMODULE -ge 4 && $MAKE_COMEDI && ! $RTAIMOD_FAILED; then
	TESTED="${TESTED}c"
	test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"
	# loading comedi:
	echo_kmsg "LOAD COMEDI MODULES"
	echo_log "triggering comedi "
	udevadm trigger
	sleep 1
	modprobe kcomedilib && echo_log "loaded kcomedilib"

	lsmod | grep -q kcomedilib && PROGRESS="${PROGRESS}c"
	
	lsmod > lsmod.dat
	
	echo_kmsg "REMOVE COMEDI MODULES"
	remove_comedi_modules
    fi
    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"
    
    # remove rtai modules:
    if test $MAXMODULE -ge 3; then
	echo_kmsg "RMMOD rtai_math"
	lsmod | grep -q rtai_math && { rmmod rtai_math && echo_log "removed rtai_math"; }
    fi
    if test $MAXMODULE -ge 2; then
	echo_kmsg "RMMOD rtai_sched"
	lsmod | grep -q rtai_sched && { rmmod rtai_sched && echo_log "removed rtai_sched"; }
    fi
    if test $MAXMODULE -ge 1; then
	echo_kmsg "RMMOD rtai_hal"
	lsmod | grep -q rtai_hal && { rmmod rtai_hal && echo_log "removed rtai_hal"; }
    fi

    # loading modules failed:
    if $RTAIMOD_FAILED; then
	echo_log "Failed to load RTAI modules."
	echo_log
	if test -z "$DESCRIPTION"; then
	    read -p 'Save configuration? (y/N): ' SAVE
	else
	    SAVE="n"
	fi
	if test "$SAVE" = "y"; then
	    echo_log
	    echo_log "saved kernel configuration in: config-$REPORT"
	    echo_log "saved test results in        : latencies-$REPORT"
	else
	    rm -f config-$REPORT
	    rm -f latencies-$REPORT
	fi
	return 1
    fi
    echo_log "successfully loaded and unloaded rtai modules"
    echo_log

    # RTAI tests:
    if test "$TESTMODE" != none; then
	# stress program available?
	STRESS=false
	stress --version &> /dev/null && STRESS=true
	# produce load:
	JOB_NUM=$CPU_NUM
	LOAD_JOBS=$(echo $LOADMODE | wc -w)
	if test $LOAD_JOBS -gt 1; then
	    let JOB_NUM=$CPU_NUM/$LOAD_JOBS
	    test $JOB_NUM -le 1 && JOB_NUM=2
	fi
	LOAD_PIDS=()
	LOAD_FILES=()
	test -n "$LOADMODE" && echo_log "start some jobs to produce load:"
	for LOAD in $LOADMODE; do
	    case $LOAD in
		cpu) if $STRESS; then
	                echo_log "  load cpu: stress -c $JOB_NUM" | tee -a load.dat
			stress -c $JOB_NUM &> /dev/null &
			LOAD_PIDS+=( $! )
                    else
	                echo_log "  load cpu: seq $JOB_NUM | xargs -P0 -n1 md5sum /dev/urandom" | tee -a load.dat
			seq $JOB_NUM | xargs -P0 -n1 md5sum /dev/urandom & 
			LOAD_PIDS+=( $! )
                    fi
		    ;;
		io) if $STRESS; then
	                echo_log "  load io : stress --hdd-bytes 128M -d $JOB_NUM" | tee -a load.dat
			stress --hdd-bytes 128M -d $JOB_NUM &> /dev/null &
			LOAD_PIDS+=( $! )
		    else
		        echo_log "  load io : ls -lR" | tee -a load.dat
			while true; do ls -lR / &> load-lsr; done & 
			LOAD_PIDS+=( $! )
			LOAD_FILES+=( load-lsr )
			echo_log "  load io : find" | tee -a load.dat
			while true; do find / -name '*.so' &> load-find; done & 
			LOAD_PIDS+=( $! )
			LOAD_FILES+=( load-find )
		    fi
		    ;;
		mem) if $STRESS; then
	                echo_log "  load mem: stress -m $JOB_NUM" | tee -a load.dat
			stress -m $JOB_NUM &> /dev/null &
			LOAD_PIDS+=( $! )
		    else
		        echo_log "  load mem: no test available"
		    fi
		    ;;
		net) echo_log "  load net: ping -f localhost" | tee -a load.dat
		    ping -f localhost > /dev/null &
		    LOAD_PIDS+=( $! )
		    ;;
		snd) echo_log "  load snd: not implemented yet!" ;;
	    esac
	done
	test -n "$LOADMODE" && echo_log

	store_cpus 0

	# run tests:
	for DIR in $TESTMODE; do
	    TT=${DIR:0:1}
	    test "$DIR" = "kthreads" && TT="t"
	    TESTED="${TESTED}${TT}"
	    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID"

	    test_run $DIR latency $TEST_TIME
	    print_environment "$CPU_ID" > results-cpus.dat
	    print_cpus >> results-cpus.dat
	    if test $DIR = ${TESTMODE%% *}; then
		rm -f config-$REPORT
		rm -f latencies-$REPORT
		TEST_RESULT="$(test_result ${TESTMODE%% *})"
		REPORT="${REPORT_NAME}-${TEST_RESULT}"
	    fi
	    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID" results-cpus.dat

	    test_run $DIR switches $TEST_TIME
	    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID" results-cpus.dat

	    test_run $DIR preempt $TEST_TIME
	    PROGRESS="${PROGRESS}${TT}"
	    test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID" results-cpus.dat
	done
    else
	print_environment "$CPU_ID" > results-cpus.dat
	print_cpus >> results-cpus.dat
    fi

    # clean up load:
    for PID in ${LOAD_PIDS[@]}; do
	kill -KILL $PID $(ps -o pid= --ppid $PID)
    done
    for FILE in ${LOAD_FILES[@]}; do
	rm -f $FILE
    done

    # clean up RTAI modules:
    for MOD in msg mbx fifo sem math sched hal; do
	lsmod | grep -q rtai_$MOD && { rmmod rtai_$MOD && echo_log "removed loaded rtai_$MOD"; }
    done

    # restore global CPU latency:
    if $LATENCY; then
	echo_log "Close /dev/cpu_dma_latency file."
	exec 5>&-
    fi

    # restore CPU latency via PM QoS:
    if $CPULATENCY; then
	echo_log "Remove cpulatency kernel module."
	rmmod cpulatency
	# clean because me made it as root:
	cd cpulatency
	make clean
	cd - > /dev/null
    fi

    # restore CPU freq governor:
    if $CPUGOVERNOR; then
	echo_log "Restore cpu freq performance governor to $GOVERNOR ."
	echo "$GOVERNOR" >&6
	exec 6>&-
    fi

    # restore CPU mask:
    if test -n "$CPUIDS"; then
	restore_rtai
    fi

    echo_kmsg "TESTS DONE"
    echo_log "finished all tests for $NAME"
    echo_log
    
    # report:
    rm -f config-$REPORT
    rm -f latencies-$REPORT
    TEST_RESULT="$(test_result ${TESTMODE%% *})"
    if test -z "$DESCRIPTION"; then
	read -p "Please enter a short description of the test result (empty: $TEST_RESULT, n: don't save): " RESULT
	test -z "$RESULT" && RESULT="$TEST_RESULT"
	echo_log
    elif test "$DESCRIPTION" = "n"; then
	RESULT="n"
    else
	RESULT="$TEST_RESULT"
    fi
    if test "$RESULT" != n; then
	REPORT="${REPORT_NAME}-${RESULT}"
	test_save "$NAME" "$REPORT" "$TESTED" "$PROGRESS" "$CPU_ID" results-cpus.dat hardware
	echo_log "saved kernel configuration in : config-$REPORT"
	echo_log "saved test results in         : latencies-$REPORT"
    else
	echo_log "test results not saved"
    fi

    # remove test results:
    for TD in kern kthreads user; do
	for TN in latency switches preempt; do
	    TEST_RESULTS=results-$TD-$TN.dat
	    rm -f $TEST_RESULTS
	done
    done
    rm -f results-cpus.dat
    rm -f results-cpu?????.dat
    rm -f load.dat
    rm -f lsmod.dat
}

function test_batch {
    # setup automatic testing of kernel parameter

    BATCH_FILE="$1"
    if test -z "$BATCH_FILE"; then
	echo "You need the specify a file that lists the kernel parameter to be tested:"
	echo "$ ./${MAKE_RTAI_KERNEL} batch FILE"
	exit 1
    fi

    # write default batch files:
    if ! test -f "$BATCH_FILE"; then
	DEFAULT_BATCHES="basics isolcpus nohzrcu dma cstates poll acpi apic"
	for DEFAULT_BATCH in $DEFAULT_BATCHES; do
	    if test "$BATCH_FILE" = "$DEFAULT_BATCH"; then
		BATCH_FILE=test${DEFAULT_BATCH}.mrk
		if test -f $BATCH_FILE; then
		    echo "File \"$BATCH_FILE\" already exists."
		    echo "Cannot write batch file for ${DEAFULT_BATCH} kernel parameter."
		    exit 1
		fi

		case $DEFAULT_BATCH in
		    basics) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with basic kernel parameter.
#
# Each line has the format:
# <description> : <load specification> : <kernel parameter>
# for specifying tests, where <description> is a brief one-word description of the kernel
# parameters that is added to the KERNEL_PARAM_DESCR variable.  
# The <kernel parameter> are added to the ones defined in the KERNEL_PARAM variable.
#
# Alternatively, lines of the following format specify a new kernel to be compiled:
# <description> : CONFIG : <config-file>
# <description> : CONFIG : backup
# where <config-file> is the file with the kernel configuration, 
# "backup" specifies the kernel configuration at the beginning of the tests,
# and <description> describes the kernel configuration for the following tests. 
# A line without a configuration file:
# <description> : CONFIG :
# just gives the current kernel configuration the name <description>.
#
# Edit this file according to your needs.
#
# Then run
#
# $ ./$MAKE_RTAI_KERNEL test math ${DEAFULT_BATCH} batch $BATCH_FILE
#
# for testing all the kernel parameter.
#
# The test results are recorded in the latencies-$(hostname)-${RTAI_DIR}-${LINUX_KERNEL}-* files.
#
# Generate and view a summary table of the test results by calling
#
# $ ./$MAKE_RTAI_KERNEL report | less -S

# without additional kernel parameter:
plain : :

# clocks and timers:
tscreliable : : tsc=reliable
tscnoirqtime : : tsc=noirqtime
highresoff : : highres=off
nohz : : nohz=off

# more clocks and timers in case you want to try:
#clocksourcehpet : : clocksource=hpet
#clocksourcetsc : : clocksource=tsc
#hpetdisable : : hpet=disable
#skewtick : : skew_tick=1
##nolapictimer : : nolapic_timer  # not good

# other candidates:
elevator : : elevator=noop
nowatchdog : : nosoftlockup=0
#nohalt : : nohalt # on IA-64 processors only

# test again to see variability of results:
plain : :
EOF
			;;

		    isolcpus) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with cpu isolation.
# Adapt the content of this file to the number of CPUs you have!

# standard cpu
plain : :
plain : full :

# non-isolated on cpu 0:
plain : cpu=0 :
plain : cpu=0 full :

# isolcpus on cpu 0:
isolcpus0 : cpu=0 : isolcpus=0
isolcpus0 : cpu=0 full : isolcpus=0

# non-isolated on cpu 1:
plain : cpu=1 :
plain : cpu=1 full :

# isolcpus on cpu 1:
isolcpus1 : cpu=1 : isolcpus=1
isolcpus1 : cpu=1 full : isolcpus=1

# non-isolated on cpu 2:
plain : cpu=2 :
plain : cpu=2 full :

# isolcpus on cpu 2:
isolcpus2 : cpu=2 : isolcpus=2
isolcpus2 : cpu=2 full : isolcpus=2

# non-isolated on cpu 3:
plain : cpu=3 :
plain : cpu=3 full :

# isolcpus on cpu 3:
isolcpus3 : cpu=3 : isolcpus=3
isolcpus3 : cpu=3 full : isolcpus=3
EOF
			;;

		    nohzrcu) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with cpu isolation.
## Replace all "=1" by the index of your best CPU from the isolcpus tests.

# isolcpus on cpu 1 + nohz_full:
isolcpus1-nohz : cpu=1 : isolcpus=1 nohz_full=1
isolcpus1-nohz : cpu=1 full : isolcpus=1 nohz_full=1

# isolcpus on cpu 1 + nohz_full +  rcu_nocbs:
isolcpus1-nohz-rcu : cpu=1 : isolcpus=1 nohz_full=1 rcu_nocbs=1
isolcpus1-nohz-rcu : cpu=1 full : isolcpus=1 nohz_full=1 rcu_nocbs=1
EOF
			;;

		    dma) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# batch file for testing RTAI kernel with and without DMA.
# Replace all "=1" by the index of the cpu you want to isolate.

# non-isolated
plain : cpu=1 io :
nodma : cpu=1 io : libata.dma=0
#noidedma : cpu=1 io : ide-core.nodma=0.0 # read Documentation/kernel-parameters.txt

# isolcpus
isolcpus1 : cpu=1 io : isolcpus=1
nodma-isolcpus1 : cpu=1 io : libata.dma=0 isolcpus=1
#noidedma : cpu=1 io : ide-core.nodma=0.0 isolcpus=1 # read Documentation/kernel-parameters.txt
EOF
			;;

		    cstates) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with kernel parameter related to processor c-states.
# You need to enable PM idle states in the kernel configuration.

# c-states:
plain : :
idlepoll : : idle=poll
idlehalt : : idle=halt
intelcstate1 : : intel_idle.max_cstate=1
processorcstate1 : : intel_idle.max_cstate=0 processor.max_cstate=1
processorcstate0 : : intel_idle.max_cstate=0 processor.max_cstate=0
nopstate : : intel_pstate=disable
EOF
			;;

		    poll) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# batch file for testing RTAI kernel with idle=poll and run-time alternatives.
# Run these tests with a specified CPU for the tests (e.g. cpu=1)

plain : :
poll : : idle=poll
plain : latency :        # write zero to /dev/cpu_dma_latency file
plain : cpulatencyall :  # use PM-QoS interface to request zero latency of all CPUs
plain : cpulatency :     # use PM-QoS interface to request zero latency of the selected CPU
poll : : idle=poll
EOF
			;;

		    acpi) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with various kernel parameter related to acpi.
# Use only if you are curious...

# acpi:
plain : :
#acpioff : : acpi=off    # often very effective, but weired system behavior
acpinoirq : : acpi=noirq
pcinoacpi : : pci=noacpi
pcinomsi : : pci=nomsi
EOF
			;;

		    apic) cat <<EOF > $BATCH_FILE
# $VERSION_STRING
# Batch file for testing RTAI kernel with various kernel parameter related to apic.
# Use only if you are curious...

# apic:
plain : :
noapic : : noapic
nox2apic : : nox2apic
x2apicphys : : x2apic_phys
lapic : : lapic
#nolapic : : nolapic    # we need the lapic timer!
#nolapic_timer : : nolapic_timer    # we need the lapic timer!
lapicnotscdeadl : : lapic=notscdeadline
EOF
			;;
		esac

		chown --reference=. $BATCH_FILE
		echo "Wrote default kernel parameter to be tested into file \"$BATCH_FILE\"."
		echo ""
		echo "Call test batch again with something like"
		echo "$ sudo ./${MAKE_RTAI_KERNEL} test ${TEST_TIME_DEFAULT} batch $BATCH_FILE"
		exit 0
	    fi
	done
	echo "File \"$BATCH_FILE\" does not exist!"
	exit 1
    fi

    # run batch file:
    N_TESTS=$(sed -e 's/ *#.*$//' $BATCH_FILE | grep -c ':.*:')
    N_COMPILE=$(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | grep -c CONFIG)
    IFS=':' read D M P < <(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | sed -n -e 1p)
    M=$(echo $M)
    P=$(echo $P)
    if test "x${M}" = "xCONFIG" && test -z "$P"; then
	let N_TESTS-=1
	let N_COMPILE-=1
    fi
    if test $N_TESTS -eq 0; then
	echo "No valid configurations specified in file \"$BATCH_FILE\"!"
	exit 1
    fi

    shift
    TEST_TIME="$((10#$1))"
    shift
    TESTMODE="$1"
    test -z "$TESTMODE" && TESTMODE="kern"
    TESTMODE=$(echo $TESTMODE)  # strip whitespace
    shift
    TEST_SPECS="$@"
    [[ "$TEST_SPECS" != *"$TEST_TIME"* ]] && TEST_SPECS="$TEST_SPECS $TEST_TIME"

    # compute total time needed for the tests:
    TEST_TOTAL_TIME=30
    for TM in $TESTMODE; do
	let TEST_TOTAL_TIME+=$TEST_TIME
	let TEST_TOTAL_TIME+=60
    done

    # overall time:
    let N=$N_TESTS-$N_COMPILE
    let TOTAL_TIME=$STARTUP_TIME+$COMPILE_TIME
    let OVERALL_TIME=${TOTAL_TIME}*${N_COMPILE}
    let TOTAL_TIME=$STARTUP_TIME+$TEST_TOTAL_TIME
    let OVERALL_TIME+=${TOTAL_TIME}*${N}
    let OVERALL_MIN=$OVERALL_TIME/60
    let OVERALL_HOURS=$OVERALL_MIN/60
    let OVERALL_MIN=$OVERALL_MIN%60
    OVERALL_TIME=$(printf "%dh%02dmin" $OVERALL_HOURS $OVERALL_MIN)

    echo_log "run \"test $TEST_SPECS\" on batch file \"$BATCH_FILE\" with content:"
    sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | while read LINE; do echo_log "  $LINE"; done
    echo_log
    chown --reference=. "$LOG_FILE"

    # read first line from configuration file:
    INDEX=1
    IFS=':' read DESCRIPTION LOAD_MODE NEW_KERNEL_PARAM < <(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | sed -n -e ${INDEX}p)
    DESCRIPTION="$(echo $DESCRIPTION)"
    LOAD_MODE="$(echo $LOAD_MODE)"
    NEW_KERNEL_PARAM="$(echo $NEW_KERNEL_PARAM)"
    # in case of a config line, this sets the description of the actual kernel configuration:
    KERNEL_DESCR=""
    if test "x${LOAD_MODE}" = "xCONFIG" && test -z "$NEW_KERNEL_PARAM"; then
	KERNEL_DESCR="$DESCRIPTION"
	# read next line from configuration file:
	let INDEX+=1
	IFS=':' read DESCRIPTION LOAD_MODE NEW_KERNEL_PARAM < <(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | sed -n -e ${INDEX}p)
	DESCRIPTION="$(echo $DESCRIPTION)"
	LOAD_MODE="$(echo $LOAD_MODE)"
	NEW_KERNEL_PARAM="$(echo $NEW_KERNEL_PARAM)"
    fi

    # report first batch entry:
    COMPILE=false
    if test "x${LOAD_MODE}" = "xCONFIG"; then
	COMPILE=true
	echo_log "Reboot into default kernel to compile kernel with \"$DESCRIPTION\" configuration."
    else
	COMPILE=false
	# assemble overall description:
	KD="${KERNEL_DESCR}"
	test -n "$KD" && test "${KD:-1:1}" != "-" && KD="${KD}-"
	KD="${KD}${KERNEL_PARAM_DESCR}"
	test -n "$KD" && test "${KD:-1:1}" != "-" && KD="${KD}-"
	# report next kernel parameter settings:
	echo_log "Reboot into first configuration: \"${KD}${DESCRIPTION}\" with kernel parameter \"$(echo $BATCH_KERNEL_PARAM $KERNEL_PARAM $NEW_KERNEL_PARAM)\""
    fi

    # confirm batch testing:
    echo_log
    read -p "Do you want to proceed testing with $N_TESTS reboots (approx. ${OVERALL_TIME}) (Y/n)? " PROCEED
    if test "x$PROCEED" != "xn"; then
	echo_log
	cp $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config $KERNEL_CONFIG_BACKUP
	echo_log "Saved kernel configuration in \"$KERNEL_CONFIG_BACKUP\"."
	restore_test_batch
	# install crontab:
	MRK_DIR="$(cd "$(dirname "$0")" && pwd)"
	(crontab -l 2>/dev/null; echo "@reboot ${MRK_DIR}/${MAKE_RTAI_KERNEL} test batchscript > ${TEST_DIR}/testbatch.log") | crontab -
	echo_log "Installed crontab for automatic testing after reboot."
	echo_log "  Uninstall by calling"
	echo_log "  $ ./${MAKE_RTAI_KERNEL} restore testbatch"
	echo_kmsg "START TEST BATCH $BATCH_FILE"

	# set information for next test/compile:
	if test -f /boot/grub/grubenv; then
	    echo_log "Set grub environment variables."
	    grub-editenv - set rtaitest_pwd="$PWD"
	    grub-editenv - set rtaitest_file="$BATCH_FILE"
	    grub-editenv - set rtaitest_index="$INDEX"
	    grub-editenv - set rtaitest_kernel_descr="$KERNEL_DESCR"
	    grub-editenv - set rtaitest_param_descr="$KERNEL_PARAM_DESCR"
	    grub-editenv - set rtaitest_time="$TEST_TOTAL_TIME"
	    grub-editenv - set rtaitest_specs="$TEST_SPECS"
	    grub-editenv - set rtaitest_state="reboot"
	else
	    echo_kmsg "NEXT TEST BATCH |$PWD|$BATCH_FILE|$INDEX|$KERNEL_DESCR|$KERNEL_PARAM_DESCR|$TEST_TOTAL_TIME|$TEST_SPECS"
	fi
	if $COMPILE; then
	    reboot_kernel default
	else
	    reboot_kernel $BATCH_KERNEL_PARAM $KERNEL_PARAM $NEW_KERNEL_PARAM
	fi
    else
	echo_log
	echo_log "Test batch aborted"
    fi

    exit 0
}

function test_abort {
    # no further tests:
    echo_kmsg "ABORT TEST BATCH"
    echo_log "Abort test batch."
    # clean up:
    echo_log "Clean up test batch:"
    restore_test_batch > /dev/null
    restore_kernel_param
    reboot_unset_kernel
    echo_log
}

function test_batch_script {
    # run automatic testing of kernel parameter.
    # this function is called automatically after reboot from cron.

    PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    # abort testing if the machine was manually booted:
    if test -f /boot/grub/grubenv; then
	TEST_STATE=$(grub-editenv - list | grep '^rtaitest_state=' | cut -d '=' -f 2-)
	if test "x$TEST_STATE" != "xreboot"; then
	    echo_kmsg "TEST WAS INTERRUPTED BY MANUAL BOOT"
	    echo_log "TEST WAS INTERRUPTED BY MANUAL BOOT"
	    test_abort
	    exit 1
	fi
	grub-editenv - set rtaitest_state="run"
    fi

    # get paramter for current test/compile:
    if test -f /boot/grub/grubenv; then
	WORKING_DIR="$(grub-editenv - list | grep '^rtaitest_pwd=' | cut -d '=' -f 2-)"
	BATCH_FILE="$(grub-editenv - list | grep '^rtaitest_file=' | cut -d '=' -f 2-)"
	INDEX="$(grub-editenv - list | grep '^rtaitest_index=' | cut -d '=' -f 2-)"
	KERNEL_DESCR="$(grub-editenv - list | grep '^rtaitest_kernel_descr=' | cut -d '=' -f 2-)"
	BATCH_DESCR="$(grub-editenv - list | grep '^rtaitest_param_descr=' | cut -d '=' -f 2-)"
	TEST_TOTAL_TIME="$(grub-editenv - list | grep '^rtaitest_time=' | cut -d '=' -f 2-)"
	TEST_SPECS="$(grub-editenv - list | grep '^rtaitest_specs=' | cut -d '=' -f 2-)"
    else
	MF=/var/log/messages
	grep -q -a -F "NEXT TEST BATCH" $MF || MF=/var/log/messages.1
	IFS='|' read ID WORKING_DIR BATCH_FILE INDEX KERNEL_DESCR BATCH_DESCR TEST_TOTAL_TIME TEST_SPECS < <(grep -a -F "NEXT TEST BATCH" $MF | tail -n 1)
    fi
    KERNEL_DESCR="$(echo $KERNEL_DESCR)"
    BATCH_DESCR="$(echo $BATCH_DESCR)"

    # working directory:
    cd "$WORKING_DIR"
    echo_kmsg "WORKING DIRECTORY IS $WORKING_DIR"

    N_TESTS=$(sed -e 's/ *#.*$//' $BATCH_FILE | grep -c ':.*:')

    # read configuration:
    source "${MAKE_RTAI_CONFIG}"
    set_variables

    # enable logs:
    LOG_FILE="${WORKING_DIR}/${MAKE_RTAI_KERNEL%.*}.log"
    echo_log
    echo_log "Automatically start test $INDEX of $N_TESTS in file \"$BATCH_FILE\" in directory \"$WORKING_DIR\"."
    echo_log
    chown --reference=. "$LOG_FILE"
    echo_kmsg "TEST $INDEX OF $N_TESTS IN FILE \"$BATCH_FILE\"."

    # read current DESCRIPTION and LOAD_MODE from configuration file:
    IFS=':' read DESCRIPTION LOAD_MODE NEW_KERNEL_PARAM < <(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | sed -n -e ${INDEX}p)
    DESCRIPTION="$(echo $DESCRIPTION)"
    LOAD_MODE="$(echo $LOAD_MODE)"
    NEW_KERNEL_PARAM="$(echo $NEW_KERNEL_PARAM)"
    # compile new kernel:
    COMPILE=false
    if test "x${LOAD_MODE}" = "xCONFIG"; then
	COMPILE=true
	KERNEL_DESCR="$DESCRIPTION"
    else
	# wait:
	echo_kmsg "WAIT FOR $STARTUP_TIME SECONDS"
	sleep $STARTUP_TIME
	echo_kmsg "FINISHED WAITING"
    fi

    # next:
    let INDEX+=1

    if test "$INDEX" -gt "$N_TESTS"; then
	# no further tests:
	echo_kmsg "LAST TEST BATCH"
	echo_log "Final test"
	# clean up:
	echo_log "Clean up test batch:"
	restore_test_batch > /dev/null
	restore_kernel_param
	echo_log
    else
	# read next test:
	IFS=':' read DESCR LM NEXT_KERNEL_PARAM < <(sed -e 's/ *#.*$//' $BATCH_FILE | grep ':.*:' | sed -n -e ${INDEX}p)
	# set information for next test/compile:
	if test -f /boot/grub/grubenv; then
	    grub-editenv - set rtaitest_index="$INDEX"
	    grub-editenv - set rtaitest_kernel_descr="$KERNEL_DESCR"
	else
	    echo_kmsg "NEXT TEST BATCH |$WORKING_DIR|$BATCH_FILE|$INDEX|$KERNEL_DESCR|$BATCH_DESCR|$TEST_TOTAL_TIME|$TEST_SPECS"
	fi
	LM="$(echo $LM)"
	NEXT_KERNEL_PARAM="$(echo $NEXT_KERNEL_PARAM)"
	if test "x${LM}" != "xCONFIG"; then
	    echo_log "Prepare next reboot:"
	    setup_kernel_param $BATCH_KERNEL_PARAM $KERNEL_PARAM $NEXT_KERNEL_PARAM
	    reboot_set_kernel
	    echo_log
	fi
    fi

    # working directory:
    cd "$WORKING_DIR"
    echo_kmsg "WORKING DIRECTORY STILL IS $WORKING_DIR"

    if $COMPILE; then
	if test -f /boot/grub/grubenv; then
	    grub-editenv - set rtaitest_state="compile"
	fi
	# compile new kernel:
	KERNEL_CONFIG="$NEW_KERNEL_PARAM"
	NEW_KERNEL_CONFIG=true
	if test -z "$KERNEL_CONFIG"; then
	    echo_log "Missing kernel configuration!"
	    echo_kmsg "Missing kernel configuration!"
	    test_abort
	    exit 1
	fi
	echo_log "Compile new kernel:"
	echo_kmsg "START COMPILE NEW KERNEL"
	KERNEL_MENU=old
	reconfigure &> "${LOG_FILE}.tmp"
	if test "x$?" != "x0"; then
	    echo_kmsg "END COMPILE NEW KERNEL"
	    echo_log ""
	    echo_log "Detailed output of reconfigure:"
	    cat "${LOG_FILE}.tmp" >> "$LOG_FILE"
	    echo_kmsg "FAILED TO BUILD KERNEL"
	    echo_log "FAILED TO BUILD KERNEL"
	    test_abort
	    exit 1
	else
	    echo_kmsg "END COMPILE NEW KERNEL"
	fi
	rm "${LOG_FILE}.tmp"
    else
	# in case everything fails do a cold start:
	{ sleep $(( $TEST_TOTAL_TIME + 240 )); reboot_cmd cold; } &
	# at TEST_TOTAL_TIME seconds later reboot:
	{ sleep $(( $TEST_TOTAL_TIME + 120)); reboot_cmd; } &
	echo_kmsg "REBOOT AFTER $(( $TEST_TOTAL_TIME + 120)) SECONDS"

	if test -f /boot/grub/grubenv; then
	    grub-editenv - set rtaitest_state="test"
	fi

	# assemble description:
	test -n "$KERNEL_DESCR" && test "${KERNEL_DESCR:-1:1}" != "-" && KERNEL_DESCR="${KERNEL_DESCR}-"
	test -n "$BATCH_DESCR" && test -n "$DESCRIPTION" && test "${BATCH_DESCR:-1:1}" != "-" && BATCH_DESCR="${BATCH_DESCR}-"

	# run tests:
	echo_log "test kernel ${KERNEL_DESCR}${BATCH_DESCR}${DESCRIPTION}:"
	if ! test_kernel $TEST_SPECS $LOAD_MODE auto "${KERNEL_DESCR}${BATCH_DESCR}${DESCRIPTION}"; then
	    test_abort
	else
	    echo_log
	fi
    fi

    if test "$INDEX" -gt "$N_TESTS"; then
	echo_kmsg "FINISHED TEST BATCH"
	echo_log "finished test batch"
    fi

    # reboot:
    sleep 1
    if test -f /boot/grub/grubenv; then
	grub-editenv - set rtaitest_pwd="$PWD"
	grub-editenv - set rtaitest_file="$BATCH_FILE"
	grub-editenv - set rtaitest_index="$INDEX"
	grub-editenv - set rtaitest_kernel_descr="${KERNEL_DESCR%%-}"
	grub-editenv - set rtaitest_param_descr="$KERNEL_PARAM_DESCR"
	grub-editenv - set rtaitest_time="$TEST_TOTAL_TIME"
	grub-editenv - set rtaitest_specs="$TEST_SPECS"
	grub-editenv - set rtaitest_state="reboot"
    fi
    if $COMPILE; then
	echo_kmsg "REBOOT AFTER KERNEL COMPILATION"
    else
	echo_kmsg "REBOOT BECAUSE TEST HAS BEEN COMPLETED"
    fi
    reboot_cmd
    sleep 60
    reboot_cmd cold

    exit 0
}

function restore_test_batch {
    if crontab -l | grep -q "${MAKE_RTAI_KERNEL}"; then
	echo_log "restore original crontab"
	if ! $DRYRUN; then
	    (crontab -l | grep -v "${MAKE_RTAI_KERNEL}") | crontab -
	fi
    fi
    if test -f /boot/grub/grubenv; then
	echo_log "clear grub environment variables"
	grub-editenv - unset rtaitest_pwd
	grub-editenv - unset rtaitest_file
	grub-editenv - unset rtaitest_index
	grub-editenv - unset rtaitest_kernel_descr
	grub-editenv - unset rtaitest_param_descr
	grub-editenv - unset rtaitest_time
	grub-editenv - unset rtaitest_specs
	grub-editenv - unset rtaitest_state
    fi
}

function test_report {
    if test -r ${0%/*}/testreport.py; then
	python ${0%/*}/testreport.py ${HIDE_COLUMNS[@]/#/--hide } $@
	return
    fi
    SORT=false
    SORTCOL=5
    if test "x$1" = "xavg"; then
	SORT=true
	SORTCOL=5
	shift
    elif test "x$1" = "xmax"; then
	SORT=true
	SORTCOL=4
	shift
    fi
    FILES="latencies-*"
    test -n "$1" && FILES="$*"
    test -d "$FILES" && FILES="$FILES/latencies-*"
    rm -f header.txt data.txt dataoverrun.txt
    # column widths:
    COLWS=()
    INIT=true
    for TEST in $FILES; do
	test -f "$TEST" || continue
	# skip empty files: (better would be to list them as failed)
	test "$(wc -l $TEST | cut -d ' ' -f 1)" -lt 4 && continue
	LINEMARKS="RTD|"
	$INIT && LINEMARKS="$LINEMARKS RTH|"
	for LINEMARK in $LINEMARKS; do
	    ORGIFS="$IFS"
	    IFS=" | "
	    INDEX=0
	    for COL in $(head -n 6 $TEST | fgrep "$LINEMARK" | tail -n 1); do
		# strip spaces:
		C=$(echo $COL)
		WIDTH=${#C}
		#if test "x$C" = "x-" || test "x$C" = "xo"; then
		#    WIDTH=0
		#fi
		if $INIT; then
		    COLWS+=($WIDTH)
		else
		    test "${COLWS[$INDEX]}" -lt "$WIDTH" && COLWS[$INDEX]=$WIDTH
		fi
		let INDEX+=1
	    done
	    IFS="$ORGIFS"
	    INIT=false
	done
    done
    # nothing found:
    if test ${#COLWS[*]} -le 2; then
	echo "You need to specify existing files or a directory with test result files!"
	echo
	echo "Usage:"
	echo "${MAKE_RTAI_KERNEL} report <FILES>"
	exit 1
    fi
    # column width for first line of header:
    INDEX=0
    HCOLWS=()
    WIDTH=0; for IDX in $(seq 1); do let WIDTH+=${COLWS[$INDEX]}; let INDEX+=1; done
    HCOLWS+=($WIDTH)
    WIDTH=2; for IDX in $(seq 2); do let WIDTH+=${COLWS[$INDEX]}; let INDEX+=1; done
    HCOLWS+=($WIDTH)
    for TD in $(seq 3); do
	WIDTH=8; for IDX in $(seq 5); do let WIDTH+=${COLWS[$INDEX]}; let INDEX+=1; done
	HCOLWS+=($WIDTH)
	WIDTH=4; for IDX in $(seq 3); do let WIDTH+=${COLWS[$INDEX]}; let INDEX+=1; done
	HCOLWS+=($WIDTH)
	WIDTH=4; for IDX in $(seq 3); do let WIDTH+=${COLWS[$INDEX]}; let INDEX+=1; done
	HCOLWS+=($WIDTH)
    done
    HCOLWS+=(${COLWS[$INDEX]})
    # reformat output to the calculated column widths:
    FIRST=true
    for TEST in $FILES; do
	# skip noexisting files:
	test -f "$TEST" || continue
	# skip empty files: (better would be to list them as failed)
	test "$(wc -l $TEST | cut -d ' ' -f 1)" -lt 4 && continue
	LINEMARKS="RTD|"
	$FIRST && LINEMARKS="RTH| $LINEMARKS"
	FIRST=false
	for LINEMARK in $LINEMARKS; do
	    DEST=""
	    if test $LINEMARK = "RTH|"; then
		DEST="header.txt"
		# first line of header:
		ORGIFS="$IFS"
		IFS="|"
		MAXINDEX=${#HCOLWS[*]}
		let MAXINDEX-=1
		INDEX=0
		for COL in $(head -n 6 $TEST | fgrep "$LINEMARK" | head -n 1); do
		    IFS=" "
		    C=$(echo $COL)
		    IFS="|"
		    if test $INDEX -ge $MAXINDEX; then
			printf "%s\n" $C >> $DEST
		    else
			printf "%-${HCOLWS[$INDEX]}s| " ${C:0:${HCOLWS[$INDEX]}} >> $DEST
		    fi
		    let INDEX+=1
		done
		IFS="$ORGIFS"
	    else
		if ! $SORT; then
		    DEST="data.txt"
		elif test $(echo $(head -n 6 $TEST | fgrep 'RTD|' | cut -d '|' -f 8)) = "-"; then
		    DEST="dataoverrun.txt"
		elif test $(echo $(head -n 6 $TEST | fgrep 'RTD|' | cut -d '|' -f 8)) = "o"; then
		    DEST="dataoverrun.txt"
		elif test $(head -n 6 $TEST | fgrep 'RTD|' | cut -d '|' -f 8) -gt 0; then
		    DEST="dataoverrun.txt"
		else
		    DEST="data.txt"
		fi
	    fi
	    ORGIFS="$IFS"
	    IFS=" | "
	    INDEX=0
	    MAXINDEX=${#COLWS[*]}
	    let MAXINDEX-=1
	    for COL in $(head -n 6 $TEST | fgrep "$LINEMARK" | tail -n 1); do
		if test $INDEX -ge $MAXINDEX; then
		    printf "%s\n" $COL >> $DEST
		elif test $INDEX -lt 3; then
		    printf "%-${COLWS[$INDEX]}s| " $COL >> $DEST
		else
		    printf "%${COLWS[$INDEX]}s| " $COL >> $DEST
		fi
		let INDEX+=1
	    done
	    IFS="$ORGIFS"
	done
    done
    # sort results with respect to average kern latency:
    if ! $FIRST; then
	cat header.txt
	if $SORT; then
	    test -f data.txt && sort -t '|' -k $SORTCOL -n data.txt
	    test -f dataoverrun.txt && sort -t '|' -k $SORTCOL -n dataoverrun.txt
	else
	    test -f data.txt && cat data.txt
	fi
    fi
    rm -f header.txt data.txt dataoverrun.txt
}


###########################################################################
# newlib:

function download_newlib {
    cd ${LOCAL_SRC_PATH}
    if test -d newlib/src/newlib; then
	echo_log "keep already downloaded newlib sources"
    else
	echo_log "download newlib"
	if ! $DRYRUN; then
	    mkdir newlib
	    cd newlib
	    if git clone git://sourceware.org/git/newlib-cygwin.git src; then
		echo_log "downloaded newlib from git repository"
		date +"%F %H:%M" > src/revision.txt
		mkdir install
	    elif wget ftp://sourceware.org/pub/newlib/$NEWLIB_TAR; then
		echo_log "downloaded newlib snapshot $NEWLIB_TAR"
		tar xzf $NEWLIB_TAR
		NEWLIB_DIR=${NEWLIB_TAR%.tar.gz}
		mv $NEWLIB_DIR src
		echo ${NEWLIB_DIR#newlib-} > src/revision.txt
		mkdir install
	    else
		echo_log "Failed to download newlib!"
		cd - > /dev/null
		return 1
	    fi
	fi
    fi
    cd - > /dev/null
}

function update_newlib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d newlib/src/.git; then
	echo_log "Update already downloaded newlib sources from git repository."
	cd newlib/src
	if git pull origin master; then
	    date +"%F %H:%M" > revision.txt
	    cd "$WORKING_DIR"
	    clean_newlib
	else
	    echo_log "Failed to update newlib from git repository!"
	    cd "$WORKING_DIR"
	    return 1
	fi
    elif ! test -f newlib/$NEWLIB_TAR; then
	echo_log "Remove entire newlib source tree."
	rm -r newlib
	cd "$WORKING_DIR"
	download_newlib || return 1
    else
	cd - > /dev/null
	echo_log "Keep newlib source tree as is."
    fi
    cd "$WORKING_DIR"
}

function build_newlib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}/newlib/install
    LIBM_PATH=$(find ${LOCAL_SRC_PATH}/newlib/install/ -name 'libm.a' | head -n 1)
    if test -f "$LIBM_PATH"; then
	echo_log "keep already built and installed newlib library"
    else
	echo_log "build newlib"
	if ! $DRYRUN; then
	    NEWLIB_CFLAGS="-fno-pie"
	    if test "$(grep CONFIG_64BIT $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config)" = 'CONFIG_64BIT=y'; then
		NEWLIB_CFLAGS="$NEWLIB_CFLAGS -mcmodel=kernel"
	    fi
	    ${LOCAL_SRC_PATH}/newlib/src/newlib/configure --prefix=${LOCAL_SRC_PATH}/newlib/install --disable-shared --disable-multilib --target="$MACHINE" CFLAGS="${NEWLIB_CFLAGS}"
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build newlib!"
		cd - > /dev/null
		return 1
	    fi
	    cd "$WORKING_DIR"
	    install_newlib || return 1
	fi
	NEW_NEWLIB=true
    fi
    cd "$WORKING_DIR"
}

function clean_newlib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d newlib; then
	echo_log "clean newlib"
	if ! $DRYRUN; then
	    rm -rf newlib/install/*
	    cd newlib/src/newlib
	    make distclean
	fi
    fi
    cd "$WORKING_DIR"
}

function install_newlib {
    cd ${LOCAL_SRC_PATH}/newlib/install
    echo_log "install newlib"
    if ! $DRYRUN; then
	make install
	if test "x$?" != "x0"; then
	    echo_log "Failed to install newlib!"
	    cd - > /dev/null
	    return 1
	fi
    fi
    NEW_NEWLIB=true
    cd - > /dev/null
}

function uninstall_newlib {
    cd ${LOCAL_SRC_PATH}
    if test -d newlib; then
	echo_log "uninstall newlib"
	if ! $DRYRUN; then
	    rm -r newlib/install/*
	fi
    fi
    cd - > /dev/null
}

function remove_newlib {
    cd ${LOCAL_SRC_PATH}
    if test -d newlib; then
	echo_log "remove ${LOCAL_SRC_PATH}/newlib"
	if ! $DRYRUN; then
	    rm -r newlib
	fi
    fi
    cd - > /dev/null
}


###########################################################################
# musl:

function download_musl {
    cd ${LOCAL_SRC_PATH}
    if test -d musl; then
	echo_log "keep already downloaded musl sources"
    else
	echo_log "download musl"
	if ! $DRYRUN; then
	    if git clone git://git.musl-libc.org/musl; then
		echo_log "downloaded musl from git repository"
		date +"%F %H:%M" > musl/revision.txt
	    elif wget https://git.musl-libc.org/cgit/musl/snapshot/$MUSL_TAR; then
		echo_log "downloaded musl snapshot $MUSL_TAR"
		tar xzf $MUSL_TAR
		MUSL_DIR=${MUSL_TAR%.tar.gz}
		mv $MUSL_DIR musl
		echo ${MUSL_DIR#musl-} > musl/revision.txt
	    else
		echo_log "Failed to download musl!"
		cd - > /dev/null
		return 1
	    fi
	fi
    fi
    cd - > /dev/null
}

function update_musl {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d musl/.git; then
	echo_log "Update already downloaded musl sources from git repository."
	cd musl
	test -f Makefile.origmrk && mv Makefile.origmrk Makefile
	if git pull origin master; then
	    date +"%F %H:%M" > revision.txt
	    cd "$WORKING_DIR"
	    clean_musl
	else
	    echo_log "Failed to update musl from git repository!"
	    cd "$WORKING_DIR"
	    return 1
	fi
    elif ! test -f $MUSL_TAR; then
	echo_log "Remove entire musl source tree."
	rm -r musl
	cd "$WORKING_DIR"
	download_musl || return 1
    else
	cd - > /dev/null
	echo_log "Keep musl source tree as is."
    fi
    cd "$WORKING_DIR"
}

function build_musl {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}/musl
    LIBM_PATH=lib/libm.a
    if test -f "$LIBM_PATH"; then
	echo_log "keep already built musl library"
    else
	echo_log "build musl"
	if ! $DRYRUN; then
	    test -f Makefile.origmrk && mv Makefile.origmrk Makefile
	    mv Makefile Makefile.origmrk
	    sed 's/-fPIC//' Makefile.origmrk > Makefile
	    MUSL_CFLAGS="-fno-common -fno-pic"
	    if test "$(grep CONFIG_64BIT $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config)" = 'CONFIG_64BIT=y'; then
		MUSL_CFLAGS="-mcmodel=kernel ${MUSL_CFLAGS}"
	    fi
	    ./configure --disable-shared CFLAGS="${MUSL_CFLAGS}"
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build musl!"
		cd - > /dev/null
		return 1
	    fi
	    cd "$WORKING_DIR"
	    install_musl || return 1
	fi
	NEW_MUSL=true
    fi
    cd "$WORKING_DIR"
}

function clean_musl {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d musl; then
	echo_log "clean musl"
	if ! $DRYRUN; then
	    cd musl
	    test -f Makefile.origmrk && mv Makefile.origmrk Makefile
	    make distclean
	fi
    fi
    cd "$WORKING_DIR"
}

function install_musl {
    cd ${LOCAL_SRC_PATH}/musl
    echo_log "install musl"
    if ! $DRYRUN; then
	if ! test -f lib/libc.a; then
	    echo_log "Failed to install musl!"
	    cd - > /dev/null
	    return 1
	fi
	ar -dv lib/libc.a fwrite.o write.o fputs.o sprintf.o strcpy.o strlen.o memcpy.o memset.o
	ar -dv lib/libc.a cpow.o cpowf.o cpowl.o
	cp lib/libc.a lib/libm.a
    fi
    NEW_MUSL=true
    cd - > /dev/null
}

function uninstall_musl {
    cd ${LOCAL_SRC_PATH}
    if test -d musl; then
	echo_log "uninstall musl"
    fi
    cd - > /dev/null
}

function remove_musl {
    cd ${LOCAL_SRC_PATH}
    if test -d musl; then
	echo_log "remove ${LOCAL_SRC_PATH}/musl"
	if ! $DRYRUN; then
	    rm -r musl
	fi
    fi
    cd - > /dev/null
}


###########################################################################
# rtai:

function download_rtai {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $RTAI_DIR; then
	echo_log "keep already downloaded rtai sources"
	cd $RTAI_DIR
	echo_log "run make distclean on rtai sources"
	if ! $DRYRUN; then
	    make distclean
	fi
	cd - > /dev/null
    else
	echo_log "download rtai sources $RTAI_DIR"
	if ! $DRYRUN; then
	    if test "x$RTAI_DIR" = "xmagma"; then
		cvs -d:pserver:anonymous@cvs.gna.org:/cvs/rtai co $RTAI_DIR
	    elif test "x$RTAI_DIR" = "xvulcano"; then
		cvs -d:pserver:anonymous@cvs.gna.org:/cvs/rtai co $RTAI_DIR
	    elif test "x$RTAI_DIR" = "xRTAI"; then
		git clone https://github.com/ShabbyX/RTAI.git
	    else
		if wget https://www.rtai.org/userfiles/downloads/RTAI/${RTAI_DIR}.tar.bz2; then
		    echo_log "unpack ${RTAI_DIR}.tar.bz2"
		    tar xof ${RTAI_DIR}.tar.bz2
		    # -o option because we are root and want the files to be root!
		else
		    echo_log "Failed to download RTAI from \"https://www.rtai.org/userfiles/downloads/RTAI/${RTAI_DIR}.tar.bz2\"!"
		    cd "$WORKING_DIR"
		    return 1
		fi
	    fi
	    if test "x$?" != "x0"; then
		echo_log "Failed to download RTAI!"
		cd "$WORKING_DIR"
		return 1
	    else
		date +"%F %H:%M" > $RTAI_DIR/revision.txt
	    fi
	fi
    fi
    echo_log "set soft link rtai -> $RTAI_DIR"
    if ! $DRYRUN; then
	ln -sfn $RTAI_DIR rtai
    fi
    cd "$WORKING_DIR"
}

function update_rtai {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $RTAI_DIR; then
	cd $RTAI_DIR
	echo_log "run make distclean on rtai sources"
	if ! $DRYRUN; then
	    make distclean
	fi
	if test -d CVS; then
	    echo_log "update already downloaded rtai sources"
	    if ! $DRYRUN; then
		cvs -d:pserver:anonymous@cvs.gna.org:/cvs/rtai update && date +"%F %H:%M" > revision.txt
	    fi
	elif test -d .git; then
	    echo_log "update already downloaded rtai sources"
	    if ! $DRYRUN; then
		git pull origin master && date +"%F %H:%M" > revision.txt
	    fi
	elif test -f ../${RTAI_DIR}.tar.bz2; then
	    cd - > /dev/null
	    echo_log "remove RTAI source tree in ${LOCAL_SRC_PATH}/${RTAI_DIR}"
	    $DRYRUN || rm -rf ${RTAI_DIR}
	    echo_log "unpack ${RTAI_DIR}.tar.bz2"
	    $DRYRUN || tar xof ${RTAI_DIR}.tar.bz2
	    cd - > /dev/null
	fi
	cd - > /dev/null
	if test "x$?" != "x0"; then
	    echo_log "Failed to update RTAI!"
	    cd "$WORKING_DIR"
	    return 1
	fi
	echo_log "set soft link rtai -> $RTAI_DIR"
	if ! $DRYRUN; then
	    ln -sfn $RTAI_DIR rtai
	fi
    else
	cd "$WORKING_DIR"
	download_rtai || return 1
    fi
    cd "$WORKING_DIR"
}

function build_rtai {
    cd ${LOCAL_SRC_PATH}/${RTAI_DIR}
    if $NEW_KERNEL || $NEW_NEWLIB || $NEW_MUSL || ! test -f base/sched/rtai_sched.ko || ! test -f ${REALTIME_DIR}/modules/rtai_hal.ko; then
	echo_log "build rtai"
	if ! $DRYRUN; then
	    LIBM_ID="0"
	    if $NEW_MUSL; then
		LIBM_ID="3"
	    elif $NEW_NEWLIB; then
		LIBM_ID="1"
	    elif $MAKE_MUSL; then
		LIBM_ID="3"
	    elif $MAKE_NEWLIB; then
		LIBM_ID="1"
	    fi
	    if test $LIBM_ID = "3"; then
		LIBM_PATH=${LOCAL_SRC_PATH}/musl/lib/libm.a
		if ! test -f ${LIBM_PATH}; then
		    MAKE_MUSL=false
		    LIBM_ID="0"
		fi
	    elif test $LIBM_ID = "1"; then
		# path to newlib math library:
		LIBM_PATH=$(find ${LOCAL_SRC_PATH}/newlib/install/ -name 'libm.a' | head -n 1)
		if test -z "$LIBM_PATH"; then
		    MAKE_NEWLIB=false
		    LIBM_ID="0"
		fi
	    else
		LIBM_PATH=""
	    fi
	    # number of CPUs:
	    CONFIG_NR_CPUS=$(grep CONFIG_NR_CPUS $KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}/.config)
	    RTAI_NUM_CPUS=${CONFIG_NR_CPUS#*=}
	    # check for configure script (no present in ShabbyX RTAI):
	    if ! test -x configure; then
		test -x autogen.sh && ./autogen.sh
	    fi
	    # start out with default configuration:
	    cp base/arch/${RTAI_MACHINE}/defconfig .rtai_config
	    # diff -u base/arch/${RTAI_MACHINE}/defconfig .rtai_config
	    # configure:
	    if grep -q 'CONFIG_RTAI_VERSION="5' .rtai_config; then
		# ./configure script options seem to be very outdated (new libmath support)! 
		# So, the following won't work:
		# ./configure --enable-cpus=${RTAI_NUM_CPUS} --enable-fpu --with-math-libm-dir=$LIBM_PATH
		patch <<EOF
--- base/arch/x86/defconfig     2017-11-17 16:20:00.000000000 +0100
+++ .rtai_config        2018-03-14 18:03:41.700624880 +0100
@@ -7,8 +7,8 @@
 #
 # General
 #
-CONFIG_RTAI_INSTALLDIR="/usr/realtime"
-CONFIG_RTAI_LINUXDIR="/usr/src/linux"
+CONFIG_RTAI_INSTALLDIR="${REALTIME_DIR}"
+CONFIG_RTAI_LINUXDIR="$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME}"
 
 #
 # RTAI Documentation
@@ -19,14 +19,15 @@
 CONFIG_RTAI_TESTSUITE=y
 CONFIG_RTAI_COMPAT=y
 # CONFIG_RTAI_EXTENDED is not set
-CONFIG_RTAI_LXRT_NO_INLINE=y
-# CONFIG_RTAI_LXRT_STATIC_INLINE is not set
+# CONFIG_RTAI_LXRT_NO_INLINE is not set
+CONFIG_RTAI_LXRT_STATIC_INLINE=y
+CONFIG_RTAI_FORTIFY_SOURCE=""

 #
 # Machine (x86)
 #
 CONFIG_RTAI_FPU_SUPPORT=y
-CONFIG_RTAI_CPUS="2"
+CONFIG_RTAI_CPUS="$RTAI_NUM_CPUS"
 # CONFIG_RTAI_DIAG_TSC_SYNC is not set

 #
@@ -38,8 +39,12 @@
 #
 # CONFIG_RTAI_SCHED_ISR_LOCK is not set
 # CONFIG_RTAI_LONG_TIMED_LIST is not set
-CONFIG_RTAI_LATENCY_SELF_CALIBRATION_FREQ="10000"
-CONFIG_RTAI_LATENCY_SELF_CALIBRATION_CYCLES="10000"
+# CONFIG_RTAI_USE_STACK_ARGS is not set
+CONFIG_RTAI_LATENCY_SELF_CALIBRATION_METRICS="1"
+CONFIG_RTAI_LATENCY_SELF_CALIBRATION_FREQ="10000"
+CONFIG_RTAI_LATENCY_SELF_CALIBRATION_CYCLES="10000"
+CONFIG_RTAI_KERN_BUSY_ALIGN_RET_DELAY="0"
+CONFIG_RTAI_USER_BUSY_ALIGN_RET_DELAY="0"
 CONFIG_RTAI_SCHED_LXRT_NUMSLOTS="150"
 CONFIG_RTAI_MONITOR_EXECTIME=y
 CONFIG_RTAI_ALLOW_RR=y
@@ -69,7 +74,10 @@
 # Other features
 #
 CONFIG_RTAI_USE_NEWERR=y
-# CONFIG_RTAI_MATH is not set
+CONFIG_RTAI_MATH=y
+CONFIG_RTAI_MATH_LIBM_TO_USE="${LIBM_ID}"
+CONFIG_RTAI_MATH_LIBM_DIR="${LIBM_PATH%/*}"
+# CONFIG_RTAI_MATH_KCOMPLEX is not set
 CONFIG_RTAI_MALLOC=y
 # CONFIG_RTAI_USE_TLSF is not set
 CONFIG_RTAI_MALLOC_VMALLOC=y
EOF
	    else
		patch <<EOF
--- base/arch/x86/defconfig	2015-03-09 11:42:51.000000000 +0100
+++ .rtai_config	2015-09-09 10:44:17.662656156 +0200
@@ -17,16 +17,17 @@
 # CONFIG_RTAI_DOC_LATEX_NONSTOP is not set
 # CONFIG_RTAI_DBX_DOC is not set
 CONFIG_RTAI_TESTSUITE=y
-CONFIG_RTAI_COMPAT=y
+# CONFIG_RTAI_COMPAT is not set
 # CONFIG_RTAI_EXTENDED is not set
-CONFIG_RTAI_LXRT_NO_INLINE=y
-# CONFIG_RTAI_LXRT_STATIC_INLINE is not set
+# CONFIG_RTAI_LXRT_NO_INLINE is not set
+CONFIG_RTAI_LXRT_STATIC_INLINE=y
+CONFIG_RTAI_FORTIFY_SOURCE=""
 
 #
 # Machine (x86)
 #
 CONFIG_RTAI_FPU_SUPPORT=y
-CONFIG_RTAI_CPUS="2"
+CONFIG_RTAI_CPUS="$RTAI_NUM_CPUS"
 # CONFIG_RTAI_DIAG_TSC_SYNC is not set
 
 #
@@ -38,8 +39,10 @@
 #
 # CONFIG_RTAI_SCHED_ISR_LOCK is not set
 # CONFIG_RTAI_LONG_TIMED_LIST is not set
-CONFIG_RTAI_SCHED_LATENCY_SELFCALIBRATE=y
+# CONFIG_RTAI_SCHED_LATENCY_SELFCALIBRATE is not set
 CONFIG_RTAI_SCHED_LATENCY="0"
+CONFIG_RTAI_KERN_BUSY_ALIGN_RET_DELAY="0"
+CONFIG_RTAI_USER_BUSY_ALIGN_RET_DELAY="0"
 CONFIG_RTAI_SCHED_LXRT_NUMSLOTS="150"
 CONFIG_RTAI_MONITOR_EXECTIME=y
 CONFIG_RTAI_ALLOW_RR=y
@@ -69,7 +72,10 @@
 # Other features
 #
 # CONFIG_RTAI_USE_NEWERR is not set
-# CONFIG_RTAI_MATH is not set
+CONFIG_RTAI_MATH=y
+CONFIG_RTAI_MATH_LIBM_TO_USE="${LIBM_ID}"
+CONFIG_RTAI_MATH_LIBM_DIR="${LIBM_PATH%/*}"
+# CONFIG_RTAI_MATH_KCOMPLEX is not set
 CONFIG_RTAI_MALLOC=y
 # CONFIG_RTAI_USE_TLSF is not set
 CONFIG_RTAI_MALLOC_VMALLOC=y
@@ -82,9 +88,7 @@
 #
 # Add-ons
 #
-CONFIG_RTAI_COMEDI_LXRT=y
-CONFIG_RTAI_COMEDI_DIR="/usr/comedi"
-# CONFIG_RTAI_USE_COMEDI_LOCK is not set
+# CONFIG_RTAI_COMEDI_LXRT is not set
 # CONFIG_RTAI_CPLUSPLUS is not set
 # CONFIG_RTAI_RTDM is not set
EOF
	    fi
	    if test "x$?" != "x0"; then
		echo_log "Failed to patch RTAI configuration!"
		cd - > /dev/null
		return 1
	    fi
	    if test ${LIBM_ID} = "0"; then
		patch <<EOF
--- .rtai_config_math   2018-03-14 16:29:57.156483235 +0100
+++ .rtai_config        2018-03-14 16:30:24.116483914 +0100
@@ -74,10 +74,7 @@
 # Other features
 #
 CONFIG_RTAI_USE_NEWERR=y
-CONFIG_RTAI_MATH=y
-CONFIG_RTAI_MATH_LIBM_TO_USE="1"
-CONFIG_RTAI_MATH_LIBM_DIR=""
-# CONFIG_RTAI_MATH_KCOMPLEX is not set
+# CONFIG_RTAI_MATH is not set
 CONFIG_RTAI_MALLOC=y
 # CONFIG_RTAI_USE_TLSF is not set
 CONFIG_RTAI_MALLOC_VMALLOC=y
EOF
		if test "x$?" != "x0"; then
		    echo_log "Failed to patch RTAI configuration for math support!"
		    cd - > /dev/null
		    return 1
		fi
	    fi
	    make -f makefile oldconfig
	    if test "x$?" != "x0"; then
		echo_log "Failed to clean RTAI configuration (make oldconfig)!"
		cd - > /dev/null
		return 1
	    fi
	    if $RTAI_MENU; then
		make menuconfig
	    fi
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build rtai modules!"
		cd - > /dev/null
		return 1
	    fi
	    cd - > /dev/null
	    install_rtai || return 1
	else
	    cd - > /dev/null
	fi
	NEW_RTAI=true
    else
	echo_log "keep already built and installed rtai modules"
	cd - > /dev/null
    fi
}

function clean_rtai { 
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $RTAI_DIR; then
	echo_log "clean rtai"
	if ! $DRYRUN; then
	    cd $RTAI_DIR
	    make clean
	fi
    fi
    cd "$WORKING_DIR"
}

function install_rtai {
    cd ${LOCAL_SRC_PATH}/${RTAI_DIR}
    echo_log "install rtai"
    if ! $DRYRUN; then
	make install
	if test "x$?" != "x0"; then
	    echo_log "Failed to install rtai modules!"
	    cd - > /dev/null
	    return 1
	fi
    fi
    NEW_RTAI=true
    cd - > /dev/null
}

function uninstall_rtai {
    if test -d ${REALTIME_DIR}; then
	echo_log "uninstall rtai"
	if ! $DRYRUN; then
	    rm -r ${REALTIME_DIR}
	fi
    fi
}

function remove_rtai {
    cd ${LOCAL_SRC_PATH}
    if test -d $RTAI_DIR; then
	echo_log "remove rtai in ${LOCAL_SRC_PATH}/$RTAI_DIR"
	if ! $DRYRUN; then
	    rm -r $RTAI_DIR
	fi
    fi
    if test -f $RTAI_DIR.tar.*; then
	echo_log "remove ${LOCAL_SRC_PATH}/$RTAI_DIR.tar.*"
	if ! $DRYRUN; then
	    rm $RTAI_DIR.tar.*
	fi
    fi
    cd - > /dev/null
}


function setup_rtai {
    CPUS="$1"
    IFS=',' read -r -a CPUIDS <<< "$CPUS"
    CPUMASK=0
    for CPU in "${CPUIDS[@]}"; do
	CPUM=`echo "2^(${CPU})" | bc`
	let CPUMASK+=$CPUM
    done
    if test $CPUMASK -eq 0; then
	echo_log "No valid CPU ids specified (comma separated list of CPU ids)."
	return 1
    fi
    if test -d ${LOCAL_SRC_PATH}/$RTAI_DIR; then
 	echo_log "Set CPU mask for kern/latency test to $CPUMASK"
	if ! $DRYRUN; then
	    cd ${LOCAL_SRC_PATH}/$RTAI_DIR/testsuite/kern/latency
	    if ! test -f latency-module.c.mrk; then
		echo_log "Save original kern/latency test"
		cp latency-module.c latency-module.c.mrk
		sync
	    fi
	    sed -e "s/#define RUNNABLE_ON_CPUS 3/#define RUNNABLE_ON_CPUS $CPUMASK/" latency-module.c.mrk > latency-module.c
	    echo_log "Rebuild kern/latency test"
	    make
	    echo_log "Reinstall kern/latency test"
	    make install
	    cd - &> /dev/null
	fi
    fi
    return 0
}

function restore_rtai {
    if test -f ${LOCAL_SRC_PATH}/$RTAI_DIR/testsuite/kern/latency/latency-module.c.mrk; then
	echo_log "Restore original RTAI testsuite."
	if ! $DRYRUN; then
	    cd ${LOCAL_SRC_PATH}/$RTAI_DIR/testsuite/kern/latency
	    cp latency-module.c.mrk latency-module.c
	    sync
	    rm latency-module.c.mrk
	    echo_log "Rebuild kern/latency test"
	    touch latency-module.c
	    make
	    echo_log "Reinstall kern/latency test"
	    make install
	    cd - &> /dev/null
	fi
    fi
}


###########################################################################
# rtai showroom:

function download_showroom {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $SHOWROOM_DIR; then
	echo_log "keep already downloaded rtai-showroom sources"
	cd $SHOWROOM_DIR/v3.x
	echo_log "run make clean on rtai-showroom sources"
	if ! $DRYRUN; then
	    PATH="$PATH:${REALTIME_DIR}/bin"
	    make clean
	fi
	cd - > /dev/null
    else
	echo_log "download rtai-showroom sources"
	if ! $DRYRUN; then
	    if ! cvs -d:pserver:anonymous@cvs.gna.org:/cvs/rtai co $SHOWROOM_DIR; then
		echo_log "Failed to download showroom!"
		cd "$WORKING_DIR"
		return 1
	    fi
	    date +"%F %H:%M" > $SHOWROOM_DIR/revision.txt
	fi
    fi
    cd "$WORKING_DIR"
}

function update_showroom {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $SHOWROOM_DIR; then
	echo_log "update already downloaded rtai-showroom sources"
	cd $SHOWROOM_DIR
	if ! cvs -d:pserver:anonymous@cvs.gna.org:/cvs/rtai update; then
	    echo_log "Failed to update showroom!"
	    cd "$WORKING_DIR"
	    return 1
	fi
	date +"%F %H:%M" > revision.txt
	cd "$WORKING_DIR"
	clean_showroom
    else
	cd "$WORKING_DIR"
	download_showroom || return 1
    fi
}

function build_showroom {
    cd ${LOCAL_SRC_PATH}/$SHOWROOM_DIR/v3.x
    echo_log "build rtai showroom"
    if ! $DRYRUN; then
	PATH="$PATH:${REALTIME_DIR}/bin"
	make
	if test "x$?" != "x0"; then
	    echo_log "Failed to build rtai showroom!"
	    cd - > /dev/null
	    return 1
	fi
    fi
    cd - > /dev/null
}

function clean_showroom {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d $SHOWROOM_DIR; then
	echo_log "clean rtai showroom"
	if ! $DRYRUN; then
	    cd $SHOWROOM_DIR/v3.x
	    PATH="$PATH:${REALTIME_DIR}/bin"
	    make clean
	fi
    fi
    cd "$WORKING_DIR"
}

function remove_showroom {
    cd ${LOCAL_SRC_PATH}
    if test -d $SHOWROOM_DIR; then
	echo_log "remove rtai showroom in ${LOCAL_SRC_PATH}/$SHOWROOM_DIR"
	if ! $DRYRUN; then
	    rm -r $SHOWROOM_DIR
	fi
    fi
    cd - > /dev/null
}


###########################################################################
# comedi:

function download_comedi {
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Keep already downloaded comedi sources."
    else
	echo_log "Download comedi."
	if ! $DRYRUN; then
	    if ! git clone https://github.com/Linux-Comedi/comedi.git comedi; then
		echo_log "Failed to download comedi from \"git clone https://github.com/Linux-Comedi/comedi.git\"!"
		cd - > /dev/null
		return 1
	    fi
	    date +"%F %H:%M" > comedi/revision.txt
	fi
    fi
    cd - > /dev/null
}

function update_comedi {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Update already downloaded comedi sources."
	cd comedi
	if ! git pull origin master; then
	    echo_log "Failed to update comedi!"
	    cd "$WORKING_DIR"
	    return 1
	fi
	date +"%F %H:%M" > revision.txt
	cd "$WORKING_DIR"
	clean_comedi
    else
	cd "$WORKING_DIR"
	download_comedi
    fi
}

function build_comedi {
    BUILT_COMEDI=false
    $NEW_RTAI && BUILT_COMEDI=true
    ! test -f ${LOCAL_SRC_PATH}/comedi/comedi/comedi.o && BUILT_COMEDI=true
    test -f /usr/local/src/comedi/config.status && ! grep -q modules/${KERNEL_NAME} /usr/local/src/comedi/config.status && BUILT_COMEDI=true
    if $BUILT_COMEDI; then
	cd ${LOCAL_SRC_PATH}/comedi
	echo_log "Build comedi ..."
	if ! $DRYRUN; then
	    ./autogen.sh
	    PATH="$PATH:${REALTIME_DIR}/bin"
	    ./configure --with-linuxdir=$KERNEL_PATH/linux-${LINUX_KERNEL}-${KERNEL_SOURCE_NAME} --with-rtaidir=${REALTIME_DIR}
	    make clean
	    cp ${REALTIME_DIR}/modules/Module.symvers comedi/
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build comedi!"
		cd - > /dev/null
		return 1
	    fi
	    cd - > /dev/null
	    install_comedi || return 1
	else
	    cd - > /dev/null
	fi
	NEW_COMEDI=true
    fi
}

function clean_comedi {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Clean comedi."
	cd comedi
	if ! $DRYRUN; then
	    make clean
	fi
    else
	echo_log "No comedi sources found."
    fi
    cd "$WORKING_DIR"
}

function install_comedi {
    echo_log "remove all loaded comedi kernel modules"
    remove_comedi_modules

    echo_log "remove comedi staging kernel modules"
    if ! $DRYRUN; then
	rm -rf /lib/modules/${KERNEL_NAME}/kernel/drivers/staging/comedi
	rm -rf /lib/modules/${KERNEL_ALT_NAME}/kernel/drivers/staging/comedi
    fi

    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Install comedi."
	cd comedi
	if ! $DRYRUN; then
	    make install
	    if test "x$?" != "x0"; then
		echo_log "Failed to install comedi!"
		cd "$WORKING_DIR"
		return 1
	    fi
	    KERNEL_MODULES=/lib/modules/${KERNEL_NAME}
	    test -d "$KERNEL_MODULES" || KERNEL_MODULES=/lib/modules/${KERNEL_ALT_NAME}
	    cp ${LOCAL_SRC_PATH}/comedi/comedi/Module.symvers ${KERNEL_MODULES}/comedi/
	    cp ${LOCAL_SRC_PATH}/comedi/include/linux/comedi.h /usr/include/linux/
	    cp ${LOCAL_SRC_PATH}/comedi/include/linux/comedilib.h /usr/include/linux/
	    echo_log "  running depmod -a"
	    depmod -a
	    sleep 1
	    echo_log "  running udevadm trigger"
	    udevadm trigger
	fi
	NEW_COMEDI=true
    else
	echo_log "No comedi sources found."
    fi
    cd "$WORKING_DIR"
}

function uninstall_comedi {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Uninstall comedi."
	cd comedi
	if ! $DRYRUN; then
	    make uninstall
	fi
    else
	echo_log "No comedi sources found."
    fi
    cd "$WORKING_DIR"
}

function remove_comedi {
    cd ${LOCAL_SRC_PATH}
    if test -d comedi; then
	echo_log "Remove ${LOCAL_SRC_PATH}/comedi ."
	if ! $DRYRUN; then
	    rm -r comedi
	fi
    else
	echo_log "No comedi sources found."
    fi
    cd - > /dev/null
}

function remove_comedi_modules {
    if lsmod | grep -q kcomedilib; then
	modprobe -r kcomedilib && echo_log "removed kcomedilib"
	for i in $(lsmod | grep "^comedi" | tail -n 1 | awk '{ m=$4; gsub(/,/,"\n",m); print m}' | tac); do
	    modprobe -r $i && echo_log "removed $i"
	done
	modprobe -r comedi && echo_log "removed comedi"
    fi
}


###########################################################################
# comedilib:

function download_comedilib {
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Keep already downloaded comedilib sources."
    else
	echo_log "Download comedilib."
	if ! $DRYRUN; then
	    if ! git clone https://github.com/Linux-Comedi/comedilib.git comedilib; then
		echo_log "Failed to download comedilib from \"git clone https://github.com/Linux-Comedi/comedilib.git\"!"
		cd - > /dev/null
		return 1
	    fi
	    date +"%F %H:%M" > comedilib/revision.txt
	fi
    fi
    cd - > /dev/null
}

function update_comedilib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Update already downloaded comedilib sources."
	cd comedilib
	if ! git pull origin master; then
	    echo_log "Failed to update comedilib!"
	    cd "$WORKING_DIR"
	    return 1
	fi
	date +"%F %H:%M" > revision.txt
	cd "$WORKING_DIR"
	clean_comedilib
    else
	cd "$WORKING_DIR"
	download_comedilib
    fi
}

function build_comedilib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if ! test -d comedilib; then
	cd "$WORKING_DIR"
	download_comedilib
    fi
    cd ${LOCAL_SRC_PATH}
    if ! test -f comedilib/testing/comedi_test; then
	cd comedilib
	echo_log "Build comedilib ..."
	if ! $DRYRUN; then
	    ./autogen.sh
	    ./configure --prefix=/usr --sysconfdir=/etc
	    make clean
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build comedilib!"
		cd "$WORKING_DIR"
		return 1
	    fi
	    cd "$WORKING_DIR"
	    install_comedilib || return 1
	fi
    else
	echo_log "Keep already compiled comedilib."
    fi
    cd "$WORKING_DIR"
}

function clean_comedilib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Clean comedilib."
	cd comedilib
	if ! $DRYRUN; then
	    make clean
	fi
    fi
    cd "$WORKING_DIR"
}

function install_comedilib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Install comedilib."
	cd comedilib
	if ! $DRYRUN; then
	    make install
	    if test "x$?" != "x0"; then
		echo_log "Failed to install comedilib!"
		cd "$WORKING_DIR"
		return 1
	    fi
	fi
    else
	echo_log "No comedilib sources found."
    fi
    cd "$WORKING_DIR"
}

function uninstall_comedilib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Uninstall comedilib."
	cd comedilib
	if ! $DRYRUN; then
	    make uninstall
	fi
    else
	echo_log "No comedilib sources found."
    fi
    cd "$WORKING_DIR"
}

function remove_comedilib {
    cd ${LOCAL_SRC_PATH}
    if test -d comedilib; then
	echo_log "Remove ${LOCAL_SRC_PATH}/comedilib."
	if ! $DRYRUN; then
	    rm -r comedilib
	fi
    else
	echo_log "No comedilib sources found."
    fi
    cd - > /dev/null
}


###########################################################################
# comedicalib:

function download_comedicalib {
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Keep already downloaded comedicalib sources."
    else
	echo_log "Download comedicalib."
	if ! $DRYRUN; then
	    if ! git clone https://github.com/Linux-Comedi/comedi_calibrate.git comedicalib; then
		echo_log "Failed to download comedicalib from \"git clone https://github.com/Linux-Comedi/comedi_calibrate.git\"!"
		cd - > /dev/null
		return 1
	    fi
	    date +"%F %H:%M" > comedicalib/revision.txt
	fi
    fi
    cd - > /dev/null
}

function update_comedicalib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Update already downloaded comedicalib sources."
	cd comedicalib
	if ! git pull origin master; then
	    echo_log "Failed to update comedicalib!"
	    cd "$WORKING_DIR"
	    return 1
	fi
	date +"%F %H:%M" > revision.txt
	cd "$WORKING_DIR"
	clean_comedicalib
    else
	cd "$WORKING_DIR"
	download_comedicalib
    fi
}

function build_comedicalib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if ! test -d comedicalib; then
	cd "$WORKING_DIR"
	download_comedicalib
    fi
    if ! test -f comedicalib/comedi_calibrate/comedi_calibrate; then
	cd comedicalib
	echo_log "Build comedicalib ..."
	if ! $DRYRUN; then
	    ./autogen.sh
	    ./configure --prefix=/usr --sysconfdir=/etc
	    make clean
	    make -j $CPU_NUM
	    if test "x$?" != "x0"; then
		echo_log "Failed to build comedicalib!"
		cd "$WORKING_DIR"
		return 1
	    fi
	    cd "$WORKING_DIR"
	    install_comedicalib || return 1
	fi
    else
	echo_log "Keep already compiled comedicalib."
    fi
    cd "$WORKING_DIR"
}

function clean_comedicalib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Clean comedicalib."
	cd comedicalib
	if ! $DRYRUN; then
	    make clean
	fi
    fi
    cd "$WORKING_DIR"
}

function install_comedicalib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Install comedicalib."
	cd comedicalib
	if ! $DRYRUN; then
	    make install
	    if test "x$?" != "x0"; then
		echo_log "Failed to install comedicalib!"
		cd "$WORKING_DIR"
		return 1
	    fi
	fi
    else
	echo_log "No comedicalib sources found."
    fi
    cd "$WORKING_DIR"
}

function uninstall_comedicalib {
    WORKING_DIR="$PWD"
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Uninstall comedicalib."
	cd comedicalib
	if ! $DRYRUN; then
	    make uninstall
	fi
    else
	echo_log "No comedicalib sources found."
    fi
    cd "$WORKING_DIR"
}

function remove_comedicalib {
    cd ${LOCAL_SRC_PATH}
    if test -d comedicalib; then
	echo_log "Remove ${LOCAL_SRC_PATH}/comedicalib."
	if ! $DRYRUN; then
	    rm -r comedicalib
	fi
    else
	echo_log "No comedicalib sources found."
    fi
    cd - > /dev/null
}


###########################################################################
# /var/log/messages:

function setup_messages {
    if test -f /etc/rsyslog.d/50-default.conf.origmrk; then
	echo_log "/etc/rsyslog.d/50-default.conf has already been modified to enable /var/log/messages"
    elif ! test -f /var/log/messages || test /var/log/messages -ot /var/log/$(ls -rt /var/log | tail -n 1); then
	cd /etc/rsyslog.d
	if test -f 50-default.conf; then
	    echo_log "Patch /etc/rsyslog.d/50-default.conf to enable /var/log/messages"
	    if ! $DRYRUN; then
		cp 50-default.conf 50-default.conf.origmrk
		sed -e '/info.*notice.*warn/,/messages/s/#//' 50-default.conf.origmrk > 50-default.conf
		service rsyslog restart
		sleep 1
		test -f /var/log/messages || echo_log "failed to enable /var/log/messages"
	    fi
	else
	    if test -f /var/log/messages; then
		echo_log "/var/log/messages is already enabled. No action required."
	    else
		echo_log "/etc/rsyslog.d/50-default.conf not found: cannot enable /var/log/messages."
	    fi
	fi
    fi
}

function restore_messages {
    cd /etc/rsyslog.d
    if test -f 50-default.conf.origmrk; then
	echo_log "Restore original /etc/rsyslog.d/50-default.conf"
	if ! $DRYRUN; then
	    mv 50-default.conf.origmrk 50-default.conf
	    service rsyslog restart
	fi
    fi
}


###########################################################################
# grub menu:

function setup_grub {
    RUN_UPDATE=false

    # grub configuration file:
    if test -f /etc/default/grub.origmrk; then
	echo_log "Grub menu has already been configured."
    elif test -f /etc/default/grub; then
	cd /etc/default
	echo_log "Configure grub menu."
	if ! $DRYRUN; then
	    cp grub grub.origmrk
	    sed -e 's/GRUB_HIDDEN/#GRUB_HIDDEN/; s/GRUB_TIMEOUT_STYLE=/#GRUB_TIMEOUT_STYLE=/; s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/; /GRUB_CMDLINE_LINUX=/aexport GRUB_CMDLINE_RTAI=""' grub.origmrk > grub
	    ( echo; echo "GRUB_DISABLE_SUBMENU=y"; echo; echo "GRUB_DISABLE_RECOVERY=true" ) >> grub
	    RUN_UPDATE=true
	fi
    else
	echo_log "/etc/default/grub not found: cannot configure grub menu."
    fi

    # grub linux kernel script:
    if test -f /etc/grub.d/10_linux.origmrk; then
	echo_log "Grub linux script has already been configured."
    elif test -f /etc/grub.d/10_linux; then
	cd /etc/grub.d
	echo_log "Configure grub linux entries."
	if ! $DRYRUN; then
	    mv 10_linux 10_linux.origmrk
	    awk '{
                if ( /export linux_gfx/ ) {
                    ++level 
                }
                if ( level > 0 && /EOF/ ) {
                    print
                    print "\ncat << EOF\nload_env rtai_cmdline\nEOF"
                    next
                }
                if ( /initramfs=$/ ) {
                    print "  # check for RTAI kernel:"
                    print "  CMDLINE_RTAI=\"\""
                    print "  if grep -q \"CONFIG_IPIPE=y\" \"${config}\"; then"
                    print "      CMDLINE_RTAI=\"${GRUB_CMDLINE_RTAI} \\$rtai_cmdline\""
                    print "  fi"
                    print ""
                }
            }1' /etc/grub.d/10_linux.origmrk | \
	    sed -e '/SUPPORTED_INITS/{s/ systemd.*systemd//; s/ upstart.*upstart//;}' -e '/\${GRUB_CMDLINE_LINUX}.*\${GRUB_CMDLINE_LINUX_DEFAULT}/s/\(${GRUB_CMDLINE_LINUX}.*\)\(${GRUB_CMDLINE_LINUX_DEFAULT}\)/\1${CMDLINE_RTAI} \2/' > 11_linux
	    if ! grep -q GRUB_DISABLE_SUBMENU 11_linux > /dev/null; then
		sed -i -e '/if .*$in_submenu.*; then/,/fi$/s/^/#/' 11_linux
	    fi
	    chmod a-x 10_linux.origmrk
	    chmod a+x 11_linux
	    RUN_UPDATE=true
	fi
    else
	echo_log "/etc/grub.d/10_linux not found: cannot configure grub linux entries."
    fi
    if test -f /boot/grub/grubenv; then
	echo_log "Enable reboot requests for normal user."
	if ! $DRYRUN; then
	    chmod a+w /boot/grub/grubenv
	fi
    else
	echo_log "/boot/grub/grubenv not found: cannot enable reboot requests for normal user."
    fi
    if $RUN_UPDATE && ! $DRYRUN; then
	update-grub
    fi
}

function restore_grub {
    cd /etc/default
    if test -f grub.origkp; then
	echo_log "Restore original grub kernel parameter"
	if ! $DRYRUN; then
	    mv grub.origkp grub
	    RUN_UPDATE=true
	fi
    fi
    if test -f grub.origmrk; then
	echo_log "Restore original grub boot menu"
	if ! $DRYRUN; then
	    mv grub.origmrk grub
	    RUN_UPDATE=true
	fi
    fi
    cd /etc/grub.d
    if test -f 10_linux.origmrk; then
	echo_log "Restore original grub linux script"
	if ! $DRYRUN; then
	    mv 10_linux.origmrk 10_linux
	    chmod a+x 10_linux
	    rm -f 11_linux
	    RUN_UPDATE=true
	fi
    fi
    if test -f /boot/grub/grubenv; then
	echo_log "Remove grub environment variables."
	if ! $DRYRUN; then
	    grub-editenv - unset rtai_cmdline
	    grub-editenv - unset next_entry
 	    grub-editenv - unset rtaitest_pwd
	    grub-editenv - unset rtaitest_file
	    grub-editenv - unset rtaitest_index
	    grub-editenv - unset rtaitest_kernel_descr
	    grub-editenv - unset rtaitest_param_descr
	    grub-editenv - unset rtaitest_time
	    grub-editenv - unset rtaitest_specs
	    grub-editenv - unset rtaitest_state
	fi
	echo_log "Disable reboot requests for normal user."
	if ! $DRYRUN; then
	    chmod go-w /boot/grub/grubenv
	fi
    fi
    if $RUN_UPDATE && ! $DRYRUN; then
	update-grub
    fi
}


###########################################################################
# udev permissions for comedi:

function setup_comedi {
    if getent group iocard > /dev/null; then
	echo_log "Group \"iocard\" already exist."
    else
	echo_log "Add group \"iocard\"."
	if ! $DRYRUN; then
	    addgroup --system iocard
	fi
    fi
    if test -d /etc/udev/rules.d; then
	if test -f /etc/udev/rules.d/95-comedi.rules; then
	    echo_log "File /etc/udev/rules.d/95-comedi.rules already exist."
	else
	    echo_log "Assign comedi modules to \"iocard\" group via udev rule in \"/etc/udev/rules.d\"."
	    if ! $DRYRUN; then
		{
		    echo "# Add comedi DAQ boards to iocard group."
		    echo "# This file has been created by ${MAKE_RTAI_KERNEL}."
		    echo
		    echo 'KERNEL=="comedi*", MODE="0660", GROUP="iocard"'
		} > /etc/udev/rules.d/95-comedi.rules
		udevadm trigger
	    fi
	    echo_log ""
	    echo_log "You still need to assign users to the \"iocard\" group! Run"
	    echo_log "$ sudo adduser <username> iocard"
	    echo_log "for each user <username> that needs access to the data acquisition boards."
	fi
    else
	echo_log "Directory \"/etc/udev/rules.d\" does not exist - cannot assign comedi modules to iocard group."
    fi
}

function restore_comedi {
    if test -f /etc/udev/rules.d/95-comedi.rules && grep -q "${MAKE_RTAI_KERNEL}" /etc/udev/rules.d/95-comedi.rules; then
	echo_log "Remove comedi device drivers from \"iocard\" group."
	if ! $DRYRUN; then
	    rm /etc/udev/rules.d/95-comedi.rules
	    udevadm trigger
	fi
    fi
    if getent group iocard > /dev/null; then
	echo_log "Delete group \"iocard\"."
	if ! $DRYRUN; then
	    delgroup iocard
	fi
    fi
}


###########################################################################
# actions:

function info_all {

    if test -z $1; then
	ORIG_RTAI_PATCH="$RTAI_PATCH"
	RTAI_PATCH=""
	check_kernel_patch "$ORIG_RTAI_PATCH"
	RTAI_PATCH="$ORIG_RTAI_PATCH"
	rm -f lsmod.dat
	rm -f results-cpu?????.dat
	print_kernel_info 0
	rm -f results-cpu?????.dat
    else

	case $1 in

	    grub ) print_grub env ;;

	    settings )
		print_settings
		echo
		echo "You may modify the settings by the respective command line options (check \$ ${MAKE_RTAI_KERNEL} help),"
		echo "by setting them in the configuration file \"${MAKE_RTAI_CONFIG}\""
		echo "(create configuration file by \$ ${MAKE_RTAI_KERNEL} config), or"
		echo "by editing the variables directly in the ${MAKE_RTAI_KERNEL} script."
		;;

	    setup ) print_setup ;;

	    log ) print_log ;;

	    configs )
		shift
		print_kernel_configs $@
		;;

	    menu ) menu_kernel ;;

	    kernel ) print_kernel ;;

	    cpu|cpus ) rm -f results-cpu?????.dat; print_cpus; rm -f results-cpu?????.dat; ;;

	    interrupts ) print_interrupts ;;

	    rtai) print_rtai_info ;;

	esac
    fi
}

function setup_features {
    check_root
    if test -z $1; then
	setup_messages
	setup_grub
	setup_comedi
	setup_kernel_param $KERNEL_PARAM
    else
	for TARGET; do
	    case $TARGET in
		messages ) setup_messages ;;
		grub ) setup_grub ;;
		comedi ) setup_comedi ;;
		kernel ) setup_kernel_param $KERNEL_PARAM ;;
		rtai ) setup_rtai "$2" ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function restore_features {
    check_root
    if test -z $1; then
	restore_messages
	restore_kernel_param
	restore_grub
	restore_comedi
	restore_test_batch
	restore_rtai
    else
	for TARGET; do
	    case $TARGET in
		messages ) restore_messages ;;
		grub ) restore_grub ;;
		comedi ) restore_comedi ;;
		kernel ) restore_kernel_param ;;
		testbatch ) restore_test_batch ;;
		rtai ) restore_rtai ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function init_installation {
    check_root
    install_packages ||	return 1
    setup_messages
    setup_grub
    setup_comedi
    download_rtai
    print_rtai_info
}

function full_install {
    NEW_KERNEL_CONFIG=true
    check_root

    SECONDS=0

    install_packages ||	return 1

    uninstall_kernel
    ${MAKE_NEWLIB} && uninstall_newlib
    ${MAKE_MUSL} && uninstall_musl
    ${MAKE_RTAI} && uninstall_rtai
    ${MAKE_COMEDI} && uninstall_comedi

    ${MAKE_RTAI} && { download_rtai || return 1; }
    ${MAKE_NEWLIB} && { download_newlib || MAKE_NEWLIB=false; }
    ${MAKE_MUSL} && { download_musl || MAKE_MUSL=false; }
    ${MAKE_COMEDI} && { download_comedi || MAKE_COMEDI=false; }
    ${MAKE_COMEDI} && download_comedilib
    ${MAKE_COMEDI} && download_comedicalib
    download_kernel || return 1

    unpack_kernel && patch_kernel && build_kernel || return 1

    ${MAKE_NEWLIB} && { build_newlib || MAKE_NEWLIB=false; }
    ${MAKE_MUSL} && { build_musl || MAKE_MUSL=false; }
    ${MAKE_RTAI} && { build_rtai || return 1; }
    ${MAKE_COMEDI} && { build_comedi || MAKE_COMEDI=false; }
    ${MAKE_COMEDI} && build_comedilib
    ${MAKE_COMEDI} && build_comedicalib

    SECS=$SECONDS
    let MIN=${SECS}/60
    let SEC=${SECS}%60

    echo_log
    echo_log "Done!"
    echo_log "Full build took ${SECS} seconds ($(printf "%02d:%02d" $MIN $SEC))."
    echo_log "Please reboot into the ${KERNEL_NAME} kernel by executing"
    echo_log "$ ./${MAKE_RTAI_KERNEL} reboot"
    echo_log
}

function reconfigure {
    RECONFIGURE_KERNEL=true
    check_root

    SECONDS=0

    uninstall_kernel
    unpack_kernel && patch_kernel && build_kernel || return 1

    ${MAKE_NEWLIB} && { build_newlib || MAKE_NEWLIB=false; }
    ${MAKE_MUSL} && { build_musl || MAKE_MUSL=false; }

    ${MAKE_RTAI} && uninstall_rtai
    ${MAKE_RTAI} && { build_rtai || return 1; }

    ${MAKE_COMEDI} && uninstall_comedi
    ${MAKE_COMEDI} && build_comedi

    SECS=$SECONDS
    let MIN=${SECS}/60
    let SEC=${SECS}%60

    echo_log
    echo_log "Done!"
    echo_log "Build took ${SECS} seconds ($(printf "%02d:%02d" $MIN $SEC), COMPILE_TIME=${COMPILE_TIME} seconds)."
    echo_log "Please reboot into the ${KERNEL_NAME} kernel by executing"
    echo_log "$ ./${MAKE_RTAI_KERNEL} reboot"
    echo_log
}

function download_all {
    check_root
    if test -z $1; then
	download_kernel
	${MAKE_NEWLIB} && download_newlib
	${MAKE_MUSL} && download_musl
	${MAKE_RTAI} && download_rtai
	${MAKE_COMEDI} && download_comedi
	${MAKE_COMEDI} && download_comedilib
	${MAKE_COMEDI} && download_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		kernel ) download_kernel ;;
 		newlib ) download_newlib ;;
 		musl ) download_musl ;;
		rtai ) download_rtai ;;
		showroom ) download_showroom ;;
		comedi ) download_comedi ;;
		comedilib ) download_comedilib ;;
		comedicalib ) download_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function update_all {
    check_root
    if test -z $1; then
	${MAKE_NEWLIB} && update_newlib
	${MAKE_MUSL} && update_musl
	${MAKE_RTAI} && update_rtai
	${MAKE_COMEDI} && update_comedi
    else
	for TARGET; do
	    case $TARGET in
		newlib ) update_newlib ;;
		musl ) update_musl ;;
		rtai ) update_rtai ;;
		showroom ) update_showroom ;;
		comedi ) update_comedi ;;
		comedilib ) update_comedilib ;;
		comedicalib ) update_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function build_all {
    check_root
    if test -z "$1"; then
	unpack_kernel && patch_kernel && build_kernel || return 1
	${MAKE_NEWLIB} && { build_newlib || MAKE_NEWLIB=false; }
	${MAKE_MUSL} && { build_musl || MAKE_MUSL=false; }
	${MAKE_RTAI} && { build_rtai || return 1; }
	${MAKE_COMEDI} && build_comedi
	${MAKE_COMEDI} && build_comedilib
	${MAKE_COMEDI} && build_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		kernel ) 
		    unpack_kernel && patch_kernel && build_kernel || return 1
		    ${MAKE_NEWLIB} && { build_newlib || MAKE_NEWLIB=false; }
		    ${MAKE_MUSL} && { build_musl || MAKE_MUSL=false; }
		    ${MAKE_RTAI} && { build_rtai || return 1; }
		    ${MAKE_COMEDI} && build_comedi
		    ;;
		newlib )
		    build_newlib || return 1
		    ${MAKE_RTAI} && { build_rtai || return 1; }
		    ${MAKE_COMEDI} && build_comedi
		    ;;
		musl )
		    build_musl || return 1
		    ${MAKE_RTAI} && { build_rtai || return 1; }
		    ${MAKE_COMEDI} && build_comedi
		    ;;
		rtai ) 
		    build_rtai || return 1
		    ${MAKE_COMEDI} && build_comedi
		    ;;
		showroom ) 
		    build_showroom ;;
		comedi ) 
		    build_comedi ;;
		comedilib ) 
		    build_comedilib ;;
		comedicalib ) 
		    build_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function buildplain_kernel {
    check_root

    SECONDS=0

    NEW_KERNEL_CONFIG=true
    uninstall_kernel
    unpack_kernel && build_kernel || return 1

    SECS=$SECONDS
    let MIN=${SECS}/60
    let SEC=${SECS}%60

    echo_log
    echo_log "Done!"
    echo_log "Build took ${SECS} seconds ($(printf "%02d:%02d" $MIN $SEC))."
    echo_log "Please reboot into the ${KERNEL_NAME} kernel by executing"
    echo_log "$ ./${MAKE_RTAI_KERNEL} reboot"
    echo_log
}

function clean_all {
    check_root
    if test -z "$1"; then
	clean_kernel
	${MAKE_NEWLIB} && clean_newlib
	${MAKE_MUSL} && clean_musl
	${MAKE_RTAI} && clean_rtai
	${MAKE_COMEDI} && clean_comedi
	${MAKE_COMEDI} && clean_comedilib
	${MAKE_COMEDI} && clean_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		kernel ) clean_kernel ;;
		newlib ) clean_newlib ;;
		musl ) clean_musl ;;
		rtai ) clean_rtai ;;
		showroom ) clean_showroom ;;
		comedi ) clean_comedi ;;
		comedilib ) clean_comedilib ;;
		comedicalib ) clean_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function install_all {
    check_root
    if test -z "$1"; then
	install_packages
	install_kernel
	${MAKE_NEWLIB} && install_newlib
	${MAKE_MUSL} && install_musl
	${MAKE_RTAI} && install_rtai
	${MAKE_COMEDI} && install_comedi
	${MAKE_COMEDI} && install_comedilib
	${MAKE_COMEDI} && install_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		packages ) install_packages ;;
		kernel ) install_kernel ;;
		newlib ) install_newlib ;;
		musl ) install_musl ;;
		rtai ) install_rtai ;;
		comedi ) install_comedi ;;
		comedilib ) install_comedilib ;;
		comedicalib ) install_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function uninstall_all {
    check_root
    if test -z "$1"; then
	uninstall_kernel
	${MAKE_NEWLIB} && uninstall_newlib
	${MAKE_MUSL} && uninstall_musl
	${MAKE_RTAI} && uninstall_rtai
	${MAKE_COMEDI} && uninstall_comedi
	${MAKE_COMEDI} && uninstall_comedilib
	${MAKE_COMEDI} && uninstall_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		kernel ) uninstall_kernel ;;
		newlib ) uninstall_newlib ;;
		musl ) uninstall_musl ;;
		rtai ) uninstall_rtai ;;
		comedi ) uninstall_comedi ;;
		comedilib ) uninstall_comedilib ;;
		comedicalib ) uninstall_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function remove_all {
    check_root
    if test -z "$1"; then
	remove_kernel
	${MAKE_NEWLIB} && remove_newlib
	${MAKE_MUSL} && remove_musl
	${MAKE_RTAI} && remove_rtai
	${MAKE_COMEDI} && remove_comedi
	${MAKE_COMEDI} && remove_comedilib
	${MAKE_COMEDI} && remove_comedicalib
    else
	for TARGET; do
	    case $TARGET in
		kernel ) remove_kernel ;;
		newlib ) remove_newlib ;;
		musl ) remove_musl ;;
		rtai ) remove_rtai ;;
		showroom ) remove_showroom ;;
		comedi ) remove_comedi ;;
		comedilib ) remove_comedilib ;;
		comedicalib ) remove_comedicalib ;;
		* ) echo "unknown target $TARGET" ;;
	    esac
	done
    fi
}

function clean_unpack_patch_kernel {
   check_root && clean_kernel && unpack_kernel && patch_kernel
 }

function print_help {
    if test -z "$1"; then
	help_usage
    else
	for TARGET; do
	    case $TARGET in
		info) help_info ;;
		setup) help_setup ;;
		restore) help_setup ;;
		reboot) help_reboot ;;
		test) help_test ;;
		report) help_report ;;
		* ) echo "sorry, no help available for $TARGET" ;;
	    esac
	done
    fi
}

###########################################################################
###########################################################################
# main script:

# read in configuration:
if test -f "$MAKE_RTAI_CONFIG"; then
    source "$MAKE_RTAI_CONFIG"
fi

while test "x${1:0:1}" = "x-"; do
    case $1 in
	--help )
	    help_usage
	    exit 0
	    ;;

	--version )
	    print_version
	    exit 0
	    ;;

	-d )
	    shift
	    DRYRUN=true
	    ;;
	-s )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		KERNEL_PATH=$1
		shift
	    else
		echo "you need to specify a path for the kernel sources after the -s option"
		exit 1
	    fi
	    ;;
	-n )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		KERNEL_NUM=$1
		shift
	    else
		echo "you need to specify a name for the kernel after the -n option"
		exit 1
	    fi
	    ;;
	-r )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		RTAI_DIR=$1
		shift
		if test "xRTAI_DIR" != "x$DEFAULT_RTAI_DIR"; then
		    RTAI_DIR_CHANGED=true
		fi
	    else
		echo "you need to specify an rtai distribution after the -r option"
		exit 1
	    fi
	    ;;
	-p )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		RTAI_PATCH=$1
		shift
		RTAI_PATCH_CHANGED=true
	    else
		echo "you need to specify an rtai patch file after the -p option"
		exit 1
	    fi
	    ;;
	-k )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		LINUX_KERNEL=$1
		shift
		LINUX_KERNEL_CHANGED=true
	    else
		echo "you need to specify a linux kernel version after the -k option"
		exit 1
	    fi
	    ;;
	-c )
	    shift
	    if test -n "$1" && test "x$1" != "xreconfigure"; then
		KERNEL_CONFIG="$1"
		shift
		NEW_KERNEL_CONFIG=true
	    else
		echo "you need to specify a kernel configuration after the -c option"
		exit 1
	    fi
	    ;;
	-l )
	    shift
	    RUN_LOCALMOD=false
	    ;;
	-m )
	    shift
	    RTAI_MENU=true
	    ;;
	-* )
	    echo "unknown options $1"
	    exit 1
    esac
done

if $RTAI_DIR_CHANGED && ! $RTAI_PATCH_CHANGED && ! $LINUX_KERNEL_CHANGED; then
    echo_log "Warning: you changed rtai sources and you might need to adapt the linux kernel version and rtai patch file to it."
    sleep 2
fi

set_variables

if test "x$1" != "xhelp" && test "x$1" != "xversion" && test "x$1" != "xinfo" && test "x$1" != "xreport" && test "x$1" != "xconfig" && ! ( test "x$1" = "xtest" && test "x$2" = "xbatchscript" ); then
    rm -f "$LOG_FILE"
fi

ACTION=$1
shift
case $ACTION in

    help ) 
	print_help $@ 
	exit 0
	;;

    version ) 
	print_version
	exit 0
	;;

    info ) info_all $@
	exit 0
	;;

    config ) 
	if test -f "${MAKE_RTAI_CONFIG}"; then
	    echo "Configuration file \"${MAKE_RTAI_CONFIG}\" already exists!"
	else
	    print_config > "${MAKE_RTAI_CONFIG}"
	    echo "Wrote configuration to file \"${MAKE_RTAI_CONFIG}\"".
	fi
	exit 0
	;;

    test ) 
	test_kernel $@
	exit $? ;;

    report ) 
	test_report $@
	exit 0 ;;

    init) init_installation ;;
    setup ) setup_features $@ ;;
    restore ) restore_features $@ ;;
    download ) download_all $@ ;;
    update ) update_all $@ ;;
    patch ) clean_unpack_patch_kernel ;;
    prepare ) prepare_kernel_configs $@ ;;
    build ) build_all $@ ;;
    buildplain ) buildplain_kernel $@ ;;
    install ) install_all $@ ;;
    clean ) clean_all $@ ;;
    uninstall ) uninstall_all $@ ;;
    remove ) remove_all $@ ;;
    reboot ) reboot_kernel $@ ;;

    reconfigure ) reconfigure ;;

    * ) if test -n "$ACTION"; then
	    echo "unknown action \"$ACTION\""
	    echo
	    help_usage
	    exit 1
	else
	    full_install
	fi ;;

esac

STATUS=$?

if test -f "$LOG_FILE"; then
    echo
    echo "Summary of log messages"
    echo "-----------------------"
    cut -c 10- "$LOG_FILE"
    rm "$LOG_FILE"
fi

exit $STATUS
