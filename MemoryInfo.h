//
//	MemoryInfo.h - Memory Usage History Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>


typedef struct vmdata {
	double wired;
	int wiredCount;
	double active;
	int activeCount;
	double inactive;
	int inactiveCount;
	double free;
	int freeCount;
	int pageins;
	int pageouts;
}	VMData, *VMDataPtr;


@interface MemoryInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	VMDataPtr vmdata;
	vm_statistics_data_t lastvmstat;
}

- (MemoryInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(VMDataPtr)ptr;
- (void)getCurrent:(VMDataPtr)ptr;
- (void)getLast:(VMDataPtr)ptr;
- (int)getSize;

@end
