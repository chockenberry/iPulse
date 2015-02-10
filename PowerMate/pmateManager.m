//
//  pmateManager.m
//  Proxi
//
//  Created by Casey Fleser on 1/8/06.
//  Copyright 2006 Griffin Technology. All rights reserved.
//

#import "pmateManager.h"
#import "pmateDevice.h"
#import "pmateEvent.h"
#import "pmateTrigger.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

static pmateManager		*sPowerMateMgr = nil;

static void DeviceAdded(
	void			*inRefCon,
	io_iterator_t   inIterator)
{
	pmateManager	*monitor = (pmateManager *)inRefCon;
	pmateDevice		*device;
	io_service_t	obj;

	while ((obj = IOIteratorNext(inIterator)) != nil) {
		if ((device = [[pmateDevice alloc] initWithService: obj]) == nil)
			IOObjectRelease(obj);
		else {
			[monitor addDevice: device];
			[device release];
		}
	}
}

static void DeviceRemoved(
	void			*inRefCon,
	io_iterator_t   inIterator)
{
	pmateManager	*monitor = (pmateManager *)inRefCon;
	io_service_t	obj;

	while ((obj = IOIteratorNext(inIterator)) != nil) {
		[monitor removeDevice: obj];
	}
}

@implementation pmateManager

+ (void) initialize
{
	[pmateManager setKeys: [NSArray arrayWithObject: @"devices"] triggerChangeNotificationsForDependentKey: @"deviceNames"];
}

+ (pmateManager *) defaultManager
{
	if (sPowerMateMgr == nil)
		sPowerMateMgr = [[pmateManager alloc] init];
	
	return sPowerMateMgr;
}

+ (BOOL) automaticallyNotifiesObserversForKey: (NSString *) inKey
{
	static NSArray		*sManualKeys = nil;

	if (sManualKeys == nil)
		sManualKeys = [[NSArray arrayWithObjects: @"devices", nil] retain];
	
	return [sManualKeys containsObject: inKey] ? NO : [NSObject automaticallyNotifiesObserversForKey: inKey];
}

- (id) init
{
	if ((self = [super init]) != nil)
		_devices = [[NSMutableArray array] retain];
	
	return self;
}

- (void) dealloc
{
	[super dealloc];
}

- (void) shutdown: (NSNotification *) inNotification
{
	NSEnumerator	*deviceEnumerator = [_devices objectEnumerator];
	NSMutableArray	*previousValues = [NSMutableArray array];
	pmateDevice		*device;

	while ((device = [deviceEnumerator nextObject]) != nil) {
		[previousValues addObject: [NSDictionary dictionaryWithObjectsAndKeys:
										[device brightness], @"brightness",
										[device pulseRate], @"pulseRate",
										[device pulseState], @"shouldPulse",
										nil]];
	}
	
	[[NSUserDefaults standardUserDefaults] setObject: previousValues forKey: @"powermate"];

	while ([_devices count]) {
		device = [_devices lastObject];
		[device shutdownDevice];
		[self willChangeValueForKey: @"devices"];
		[_devices removeObject: device];
		[self didChangeValueForKey: @"devices"];
	}
}

- (NSRunLoop *) runLoop
{
	return _pmateLoop;
}

- (void) start
{
	[NSThread detachNewThreadSelector: @selector(startPmateRunLoop:) toTarget: self withObject: self];
}

- (void) startPmateRunLoop: (id) inObj
{
	NSAutoreleasePool	*ourPool = [[NSAutoreleasePool alloc] init];
	BOOL				running = YES;
	
	_pmateLoop = [NSRunLoop currentRunLoop];
	[self matchDevices];
	[ourPool release];
	
	while (running) {
		ourPool = [[NSAutoreleasePool alloc] init];

		// we stop every now and again to clear the autorelease pool
		running = [_pmateLoop runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 2]];

		[ourPool release];
	}
}

