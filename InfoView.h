//
//	InfoView.h
//

#import <Cocoa/Cocoa.h>

@interface InfoView : NSView
{
	id theContentDrawer;
	SEL theContentDrawingMethod;
}

- (void)setContentDrawer:(id)theDrawer method:(SEL)theMethod;

@end
