//
//	TemperatureInfo.m - Processor Usage History Container Class
//


#import <mach/mach.h>
#import <mach/mach_error.h>

#import "TemperatureInfo.h"

#import "Preferences.h"

// for sysctlbyname
#include <sys/types.h>
#include <sys/sysctl.h>

// for private SMC stuff
#include "smc.h"

//#define CPUID_SERVICE_NAME "cpuid"
#define IOHWSENSOR_SERVICE_NAME "IOHWSensor"
#define APPLECPUTHERMO_SERVICE_NAME "AppleCPUThermo"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned short fu16;
typedef int fs32;
typedef short fs16;

struct mpu_data
{
	u8	signature;			/* 0x00 - EEPROM sig. */
	u8	bytes_used;			/* 0x01 - Bytes used in eeprom (160 ?) */
	u8	size;				/* 0x02 - EEPROM size (256 ?) */
	u8	version;			/* 0x03 - EEPROM version */
	u32	data_revision;		/* 0x04 - Dataset revision */
	u8	processor_bin_code[3];	/* 0x08 - Processor BIN code */
	u8	bin_code_expansion;	/* 0x0b - ??? (padding ?) */
	u8	processor_num;		/* 0x0c - Number of CPUs on this MPU */
	u8	input_mul_bus_div;		/* 0x0d - Clock input multiplier/bus divider */
	u8	reserved1[2];		/* 0x0e - */
	u32	input_clk_freq_high;	/* 0x10 - Input clock frequency high */
	u8	cpu_nb_target_cycles;	/* 0x14 - ??? */
	u8	cpu_statlat;			/* 0x15 - ??? */
	u8	cpu_snooplat;		/* 0x16 - ??? */
	u8	cpu_snoopacc;		/* 0x17 - ??? */
	u8	nb_paamwin;		/* 0x18 - ??? */
	u8	nb_statlat;			/* 0x19 - ??? */
	u8	nb_snooplat;			/* 0x1a - ??? */
	u8	nb_snoopwin;		/* 0x1b - ??? */
	u8	api_bus_mode;		/* 0x1c - ??? */
	u8	reserved2[3];		/* 0x1d - */
	u32	input_clk_freq_low;		/* 0x20 - Input clock frequency low */
	u8	processor_card_slot;	/* 0x24 - Processor card slot number */
	u8	reserved3[2];		/* 0x25 - */
	u8	padjmax;       		/* 0x27 - Max power adjustment (Not in OF!) */
	u8	ttarget;			/* 0x28 - Target temperature */
	u8	tmax;				/* 0x29 - Max temperature */
	u8	pmaxh;			/* 0x2a - Max power */
	u8	tguardband;			/* 0x2b - Guardband temp ??? Hist. len in OSX */
	fs32	pid_gp;			/* 0x2c - PID proportional gain */
	fs32	pid_gr;			/* 0x30 - PID reset gain */
	fs32	pid_gd;			/* 0x34 - PID derivative gain */
	fu16	voph;				/* 0x38 - Vop High */
	fu16	vopl;				/* 0x3a - Vop Low */
	fs16	nactual_die;			/* 0x3c - nActual Die */
	fs16	nactual_heatsink;		/* 0x3e - nActual Heatsink */
	fs16	nactual_system;		/* 0x40 - nActual System */
	u16	calibration_flags;		/* 0x42 - Calibration flags */
	fu16	mdiode;			/* 0x44 - Diode M value (scaling factor) */
	fs16	bdiode;			/* 0x46 - Diode B value (offset) */
	fs32	theta_heat_sink;		/* 0x48 - Theta heat sink */
	u16	rminn_intake_fan;		/* 0x4c - Intake fan min RPM */
	u16	rmaxn_intake_fan;		/* 0x4e - Intake fan max RPM */
	u16	rminn_exhaust_fan;	/* 0x50 - Exhaust fan min RPM */
	u16	rmaxn_exhaust_fan;	/* 0x52 - Exhaust fan max RPM */
	u8	processor_part_num[8];	/* 0x54 - Processor part number */
	u32	processor_lot_num;		/* 0x5c - Processor lot number */
	u8	orig_card_sernum[0x10];	/* 0x60 - Card original serial number */
	u8	curr_card_sernum[0x10];	/* 0x70 - Card current serial number */
	u8	mlb_sernum[0x18];		/* 0x80 - MLB serial number */
	u32	checksum1;			/* 0x98 - */
	u32	checksum2;			/* 0x9c - */	
}; /* Total size = 0xa0 */

