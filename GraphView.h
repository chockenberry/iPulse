//
//	GraphView.h
//

#import <Cocoa/Cocoa.h>

#define GRAPH_VIEW_MOVED @"GraphViewMoved"
#define GRAPH_VIEW_ENTERED @"GraphViewEntered"
#define GRAPH_VIEW_UPDATE @"GraphViewUpdate"
#define GRAPH_VIEW_EXITED @"GraphViewExited"

typedef struct _GraphPoint {
    float radius;
    float angle;
} GraphPoint;

@interface GraphView : NSView
{
	id theContentDrawer;
	SEL theContentDrawingMethod;

	NSPoint offsetMouseLoc;

	BOOL mouseInView;
	BOOL mouseDown;

	GraphPoint graphPoint;
}

- (float)angleOfPoint:(NSPoint)point;
- (float)radiusOfPoint:(NSPoint)point;

- (void)updateGraphPoint;
- (GraphPoint)getGraphPoint;

- (BOOL)acceptsFirstResponder:(NSEvent *)theEvent;
- (void)keyDown:(NSEvent *)theEvent;
- (void)flagsChanged:(NSEvent *)theEvent;
- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
- (void)mouseMoved:(NSEvent *)theEvent;
- (void)mouseEntered:(NSEvent *)theEvent;
- (void)mouseExited:(NSEvent *)theEvent;
- (void)mouseDown:(NSEvent *)theEvent;
- (void)mouseUp:(NSEvent *)theEvent;


- (void)setContentDrawer:(id)theDrawer method:(SEL)theMethod;

@end
