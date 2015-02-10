//
//  pmateManager.h
//  Proxi
//
//  Created by Casey Fleser on 1/8/06.
//  Copyright 2006 Griffin Technology. All rights reserved.
//

#import <Cocoa/Cocoa.h>

enum {
    ePowerMateAction_ButtonPress = 0,
    ePowerMateAction_ButtonRelease,
    ePowerMateAction_RotateLeft,
    ePowerMateAction_RotateRight,
    ePowerMateAction_NumActions
};

enum {
    ePowerMateModifier_None = 0x00,
    ePowerMateModifier_Shift = 0x01,
    ePowerMateModifier_Control = 0x02,
    ePowerMateModifier_Option = 0x04,
    ePowerMateModifier_Command = 0x08,
    ePowerMateModifier_Button = 0x10
};

#define kPowerMateVendor	0x077d
#define kPowerMateProduct	0x0410

@class pmateDevice;
@class pmateEvent;

@interface pmateManager : NSObject
{
	NSRunLoop				*_pmateLoop;
	io_iterator_t			_deviceIterator;
	IONotificationPortRef 	_notifyPort;
	
	NSMutableArray			*_devices;
}

+ (pmateManager *)	defaultManager;

- (NSRunLoop *)		runLoop;

- (void)			start;
- (void)			matchDevices;
- (void)			addDevice: (pmateDevice *) inDevice;
- (void)			removeDevice: (io_service_t) inServiceID;
- (NSArray *)		devices;
- (pmateDevice *)	deviceAtIndex: (unsigned) inIndex;

- (void)			handleEvent: (pmateEvent *) inEvent;

@end
