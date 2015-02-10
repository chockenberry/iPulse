//
//	ProcessorInfo.m - Processor Usage History Container Class
//


#import "mach/mach_host.h"
#import "ProcessorInfo.h"


@implementation ProcessorInfo

/*
	kern_return_t error;
	natural_t processorCount;
	processor_flavor_t flavor;
	processor_info_array_t infoArray;
	mach_msg_type_number_t infoCount;
	int infoSize;
	int i, j;
	unsigned int kern, user, nice, idle, total;
	
	flavor = PROCESSOR_CPU_LOAD_INFO;
	error = host_processor_info(mach_host_self(), flavor, &processorCount, &infoArray, &infoCount);
	if (error != KERN_SUCCESS)
	{
		NSLog (@"Failed to get CPU statistics.");
	}
	infoSize = infoCount / processorCount;	// actual data size for each processor
	
	for (i=0; i < processorCount; i++ )
	{
		kern = infoArray[(i * infoSize) + CPU_STATE_SYSTEM];
		user = infoArray[(i * infoSize) + CPU_STATE_USER];
		nice = infoArray[(i * infoSize) +  CPU_STATE_NICE];
		idle = infoArray[(i * infoSize) + CPU_STATE_IDLE]; 
		total = kern + user + nice + idle;
	}
	
	vm_deallocate( mach_task_self(), (vm_address_t)infoArray, infoCount ); // don't forget to call this
*/

static void getCPUStat (host_cpu_load_info_t cpustat)
{
	mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
	
	if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, (host_info_t) cpustat, &count) != KERN_SUCCESS)
		NSLog (@"Failed to get CPU statistics.");
}


- (id)initWithCapacity:(unsigned)numItems
{
	int i, j;
	
	self = [super init];
	size = numItems;
	cpudata = calloc(numItems, sizeof(CPUData));
	if (cpudata == NULL) {
		NSLog (@"Failed to allocate buffer for ProcessorInfo");
		return (nil);
	}
	
	inptr = 0;
	outptr = -1;
	
	for (i = 0; i < size; i++)
	{
		cpudata[i].processorCount = 1;
			
		for (j = 0; j < MAX_PROCESSORS; j++)
		{
			cpudata[i].system[j] = 0.0;
			cpudata[i].user[j] = 0.0;
			cpudata[i].nice[j] = 0.0;
			cpudata[i].idle[j] = 0.0;
		}
	}
	
	getCPUStat (&lastcpustat);
	return (self);
}


