//
//	WirelessInfo.m - Wireless History Container Class
//


#import "AirportInfo.h"


@implementation AirportInfo


- (id)initWithCapacity:(unsigned)numItems
{
	int i, j;

	self = [super init];
	size = numItems;
	wirelessData = calloc(numItems, sizeof(WirelessData));
	if (wirelessData == NULL) {
		NSLog (@"Failed to allocate buffer for WirelessInfo");
		return (nil);
	}
	
	inptr = 0;
	outptr = -1;
	
	for (i = 0; i < size; i++)
	{
		wirelessData[i].wirelessAvailable = NO;
		wirelessData[i].wirelessHasPower = NO;
		wirelessData[i].wirelessLevel = 0.0;
		
		for (j = 0; j < 6; j++)
		{
			wirelessData[i].wirelessMacAddress[j] = 0;
		}
		
		wirelessData[i].wirelessName[0] = 0;
	}
	
	isAvailable = NO;
	@try {
		interface = [CWInterface interface];
		if (interface)
		{
			[interface retain];
			isAvailable = YES;
			attached = YES;
		}			
	}
	@catch (NSException *e) {
		NSLog(@"Failed to find CWInterface, exception = %@", e);
	}
	
	return (self);
}

- (void)dealloc
{
	[interface release];
	
	[super dealloc];
}

- (BOOL)isAvailable
{
	return (attached && isAvailable);
}

- (void)refresh
{
#if 1
	if (attached && isAvailable)
	{
		wirelessData[inptr].wirelessAvailable = YES;

		BOOL interfaceHasPower = [interface powerOn];
		NSInteger signal = [interface rssiValue];
		NSInteger noise = [interface noiseMeasurement];
		
		wirelessData[inptr].wirelessHasPower = interfaceHasPower;
		wirelessData[inptr].wirelessSignal = signal;
		wirelessData[inptr].wirelessNoise = noise;

		double signalToNoise = signal - noise;
		double level = signalToNoise / 50.0f;
		if (level > 1.0)
		{
			level = 1.0;
		}
		wirelessData[inptr].wirelessLevel = level;

		CWInterfaceMode interfaceMode = [interface interfaceMode];
		UInt16 clientMode = 0;
		switch (interfaceMode) {
			case kCWInterfaceModeStation:
				clientMode = 1;
				break;
			case kCWInterfaceModeIBSS:
				clientMode = 2;
				break;
			case kCWInterfaceModeHostAP:
				clientMode = 4;
				break;
			default:
				break;
		}
		wirelessData[inptr].wirelessClientMode = clientMode;

		if (interfaceHasPower)
		{
			int j;
			
			NSString *bssid = [interface bssid];
			if (bssid)
			{
				const char *bssidBytes = [bssid UTF8String];
				sscanf(bssidBytes, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
						&wirelessData[inptr].wirelessMacAddress[0],
						&wirelessData[inptr].wirelessMacAddress[1],
						&wirelessData[inptr].wirelessMacAddress[2],
						&wirelessData[inptr].wirelessMacAddress[3],
						&wirelessData[inptr].wirelessMacAddress[4],
						&wirelessData[inptr].wirelessMacAddress[5]);
			}
			else
			{
				for (j = 0; j < 6; j++)
				{
					wirelessData[inptr].wirelessMacAddress[j] = 0;
				}
			}

			NSString *ssid = [interface ssid];
			if (ssid)
			{
				const char *ssidBytes = [ssid UTF8String];
				for (j = 0; j < 34; j++)
				{
					wirelessData[inptr].wirelessName[j] = ssidBytes[j];
				}
				wirelessData[inptr].wirelessName[33] = 0;
			}
			else
			{
				wirelessData[inptr].wirelessName[0] = 0;
			}
		}
		else
		{
			int j;
			for (j = 0; j < 6; j++)
			{
				wirelessData[inptr].wirelessMacAddress[j] = 0;
			}
			
			wirelessData[inptr].wirelessName[0] = 0;
		}
	}
	else
#endif
	{
		wirelessData[inptr].wirelessAvailable = NO;
		wirelessData[inptr].wirelessLevel = 0.0;
	}

//	wirelessData[inptr].wirelessAvailable = YES;
//	wirelessData[inptr].wirelessLevel = 0.50;

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(WirelessDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = wirelessData[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(WirelessDataPtr)ptr
{
	*ptr = wirelessData[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(WirelessDataPtr)ptr
{
	*ptr = wirelessData[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}


@end
