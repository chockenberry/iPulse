//
//	PowerInfo.m - Battery Usage Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>

///#define MAX_PROCESSORS 2

typedef struct BatteryData
{
	BOOL batteryPresent;
	BOOL batteryCharging;
	BOOL batteryChargerConnected;
	double batteryLevel;
	int batteryAmperage;
	int batteryVoltage;
	int batteryMinutesRemaining;
	BOOL batteryMinutesIsValid;
} BatteryData, *BatteryDataPtr;


@interface PowerInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	BatteryDataPtr batteryData;
	
	int last;
	int interval;

	BOOL isAvailable;
}

- (PowerInfo *)initWithCapacity:(unsigned)numItems;
- (BOOL)isAvailable;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(BatteryDataPtr)ptr;
- (void)getCurrent:(BatteryDataPtr)ptr;
- (void)getLast:(BatteryDataPtr)ptr;
- (int)getSize;

@end
