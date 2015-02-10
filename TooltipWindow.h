//
//  TooltipWindow.h
//  iPulse
//
//  Created by Craig Hockenberry on Sat Dec 21 2002.
//  Copyright (c) 2001 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/NSWindow.h>


@interface NSWindow(TooltipWindow)


+ (NSWindow *)tooltipLikeWindowWithContentRect:(NSRect)someRect;


@end