- (void) matchDevices
{
	IOReturn				result;
	CFMutableDictionaryRef  matchingDict;
	
	[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(shutdown:) name: NSApplicationWillTerminateNotification object: NSApp];

	if ((matchingDict = IOServiceMatching(kIOHIDDeviceKey)) == nil) {
		NSLog(@"IOServiceMatching failed File %s Line %d", __FILE__, __LINE__);
		result = kIOReturnError;
	}
	else {
		NSMutableDictionary		*dict = (NSMutableDictionary *)matchingDict;
		
		CFRetain(matchingDict);
		[dict setValue: [NSNumber numberWithLong: kPowerMateProduct] forKey: [NSString stringWithCString: kIOHIDProductIDKey]];
		[dict setValue: [NSNumber numberWithLong: kPowerMateVendor] forKey: [NSString stringWithCString: kIOHIDVendorIDKey]];
		
		_notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
		result = IOServiceAddMatchingNotification(_notifyPort, kIOFirstMatchNotification, matchingDict, &DeviceAdded, self, &_deviceIterator);
		
		if (result != KERN_SUCCESS) {
			NSLog(@"IOServiceAddMatchingNotification failed File %s Line %d - result %08x", __FILE__, __LINE__, result);
		}
		else {
			DeviceAdded((void *)self, _deviceIterator);
			
			result = IOServiceAddMatchingNotification(_notifyPort, kIOTerminatedNotification, matchingDict, &DeviceRemoved, self, &_deviceIterator);
			
			if (result != KERN_SUCCESS) {
				NSLog(@"IOServiceAddMatchingNotification failed File %s Line %d - result %08x", __FILE__, __LINE__, result);
			}
			else {
				CFRunLoopSourceRef 		runLoopSource;
				
				DeviceRemoved((void *)self, _deviceIterator);

				runLoopSource = IONotificationPortGetRunLoopSource(_notifyPort);
				CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
				CFRelease(runLoopSource);
			}
		}
		
	}
}

- (void) addDevice: (pmateDevice *) inDevice
{
	NSArray			*previousValues = [[NSUserDefaults standardUserDefaults] objectForKey: @"powermate"];
	unsigned int	newIdx = [_devices count];
	
	if (newIdx < [previousValues count]) {
		NSDictionary		*valueInfo = [previousValues objectAtIndex: newIdx];
		
		if (valueInfo != nil) {
			NSNumber		*brightness = [valueInfo valueForKey: @"brightness"];
			NSNumber		*pulseRate = [valueInfo valueForKey: @"pulseRate"];
			NSNumber		*shouldPulse = [valueInfo valueForKey: @"shouldPulse"];
			
			[inDevice setBrightness: brightness];
			[inDevice setPulseRate: pulseRate];
			[inDevice setPulseState: shouldPulse];
		}
	}

	[self willChangeValueForKey: @"devices"];
	[_devices addObject: inDevice];
	[self didChangeValueForKey: @"devices"];
}

- (void) removeDevice: (io_service_t) inServiceID
{
	NSEnumerator	*deviceEnumerator = [_devices objectEnumerator];
	pmateDevice		*device;
	
	while ((device = [deviceEnumerator nextObject]) != nil) {
		if ([pmateDevice locationID: [device serviceID]] == [pmateDevice locationID: inServiceID]) {
			[device shutdownDevice];
			[self willChangeValueForKey: @"devices"];
			[_devices removeObject: device];
			[self didChangeValueForKey: @"devices"];
			break;
		}
	}
}

- (NSArray *) devices
{
	return _devices;
}

- (NSArray *) deviceNames
{
	NSMutableArray		*deviceNames = [NSMutableArray arrayWithObject: @"PowerMate"];
	int					deviceCount = [_devices count];
	
	if (deviceCount > 1) {
		int			i;
		
		for (i=1; i<deviceCount ; i++)
			[deviceNames addObject: [NSString stringWithFormat: @"PowerMate %d", i+1]];
	}

	return deviceNames;
}

- (pmateDevice *) deviceAtIndex: (unsigned) inIndex
{
	pmateDevice		*device = nil;
	
	if (inIndex < [_devices count])
		device = [_devices objectAtIndex: inIndex];
		
	return device;
}

