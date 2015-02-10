//
//	DiskInfo.h - Disk Usage History Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>
#import "sys/mount.h"

#import <IOKit/IOKitLib.h>
#import <IOKit/storage/IOBlockStorageDriver.h>

#define MAX_DISK_COUNT 12

typedef struct diskstats {
	int count;
	double used[MAX_DISK_COUNT];
	UInt32 blockSize[MAX_DISK_COUNT];
	UInt32 freeBlocks[MAX_DISK_COUNT];
	UInt32 availableBlocks[MAX_DISK_COUNT];
	char fsTypeName[MAX_DISK_COUNT][MFSNAMELEN]; // fs type name
	HFSUniStr255 fsMountName[MAX_DISK_COUNT]; // directory on which mounted
}
DiskStats;

typedef struct diskdata {
	DiskStats unlocked;
	DiskStats locked;

	UInt64 readCount;
	UInt64 readBytes;
	UInt64 writeCount;
	UInt64 writeBytes;
}
DiskData, *DiskDataPtr;


@interface DiskInfo : NSObject
{
	int			size;
	int			inptr;
	int			outptr;
	DiskDataPtr		diskdata;

	UInt64 lastReadCount;
	UInt64 lastReadBytes;
	UInt64 lastWriteCount;
	UInt64 lastWriteBytes;
}

- (DiskInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(DiskDataPtr)ptr;
- (void)getCurrent:(DiskDataPtr)ptr;
- (void)getLast:(DiskDataPtr)ptr;
- (int)getSize;

@end