extern io_connect_t conn;

kern_return_t SMCSetup()
{
	return(SMCOpen(&conn));
}

kern_return_t SMCShutdown()
{
    return(SMCClose(conn));
}

@implementation TemperatureInfo

/*
<http://developer.apple.com/documentation/DeviceDrivers/Conceptual/AccessingHardware/AH_Finding_Devices/chapter_4_section_2.html>

When you’re completely finished with the port you received from IOMasterPort, you should release it, using  mach_port_deallocate. Although multiple calls to IOMasterPort will not result in leaking ports (each call to IOMasterPort adds another send right to the port), it’s good programming practice to deallocate the port when you’re finished with it.

Starting with Mac OS X version 10.2, you can bypass this procedure entirely and use instead the convenience constant kIOMasterPortDefault (defined in IOKitLib.h in the I/O Kit framework). This means that when you call a function that requires the I/O Kit master port, such as IOServiceGetMatchingServices, you can pass in kIOMasterPortDefault instead of the mach_port_t object you get from IOMasterPort, as in this example:

	IOServiceGetMatchingServices(kIOMasterPortDefault, myMatchingDictionary, &myIterator);
*/

BOOL hasServiceNamed(char *serviceName)
{
	BOOL result = NO;
	
	kern_return_t kernResult; 
	mach_port_t masterPort;
	CFMutableDictionaryRef classesToMatch;

	//NSLog(@"Checking for service named %s", serviceName);

	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"TemperatureInfo: hasServiceNamed: IOMasterPort returned %d\n", kernResult);
	}

	// find hardware sensors
	classesToMatch = IOServiceMatching(serviceName);
	
	if (classesToMatch == NULL)
	{
		NSLog(@"TemperatureInfo: hasServiceNamed: IOServiceMatching returned a NULL dictionary.\n");
	}
	else
	{
		io_iterator_t matchingServices;

		kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
		if (kernResult != KERN_SUCCESS)
		{
			NSLog(@"TemperatureInfo: hasServiceNamed: IOServiceGetMatchingServices returned %d\n", kernResult);
		}
	
		io_object_t service;
		while ((service = IOIteratorNext(matchingServices)))
		{
			//NSLog(@"Found service named %s", serviceName);

			CFTypeRef type;
			type = IORegistryEntryCreateCFProperty(service, CFSTR("type"), kCFAllocatorDefault, 0);
			if (type)
			{
				//NSLog(@"Found service = 0x%x (%@)", service, type);
				
				if ((CFStringCompare(type, CFSTR("temperature"), 0) == kCFCompareEqualTo) ||
					(CFStringCompare(type, CFSTR("temp"), 0) == kCFCompareEqualTo))
				{
					result = YES;
				}
				CFRelease(type);
			}
			
			if (result == YES)
			{
				break;
			}
		}

		(void) IOObjectRelease(service);

		(void) IOObjectRelease(matchingServices);
	}
	
	mach_port_deallocate(mach_task_self(), masterPort);
		 
	return (result);
}

