//
//	AirportInfo.m -  Wireless History Container Class
//


#import <Cocoa/Cocoa.h>

#import <CoreWLAN/CoreWLAN.h>


typedef struct WirelessData
{
	BOOL wirelessAvailable;
	BOOL wirelessHasPower;
	double wirelessLevel;
	UInt16 wirelessClientMode;
	UInt8	wirelessMacAddress[6]; /* MAC address of wireless access point. */
	SInt8	wirelessName[34];      /* Name of current (or wanted?) network. */
	SInt16 wirelessSignal;        /* Signal level */
	SInt16 wirelessNoise;         /* Noise level */
} WirelessData, *WirelessDataPtr;


@interface AirportInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	WirelessDataPtr wirelessData;
	BOOL attached;
	BOOL isAvailable;
	
	CWInterface *interface;
}

- (AirportInfo *)initWithCapacity:(unsigned)numItems;
- (BOOL)isAvailable;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(WirelessDataPtr)ptr;
- (void)getCurrent:(WirelessDataPtr)ptr;
- (void)getLast:(WirelessDataPtr)ptr;
- (int)getSize;

@end
