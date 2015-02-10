//
//	MemoryInfo.m - Memory Usage History Container Class
//


#import "mach/mach_host.h"
#import "MemoryInfo.h"


@implementation MemoryInfo


static void getVMStat (vm_statistics_t vmstat)
{
	mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
	
	if (host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t) vmstat, &count) != KERN_SUCCESS)
		NSLog (@"Failed to get VM statistics.");
}


- (id)initWithCapacity:(unsigned)numItems
{
	self = [super init];
	size = numItems;
	vmdata = calloc(numItems, sizeof(VMData));
	if (vmdata == NULL) {
		NSLog (@"Failed to allocate buffer for MemoryInfo");
		return (nil);
	}
	inptr = 0;
	outptr = -1;
	getVMStat (&lastvmstat);
	return (self);
}


- (void)refresh
{
	vm_statistics_data_t	vmstat;
	double			total;
	
	getVMStat (&vmstat);
	total = vmstat.wire_count + vmstat.active_count + vmstat.inactive_count + vmstat.free_count;
	vmdata[inptr].wired = vmstat.wire_count / total;
	vmdata[inptr].active = vmstat.active_count / total;
	vmdata[inptr].inactive = vmstat.inactive_count / total;
	vmdata[inptr].free = vmstat.free_count / total;
	vmdata[inptr].pageins =  vmstat.pageins - lastvmstat.pageins;
	vmdata[inptr].pageouts = vmstat.pageouts - lastvmstat.pageouts;
	vmdata[inptr].wiredCount = vmstat.wire_count;
	vmdata[inptr].activeCount = vmstat.active_count;
	vmdata[inptr].inactiveCount = vmstat.inactive_count;
	vmdata[inptr].freeCount = vmstat.free_count;
	lastvmstat = vmstat;
	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(VMDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = vmdata[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(VMDataPtr)ptr
{
	*ptr = vmdata[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(VMDataPtr)ptr
{
	*ptr = vmdata[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
