//
//	LoadInfo.m - Load History Container Class
//


#import "mach/mach_host.h"
#import "LoadInfo.h"


@implementation LoadInfo


static void getLoadStat (host_load_info_t loadstat)
{
	mach_msg_type_number_t count = HOST_LOAD_INFO_COUNT;
	
	if (host_statistics(mach_host_self(), HOST_LOAD_INFO, (host_info_t) loadstat, &count) != KERN_SUCCESS)
		NSLog (@"Failed to get Load statistics.");
}


- (id)initWithCapacity:(unsigned)numItems
{
	self = [super init];
	size = numItems;
	loaddata = calloc(numItems, sizeof(LoadData));
	if (loaddata == NULL) {
		NSLog (@"Failed to allocate buffer for LoadInfo");
		return (nil);
	}
	inptr = 0;
	outptr = -1;
	return (self);
}


- (void)refresh
{
	host_load_info_data_t	loadstat;
	
	getLoadStat (&loadstat);

	loaddata[inptr].average = (double)loadstat.avenrun[0] / (double)LOAD_SCALE;
	loaddata[inptr].machFactor = (double)loadstat.mach_factor[0] / (double)LOAD_SCALE;

	//NSLog(@"average = %6.3f machFactor = %6.3f", loaddata[inptr].average, loaddata[inptr].machFactor);

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(LoadDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = loaddata[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(LoadDataPtr)ptr
{
	*ptr = loaddata[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(LoadDataPtr)ptr
{
	*ptr = loaddata[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
