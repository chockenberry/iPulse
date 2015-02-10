//
//  pmateDevice.m
//  Proxi
//
//  Created by Casey Fleser on 1/8/06.
//  Copyright 2006 Griffin Technology. All rights reserved.
//

#import "pmateDevice.h"
#import "pmateEvent.h"
#import "pmateManager.h"
#import <Carbon/Carbon.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <unistd.h>

#define kPowerMateCmd_SetBrightness		0x0001
#define kPowerMateCmd_SetSleepPulse		0x0002
#define kPowerMateCmd_SetAlwaysPulse	0x0003
#define kPowerMateCmd_SetPulseRate		0x0004

#define kPowerMateRevolutionUnits		96

void PowerMateCallbackFunction(
	void *	 		inTarget,
	IOReturn 		inResult,
	void * 			inRefcon,
	void * 			inSender,
	UInt32		 	inBufferSize)
{
	if (inResult == kIOReturnSuccess) {
		pmateDevice		*device = (pmateDevice *)inTarget;

		[device processReadData];
	}
}

@implementation pmateDevice

+ (UInt32) locationID: (io_service_t) inServiceID
{
	NSDictionary			*properties;
	NSNumber				*location;
	
	properties = [pmateDevice deviceProperties: inServiceID];
	location = [properties valueForKey: (NSString *)CFSTR(kIOHIDLocationIDKey)];

	return location != nil ? [location unsignedLongValue] : 0;
}

+ (NSDictionary *) deviceProperties: (io_service_t) inServiceID
{
	NSMutableDictionary		*properties = nil;
	IOReturn				result;

	result = IORegistryEntryCreateCFProperties(inServiceID, (CFMutableDictionaryRef *)&properties, kCFAllocatorDefault, kNilOptions);
		
	return [properties autorelease];
}

- (id) initWithService: (io_service_t) inServiceID
{
	if ((self = [super init]) != nil) {
		_absolutePosition = kPowerMateRevolutionUnits / 2;
		_serviceID = inServiceID;
		_locationID = [pmateDevice locationID: _serviceID];

		[self initHIDInterface];
		[self initDeviceInterface];

		if (_usbDevice == nil || _hidDevice == nil) {
			if (_usbDevice != nil) {
				(*_usbDevice)->Release(_usbDevice);
				_usbDevice = nil;
			}
			if (_hidDevice != nil) {
				(*_hidDevice)->Release(_hidDevice);
				_hidDevice = nil;
			}
			IOObjectRelease(_serviceID);
			self = nil;
		}
		else {
			[self completeStartup];

			_savedStates = [[NSMutableArray alloc] init];
			_brightness = [[NSNumber numberWithFloat: 0.5] retain];
			_pulseRate = [[NSNumber numberWithFloat: 0.5] retain];
			_pulseState = [[NSNumber numberWithBool: NO] retain];
		}
	}
	
	return self;
}

- (IOReturn) initDeviceInterface
{
	CFMutableDictionaryRef  matchingDict;
	IOReturn				result;
	
	if ((matchingDict = IOServiceMatching(kIOUSBDeviceClassName)) == nil) {
		NSLog(@"IOServiceMatching failed File %s Line %d", __FILE__, __LINE__);
		result = kIOReturnError;
	}
	else {
		NSMutableDictionary		*dict = (NSMutableDictionary *)matchingDict;
		io_iterator_t			deviceIterator;
		io_object_t				usbDevice;
		
		[dict setValue: [NSNumber numberWithLong: kPowerMateProduct] forKey: [NSString stringWithCString: kUSBProductID]];
		[dict setValue: [NSNumber numberWithLong: kPowerMateVendor] forKey: [NSString stringWithCString: kUSBVendorID]];

		sleep(1);
		// TODO: Preceding sleep offered as a workaround to radar://5474691
		
		if ((result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &deviceIterator)) == kIOReturnSuccess) {
			IOCFPlugInInterface			**iodev = nil;
			SInt32						score;

			while ((usbDevice = IOIteratorNext(deviceIterator)) != nil && _usbDevice == nil) {
				result = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID,
																kIOCFPlugInInterfaceID, &iodev, &score);
				if (result == kIOReturnSuccess) {
					IOUSBDeviceInterface		**usbDeviceInterface;

					if ((result = (*iodev)->QueryInterface(iodev, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID) &usbDeviceInterface)) == kIOReturnSuccess) {
						UInt32			deviceLocationID;
						
						if ((result = (*usbDeviceInterface)->GetLocationID(usbDeviceInterface, &deviceLocationID)) == kIOReturnSuccess) {
							if (deviceLocationID == _locationID)
								_usbDevice = usbDeviceInterface;
						}
					}
					
					
					if (_usbDevice == nil)
						IOObjectRelease(usbDevice);

					if (iodev != nil)
						(*iodev)->Release(iodev);
				}
			}
			
			IOObjectRelease(deviceIterator);
		}
	}
	
	if (result != kIOReturnSuccess)
		NSLog(@"initDeviceInterface failed: %08x", result);

	return result;
}

