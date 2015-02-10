//
//  KeyBroadcaster.h
//
//  Created by Quentin D. Carnicelli on Tue Jun 18 2002.
//  Copyright (c) 2001 Quentin D. Carnicelli. All rights reserved.
//

#import <AppKit/AppKit.h>


@interface KeyBroadcaster : NSButton
{
}

+ (long)cocoaToCarbonModifiers: (long)cocoaModifiers;

@end

extern NSString* KeyBraodcasterKeyEvent;