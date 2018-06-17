/* Add GPL header */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/cpu.h>
#include <linux/pm_qos.h>

MODULE_LICENSE( "GPL" );
MODULE_DESCRIPTION( "Add a PM QoS request for zero latency of a specific CPU" );
MODULE_AUTHOR( "Jan Benda <jan.benda@uni-tuebingen.de>" );

// MODULE_SUPPORTED_DEVICE("cpu_dma_latency"); ???

#if LINUX_VERSION_CODE < KERNEL_VERSION(4,0,0)
//  extern unsigned long cpu_isolated_map; // I do not find this in the kernel headers
#else
  extern cpumask_var_t cpu_isolated_map;
#endif
int isolatedCPUId = -1;

/* The id of the CPU on which the resume latency should be limited.
   If -1 then take the first isolated CPU.
   If -2 then apply zero latency to all CPUs. */
static int cpu_id = -2;

// module_param( cpu_dma_latency, int, S_IRUSR | S_IRGRP | S_IROTH );
// MODULE_PARM_DESC( cpu_dma_latency, "CPU DMA latency in microseconds" );


static struct pm_qos_request cpu_dma_latency_req;
static struct dev_pm_qos_request cpu_resume_latency_req;


static int __init init_cpulatency( void )
{
  int i;
  int latency = 0;

  printk( KERN_INFO "INIT CPULATENCY\n" );

  if ( cpu_id == -1 ) {
    // find first isolated cpu:
#ifdef CONFIG_SMP
    for ( i=0; i<NR_CPUS; i++ ) {
#if LINUX_VERSION_CODE < KERNEL_VERSION(4,0,0)
      //      if ( cpu_isolated_map & (1<<i) ) {
      if ( 0 ) {
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
      printk( KERN_INFO "no isolated CPU - set latency for all CPUs to zero\n");
  }

  if ( cpu_id < 0 ) {
    /* Set maximum CPU latency to zero for all CPUs: */
    /* This is equivalent to what the /dev/cpu_dma_latency file does. */
    memset( &cpu_dma_latency_req, 0, sizeof cpu_dma_latency_req );
    printk( KERN_INFO "cpulatency: setting latency of all CPUs to zero\n" );
    pm_qos_add_request( &cpu_dma_latency_req, PM_QOS_CPU_DMA_LATENCY, latency );
  }
  else {
    struct device *cpudev = get_cpu_device( cpu_id );
    if ( cpudev != NULL ) {
      printk( KERN_INFO "cpulatency: setting latency for CPU %d to zero\n", cpu_id );
      // only implemented for CONFIG_PM kernel parameter!
#if LINUX_VERSION_CODE < KERNEL_VERSION(4,0,0)
      dev_pm_qos_add_request( cpudev, &cpu_resume_latency_req, DEV_PM_QOS_LATENCY, latency );
#else
      dev_pm_qos_add_request( cpudev, &cpu_resume_latency_req, DEV_PM_QOS_RESUME_LATENCY, latency );
#endif
    }
    else {
      printk( KERN_INFO "Invalid CPU id %d\n", cpu_id );
      return -EINVAL;
    }
  }

  return 0;
}


static void __exit cleanup_cpulatency( void )
{
  printk(KERN_INFO "cpulatency: removing PM QoS request\n");

  if ( cpu_id < 0 )
    pm_qos_remove_request( &cpu_dma_latency_req );
  else
    dev_pm_qos_remove_request( &cpu_resume_latency_req );
    
  printk( KERN_INFO "EXIT CPULATENCY\n" );
}

module_init( init_cpulatency );
module_exit( cleanup_cpulatency );