- (IOReturn) initHIDInterface
{
    IOCFPlugInInterface		**iodev = nil;
	IOReturn				result;
    SInt32					score;
	
	result = IOCreatePlugInInterfaceForService(_serviceID,
		kIOHIDDeviceUserClientTypeID,
		kIOCFPlugInInterfaceID, &iodev, &score);
	
	if (result == kIOReturnSuccess) {
		IOHIDDeviceInterface122		**hidDeviceInterface;

		if ((result = (*iodev)->QueryInterface(iodev, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID122), (LPVOID) &hidDeviceInterface)) == kIOReturnSuccess)
			_hidDevice = hidDeviceInterface;

		if (iodev != nil)
			(*iodev)->Release(iodev);
	}
	
	if (result != kIOReturnSuccess)
		NSLog(@"initHIDInterface failed: %08x", result);

	return result;
}

- (IOReturn) completeStartup
{
	CFRunLoopSourceRef		eventSource;
	IOReturn				result = kIOReturnError;	// assume failure (pessimist!)
 	
	if ((result = (*_hidDevice)->open(_hidDevice, 0)) == kIOReturnSuccess) {
		if ((result = (*_hidDevice)->createAsyncEventSource(_hidDevice, &eventSource)) != kIOReturnSuccess) {
			NSLog(@"completeStartup - createAsyncEventSource failed: %08x", result);
		}
		else {
			CFRunLoopAddSource([[[pmateManager defaultManager] runLoop] getCFRunLoop], eventSource, kCFRunLoopDefaultMode);
			result = (*_hidDevice)->setInterruptReportHandlerCallback(_hidDevice, _buffer, kPowerMateReportBufferSize, PowerMateCallbackFunction, self, nil);
		}
	}
	
	if (result != kIOReturnSuccess)
		NSLog(@"completeStartup failed: %08x", result);
		
	return result;
}

- (void) dealloc
{
	[self shutdownDevice];
	IOObjectRelease(_serviceID);
	
	[super dealloc];
}

- (void) shutdownDevice
{
	if (_hidDevice != nil) {
		(*_hidDevice)->close(_hidDevice);
		(*_hidDevice)->Release(_hidDevice);
		_hidDevice = nil;
	}
	if (_usbDevice != nil) {
		(*_usbDevice)->Release(_usbDevice);
		_usbDevice = nil;
	}
}

- (float) setTimeSinceLast: (NSTimeInterval) inTimeSinceLast
	rotationAmount: (int) inRotationAmount
{
	float		average;
	int			i;

	inRotationAmount = abs(inRotationAmount);

	if (inTimeSinceLast > 0.2) {
		_rotationFull = NO;
		average = 0.15;
		
		for (i=0; i<kRotationAvgSize; i++)
			_rotationSpeed[i] = 0.15;
			_rotationIndex = 0;
	}
	else {
		int		validCnt;
		float	rps = (1.0 / 96.0) / (inTimeSinceLast / inRotationAmount);
		
		if (rps < 4) {
			_rotationSpeed[_rotationIndex] = rps;
			_rotationIndex++;
			if (_rotationIndex >= kRotationAvgSize) {
				_rotationIndex = 0;
				_rotationFull = YES;
			}
		}
		
		validCnt = _rotationFull ? kRotationAvgSize : (_rotationIndex + 1);
		average = 0.0;
		for (i=0; i<validCnt; i++) {
			average += _rotationSpeed[i];
		}
		
		average /= validCnt;
	}
	
	return average;
}