BOOL getCalibrationCpuid(unsigned short *diodeM, short *diodeB, int *diodeCount)
{
	BOOL result = NO;

	kern_return_t kernResult; 
	mach_port_t masterPort;
	CFMutableDictionaryRef classesToMatch;

	//NSLog(@"Checking for cpuid...");
	
	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"TemperatureInfo: getCalibrationCpuid: IOMasterPort returned %d\n", kernResult);
	}


	// try getting the calibration information for the PowerMac G5 and the Xserve G5
	classesToMatch = IOServiceNameMatching("cpuid");
	if (classesToMatch == NULL)
	{
		NSLog(@"TemperatureInfo: getCalibrationCpuid: IOServiceMatching returned a NULL dictionary.\n");
	}
	else
	{
		io_iterator_t matchingServices;

		kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
		if (kernResult != KERN_SUCCESS)
		{
			NSLog(@"TemperatureInfo: getCalibrationCpuid: IOServiceGetMatchingServices returned %d\n", kernResult);
		}
	
		int count = 0;
		io_object_t service;
		while ((service = IOIteratorNext(matchingServices)))
		{
			//NSLog(@"Found service = 0x%x", service);
			
			struct mpu_data mpuData;
			
			CFTypeRef cpuid;
			cpuid = IORegistryEntryCreateCFProperty(service, CFSTR("cpuid"), kCFAllocatorDefault, 0);
			if (cpuid)
			{
				//CFShow(cpuid);
				CFDataGetBytes(cpuid, CFRangeMake(0, sizeof(struct mpu_data)), (UInt8 *)&mpuData);
				
				if (count < MAX_PROCESSOR_SENSORS)
				{
					diodeM[count] = mpuData.mdiode;
					diodeB[count] = mpuData.bdiode;

					//NSLog(@"TemperatureInfo: getCalibrationCpuid: count = %d, mdiode = %d, bdiode = %d\n", count, mpuData.mdiode, mpuData.bdiode);
					
					count++;
					*diodeCount = count;
				}
				
				result = YES;

				CFRelease(cpuid);
			}
		}
			
		(void) IOObjectRelease(service);

		(void) IOObjectRelease(matchingServices);
	}

	if (! result)
	{
		// try getting the calibration information for the iMac G5

		classesToMatch = IOServiceNameMatching("SMU_Neo2_PlatformPlugin");
		
		if (classesToMatch == NULL)
		{
			NSLog(@"TemperatureInfo: getCalibrationCpuid: IOServiceMatching returned a NULL dictionary.\n");
		}
		else
		{
			io_iterator_t matchingServices;

			kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
			if (kernResult != KERN_SUCCESS)
			{
				NSLog(@"TemperatureInfo: getCalibrationCpuid: IOServiceGetMatchingServices returned %d\n", kernResult);
			}
		
			//int count = 0;
			io_object_t service;
			while ((service = IOIteratorNext(matchingServices)))
			{
				//NSLog(@"TemperatureInfo: getCalibrationCpuid: SMU_Neo2_PlatformPlugin, found service = 0x%x", service);
				
				// get IOHWSensors array with dictionaries containing sensor information
				CFTypeRef hardwareSensorsArray = IORegistryEntryCreateCFProperty(service, CFSTR("IOHWSensors"), kCFAllocatorDefault, 0);
				if (hardwareSensorsArray)
				{
					CFIndex count = CFArrayGetCount(hardwareSensorsArray);
					//NSLog(@"TemperatureInfo: getCalibrationCpuid: count = %d\n", count);
					
					// check each dictionary in the array
					CFIndex index;
					for (index = 0; index < count; index++)
					{
						CFTypeRef sensorDictionary = CFArrayGetValueAtIndex(hardwareSensorsArray, index);
						if (sensorDictionary)
						{
							short value;
							
							// check for the B diode
							CFDataRef bDiodeRef = CFDictionaryGetValue(sensorDictionary, CFSTR("b-diode"));
							if (bDiodeRef)
							{
								CFDataGetBytes(bDiodeRef, CFRangeMake(0, sizeof(short)), (UInt8 *)&value);
								diodeB[0] = value;
								//NSLog(@"TemperatureInfo: getCalibrationCpuid: index = %d, bdiode = %hd <%hx>\n", index, value, value);
								
								// check for the M diode
								CFDataRef mDiodeRef = CFDictionaryGetValue(sensorDictionary, CFSTR("m-diode"));
								if (mDiodeRef)
								{
									CFDataGetBytes(mDiodeRef, CFRangeMake(0, sizeof(short)), (UInt8 *)&value);
									diodeM[0] = value;
									//NSLog(@"TemperatureInfo: getCalibrationCpuid: index = %d, mdiode = %hd <%hx>\n", index, value, value);

									result = YES;
								}
							}
						}
					}

					CFRelease(hardwareSensorsArray);
				}
			}
				
			(void) IOObjectRelease(service);

			(void) IOObjectRelease(matchingServices);
		}
	}	
	mach_port_deallocate(mach_task_self(), masterPort);
	
	return (result);
}

