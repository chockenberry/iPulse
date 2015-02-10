//
//	PowerInfo.m - Battery Usage Container Class
//


// for battery info
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPM.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

// for power source information
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

//#import "mach/mach_host.h"
#import "PowerInfo.h"


@implementation PowerInfo

- (id)initWithCapacity:(unsigned)numItems
{
	int i;
	
	self = [super init];
	size = numItems;
	batteryData = calloc(numItems, sizeof(BatteryData));
	if (batteryData == NULL)
	{
		NSLog (@"Failed to allocate buffer for PowerInfo");
		return (nil);
	}
	
	inptr = 0;
	outptr = -1;
	
	for (i = 0; i < size; i++)
	{
		batteryData[i].batteryPresent = NO;
		batteryData[i].batteryCharging = NO;
		batteryData[i].batteryChargerConnected = NO;
		batteryData[i].batteryLevel = 0.0;
	}

	last = 0;
	interval = 0;

	isAvailable = NO;
	{
		kern_return_t kernResult; 
		CFArrayRef tmp = NULL;
		mach_port_t masterPort;
		
		kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
		if (KERN_SUCCESS != kernResult)
		{
			NSLog(@"IOMasterPort returned %d\n", kernResult);
		}
		IOPMCopyBatteryInfo(masterPort, &tmp);
		if (tmp)
		{
			isAvailable = YES;
			
			CFRelease(tmp);
		}

		mach_port_deallocate(mach_task_self(), masterPort);
	}
	
	return (self);
}

- (BOOL)isAvailable
{
#if 0
	kern_return_t kernResult; 
	CFArrayRef tmp = NULL;
	mach_port_t masterPort;
	BOOL result = NO;
	
	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"IOMasterPort returned %d\n", kernResult);
	}
	IOPMCopyBatteryInfo(masterPort, &tmp);
	if (tmp)
	{
		result = YES;
	}
	CFRelease(tmp);
	
	mach_port_deallocate(mach_task_self(), masterPort);

	return (result);
#else
	return (isAvailable);
#endif
}

- (void)refresh
{
	kern_return_t kernResult; 
	CFArrayRef tmp = NULL;
	mach_port_t masterPort;
    
	
	batteryData[inptr].batteryPresent = NO;
	batteryData[inptr].batteryCharging = NO;
	batteryData[inptr].batteryChargerConnected = NO;
	batteryData[inptr].batteryLevel = 0.0;
	batteryData[inptr].batteryAmperage = 0;
	batteryData[inptr].batteryVoltage = 0;
	batteryData[inptr].batteryMinutesRemaining = 0;
	batteryData[inptr].batteryMinutesIsValid = NO;

#if 1
	kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"IOMasterPort returned %d\n", kernResult);
	}
	IOPMCopyBatteryInfo(masterPort, &tmp);
	if (!tmp)
	{
		// no batteries
	} 
	else
	{
		// Batteries are present
		CFIndex count = CFArrayGetCount(tmp);
		CFIndex i;
		
		batteryData[inptr].batteryPresent = YES;

		//NSLog(@"Battery count = %d", count);
		for (i = 0; i < count; i++)
		{
			CFTypeRef dict = CFArrayGetValueAtIndex(tmp, i);
			CFTypeRef value;
			
			//CFShow(value);

			int current;
			int capacity;
			int amperage;
			int voltage;
			int flags;
//			float charge;
//			float wattage;
//			char batteryInstalled;
//			char batteryCharge;
//			char batteryChargerConnect;
			
			value = CFDictionaryGetValue(dict, CFSTR(kIOBatteryCurrentChargeKey));
			if (! CFNumberGetValue (value, kCFNumberSInt32Type, (void*) &current))
			{
				current = 0;
			}

			value = CFDictionaryGetValue(dict, CFSTR(kIOBatteryCapacityKey));
			if (! CFNumberGetValue (value, kCFNumberSInt32Type, (void*) &capacity))
			{
				capacity = 0;
			}

			value = CFDictionaryGetValue(dict, CFSTR(kIOBatteryAmperageKey));
			if (! CFNumberGetValue (value, kCFNumberSInt32Type, (void*) &amperage))
			{
				amperage = 0;
			}
			
			value = CFDictionaryGetValue(dict, CFSTR(kIOBatteryVoltageKey));
			if (! CFNumberGetValue (value, kCFNumberSInt32Type, (void*) &voltage))
			{
				voltage = 0;
			}
			

			value = CFDictionaryGetValue(dict, CFSTR(kIOBatteryFlagsKey));
			if (! CFNumberGetValue (value, kCFNumberSInt32Type, (void*) &flags))
			{
				flags = 0;
			}
			if (flags & kIOBatteryCharge)
			{
				batteryData[inptr].batteryCharging = YES;
			}
			if (flags & kIOBatteryChargerConnect)
			{
				batteryData[inptr].batteryChargerConnected = YES;
			}

			//charge = ((float) current / (float) capacity) * 100.0;
			//wattage = ((float) voltage / 1000.0) * ((float) amperage / 1000.0);
			//NSLog(@"%c %c %c charge = %.2f A = %d V = %d W = %.2f  d = %.2f", 
			//	batteryInstalled, batteryCharge, batteryChargerConnect,
			//	charge, amperage, voltage, wattage, lastWattage - wattage);
			//lastWattage = wattage;
			
			batteryData[inptr].batteryLevel = (float) current / (float) capacity;
			batteryData[inptr].batteryAmperage = amperage;
			batteryData[inptr].batteryVoltage = voltage;
			
			//NSLog(@"battery delta = %d, interval = %d", current - last, interval);
			if (current - last != 0)
			{
				interval = 0;
			}
			else
			{
				interval += 1;
			}
			last = current;
		}
		
		CFRelease(tmp);
	}
	mach_port_deallocate(mach_task_self(), masterPort);
