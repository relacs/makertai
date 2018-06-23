/* Add GPL header */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/cpu.h>
#include <linux/pm_qos.h>   // since 3.2

MODULE_LICENSE( "GPL" );
MODULE_DESCRIPTION( "Add a PM QoS request for zero latency of a specific CPU" );
MODULE_AUTHOR( "Jan Benda <jan.benda@uni-tuebingen.de>" );


/* The id of the CPU on which the latency should be limited to zero.
   If -1: take the first isolated CPU.
   If -2: apply zero latency to all CPUs. */
static int cpu_id = -2;
module_param( cpu_id, int, S_IRUSR | S_IRGRP | S_IROTH );
MODULE_PARM_DESC( cpu_id, "Id of CPU on which latencies should be set to zero" );


#if LINUX_VERSION_CODE < KERNEL_VERSION(4,0,0)
//extern unsigned long cpu_isolated_map;  // symbol is exported by RTAI patch
#else
extern cpumask_var_t cpu_isolated_map;
#endif
int isolatedCPUId = -1;


static struct pm_qos_request cpu_dma_latency_req;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,8,0)
#ifdef CONFIG_PM
static struct dev_pm_qos_request cpu_resume_latency_req;  // since 3.2
#endif
#endif


static int __init init_cpulatency( void )
{
  int i;
  int latency = 0;

  if ( cpu_id == -1 ) {
    // find first isolated cpu:
#ifdef CONFIG_SMP
    for ( i=0; i<NR_CPUS; i++ ) {
#if LINUX_VERSION_CODE < KERNEL_VERSION(4,0,0)
      if ( 0 ) {
	//if ( cpu_isolated_map & (1<<i) ) {
#else
      if ( cpumask_test_cpu( i, cpu_isolated_map ) ) {
#endif
	isolatedCPUId = i;
	break;
      }
    }
#endif
    if ( isolatedCPUId >= 0 )
      cpu_id = isolatedCPUId;
    else
      printk( KERN_INFO "cpulatency: no isolated CPU\n");
  }

#if LINUX_VERSION_CODE < KERNEL_VERSION(3,8,0)
    cpu_id = -2;
#else
#ifndef CONFIG_PM
    /*  Device specific PM QoS only implemented for CONFIG_PM enabled:
	"Device power management core functionality" */
    cpu_id = -2;
#endif
#endif

  if ( cpu_id < 0 ) {
    memset( &cpu_dma_latency_req, 0, sizeof cpu_dma_latency_req );
    pm_qos_add_request( &cpu_dma_latency_req, PM_QOS_CPU_DMA_LATENCY, latency );
    printk( KERN_INFO "cpulatency: set latency of all CPUs to zero\n" );
    printk( KERN_INFO "cpulatency: CPU=all\n" );
    /* This is equivalent to what the /dev/cpu_dma_latency file does! */
    return 0;
  }

#if LINUX_VERSION_CODE >= KERNEL_VERSION(3,8,0)
#ifdef CONFIG_PM
  else {
    struct device *cpudev = get_cpu_device( cpu_id );
    if ( cpudev != NULL ) {
      memset( &cpu_resume_latency_req, 0, sizeof cpu_resume_latency_req );
#if LINUX_VERSION_CODE < KERNEL_VERSION(3,15,0)
      dev_pm_qos_add_request( cpudev, &cpu_resume_latency_req, DEV_PM_QOS_LATENCY, latency );
#else
      dev_pm_qos_add_request( cpudev, &cpu_resume_latency_req, DEV_PM_QOS_RESUME_LATENCY, latency );
#endif
      printk( KERN_INFO "cpulatency: set latency for CPU %d to zero\n", cpu_id );
      printk( KERN_INFO "cpulatency: CPU=%d\n", cpu_id );
    }
    else {
      printk( KERN_INFO "cpulatency: invalid CPU id %d\n", cpu_id );
      printk( KERN_INFO "cpulatency: CPU=none\n" );
      return -EINVAL;
    }
  }
#endif
#endif

  return 0;
}


static void __exit cleanup_cpulatency( void )
{
  if ( cpu_id < 0 )
    pm_qos_remove_request( &cpu_dma_latency_req );

#ifdef CONFIG_PM
  else
    dev_pm_qos_remove_request( &cpu_resume_latency_req );
#endif

  printk( KERN_INFO "cpulatency: removed all power management requests on CPUs\n" );
}

module_init( init_cpulatency );
module_exit( cleanup_cpulatency );

/*
check with

sudo hexdump -x /dev/cpu_dma_latency
 */
