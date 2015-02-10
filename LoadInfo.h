//
//	LoadInfo.h - Load History Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>


typedef struct loaddata {
	double	average;
	double	machFactor;
}	LoadData, *LoadDataPtr;


@interface LoadInfo : NSObject
{
	int			size;
	int			inptr;
	int			outptr;
	LoadDataPtr		loaddata;
}

- (LoadInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(LoadDataPtr)ptr;
- (void)getCurrent:(LoadDataPtr)ptr;
- (void)getLast:(LoadDataPtr)ptr;
- (int)getSize;

@end