- (void) handleEvent: (pmateEvent *) inEvent
{
	pmateDevice		*deviceForEvent = [self deviceAtIndex: [inEvent deviceIndex]];
	
	if (deviceForEvent != nil) {
		// if another event has been generated, we can assume this one is no longer valid and toss it out
		
		if ([inEvent eventID] == [deviceForEvent activeEventID]) {
			NSEnumerator	*triggerEnumerator;
			NSMutableArray	*affectedTriggers = [NSMutableArray array];
			NSArray			*triggerList = [pmateTrigger triggerList];
			pmateTrigger	*trigger;
			NSTimeInterval	startTime = [inEvent processedOffset];
			NSTimeInterval	endTime = [NSDate timeIntervalSinceReferenceDate] - [inEvent eventTime];
			NSTimeInterval	nextTime = 999.0;
			BOOL			canExecuteContingency = YES;
		
			triggerEnumerator = [triggerList objectEnumerator];
			while ((trigger = [triggerEnumerator nextObject]) != nil) {
				if ([[trigger deviceAction] unsignedIntValue] == [inEvent eventType] &&
						[[trigger modifiers] unsignedIntValue] == [inEvent modifiers] &&
						[[trigger deviceIndex] unsignedIntValue] == [inEvent deviceIndex]) {
					
					switch ([inEvent eventType]) {
						case ePowerMateAction_ButtonPress:
						case ePowerMateAction_ButtonRelease: {
								NSTimeInterval		buttonTime = [[trigger buttonTime] doubleValue];
								
								if (buttonTime > endTime) {		// maybe later?
									if (buttonTime < nextTime)	
										nextTime = buttonTime;	// math later
								}
								else if (buttonTime >= startTime && buttonTime < endTime) {
									[affectedTriggers addObject: trigger];
								}
							}
							break;
								
						case ePowerMateAction_RotateLeft:
						case ePowerMateAction_RotateRight: {
								if (![[trigger gameMode] boolValue] || [deviceForEvent lastAction] != [inEvent eventType])
									[affectedTriggers addObject: trigger];
							}
							break;
					}
				}
			}
		
			[inEvent setProcessedOffset: endTime];
			
			if (nextTime < 999.0) {		// reschedule this event
				NSTimeInterval	newEnd = nextTime - ([NSDate timeIntervalSinceReferenceDate] - [inEvent eventTime]);
				
				[NSTimer scheduledTimerWithTimeInterval: newEnd target: self
					selector: @selector(resendEvent:) userInfo: inEvent repeats: NO];
					
				canExecuteContingency = NO;
			}
			
			if ([affectedTriggers count]) {
				NSMutableDictionary	*notificationInfo = [NSMutableDictionary dictionary];
				NSMutableArray		*executionList = [NSMutableArray array];
				pmateTrigger		*contingentTrigger = nil;
				
				triggerEnumerator = [affectedTriggers objectEnumerator];
				while (contingentTrigger == nil && (trigger = [triggerEnumerator nextObject]) != nil) {
					if ([[trigger contingent] boolValue]) {
						contingentTrigger = trigger;
						[affectedTriggers removeObject: contingentTrigger];
					}
				}
				
				if (contingentTrigger != nil) {
					[notificationInfo setValue: [NSDictionary dictionaryWithObjectsAndKeys:
													[NSValue valueWithPointer: contingentTrigger], GContingentTriggerAttribute,
													[contingentTrigger notificationDictionaryForEvent: inEvent], GContingentValuesAttribute, nil]
													forKey: GContingentAttribute];
				}
				
				triggerEnumerator = [affectedTriggers objectEnumerator];
				while ((trigger = [triggerEnumerator nextObject]) != nil) {
					[executionList addObject: [NSDictionary dictionaryWithObjectsAndKeys:
												[NSValue valueWithPointer: trigger], GContingentTriggerAttribute,
												[trigger notificationDictionaryForEvent: inEvent], GContingentValuesAttribute, nil]];
				}
				
				[notificationInfo setValue: executionList forKey: GContingentTriggerListAttribute];

				[self performSelectorOnMainThread: @selector(forwardNotification:) withObject: notificationInfo waitUntilDone: NO];
//				[[NSNotificationCenter defaultCenter] postNotificationName: GContingentNotificationName object: self userInfo: notificationInfo];
			}
		}
	}
}

- (void) resendEvent: (NSTimer *) inTimer
{
	pmateEvent	*event = [inTimer userInfo];
	
	[self handleEvent: event];
}

- (void) forwardNotification: (NSDictionary *) inNotificationInfo
{
	[[NSNotificationCenter defaultCenter] postNotificationName: GContingentNotificationName object: self userInfo: inNotificationInfo];
}

@end
