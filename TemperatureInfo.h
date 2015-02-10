//
//	TemperatureInfo.m - Temperature History Container Class
//


#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_types.h>

#define MAX_PROCESSOR_SENSORS 2

typedef struct TemperatureData
{
	int temperatureCount;
	double temperatureLevel[MAX_PROCESSOR_SENSORS];
} TemperatureData, *TemperatureDataPtr;

typedef enum
{
	NoSensorType = 0,
	IOHWSensorSensorType = 1,
	AppleCPUThermoSensorType = 2,
	CpuidSensorType = 3,
	SMCSensorType = 4	
} SensorType;


@interface TemperatureInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	TemperatureDataPtr temperatureData;
	
	BOOL chudWorkaround;

	SensorType sensorType;
	char smcSensorKey[5];
	
	int diodeCount;
	unsigned short diodeM[MAX_PROCESSOR_SENSORS]; // diode M value (scaling factor)
	short diodeB[MAX_PROCESSOR_SENSORS]; // diode B value (offset)
	
	io_connect_t smc_connection;
}

- (TemperatureInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(TemperatureDataPtr)ptr;
- (void)getCurrent:(TemperatureDataPtr)ptr;
- (void)getLast:(TemperatureDataPtr)ptr;
- (int)getSize;

@end
