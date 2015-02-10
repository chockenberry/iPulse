//
//	InfoView.m
//

#import "InfoView.h"

#import "Preferences.h"

#define USE_INTERPOLATION 0

@implementation InfoView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];

	theContentDrawer = nil;

	return self;
}


- (void)drawRect:(NSRect)rect
{
#if USE_INTERPOLATION
	NSGraphicsContext* graphicsContext;
	BOOL wasAntialiasing;
	NSImageInterpolation previousImageInterpolation;
#endif
	
#if USE_INTERPOLATION
	// set current graphics context to use antialiasing and high-quality image scaling.
	graphicsContext = [NSGraphicsContext currentContext];
	wasAntialiasing = [graphicsContext shouldAntialias];
	previousImageInterpolation = [graphicsContext imageInterpolation];
	[graphicsContext setShouldAntialias:YES];
	[graphicsContext setImageInterpolation:NSImageInterpolationHigh];
#endif
	
	// draw the content
	if (theContentDrawer != nil)
	{
		[theContentDrawer performSelector:theContentDrawingMethod];
	}

#if USE_INTERPOLATION
	// restore previous graphics context settings.
	[graphicsContext setShouldAntialias:wasAntialiasing];
	[graphicsContext setImageInterpolation:previousImageInterpolation];
#endif
}


- (BOOL)isOpaque
{
	return YES; // view covers rect -- AppKit won't try to draw behind 
}

- (void)setContentDrawer:(id)theDrawer method:(SEL)theMethod
{
	theContentDrawer = theDrawer;
	theContentDrawingMethod = theMethod;
}

@end