#else
//	if (majorVersion == 10 && minorVersion >= 2)
	{
		/*
		Returns a blob of Power Source information in an opaque CFTypeRef. Clients should
		not actually look directly at data in the CFTypeRef - they should use the accessor
		functions IOPSCopyPowerSourcesList and IOPSGetPowerSourceDescription, instead.
		Returns NULL if errors were encountered.
		Return: Caller must CFRelease() the return value when done.
		*/
		CFTypeRef powerSourcesInfo = IOPSCopyPowerSourcesInfo();

		//NSLog(@"powerSourcesInfo = 0x%x", powerSourcesInfo);

		/*
		Arguments - Takes the CFTypeRef returned by IOPSCopyPowerSourcesInfo()
		Returns a CFArray of Power Source handles, each of type CFTypeRef.
		The caller shouldn't look directly at the CFTypeRefs, but should use
		IOPSGetPowerSourceDescription on each member of the CFArrayRef.
		Returns NULL if errors were encountered.
		Return: Caller must CFRelease() the returned CFArrayRef.
		*/
		CFArrayRef powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo);

		if (powerSources)
		{
			CFIndex count = CFArrayGetCount(powerSources);
			//NSLog(@"powerSources count = %d", count);

			BOOL chargerConnected = NO;
			
			int current = 0;
			int capacity = 0;
			int amperage = 0;
			int voltage = 0;
			int minutesRemaining = 0;
			BOOL minutesIsValid = NO;

			CFIndex index;
			for (index = 0; index < count; index++)
			{
				NSLog(@"powerSource %d", index);
			
				/*
				Arguments -
				1) The CFTypeRef returned by IOPSCopyPowerSourcesInfo
				2) One of the CFTypeRefs in the CFArray returned by IOPSCopyPowerSourcesList
				
				Returns a CFDictionary with specific information about the power source.
				See IOPSKeys.h for keys and the meaning of specific fields.
				Return: Caller should NOT CFRelease() the returned CFDictionaryRef
				*/
				CFDictionaryRef powerSource = IOPSGetPowerSourceDescription(powerSourcesInfo, CFArrayGetValueAtIndex(powerSources, index));
				if (powerSource)
				{							
					CFStringRef transportType = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTransportTypeKey));
					if (transportType && CFEqual(transportType, CFSTR(kIOPSInternalType)))
					{
						int temp;
												
						// battery power source is present
						//powerSourcePresent = YES;

						batteryData[inptr].batteryPresent = YES;

						NSLog(@"powerSource kIOPSInternalType present");
						
						CFBooleanRef isCharging = CFDictionaryGetValue(powerSource, CFSTR(kIOPSIsChargingKey));
						if (isCharging)
						{
							NSLog(@"powerSource check charging");

							if (CFBooleanGetValue(isCharging))
							{
								// power source is charging
								NSLog(@"powerSource charging");

								batteryData[inptr].batteryCharging = YES;

								CFNumberRef timeToFull = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTimeToFullChargeKey));
								CFNumberGetValue(timeToFull, kCFNumberIntType, &temp);
								if (temp != -1)
								{
									minutesRemaining += temp;
									minutesIsValid = YES;
								}
							}
							else
							{
								// power source is not charging
								NSLog(@"powerSource not charging");
								CFNumberRef timeToEmpty = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTimeToEmptyKey));
								CFNumberGetValue(timeToEmpty, kCFNumberIntType, &temp);
								if (temp != -1)
								{
									minutesRemaining += temp;
									minutesIsValid = YES;
								}
							}

							NSLog(@"powerSource minutesRemaining = %d", minutesRemaining);
						}