// As of 10.7.4, the TC0H key logs an error to the console: kernel: SMC::smcReadKeyAction ERROR TC0H kSMCBadArgumentError(0x89) fKeyHashTable=0x0xffffff8011e57000
#define INCLUDE_TC0H 1

- (TemperatureInfo *)initWithCapacity:(unsigned)numItems
{
	int i, j;
	
	self = [super init];
	size = numItems;
	temperatureData = calloc(numItems, sizeof(TemperatureData));
	if (temperatureData == NULL)
	{
		NSLog (@"Failed to allocate buffer for TemperatureInfo");
		return (nil);
	}
	
	inptr = 0;
	outptr = -1;
	
	for (i = 0; i < size; i++)
	{
		temperatureData[i].temperatureCount = 0;
			
		for (j = 0; j < MAX_PROCESSOR_SENSORS; j++)
		{
			temperatureData[i].temperatureLevel[j] = 0.0;
		}
	}

	if (hasServiceNamed(APPLECPUTHERMO_SERVICE_NAME)) {
		sensorType = AppleCPUThermoSensorType;
	}
	else if (hasServiceNamed(IOHWSENSOR_SERVICE_NAME)) {
		// get calibration information if available
		BOOL hasCpuid = getCalibrationCpuid(diodeM, diodeB, &diodeCount);
		
		if (hasCpuid) {
			sensorType = CpuidSensorType;
		}
		else {
			// no calibration information, so look on motherboard
			sensorType = IOHWSensorSensorType;
		}
	}
	else {
		// get temperature from AppleSMC kernel extension if supported on this computer model
		
		kern_return_t result = SMCSetup();
		if (result == kIOReturnSuccess) {
			sensorType = SMCSensorType;

			// check if we know about one of the keys
			SMCVal_t val;
			kern_return_t result;

			BOOL keyFound = NO;
			strncpy(smcSensorKey, "TC0H", 4);
			result = SMCReadKey(smcSensorKey, &val);
			if (result == kIOReturnSuccess && val.dataSize > 0) {
				//NSLog(@"%s found key 1 = %s", __PRETTY_FUNCTION__, smcSensorKey);
				keyFound = YES;
			}
			else {
				strncpy(smcSensorKey, "TC0D", 4);
				result = SMCReadKey(smcSensorKey, &val);
				if (result == kIOReturnSuccess && val.dataSize > 0) {
					//NSLog(@"%s found key 2 = %s", __PRETTY_FUNCTION__, smcSensorKey);
					keyFound = YES;
				}
				else {
					strncpy(smcSensorKey, "TC0P", 4);
					result = SMCReadKey(smcSensorKey, &val);
					if (result == kIOReturnSuccess && val.dataSize > 0) {
						keyFound = YES;
						//NSLog(@"%s found key 3 = %s", __PRETTY_FUNCTION__, smcSensorKey);
					}
				}
			}
			if (! keyFound) {
#if DEBUG
				NSLog(@"%s unknown SMC key, available keys are: ", __PRETTY_FUNCTION__);
				SMCPrintAll();
#endif
				sensorType = NoSensorType;
			}
		}
		else {
			if (result != kIOReturnNoDevice) {
				NSLog(@"%s SMCSetup returned 0x%08x", __PRETTY_FUNCTION__, result);
			}

			sensorType = NoSensorType;
		}
	}

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	chudWorkaround = [defaults boolForKey:APPLICATION_CHUD_WORKAROUND_KEY];
	
	NSArray *checkTemperatureArray;
	NSEnumerator *checkTemperatureEnumerator;
	NSString *checkTemperatureString;
	
	checkTemperatureArray  =  [defaults arrayForKey:APPLICATION_CHECK_MOTHERBOARD_TEMPERATURE_KEY];
	checkTemperatureEnumerator = [checkTemperatureArray objectEnumerator];
	while (checkTemperatureString = [checkTemperatureEnumerator nextObject])
	{
		//NSLog(@"TemperatureInfo: initWithCapacity: motherboard = %@", checkTemperatureString);
	}

	checkTemperatureArray =  [defaults arrayForKey:APPLICATION_CHECK_DIODE_TEMPERATURE_KEY];
	checkTemperatureEnumerator = [checkTemperatureArray objectEnumerator];
	while (checkTemperatureString = [checkTemperatureEnumerator nextObject])
	{
		//NSLog(@"TemperatureInfo: initWithCapacity: diode = %@", checkTemperatureString);
	}

	return (self);
}

