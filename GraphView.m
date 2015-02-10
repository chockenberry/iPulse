//
//	GraphView.m
//

#import "GraphView.h"


#define USE_INTERPOLATION 1

#define DEBUG_NOTIFICATIONS 0
#define DEBUG_METHODS 0

@implementation GraphView

- (float)angleOfPoint:(NSPoint)point
{
	float angle = (atan2(point.y, point.x)) / M_PI * 180.0;
	if (angle < 0)
	{
		angle = 360.0 + angle;
	}
	return (angle);
}

- (float)radiusOfPoint:(NSPoint)point
{
	return (sqrt((point.x * point.x) + (point.y * point.y)));
}


- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];

	theContentDrawer = nil;

	mouseInView = NO;
	mouseDown = NO;

	return self;
}

- (void)updateGraphPoint
{
	NSRect viewFrame = [self frame];

	NSPoint windowMouseLoc = [[self window] convertScreenToBase:[NSEvent mouseLocation]];
	NSPoint normalizedLoc;

	normalizedLoc.x = ((windowMouseLoc.x / NSWidth(viewFrame)) * 2.0) - 1.0;
	normalizedLoc.y = ((windowMouseLoc.y / NSHeight(viewFrame)) * 2.0) - 1.0;

	graphPoint.radius = [self radiusOfPoint:normalizedLoc];
	graphPoint.angle = [self angleOfPoint:normalizedLoc];
}

- (GraphPoint)getGraphPoint
{
	return (graphPoint);
}

- (void)drawRect:(NSRect)rect
{
#if USE_INTERPOLATION
	NSGraphicsContext* graphicsContext;
	BOOL wasAntialiasing;
	NSImageInterpolation previousImageInterpolation;
#endif	

	if (mouseInView)
	{
		[self updateGraphPoint];
	}
	
	[[NSColor clearColor] set];
	NSRectFill(rect);

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

- (void)flagsChanged:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Flags changed (keyboard)");
#endif
}


- (BOOL)acceptsFirstResponder:(NSEvent *)theEvent
{
	return (YES);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	return (YES);
}


- (void)keyDown:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Key down");
#endif
}

- (void)mouseEntered:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse entered");
#endif

	mouseInView = YES;

	[self updateGraphPoint];

#if DEBUG_NOTIFICATIONS
	NSLog(@"GraphView: Sending GRAPH_VIEW_ENTERED");
#endif
	[[NSNotificationCenter defaultCenter] postNotificationName:GRAPH_VIEW_ENTERED object:nil];
}

- (void)mouseExited:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse exited");
#endif

	mouseInView = NO;

#if DEBUG_NOTIFICATIONS
	NSLog(@"GraphView: Sending GRAPH_VIEW_EXITED");
#endif
	[[NSNotificationCenter defaultCenter] postNotificationName:GRAPH_VIEW_EXITED object:nil];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse moved");
#endif

	if (mouseInView)
	{
		[self updateGraphPoint];

#if DEBUG_NOTIFICATIONS
		NSLog(@"GraphView: Sending GRAPH_VIEW_UPDATE");
#endif
		[[NSNotificationCenter defaultCenter] postNotificationName:GRAPH_VIEW_UPDATE object:nil];
	}
}

- (void)rightMouseDown:(NSEvent *)theEvent;
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse down (right)");
#endif

	[NSMenu popUpContextMenu:[self menu] withEvent:theEvent forView:self];
}

- (void)rightMouseDragged:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse dragged (right)");
#endif
}

- (void)mouseDown:(NSEvent *)theEvent
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse down");
#endif
	
	mouseDown = YES;

	offsetMouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	NSPoint mouseLoc;
	NSPoint globalMouseLoc;
	NSPoint tempWindowLoc;

#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse dragged");
#endif

	mouseLoc = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	globalMouseLoc = [[self window] convertBaseToScreen:mouseLoc];
	
	// calculate the new origin of the window
	tempWindowLoc.x = (globalMouseLoc.x - offsetMouseLoc.x);
	tempWindowLoc.y = (globalMouseLoc.y - offsetMouseLoc.y);
	[[self window] setFrameOrigin:tempWindowLoc];

#if DEBUG_NOTIFICATIONS
	NSLog(@"GraphView: Sending GRAPH_VIEW_MOVED");
#endif
	[[NSNotificationCenter defaultCenter] postNotificationName:GRAPH_VIEW_MOVED object:nil];
}

- (void)mouseUp:(NSEvent *)theEvent;
{
#if DEBUG_METHODS
	NSLog(@"GraphView: Mouse up");
#endif

	mouseDown = NO;
}


- (void)setContentDrawer:(id)theDrawer method:(SEL)theMethod
{
	theContentDrawer = theDrawer;
	theContentDrawingMethod = theMethod;
}

@end