- (void)refresh
{
	//host_cpu_load_info_data_t cpustat;
	cpustats_t newcpustat;
	double total;
	double deltaSystem, deltaUser, deltaNice, deltaIdle;
	double deltaTotal;
	
	kern_return_t error;
	natural_t processorCount;
	processor_flavor_t flavor;
	processor_info_array_t infoArray;
	mach_msg_type_number_t infoCount;
	int infoSize;
	int i;
	//unsigned int system, user, nice, idle, total;

	flavor = PROCESSOR_CPU_LOAD_INFO;
	error = host_processor_info(mach_host_self(), flavor, &processorCount, &infoArray, &infoCount);
	if (error != KERN_SUCCESS)
	{
		NSLog (@"Failed to get CPU statistics.");
	}
	infoSize = infoCount / processorCount;	// actual data size for each processor
	
	//NSLog(@"infoCount = %d, processorCount = %d, infoSize = %d", infoCount, processorCount, infoSize);
	
	if (processorCount > MAX_PROCESSORS)
	{
		processorCount = MAX_PROCESSORS;
	}
	
	newcpustat.processorCount = processorCount;
	for (i = 0; i < processorCount; i++ )
	{
		newcpustat.system[i] = infoArray[(i * infoSize) + CPU_STATE_SYSTEM];
		newcpustat.user[i] = infoArray[(i * infoSize) + CPU_STATE_USER];
		newcpustat.nice[i] = infoArray[(i * infoSize) +  CPU_STATE_NICE];
		newcpustat.idle[i] = infoArray[(i * infoSize) + CPU_STATE_IDLE]; 
	}
	
	vm_deallocate( mach_task_self(), (vm_address_t)infoArray, infoCount ); // don't forget to call this
	
	total = 0.0;
	for (i = 0; i < processorCount; i++)
	{
		//NSLog(@"processor: %d cpustat = %d %d %d %d", i, newcpustat.system[i], newcpustat.user[i], newcpustat.nice[i], newcpustat.idle[i]);
		total += newcpustat.system[i] + newcpustat.user[i] + newcpustat.nice[i] + newcpustat.idle[i];
	}
	
	cpudata[inptr].systemTotal = 0.0;
	cpudata[inptr].userTotal = 0.0;
	cpudata[inptr].niceTotal = 0.0;
	cpudata[inptr].idleTotal = 0.0;
	for (i = 0; i < processorCount; i++)
	{
		cpudata[inptr].systemTotal = (double) newcpustat.system[i] / total;
		cpudata[inptr].userTotal = (double) newcpustat.user[i] / total;
		cpudata[inptr].niceTotal = (double) newcpustat.nice[i] / total;
		cpudata[inptr].idleTotal = (double) newcpustat.idle[i] / total;
	}
	//NSLog(@"cpudata = %6.3f %6.3f %6.3f %6.3f total = %6.3f", cpudata[inptr].systemTotal, cpudata[inptr].userTotal, cpudata[inptr].niceTotal, cpudata[inptr].idleTotal, total);
	
	for (i = 0; i < processorCount; i++)
	{
		deltaSystem = newcpustat.system[i] - newlastcpustat.system[i];
		deltaUser = newcpustat.user[i] - newlastcpustat.user[i];
		deltaNice = newcpustat.nice[i] - newlastcpustat.nice[i];
		deltaIdle = newcpustat.idle[i] - newlastcpustat.idle[i];
		deltaTotal = deltaSystem + deltaUser + deltaNice + deltaIdle;
	
		if (deltaTotal == 0.0)
		{
			cpudata[inptr].system[i] = 0.0;
			cpudata[inptr].user[i] = 0.0;
			cpudata[inptr].nice[i] = 0.0;
			cpudata[inptr].idle[i] = 0.0;			
		}
		else
		{
			cpudata[inptr].system[i] = deltaSystem / deltaTotal;
			cpudata[inptr].user[i] = deltaUser / deltaTotal;
			cpudata[inptr].nice[i] = deltaNice / deltaTotal;
			cpudata[inptr].idle[i] = deltaIdle / deltaTotal;			
		}

		//NSLog(@"processor: %d delta = %6.3f %6.3f %6.3f %6.3f total = %6.3f cpudata = %6.3f %6.3f %6.3f %6.3f", i, deltaSystem, deltaUser, deltaNice, deltaIdle, deltaTotal, cpudata[inptr].system[i], cpudata[inptr].user[i], cpudata[inptr].nice[i], cpudata[inptr].idle[i]);
	}
	
	cpudata[inptr].processorCount = newcpustat.processorCount;
	
#if 0
	// testing
	cpudata[inptr].processorCount = MAX_PROCESSORS;
//	cpudata[inptr].nice[0] = 1.0 - cpudata[inptr].system[0] - cpudata[inptr].user[0];
//	cpudata[inptr].idle[0] = 0.0;

	for (i = 1; i < cpudata[inptr].processorCount; i++)
	{
		cpudata[inptr].system[i] = cpudata[inptr].system[0] * (1.0 - (i * 0.1));
		cpudata[inptr].user[i] = cpudata[inptr].user[0] * (1.0 - (i * 0.1));
		cpudata[inptr].nice[i] = cpudata[inptr].nice[0] * (1.0 - (i * 0.1));
		cpudata[inptr].idle[i] = cpudata[inptr].idle[0] * (1.0 - (i * 0.1));
	}
#endif

	newlastcpustat = newcpustat;

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(CPUDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = cpudata[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(CPUDataPtr)ptr
{
	*ptr = cpudata[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(CPUDataPtr)ptr
{
	*ptr = cpudata[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