- (void) processReadData
{
	NSTimeInterval	eventTime = [NSDate timeIntervalSinceReferenceDate];
	SInt8			newButton = _buffer[0];
	SInt8			newRotate = _buffer[1];
	UInt32			modifiers = GetCurrentKeyModifiers();
	unsigned int	translatedModifiers = 0;
	unsigned int	deviceIndex = [[[pmateManager defaultManager] devices] indexOfObject: self];
	pmateEvent		*devEvent;
	
	if (modifiers & cmdKey)
		translatedModifiers |= ePowerMateModifier_Command;
	if (modifiers & shiftKey)
		translatedModifiers |= ePowerMateModifier_Shift;
	if (modifiers & optionKey)
		translatedModifiers |= ePowerMateModifier_Option;
	if (modifiers & controlKey)
		translatedModifiers |= ePowerMateModifier_Control;

	if (_lastButton != newButton) {
		devEvent = [pmateEvent createForDeviceIndex: deviceIndex event: newButton ? ePowerMateAction_ButtonPress : ePowerMateAction_ButtonRelease
			modifiers: translatedModifiers absValue: newButton relValue: newButton - _lastButton];
		
		_activeEventID = [devEvent eventID];
		[[pmateManager defaultManager] handleEvent: devEvent]; 
		_lastAction = [devEvent eventType];
		_lastButton = newButton;
		_lastButtonTime = eventTime;
	}
	
	if (newRotate && eventTime - _lastButtonTime > 0.25) {
		float				delta, average, multiplier;

		average = multiplier = [self setTimeSinceLast: eventTime - _lastRotateTime rotationAmount: newRotate];

		// 3 stage scaling:
		// 0.0 - 0.4 RPS = 0.0 - 0.3 multiplier
		// 0.4 - 1.0 RPS = 0.3 - 1.0 multiplier
		// 1.0 - 2.0 RPS = 1.0 - 5.0 multiplier ...
		
		if (multiplier > 1.0)
			multiplier = ((multiplier - 1.0) * 4.0) + 1.0;
		else if (multiplier > 0.4)
			multiplier = ((multiplier - 0.4) / (0.6 / 0.7)) + 0.3;
		else 
			multiplier *= 0.75;

		_absolutePosition += newRotate;
		if (_absolutePosition < 0)
			_absolutePosition = 0;
		else if (_absolutePosition > kPowerMateRevolutionUnits)
			_absolutePosition = kPowerMateRevolutionUnits;

		_ballisticPosition += (float)newRotate * multiplier;
		delta = fabs(_ballisticPosition) - fabs(_lastBroadcastPosition);
		
		if (newButton)
			translatedModifiers |= ePowerMateModifier_Button;

		if (delta <= -1.0 || delta >= 1.0) {
			_lastBroadcastPosition = _ballisticPosition;
			devEvent = [pmateEvent createForDeviceIndex: deviceIndex event: newRotate < 0 ? ePowerMateAction_RotateLeft : ePowerMateAction_RotateRight
				modifiers: translatedModifiers absValue: (float)_absolutePosition / kPowerMateRevolutionUnits relValue: (int)delta];

			_activeEventID = [devEvent eventID];
			[[pmateManager defaultManager] handleEvent: devEvent]; 
			_lastAction = [devEvent eventType];
		}
		
		_lastRotateTime = eventTime;
	}
}

- (io_service_t) serviceID
{
	return _serviceID;
}

- (unsigned long) activeEventID
{
	return _activeEventID;
}

- (unsigned int) lastAction
{
	return _lastAction;
}

