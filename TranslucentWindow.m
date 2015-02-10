//
//	TranslucentWindow.m
//

#import "TranslucentWindow.h"


@implementation TranslucentWindow

- initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	if (self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag])
	{
		[self setReleasedWhenClosed:NO];
		[self setBackgroundColor:[NSColor clearColor]];
		[self setAlphaValue:0.0];
		[self setOpaque:NO];
	}

	return (self);
}

// Windows that use the NSBorderlessWindowMask can't become key by default.  Therefore, controls in such windows
// won't ever be enabled by default.  Thus, we override this method to change that.

- (BOOL)canBecomeKeyWindow
{
	return (YES);
}


- (BOOL)acceptsFirstResponder:(NSEvent *)theEvent
{
	return (YES);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	return (YES);
}

@end