- (void)dealloc
{
	if (sensorType == SMCSensorType)
	{
		SMCShutdown();
	}
	
	// cleanup cached information
	
	[super dealloc];
}

float getTemperatureIOHWSensor()
{
	float result = 0.0;
	
	kern_return_t kernResult; 
	mach_port_t masterPort;
	CFMutableDictionaryRef classesToMatch;

	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: IOMasterPort returned %d\n", kernResult);
	}

	// find hardware sensors
	classesToMatch = IOServiceMatching(IOHWSENSOR_SERVICE_NAME);
	
	if (classesToMatch == NULL)
	{
		NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: IOServiceMatching returned a NULL dictionary.\n");
	}
	else
	{
		io_iterator_t matchingServices;

		kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
		if (kernResult != KERN_SUCCESS)
		{
			NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: IOServiceGetMatchingServices returned %d\n", kernResult);
		}
	
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSArray *checkTemperatureArray =  [defaults arrayForKey:APPLICATION_CHECK_MOTHERBOARD_TEMPERATURE_KEY];

		int count = 0;
		io_object_t service;
		while ((service = IOIteratorNext(matchingServices)))
		{
			CFTypeRef type;
			type = IORegistryEntryCreateCFProperty(service, CFSTR("type"), kCFAllocatorDefault, 0);
			if (type)
			{
				//NSLog(@"Found service = 0x%x (%@)", service, type);
				
				if ((CFStringCompare(type, CFSTR("temperature"), 0) == kCFCompareEqualTo) ||
					(CFStringCompare(type, CFSTR("temp"), 0) == kCFCompareEqualTo))
				{
					CFTypeRef location;
					location = IORegistryEntryCreateCFProperty(service, CFSTR("location"), kCFAllocatorDefault, 0);
					if (location)
					{
						CFTypeRef currentValue;
						currentValue = IORegistryEntryCreateCFProperty(service, CFSTR("current-value"), kCFAllocatorDefault, 0);
						if (currentValue)
						{
							//CFShow(currentValue);
							int value;
							if (CFNumberGetValue(currentValue, kCFNumberSInt32Type, &value))
							{
								NSEnumerator *checkTemperatureEnumerator = [checkTemperatureArray objectEnumerator];
								NSString *checkTemperatureString;
								while (checkTemperatureString = [checkTemperatureEnumerator nextObject])
								{
									//NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: check: %@", checkTemperatureString);
									if ([checkTemperatureString isEqualToString:(NSString *)location])
									{
										count++;
										float reading = (float)value/65535.0;
										result = result + reading;
										//NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: location: %@ value = %d, reading = %.2f, count = %d", location, value, reading, count);
									}
								}
							}
							CFRelease(currentValue);
						}

						CFRelease(location);
					}
				}
				CFRelease(type);
			}
		}
			
		//NSLog(@"Done looking for services.");
		
		(void) IOObjectRelease(service);

		(void) IOObjectRelease(matchingServices);

		//NSLog(@"TemperatureInfo: getTemperatureIOHWSensor: count = %d, sum = %f, result = %f", count, result, result/(float)count);
		result = result / (float)count;
	}
	
	mach_port_deallocate(mach_task_self(), masterPort);

	return (result);
}

