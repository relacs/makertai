/* Add GPL header */

#include<linux/init.h>
#include<linux/module.h>
#include <linux/version.h>
#include<linux/kernel.h>
#include <linux/pm_qos.h>

MODULE_LICENSE( "GPL" );
MODULE_DESCRIPTION( "Add a PM QoS request for zero latency of a specific CPU" );
MODULE_AUTHOR( "Jan Benda <jan.benda@uni-tuebingen.de>" );

MODULE_SUPPORTED_DEVICE("cpu_dma_latency");

// module_param( cpu_dma_latency, int, S_IRUSR | S_IRGRP | S_IROTH );
// MODULE_PARM_DESC( cpu_dma_latency, "CPU DMA latency in microseconds" );


static struct pm_qos_request cpu_dma_latency_req;


static int __init init_cpulatency( void )
{
  int latency = 0;

  printk( KERN_INFO "INIT CPULATENCY\n" );

  /* Set maximum CPU latency to zero for all CPUs: */
  /* This is equivalent to what the /dev/cpu_dma_latency file does. */
  memset( &cpu_dma_latency_req, 0, sizeof cpu_dma_latency_req );
  printk( KERN_INFO "cpulatency: setting CPU latency to zero\n" );
  pm_qos_add_request( &cpu_dma_latency_req, PM_QOS_CPU_DMA_LATENCY, latency );

  return 0;
}

static void __exit cleanup_cpulatency( void )
{
  printk(KERN_INFO "cpulatency: removing PM QoS request\n");

  pm_qos_remove_request( &cpu_dma_latency_req );

  printk( KERN_INFO "EXIT CPULATENCY\n" );
}

module_init( init_cpulatency );
module_exit( cleanup_cpulatency );

