//
//	ProcessorInfo.m - Processor Usage History Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>

//#define MAX_PROCESSORS 2
#define MAX_PROCESSORS 8

typedef struct cpustats
{
	int processorCount;
	unsigned long system[MAX_PROCESSORS];
	unsigned long user[MAX_PROCESSORS];
	unsigned long nice[MAX_PROCESSORS];
	unsigned long idle[MAX_PROCESSORS];
} cpustats_t;

typedef struct cpudata
{
	double userTotal;
	double systemTotal;
	double niceTotal;
	double idleTotal;
	int processorCount;
	double system[MAX_PROCESSORS];
	double user[MAX_PROCESSORS];
	double nice[MAX_PROCESSORS];
	double idle[MAX_PROCESSORS];
} CPUData, *CPUDataPtr;


@interface ProcessorInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	CPUDataPtr cpudata;
	host_cpu_load_info_data_t lastcpustat;
	cpustats_t newlastcpustat;
}

- (ProcessorInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(CPUDataPtr)ptr;
- (void)getCurrent:(CPUDataPtr)ptr;
- (void)getLast:(CPUDataPtr)ptr;
- (int)getSize;

@end