float getTemperatureAppleCPUThermo()
{
	float result = 0.0;
	
	kern_return_t kernResult; 
	mach_port_t masterPort;
	CFMutableDictionaryRef classesToMatch;

	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"TemperatureInfo: getTemperatureAppleCPUThermo: IOMasterPort returned %d\n", kernResult);
	}

	// find hardware sensors
	classesToMatch = IOServiceMatching(APPLECPUTHERMO_SERVICE_NAME);
	
	if (classesToMatch == NULL)
	{
		NSLog(@"TemperatureInfo: getTemperatureAppleCPUThermo: IOServiceMatching returned a NULL dictionary.\n");
	}
	else
	{
		io_iterator_t matchingServices;

		kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
		if (kernResult != KERN_SUCCESS)
		{
			NSLog(@"TemperatureInfo: getTemperatureAppleCPUThermo: IOServiceGetMatchingServices returned %d\n", kernResult);
		}
	
		int count = 0;

		io_object_t service;
		while ((service = IOIteratorNext(matchingServices)))
		{
			//NSLog(@"Found service = 0x%x", service);
			
			CFTypeRef temperature;
			temperature = IORegistryEntryCreateCFProperty(service, CFSTR("temperature"), kCFAllocatorDefault, 0);
			if (temperature)
			{
				//CFShow(temperature);
				
				int value;
				if (CFNumberGetValue(temperature, kCFNumberSInt32Type, &value))
				{
					count++;
					
					//NSLog(@"value = %d, temp = %f", value, (float)value/256.0);
					//NSLog(@"TemperatureInfo: getTemperatureAppleCPUThermo: value = %d, temp = %.2f", value, (float)value/256.0);
					result = result + (float)value/256.0;
				}
								
				CFRelease(temperature);
			}
		}
			
		//NSLog(@"Done looking for services.");
		
		(void) IOObjectRelease(service);
	
		(void) IOObjectRelease(matchingServices);

		//NSLog(@"TemperatureInfo: getTemperatureAppleCPUThermo: count = %d, sum = %f, result = %f", count, result, result/(float)count);
		result = result / (float)count;
	}
	
	mach_port_deallocate(mach_task_self(), masterPort);

	return (result);
}

void getTemperatureCpuid(unsigned short *diodeM, short *diodeB, float *temperatures, int *temperatureCount)
{
	kern_return_t kernResult; 
	mach_port_t masterPort;
	CFMutableDictionaryRef classesToMatch;

	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"TemperatureInfo: getTemperatureCpuid: IOMasterPort returned %d\n", kernResult);
	}

	// find hardware sensors
	classesToMatch = IOServiceMatching(IOHWSENSOR_SERVICE_NAME);
	
	if (classesToMatch == NULL)
	{
		NSLog(@"TemperatureInfo: getTemperatureCpuid: IOServiceMatching returned a NULL dictionary.\n");
	}
	else
	{
		io_iterator_t matchingServices;

		kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
		if (kernResult != KERN_SUCCESS)
		{
			NSLog(@"TemperatureInfo: getTemperatureCpuid: IOServiceGetMatchingServices returned %d\n", kernResult);
		}
	
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSArray *checkTemperatureArray =  [defaults arrayForKey:APPLICATION_CHECK_DIODE_TEMPERATURE_KEY];

		int count = 0;
		io_object_t service;
		while ((service = IOIteratorNext(matchingServices)))
		{
			CFTypeRef type;
			type = IORegistryEntryCreateCFProperty(service, CFSTR("type"), kCFAllocatorDefault, 0);
			if (type)
			{
				//NSLog(@"Found service = 0x%x (%@)", service, type);
				
				// check for ADC sensors: (PowerMac & Xserve G5) or (iMac G5)
				if ((CFStringCompare(type, CFSTR("adc"), 0) == kCFCompareEqualTo) ||
					(CFStringCompare(type, CFSTR("temp"), 0) == kCFCompareEqualTo))
				{
					CFTypeRef location;
					location = IORegistryEntryCreateCFProperty(service, CFSTR("location"), kCFAllocatorDefault, 0);
					if (location)
					{
						CFTypeRef currentValue;
						currentValue = IORegistryEntryCreateCFProperty(service, CFSTR("current-value"), kCFAllocatorDefault, 0);
						if (currentValue)
						{
							//CFShow(currentValue);
							int value;
							if (CFNumberGetValue(currentValue, kCFNumberSInt32Type, &value))
							{
								NSEnumerator *checkTemperatureEnumerator = [checkTemperatureArray objectEnumerator];
								NSString *checkTemperatureString;
								while (checkTemperatureString = [checkTemperatureEnumerator nextObject])
								{
									if ([checkTemperatureString isEqualToString:(NSString *)location])
									{
										//NSLog(@"TemperatureInfo: getTemperatureCpuid: value = %d, diodeM = %d, diodeB = %d", value, diodeM[count], diodeB[count]);
										int temp = (value * (int)diodeM[count] + ((int)diodeB[count] << 12)) >> 2;

										float reading = (float)temp/65535.0;
										
										if (count < MAX_PROCESSOR_SENSORS)
										{
											temperatures[count] = reading;
											*temperatureCount = count + 1;
										}
										
										//NSLog(@"TemperatureInfo: getTemperatureCpuid: location: %@ temp = %d, reading = %.2f, count = %d", location, temp, reading, count);
										
										count++;
									}
								}
							}
							CFRelease(currentValue);
						}

						CFRelease(location);
					}
				}
				
				CFRelease(type);
			}
		}
			
		//NSLog(@"Done looking for services.");
		
		(void) IOObjectRelease(service);

		(void) IOObjectRelease(matchingServices);
	}
	
	mach_port_deallocate(mach_task_self(), masterPort);
}


