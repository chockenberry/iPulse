//
//  pmateDevice.h
//  Proxi
//
//  Created by Casey Fleser on 1/8/06.
//  Copyright 2006 Griffin Technology. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/hid/IOHIDLib.h>

#define kPowerMateReportBufferSize		6
#define kRotationAvgSize				24

@interface pmateDevice : NSObject
{
	io_service_t				_serviceID;
	
	IOUSBDeviceInterface		**_usbDevice;
	IOHIDDeviceInterface122		**_hidDevice;
	UInt32						_locationID;
	UInt8						_buffer[kPowerMateReportBufferSize];
	
	NSMutableArray				*_savedStates;
	
	NSNumber					*_brightness;
	NSNumber					*_pulseRate;
	NSNumber					*_pulseState;
	
	unsigned int				_lastAction;
	UInt8						_lastButton;
	NSTimeInterval				_lastButtonTime;
	NSTimeInterval				_lastRotateTime;
	
	float						_rotationSpeed[kRotationAvgSize];
	int							_rotationIndex;
	BOOL						_rotationFull;
	
	float						_ballisticPosition;
	float						_lastBroadcastPosition;
	int							_absolutePosition;
	unsigned long				_activeEventID;
}

+ (UInt32)			locationID: (io_service_t) inServiceID;
+ (NSDictionary *)	deviceProperties: (io_service_t) inServiceID;

- (id)				initWithService: (io_service_t) inServiceID;
- (IOReturn)		initDeviceInterface;
- (IOReturn)		initHIDInterface;
- (IOReturn)		completeStartup;

- (void)			shutdownDevice;

- (void)			processReadData;

- (io_service_t)	serviceID;
- (unsigned long)	activeEventID;
- (unsigned int)	lastAction;

- (void)			saveAndRestoreStateAfter: (NSTimeInterval) inRestoreTime;

- (NSNumber *)		brightness;
- (void)			setBrightness: (NSNumber *) inBrightness;
- (NSNumber *)		pulseState;
- (void)			setPulseState: (NSNumber *) inPulseState;
- (NSNumber *)		pulseRate;
- (void)			setPulseRate: (NSNumber *) inPulseRate;

@end
