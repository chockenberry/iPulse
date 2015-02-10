//
//  TooltipWindow.m
//  iPulse
//
//  Created by Craig Hockenberry on Sat Dec 21 2002.
//  Copyright (c) 2001 __MyCompanyName__. All rights reserved.
//

#import "TooltipWindow.h"

#import <AppKit/NSColor.h>

@implementation NSWindow(TooltipLike)

+ (NSWindow *)tooltipLikeWindowWithContentRect:(NSRect)someRect
{
	NSWindow *yourWindow = [[NSWindow alloc] initWithContentRect:someRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreRetained defer:YES]; 
	
	// This seems "proper", may want a diff. level though.. 
	[yourWindow setLevel:NSStatusWindowLevel]; 
	
	// Mouse events aren't needed, most likely... 
	//[yourWindow setIgnoresMouseEvents:YES]; 
	
	// Tooltips are more of a toned-down peachy-yellow I think. 
	// This will be bright, I just know it. ;-) 
	//[yourWindow setBackgroundColor: [NSColor yellowColor] ]; 
	
	// ? 
	return ([yourWindow autorelease]); 
}

@end 