- (void)refresh
{
	temperatureData[inptr].temperatureCount = 0;

	//NSLog(@"Sensor type = %d", sensorType);
	
	switch (sensorType)
	{
	default:
	case NoSensorType:
		break;
	case IOHWSensorSensorType:
		{
			temperatureData[inptr].temperatureLevel[0] = getTemperatureIOHWSensor();
			temperatureData[inptr].temperatureCount = 1;
		}
		break;
	case AppleCPUThermoSensorType:
		{
			temperatureData[inptr].temperatureLevel[0] = getTemperatureAppleCPUThermo();
			temperatureData[inptr].temperatureCount = 1;
		}
		break;
	case CpuidSensorType:
		{
			float temperatures[MAX_PROCESSOR_SENSORS];
			int temperatureCount;
			getTemperatureCpuid(diodeM, diodeB, temperatures, &temperatureCount);
			temperatureData[inptr].temperatureLevel[0] = temperatures[0];
			temperatureData[inptr].temperatureLevel[1] = temperatures[1];
			temperatureData[inptr].temperatureCount = temperatureCount;
		}
		break;
	case SMCSensorType:
		{
			SMCVal_t val;
			kern_return_t result;
			
			//NSLog(@"TemperatureInfo: SMC keys are: ");
			//SMCPrintAll();

			temperatureData[inptr].temperatureLevel[0] = 0;
			temperatureData[inptr].temperatureLevel[1] = 0;
			temperatureData[inptr].temperatureCount = 0;

			result = SMCReadKey(smcSensorKey, &val);
//#warning "Disable logging in release build"
//			NSLog(@"%s SMCReadKey %s result = %d (0x%08x), val.dataSize = %ld", __PRETTY_FUNCTION__, smcSensorKey, result, result, (unsigned long)val.dataSize);
			if (result == kIOReturnSuccess && val.dataSize > 0) {
				unsigned int val0 = (unsigned char)val.bytes[0];
				unsigned int val1 = (unsigned char)val.bytes[1];

				unsigned int valInt = ((val0 << 8) + val1);
				//NSLog(@"valInt = %d (0x%08x), valInt >> 4 = %d (0x%08x)", valInt, valInt, valInt >> 4, valInt >> 4);

				float temp = (float)(valInt >> 4) / 16.0;
//#warning "Disable logging in release build"
//				NSLog(@"%s val0 = %x, val1 = %x, temp = %f", __PRETTY_FUNCTION__, val0, val1, temp);

				temperatureData[inptr].temperatureLevel[0] = temp;
				temperatureData[inptr].temperatureCount = 1;
			}
		}
		break;
	}

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(TemperatureDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = temperatureData[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(TemperatureDataPtr)ptr
{
	*ptr = temperatureData[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(TemperatureDataPtr)ptr
{
	*ptr = temperatureData[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