// kIOPSPowerSourceStateKey // Type CFString, value is kIOPSACPowerValue or kIOPSBatteryPowerValue

// kIOPSCurrentCapacityKey // Type CFNumber (signed integer), units are %
// kIOPSMaxCapacityKey // Type CFNumber (signed integer), units are %

// kIOPSCurrentKey // Type CFNumber (signed integer) - units are mA
// kIOPSVoltageKey // Type CFNumber (signed integer) - units are mV

						CFStringRef powerSourceState = CFDictionaryGetValue(powerSource, CFSTR(kIOPSPowerSourceStateKey));
						if (powerSourceState)
						{
							if (CFStringCompare(powerSourceState, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo)
							{
								NSLog(@"powerSource kIOPSACPowerValue present - charger connected");
								chargerConnected = YES;
							}
						}
						
						CFNumberRef powerSourceCurrentCapacity = CFDictionaryGetValue(powerSource, CFSTR(kIOPSCurrentCapacityKey));
						if (powerSourceCurrentCapacity)
						{
							CFNumberGetValue(powerSourceCurrentCapacity, kCFNumberIntType, &temp);
							current += temp;
							NSLog(@"powerSource current = %d", current);
						}
						
						CFNumberRef powerSourceMaxCapacity = CFDictionaryGetValue(powerSource, CFSTR(kIOPSMaxCapacityKey));
						if (powerSourceMaxCapacity)
						{
							CFNumberGetValue(powerSourceMaxCapacity, kCFNumberIntType, &temp);
							capacity += temp;
							NSLog(@"powerSource capacity = %d", capacity);
						}
						
						CFNumberRef powerSourceVoltage = CFDictionaryGetValue(powerSource, CFSTR(kIOPSVoltageKey));
						if (powerSourceVoltage)
						{
							CFNumberGetValue(powerSourceVoltage, kCFNumberIntType, &temp);
							voltage += temp;
							NSLog(@"powerSource voltage = %d", voltage);
						}

						CFNumberRef powerSourceCurrent = CFDictionaryGetValue(powerSource, CFSTR(kIOPSCurrentKey));
						if (powerSourceCurrent)
						{
							CFNumberGetValue(powerSourceCurrent, kCFNumberIntType, &temp);
							amperage += temp;
							NSLog(@"powerSource amperage = %d", amperage);
						}
					}
				}
			}
			CFRelease(powerSources);

			batteryData[inptr].batteryChargerConnected = chargerConnected;
			
			batteryData[inptr].batteryLevel = (float) current / (float) capacity;
			batteryData[inptr].batteryAmperage = amperage;
			batteryData[inptr].batteryVoltage = voltage;
		}
		
		CFRelease(powerSourcesInfo);
	}
#endif

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(BatteryDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = batteryData[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(BatteryDataPtr)ptr
{
	*ptr = batteryData[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(BatteryDataPtr)ptr
{
	*ptr = batteryData[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
