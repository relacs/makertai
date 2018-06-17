#include <linux/init.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/kthread.h>

MODULE_LICENSE( "GPL" );
MODULE_DESCRIPTION( "Poll a CPU to keep it in C0 state" );
MODULE_AUTHOR( "Jan Benda <jan.benda@uni-tuebingen.de>" );


struct task_struct *task;


int poll_task( void *data )
{
  int i;
  printk( KERN_INFO "RUN POLL\n");
  // allow_signal( SIGKILL );
  while ( ! kthread_should_stop() ) {
    i++;
    /*
    if ( signal_pending( current ) )
      break;
    */
  }
  return 0;
}


static int __init poll_init( void )
{
  printk( KERN_INFO "INIT POLL\n" );
  task = kthread_create( &poll_task, NULL, "poll" );
  if ( (task) ) {
    printk(KERN_INFO "POLL CREATED");
    // kthread_bind( task, int cpu );
    wake_up_process( task );
    printk( KERN_INFO "POLL Thread : %s\n",task->comm );
    return 0;
  }
  return -EFAULT;
}

static void __exit poll_exit( void )
{
  int ret = 0;
  ret = kthread_stop( task );
  if ( ! ret )
    printk( KERN_INFO "POLL STOPPED\n" );
  printk( KERN_INFO "EXIT POLL\n" );
}

module_init( poll_init );
module_exit( poll_exit );

// check with ps -ef | grep poll