- (NSString *) title
{
	return [NSString stringWithFormat: @"PowerMate %08x", _serviceID];
}

- (void) setTitle: (NSString *) inTitle
{
	// read only
}

- (void) sendCommand: (UInt16) inCommand
	withValue: (UInt16) inValue
{
	IOReturn			result;

	if ((result = (*_usbDevice)->USBDeviceOpen(_usbDevice)) == kIOReturnSuccess) {
		IOUSBDevRequest		request;
		
		request.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBVendor, kUSBInterface);
		request.bRequest = 1;
		request.wValue = inCommand;
		request.wIndex = inValue;
		request.wLength = 0x0000;
		request.pData = nil;
		
		result = (*_usbDevice)->DeviceRequest(_usbDevice, &request);
		if (result != kIOReturnSuccess)
			NSLog(@"DeviceRequest %08x", result);
		
		(*_usbDevice)->USBDeviceClose(_usbDevice);
	}
	else {
		NSLog(@"failed to open usb device %08x", result);
	}
}

- (void) restoreState: (NSDictionary *) inSavedState
{
	NSDictionary		*lastState = [_savedStates lastObject];
	
	if (inSavedState == lastState) {	// only switch states if we're the active state
		[self setPulseState: [inSavedState valueForKey: @"pulseState"]];
		[self setBrightness: [inSavedState valueForKey: @"brightness"]];
		[self setPulseRate: [inSavedState valueForKey: @"pulseRate"]];
	}
	
	[_savedStates removeObject: inSavedState];
}

- (void) saveAndRestoreStateAfter: (NSTimeInterval) inRestoreTime
{
	NSMutableDictionary		*savedState = [NSMutableDictionary dictionary];
	NSTimeInterval			interval = [NSDate timeIntervalSinceReferenceDate] + inRestoreTime;

	[savedState setValue: _pulseState forKey: @"pulseState"];
	[savedState setValue: _pulseRate forKey: @"pulseRate"];
	[savedState setValue: _brightness forKey: @"brightness"];
	[savedState setValue: [NSNumber numberWithDouble: interval] forKey: @"restoreTime"];
	[_savedStates addObject: savedState];
	
	[self performSelector: @selector(restoreState:) withObject: savedState afterDelay: inRestoreTime];
}

- (NSNumber *) brightness
{
	return _brightness;
}

- (void) setBrightness: (NSNumber *) inBrightness
{
	if ([inBrightness floatValue] < 0.0)
		inBrightness = [NSNumber numberWithFloat: 0.0];
	else if ([inBrightness floatValue] > 1.0)
		inBrightness = [NSNumber numberWithFloat: 1.0];
		
	[_brightness autorelease];
	_brightness = [inBrightness retain];
	
	[self sendCommand: kPowerMateCmd_SetBrightness withValue: [_brightness floatValue] * 255];
}

- (NSNumber *) pulseState
{
	return _pulseState;
}

- (void) setPulseState: (NSNumber *) inPulseState
{
	[_pulseState autorelease];
	_pulseState = [inPulseState retain];

	[self sendCommand: kPowerMateCmd_SetAlwaysPulse withValue: [_pulseState boolValue]];
}

- (NSNumber *) pulseRate
{
	return _pulseRate;
}

- (void) setPulseRate: (NSNumber *) inPulseRate
{	
	UInt16		baseValue;

	if ([inPulseRate floatValue] < 0.0)
		inPulseRate = [NSNumber numberWithFloat: 0.0];
	else if ([inPulseRate floatValue] > 1.0)
		inPulseRate = [NSNumber numberWithFloat: 1.0];

	[_pulseRate autorelease];
	_pulseRate = [inPulseRate retain];

	baseValue = (UInt16)([_pulseRate floatValue] * 64);
	
	// values range from:
	// 0x0f00 - 0x0000 / 0x0002 - 0x3002
	[self sendCommand: kPowerMateCmd_SetPulseRate withValue: (baseValue < 16) ? ((15 - baseValue) << 8) : ((baseValue - 16) << 8) + 0x0002];
}

@end
