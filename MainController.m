//
//	MainController.m - Main Application Controller Class
//

#import "MainController.h"

//#import "Licensing.h"

#import <string.h>
#import <time.h>

// for setpriority
#import <sys/resource.h>

// for battery info
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

// for network info
#include <IOKit/network/IOEthernetInterface.h>
#include <IOKit/network/IONetworkInterface.h>
#include <IOKit/network/IONetworkController.h>

// for temperature info
#import <mach/mach.h>
#import <mach/mach_error.h>

// for network interface info
#include <SystemConfiguration/SystemConfiguration.h>
#include <SystemConfiguration/SCDynamicStore.h>

// for julian date & moon phase functions
#include "Phase.h"

// miscellaneous math definitions
#include "MathDefinitions.h"

// for process information
#import "AGProcess.h"

// for hotkey library
#import "KeyCombo.h"
#import "KeyComboPanel.h"
#import "HotKeyCenter.h"

#if OPTION_INCLUDE_MATRIX_ORBITAL	
// for serial port communication
#include <IOKit/serial/IOSerialKeys.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
// to hold the original termios attributes so we can reset them
static struct termios gOriginalTTYAttrs;
#endif

// for getpid
#include <unistd.h>

// for power source information
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

// for sleep & wake notifications
#import <IOKit/IOMessage.h>

// for Sparkle updates
#import "Sparkle/SUUpdater.h"
static SUUpdater *sparkleUpdater = nil;


#define GRAPH_SIZE 128.0
#define SAMPLE_SIZE 10
#define TRANSPARENCY_STEPS 10

// info window dimensions
#define INFO_WIDTH 300.0
#define INFO_HEIGHT 300.0
#define INFO_RADIUS 8.0
#define INFO_OFFSET 12.0

	
// interval for special effects (like info window fading)
#define EFFECT_INTERVAL 0.05

// number of steps in effect
#define EFFECT_STEPS 24

// this magic number is 4 * (sqrt(2) - 1)/3 -- used to draw moon ellipse
#define KAPPA 0.5522847498


// hotkey names
#define HOTKEY_TOGGLE_WINDOW @"HotkeyToggleWindow"
#define HOTKEY_TOGGLE_IGNORE_MOUSE @"HotkeyToggleIgnoreMouse"
#define HOTKEY_LOCK_INFO_WINDOW @"HotkeyLockInfoWindow"
#define HOTKEY_TOGGLE_STATUS_ITEM @"HotkeyToggleStatusItem"

@implementation MainController

BOOL hasColor(NSColor *color)
{
	return ([color alphaComponent] > 0.0);
}

- (NSArray *)collectProcesses
{
	NSArray *result = nil;

	if (haveAuthorizedTaskPort) {
		result = [AGProcess allProcesses];
	}
	else {
		// without an authorized task port, everything is going to fail, so just return and empty array
		result = [NSArray array];
	}
	
	return result;
}

#pragma mark -

// called by graphView to transfer graphImage onto view
- (void)drawGraphImage
{
	[graphImage drawInRect:NSMakeRect(0, 0, NSWidth([graphWindow frame]), NSHeight([graphWindow frame]))
		fromRect:NSMakeRect(0, 0, GRAPH_SIZE, GRAPH_SIZE) operation:NSCompositeCopy
		fraction:1.0];
}

#pragma mark -

- (void)setWindows
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults boolForKey:WINDOW_SHOW_FLOATING_KEY])
	{
		NSRect graphWindowFrame;	
		NSPoint graphWindowCenter;
		float size;

/*
		graphWindowCenter.x = [defaults floatForKey:WINDOW_FLOATING_CENTER_X_KEY];
		graphWindowCenter.y = [defaults floatForKey:WINDOW_FLOATING_CENTER_Y_KEY];
		size = [defaults floatForKey:WINDOW_FLOATING_SIZE_KEY];
*/
		graphWindowFrame = [graphWindow frame];
		graphWindowCenter.x = graphWindowFrame.origin.x + (graphWindowFrame.size.width / 2.0);
		graphWindowCenter.y = graphWindowFrame.origin.y + (graphWindowFrame.size.height / 2.0);
		size = [defaults floatForKey:WINDOW_FLOATING_SIZE_KEY];
		
		graphWindowFrame.size = NSMakeSize(size, size);
		graphWindowFrame.origin = NSMakePoint(graphWindowCenter.x - (size/2.0), graphWindowCenter.y - (size/2.0));
		[graphWindow setFrame:graphWindowFrame display:YES];

// TODO - is this really necessary? why?
		[graphWindow orderWindow:NSWindowBelow relativeTo:[preferences windowNumber]];
		
		switch ([defaults integerForKey:WINDOW_FLOATING_LEVEL_KEY])
		{
		case 0:
			[graphWindow setLevel:kCGDesktopIconWindowLevel];
			break;
		case 1:
			[graphWindow setLevel:NSNormalWindowLevel];
			break;
		case 2:
			[graphWindow setLevel:kCGModalPanelWindowLevel]; // above utility windows, below dock
			break;
		case 3:
			[graphWindow setLevel:kCGPopUpMenuWindowLevel]; // above dock
			// [graphWindow setLevel:kCGMaximumWindowLevel]; // above dock & screensaver
			break;
		}

		if ([defaults boolForKey:WINDOW_FLOATING_NO_HIDE_KEY])
		{
			[graphWindow setCanHide:NO];
			[infoWindow setCanHide:NO];
		}
		else
		{
			[graphWindow setCanHide:YES];
			[infoWindow setCanHide:YES];
		}

		if ([defaults boolForKey:WINDOW_FLOATING_IGNORE_CLICK_KEY])
		{
			// make window transparent to Cocoa appications
			[graphWindow setIgnoresMouseEvents:YES];
		}
		else
		{
			// make window opaque to Cocoa appications
			[graphWindow setIgnoresMouseEvents:NO];
		}

		if (fade >= 0 && fade <= EFFECT_STEPS)
		{
			// info window is visible
			[infoWindow orderFront:self];
		}
	} 
	else
	{
		infoWindowIsLocked = NO;
		
		[graphWindow orderOut:self];
		
		[infoWindow orderOut:self];
	}
}

- (void)updateWindow
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSData *data = [defaults objectForKey:OTHER_IMAGE_KEY];

	[backgroundImage release];
	
	if (data)
	{
		backgroundImage = [[NSUnarchiver unarchiveObjectWithData:data] retain];
		//NSLog(@"MainController: updateWindow: loaded image named '%@'", [backgroundImage name]);
	}
	else
	{
		backgroundImage = nil;
	}
	
	[self updateIconAndWindow];
}

#pragma mark -

- (void)updateStatus
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSData *data = [defaults objectForKey:GLOBAL_STATUS_IMAGE_KEY];

	[statusBackgroundImage release];
	
	if (data)
	{
		statusBackgroundImage = [[NSUnarchiver unarchiveObjectWithData:data] retain];
		//NSLog(@"MainController: updateStatus: loaded image named '%@'", [statusBackgroundImage name]);
	}
	else
	{
		statusBackgroundImage = [NSImage imageNamed:@"StatusBackground.tif"];
	}
}

#pragma mark -

- (void)updateHotkeys
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	HotKeyCenter *hotkeyCenter = [HotKeyCenter sharedCenter];
	
	KeyCombo *toggleWindowKeyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_FLOATING_WINDOW_KEY];
	KeyCombo *toggleIgnoreMouseKeyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_IGNORE_MOUSE_KEY];
	KeyCombo *lockInfoWindowKeyCombo = [defaults keyComboForKey:GLOBAL_LOCK_INFO_WINDOW_KEY];
	KeyCombo *toggleStatusItemKeyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_STATUS_ITEM_KEY];

	if (toggleWindowKeyCombo)
	{
		[hotkeyCenter removeHotKey:HOTKEY_TOGGLE_WINDOW];
		[hotkeyCenter addHotKey:HOTKEY_TOGGLE_WINDOW combo:toggleWindowKeyCombo target:self action:@selector(toggleFloatingWindow:)];
	}
	if (toggleIgnoreMouseKeyCombo)
	{
		[hotkeyCenter removeHotKey:HOTKEY_TOGGLE_IGNORE_MOUSE];
		[hotkeyCenter addHotKey:HOTKEY_TOGGLE_IGNORE_MOUSE combo:toggleIgnoreMouseKeyCombo target:self action:@selector(toggleIgnoreMouse:)];
	}
	if (lockInfoWindowKeyCombo)
	{
		[hotkeyCenter removeHotKey:HOTKEY_LOCK_INFO_WINDOW];
		[hotkeyCenter addHotKey:HOTKEY_LOCK_INFO_WINDOW combo:lockInfoWindowKeyCombo target:self action:@selector(lockInfoWindow:)];
	}
	if (toggleStatusItemKeyCombo)
	{
		[hotkeyCenter removeHotKey:HOTKEY_TOGGLE_STATUS_ITEM];
		[hotkeyCenter addHotKey:HOTKEY_TOGGLE_STATUS_ITEM combo:toggleStatusItemKeyCombo target:self action:@selector(toggleStatusItem:)];
	}
}

#pragma mark -

- (NSPoint)pointAtCenter:(NSPoint)center atAngle:(float)angle atRadius:(float)radius
{
	NSPoint point;
	
	point.x = center.x + (dcos(angle) * radius);
	point.y = center.y + (dsin(angle) * radius);
	
	return (point);
}

- (float) angleAtCenter:(NSPoint)center ofPoint:(NSPoint)point
{
	NSPoint offset;
	offset.x = point.x - center.x;
	offset.y = point.y - center.y;
	
	return (atan(offset.y / offset.x));
}

- (float) radiusAtCenter:(NSPoint)center ofPoint:(NSPoint)point
{
	NSPoint offset;
	offset.x = point.x - center.x;
	offset.y = point.y - center.y;

	return (sqrt((offset.x * offset.x) + (offset.y * offset.y)));
}

#pragma mark -

- (NSString *)stringForPercentage:(float)value withPercent:(BOOL)withPercent
{
	return ([NSString stringWithFormat:@"%.1f%s", value * 100.0, (withPercent ? "%" : "")]);
}

- (NSString *)stringForPercentage:(float)value
{
	return ([self stringForPercentage:value withPercent:NO]);
}


//	Apple - KB = 2^10
//	IEEE (260.1-1993) - Kb = 2^10, kb = 10^3 (K, M, G = powers of 2 & k, m, g = powers of 10)
//	SI (IEC 60027-2) - KiB = 2^10, kB = 10^3 (Ki, Mi, Gi = powers of 2 & k, M, G = powers of 10)

typedef enum
{
	appleUnitsType = 0,
	ieeeUnitsType = 1,
	siUnitsType = 2
} UnitsType;

char *siUnits10[] = {"", "K", "M", "G", "T", "P"};
char *siUnits2[] = {"", "Ki", "Mi", "Gi", "Ti", "Pi"};

char *ieeeUnits10[] = {"", "k", "m", "g", "t", "p"};
char *ieeeUnits2[] = {"", "K", "M", "G", "T", "P"};

char *appleUnits10[] = {"", "K", "M", "G", "T", "P"};
char *appleUnits2[] = {"", "K", "M", "G", "T", "P"};

- (NSString *)stringForValue:(float)value
{
	return ([self stringForValue:(float)value powerOf10:NO withBytes:YES]);
}

- (NSString *)stringForValue:(float)value withBytes:(BOOL)withBytes
{
	return ([self stringForValue:(float)value powerOf10:NO withBytes:withBytes]);
}

- (NSString *)stringForValue:(float)value withBytes:(BOOL)withBytes withDecimal:(BOOL)withDecimal
{
	return ([self stringForValue:(float)value powerOf10:NO withBytes:withBytes withDecimal:withDecimal]);
}

- (NSString *)stringForValue:(float)value powerOf10:(BOOL)isPowerOf10 withBytes:(BOOL)withBytes
{
	return ([self stringForValue:(float)value powerOf10:isPowerOf10 withBytes:withBytes withDecimal:YES]);
}

- (NSString *)stringForValue:(float)value powerOf10:(BOOL)isPowerOf10 withBytes:(BOOL)withBytes withDecimal:(BOOL)withDecimal
{
	NSString *result = nil;
	
	if (value == 0.0)
	{
		result = NSLocalizedString(@"Dash", nil);
	}
	else if (value < 1.0)
	{
		// don't process deci, centi, milli, etc.

		if (! withBytes)
		{
			if (withDecimal)
			{
				result = [NSString stringWithFormat:@"%.1f", value];
			}
			else
			{
				result = [NSString stringWithFormat:@"%.0f", value];
			}
		}
		else
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			UnitsType unitsType = [[defaults objectForKey:GLOBAL_UNITS_TYPE_KEY] intValue];

			NSString *unitsByte = nil;

			switch (unitsType)
			{
			case appleUnitsType:
			default:
				unitsByte = NSLocalizedString(@"appleUnitsByteAbbr", nil); 
				break;
			case ieeeUnitsType:
				unitsByte = NSLocalizedString(@"ieeeUnitsByteAbbr", nil); 
				break;
			case siUnitsType:
				unitsByte = NSLocalizedString(@"siUnitsByteAbbr", nil); 
				break;
			}		

			if (withDecimal)
			{
				result = [NSString stringWithFormat:@"%.1f %@", value, unitsByte];
			}
			else
			{
				result = [NSString stringWithFormat:@"%.0f %@", value, unitsByte];
			}
		}
	}
	else
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		UnitsType unitsType = [[defaults objectForKey:GLOBAL_UNITS_TYPE_KEY] intValue];
		char **units;
		NSString *unitsByte;

		float scaledValue = 0.0;
		char *unit = NULL;
		NSString *unitByte;
		char *spacer = "";
		
		int logIndex;
		float unitScale;
		if (isPowerOf10)
		{
			// power of 10

				// logIndex: 0
				// 10^0 = 1 -> 1
				// 10^1 = 10 -> 10
				// 10^2 = 100 -> 100
				
				// logIndex: 1
				// 10^3 = 1,000 -> 1.0K
				// 10^4 = 10,000 -> 10.0K
				// 10^5 100,000 -> 100.0K

				// logIndex: 2
				// 10^6 = 1,000,000 -> 1.0M
				// 10^7 = 10,000,000 -> 10.0M
				// 10^8 = 100,000,000 -> 100.0M

			logIndex = (int)(floor(log10(value) / 3.0));
			unitScale = 1000.0;

			switch (unitsType)
			{
			case appleUnitsType:
			default:
				units = appleUnits10;
				unitsByte = NSLocalizedString(@"appleUnitsByteAbbr", nil); 
				break;
			case ieeeUnitsType:
				units = ieeeUnits10;
				unitsByte = NSLocalizedString(@"ieeeUnitsByteAbbr", nil); 
				break;
			case siUnitsType:
				units = siUnits10;
				unitsByte = NSLocalizedString(@"siUnitsByteAbbr", nil); 
				break;
			}		
		}
		else
		{
			// power of 2
			
				// logIndex: 0
				// 2^0 to (2^10 - 1) -> no change
				
				// logIndex: 1
				// 2^10 to (2^20 - 1) -> K
				
				// logIndex: 2
				// 2^20 to (2^30 - 1) -> M
				
			logIndex = (int)(floor((log(value)/log(2)) / 10.0)); // log(value)/log(2) == log2(value)
			unitScale = 1024.0;
	
			switch (unitsType)
			{
			case appleUnitsType:
			default:
				units = appleUnits2;
				unitsByte = NSLocalizedString(@"appleUnitsByteAbbr", nil); 
				break;
			case ieeeUnitsType:
				units = ieeeUnits2;
				unitsByte = NSLocalizedString(@"ieeeUnitsByteAbbr", nil); 
				break;
			case siUnitsType:
				units = siUnits2;
				unitsByte = NSLocalizedString(@"siUnitsByteAbbr", nil); 
				break;
			}			
		}
		
		if (logIndex == 0 || logIndex > 5)
		{
			// no scaling or units
			scaledValue = value;
			unit = "";
		}
		else
		{
			scaledValue = value / pow(unitScale, logIndex);
			unit = units[logIndex];
			spacer = " ";
		}
		
		if (! withBytes)
		{
			unitByte = @"";
		}
		else
		{
			unitByte = unitsByte;
			spacer = " ";
		}

		if (withDecimal)
		{
			result = [NSString stringWithFormat:@"%.1f%s%s%@", scaledValue, spacer, unit, unitByte];
		}
		else
		{
			result = [NSString stringWithFormat:@"%.0f%s%s%@", scaledValue, spacer, unit, unitByte];
		}
	}
	
	return (result);
}

#pragma mark -

- (float)computeScaleForGauge:(int)scaleType withPeak:(float)peak
{
	float result;
	
	if (scaleType < 0)
	{
		// logarithmic scale
		result = (float)scaleType * -1.0;
	}
	else if (scaleType == 0)
	{
		// automatic scale
		result = pow(10.0, ceil(log10(peak)));
	}
	else
	{
		// fixed scale
		result = (float) scaleType;
	}
	
	//NSLog(@"MainController: computeScaleForGauge: scaleType = %d, peak = %6.4f, scale = %6.4f", scaleType, peak, result);
	
	return (result);
}

- (float)scaleValueForGauge:(float)value scaleType:(int)scaleType scale:(float)scale
{
	float result = 0.0;
	
	if (value > 0.0) // avoid computation when gauges are inactive
	{
		if (scaleType < 0)
		{
			// logarithmic scale
			float logValue = log10(value);
			if (logValue < scale)
			{
				result = 0.0;
			}
			else if (logValue > scale + 3.0)
			{
				result = 1.0;
			}
			else
			{
				result = (logValue - scale) / 3.0;
			}
			//NSLog(@"MainController: scaleValueForGauge: scaleType = %d, value = %6.4f, logValue = %6.4f, result = %6.4f", scaleType, value, logValue, result);
		}
		else
		{
			// automatic and fixed scale
			result = value / scale;
			if (result > 1.0)
			{
				result = 1.0;
			}
			//NSLog(@"MainController: scaleValueForGauge: scaleType = %d, value = %6.4f, result = %6.4f", scaleType, value, result);
		}
	}
	
	return (result);
}

#pragma mark -

- (NSAttributedString *)attributedStringForFile:(NSString *)filename 
{
	NSBundle *bundle = [NSBundle mainBundle];
	NSAttributedString *fileString = nil;
	
	if (majorVersion == 10 && minorVersion >= 2)
	{	
		NSString *filePath = [bundle pathForResource:[filename stringByDeletingPathExtension] ofType:[filename pathExtension]];
		fileString = [[[NSAttributedString alloc] initWithPath:filePath documentAttributes:NULL] autorelease]; 
	}
	else
	{
		// load a generic file (that does not use flush right tabs)
		NSString *filePath = [bundle pathForResource:[filename stringByDeletingPathExtension] ofType:[filename pathExtension] inDirectory:nil forLocalization:@"Generic"];
		if (!filePath)
		{
			// doesn't exist, try getting the localized version
			filePath = [bundle pathForResource:[filename stringByDeletingPathExtension] ofType:[filename pathExtension]];
		}
		fileString = [[[NSAttributedString alloc] initWithPath:filePath documentAttributes:NULL] autorelease]; 
	}

	return (fileString); 
} 

- (void)replaceFormattingColor:(NSMutableAttributedString *)output inString:(NSMutableString *)outputString withColor:(NSColor *)formatColor
{
	NSRange beginRange = [outputString rangeOfString:@"{" options:NSLiteralSearch];
	NSRange endRange = [outputString rangeOfString:@"}" options:NSLiteralSearch];
	while (beginRange.length > 0 && endRange.length > 0)
	{
		NSRange formatRange = NSUnionRange(beginRange, endRange);

		[output addAttribute:NSForegroundColorAttributeName value:formatColor range:formatRange];

		[outputString replaceCharactersInRange:beginRange withString:@""];

		endRange.location -= 1; // adjust for character deletion
		[outputString replaceCharactersInRange:endRange withString:@""];
		endRange.location -= 1; // adjust for character deletion

		NSRange nextRange = NSMakeRange(endRange.location, [outputString length] - endRange.location);
		beginRange = [outputString rangeOfString:@"{" options:NSLiteralSearch range:nextRange];
		endRange = [outputString rangeOfString:@"}" options:NSLiteralSearch range:nextRange];
	}
}

- (void)replaceFormatting:(NSMutableAttributedString *)output inString:(NSMutableString *)outputString
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSColor *foregroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]];
	NSColor *formatColor = [foregroundColor colorWithAlphaComponent:([foregroundColor alphaComponent] * 0.75)];

	[self replaceFormattingColor:output inString:outputString withColor:formatColor];
}

- (void)replaceToken:(NSString *)token inString:(NSMutableString *)string withString:(NSString *)replacementString
{
	NSRange tokenRange = [string rangeOfString:token options:NSLiteralSearch];
	if (tokenRange.length > 0)
	{
		// string found
		[string replaceCharactersInRange:tokenRange withString:replacementString];
	}
#if OPTION_REPLACE_TOKEN_TEST
	else
	{
		NSLog(@"MainController: replaceToken: %@ not found", token);
	}
#endif
}

- (void)highlightToken:(NSString *)token ofAttributedString:(NSMutableAttributedString *)attributedString inString:(NSMutableString *)string
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSColor *highlightColor = [Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_HIGHLIGHT_COLOR_KEY]];

	[attributedString addAttribute:NSForegroundColorAttributeName value:highlightColor range:[string rangeOfString:token options:NSLiteralSearch]];
}

#pragma mark -

- (void)drawTextPlain:(NSString *)text atPoint:(NSPoint)center withColor:(NSColor *)color
{
	NSMutableDictionary *fontAttrs;
	NSSize size;
	NSPoint point;

	fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			[NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
			color, NSForegroundColorAttributeName,
			nil];
	size = [text sizeWithAttributes:fontAttrs];
	
	point.x = center.x - (size.width / 2.0);
	point.y = center.y - (size.height / 2.0);
	
	[text drawAtPoint:point withAttributes:fontAttrs];

	[fontAttrs release];
}

typedef enum
{
	TextHardShadowStyle = 0,
	TextSoftShadowStyle = 1
} TextShadowStyle;

- (void)drawText:(NSString *)text atPoint:(NSPoint)center withShadow:(TextShadowStyle)shadowStyle
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *fontAttrs;
	NSSize size;
	NSPoint point;

	NSColor *textColor = [Preferences colorAlphaFromString:[defaults stringForKey:OTHER_TEXT_COLOR_KEY]];

	fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
		[[NSColor blackColor] colorWithAlphaComponent:[textColor alphaComponent]], NSForegroundColorAttributeName,
		nil];
	size = [text sizeWithAttributes:fontAttrs];
	
	point.x = center.x - (size.width / 2.0);
	point.y = center.y - (size.height / 2.0);
	
	NSShadow *shadow = [[NSShadow alloc] init];
	NSSize offset = NSMakeSize(0.0, -2.0);
	[shadow setShadowOffset:offset];
	[shadow setShadowBlurRadius:2.0];
	[shadow setShadowColor:[NSColor blackColor]];
	[shadow set];
	
	if (shadowStyle == TextHardShadowStyle)
	{
		// add dark border behind text
		if (shadowStyle == TextHardShadowStyle || shadowStyle == TextSoftShadowStyle)
		{
			[text drawAtPoint:NSMakePoint(point.x + 1.0, point.y - 1.0) withAttributes:fontAttrs];
		}
	}
		
	[fontAttrs setObject:textColor forKey:NSForegroundColorAttributeName];
	
	[text drawAtPoint:point withAttributes:fontAttrs];
	
	[shadow release];
	
	[fontAttrs release];
}

- (void)drawText:(NSString *)text atPoint:(NSPoint)center
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	TextShadowStyle textShadow;
	
	if ([defaults boolForKey:OTHER_TEXT_SHADOW_DARK_KEY])
	{
		textShadow = TextHardShadowStyle;
	}
	else
	{
		textShadow = TextSoftShadowStyle;
	}
	[self drawText:text atPoint:center withShadow:textShadow];
}

- (void)drawTextOnArc:(NSString *)text atPoint:(NSPoint)center radius:(float)radius angle:(float)centerAngle
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *fontAttrs;
	NSSize size;
	NSPoint point;

	NSColor *textColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_FOREGROUND_COLOR_KEY]];

	fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:12.0], NSFontAttributeName,
		textColor, NSForegroundColorAttributeName,
		nil];
	size = [text sizeWithAttributes:fontAttrs];
	
	point.x = center.x - (size.width / 2.0);
	point.y = center.y - (size.height / 2.0);

	{
		unsigned int i;
		unsigned int stringLength = [text length];
	
		float characterIndex = 0.0;
	
		float totalRadians = torad(centerAngle) + size.width / radius;
		float offsetRadians = totalRadians / 2.0;
		
		for (i = 0; i < stringLength; i++)
		{
			NSString *character = [text substringWithRange:NSMakeRange(i, 1)];
			NSSize characterSize = [character sizeWithAttributes:fontAttrs];
	
			NSGraphicsContext *context = [NSGraphicsContext currentContext];
	
			NSAffineTransform *transform = [NSAffineTransform transform];
			NSPoint viewLocation;
			
			// We then use the layoutLocation to calculate an appropriate position for the glyph 
			// around the circle (by angle and distance, or viewLocation in rectangular coordinates).
			float angleRadians = -offsetRadians + torad(centerAngle) + characterIndex / radius;
			
			viewLocation.x = center.x + radius * sin(angleRadians);
			viewLocation.y = center.y + radius * cos(angleRadians);
			
			// We use a different affine transform for each glyph, to position and rotate it
			// based on its calculated position around the circle.  
			[transform translateXBy:viewLocation.x yBy:viewLocation.y];
			[transform rotateByRadians:-angleRadians];
			
			// We save and restore the graphics state so that the transform applies only to this glyph.
			[context saveGraphicsState];
			[transform concat];
	
			[character drawAtPoint:NSMakePoint(0,0) withAttributes:fontAttrs];
	
			[context restoreGraphicsState];
			
			characterIndex += characterSize.width;
		}
	}	
	
	[fontAttrs release];
}

#pragma mark -

- (void)drawLineFrom:(NSPoint)fromPoint to:(NSPoint)toPoint width:(float)lineWidth
{
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path moveToPoint:fromPoint];
	[path lineToPoint:toPoint];
	[path setLineWidth:lineWidth];
	[path stroke];
}

- (void)drawPointer:(float)value atPoint:(NSPoint)point
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	
	[path moveToPoint:point];
	[path lineToPoint:NSMakePoint(point.x + value, point.y)];
	[path lineToPoint:NSMakePoint(point.x, point.y - (value * 1.5))];
	[path lineToPoint:NSMakePoint(point.x - value, point.y)];
	[path lineToPoint:point];
	[path fill];
}

- (void)drawValueFrom:(float)value1 to:(float)value2 atPoint:(NSPoint)point
{
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path setWindingRule:NSEvenOddWindingRule];
	[path moveToPoint:point];
	[path appendBezierPathWithArcWithCenter:point radius:value2 startAngle:0.0 endAngle:360.0];
	[path appendBezierPathWithArcWithCenter:point radius:value1 startAngle:0.0 endAngle:360.0];
	[path fill];
}

- (void)drawValue:(float)value atPoint:(NSPoint)point withFill:(BOOL)doFill
{
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path appendBezierPathWithArcWithCenter:point radius:value startAngle:0.0 endAngle:360.0];

	if (doFill)
	{
		[path fill];
	}
	else
	{
		[path stroke];
	}
}

- (void)drawValue:(float)value atPoint:(NSPoint)point
{
	[self drawValue:value atPoint:point withFill:YES];
}

- (void)drawArrowAtPoint:(NSPoint)point leftEdge:(NSPoint)leftPoint rightEdge:(NSPoint)rightPoint
{
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path moveToPoint:point];
	[path lineToPoint:leftPoint];
	[path lineToPoint:rightPoint];
	[path closePath];
	[path fill];
}

- (void)drawValueAngle:(float)value atPoint:(NSPoint)point startAngle:(float)start endAngle:(float)end withFill:(BOOL)doFill clockwise:(BOOL)doClockwise
{
	NSBezierPath *path = [NSBezierPath bezierPath];
	
	if (start < 0.0)
	{
		start += 360.0;
	}
	if (start > 360.0)
	{
		start -= 360.0;
	}
	if (end < 0.0)
	{
		end += 360.0;
	}
	if (end > 360.0)
	{
		end -= 360.0;
	}
	
	[path moveToPoint:point];
	if (doFill)
	{
		[path appendBezierPathWithArcWithCenter:point radius:value startAngle:start endAngle:end clockwise:doClockwise];
		[path fill];
	}
	else
	{
		[path setLineWidth:1.0];
		[path appendBezierPathWithArcWithCenter:point radius:value-1.0 startAngle:start endAngle:end clockwise:doClockwise];
		[path stroke];
	}
}

- (void)drawValueAngle:(float)value atPoint:(NSPoint)point startAngle:(float)start endAngle:(float)end withFill:(BOOL)doFill
{
	[self drawValueAngle:value atPoint:point startAngle:start endAngle:end withFill:doFill clockwise:NO];
}

- (void)drawValueAngleFrom:(float)value1 to:(float)value2 atPoint:(NSPoint)point startAngle:(float)start endAngle:(float)end clockwise:(BOOL)doClockwise
{
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path setWindingRule:NSEvenOddWindingRule];
	
	[path moveToPoint:point];
	[path appendBezierPathWithArcWithCenter:point radius:value2 startAngle:start endAngle:end clockwise:doClockwise];
	[path appendBezierPathWithArcWithCenter:point radius:value1 startAngle:end endAngle:start clockwise:!doClockwise];
		
	[path fill];
}

- (void)drawValueAngleRoundedFrom:(float)value1 to:(float)value2 atPoint:(NSPoint)point startAngle:(float)start endAngle:(float)end clockwise:(BOOL)doClockwise
{
	NSPoint valuePoint;
	float halfDelta = (value2 - value1) / 2.0;
	
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path appendBezierPathWithArcWithCenter:point radius:value2 startAngle:start endAngle:end clockwise:doClockwise];
	
	valuePoint.x = point.x + (dcos(end) * (value2 - halfDelta));
	valuePoint.y = point.y + (dsin(end) * (value2 - halfDelta));

	[path appendBezierPathWithArcWithCenter:valuePoint radius:halfDelta startAngle:end endAngle:(end - 180.0) clockwise:doClockwise];

	[path appendBezierPathWithArcWithCenter:point radius:value1 startAngle:end endAngle:start clockwise:!doClockwise];
	
	valuePoint.x = point.x + (dcos(start) * (value2 - halfDelta));
	valuePoint.y = point.y + (dsin(start) * (value2 - halfDelta));

	[path appendBezierPathWithArcWithCenter:valuePoint radius:halfDelta startAngle:(start + 180.0) endAngle:start clockwise:doClockwise];

	[path fill];
}

#pragma mark -

- (void)drawBarValue:(float)value atPosition:(float)position withForegroundColor:(NSColor *)foregroundColor withBackgroundColor:(NSColor *)backgroundColor withFill:(BOOL)doFill
{
		float scale = value / (100.0 / 6.0);
		float index = floor(scale);
		float fraction = scale - index;
		
		//NSLog(@"y = %6.2f, scale = %6.2f, index = %6.2f, fraction = %6.2f", y, scale, index, fraction);

		int x;
		const double sliceMinuteAngle = 360.0 / 60.0;

		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
		NSPoint timePoint;

		float startAngle = position + (10.0 * sliceMinuteAngle) - (0.0 * sliceMinuteAngle); 
		float endAngle = position + (10.0 * sliceMinuteAngle) - (5.0 * sliceMinuteAngle); 

		[backgroundColor set];
		[self drawValueAngleRoundedFrom:(GRAPH_SIZE/2.0) to:(GRAPH_SIZE/2.0 + GRAPH_SIZE/16.0) atPoint:processorPoint startAngle:startAngle endAngle:endAngle clockwise:YES];

		double radius = (GRAPH_SIZE/2.0) + (GRAPH_SIZE/32.0);
		
		float alphaComponent = [foregroundColor alphaComponent];

		for (x = 0; x < 6; x++)
		{
			float fadeAngle = position + (10.0 * sliceMinuteAngle) - (x * sliceMinuteAngle);

			timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];
			if (x < index)
			{
				// display a normal dot
				[foregroundColor set];
				[self drawValue:(GRAPH_SIZE / 48.0) atPoint:timePoint withFill:doFill];
			}
			else if (x < (index + 1.0))
			{
				// display a faded dot
				[[foregroundColor colorWithAlphaComponent:(alphaComponent *fraction)] set];
				[self drawValue:(GRAPH_SIZE / 48.0) atPoint:timePoint withFill:doFill];
			}
		}
}

#pragma mark -

#define STATUS_ITEM_PADDING 8.0

#define STATUS_BAR_SIZE 6.0
#define STATUS_BAR_RADIUS (STATUS_BAR_SIZE / 2.0)

#define STATUS_WIDTH 79.0
#define STATUS_HEIGHT 21.0

#define STATUS_BAR_DIVIDER 1.0
#define STATUS_BAR_SPACING 4.0

typedef enum
{
	upperLeftBar = 0,
	upperRightBar = 1,
	lowerLeftBar = 2,
	lowerRightBar = 3,
	lowerLeftDot = 4,
	lowerRightDot = 5,
	upperLeftDot = 6,
	upperRightDot = 7
} PositionType;

typedef enum
{
	upperBar = 0,
	lowerBar = 1,
	lowerDots = 2,
	upperDots = 3
} StatusType;

- (void)generateParametersFor:(StatusType)statusType leftColor:(NSColor **)leftColor rightColor:(NSColor **)rightColor alertColor:(NSColor **)alertColor leftPosition:(PositionType *)leftPosition rightPosition:(PositionType *)rightPosition fadeAll:(BOOL *)fadeAll
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	switch (statusType)
	{
	default:
	case upperBar:
		*leftColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY]];
		*rightColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY]];
		*alertColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY]];
		*leftPosition = upperLeftBar;
		*rightPosition = upperRightBar;
		*fadeAll = YES;
		break;
	case upperDots:
		*leftColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY]];
		*rightColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY]];
		*alertColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY]];
		*leftPosition = upperLeftDot;
		*rightPosition = upperRightDot;
		*fadeAll = NO;
		break;
	case lowerBar:
		*leftColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY]];
		*rightColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY]];
		*alertColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY]];
		*leftPosition = lowerLeftBar;
		*rightPosition = lowerRightBar;
		*fadeAll = YES;
		break;
	case lowerDots:
		*leftColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY]];
		*rightColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY]];
		*alertColor = [Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY]];
		*leftPosition = lowerLeftDot;
		*rightPosition = lowerRightDot;
		*fadeAll = NO;
		break;
	}
}

- (void)drawStatusBarValue:(float)value atPosition:(PositionType)position withColor:(NSColor *)color
{
	if (value > 0.0)
	{
		if (value > 1.0)
		{
			value = 1.0;
		}
		
		NSPoint point;	

		float leftOffset, rightOffset, bottomOffset;
		float drawWidth;
		BOOL flatLeft, flatRight;
		
		switch (position) {
		default:
		case upperLeftBar:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_SIZE + STATUS_BAR_DIVIDER + STATUS_BAR_RADIUS;
			
			leftOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
			drawWidth = (STATUS_WIDTH / 2.0) - (STATUS_BAR_SPACING * 2.0) - STATUS_BAR_RADIUS;
			rightOffset = leftOffset + (drawWidth * value);
			
			flatLeft = NO;
			flatRight = NO;
			break;
		case upperRightBar:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_SIZE + STATUS_BAR_DIVIDER + STATUS_BAR_RADIUS;

			rightOffset = STATUS_WIDTH - STATUS_BAR_SPACING - STATUS_BAR_RADIUS;
			drawWidth = (STATUS_WIDTH / 2.0) - (STATUS_BAR_SPACING * 2.0) - STATUS_BAR_RADIUS;
			leftOffset = rightOffset - (drawWidth * value);
			
			flatLeft = NO;
			flatRight = NO;
			break;
		case lowerLeftBar:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
				
			drawWidth = (STATUS_WIDTH / 2.0) - (STATUS_BAR_SPACING * 2.0);
			rightOffset = (STATUS_WIDTH / 2.0);
			leftOffset = rightOffset - (drawWidth * value);
			
			flatLeft = NO;
			flatRight = YES;
			break;
		case lowerRightBar:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
				
			drawWidth = (STATUS_WIDTH / 2.0) - (STATUS_BAR_SPACING * 2.0);
			leftOffset = (STATUS_WIDTH / 2.0);
			rightOffset = leftOffset + (drawWidth * value);
			
			flatLeft = YES;
			flatRight = NO;
			break;
		case lowerLeftDot:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
				
			leftOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
			rightOffset = leftOffset;
			
			flatLeft = NO;
			flatRight = NO;
			break;
		case lowerRightDot:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
				
			rightOffset = STATUS_WIDTH - STATUS_BAR_SPACING - STATUS_BAR_RADIUS;
			leftOffset = rightOffset;
			
			flatLeft = NO;
			flatRight = NO;
			break;
		case upperLeftDot:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_SIZE + STATUS_BAR_DIVIDER + STATUS_BAR_RADIUS;
				
			leftOffset = STATUS_BAR_SPACING + STATUS_BAR_RADIUS;
			rightOffset = leftOffset;
			
			flatLeft = NO;
			flatRight = NO;
			break;
		case upperRightDot:
			bottomOffset = STATUS_BAR_SPACING + STATUS_BAR_SIZE + STATUS_BAR_DIVIDER + STATUS_BAR_RADIUS;
				
			rightOffset = STATUS_WIDTH - STATUS_BAR_SPACING - STATUS_BAR_RADIUS;
			leftOffset = rightOffset;
			
			flatLeft = NO;
			flatRight = NO;
			break;
		}

		NSBezierPath *path = [NSBezierPath bezierPath];

		[path moveToPoint:NSMakePoint(leftOffset, bottomOffset + STATUS_BAR_RADIUS)];
		point = NSMakePoint(leftOffset, bottomOffset);
		if (flatLeft)
		{
			[path lineToPoint:NSMakePoint(leftOffset, bottomOffset - STATUS_BAR_RADIUS)];
		}
		else
		{
			[path appendBezierPathWithArcWithCenter:point radius:STATUS_BAR_RADIUS startAngle:90.0 endAngle:270.0 clockwise:NO];
		}
		[path lineToPoint:NSMakePoint(rightOffset, bottomOffset - STATUS_BAR_RADIUS)];		
		point = NSMakePoint(rightOffset, bottomOffset);
		if (flatRight)
		{
			[path lineToPoint:NSMakePoint(rightOffset, bottomOffset + STATUS_BAR_RADIUS)];
		}
		else
		{
			[path appendBezierPathWithArcWithCenter:point radius:STATUS_BAR_RADIUS startAngle:270.0 endAngle:90.0 clockwise:NO];
		}
		[path lineToPoint:NSMakePoint(leftOffset, bottomOffset + STATUS_BAR_RADIUS)];
		
		[color set];
		[path fill];
	
#if 0 // DEBUG
		{
			NSRect bounds;
			
			bounds = NSMakeRect(0.0, 0.0, STATUS_WIDTH, STATUS_HEIGHT);
			[[NSColor blackColor] set];
			NSFrameRect(bounds);

			NSBezierPath *halfPath = [NSBezierPath bezierPath];
			[halfPath moveToPoint:NSMakePoint(STATUS_WIDTH / 2.0, 0.0)];
			[halfPath lineToPoint:NSMakePoint(STATUS_WIDTH / 2.0, STATUS_HEIGHT)];	
			[[NSColor grayColor] set];
			[halfPath stroke];


			NSBezierPath *centerPath = [NSBezierPath bezierPath];
			[centerPath moveToPoint:NSMakePoint(leftOffset, bottomOffset)];
			[centerPath lineToPoint:NSMakePoint(rightOffset, bottomOffset)];
			[[NSColor blackColor] set];
			[centerPath stroke];
		}	
#endif

	}
}

- (void)drawStatusBackground
{
	// clear existing image
	[[[NSColor blackColor] colorWithAlphaComponent:0.0] set];
	NSSize size = [statusImage size];
	NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));

	[statusBackgroundImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

#pragma mark -

- (void)drawGaugeBackground
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	// draw background image
	{
		float fraction = [defaults floatForKey:OTHER_IMAGE_TRANSPARENCY_KEY];
		if (fraction > 0.0)
		{
			[backgroundImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
		}
	}
	
	// draw background color
	{
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);

		NSColor *backgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:OTHER_BACKGROUND_COLOR_KEY]];
		[backgroundColor set];

		[self drawValue:(GRAPH_SIZE/2.0) atPoint:processorPoint];
	}
}

- (void)drawGaugeGrid
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSColor *gridColor = [Preferences colorAlphaFromString:[defaults stringForKey:OTHER_MARKER_COLOR_KEY]];

	if (hasColor(gridColor))
	{
		int x;
		int numTicks;
		BOOL alternate;
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);	
	
		[gridColor set];
		
		// draw hour ticks (both 12 and 24 hour clocks)
		if (! [defaults boolForKey:TIME_USE_24_HOUR_KEY])
		{
			numTicks = 12;
			alternate = NO;
		}
		else
		{
			numTicks = 24;
			alternate = YES;
		}
		for (x = 0; x < numTicks; x++)
		{
			NSPoint innerPoint;
			NSPoint outerPoint;
			
			float gridAngle = 90 - (x * (360.0 / (float)numTicks));
			float offset;
	
			if (alternate)
			{
				if (x % 2 == 0)
				{
					offset = 0.0;
				}
				else
				{
					offset = GRAPH_SIZE/16.0;
				}
			}
			else
			{
				offset = 0.0;
			}
			innerPoint = [self pointAtCenter:processorPoint atAngle:gridAngle atRadius:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0)];
			outerPoint = [self pointAtCenter:processorPoint atAngle:gridAngle atRadius:(GRAPH_SIZE/2.0 - offset)];
			[self drawLineFrom:innerPoint to:outerPoint width:1.0];
		}
	
		// draw minute ticks
		for (x = 0; x < 60; x++)
		{
			NSPoint timePoint;
			
			float gridAngle = 90 - (x * (360.0 / 60.0));
	
			timePoint = [self pointAtCenter:processorPoint atAngle:gridAngle atRadius:(GRAPH_SIZE/2.0) - (GRAPH_SIZE/32.0)];
			[self drawValue:(GRAPH_SIZE / 96.0) atPoint:timePoint];
		}
	}
}

#pragma mark -

- (void)drawProcessorGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults boolForKey:PROCESSOR_SHOW_GAUGE_KEY])
	{
		NSColor *processorSystemColor = [Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_SYSTEM_COLOR_KEY]];
		NSColor *processorUserColor = [Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_USER_COLOR_KEY]];
		NSColor *processorNiceColor = [Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_NICE_COLOR_KEY]];

		int x;
		double y, yy;
		float systemTransparency, userTransparency, niceTransparency;
		CPUData cpudata;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		// draw  dynamic cpu data
		[processorInfo startIterate];
		for (x = 0; [processorInfo getNext:&cpudata]; x++) {
			double sliceAngle = 360.0 / (float) cpudata.processorCount;
			double currentAngle = 90.0;
	
			systemTransparency = (floor((float)(x + 1) / ((float)(SAMPLE_SIZE) / TRANSPARENCY_STEPS)) / TRANSPARENCY_STEPS) * [processorSystemColor alphaComponent];
			userTransparency = (floor((float)(x + 1) / ((float)(SAMPLE_SIZE) / TRANSPARENCY_STEPS)) / TRANSPARENCY_STEPS) * [processorUserColor alphaComponent];
			niceTransparency = (floor((float)(x + 1) / ((float)(SAMPLE_SIZE) / TRANSPARENCY_STEPS)) / TRANSPARENCY_STEPS) * [processorNiceColor alphaComponent];
	
			if (cpudata.processorCount == 1)
			{
				if (plotArea)
				{
					y = sqrt(cpudata.system[0]) * (GRAPH_SIZE/4.0);
				}
				else
				{
					y = (cpudata.system[0]) * (GRAPH_SIZE/4.0);
				}
				[[processorSystemColor colorWithAlphaComponent:systemTransparency] set];
				[self drawValue:y atPoint:processorPoint];
		
				yy = y;
				if (plotArea)
				{
					y = sqrt(cpudata.user[0] + cpudata.system[0]) * (GRAPH_SIZE/4.0);
				}
				else
				{
					y = (cpudata.user[0] + cpudata.system[0]) * (GRAPH_SIZE/4.0);
				}
				[[processorUserColor colorWithAlphaComponent:userTransparency] set];
				[self drawValueFrom:y to:yy atPoint:processorPoint];
				
				if (cpudata.nice[0] > 0.0)
				{
					yy = y;
					if (plotArea)
					{
						y = sqrt(cpudata.nice[0] + cpudata.user[0] + cpudata.system[0]) * (GRAPH_SIZE/4.0);
					}
					else
					{
						y = (cpudata.nice[0] + cpudata.user[0] + cpudata.system[0]) * (GRAPH_SIZE/4.0);
					}
					[[processorNiceColor colorWithAlphaComponent:niceTransparency] set];
					[self drawValueFrom:y to:yy atPoint:processorPoint];
				}
			}
			else
			{
				int i;
				
				for (i = 0; i < cpudata.processorCount; i++)
				{
					if (plotArea)
					{
						y = sqrt(cpudata.system[i]) * (GRAPH_SIZE/4.0);
					}
					else
					{
						y = (cpudata.system[i]) * (GRAPH_SIZE/4.0);
					}
					[[processorSystemColor colorWithAlphaComponent:systemTransparency] set];
					[self drawValueAngle:y atPoint:processorPoint startAngle:currentAngle endAngle:(currentAngle + sliceAngle) withFill:YES];
			
					yy = y;
					if (plotArea)
					{
						y = sqrt(cpudata.user[i] + cpudata.system[i]) * (GRAPH_SIZE/4.0);
					}
					else
					{
						y = (cpudata.user[i] + cpudata.system[i]) * (GRAPH_SIZE/4.0);
					}
					[[processorUserColor colorWithAlphaComponent:userTransparency] set];
					[self drawValueAngleFrom:y to:yy atPoint:processorPoint startAngle:currentAngle endAngle:(currentAngle + sliceAngle) clockwise:NO];
					
					if (cpudata.nice[i] > 0.0)
					{
						yy = y;
						if (plotArea)
						{
							y = sqrt(cpudata.nice[i] + cpudata.user[i] + cpudata.system[i]) * (GRAPH_SIZE/4.0);
						}
						else
						{
							y = (cpudata.nice[i] + cpudata.user[i] + cpudata.system[i]) * (GRAPH_SIZE/4.0);
						}
						[[processorNiceColor colorWithAlphaComponent:niceTransparency] set];
						[self drawValueAngleFrom:y to:yy atPoint:processorPoint startAngle:currentAngle endAngle:(currentAngle + sliceAngle) clockwise:NO];
					}

					currentAngle += sliceAngle;
				}
			}
		}
		
		// blend load color into CPU gauges
		{
			NSColor *loadColor = [Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_LOAD_COLOR_KEY]];
			float alphaComponent = [loadColor alphaComponent];
	
			// load statistics
			double currentLoad = 0.0;
			{
	
				host_load_info_data_t loadstat;
				mach_msg_type_number_t count = HOST_LOAD_INFO_COUNT;
		
				if (host_statistics(mach_host_self(), HOST_LOAD_INFO, (host_info_t) &loadstat, &count) == KERN_SUCCESS)
				{
					currentLoad = (double)loadstat.avenrun[2] / (double)LOAD_SCALE; // 15 minute load average
				}
			}
			float minLoad = [[defaults objectForKey:HISTORY_LOAD_MINIMUM_KEY] floatValue];;
			float maxLoad = [[defaults objectForKey:HISTORY_LOAD_MAXIMUM_KEY] floatValue];;
			
			float loadFraction = (currentLoad - minLoad) / (maxLoad - minLoad);
			if (loadFraction > 1.0)
			{
				loadFraction = 1.0;
			}
			if (loadFraction < 0.0)
			{
				loadFraction = 0.0;
			}

			[[loadColor colorWithAlphaComponent:(alphaComponent * loadFraction)] set];
			[self drawValue:(GRAPH_SIZE/4.0) atPoint:processorPoint];
		}
	}
}

- (void)drawProcessorText
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:PROCESSOR_SHOW_TEXT_KEY])
	{
		int x;
		
		double average[MAX_PROCESSORS];
		for (int i = 0; i < MAX_PROCESSORS; i++) {
			average[i] = 0.0;
		}

		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		CPUData cpudata;
		[processorInfo startIterate];
		for (x = 0; [processorInfo getNext:&cpudata]; x++) {
			for (int i = 0; i < cpudata.processorCount; i++) {
				if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY]) {
					average[i] = (average[i] + (cpudata.system[i] + cpudata.user[i] + cpudata.nice[i])) / 2.0;
				}
				else {
					average[i] = (average[i] + (cpudata.system[i] + cpudata.user[i])) / 2.0;
				}
			}
		}

		[processorInfo getCurrent:&cpudata];
		//NSLog(@"processorCount = %d", cpudata.processorCount);
		
		if (cpudata.processorCount == 1)
		{
			//NSLog(@"average[0] = %6.3f", average[0]);
			
			NSString *string = [NSString stringWithFormat:@"%.0f", average[0] * 100.0];
			[self drawText:string atPoint:processorPoint];
		}
		else
		{
			double sliceAngle = 360.0 / (float) cpudata.processorCount;
			double currentAngle = 90.0 + (sliceAngle / 2.0);
			
			for (x = 0; x < cpudata.processorCount; x++)
			{
				NSPoint drawPoint;
				
				//NSLog(@"average[%d] = %6.3f", x, average[0]);

				NSString *string = [NSString stringWithFormat:@"%.0f", average[x] * 100.0];

				drawPoint = [self pointAtCenter:processorPoint atAngle:currentAngle atRadius:(GRAPH_SIZE/8.0)];
				[self drawText:string atPoint:drawPoint];
				
				currentAngle += sliceAngle;
			}
		}		
	}
}

- (BOOL)inProcessorGauge:(GraphPoint)atPoint
{
	int result = 0;

	if (atPoint.radius < 0.5)
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		if ([defaults boolForKey:PROCESSOR_SHOW_GAUGE_KEY])
		{
			CPUData cpudata;
	
			[processorInfo getCurrent:&cpudata];
			//NSLog(@"processorCount = %d", cpudata.processorCount);
			
			if (cpudata.processorCount == 1)
			{
				result = 1;
			}
			else
			{
				float sliceAngle = 360.0 / (float) cpudata.processorCount;
				float currentAngle = 0.0;
				// adjust atAngle to top of CPU gauge (at 90 degrees)
				float atAngle = atPoint.angle - 90.0;
				if (atAngle < 0)
				{
					atAngle += 360.0;
				}
				
				int i;
				for (i = 0; i < cpudata.processorCount; i++)
				{
					// 2 CPUs:
					// currentAngle: 0 -> 180 = 1, 180 -> 360 = 2
					
					// 4 CPUs:
					// currentAngle: 0 -> 90 = 1, 90 -> 180 = 2, 180 -> 270 = 3, 270 -> 360 = 4
					
					float nextAngle = currentAngle + sliceAngle;
					
					if (atAngle >= currentAngle && atAngle < nextAngle)
					{
						result = i + 1;
						break;
					}

					currentAngle += sliceAngle;
				}
			}
		}
	}
	
	return (result);
}

NSInteger cpuSort(id process1, id process2, void *context)
{
	double cpu1 = [process1 percentCPUUsage];
	double cpu2 = [process2 percentCPUUsage];
	
	if (cpu1 == AGProcessValueUnknown)
	{
		cpu1 = -1.0;
	}
	if (cpu2 == AGProcessValueUnknown)
	{
		cpu2 = -1.0;
	}
	
	if (cpu1 < cpu2)
	{
		return NSOrderedDescending;
	}
	else if (cpu1 > cpu2)
	{
		return NSOrderedAscending;
	}
	else
	{
		return NSOrderedSame;
	}
}

int processListSort(const void *value1, const void *value2)
{
	struct processEntry *entry1 = (struct processEntry *)value1;
	struct processEntry *entry2 = (struct processEntry *)value2;

	if (entry1->average < entry2->average)
	{
		return (1);
	}
	else if (entry1->average > entry2->average)
	{
		return (-1);
	}
	else
	{	
		return (0);
	}
}

- (void)drawProcessorInfo:(GraphPoint)atPoint withIndex:(int)index
{
	if (atPoint.radius < 0.5)
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		CPUData cpudata;

		int x;

		double average[MAX_PROCESSORS];
		for (int i = 0; i < MAX_PROCESSORS; i++) {
			average[i] = 0.0;
		}

		NSString *marker = NSLocalizedString(@">", nil);
		NSString *blank = @"";
		
		// load attributed string and reformat
		if (! processorInfoString)
		{
			processorInfoString = [self attributedStringForFile:@"CPU.rtf"];
			[processorInfoString retain];
		}
		NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:processorInfoString] autorelease];

		[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

		NSMutableString *outputString = [output mutableString];
		
		[self replaceFormatting:output inString:outputString];

		
		[processorInfo getCurrent:&cpudata];
		[processorInfo startIterate];
		for (x = 0; [processorInfo getNext:&cpudata]; x++) {
			for (int i = 0; i < cpudata.processorCount; i++) {
				if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY]) {
					average[i] = (average[i] + (cpudata.system[i] + cpudata.user[i] + cpudata.nice[i])) / 2.0;
				}
				else {
					average[i] = (average[i] + (cpudata.system[i] + cpudata.user[i])) / 2.0;
				}
			}
		}

		[processorInfo getCurrent:&cpudata];

		int processorsDisplayed = 0;
		int i;
		NSMutableString *processorList = [NSMutableString stringWithString:@""];
		for (i = 0; i < cpudata.processorCount; i++)
		{
			float usage;
			if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY])
			{
				usage = cpudata.system[i] + cpudata.user[i] + cpudata.nice[i];
			}
			else
			{
				usage = cpudata.system[i] + cpudata.user[i];
			}

			NSString *indicator;
			if (index == i + 1)
			{
				indicator = marker;
			}
			else
			{
				indicator = blank;
			}

			if (usage > 0.01)
			{
				[processorList appendString:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@\t%@\t%@\n",
						indicator,
						[self stringForPercentage:average[i]],
						[self stringForPercentage:cpudata.system[i]],
						[self stringForPercentage:cpudata.user[i]],
						[self stringForPercentage:cpudata.nice[i]],
						[self stringForPercentage:cpudata.idle[i]],
						[self stringForPercentage:usage]]];
				processorsDisplayed += 1;
			}
		}
		[self replaceToken:@"[pl]" inString:outputString withString:processorList];
		[self highlightToken:marker ofAttributedString:output inString:outputString];

		// temperature statistics
		int temperaturesDisplayed = 0;
		{
			TemperatureData temperatureData;
			int numTemperatures;
		
			[temperatureInfo getCurrent:&temperatureData];
			numTemperatures = temperatureData.temperatureCount;
		
			if (numTemperatures > 0)
			{
				float temperatureCelsius;
				if (numTemperatures == 1)
				{
					temperatureCelsius = temperatureData.temperatureLevel[0];
				}
				else
				{
					temperatureCelsius = (temperatureData.temperatureLevel[0] + temperatureData.temperatureLevel[1]) / 2.0;
				}

				/* Tf = ((9/5)*Tc)+32 */
				float temperatureFahrenheit = ((9.0 / 5.0) * temperatureCelsius) + 32.0;
				float temperatureKelvin = temperatureCelsius + 273.15;

				[self replaceToken:@"[ct]" inString:outputString withString:[NSString stringWithFormat:@"\n%@:\t%.1f °C   %.1f °F   %.1f K\n", NSLocalizedString(@"Temperature", nil), temperatureCelsius,   temperatureFahrenheit, temperatureKelvin]];
				
				temperaturesDisplayed = 2; // two lines are displayed
			}
			else
			{
// For testing on Mac Pro without SMC temperature
#if 0
				[self replaceToken:@"[ct]" inString:outputString withString:[NSString stringWithFormat:@"\n%@:\t100 °C   200 °F   300 K\n", NSLocalizedString(@"Temperature", nil)]];
				temperaturesDisplayed = 2; // two lines are displayed
#else
				[self replaceToken:@"[ct]" inString:outputString withString:@""];
#endif
			}
		}

		// load statistics
		{
			int x;
			LoadData loaddata;
			
			double currentLoad = 0.0;
			double maxLoad = 0.0;
			double minLoad = 99999.0;
			double avgLoad = 0.0;	
			
			// get current load
			{
				host_load_info_data_t loadstat;
				mach_msg_type_number_t count = HOST_LOAD_INFO_COUNT;
		
				if (host_statistics(mach_host_self(), HOST_LOAD_INFO, (host_info_t) &loadstat, &count) == KERN_SUCCESS)
				{
					currentLoad = (double)loadstat.avenrun[0] / (double)LOAD_SCALE;
				}
			}

			[loadInfo startIterate];
			for (x = 0; [loadInfo getNext:&loaddata]; x++)
			{
				if (loaddata.average > maxLoad)
				{
					maxLoad = loaddata.average;
				}
				if (loaddata.average > 0.0)
				{
					if (loaddata.average < minLoad)
					{
						minLoad = loaddata.average;
					}
				}
				
				if (x == 0)
				{
					avgLoad = loaddata.average;
				}
				else
				{
					if (loaddata.average > 0.0)
					{
						avgLoad = (avgLoad + loaddata.average) / 2.0;
					}
				}
			}

			[self replaceToken:@"[lc]" inString:outputString withString:[NSString stringWithFormat:@"%.2f", currentLoad]];
			[self replaceToken:@"[lh]" inString:outputString withString:[NSString stringWithFormat:@"%.2f", maxLoad]];
			[self replaceToken:@"[ll]" inString:outputString withString:[NSString stringWithFormat:@"%.2f", minLoad]];
			[self replaceToken:@"[la]" inString:outputString withString:[NSString stringWithFormat:@"%.2f", avgLoad]];
		}
		
		NSMutableString *applicationList = [NSMutableString stringWithString:@""];
		{
			NSArray *processes = [self collectProcesses];
			
			// overall process statistics
			{
				int totalCount = 0;
				int unknownCount = 0;
				int runnableCount = 0;
				int sleepingCount = 0;
				int otherCount = 0;
				
				NSEnumerator *processEnumerator = [processes objectEnumerator];
				AGProcess *process;
				while (process = [processEnumerator nextObject])
				{
					totalCount++;
					
					int state = [process state];
					switch (state)
					{
					case AGProcessStateUnknown:
						unknownCount++;
						break;
					case AGProcessStateRunnable:
						runnableCount++;
						break;
					case AGProcessStateSleeping:
						sleepingCount++;
						break;
					default:
						otherCount++;
						break;
					}
				}

				[self replaceToken:@"[pt]" inString:outputString withString:[NSString stringWithFormat:@"%d", totalCount]];				
				[self replaceToken:@"[pr]" inString:outputString withString:[NSString stringWithFormat:@"%d", runnableCount]];				
				[self replaceToken:@"[ps]" inString:outputString withString:[NSString stringWithFormat:@"%d", sleepingCount]];				
				[self replaceToken:@"[po]" inString:outputString withString:[NSString stringWithFormat:@"%d", otherCount]];				
				[self replaceToken:@"[pu]" inString:outputString withString:[NSString stringWithFormat:@"%d", unknownCount]];				
			}
			
			NSArray *sortedProcesses = [processes sortedArrayUsingFunction:cpuSort context:NULL];
			
			// setup process list
			{
				int i;
				for (i = 0; i < PROCESS_LIST_SIZE; i++)
				{
					processList[i].isCurrent = NO;
				}
			}
			
			// add new processes to list
			BOOL checkPid = NO;
			if (! [defaults boolForKey:GLOBAL_SHOW_SELF_KEY])
			{
				checkPid = YES;
			}
			NSEnumerator *processEnumerator = [sortedProcesses objectEnumerator];
			int count = 0;
			BOOL done = NO;
			AGProcess *process;
			while (! done && (process = [processEnumerator nextObject]))
			{
				double cpu = [process percentCPUUsage];
				int pid = [process processIdentifier];

				BOOL pidOK = YES;
				if (checkPid)
				{
					if (pid == selfPid)
					{
						pidOK = NO;
					}
				}

				if (cpu != AGProcessValueUnknown && cpu > 0.0 && pid !=0 && pidOK)
				{
					BOOL found = NO;
					float minAverage = processList[9].average;
					int minIndex = 9;
					
					
					int i;
					for (i = 0; i < PROCESS_LIST_SIZE; i++)
					{
						if (processList[i].pid == pid)
						{
							processList[i].average = (processList[i].average + cpu) / 2.0;
							processList[i].current = cpu;
							processList[i].isCurrent = YES;
							found = YES;
							break;
						}
					}
					if (! found)
					{
						int i;
						for (i = 0; i < PROCESS_LIST_SIZE; i++)
						{
							if (processList[i].average < minAverage && !processList[i].isCurrent)
							{
								minAverage = processList[i].average;
								minIndex = i;
							}
						}
					
						processList[minIndex].pid = pid;
						processList[minIndex].average = cpu;
						processList[minIndex].current = cpu;
						processList[minIndex].isCurrent = YES;
					}
					
					count++;
					if (count == 10)
					{
						done = YES;
					}
				}
			}

			// update others in process list
			{
				int i;
				for (i = 0; i < PROCESS_LIST_SIZE; i++)
				{
					int pid = processList[i].pid;
					if (pid != 0 && ! processList[i].isCurrent)
					{
						AGProcess *updateProcess = [AGProcess processForProcessIdentifier:pid];
						if (updateProcess != nil)
						{
							double cpu = [updateProcess percentCPUUsage];
	
							if (cpu != AGProcessValueUnknown)
							{
								processList[i].average = (processList[i].average + cpu) / 2.0;
								processList[i].current = cpu;
								processList[i].isCurrent = YES;
							}
							else
							{
								// can't access process
								processList[i].pid = 0;
								processList[i].average = 0.0;
								processList[i].current = 0.0;
								processList[i].isCurrent = NO;
							}
						}
						else
						{
							// process disappeared
							processList[i].pid = 0;
							processList[i].average = 0.0;
							processList[i].current = 0.0;
							processList[i].isCurrent = NO;
						}
					}
				}
			}
			
			// sort process list
			{
				qsort(&processList[0], PROCESS_LIST_SIZE, sizeof(struct processEntry), processListSort);
			}
			
			// output process list
			{
				int processListDisplaySize = PROCESS_LIST_SIZE + 1 - (processorsDisplayed + temperaturesDisplayed);
				
				int i;
				for (i = 0; i < processListDisplaySize; i++)
				{
					int pid = processList[i].pid;
					
					if (pid != 0)
					{
						AGProcess *outputProcess = [AGProcess processForProcessIdentifier:pid];
						double cpu = processList[i].current;
						double avg = processList[i].average;
						
						[applicationList appendString:[NSString stringWithFormat:@"\t%@\t%@\t%d\t%@\n",
							[self stringForPercentage:avg], [self stringForPercentage:cpu], pid, [outputProcess annotatedCommand]]];
					}
				}
			}
		}
		[self replaceToken:@"[al]" inString:outputString withString:applicationList];

		{
			NSRect infoFrame = [infoView frame];
			float minX = NSMinX(infoFrame);
			float maxY = NSMaxY(infoFrame);
			float baseY = maxY - (INFO_OFFSET * 2.5);
	
			NSSize size = [output size];
			[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
		}
	}
}

- (void)drawProcessorStatusAt:(StatusType)statusType
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSColor *leftColor;
	NSColor *rightColor;
	NSColor *alertColor;
	PositionType leftPosition;
	PositionType rightPosition;
	BOOL fadeAll;	
	[self generateParametersFor:statusType leftColor:&leftColor rightColor:&rightColor alertColor:&alertColor leftPosition:&leftPosition rightPosition:&rightPosition fadeAll:&fadeAll];

	int x;
	double y1, y2;
	CPUData cpudata;

	float alphaLeft = [leftColor alphaComponent];
	float alphaRight = [rightColor alphaComponent];
	
	BOOL alert1 = NO;
	BOOL alert2 = NO;
	
	[processorInfo startIterate];
	for (x = 0; [processorInfo getNext:&cpudata]; x++)
	{
		float leftTransparency = (floor((float)(x + 1) / ((float)(SAMPLE_SIZE) / TRANSPARENCY_STEPS)) / TRANSPARENCY_STEPS) * alphaLeft;
		float rightTransparency = (floor((float)(x + 1) / ((float)(SAMPLE_SIZE) / TRANSPARENCY_STEPS)) / TRANSPARENCY_STEPS) * alphaRight;

		if (cpudata.processorCount == 1)
		{
			if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY])
			{
				y1 = (cpudata.system[0] + cpudata.user[0] + cpudata.nice[0]);
				y2 = y1;
			}
			else
			{
				y1 = (cpudata.system[0] + cpudata.user[0] + cpudata.nice[0]);
				y2 = y1;
			}
		}
		else
		{
			if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY])
			{
				if (cpudata.processorCount == 4)
				{
					y1 = ((cpudata.system[0] + cpudata.user[0] + cpudata.nice[0]) +
						(cpudata.system[1] + cpudata.user[1] + cpudata.nice[1])) / 2.0;
					y2 = ((cpudata.system[2] + cpudata.user[2] + cpudata.nice[2]) +
						(cpudata.system[3] + cpudata.user[3] + cpudata.nice[3])) / 2.0;
				}
				else
				{
					y1 = (cpudata.system[0] + cpudata.user[0] + cpudata.nice[0]);
					y2 = (cpudata.system[1] + cpudata.user[1] + cpudata.nice[1]);
				}
			}
			else
			{
				if (cpudata.processorCount == 4)
				{
					y1 = ((cpudata.system[0] + cpudata.user[0]) +
						(cpudata.system[1] + cpudata.user[1])) / 2.0;
					y2 = ((cpudata.system[2] + cpudata.user[2]) +
						(cpudata.system[3] + cpudata.user[3])) / 2.0;
				}
				else
				{
					y1 = (cpudata.system[0] + cpudata.user[0]);
					y2 = (cpudata.system[1] + cpudata.user[1]);
				}
			}
		}

		if (x == (SAMPLE_SIZE - 1) && y1 >= statusAlertThreshold)
		{
			alert1 = YES;
		}
		if (x == (SAMPLE_SIZE - 1) && y2 >= statusAlertThreshold)
		{
			alert2 = YES;
		}

		[self drawStatusBarValue:y1 atPosition:leftPosition withColor:[leftColor colorWithAlphaComponent:leftTransparency]];
		[self drawStatusBarValue:y2 atPosition:rightPosition withColor:[rightColor colorWithAlphaComponent:rightTransparency]];
	}
	if (alert1)
	{
		[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
	}
	if (alert2)
	{
		[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
	}
}

#pragma mark -

- (void)drawMobilityGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	BatteryData batteryData;
	[powerInfo getCurrent:&batteryData];

	if (batteryData.batteryPresent && [defaults boolForKey:MOBILITY_BATTERY_SHOW_GAUGE_KEY])
	{
		NSColor *batteryNormalColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_COLOR_KEY]];
		NSColor *batteryChargeColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_CHARGE_COLOR_KEY]];	
		NSColor *batteryFullColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_FULL_COLOR_KEY]];	
	
		NSColor *mobilityBackgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BACKGROUND_COLOR_KEY]];
		NSColor *mobilityWarningColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_WARNING_COLOR_KEY]];
		
		if (! batteryData.batteryChargerConnected)
		{
			if (batteryData.batteryLevel <= 0.10)
			{
				// low battery warning
				[self drawBarValue:(batteryData.batteryLevel * 100.0) atPosition:0.0 withForegroundColor:batteryNormalColor withBackgroundColor:mobilityWarningColor withFill:YES];
			}
			else
			{
				// normal battery level
				[self drawBarValue:(batteryData.batteryLevel * 100.0) atPosition:0.0 withForegroundColor:batteryNormalColor withBackgroundColor:mobilityBackgroundColor withFill:YES];
			}
		}
		else
		{
			if (batteryData.batteryCharging)
			{
				// battery charging
				[self drawBarValue:(batteryData.batteryLevel * 100.0) atPosition:0.0 withForegroundColor:batteryChargeColor withBackgroundColor:mobilityBackgroundColor withFill:YES];
			}
			else
			{
				//battery fully charged
				[self drawBarValue:(batteryData.batteryLevel * 100.0) atPosition:0.0 withForegroundColor:batteryFullColor withBackgroundColor:mobilityBackgroundColor withFill:YES];
			}
		}
	}

	WirelessData wirelessData;
	[airportInfo getCurrent:&wirelessData];

	if (wirelessData.wirelessAvailable && wirelessData.wirelessClientMode == 1 &&
			[defaults boolForKey:MOBILITY_WIRELESS_SHOW_GAUGE_KEY])
	{
		NSColor *wirelessNormalColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_WIRELESS_COLOR_KEY]];
	
		NSColor *mobilityBackgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BACKGROUND_COLOR_KEY]];
		NSColor *mobilityWarningColor = [Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_WARNING_COLOR_KEY]];

		int x;
		float wirelessLevel = 0.0;

		[airportInfo startIterate];
		for (x = 0; [airportInfo getNext:&wirelessData]; x++) 
		{
			if (x == 0)
			{
				wirelessLevel = wirelessData.wirelessLevel;
			}
			else
			{
				wirelessLevel = (wirelessLevel + wirelessData.wirelessLevel) / 2.0;
			}
		}

		if (wirelessData.wirelessHasPower) 
		{
			if (wirelessLevel <= 0.10)
			{
				[self drawBarValue:(wirelessLevel * 100.0) atPosition:180.0 withForegroundColor:wirelessNormalColor withBackgroundColor:mobilityWarningColor withFill:YES];
			}
			else
			{
				[self drawBarValue:(wirelessLevel * 100.0) atPosition:180.0 withForegroundColor:wirelessNormalColor withBackgroundColor:mobilityBackgroundColor withFill:YES];
			}

		}
	}
}

- (int)inMobilityGauge:(GraphPoint)atPoint
{
	int result = 0;

	if (atPoint.radius >= 1.0)
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		BatteryData batteryData;
		[powerInfo getCurrent:&batteryData];

		if (batteryData.batteryPresent &&[defaults boolForKey:MOBILITY_BATTERY_SHOW_GAUGE_KEY])
		{
			if (atPoint.angle >= 0.0 && atPoint.angle < 90.0)
			{
				result = 1; // in battery gauge
			}
		}
		
		WirelessData wirelessData;
		[airportInfo getCurrent:&wirelessData];

		if (wirelessData.wirelessAvailable && [defaults boolForKey:MOBILITY_WIRELESS_SHOW_GAUGE_KEY])
		{
			if (atPoint.angle >= 180.0 && atPoint.angle < 270.0)
			{
				result = 2; // in wireless gauge
			}
		}
	}

	return (result);
}

- (void)drawMobilityInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSString *marker = NSLocalizedString(@">", nil);
	NSString *blank = @"";

	if (! mobilityInfoString)
	{
		mobilityInfoString = [self attributedStringForFile:@"Mobility.rtf"];
		[mobilityInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:mobilityInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];
	
	[self replaceFormatting:output inString:outputString];

	if (index == 1)
	{
		// in battery
		[self highlightToken:@"[mb]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mb]" inString:outputString withString:marker];
		[self replaceToken:@"[mw]" inString:outputString withString:blank];
	}
	else
	{
		// in wireless
		[self highlightToken:@"[mw]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mb]" inString:outputString withString:blank];
		[self replaceToken:@"[mw]" inString:outputString withString:marker];
	}

	{
		BatteryData batteryData;
		[powerInfo getCurrent:&batteryData];

		if (batteryData.batteryPresent)
		{
			[self replaceToken:@"[bl]" inString:outputString withString:[NSString stringWithFormat:@"%.1f%%", batteryData.batteryLevel * 100.0]];

			BOOL powerSourcePresent = NO;
			int minutes = 0;
			BOOL minutesIsValid = NO;
				
			if (majorVersion == 10 && minorVersion >= 2)
			{
				/*
				Returns a blob of Power Source information in an opaque CFTypeRef. Clients should
				not actually look directly at data in the CFTypeRef - they should use the accessor
				functions IOPSCopyPowerSourcesList and IOPSGetPowerSourceDescription, instead.
				Returns NULL if errors were encountered.
				Return: Caller must CFRelease() the return value when done.
				*/
				CFTypeRef powerSourcesInfo = IOPSCopyPowerSourcesInfo();

				//NSLog(@"powerSourcesInfo = 0x%x", powerSourcesInfo);

				/*
				Arguments - Takes the CFTypeRef returned by IOPSCopyPowerSourcesInfo()
				Returns a CFArray of Power Source handles, each of type CFTypeRef.
				The caller shouldn't look directly at the CFTypeRefs, but should use
				IOPSGetPowerSourceDescription on each member of the CFArrayRef.
				Returns NULL if errors were encountered.
				Return: Caller must CFRelease() the returned CFArrayRef.
				*/
				CFArrayRef powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo);
	
				if (powerSources)
				{
					CFIndex count = CFArrayGetCount(powerSources);
					//NSLog(@"powerSources count = %d", count);
		
					CFIndex index;
					for (index = 0; index < count; index++)
					{
						//NSLog(@"powerSource %d", index);
					
						/*
						Arguments -
						1) The CFTypeRef returned by IOPSCopyPowerSourcesInfo
						2) One of the CFTypeRefs in the CFArray returned by IOPSCopyPowerSourcesList
						
						Returns a CFDictionary with specific information about the power source.
						See IOPSKeys.h for keys and the meaning of specific fields.
						Return: Caller should NOT CFRelease() the returned CFDictionaryRef
						*/
						CFDictionaryRef powerSource = IOPSGetPowerSourceDescription(powerSourcesInfo, CFArrayGetValueAtIndex(powerSources, index));
						if (powerSource)
						{							
							CFStringRef transportType = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTransportTypeKey));
							if (transportType && CFEqual(transportType, CFSTR(kIOPSInternalType)))
							{
								// battery power source is present
								powerSourcePresent = YES;

								//NSLog(@"powerSource kIOPSInternalType present");
								
								CFBooleanRef isCharging = CFDictionaryGetValue(powerSource, CFSTR(kIOPSIsChargingKey));
								if (isCharging)
								{
									int temp;
								
									//NSLog(@"powerSource check charging");

									if (CFBooleanGetValue(isCharging))
									{
										// power source is charging
										//NSLog(@"powerSource charging");
										CFNumberRef timeToFull = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTimeToFullChargeKey));
										CFNumberGetValue(timeToFull, kCFNumberIntType, &temp);
										if (temp != -1)
										{
											minutes += temp;
											minutesIsValid = YES;
										}
									}
									else
									{
										// power source is not charging
										//NSLog(@"powerSource not charging");
										CFNumberRef timeToEmpty = CFDictionaryGetValue(powerSource, CFSTR(kIOPSTimeToEmptyKey));
										CFNumberGetValue(timeToEmpty, kCFNumberIntType, &temp);
										if (temp != -1)
										{
											minutes += temp;
											minutesIsValid = YES;
										}
									}
								}
							}
						}
					}

					CFRelease(powerSources);
				}
				
				CFRelease(powerSourcesInfo);
			}

			if (! batteryData.batteryChargerConnected)
			{
				// battery in use
				[self replaceToken:@"[bs]" inString:outputString withString:NSLocalizedString(@"InUse", nil)];

				if (powerSourcePresent)
				{
					if (minutesIsValid)
					{
						double remainingHours = (double) minutes / 60.0;
						double remainingMinutes = 60.0 * (remainingHours - floor(remainingHours));

						[self replaceToken:@"[br]" inString:outputString withString:[NSString stringWithFormat:@"%.0f:%02.0f",
							floor(remainingHours), remainingMinutes]];
					}
					else
					{
						// not enough data to display
						[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"Calculating", nil)];
					}
				}
				else
				{
					[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
				}
			}
			else
			{
				if (batteryData.batteryCharging)
				{
					// battery charging
					[self replaceToken:@"[bs]" inString:outputString withString:NSLocalizedString(@"Charging", nil)];

					if (powerSourcePresent)
					{
						if (minutesIsValid)
						{
							double remainingHours = (double) minutes / 60.0;
							double remainingMinutes = 60.0 * (remainingHours - floor(remainingHours));
	
							[self replaceToken:@"[br]" inString:outputString withString:[NSString stringWithFormat:@"%.0f:%02.0f",
								floor(remainingHours), remainingMinutes]];
						}
						else
						{
							// not enough data to display
							[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"Calculating", nil)];
						}
					}
					else
					{
						[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
					}
				}
				else
				{
					//battery fully charged
					[self replaceToken:@"[bs]" inString:outputString withString:NSLocalizedString(@"Full", nil)];
					[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"Dash", nil)];
				}
			}
			[self replaceToken:@"[ba]" inString:outputString withString:[NSString stringWithFormat:@"%d", batteryData.batteryAmperage]];
			[self replaceToken:@"[bv]" inString:outputString withString:[NSString stringWithFormat:@"%.3f", ((float)batteryData.batteryVoltage / 1000.0)]];
		}
		else
		{
			[self replaceToken:@"[bl]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
			[self replaceToken:@"[bs]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
			[self replaceToken:@"[ba]" inString:outputString withString:NSLocalizedString(@"Dash", nil)];
			[self replaceToken:@"[bv]" inString:outputString withString:NSLocalizedString(@"Dash", nil)];
			[self replaceToken:@"[br]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
		}
	}
	
	{
		WirelessData wirelessData;
		[airportInfo getCurrent:&wirelessData];
		
		if (wirelessData.wirelessAvailable)
		{
			int x;
			float wirelessLevel = 0.0;

			if (wirelessData.wirelessHasPower)
			{
				[self replaceToken:@"[wp]" inString:outputString withString:NSLocalizedString(@"Yes", nil)];

				switch (wirelessData.wirelessClientMode)
				{
					case 1:
						[self replaceToken:@"[wm]" inString:outputString withString:NSLocalizedString(@"NetworkClient", nil)];
						break;
					case 2:
						[self replaceToken:@"[wm]" inString:outputString withString:NSLocalizedString(@"SoftwareBaseStation", nil)];
						break;
					case 4:
						[self replaceToken:@"[wm]" inString:outputString withString:NSLocalizedString(@"ComputerToComputer", nil)];
						break;
					default:
						[self replaceToken:@"[wm]" inString:outputString withString:NSLocalizedString(@"Unknown", nil)];
						break;
				}

				[self replaceToken:@"[wa]" inString:outputString withString:[NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
					wirelessData.wirelessMacAddress[0], wirelessData.wirelessMacAddress[1],
					wirelessData.wirelessMacAddress[2], wirelessData.wirelessMacAddress[3],
					wirelessData.wirelessMacAddress[4], wirelessData.wirelessMacAddress[5]]];
				[self replaceToken:@"[wn]" inString:outputString withString:[NSString stringWithFormat:@"%s", wirelessData.wirelessName]];
			}
			else
			{
				[self replaceToken:@"[wp]" inString:outputString withString:NSLocalizedString(@"No", nil)];

				[self replaceToken:@"[wm]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];

				[self replaceToken:@"[wa]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
				[self replaceToken:@"[wn]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
			}
			
			
			if (wirelessData.wirelessSignal > 0 && wirelessData.wirelessNoise > 0)
			{
				// before Airport 3.4.1 update
				int signal = wirelessData.wirelessSignal;
				int noise = wirelessData.wirelessNoise;

				float signalToNoise = (float)signal / (float)noise;
				[self replaceToken:@"[ws]" inString:outputString withString:[NSString stringWithFormat:@"%d/%d = %.2f",
						signal, noise, signalToNoise]];
			}
			else
			{
				// after Airport 3.4.1 update
				int signal = wirelessData.wirelessSignal;
				int noise = wirelessData.wirelessNoise;

				int signalToNoise = signal - noise;
				[self replaceToken:@"[ws]" inString:outputString withString:[NSString stringWithFormat:@"%d%@%d %@ = %d %@",
						signal, NSLocalizedString(@"Ratio", nil), noise, NSLocalizedString(@"DecibelPerMilliwatt", nil), signalToNoise, NSLocalizedString(@"Decibel", nil)]];
			}

			[airportInfo startIterate];
			for (x = 0; [airportInfo getNext:&wirelessData]; x++) 
			{
				if (x == 0)
				{
					wirelessLevel = wirelessData.wirelessLevel;
				}
				else
				{
					wirelessLevel = (wirelessLevel + wirelessData.wirelessLevel) / 2.0;
				}
			}
			[self replaceToken:@"[wl]" inString:outputString withString:[NSString stringWithFormat:@"%.1f%%", wirelessLevel * 100.0]];
		}
		else
		{
			[self replaceToken:@"[wp]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
			[self replaceToken:@"[wa]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
			[self replaceToken:@"[wn]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];

			[self replaceToken:@"[ws]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];

			[self replaceToken:@"[wl]" inString:outputString withString:NSLocalizedString(@"NotAvailableAbbr", nil)];
		}
	}
	

	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

#pragma mark -

- (void)drawHistoryGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:HISTORY_SHOW_GAUGE_KEY])
	{
		int x;
		LoadData loaddata;

		struct tm *nowTime = localtime(&now);
		const double sliceMinuteAngle = 360.0 / 60.0;
		double minuteAngle = 90.0 - ((double)nowTime->tm_min * sliceMinuteAngle);
	
		double radius = (GRAPH_SIZE/2.0) - (GRAPH_SIZE/32.0);
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
		NSPoint timePoint;
	
		NSColor *loadColor = [Preferences colorAlphaFromString:[defaults stringForKey:HISTORY_LOAD_COLOR_KEY]];
		
		// draw load data
		float minLoad = [[defaults objectForKey:HISTORY_LOAD_MINIMUM_KEY] floatValue];;
		float maxLoad = [[defaults objectForKey:HISTORY_LOAD_MAXIMUM_KEY] floatValue];;

		[loadInfo startIterate];
		for (x = 1; [loadInfo getNext:&loaddata]; x++)
		{
			float fadeAngle = minuteAngle - (x * sliceMinuteAngle);
			float loadFraction = (loaddata.average - minLoad) / (maxLoad - minLoad);
			//NSLog(@"minLoad = %6.2f, maxLoad = %6.2f, sample = %6.2f loadFraction = %6.2f", minLoad, maxLoad, loaddata.average, loadFraction);

			if (loadFraction > 1.0)
			{
				loadFraction = 1.0;
			}
			if (loadFraction < 0.0)
			{
				loadFraction = 0.0;
			}

			timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];
	
			if (x < 60)
			{
				// display a normal load dot
				[[loadColor colorWithAlphaComponent:loadFraction] set];
				[self drawValue:(GRAPH_SIZE / 48.0) atPoint:timePoint];
			}
			else
			{
				// display a marker for last minute (next one to be filled in)
				[loadColor set];
				{
					NSBezierPath *path = [NSBezierPath bezierPath];
				
					[path appendBezierPathWithArcWithCenter:timePoint radius:(GRAPH_SIZE / 48.0) startAngle:0.0 endAngle:360.0];
					[path stroke];
				}
			}
		}
	}
}

#pragma mark -

- (void)drawMemoryGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:MEMORY_SHOW_GAUGE_KEY])
	{
		NSColor *memorySystemActiveColor = [Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SYSTEMACTIVE_COLOR_KEY]];
		NSColor *memoryInactiveFreeColor = [Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_INACTIVEFREE_COLOR_KEY]];

		float splitAngle;
		float endAngle;
		VMData vmdata;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
		
		// draw  static memory data
		[memoryInfo getCurrent:&vmdata];
		{
			splitAngle = 180.0 - ((vmdata.wired + vmdata.active) * 180.0);

			// draw free
			[memoryInactiveFreeColor set];
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:splitAngle endAngle:0.0 clockwise:YES];

			// draw inactive
			endAngle = splitAngle - (vmdata.inactive * 180.0);
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:splitAngle endAngle:endAngle clockwise:YES];

			// draw active
			[memorySystemActiveColor set];
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:180.0 endAngle:splitAngle clockwise:YES];

			// draw wired
			endAngle = 180.0 - (vmdata.wired * 180.0);
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:180.0 endAngle:endAngle clockwise:YES];
		}
	}
}

- (void)drawMemoryText
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults boolForKey:MEMORY_SHOW_TEXT_KEY])
	{
		NSPoint memoryPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE-(GRAPH_SIZE/4.0)+(GRAPH_SIZE/16.0));
	
		VMData vmdata;	
		[memoryInfo getCurrent:&vmdata];
	
		NSString *string = [NSString stringWithFormat:@"%.0f", (vmdata.wired + vmdata.active) * 100.0];
		[self drawText:string atPoint:memoryPoint];
	}		
}

- (BOOL)inMemoryGauge:(GraphPoint)atPoint
{
	int result = 0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:MEMORY_SHOW_GAUGE_KEY])
	{
		if (atPoint.radius > 0.5 && atPoint.radius < 0.75)
		{
			VMData vmdata;
			float freeAngle;
			float inactiveAngle;
			float activeAngle;
	
			[memoryInfo getCurrent:&vmdata];
	
			freeAngle = vmdata.free * 180.0;
			inactiveAngle = freeAngle + (vmdata.inactive * 180.0);
			activeAngle = inactiveAngle + (vmdata.active * 180.0);
	
			//NSLog(@"angle = %.1f, freeAngle = %.1f, inactiveAngle = %.1f, activeAngle = %.1f", angle, freeAngle, inactiveAngle, activeAngle);
	
			if (atPoint.angle <= freeAngle && atPoint.angle > 0.0)
			{
				// free memory
				result = 1;
			}
			else if (atPoint.angle <= inactiveAngle && atPoint.angle > freeAngle)
			{
				// inactive memory
				result = 2;
			}
			else if (atPoint.angle <= activeAngle && atPoint.angle > inactiveAngle)
			{
				// active memory
				result = 3;
			}
			else if (atPoint.angle <= 180.0)
			{
				// wired memory
				result = 4;
			}
		}
	}

	return (result);
}

NSInteger memorySort(id process1, id process2, void *context)
{
	vm_size_t mem1 = [process1 residentMemorySize];
	vm_size_t mem2 = [process2 residentMemorySize];
	
	if (mem1 == AGProcessValueUnknown)
	{
		mem1 = 0;
	}
	if (mem2 == AGProcessValueUnknown)
	{
		mem2 = 0;
	}
	
	if (mem1 < mem2)
	{
		return NSOrderedDescending;
	}
	else if (mem1 > mem2)
	{
		return NSOrderedAscending;
	}
	else
	{
		return NSOrderedSame;
	}
}

- (void)drawMemoryInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	VMData vmdata;

	NSString *marker = NSLocalizedString(@">", nil);
	NSString *blank = @"";
	
	if (! memoryInfoString)
	{
		memoryInfoString = [self attributedStringForFile:@"Memory.rtf"];
		[memoryInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:memoryInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];

	[self replaceFormatting:output inString:outputString];
	
	[memoryInfo getCurrent:&vmdata];

	switch (index)
	{
	case 1: // free
		[self highlightToken:@"[mf]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mf]" inString:outputString withString:marker];
		[self replaceToken:@"[mi]" inString:outputString withString:blank];
		[self replaceToken:@"[ma]" inString:outputString withString:blank];
		[self replaceToken:@"[mw]" inString:outputString withString:blank];
		break;
	case 2: // inactive
		[self highlightToken:@"[mi]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mf]" inString:outputString withString:blank];
		[self replaceToken:@"[mi]" inString:outputString withString:marker];
		[self replaceToken:@"[ma]" inString:outputString withString:blank];
		[self replaceToken:@"[mw]" inString:outputString withString:blank];
		break;
	case 3: // active
		[self highlightToken:@"[ma]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mf]" inString:outputString withString:blank];
		[self replaceToken:@"[mi]" inString:outputString withString:blank];
		[self replaceToken:@"[ma]" inString:outputString withString:marker];
		[self replaceToken:@"[mw]" inString:outputString withString:blank];
		break;
	case 4: // wired
		[self highlightToken:@"[mw]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[mf]" inString:outputString withString:blank];
		[self replaceToken:@"[mi]" inString:outputString withString:blank];
		[self replaceToken:@"[ma]" inString:outputString withString:blank];
		[self replaceToken:@"[mw]" inString:outputString withString:marker];
		break;
	}

	[self replaceToken:@"[mwb]" inString:outputString withString:[self stringForValue:(vmdata.wiredCount * 4096.0) withBytes:YES]];
	[self replaceToken:@"[mwp]" inString:outputString withString:[self stringForPercentage:vmdata.wired withPercent:NO]];

	[self replaceToken:@"[mab]" inString:outputString withString:[self stringForValue:(vmdata.activeCount * 4096.0) withBytes:YES]];
	[self replaceToken:@"[map]" inString:outputString withString:[self stringForPercentage:vmdata.active withPercent:NO]];

	[self replaceToken:@"[mib]" inString:outputString withString:[self stringForValue:(vmdata.inactiveCount * 4096.0) withBytes:YES]];
	[self replaceToken:@"[mip]" inString:outputString withString:[self stringForPercentage:vmdata.inactive withPercent:NO]];

	[self replaceToken:@"[mfb]" inString:outputString withString:[self stringForValue:(vmdata.freeCount * 4096.0) withBytes:YES]];
	[self replaceToken:@"[mfp]" inString:outputString withString:[self stringForPercentage:vmdata.free withPercent:NO]];

	[self replaceToken:@"[mub]" inString:outputString withString:[self stringForValue:((vmdata.activeCount + vmdata.wiredCount) * 4096.0) withBytes:YES]];
	[self replaceToken:@"[mup]" inString:outputString withString:[self stringForPercentage:(vmdata.active + vmdata.wired) withPercent:NO]];

	[self replaceToken:@"[mxb]" inString:outputString withString:[self stringForValue:((vmdata.freeCount + vmdata.inactiveCount) * 4096.0) withBytes:YES]];
	[self replaceToken:@"[mxp]" inString:outputString withString:[self stringForPercentage:(vmdata.free + vmdata.inactive) withPercent:NO]];


	NSMutableString *memoryList = [NSMutableString stringWithString:@""];
	{
		NSArray *processes = [self collectProcesses];

		NSArray *sortedProcesses = [processes sortedArrayUsingFunction:memorySort context:NULL];
		
		BOOL checkPid = NO;
		if (! [defaults boolForKey:GLOBAL_SHOW_SELF_KEY])
		{
			checkPid = YES;
		}
		NSEnumerator *processEnumerator = [sortedProcesses objectEnumerator];
		int count = 0;
		BOOL done = NO;
		AGProcess *process;
		while (! done && (process = [processEnumerator nextObject]))
		{
			double memoryUsage = [process percentMemoryUsage];
			int pid = [process processIdentifier];

			BOOL pidOK = YES;
			if (checkPid)
			{
				if (pid == selfPid)
				{
					pidOK = NO;
				}
			}

			if (memoryUsage != AGProcessValueUnknown && memoryUsage > 0.0 && pidOK)
			{
				float virtualSize = (float)[process virtualMemorySize];
				float residentSize = (float)[process residentMemorySize];

				[memoryList appendString:[NSString stringWithFormat:@"\t%@\t%@\t%@\t%@\n", [self stringForValue:residentSize withBytes:YES], [self stringForPercentage:memoryUsage withPercent:NO], [self stringForValue:virtualSize withBytes:YES], [process annotatedCommand]]];

				count++;
				if (count == 10)
				{
					done = YES;
				}
			}
		}
	}
	[self replaceToken:@"[ml]" inString:outputString withString:memoryList];
	
	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

#pragma mark -

- (void)drawSwappingGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:MEMORY_SWAPPING_SHOW_GAUGE_KEY])
	{
		NSColor *memoryInColor = [Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SWAPPING_IN_COLOR_KEY]];
		NSColor *memoryOutColor = [Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SWAPPING_OUT_COLOR_KEY]];
	
		int x;
		float y;
		VMData vmdata;
		
		float alphaIn = [memoryInColor alphaComponent];
		float transparencyIn;
		float alphaOut = [memoryOutColor alphaComponent];
		float transparencyOut;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		// draw  dynamic memory data
		[memoryInfo startIterate];
		for (x = 0; [memoryInfo getNext:&vmdata]; x++)
		{
			float endAngle;

			transparencyIn = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaIn;
	
			y = vmdata.pageins * 1.0;
			[[memoryInColor colorWithAlphaComponent:transparencyIn] set];
	
			endAngle = (180 - y);
			if (endAngle < 90.0)
			{
				endAngle = 90.0;
			}
			[self drawValueAngleFrom:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0) to:(GRAPH_SIZE/2.0) atPoint:processorPoint startAngle:180.0 endAngle:endAngle clockwise:YES];
			
			transparencyOut = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaOut;

			y = vmdata.pageouts * 1.0;
			[[memoryOutColor colorWithAlphaComponent:transparencyOut] set];
	
			endAngle = (0.0 + y);
			if (endAngle > 90.0)
			{
				endAngle = 90.0;
			}
			[self drawValueAngleFrom:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0) to:(GRAPH_SIZE/2.0) atPoint:processorPoint startAngle:0.0 endAngle:endAngle clockwise:NO];
		}
	}
}

- (void)drawSwappingText
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	if ([defaults boolForKey:MEMORY_SWAPPING_SHOW_TEXT_KEY])
	{
		NSPoint memoryInPoint = NSMakePoint(0.0 + (GRAPH_SIZE/16.0), (GRAPH_SIZE/2.0) + (GRAPH_SIZE/16.0));
		NSPoint memoryOutPoint = NSMakePoint(GRAPH_SIZE - (GRAPH_SIZE/16.0), (GRAPH_SIZE/2.0) + (GRAPH_SIZE/16.0));

		VMData vmdata;	
		[memoryInfo getCurrent:&vmdata];
		 
		if (vmdata.pageins > 0)
		{
			NSString *string;
			if (vmdata.pageins > 99)
			{
				string = @"+";
			}
			else
			{
				string = [NSString stringWithFormat:@"%d", (vmdata.pageins)];
			}
			[self drawText:string atPoint:memoryInPoint];
		}
		
		if (vmdata.pageouts > 0)
		{
			NSString *string;
			if (vmdata.pageouts > 99)
			{
				string = @"+";
			}
			else
			{
				string = [NSString stringWithFormat:@"%d", (vmdata.pageouts)];
			}

			[self drawText:string atPoint:memoryOutPoint];
		}
	}
}

- (BOOL)inSwappingGauge:(GraphPoint)atPoint
{
	int result = 0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:MEMORY_SWAPPING_SHOW_GAUGE_KEY])
	{
		if (atPoint.radius > 0.75 && atPoint.radius < 1.0)
		{
			if (atPoint.angle <= 90.0 && atPoint.angle > 0.0)
			{
				// in pageouts
				result = 1;
			}
			else if (atPoint.angle <= 180.0 && atPoint.angle > 90.0)
			{
				// in pageins
				result = 2;
			}
		}
	}

	return (result);
}

NSInteger swappingSort(id process1, id process2, void *context)
{
	int pid1 = [process1 processIdentifier];
	int pid2 = [process2 processIdentifier];
	
	if (pid1 == AGProcessValueUnknown)
	{
		pid1 = INT_MAX;
	}
	if (pid2 == AGProcessValueUnknown)
	{
		pid2 = INT_MAX;
	}
	
	if (pid1 > pid2)
	{
		return NSOrderedDescending;
	}
	else if (pid1 < pid2)
	{
		return NSOrderedAscending;
	}
	else
	{
		return NSOrderedSame;
	}
}

int swappingListSortByRank(const void *value1, const void *value2)
{
	struct swappingEntry *entry1 = (struct swappingEntry *)value1;
	struct swappingEntry *entry2 = (struct swappingEntry *)value2;

	int rank1 = ((entry1->pageins - entry1->lastPageins) * 10000) +  (entry1->faults - entry1->lastFaults);
	int rank2 = ((entry2->pageins - entry2->lastPageins) * 10000) +  (entry2->faults - entry2->lastFaults);;
	
	if (rank1 < rank2)
	{
		return (1);
	}
	else if (rank1 > rank2)
	{
		return (-1);
	}
	else
	{	
		return (0);
	}
}

int swappingListSortByPid(const void *value1, const void *value2)
{
	struct swappingEntry *entry1 = (struct swappingEntry *)value1;
	struct swappingEntry *entry2 = (struct swappingEntry *)value2;

	if (entry1->pid > entry2->pid)
	{
		return (1);
	}
	else if (entry1->pid < entry2->pid)
	{
		return (-1);
	}
	else
	{	
		return (0);
	}
}



- (void)drawSwappingInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	VMData vmdata;


	NSString *marker = NSLocalizedString(@">", nil);
	NSString *blank = @"";
	
	if (! swappingInfoString)
	{
		swappingInfoString = [self attributedStringForFile:@"Swapping.rtf"];
		[swappingInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:swappingInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];

	[self replaceFormatting:output inString:outputString];

	[memoryInfo getCurrent:&vmdata];

	if (index == 1)
	{
		// in pageouts
		[self highlightToken:@"[po]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[po]" inString:outputString withString:marker];
		[self replaceToken:@"[pi]" inString:outputString withString:blank];
	}
	else if (index == 2)
	{
		// in pageins
		[self highlightToken:@"[pi]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[po]" inString:outputString withString:blank];
		[self replaceToken:@"[pi]" inString:outputString withString:marker];
	}

	[self replaceToken:@"[poc]" inString:outputString withString:[NSString stringWithFormat:@"%d", vmdata.pageouts]];
	[self replaceToken:@"[pob]" inString:outputString withString:[self stringForValue:(vmdata.pageouts * 4096.0) withBytes:YES]];

	[self replaceToken:@"[pic]" inString:outputString withString:[NSString stringWithFormat:@"%d", vmdata.pageins]];
	[self replaceToken:@"[pib]" inString:outputString withString:[self stringForValue:(vmdata.pageins * 4096.0) withBytes:YES]];

	// count number & size of swapfiles in /var/vm
	{
		NSString *file;
		NSDirectoryEnumerator *enumerator;
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *swapfilesDirectory = [defaults stringForKey:APPLICATION_SWAPFILES_PATH_KEY];
		if (swapfilesDirectory == nil)
		{
			swapfilesDirectory = @"/var/vm";
		}		
		BOOL isDirectory;
		
		if ([fileManager fileExistsAtPath:swapfilesDirectory isDirectory:&isDirectory] && isDirectory)
		{
			int numberOfSwapfiles = 0;
			float sizeOfSwapfiles = 0.0;			

			enumerator = [fileManager enumeratorAtPath:swapfilesDirectory];
			while (file = [enumerator nextObject])
			{
				// check that name begins with "swapfile"
				NSRange range = [file rangeOfString:@"swapfile"];
				if (range.location != NSNotFound && range.location == 0)
				{
					NSString *filePath = [NSString stringWithFormat:@"%@/%@", swapfilesDirectory, file];
					
					NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:NULL];
					if (fileAttributes)
					{
						NSNumber *fileSize;
						if ((fileSize = [fileAttributes objectForKey:NSFileSize]))
						{
							numberOfSwapfiles += 1;
							sizeOfSwapfiles += [fileSize floatValue];
						}
					}
				}
			}

			[self replaceToken:@"[pf]" inString:outputString withString:[NSString stringWithFormat:@"%d", numberOfSwapfiles]];
			[self replaceToken:@"[ps]" inString:outputString withString:[self stringForValue:sizeOfSwapfiles withBytes:YES]];
		}
		else
		{
			[self replaceToken:@"[pf]" inString:outputString withString:@"?"];
			[self replaceToken:@"[ps]" inString:outputString withString:@"?"];
		}
	}
	
	NSMutableString *pagingList = [NSMutableString stringWithString:@""];
	{
		NSArray *processes = [self collectProcesses];
		AGProcess *process;

		NSArray *sortedProcesses = [processes sortedArrayUsingFunction:swappingSort context:NULL];

		// setup swapping list
		{
			int i;
			for (i = 0; i < SWAPPING_LIST_SIZE; i++)
			{
				swappingList[i].isCurrent = NO;
			}
		}
		
		// update swapping list
		NSEnumerator *processEnumerator = [sortedProcesses objectEnumerator];
		int swappingListIndex = 0;
		int insertIndex = SWAPPING_LIST_SIZE - 1;
		while (process = [processEnumerator nextObject])
		{
			int swappingListPid = swappingList[swappingListIndex].pid;
			int processPid = [process processIdentifier];
			
			while (swappingListPid < processPid)
			{
				swappingListIndex += 1;
				swappingListPid = swappingList[swappingListIndex].pid;
			}
			
			if (swappingListPid == processPid)
			{
				swappingList[swappingListIndex].lastPageins = swappingList[swappingListIndex].pageins;
				swappingList[swappingListIndex].pageins = [process pageins];
				swappingList[swappingListIndex].lastFaults = swappingList[swappingListIndex].faults;
				swappingList[swappingListIndex].faults = [process faults];
				swappingList[swappingListIndex].isCurrent = YES;
			}
			else
			{
				swappingList[insertIndex].pid = processPid;
				swappingList[insertIndex].lastPageins = [process pageins];
				swappingList[insertIndex].pageins = [process pageins];
				swappingList[insertIndex].lastFaults = [process faults];
				swappingList[insertIndex].faults = [process faults];
				swappingList[insertIndex].isCurrent = YES;
				
				insertIndex -= 1;
			}
		}
		
		// cleanup swapping list
		{
			int i;
			for (i = 0; i < SWAPPING_LIST_SIZE; i++)
			{
				if (! swappingList[i].isCurrent)
				{
					swappingList[i].pid = INT_MAX;
					swappingList[i].lastPageins = 0;
					swappingList[i].pageins = 0;
					swappingList[i].lastFaults = 0;
					swappingList[i].faults = 0;
				}
			}
		}
		
		// sort swapping list by rank
		{
			qsort(&swappingList[0], SWAPPING_LIST_SIZE, sizeof(struct swappingEntry), swappingListSortByRank);
		}
		
		// output process list
		{
			BOOL checkPid = NO;
			if (! [defaults boolForKey:GLOBAL_SHOW_SELF_KEY])
			{
				checkPid = YES;
			}

			BOOL done = NO;
			int i = 0;
			int count = 0;
			while (! done)
			{
				int pid = swappingList[i].pid;
				
				BOOL pidOK = YES;
				if (checkPid)
				{
					if (pid == selfPid)
					{
						pidOK = NO;
					}
				}

				if (pid != INT_MAX && pidOK)
				{
					AGProcess *outputProcess = [AGProcess processForProcessIdentifier:pid];
					int pageinDelta = swappingList[i].pageins - swappingList[i].lastPageins;
					int faultDelta = swappingList[i].faults - swappingList[i].lastFaults;

					if (pageinDelta == 0 && faultDelta == 0)
					{
						done = YES;
					}
					else
					{
						[pagingList appendString:[NSString stringWithFormat:@"\t%d\t%d\t%@\n", pageinDelta, faultDelta, [outputProcess annotatedCommand]]];
						count += 1;
					}
				}
				
				i ++;
				
				if (count == 10 || i == SWAPPING_LIST_SIZE)
				{
					done = YES;
				}
			}
		}

		// sort swapping list by pid
		{
			qsort(&swappingList[0], SWAPPING_LIST_SIZE, sizeof(struct swappingEntry), swappingListSortByPid);
		}
	}
	[self replaceToken:@"[pl]" inString:outputString withString:pagingList];
	
	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

- (void)drawSwappingStatusAt:(StatusType)statusType
{
	NSColor *leftColor;
	NSColor *rightColor;
	NSColor *alertColor;
	PositionType leftPosition;
	PositionType rightPosition;
	BOOL fadeAll;	
	[self generateParametersFor:statusType leftColor:&leftColor rightColor:&rightColor alertColor:&alertColor leftPosition:&leftPosition rightPosition:&rightPosition fadeAll:&fadeAll];

	int x;
	float iy, oy;
	VMData vmdata;
	
	if (fadeAll)
	{
		float alphaIn = [leftColor alphaComponent];
		float transparencyIn;
		float alphaOut = [rightColor alphaComponent];
		float transparencyOut;

		[memoryInfo startIterate];
		for (x = 0; [memoryInfo getNext:&vmdata]; x++)
		{
			transparencyIn = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaIn;
			transparencyOut = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaOut;

			iy = (vmdata.pageins / 50.0);
			oy = (vmdata.pageouts / 50.0);

			[self drawStatusBarValue:iy atPosition:leftPosition withColor:[leftColor colorWithAlphaComponent:transparencyIn]];
			[self drawStatusBarValue:oy atPosition:rightPosition withColor:[rightColor colorWithAlphaComponent:transparencyOut]];
		}
	}
	else
	{
		[memoryInfo getCurrent:&vmdata];

		iy = (vmdata.pageins / 50.0);
		oy = (vmdata.pageouts / 50.0);

		if (iy > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:leftColor];
			if (iy >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
			}
		}
		if (oy > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:rightColor];
			if (oy >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
			}
		}
	}
}

#pragma mark -

- (void)drawDiskGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:DISK_SHOW_GAUGE_KEY])
	{
		NSColor *diskUsedColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_USED_COLOR_KEY]];
		NSColor *diskWarningColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_WARNING_COLOR_KEY]];
		NSColor *diskBackgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_BACKGROUND_COLOR_KEY]];
		
		DiskData diskdata;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		// draw static disk data
		[diskInfo getCurrent:&diskdata];

		if ([defaults boolForKey:DISK_SUM_ALL_KEY])
		{
			// sum all of the current disks and display as one gauge
			
			int i;
			float endAngle;
			
			unsigned long totalFreeBlocks = 0;
			unsigned long totalAvailableBlocks = 0;
			
			float used;

			if (diskdata.unlocked.count > 0)
			{
				for (i = 0; i < diskdata.unlocked.count; i++)
				{
					totalFreeBlocks += diskdata.unlocked.freeBlocks[i];
					totalAvailableBlocks += diskdata.unlocked.availableBlocks[i];
				}
				
				used = 1.0 - ((float)totalFreeBlocks /  (float)totalAvailableBlocks);
			}
			else
			{
				used = 0.0;
			}


			[diskBackgroundColor set];
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:360.0 endAngle:180.0 clockwise:YES];
	
			if (used < 0.90)
			{
				[diskUsedColor set];
			}
			else
			{
				[diskWarningColor set];
			}
			
			endAngle = 360.0 - (used * 180.0);
			[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:360.0 endAngle:endAngle clockwise:YES];
		}
		else
		{
			// show each disk in a separate gauge
			
			int i;
			float sliceAngle = 180.0 / diskdata.unlocked.count;
			float currentAngle = 360.0;
			float endAngle;
	
			for (i = 0; i < diskdata.unlocked.count; i++)
			{
				[diskBackgroundColor set];
				endAngle = currentAngle - sliceAngle;
				[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:currentAngle endAngle:endAngle clockwise:YES];
	
				if (diskdata.unlocked.used[i] < 0.90)
				{
					[diskUsedColor set];
				}
				else
				{
					[diskWarningColor set];
				}
				
				// draw a divider so disks with little usage will show up
				{
					NSPoint innerPoint;
					NSPoint outerPoint;
					
					innerPoint = [self pointAtCenter:processorPoint atAngle:currentAngle atRadius:(GRAPH_SIZE/4.0)];
					outerPoint = [self pointAtCenter:processorPoint atAngle:currentAngle atRadius:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0)];
					[self drawLineFrom:innerPoint to:outerPoint width:1.0];
				}
				
				endAngle = currentAngle - (diskdata.unlocked.used[i] * sliceAngle);
				[self drawValueAngleFrom:(GRAPH_SIZE/4.0 + GRAPH_SIZE/8.0) to:(GRAPH_SIZE/4.0) atPoint:processorPoint startAngle:currentAngle endAngle:endAngle clockwise:YES];
	
				currentAngle -= sliceAngle;
			}
		}
	}

	if ([defaults boolForKey:DISK_IO_SHOW_GAUGE_KEY])
	{
		NSColor *diskReadColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_READ_COLOR_KEY]];
		NSColor *diskWriteColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_WRITE_COLOR_KEY]];
	
		NSColor *readsDarkColor = [diskReadColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];
		NSColor *writesDarkColor = [diskWriteColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];

		int x;
		float y;
		DiskData diskdata;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;
	
		int scaleType = [defaults integerForKey:DISK_SCALE_KEY];
		float peakRead = (peakReadBytes / interval);
		float scaleRead = [self computeScaleForGauge:scaleType withPeak:peakRead];
		float peakWrite = (peakWriteBytes / interval);
		float scaleWrite = [self computeScaleForGauge:scaleType withPeak:peakWrite];
		float holdTime = rint(pow(60, [defaults floatForKey:GLOBAL_HOLD_TIME_KEY]));
		
		const float innerRadius = (GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0 - GRAPH_SIZE/8.0);
		const float outerRadius = (GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0);

		float alphaRead = [diskReadColor alphaComponent];
		float transparencyRead;
		float alphaWrite = [diskWriteColor alphaComponent];
		float transparencyWrite;
		
		float maxRead = 0.0;
		float maxWrite = 0.0;
		
		[diskInfo startIterate];
		for (x = 0; [diskInfo getNext:&diskdata]; x++)
		{
			transparencyRead = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaRead;

			y = [self scaleValueForGauge:(diskdata.readBytes / interval) scaleType:scaleType scale:scaleRead] * 90.0;
			[[diskReadColor colorWithAlphaComponent:transparencyRead] set];
			[self drawValueAngleFrom:innerRadius to:outerRadius atPoint:processorPoint startAngle:180.0 endAngle:(180.0 + y) clockwise:NO];
			
			if (y > maxRead)
			{
				maxRead = y;
			}
	
			transparencyWrite = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaWrite;

			y = [self scaleValueForGauge:(diskdata.writeBytes / interval) scaleType:scaleType scale:scaleWrite] * 90.0;
			[[diskWriteColor colorWithAlphaComponent:transparencyWrite] set];
			[self drawValueAngleFrom:innerRadius to:outerRadius atPoint:processorPoint startAngle:360.0 endAngle:(360.0 - y) clockwise:YES];

			if (y > maxWrite)
			{
				maxWrite = y;
			}	
		}

		if (scaleType < 0) // logarithmic
		{
			[readsDarkColor set];

			if (maxRead > 30.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 30.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 30.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
			if (maxRead > 60.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 60.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 60.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}

			[writesDarkColor set];

			if (maxWrite > 30.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 30.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 30.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
			if (maxWrite > 60.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 60.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 60.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
		}
		else if (scaleType == 0) // automatic
		{
			int readDots = 0;
			if (scaleRead > 0.0)
			{
				readDots = floor(log10(scaleRead) - 3.0);
				if (readDots < 0)
				{
					readDots = 0;
				}
			}
			int writeDots = 0;
			if (scaleWrite > 0.0)
			{
				writeDots = floor(log10(scaleWrite) - 3.0);
				if (writeDots < 0)
				{
					writeDots = 0;
				}
			}
			//NSLog(@"MainController: drawDiskGauge: readDots = %d, writeDots = %d", readDots, writeDots);

			int x;
			const double sliceMinuteAngle = 360.0 / 45.0;
	
			NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
			NSPoint timePoint;

			double radius = (GRAPH_SIZE/4.0) + (GRAPH_SIZE/32.0);
		
			for (x = 1; x <= readDots; x++)
			{
				float fadeAngle = 270.0 - (x * sliceMinuteAngle);
	
				timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];

				[readsDarkColor set];
				[self drawValue:(GRAPH_SIZE / 64.0) atPoint:timePoint withFill:YES];
			}

			for (x = 1; x <= writeDots; x++)
			{
				float fadeAngle = 270.0 + (x * sliceMinuteAngle);
	
				timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];

				[writesDarkColor set];
				[self drawValue:(GRAPH_SIZE / 64.0) atPoint:timePoint withFill:YES];
			}
		}


		if ([defaults boolForKey:DISK_SHOW_PEAK_KEY])
		{
			NSPoint innerPoint;
			NSPoint outerPoint;
			float y;
		
			y = [self scaleValueForGauge:peakRead scaleType:scaleType scale:scaleRead] * 90.0;
			if (y > 0.0)
			{
				float peakAngle = 180.0 + y;

				innerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:innerRadius];
				outerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:outerRadius];
				
				[diskReadColor set];
				[self drawLineFrom:innerPoint to:outerPoint width:2.0];
			}

			y = [self scaleValueForGauge:peakWrite scaleType:scaleType scale:scaleWrite] * 90.0;
			if (y > 0.0)
			{
				float peakAngle = 360.0 - y;
						
				innerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:innerRadius];
				outerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:outerRadius];

				[diskWriteColor set];
				[self drawLineFrom:innerPoint to:outerPoint width:2.0];
			}
		}
		if (now - timePeakReadBytes > holdTime || diskdata.readBytes > peakReadBytes)
		{
			// set new peak if time has elapsed or if there is a new high value
			peakReadBytes = diskdata.readBytes;
			timePeakReadBytes = now;
		}
		if (now - timePeakWriteBytes > holdTime || diskdata.writeBytes > peakWriteBytes)
		{
			// set new peak if time has elapsed or if there is a new high value
			peakWriteBytes = diskdata.writeBytes;
			timePeakWriteBytes = now;
		}
	}
	
	if ([defaults boolForKey:DISK_SHOW_ACTIVITY_KEY])
	{
		NSColor *diskReadColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_READ_COLOR_KEY]];
		NSColor *diskWriteColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_WRITE_COLOR_KEY]];
		NSColor *diskHighColor = [Preferences colorAlphaFromString:[defaults stringForKey:DISK_HIGH_COLOR_KEY]];
	
		NSColor *readsDarkColor = [diskReadColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];
		NSColor *writesDarkColor = [diskWriteColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];

		float y;
		DiskData diskdata;
	
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

		NSPoint diskReadPoint = NSMakePoint(0.0 + GRAPH_SIZE/16.0 + GRAPH_SIZE/8.0, (GRAPH_SIZE/2.0));
		NSPoint diskWritePoint = NSMakePoint(GRAPH_SIZE - GRAPH_SIZE/16.0 - GRAPH_SIZE/8.0, (GRAPH_SIZE/2.0));

		float readsAlpha = [diskReadColor alphaComponent] * 1.5;
		float writesAlpha = [diskWriteColor alphaComponent] * 1.5;

		[diskInfo getCurrent:&diskdata];
		{
			if (diskdata.readCount > 0)
			{
				y = GRAPH_SIZE / 16.0;
				if (diskdata.readCount < (100.0 / interval))
				{
					[[readsDarkColor colorWithAlphaComponent:readsAlpha] set];
				}
				else
				{
					[[diskHighColor colorWithAlphaComponent:readsAlpha] set];
				}
				if (! alternativeActivity)
				{
					[self drawValue:y atPoint:diskReadPoint];
				}
				else
				{
					[self drawPointer:y atPoint:diskReadPoint];
				}
			}
			if (diskdata.writeCount > 0)
			{
				y = GRAPH_SIZE / 16.0;
				if (diskdata.writeCount < (100.0 / interval))
				{
					[[writesDarkColor colorWithAlphaComponent:writesAlpha] set];
				}
				else
				{
					[[diskHighColor colorWithAlphaComponent:writesAlpha] set];
				}
				if (! alternativeActivity)
				{
					[self drawValue:y atPoint:diskWritePoint];
				}
				else
				{
					[self drawPointer:y atPoint:diskWritePoint];
				}
			}	
		}
	}
}

- (void)drawDiskText
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:DISK_SHOW_TEXT_KEY])
	{
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		DiskData diskdata;

		if ([defaults boolForKey:DISK_SUM_ALL_KEY])
		{
			int x;
			
			unsigned long totalFreeBlocks = 0;
			unsigned long totalAvailableBlocks = 0;

			[diskInfo getCurrent:&diskdata];
	
			for (x = 0; x < diskdata.unlocked.count; x++)
			{
				totalFreeBlocks += diskdata.unlocked.freeBlocks[x];
				totalAvailableBlocks += diskdata.unlocked.availableBlocks[x];
			}

			NSString *string = [NSString stringWithFormat:@"%.0f", (1.0 - ((double)totalFreeBlocks / (double)totalAvailableBlocks)) * 100.0];

			NSPoint drawPoint = [self pointAtCenter:processorPoint atAngle:270.0 atRadius:(GRAPH_SIZE/4.0 + GRAPH_SIZE/16.0)];
			[self drawText:string atPoint:drawPoint];
		}
		else
		{
			int x;
			
			float sliceAngle;
			float currentAngle;
	
			[diskInfo getCurrent:&diskdata];
	
			sliceAngle = 180.0 / diskdata.unlocked.count;
			currentAngle = 360.0;
	
			for (x = 0; x < diskdata.unlocked.count; x++)
			{
				NSPoint drawPoint;
				
				float textAngle = currentAngle - (diskdata.unlocked.used[x] * sliceAngle / 2.0);
	
				NSString *string = [NSString stringWithFormat:@"%.0f", diskdata.unlocked.used[x] * 100.0];
	
				drawPoint = [self pointAtCenter:processorPoint atAngle:textAngle atRadius:(GRAPH_SIZE/4.0 + GRAPH_SIZE/16.0)];
				[self drawText:string atPoint:drawPoint];
				
				currentAngle -= sliceAngle;
			}
		}
	}
}

- (int)inDiskGauge:(GraphPoint)atPoint
{
	int result = 0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:DISK_SHOW_GAUGE_KEY] || [defaults boolForKey:DISK_IO_SHOW_GAUGE_KEY])
	{
		if (atPoint.radius > 0.5 && atPoint.radius < 0.75)
		{
			if ([defaults boolForKey:DISK_SUM_ALL_KEY])
			{
				if (atPoint.angle <= 360.0 && atPoint.angle > 180.0)
				{
					result = 1;
				}
			}
			else
			{
				DiskData diskdata;
				int x;
		
				float sliceAngle;
				float currentAngle;
				float endAngle;
		
				[diskInfo getCurrent:&diskdata];
		
				sliceAngle = 180.0 / diskdata.unlocked.count;
				currentAngle = 360.0;
		
				for (x = 0; x < diskdata.unlocked.count; x++)
				{
					endAngle = currentAngle - sliceAngle;
		
					if (atPoint.angle <= currentAngle && atPoint.angle > endAngle)
					{
						// point in diskdata.fsMountName[x]
						result = x + 1;
					}
		
					currentAngle -= sliceAngle;
				}
			}
		}
	}

	return (result);
}

- (void)drawDiskInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	DiskData diskdata;

	NSString *marker = NSLocalizedString(@">", nil);
	NSString *blank = @"";	
	
	if (! diskInfoString)
	{
		diskInfoString = [self attributedStringForFile:@"Disk.rtf"];
		[diskInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:diskInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];
	
	[self replaceFormatting:output inString:outputString];

	[diskInfo getCurrent:&diskdata];
	int disksDisplayed = 0;
	NSMutableString *diskList = [NSMutableString stringWithString:@""];
	for (int i = 0; i < diskdata.unlocked.count; i++)
	{
		NSString *indicator;
		if ([defaults boolForKey:DISK_SUM_ALL_KEY] || ! [defaults boolForKey:DISK_SHOW_GAUGE_KEY])
		{
			// no indicator in disk sum mode or not showing disk gauge
			indicator = blank;
		}
		else {
			if (index == i + 1)
			{
				indicator = marker;
			}
			else
			{
				indicator = blank;
			}
		}
		
		unsigned long usedBlocks = diskdata.unlocked.availableBlocks[i] - diskdata.unlocked.freeBlocks[i];
		double usedBytes = (double)usedBlocks * (double)diskdata.unlocked.blockSize[i];
		double freeBytes = (double)diskdata.unlocked.freeBlocks[i] * (double)diskdata.unlocked.blockSize[i];
		double availableBytes = (double)diskdata.unlocked.availableBlocks[i] * (double)diskdata.unlocked.blockSize[i];

		NSString *mountName = nil;
		NSUInteger length = diskdata.unlocked.fsMountName[i].length;
		if (length > 12) {
			mountName = [[NSString stringWithCharacters:diskdata.unlocked.fsMountName[i].unicode length:11] stringByAppendingString:@"…"];
		}
		else {
			mountName = [NSString stringWithCharacters:diskdata.unlocked.fsMountName[i].unicode length:length];
		}

		[diskList appendString:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@\t%@\t%@\n",
									 indicator,
									 [self stringForValue:usedBytes],
									 [self stringForPercentage:diskdata.unlocked.used[i] withPercent:NO],
									 [self stringForValue:freeBytes withBytes:YES withDecimal:NO],
									 [self stringForValue:availableBytes withBytes:YES withDecimal:NO],
									 [NSString stringWithUTF8String:diskdata.unlocked.fsTypeName[i]],
									 mountName]];
		disksDisplayed += 1;
	}
	
// for testing a lot of disks...
#if 0
	for (int x = 0; x < 5; x++) {
		[diskList appendString:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@\t%@\t%@\n",
								blank,
								[self stringForValue:100000],
								[self stringForPercentage:0.25 withPercent:NO],
								[self stringForValue:300000 withBytes:YES withDecimal:NO],
								[self stringForValue:400000 withBytes:YES withDecimal:NO],
								@"test",
								[NSString stringWithFormat:@"Test Disk %ld", (long)x]]];
		disksDisplayed += 1;
	}
#endif
	
	[self replaceToken:@"[dl]" inString:outputString withString:diskList];
	[self highlightToken:marker ofAttributedString:output inString:outputString];
	
	int lockedListDisplaySize = DISK_LIST_SIZE - 1 - disksDisplayed;

	[diskInfo getCurrent:&diskdata];
	NSMutableString *lockedDiskList = [NSMutableString stringWithString:@""];
	int displayCount = diskdata.locked.count;
	if (displayCount > lockedListDisplaySize) {
		displayCount = lockedListDisplaySize;
	}
	for (int i = 0; i < displayCount; i++)
	{
		double availableBytes = (double)diskdata.locked.availableBlocks[i] * (double)diskdata.locked.blockSize[i];
		NSString *mountName = [NSString stringWithCharacters:diskdata.locked.fsMountName[i].unicode length:diskdata.locked.fsMountName[i].length];
		
		[lockedDiskList appendString:[NSString stringWithFormat:@"%@\t%@\t%@\n",
				[self stringForValue:availableBytes],
				[NSString stringWithUTF8String:diskdata.locked.fsTypeName[i]],
				mountName]];
	}
	[self replaceToken:@"[rl]" inString:outputString withString:lockedDiskList];
	
	// display dynamic disk data
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;
	
		float peakRead = (peakReadBytes / interval);
		float peakWrite = (peakWriteBytes / interval);
		float readBytes = (diskdata.readBytes / interval);
		int readCount = diskdata.readCount;
		float writeBytes = (diskdata.writeBytes / interval);
		int writeCount = diskdata.writeCount;
		
		float readSum = 0.0;
		int readCounter = 0;
		float readAverage;
		float writeSum = 0.0;
		int writeCounter = 0;
		float writeAverage;

		[diskInfo startIterate];
		for (int i = 0; [diskInfo getNext:&diskdata]; i++)
		{
			readSum += diskdata.readBytes;
			readCounter += 1;

			writeSum += diskdata.writeBytes;
			writeCounter += 1;
		}
		readAverage = (readSum / (float) readCounter) / interval;
		writeAverage = (writeSum / (float) writeCounter) / interval;

		if (atPoint.angle <= 270.0 && atPoint.angle > 180.0)
		{
			// in reads
			if ([defaults boolForKey:DISK_IO_SHOW_GAUGE_KEY])
			{
				[self highlightToken:@"[dr]" ofAttributedString:output inString:outputString];
				[self replaceToken:@"[dr]" inString:outputString withString:marker];
			}
			else
			{
				[self replaceToken:@"[dr]" inString:outputString withString:blank];
			}
			
			[self replaceToken:@"[dw]" inString:outputString withString:blank];
		}
		else if (atPoint.angle <= 360.0 && atPoint.angle > 270.0)
		{
			// in writes
			if ([defaults boolForKey:DISK_IO_SHOW_GAUGE_KEY])
			{
				[self highlightToken:@"[dw]" ofAttributedString:output inString:outputString];
				[self replaceToken:@"[dw]" inString:outputString withString:marker];
			}
			else
			{
				[self replaceToken:@"[dw]" inString:outputString withString:blank];
			}
			
			[self replaceToken:@"[dr]" inString:outputString withString:blank];	
		}

		[self replaceToken:@"[drc]" inString:outputString withString:[NSString stringWithFormat:@"%d", readCount]];
		[self replaceToken:@"[drb]" inString:outputString withString:[self stringForValue:readBytes]];
		[self replaceToken:@"[drp]" inString:outputString withString:[self stringForValue:peakRead]];
		[self replaceToken:@"[dra]" inString:outputString withString:[self stringForValue:readAverage]];

		[self replaceToken:@"[dwc]" inString:outputString withString:[NSString stringWithFormat:@"%d", writeCount]];
		[self replaceToken:@"[dwb]" inString:outputString withString:[self stringForValue:writeBytes]];
		[self replaceToken:@"[dwp]" inString:outputString withString:[self stringForValue:peakWrite]];
		[self replaceToken:@"[dwa]" inString:outputString withString:[self stringForValue:writeAverage]];
	}
	
	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

- (void)drawDiskStatusAt:(StatusType)statusType
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSColor *leftColor;
	NSColor *rightColor;
	NSColor *alertColor;
	PositionType leftPosition;
	PositionType rightPosition;
	BOOL fadeAll;	
	[self generateParametersFor:statusType leftColor:&leftColor rightColor:&rightColor alertColor:&alertColor leftPosition:&leftPosition rightPosition:&rightPosition fadeAll:&fadeAll];

	int x;
	float ry, wy;
	DiskData diskdata;
	
	float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

	int scaleType = [defaults integerForKey:DISK_SCALE_KEY];
	float peakRead = (peakReadBytes / interval);
	float scaleRead = [self computeScaleForGauge:scaleType withPeak:peakRead];
	float peakWrite = (peakWriteBytes / interval);
	float scaleWrite = [self computeScaleForGauge:scaleType withPeak:peakWrite];
	
	if (fadeAll)
	{
		float alphaIn = [leftColor alphaComponent];
		float transparencyIn;
		float alphaOut = [rightColor alphaComponent];
		float transparencyOut;

		BOOL alertIn = NO;
		BOOL alertOut = NO;
		
		[diskInfo startIterate];
		for (x = 0; [diskInfo getNext:&diskdata]; x++)
		{
			transparencyIn = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaIn;
			transparencyOut = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaOut;

			ry = [self scaleValueForGauge:(diskdata.readBytes / interval) scaleType:scaleType scale:scaleRead];
			wy = [self scaleValueForGauge:(diskdata.writeBytes / interval) scaleType:scaleType scale:scaleWrite];

			if (x == (SAMPLE_SIZE - 1) && ry >= statusAlertThreshold)
			{
				alertIn = YES;
			}
			if (x == (SAMPLE_SIZE - 1) && ry >= statusAlertThreshold)
			{
				alertOut = YES;
			}

			[self drawStatusBarValue:ry atPosition:leftPosition withColor:[leftColor colorWithAlphaComponent:transparencyIn]];
			[self drawStatusBarValue:wy atPosition:rightPosition withColor:[rightColor colorWithAlphaComponent:transparencyOut]];
		}
		if (alertIn)
		{
			[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
		}
		if (alertOut)
		{
			[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
		}
	}
	else
	{
		[diskInfo getCurrent:&diskdata];

		ry = [self scaleValueForGauge:(diskdata.readBytes / interval) scaleType:scaleType scale:scaleRead];
		wy = [self scaleValueForGauge:(diskdata.writeBytes / interval) scaleType:scaleType scale:scaleWrite];

		if (ry > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:leftColor];
			if (ry >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
			}
		}
		if (wy > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:rightColor];
			if (wy >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
			}
		}
	}	
}

#pragma mark -

- (void)drawNetworkGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:NETWORK_SHOW_GAUGE_KEY])
	{
		NSColor *networkInColor = [Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_IN_COLOR_KEY]];
		NSColor *networkOutColor = [Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_OUT_COLOR_KEY]];
	
		NSColor *inDarkColor = [networkInColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];
		NSColor *outDarkColor = [networkOutColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];

		int x;
		float y;
		NetData netdata;
	
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

		int scaleType = [defaults integerForKey:NETWORK_SCALE_KEY];
		float peakIn = (peakPacketsInBytes / interval);
		float scaleIn = [self computeScaleForGauge:scaleType withPeak:peakIn];
		float peakOut = (peakPacketsOutBytes / interval);
		float scaleOut = [self computeScaleForGauge:scaleType withPeak:peakOut];
		float holdTime = rint(pow(60, [defaults floatForKey:GLOBAL_HOLD_TIME_KEY]));

		const float innerRadius = (GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0);
		const float outerRadius = (GRAPH_SIZE/2.0);
		
		float alphaIn = [networkInColor alphaComponent];
		float transparencyIn;
		float alphaOut = [networkOutColor alphaComponent];
		float transparencyOut;

		float maxIn = 0.0;
		float maxOut = 0.0;
		
		[networkInfo startIterate];
		for (x = 0; [networkInfo getNext:&netdata]; x++)
		{
			transparencyIn = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaIn;
	
			y = [self scaleValueForGauge:(netdata.packetsInBytes / interval) scaleType:scaleType scale:scaleIn] * 90.0;
			[[networkInColor colorWithAlphaComponent:transparencyIn] set];
			[self drawValueAngleFrom:innerRadius to:outerRadius atPoint:processorPoint startAngle:180.0 endAngle:(180.0 + y) clockwise:NO];

			if (y > maxIn)
			{
				maxIn = y;
			}

			transparencyOut = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaOut;

			y = [self scaleValueForGauge:(netdata.packetsOutBytes / interval) scaleType:scaleType scale:scaleOut] * 90.0;
			[[networkOutColor colorWithAlphaComponent:transparencyOut] set];
			[self drawValueAngleFrom:innerRadius to:outerRadius atPoint:processorPoint startAngle:360.0 endAngle:(360.0 - y) clockwise:YES];
	
			if (y > maxOut)
			{
				maxOut = y;
			}
		}

		if (scaleType < 0) // logarithmic
		{
			[inDarkColor set];

			if (maxIn > 30.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 30.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 30.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
			if (maxIn > 60.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 60.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:180.0 + 60.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}

			[outDarkColor set];

			if (maxOut > 30.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 30.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 30.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
			if (maxOut > 60.0)
			{
				NSPoint innerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 60.0 atRadius:innerRadius];
				NSPoint outerPoint = [self pointAtCenter:processorPoint atAngle:360.0 - 60.0 atRadius:outerRadius];

				[self drawLineFrom:innerPoint to:outerPoint width:1.0];
			}
		}
		else if (scaleType == 0) // automatic
		{
			int inDots = 0;
			if (scaleIn > 0.0)
			{
				inDots = floor(log10(scaleIn) - 3.0);
				if (inDots < 0)
				{
					inDots = 0;
				}
			}
			int outDots = 0;
			if (scaleOut > 0.0)
			{
				outDots = floor(log10(scaleOut) - 3.0);
				if (outDots < 0)
				{
					outDots = 0;
				}
			}
			//NSLog(@"MainController: drawDiskGauge: readDots = %d, writeDots = %d", readDots, writeDots);

			int x;
			const double sliceMinuteAngle = 360.0 / 60.0;
	
			NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
			NSPoint timePoint;

			double radius = (GRAPH_SIZE/2.0) - (GRAPH_SIZE/16.0) - (GRAPH_SIZE/32.0); // network
		
			for (x = 1; x <= inDots; x++)
			{
				float fadeAngle = 270.0 - (x * sliceMinuteAngle);
	
				timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];

				[inDarkColor set];
				[self drawValue:(GRAPH_SIZE / 64.0) atPoint:timePoint withFill:YES];
			}

			for (x = 1; x <= outDots; x++)
			{
				float fadeAngle = 270.0 + (x * sliceMinuteAngle);
	
				timePoint = [self pointAtCenter:processorPoint atAngle:fadeAngle atRadius:radius];

				[outDarkColor set];
				[self drawValue:(GRAPH_SIZE / 64.0) atPoint:timePoint withFill:YES];
			}
		}


		if ([defaults boolForKey:NETWORK_SHOW_PEAK_KEY])
		{
			NSPoint innerPoint;
			NSPoint outerPoint;
			float y;
		
			y = [self scaleValueForGauge:peakIn scaleType:scaleType scale:scaleIn] * 90.0;
			if (y > 0.0)
			{
				float peakAngle = 180.0 + y;

				innerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:innerRadius];
				outerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:outerRadius];
				
				[networkInColor set];
				[self drawLineFrom:innerPoint to:outerPoint width:2.0];
			}

			y = [self scaleValueForGauge:peakOut scaleType:scaleType scale:scaleOut] * 90.0;
			if (y > 0.0)
			{
				float peakAngle = 360.0 - y;
						
				innerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:innerRadius];
				outerPoint = [self pointAtCenter:processorPoint atAngle:peakAngle atRadius:outerRadius];

				[networkOutColor set];
				[self drawLineFrom:innerPoint to:outerPoint width:2.0];
			}
		}
		if (now - timePeakPacketsInBytes > holdTime || netdata.packetsInBytes > peakPacketsInBytes)
		{
			// set new peak if time has elapsed or if there is a new high value
			peakPacketsInBytes = netdata.packetsInBytes;
			timePeakPacketsInBytes = now;
			//NSLog(@"MainController: drawNetworkGauge: packetsInBytes = %llu, peakPacketsInBytes = %llu", netdata.packetsInBytes, peakPacketsInBytes);
		}
		if (now - timePeakPacketsOutBytes > holdTime || netdata.packetsOutBytes > peakPacketsOutBytes)
		{
			// set new peak if time has elapsed or if there is a new high value
			peakPacketsOutBytes = netdata.packetsOutBytes;
			timePeakPacketsOutBytes = now;
			//NSLog(@"MainController: drawNetworkGauge: packetsOutBytes = %llu, peakPacketsOutBytes = %llu", netdata.packetsOutBytes, peakPacketsOutBytes);
		}
	}

	if ([defaults boolForKey:NETWORK_SHOW_ACTIVITY_KEY])
	{
		NSColor *networkInColor = [Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_IN_COLOR_KEY]];
		NSColor *networkOutColor = [Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_OUT_COLOR_KEY]];
		NSColor *networkHighColor = [Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_HIGH_COLOR_KEY]];	
	
		NSColor *inDarkColor = [networkInColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];
		NSColor *outDarkColor = [networkOutColor blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]];

		float y;
		NetData netdata;
	
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;	

		NSPoint packetsInPoint = NSMakePoint(0.0 + GRAPH_SIZE/16.0, (GRAPH_SIZE/2.0));
		NSPoint packetsOutPoint = NSMakePoint(GRAPH_SIZE - GRAPH_SIZE/16.0, (GRAPH_SIZE/2.0));

		float packetsInAlpha = [networkInColor alphaComponent] * 1.5;
		float packetsOutAlpha = [networkOutColor alphaComponent] * 1.5;


		[networkInfo getCurrent:&netdata];
		
		if (netdata.packetsIn > 0)
		{
			y = GRAPH_SIZE / 16.0;
			if (netdata.packetsIn < (50.0 / interval))
			{
				[[inDarkColor colorWithAlphaComponent:packetsInAlpha] set];
			}
			else
			{
				[[networkHighColor colorWithAlphaComponent:packetsInAlpha] set];
			}
			if (! alternativeActivity)
			{
				[self drawValue:y atPoint:packetsInPoint];
			}
			else
			{
				[self drawPointer:y atPoint:packetsInPoint];
			}
		}

		if (netdata.packetsOut > 0)
		{
			y = GRAPH_SIZE / 16.0;
			if (netdata.packetsOut < (50.0 / interval))
			{
				[[outDarkColor colorWithAlphaComponent:packetsOutAlpha] set];
			}
			else
			{
				[[networkHighColor colorWithAlphaComponent:packetsOutAlpha] set];
			}
			if (! alternativeActivity)
			{
				[self drawValue:y atPoint:packetsOutPoint];
			}
			else
			{
				[self drawPointer:y atPoint:packetsOutPoint];
			}
		}
	}
}

- (void)drawNetworkText
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:NETWORK_SHOW_TEXT_KEY])
	{
		NSPoint networkInPoint = NSMakePoint(0.0 + (GRAPH_SIZE/16.0), (GRAPH_SIZE/2.0) - (GRAPH_SIZE/16.0));
		NSPoint networkOutPoint = NSMakePoint(GRAPH_SIZE - (GRAPH_SIZE/16.0), (GRAPH_SIZE/2.0) - (GRAPH_SIZE/16.0));

		int x;
		
		double inSum = 0;
		int inCount = 0;
		double inAverage;
		double outSum = 0;
		int outCount = 0;
		double outAverage;
		
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;
		
		double inPerSecond;
		double outPerSecond;


		int scaleType = [defaults integerForKey:NETWORK_SCALE_KEY];
		float peakIn = (peakPacketsInBytes / interval);
		float scaleIn = [self computeScaleForGauge:scaleType withPeak:peakIn];
		float peakOut = (peakPacketsOutBytes / interval);
		float scaleOut = [self computeScaleForGauge:scaleType withPeak:peakOut];
			
		NetData netdata;
	
		[networkInfo startIterate];
		for (x = 0; [networkInfo getNext:&netdata]; x++)
		{
			inSum += netdata.packetsInBytes;
			inCount += 1;

			outSum += netdata.packetsOutBytes;
			outCount += 1;
		}
		inAverage = inSum / (double) inCount;
		outAverage = outSum / (double) outCount;
		
		inPerSecond = [self scaleValueForGauge:(inAverage / interval) scaleType:scaleType scale:scaleIn] * 100.0;
		outPerSecond = [self scaleValueForGauge:(outAverage / interval) scaleType:scaleType scale:scaleOut] * 100.0;

		//NSLog(@"In average = %8.2f rate = %8.2f, Out average = %8.2f rate = %8.2f", inAverage, inPerSecond, outAverage, outPerSecond);

		if (inPerSecond > 0)
		{
			NSString *string;
			if (inPerSecond > 99.0)
			{
				string = @"+";
			}
			else
			{
				string = [NSString stringWithFormat:@"%.0f", ceil(inPerSecond)];
			}

			[self drawText:string atPoint:networkInPoint];
		}
		
		if (outPerSecond > 0)
		{
			NSString *string;
			if (outPerSecond > 99.0)
			{
				string = @"+";
			}
			else
			{
				string = [NSString stringWithFormat:@"%.0f", ceil(outPerSecond)];
			}

			[self drawText:string atPoint:networkOutPoint];
		}
	}
}

- (BOOL)inNetworkGauge:(GraphPoint)atPoint
{
	int result = 0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:NETWORK_SHOW_GAUGE_KEY])
	{		
		if (atPoint.radius > 0.75 && atPoint.radius < 1.0)
		{
			if (atPoint.angle <= 270.0 && atPoint.angle > 180.0)
			{
				// in received
				result = 1;
			}
			else if (atPoint.angle <= 360.0 && atPoint.angle > 270.0)
			{
				// in sent
				result = 2;
			}
		}
	}

	return (result);
}

- (void)drawNetworkInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NetData netdata;

	char hostname[1024];

	NSString *marker = NSLocalizedString(@">", nil);
	NSString *blank = @"";
	
	if (! networkInfoString)
	{
		networkInfoString = [self attributedStringForFile:@"Network.rtf"];
		[networkInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:networkInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];
	
	[self replaceFormatting:output inString:outputString];

	int x;

	double inSum = 0;
	int inCount = 0;
	double inAverage;
	double outSum = 0;
	int outCount = 0;
	double outAverage;

	float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

	float peakIn = (peakPacketsInBytes / interval);
	float peakOut = (peakPacketsOutBytes / interval);

	double inPerSecond;
	double outPerSecond;

	[networkInfo getCurrent:&netdata];

	[self replaceToken:@"[nrc]" inString:outputString withString:[NSString stringWithFormat:@"%llu",netdata.packetsIn]];
	[self replaceToken:@"[nrb]" inString:outputString withString:[self stringForValue:(netdata.packetsInBytes / interval)]];
	[self replaceToken:@"[nrp]" inString:outputString withString:[self stringForValue:peakIn]];
	//NSLog(@"MainController: drawNetworkInfo: peakPacketsInBytes = %llu, interval = %f, peakIn = %f", peakPacketsInBytes, interval, peakIn);
	
	[self replaceToken:@"[nsc]" inString:outputString withString:[NSString stringWithFormat:@"%llu",netdata.packetsOut]];
	[self replaceToken:@"[nsb]" inString:outputString withString:[self stringForValue:(netdata.packetsOutBytes / interval)]];
	[self replaceToken:@"[nsp]" inString:outputString withString:[self stringForValue:peakOut]];
	//NSLog(@"MainController: drawNetworkInfo: peakPacketsOutBytes = %llu, interval = %f, peakOut = %f", peakPacketsOutBytes, interval, peakOut);

	[self replaceToken:@"[nrbb]" inString:outputString withString:[self stringForValue:((netdata.packetsInBytes / interval) * 8) powerOf10:YES withBytes:NO]];
	[self replaceToken:@"[nrbp]" inString:outputString withString:[self stringForValue:(peakIn * 8) powerOf10:YES withBytes:NO]];

	[self replaceToken:@"[nsbb]" inString:outputString withString:[self stringForValue:((netdata.packetsOutBytes / interval) * 8) powerOf10:YES withBytes:NO]];
	[self replaceToken:@"[nsbp]" inString:outputString withString:[self stringForValue:(peakOut * 8) powerOf10:YES withBytes:NO]];

	[networkInfo startIterate];
	for (x = 0; [networkInfo getNext:&netdata]; x++)
	{
		inSum += netdata.packetsInBytes;
		inCount += 1;

		outSum += netdata.packetsOutBytes;
		outCount += 1;
	}
	inAverage = inSum / (double) inCount;
	outAverage = outSum / (double) outCount;

	inPerSecond = inAverage / interval;
	outPerSecond = outAverage / interval;

	[self replaceToken:@"[nra]" inString:outputString withString:[self stringForValue:inPerSecond]];
	[self replaceToken:@"[nsa]" inString:outputString withString:[self stringForValue:outPerSecond]];

	[self replaceToken:@"[nrba]" inString:outputString withString:[self stringForValue:(inPerSecond * 8) powerOf10:YES withBytes:NO]];
	[self replaceToken:@"[nsba]" inString:outputString withString:[self stringForValue:(outPerSecond * 8) powerOf10:YES withBytes:NO]];

	if (gethostname(hostname, 1024) < 0)
	{
		perror("gethostname failed");
	}
	[self replaceToken:@"[hn]" inString:outputString withString:[NSString stringWithUTF8String:hostname]];


	if (index == 1)
	{
		// in received
		[self highlightToken:@"[nr]" ofAttributedString:output inString:outputString];
		[self highlightToken:@"[nrb]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[nr]" inString:outputString withString:marker];
		[self replaceToken:@"[ns]" inString:outputString withString:blank];

		[self replaceToken:@"[nrb]" inString:outputString withString:marker];
		[self replaceToken:@"[nsb]" inString:outputString withString:blank];
	}
	else if (index == 2)
	{
		// in sent
		[self highlightToken:@"[ns]" ofAttributedString:output inString:outputString];
		[self highlightToken:@"[nsb]" ofAttributedString:output inString:outputString];

		[self replaceToken:@"[nr]" inString:outputString withString:blank];
		[self replaceToken:@"[ns]" inString:outputString withString:marker];

		[self replaceToken:@"[nrb]" inString:outputString withString:blank];
		[self replaceToken:@"[nsb]" inString:outputString withString:marker];
	}

	NSMutableString *interfaceList = [NSMutableString stringWithString:@""];

	{
		SCDynamicStoreRef  dynRef = SCDynamicStoreCreate(kCFAllocatorSystemDefault, (CFStringRef)@"iPulse", NULL, NULL);
		
		// Get all available interfaces IPv4 addresses
		NSArray *interfaceArray = (NSArray *)SCDynamicStoreCopyKeyList(dynRef,(CFStringRef)@"State:/Network/Interface/..*/IPv4");
		NSEnumerator *interfaceEnumerator = [interfaceArray objectEnumerator];
		NSString *interfacePath;
		while (interfacePath = [interfaceEnumerator nextObject])
		{ 
			NSDictionary *interfaceEntry = (NSDictionary *)SCDynamicStoreCopyValue(dynRef,(CFStringRef)interfacePath); 
			//NSLog(@"interfaceEntry = %@", interfaceEntry);
			
			NSString *interfaceName = [[interfacePath stringByDeletingLastPathComponent] lastPathComponent];

			NSArray *addressArray = [interfaceEntry objectForKey:@"Addresses"];

			BOOL firstAddress = YES;
			NSEnumerator *addressEnumerator = [addressArray objectEnumerator];
			NSString *address;
			while (address = [addressEnumerator nextObject])
			{
				// output the interface name and IP addresses
				if (firstAddress)
				{
					//[interfaceList appendString:[NSString stringWithFormat:@"%@:\t%@", interfaceName, @"999.999.999.999"]];
					[interfaceList appendString:[NSString stringWithFormat:@"%@:\t%@", interfaceName, address]];
				}
				else
				{
					[interfaceList appendString:[NSString stringWithFormat:@"\t%@", address]];
				}
				
				// dig around in the IO registry for the MAC address and link speed
				if (firstAddress)
				{
					kern_return_t kernResult; 
					mach_port_t masterPort;
					CFMutableDictionaryRef classesToMatch;

					kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
					if (KERN_SUCCESS != kernResult)
					{
						NSLog(@"MainController: drawNetworkInfo: IOMasterPort returned %d\n", kernResult);
					}

					// find ethernet interface using BSD name
					classesToMatch = IOBSDNameMatching(masterPort, 0, [interfaceName UTF8String]);

					if (classesToMatch == NULL)
					{
						NSLog(@"MainController: drawNetworkInfo: IOServiceMatching returned a NULL dictionary.\n");
					}
					else
					{
						io_iterator_t matchingServices;

						kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &matchingServices);    
						if (kernResult != KERN_SUCCESS)
						{
							NSLog(@"MainController: drawNetworkInfo:: IOServiceGetMatchingServices returned %d\n", kernResult);
						}
					
						io_object_t service;
						while ((service = IOIteratorNext(matchingServices)))
						{
							// found interface
							{
								// IONetworkControllers can't be found directly by the IOServiceGetMatchingServices call, 
								// since they are hardware nubs and do not participate in driver matching. In other words,
								// registerService() is never called on them. So we've found the IONetworkInterface and will 
								// get its parent controller by asking for it specifically.
								
								io_object_t controllerService;
								kernResult = IORegistryEntryGetParentEntry(service, kIOServicePlane, &controllerService);
								if (kernResult == KERN_SUCCESS)
								{
									CFTypeRef macAddress = IORegistryEntryCreateCFProperty(controllerService, CFSTR(kIOMACAddress), kCFAllocatorDefault, 0);
									if (macAddress)
									{
										unsigned char *data = (unsigned char *)[(NSData *)macAddress bytes];
										//[interfaceList appendString:[NSString stringWithFormat:@"\t99:99:99:99:99:99"]];
										[interfaceList appendString:[NSString stringWithFormat:@"\t%02x:%02x:%02x:%02x:%02x:%02x", data[0], data[1], data[2], data[3], data[4], data[5]]];
										CFRelease(macAddress);
									}
									else
									{
										[interfaceList appendString:[NSString stringWithFormat:@"\t%@", NSLocalizedString(@"NotAvailableAbbr", nil)]];
									}
									
									CFTypeRef linkSpeed = IORegistryEntryCreateCFProperty(controllerService, CFSTR(kIOLinkSpeed), kCFAllocatorDefault, 0);
									if (linkSpeed)
									{
										float speed = [(NSNumber *)linkSpeed floatValue];

										if (speed > 0.0)
										{
											[interfaceList appendString:[NSString stringWithFormat:@"\t%@%@", [self stringForValue:speed powerOf10:YES withBytes:NO withDecimal:NO], NSLocalizedString(@"BitAbbr", nil)]];
										}
										else
										{
											[interfaceList appendString:[NSString stringWithFormat:@"\t%@", NSLocalizedString(@"Dash", nil)]];
										}

										CFRelease(linkSpeed);
									}
									else
									{
										[interfaceList appendString:[NSString stringWithFormat:@"\t%@", NSLocalizedString(@"NotAvailableAbbr", nil)]];
									}
							
									IOObjectRelease(controllerService);
								}
							}

							IOObjectRelease(service);

							IOObjectRelease(matchingServices);
						}
					}

					mach_port_deallocate(mach_task_self(), masterPort);
				}

				[interfaceList appendString:@"\n"];
			}

			[interfaceEntry release];
		} 

		[interfaceArray release];
		
		CFRelease(dynRef);
	}

	[self replaceToken:@"[il]" inString:outputString withString:interfaceList];

	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

- (void)drawNetworkStatusAt:(StatusType)statusType
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSColor *leftColor;
	NSColor *rightColor;
	NSColor *alertColor;
	PositionType leftPosition;
	PositionType rightPosition;
	BOOL fadeAll;	
	[self generateParametersFor:statusType leftColor:&leftColor rightColor:&rightColor alertColor:&alertColor leftPosition:&leftPosition rightPosition:&rightPosition fadeAll:&fadeAll];

	float iy, oy;
	NetData netdata;
	int x;

	float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

	int scaleType = [defaults integerForKey:NETWORK_SCALE_KEY];
	float peakIn = (peakPacketsInBytes / interval);
	float scaleIn = [self computeScaleForGauge:scaleType withPeak:peakIn];
	float peakOut = (peakPacketsOutBytes / interval);
	float scaleOut = [self computeScaleForGauge:scaleType withPeak:peakOut];
	
	if (fadeAll)
	{
		float alphaIn = [leftColor alphaComponent];
		float transparencyIn;
		float alphaOut = [rightColor alphaComponent];
		float transparencyOut;

		BOOL alertIn = NO;
		BOOL alertOut = NO;
		
		[networkInfo startIterate];
		for (x = 0; [networkInfo getNext:&netdata]; x++)
		{
			transparencyIn = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaIn;
			transparencyOut = ((float)(x + 1) / (float)SAMPLE_SIZE) * alphaOut;

			iy = [self scaleValueForGauge:(netdata.packetsInBytes / interval) scaleType:scaleType scale:scaleIn];
			oy = [self scaleValueForGauge:(netdata.packetsOutBytes / interval) scaleType:scaleType scale:scaleOut];

			if (x == (SAMPLE_SIZE - 1) && iy >= statusAlertThreshold)
			{
				alertIn = YES;
			}
			if (x == (SAMPLE_SIZE - 1) && oy >= statusAlertThreshold)
			{
				alertOut = YES;
			}

			[self drawStatusBarValue:iy atPosition:leftPosition withColor:[leftColor colorWithAlphaComponent:transparencyIn]];
			[self drawStatusBarValue:oy atPosition:rightPosition withColor:[rightColor colorWithAlphaComponent:transparencyOut]];
		}
		if (alertIn)
		{
			[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
		}
		if (alertOut)
		{
			[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
		}
	}
	else
	{
		[networkInfo getCurrent:&netdata];

		iy = [self scaleValueForGauge:(netdata.packetsInBytes / interval) scaleType:scaleType scale:scaleIn];
		oy = [self scaleValueForGauge:(netdata.packetsOutBytes / interval) scaleType:scaleType scale:scaleOut];

		if (iy > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:leftColor];
			if (iy >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:leftPosition withColor:alertColor];
			}
		}
		if (oy > 0.0)
		{
			[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:rightColor];
			if (oy >= statusAlertThreshold)
			{
				[self drawStatusBarValue:1.0 atPosition:rightPosition withColor:alertColor];
			}
		}
	}
}

#pragma mark -

- (BOOL)inClockGauge:(GraphPoint)atPoint
{
	int result = 0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL alwaysHover = [defaults boolForKey:APPLICATION_ALWAYS_HOVER_TIME_KEY];

	BOOL checkPosition = YES;
	if (! alwaysHover)
	{
		checkPosition = ([defaults integerForKey:TIME_DATE_STYLE_KEY] != 0); // 0 = no date or time indicator
	}
	
	if (checkPosition)
	{
		if (atPoint.radius > 0.75 && atPoint.radius < 1.0)
		{
			if (atPoint.angle < 100.0 && atPoint.angle > 80.0)
			{
				result = 1;
			}
		}
	}

	return (result);
}


// maximum number of slots in a month array (6 weeks * 7 days)
#define MAX_DAYS 42
// empty slot in month array
#define DAY_EMPTY -1

// compute leap year, 0 = leap year, 1 = not leap year
#define LEAP_YEAR(yr) ((!((yr) % 4) && ((yr) % 100)) || !((yr) % 400))

// number of centuries since 1700, not inclusive
#define CENTURIES_SINCE_1700(yr) ((yr) / 100 - 17)

// number of centuries since 1700 whose modulo of 400 is 0
#define QUAD_CENTURIES_SINCE_1700(yr) (((yr) - 1600) / 400)

/* number of leap years between year 1 and this year, not inclusive */
#define LEAP_YEARS_SINCE_YEAR_1(yr) ((yr) / 4 - CENTURIES_SINCE_1700(yr) + QUAD_CENTURIES_SINCE_1700(yr))


static int daysInMonth[2][12] = {
	{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31},
	{31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31},
};

int dayInYear(int day, int month, int year)
{
	int result = 0;
	int leap = LEAP_YEAR(year);
	int i;
	for (i = 0; i < (month - 1); i++)
	{
		day += daysInMonth[leap][i];
	}
	
	result += day;
	
	return (result);
}

int dayInWeek(int day, int month, int year)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	long temp = (long)(year - 1) * 365 + LEAP_YEARS_SINCE_YEAR_1(year - 1) + dayInYear(day, month, year);
	if ([defaults boolForKey:TIME_SHOW_WEEK_KEY])
	{
		temp = temp - 1;
	}
	
	return (((temp - 1 + 6) - 11) % 7); // 6 = Saturday, Jan 1, Year 1; 11 = correction for Gregorian reformation
}

- (NSString *)computeCalendar
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	struct tm *nowTime = localtime(&now);
	int monthArray[MAX_DAYS];
	
	int year = nowTime->tm_year + 1900;
	int month = nowTime->tm_mon + 1;
	int day = nowTime->tm_mday;
	
#if 0
	// TESTING
	year = 2003;
	month = (nowTime->tm_sec / 5) + 1;
#endif

	int i;
	for (i = 0; i < MAX_DAYS; i++)
	{
		monthArray[i] = DAY_EMPTY;
	}

	int dm = daysInMonth[LEAP_YEAR(year)][month - 1];
	int dw = dayInWeek(1, month, year);
	int di = 1;
	while (dm--) // from the days when people did optimizations rather than compilers
	{
		monthArray[dw++] = di++;
	}

	NSMutableString *output = [NSMutableString string];

	// [output appendFormat:@"%d/%d/%d\n", month, day, year]; // TESTING

	int row;
	int col;
	for (row = 0; row < 6; row++)
	{
		int firstIndex = (row * 7) + 0;
		int firstDay = monthArray[firstIndex];
		int lastIndex = (row * 7) + 6;
		int lastDay = monthArray[lastIndex];

		if (firstDay == DAY_EMPTY && lastDay != DAY_EMPTY)
		{
			firstDay = 1;
		}		
		if (lastDay == DAY_EMPTY && firstDay != DAY_EMPTY)
		{
			lastDay = daysInMonth[LEAP_YEAR(year)][month - 1];
		}
		
		if (day >= firstDay && day <= lastDay)
		{
			[output appendString:@"\t[cw]"]; // current day is in this week
		}
		else
		{
			[output appendString:@"\t"];
		}
		for (col = 0; col < 7; col++)
		{
			int dayIndex = (row * 7) + col;
			if (monthArray[dayIndex] == DAY_EMPTY)
			{
				[output appendString:@"\t"];
			}
			else
			{
				if (monthArray[dayIndex] == day)
				{
					[output appendFormat:@"\t{%d}", monthArray[dayIndex]]; // add highlight markers
				}
				else
				{
					[output appendFormat:@"\t%d", monthArray[dayIndex]];
				}
			}
		}
		if ([defaults boolForKey:TIME_SHOW_WEEK_KEY])
		{
			int firstDayInYear = dayInWeek(1, 1, year);
			int dayOffset = firstDayInYear - 1;
			int weekOffset = 0;
			if (firstDayInYear <= 3)
			{
				// four or more days in the first week
				weekOffset = 1;
			}

			int dayIndex = (row * 7);
			if (monthArray[dayIndex] == DAY_EMPTY && monthArray[dayIndex + 6] == DAY_EMPTY)
			{
				[output appendString:@"\t"];
			}
			else
			{
				firstDay = monthArray[dayIndex];
				if (firstDay == DAY_EMPTY)
				{
					firstDay = 1;
				}
				int yearWeek = ((dayInYear(firstDay, month, year) + dayOffset) / 7) + weekOffset;
				if (yearWeek == 0)
				{
					[output appendFormat:@"\t"];
				}
				else
				{
					[output appendFormat:@"\t(%02d)", yearWeek];
				}
			}
		}
		if (row < 5)
		{
			[output appendString:@"\n"];
		}
	}
	return (output);
}

- (void)drawClockInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSString *marker = NSLocalizedString(@">", nil);
	
	if (! clockInfoString)
	{
		clockInfoString = [self attributedStringForFile:@"Clock.rtf"];
		[clockInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:clockInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];

	[self replaceFormatting:output inString:outputString];

	// compute UTC
	struct tm *gmtTime = gmtime(&now);
	
	// compute Julian date
	double julianDate = jtime(gmtTime);
	
	// compute moon phase
	double pphase;	// illuminated fraction
	double mage;	// age of moon in days
	{
		double dist;		// distance in kilometres
		double angdia;	// angular diameter in degrees
		double sudist;	// distance to sun
		double suangdia;	// sun's angular diameter
		phase(julianDate, &pphase, &mage, &dist, &angdia, &sudist, &suangdia);
	}

	// compute uptime
	float daysUptime;
	float hoursUptime;
	{
		time_t uptime;
		int mib[2];
		size_t size;
		struct timeval boottime;

		mib[0] = CTL_KERN;
		mib[1] = KERN_BOOTTIME;
		size = sizeof(boottime);
		if (sysctl(mib, 2, &boottime, &size, NULL, 0) != -1 && boottime.tv_sec != 0)
		{
			float daysUptimeTotal;
			
			uptime = now - boottime.tv_sec;
			daysUptimeTotal = (float) uptime / 60.0 / 60.0 / 24.0;
			daysUptime = floor(daysUptimeTotal);
			hoursUptime = 24.0 * (daysUptimeTotal - daysUptime);
		}
		else
		{
			NSLog(@"MainController: drawClockInfo: Can't compute uptime.");
			daysUptime = 0.0;
			hoursUptime = 0.0;
		}
	}
	
	// compute moon name
	NSString *moonPhase;
	{
		if (mage < (synmonth / 2.0))
		{
			// first half
			if (pphase >= 0.0 && pphase < 0.05)
			{
				moonPhase = NSLocalizedString(@"NewMoon", nil);
			}
			else if (pphase >= 0.05 && pphase < 0.45)
			{
				moonPhase =  NSLocalizedString(@"WaxingCrescent", nil);
			}
			else if (pphase >= 0.45 && pphase < 0.55)
			{
				moonPhase =  NSLocalizedString(@"FirstQuarter", nil);
			}
			else if (pphase >= 0.55 && pphase < 0.95)
			{
				moonPhase =  NSLocalizedString(@"WaxingGibbous", nil);
			}
			else
			{
				moonPhase =  NSLocalizedString(@"FullMoon", nil);
			}
		}
		else
		{
			// second half
			if (pphase >= 0.0 && pphase < 0.05)
			{
				moonPhase =  NSLocalizedString(@"NewMoon", nil);
			}
			else if (pphase >= 0.05 && pphase < 0.45)
			{
				moonPhase =  NSLocalizedString(@"WaningCrescent", nil);
			}
			else if (pphase >= 0.45 && pphase < 0.55)
			{
				moonPhase =  NSLocalizedString(@"LastQuarter", nil);
			}
			else if (pphase >= 0.55 && pphase < 0.95)
			{
				moonPhase =  NSLocalizedString(@"WaningGibbous", nil);
			}
			else
			{
				moonPhase =  NSLocalizedString(@"FullMoon", nil);
			}
		}
	}

	// compute local time
	struct tm *nowTime = localtime(&now);

	NSLocale *locale = [NSLocale currentLocale];

	NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[dateFormatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"yyyyMd" options:0 locale:locale]];
	NSDateFormatter *timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[timeFormatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"hmmss a" options:0 locale:locale]];
	NSDateFormatter *zoneFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[zoneFormatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"ZZZZ" options:0 locale:locale]];
	
	// compute now
	{
		NSTimeZone *timeZone = [NSTimeZone localTimeZone];
		NSDate *nowDate = [NSDate date];
		
		NSString *calendarDate = [dateFormatter stringFromDate:nowDate];
		NSString *calendarTime = [timeFormatter stringFromDate:nowDate];
		NSString *calendarZone = [zoneFormatter stringFromDate:nowDate];
		
		NSString *timeZoneInfo = [NSString stringWithFormat:@"%@: %@ (%@)", calendarZone, [timeZone name], [timeZone abbreviation]];
		
		[self replaceToken:@"[ct]" inString:outputString withString:calendarTime];
		[self replaceToken:@"[cd]" inString:outputString withString:calendarDate];
		[self replaceToken:@"[cz]" inString:outputString withString:timeZoneInfo];
	}
	
	// compute month name
	{
		NSArray *monthNames = [dateFormatter monthSymbols];
		[self replaceToken:@"[cn]" inString:outputString withString:[NSString stringWithFormat:@"%@ %d", [monthNames objectAtIndex:nowTime->tm_mon], nowTime->tm_year + 1900]];
	}

	[self replaceToken:@"[ud]" inString:outputString withString:[NSString stringWithFormat:@"%.0f", daysUptime]];
	[self replaceToken:@"[uh]" inString:outputString withString:[NSString stringWithFormat:@"%.1f", hoursUptime]];

	[self replaceToken:@"[jd]" inString:outputString withString:[NSString stringWithFormat:@"%.5f", julianDate]];

	[self replaceToken:@"[mp]" inString:outputString withString:[self stringForPercentage:pphase withPercent:YES]];
	[self replaceToken:@"[ma]" inString:outputString withString:[NSString stringWithFormat:@"%.1f", mage]];
	[self replaceToken:@"[mn]" inString:outputString withString:moonPhase];
	
	
	{
		NSMutableString *output = [NSMutableString string];
		int col;
		
		NSArray *dayNames = [dateFormatter shortWeekdaySymbols];

		[output appendString:@"\t"];

		if ([defaults boolForKey:TIME_SHOW_WEEK_KEY])
		{
			for (col = 1; col < 7; col++)
			{
				[output appendFormat:@"\t%@", [dayNames objectAtIndex:col]];
			}
			[output appendFormat:@"\t%@", [dayNames objectAtIndex:0]];
		}
		else
		{
			for (col = 0; col < 7; col++)
			{
				[output appendFormat:@"\t%@", [dayNames objectAtIndex:col]];
			}
		}

		[self replaceToken:@"[ch]" inString:outputString withString:output];
	}


	[self replaceToken:@"[cm]" inString:outputString withString:[self computeCalendar]];


	NSColor *highlightColor = [Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_HIGHLIGHT_COLOR_KEY]];
	[self replaceFormattingColor:output inString:outputString withColor:highlightColor];
	
	[self highlightToken:@"[cw]" ofAttributedString:output inString:outputString];
	[self replaceToken:@"[cw]" inString:outputString withString:marker];

	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

- (void)drawClockTimeGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	struct tm *nowTime = localtime(&now);

	if ([defaults boolForKey:TIME_RING_KEY])
	{
		if (nowTime->tm_hour != lastHour && nowTime->tm_min == 0)
		{
			[[NSSound soundNamed:[defaults stringForKey:TIME_RING_SOUND_KEY]] play];
	
			lastHour = nowTime->tm_hour;
		}
	}

	if ([defaults boolForKey:TIME_SHOW_GAUGE_KEY])
	{
		NSColor *timeHandsColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_HANDS_COLOR_KEY]];
		NSColor *timeSecondsColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_SECONDS_COLOR_KEY]];

		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
	
		float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;
	
		const double sliceMinuteAngle = 360.0 / 60.0;
		double sliceHourAngle;
		double sliceHourOffset;
	
		double timeAngle;
		NSPoint timePoint;
				
		double secondRadius = (GRAPH_SIZE/2.0) - (GRAPH_SIZE/32.0);
		double minuteRadius = (GRAPH_SIZE/2.0) - (GRAPH_SIZE/16.0);
		double hourRadius = (GRAPH_SIZE/2.0) - (GRAPH_SIZE/8.0)  - (GRAPH_SIZE/16.0); // - (GRAPH_SIZE/32.0);
	
		if (interval <= 1.0)
		{
			// seconds
			timeAngle = 90.0 - (nowTime->tm_sec * sliceMinuteAngle);
			
			timePoint = [self pointAtCenter:processorPoint atAngle:timeAngle atRadius:secondRadius];
	
			[timeSecondsColor set];
			[self drawValue:(GRAPH_SIZE / 32.0) atPoint:timePoint];		
		}
		
		// hours
		if (! [defaults boolForKey:TIME_USE_24_HOUR_KEY])
		{
			// normal
			sliceHourOffset = 90.0;
			sliceHourAngle = 360.0 / 12.0;
		}
		else
		{
			// 24 hour
			if ([defaults boolForKey:TIME_NOON_AT_TOP_KEY])
			{
				sliceHourOffset = 270.0;
			}
			else
			{
				sliceHourOffset = 90.0;
			}
			sliceHourAngle = 360.0 / 24.0;
		}
		timeAngle = sliceHourOffset - (((double)nowTime->tm_hour + ((double)nowTime->tm_min / 60.0)) * sliceHourAngle);
		
		timePoint = [self pointAtCenter:processorPoint atAngle:timeAngle atRadius:hourRadius];
	
		[timeHandsColor set];
	
		if ([defaults boolForKey:TIME_TRADITIONAL_KEY])
		{
			NSBezierPath *path = [NSBezierPath bezierPath];
		
			[path setLineWidth:3.0];
			[path setLineCapStyle:NSRoundLineCapStyle];
			[path moveToPoint:processorPoint];
			[path lineToPoint:timePoint];
			[path stroke];
		}
		else
		{
			[self drawValue:(GRAPH_SIZE / 20.0) atPoint:timePoint];
		}
	
		// minutes
		timeAngle = 90.0 - (((double)nowTime->tm_min + ((double)nowTime->tm_sec / 60.0)) * sliceMinuteAngle);
		
		timePoint = [self pointAtCenter:processorPoint atAngle:timeAngle atRadius:minuteRadius];
		
		[timeHandsColor set];
		if ([defaults boolForKey:TIME_TRADITIONAL_KEY])
		{
			NSBezierPath *path = [NSBezierPath bezierPath];
		
			[path setLineWidth:3.0];
			[path setLineCapStyle:NSRoundLineCapStyle];
			[path moveToPoint:processorPoint];
			[path lineToPoint:timePoint];
			[path stroke];
		}
		else
		{
			[self drawValue:(GRAPH_SIZE / 32.0) atPoint:timePoint];		
		}
	}
}

- (void)drawMoonPhase
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSColor *dateBackgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_BACKGROUND_COLOR_KEY]];
	NSColor *dateForegroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_FOREGROUND_COLOR_KEY]];

#if OPTION_MOON_TEST
	struct tm *nowTime = localtime(&now);
	double pphase;
	if (nowTime->tm_sec < 30)
	{
		pphase = ((float)nowTime->tm_sec  / 30.0);
	}
	else
	{
		pphase = 1.0 - ((float)(nowTime->tm_sec - 30) / 30.0);
	}
	double mage = ((float)nowTime->tm_sec  / 60.0) * synmonth;
#else
	// compute UTC
	struct tm *utcTime = gmtime(&now);
	
	// compute Julian date
	double julianDate = jtime(utcTime);

	// compute moon phase
	double pphase;	// illuminated fraction
	double mage;	// age of moon in days
	{
		double dist;		// distance in kilometres
		double angdia;	// angular diameter in degrees
		double sudist;	// distance to sun
		double suangdia;	// sun's angular diameter
		phase(julianDate, &pphase, &mage, &dist, &angdia, &sudist, &suangdia);
	}
#endif
	
	{
		NSPoint datePoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE-(GRAPH_SIZE/16.0));
		NSRect fullRect = NSMakeRect(datePoint.x - (GRAPH_SIZE/16.0), datePoint.y - (GRAPH_SIZE/16.0), (GRAPH_SIZE/8.0), (GRAPH_SIZE/8.0));
		NSRect partialRect;

		float offset;
		if (mage < (synmonth / 2.0))
		{
			offset = ((GRAPH_SIZE/16.0) * 2.0) - ((pphase * 2.0) * (GRAPH_SIZE/16.0));
		}
		else
		{
			offset = (pphase * 2.0) * (GRAPH_SIZE/16.0);
		}

		partialRect.origin.x = fullRect.origin.x + offset;
		partialRect.origin.y = fullRect.origin.y;
		partialRect.size.width = fullRect.size.width - (offset * 2.0);
		partialRect.size.height = fullRect.size.height;

		// draw background
		{
			NSBezierPath *path = [NSBezierPath bezierPath];

			[dateBackgroundColor set];
			[path moveToPoint:datePoint];
			[path appendBezierPathWithOvalInRect:fullRect];
			[path closePath];
			[path fill];
		}
		
		// draw moon
		{
			NSPoint p, p1, p2;
			double originx = partialRect.origin.x;
			double originy = partialRect.origin.y;
			double width = partialRect.size.width;
			double height = partialRect.size.height;
			double hdiff = width / 2 * KAPPA;
			double vdiff = height / 2 * KAPPA;

			NSBezierPath *path = [NSBezierPath bezierPath];

			//NSLog(@"MainController: drawMoonPhase: pphase = %6.4f, mage = %6.4f, offset = %6.4f", pphase, mage, offset);

			[dateForegroundColor set];

			[path moveToPoint:NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE)];

			p = NSMakePoint(originx, originy + height / 2);
			p1 = NSMakePoint(originx + width / 2 - hdiff, originy + height);
			p2 = NSMakePoint(originx, originy + height / 2 + vdiff);
			[path curveToPoint: p controlPoint1: p1 controlPoint2: p2];
			
			p = NSMakePoint(originx + width / 2, originy);
			p1 = NSMakePoint(originx, originy + height / 2 - vdiff);
			p2 = NSMakePoint(originx + width / 2 - hdiff, originy);
			[path curveToPoint: p controlPoint1: p1 controlPoint2: p2];	

			if (mage < (synmonth / 2.0))
			{
				// first half
				[path appendBezierPathWithArcWithCenter:datePoint radius:(GRAPH_SIZE/16.0) startAngle:270.0 endAngle:90.0 clockwise:NO];
			}
			else
			{
				// second half
				[path appendBezierPathWithArcWithCenter:datePoint radius:(GRAPH_SIZE/16.0) startAngle:270.0 endAngle:90.0 clockwise:YES];
			}

			[path fill];
		}
	}
}

- (void)drawClockDateGauge
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults integerForKey:TIME_DATE_STYLE_KEY]) // 0 = None
	{
		struct tm *nowTime = localtime(&now);

		NSPoint datePoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE-(GRAPH_SIZE/16.0)+1.0);
		NSPoint processorPoint = NSMakePoint(GRAPH_SIZE/2.0, GRAPH_SIZE/2.0);
		NSArray *names;
		NSString *string;
		
		NSColor *dateForegroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_FOREGROUND_COLOR_KEY]];
		NSColor *dateBackgroundColor = [Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_BACKGROUND_COLOR_KEY]];

		NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
		
		switch ([defaults integerForKey:TIME_DATE_STYLE_KEY])
		{
		default:
		case 1: // date
			string = [NSString stringWithFormat:@"%d", nowTime->tm_mday];

			[dateBackgroundColor set];
			[self drawValueAngleRoundedFrom:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0) to:(GRAPH_SIZE/2.0) atPoint:processorPoint startAngle:95.0 endAngle:85.0 clockwise:YES];
			[self drawTextPlain:string atPoint:datePoint withColor:dateForegroundColor];		
			break;
		case 2: // month & date
			names = [dateFormatter shortMonthSymbols];
#if 0 // TESTING
			string = @"||||||||||";
#else
			string = [NSString stringWithFormat:@"%@ %d", [names objectAtIndex:nowTime->tm_mon], nowTime->tm_mday];
#endif			
			[dateBackgroundColor set];
			[self drawValueAngleRoundedFrom:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0) to:(GRAPH_SIZE/2.0) atPoint:processorPoint startAngle:112.0 endAngle:68.0 clockwise:YES];
			[self drawTextOnArc:string atPoint:processorPoint radius:((GRAPH_SIZE/2.0)-(GRAPH_SIZE/8.0)+1.0) angle:0.0];
			break;
		case 3: // day & date
			names = [dateFormatter shortWeekdaySymbols];
			string = [NSString stringWithFormat:@"%@ %d", [names objectAtIndex:nowTime->tm_wday], nowTime->tm_mday];

			[dateBackgroundColor set];
			[self drawValueAngleRoundedFrom:(GRAPH_SIZE/2.0 - GRAPH_SIZE/8.0) to:(GRAPH_SIZE/2.0) atPoint:processorPoint startAngle:112.0 endAngle:68.0 clockwise:YES];
			[self drawTextOnArc:string atPoint:processorPoint radius:((GRAPH_SIZE/2.0)-(GRAPH_SIZE/8.0)+1.0) angle:0.0];
			break;
		case 4: // phase of the moon
			[self drawMoonPhase];
			break;
		}
	}
}

#pragma mark -

- (void)setInfoLocation
{
	//NSLog(@"MainController: setInfoLocation");
	
	NSRect infoFrame = [infoWindow frame];
	NSRect windowFrame = [graphWindow frame];
	NSRect viewFrame = [graphView frame];
	NSRect newInfoFrame = NSZeroRect;
	NSRect screenFrame = [[graphWindow screen] frame];
	float offset = 8.0;
	NSPoint alignPoint;

	newInfoFrame.size.width = infoFrame.size.width; // INFO_WIDTH;
	newInfoFrame.size.height = infoFrame.size.height; // INFO_HEIGHT;

	if (NSMidX(windowFrame) < NSMidX(screenFrame))
	{
		// align on right
		float x = NSMaxX(viewFrame) + offset;
		if (NSMidY(windowFrame) < NSMidY(screenFrame))
		{
			// align on bottom
			alignPoint = NSMakePoint(x, NSMinY(viewFrame));
		}
		else
		{
			// align on top
			alignPoint = NSMakePoint(x, NSMaxY(viewFrame) - NSMaxY(newInfoFrame));
		}
	}
	else
	{
		// align on left
		float x = NSMinX(viewFrame) - NSWidth(newInfoFrame) - offset;
		if (NSMidY(windowFrame) < NSMidY(screenFrame))
		{
			// align on bottom
			alignPoint = NSMakePoint(x, NSMinY(viewFrame));
		}
		else
		{
			// align on top
			alignPoint = NSMakePoint(x, NSMaxY(viewFrame) - NSMaxY(newInfoFrame));
		}
	}
	newInfoFrame.origin = [graphWindow convertBaseToScreen:alignPoint];

	//NSLog(@"newInfoFrame = %@, graphWindow frame = %@", NSStringFromRect(newInfoFrame), NSStringFromRect([graphWindow frame]));

	[infoWindow setFrame:newInfoFrame display:NO animate:NO];
}


#if OPTION_RESIZE_INFO
- (void)setInfoSize:(NSString *)infoText
{
	NSRect infoFrame = [infoWindow frame];
	NSRect windowFrame = [graphWindow frame];
	NSRect viewFrame = [graphView frame];
	NSRect newInfoFrame;
	NSRect screenFrame = [[graphWindow screen] frame];
	float offset = 8.0;
	NSPoint alignPoint;

	NSSize size;
	// information size
	{
		NSMutableDictionary *fontAttrs;

		fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			[NSFont systemFontOfSize:11.0], NSFontAttributeName,
			[NSColor whiteColor], NSForegroundColorAttributeName,
			nil];

		size = [infoText sizeWithAttributes:fontAttrs];

		[fontAttrs release];
	}

	newInfoFrame.size.width = infoFrame.size.width; // INFO_WIDTH;
	newInfoFrame.size.height = size.height + (INFO_RADIUS * 2.0) + (INFO_OFFSET * 2);

	if (NSMidX(windowFrame) < NSMidX(screenFrame))
	{
		// align on right
		float x = NSMaxX(viewFrame) + offset;
		if (NSMidY(windowFrame) < NSMidY(screenFrame))
		{
			// align on bottom
			alignPoint = NSMakePoint(x, NSMinY(viewFrame));
		}
		else
		{
			// align on top
			alignPoint = NSMakePoint(x, NSMaxY(viewFrame) - NSMaxY(newInfoFrame));
		}
	}
	else
	{
		// align on left
		float x = NSMinX(viewFrame) - NSWidth(newInfoFrame) - offset;
		if (NSMidY(windowFrame) < NSMidY(screenFrame))
		{
			// align on bottom
			alignPoint = NSMakePoint(x, NSMinY(viewFrame));
		}
		else
		{
			// align on top
			alignPoint = NSMakePoint(x, NSMaxY(viewFrame) - NSMaxY(newInfoFrame));
		}
	}
	newInfoFrame.origin = [graphWindow convertBaseToScreen:alignPoint];

	//NSLog(@"newInfoFrame = %@, graphWindow frame = %@", NSStringFromRect(newInfoFrame), NSStringFromRect([graphWindow frame]));

	if (newInfoFrame.size.height != infoFrame.size.height)
	{
		[infoWindow setFrame:newInfoFrame display:YES animate:YES];
	}
	else
	{
		[infoView setNeedsDisplay:YES];
	}
}
#endif

- (void)updateInfo
{
#if OPTION_RESIZE_INFO
	int index;
	GraphPoint graphPoint = [graphView getGraphPoint];
	NSString *infoText; // TEMPORARY

	// create a string of text with the info
	infoText = [self drawTemperatureInfo:graphPoint withIndex:index];

	// resize info window to fit text
	[self setInfoSize:infoText];
#else
	[infoView setNeedsDisplay:YES];
#endif
}

- (void)drawInfoBackground
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSRect infoFrame = [infoView frame];
	float minX = NSMinX(infoFrame);
	float maxX = NSMaxX(infoFrame);
	float minY = NSMinY(infoFrame);
	float maxY = NSMaxY(infoFrame);
	NSBezierPath *path = [NSBezierPath bezierPath];

	// erase previous background
	[[[NSColor blackColor] colorWithAlphaComponent:0.0] set];
	NSRectFill(infoFrame);

	[[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_BACKGROUND_COLOR_KEY]] set];

	[path moveToPoint:NSMakePoint(minX + INFO_RADIUS, maxY)];
	
	[path lineToPoint:NSMakePoint(maxX - INFO_RADIUS, maxY)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(maxX - INFO_RADIUS, maxY - INFO_RADIUS) radius:INFO_RADIUS startAngle:90.0 endAngle:0.0 clockwise:YES];
	
	[path lineToPoint:NSMakePoint(maxX, maxY - INFO_RADIUS)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(maxX - INFO_RADIUS, minY + INFO_RADIUS) radius:INFO_RADIUS startAngle:360.0 endAngle:270.0 clockwise:YES];
	
	[path lineToPoint:NSMakePoint(minX + INFO_RADIUS, minY)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(minX + INFO_RADIUS, minY + INFO_RADIUS) radius:INFO_RADIUS startAngle:270.0 endAngle:180.0 clockwise:YES];
	
	[path lineToPoint:NSMakePoint(minX, maxY - INFO_RADIUS)];
	[path appendBezierPathWithArcWithCenter:NSMakePoint(minX + INFO_RADIUS, maxY - INFO_RADIUS) radius:INFO_RADIUS startAngle:180.0 endAngle:90.0 clockwise:YES];
	
	[path fill];
}

- (void)drawInfoTitle:(NSString *)text withImageName:(NSString *)imageName
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSRect infoFrame = [infoView frame];
	float minX = NSMinX(infoFrame);
	float maxX = NSMaxX(infoFrame);
	float maxY = NSMaxY(infoFrame);
	float baseY = maxY - INFO_OFFSET;

	// title bar
	{
		NSBezierPath *path = [NSBezierPath bezierPath];

		[[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_BACKGROUND_COLOR_KEY]] set];

		[path moveToPoint:NSMakePoint(minX + INFO_RADIUS, maxY)];
		
		[path lineToPoint:NSMakePoint(maxX - INFO_RADIUS, maxY)];
		[path appendBezierPathWithArcWithCenter:NSMakePoint(maxX - INFO_RADIUS, maxY - INFO_RADIUS) radius:INFO_RADIUS startAngle:90.0 endAngle:0.0 clockwise:YES];

		[path lineToPoint:NSMakePoint(maxX, maxY - (INFO_OFFSET * 2.0))];
		[path lineToPoint:NSMakePoint(minX, maxY - (INFO_OFFSET * 2.0))];

		[path lineToPoint:NSMakePoint(minX, maxY - INFO_RADIUS)];
		[path appendBezierPathWithArcWithCenter:NSMakePoint(minX + INFO_RADIUS, maxY - INFO_RADIUS) radius:INFO_RADIUS startAngle:180.0 endAngle:90.0 clockwise:YES];
		
		[path fill];
	}

	// title
	{
		// image
		{
			NSImage *titleImage = [NSImage imageNamed:imageName];
			NSSize titleSize = NSMakeSize(16.0, 16.0);
			NSRect titleRect = NSMakeRect(0.0, 0.0, 16.0, 16.0);
			[titleImage setScalesWhenResized:YES];
			[titleImage setSize:titleSize];
			[titleImage drawAtPoint:NSMakePoint(minX + INFO_OFFSET - 8.0,  baseY - 8.0) fromRect:titleRect operation:NSCompositeSourceOver fraction:1.0];
		}

		// text
		{
			NSMutableDictionary *fontAttrs;
			NSSize size;

			fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
				[NSFont systemFontOfSize:12.0], NSFontAttributeName,
				[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]], NSForegroundColorAttributeName,
				nil];

			size = [text sizeWithAttributes:fontAttrs];
			[text drawAtPoint:NSMakePoint(minX + (INFO_OFFSET * 2.0), baseY - (size.height / 2.0)) withAttributes:fontAttrs];

			[fontAttrs release];
		}

		// lock
		if (infoWindowIsLocked)
		{
			// get the lock image
			NSImage *lockImage = [NSImage imageNamed:@"Lock"];
			
			// create a new image that's the same size as the lock image
			NSSize size = [lockImage size];
			NSRect imageBounds = NSMakeRect(0, 0, size.width, size.height);    
			NSImage *newImage = [[NSImage alloc] initWithSize:size];
    
			// create a new image that uses the foreground color in opaque areas
			[newImage lockFocus];
			[lockImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
			[[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] set];
			NSRectFillUsingOperation(imageBounds, NSCompositeSourceAtop);
			[newImage unlockFocus];
			
			// draw the new image
			NSSize titleSize = NSMakeSize(16.0, 16.0);
			NSRect titleRect = NSMakeRect(0.0, 0.0, 16.0, 16.0);
			[newImage setScalesWhenResized:YES];
			[newImage setSize:titleSize];
			[newImage drawAtPoint:NSMakePoint(maxX - INFO_OFFSET - 8.0,  baseY - 8.0) fromRect:titleRect operation:NSCompositeSourceOver fraction:1.0];
			[newImage autorelease];
		}
	}
}

#pragma mark -

- (void)drawGeneralInfo:(GraphPoint)atPoint withIndex:(int)index
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if (! generalInfoString)
	{
		generalInfoString = [self attributedStringForFile:@"General.rtf"];
		[generalInfoString retain];
	}
	NSMutableAttributedString *output = [[[NSMutableAttributedString alloc] initWithAttributedString:generalInfoString] autorelease];

	[output addAttribute:NSForegroundColorAttributeName value:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]] range:NSMakeRange(0, [output length])];

	NSMutableString *outputString = [output mutableString];
	
	[self replaceFormatting:output inString:outputString];

	CFStringRef computerName = CSCopyMachineName();
	CFStringRef loginNameLong = CSCopyUserName(NO); // long name
	CFStringRef loginNameShort = CSCopyUserName(YES); // short name

	[self replaceToken:@"[cn]" inString:outputString withString:(NSString *)computerName];
	[self replaceToken:@"[ll]" inString:outputString withString:(NSString *)loginNameLong];
	[self replaceToken:@"[ls]" inString:outputString withString:(NSString *)loginNameShort];
	
	CFRelease(computerName);
	CFRelease(loginNameLong);
	CFRelease(loginNameShort);
	
	time_t runtime = now - startTime;
	float daysRuntimeTotal = (float) runtime / 60.0 / 60.0 / 24.0;
	float daysRuntime = floor(daysRuntimeTotal);
	float hoursRuntime = 24.0 * (daysRuntimeTotal - daysRuntime);
	
	[self replaceToken:@"[rd]" inString:outputString withString:[NSString stringWithFormat:@"%.0f", daysRuntime]];
	[self replaceToken:@"[rh]" inString:outputString withString:[NSString stringWithFormat:@"%.1f", hoursRuntime]];
	
	NSString *ignoringMouseState = nil;
	if ([defaults boolForKey:WINDOW_FLOATING_IGNORE_CLICK_KEY])
	{
		ignoringMouseState = NSLocalizedString(@"Yes", nil);
	}
	else
	{
		ignoringMouseState = NSLocalizedString(@"No", nil);
	}
	KeyCombo *toggleIgnoreMouseKeyCombo = [[HotKeyCenter sharedCenter] keyComboForName:HOTKEY_TOGGLE_IGNORE_MOUSE];
	NSString *ignoringMouse;
	if ([toggleIgnoreMouseKeyCombo isValid])
	{
		ignoringMouse = [NSString stringWithFormat:@"%@, %@ %@", ignoringMouseState, NSLocalizedString(@"Hotkey", nil), [toggleIgnoreMouseKeyCombo userDisplayRep]];
	}
	else
	{
		ignoringMouse = [NSString stringWithFormat:@"%@", ignoringMouseState];
	}
	[self replaceToken:@"[im]" inString:outputString withString:ignoringMouse];
	
	[self replaceToken:@"[rn]" inString:outputString withString:NSLocalizedString(@"Unregistered", nil)];
 
	[self replaceToken:@"[av]" inString:outputString withString:applicationVersion];
#ifdef __BIG_ENDIAN__
	NSString *platform = @"PowerPC";
#else
	NSString *platform = @"Intel";
#endif
	[self replaceToken:@"[os]" inString:outputString withString:[NSString stringWithFormat:@"%@%d.%d.%d (%@)", NSLocalizedString(@"Version", nil), majorVersion, minorVersion, updateVersion, platform]];
	
	{
		NSRect infoFrame = [infoView frame];
		float minX = NSMinX(infoFrame);
		float maxY = NSMaxY(infoFrame);
		float baseY = maxY - (INFO_OFFSET * 2.5);

		NSSize size = [output size];
		[output drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height)];
	}
}

#pragma mark -

- (void)drawInfo
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:WINDOW_SHOW_INFO_KEY])
	{
		int index;
		GraphPoint graphPoint;
		
		if (infoWindowIsLocked)
		{
			graphPoint = lockedGraphPoint;
		}
		else
		{
			//NSLog(@"Updating lockedGraphPoint...");
			
			graphPoint = [graphView getGraphPoint];
			lockedGraphPoint = graphPoint;
		}
		
		NSString *titleImageName;
		NSString *titleText;
		NSString *infoText = nil; // TEMPORARY
	
		// main background
		[self drawInfoBackground];
	
		// get title variables
		if ((index = [self inProcessorGauge:graphPoint]))
		{
			titleImageName = @"CPU.icns";
			titleText = NSLocalizedString(@"CpuLabel", nil);
			[self drawProcessorInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inDiskGauge:graphPoint]))
		{
			titleImageName = @"Disk.icns";
			titleText = NSLocalizedString(@"DiskLabel", nil);
			[self drawDiskInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inMemoryGauge:graphPoint]))
		{
			titleImageName = @"Memory.icns";
			titleText = NSLocalizedString(@"MemoryLabel", nil);
			[self drawMemoryInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inClockGauge:graphPoint]))
		{
			titleImageName = @"Clock.icns";
			titleText = NSLocalizedString(@"ClockLabel", nil);
			[self drawClockInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inMobilityGauge:graphPoint]))
		{
			titleImageName = @"Mobility.icns";
			titleText = NSLocalizedString(@"MobilityLabel", nil);
			[self drawMobilityInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inSwappingGauge:graphPoint]))
		{
			titleImageName = @"Memory.icns";
			titleText = NSLocalizedString(@"SwappingLabel", nil);
			[self drawSwappingInfo:graphPoint withIndex:index];
		}
		else if ((index = [self inNetworkGauge:graphPoint]))
		{
			titleImageName = @"Network.icns";
			titleText =NSLocalizedString(@"NetworkLabel", nil);
			[self drawNetworkInfo:graphPoint withIndex:index];
		}
		else
		{
			titleImageName = @"Info.icns";
			titleText = NSLocalizedString(@"GeneralLabel", nil);
			[self drawGeneralInfo:graphPoint withIndex:0];
		}
	
	
		// title
		[self drawInfoTitle:titleText withImageName:titleImageName];
	
		// information
		if (infoText != nil)
		{
			NSRect infoFrame = [infoView frame];
			float minX = NSMinX(infoFrame);
			float maxY = NSMaxY(infoFrame);
			float baseY = maxY - (INFO_OFFSET * 2.5);
	
			NSMutableDictionary *fontAttrs;
			NSSize size;
	
			fontAttrs = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
				[NSFont systemFontOfSize:10.0], NSFontAttributeName,
				[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]], NSForegroundColorAttributeName,
				nil];
	
			size = [infoText sizeWithAttributes:fontAttrs];
			[infoText drawAtPoint:NSMakePoint(minX + INFO_OFFSET, baseY - size.height) withAttributes:fontAttrs];
	
			[fontAttrs release];
		}
	}
	else
	{
		// erase window
		[[[NSColor blackColor] colorWithAlphaComponent:0.0] set];
		NSRectFill([infoView frame]);
	}
}

#pragma mark -

#if OPTION_INCLUDE_MATRIX_ORBITAL	

char *LogBytes(unsigned char *bytes, size_t count)
{
	static char     buf[2048];
	char            *ptr = buf;
	unsigned char             i;
	size_t pos;
	
	*ptr = '\0';

	for (pos = 0; pos < count; pos++)
	{
		i = bytes[pos];
		(void)sprintf(ptr, "0x%02x ", i);
		ptr += 5;
	}
	*ptr = '\0';

	return buf;
}

Boolean SendBytes(int fileDescriptor, unsigned char *bytes, size_t count)
{
	Boolean result = false;

	if (fileDescriptor != -1)
	{
		ssize_t numBytes = write(fileDescriptor, bytes, count);
		if (numBytes == -1)
		{
			NSLog(@"SendBytes: Error writing to display - %s (%d)", strerror(errno), errno);
		}
		else {
//			NSLog(@"SendBytes: Wrote %ld bytes \"%s\"\n", numBytes, LogBytes(bytes, count));
			result = true;
		}
	}
	
	return (result);
}

Boolean SendString(int fileDescriptor, char *string)
{
	return (SendBytes(fileDescriptor, (unsigned char *)string, strlen(string)));
}


Boolean ExecuteBytes(int fileDescriptor, unsigned char *bytes, size_t count, unsigned char *buffer, int *bufferSize)
{
	Boolean result = false;
	
	bzero(buffer, *bufferSize);
	
	ssize_t bytesRead = 0;
	
	if (! SendBytes(fileDescriptor, bytes, count))
	{
		NSLog(@"ExecuteBytes: Error sending bytes to display");
	}
	else {
		// Read characters into our buffer until we get an error
		int retryCount = 5;
		unsigned char *bufferPtr = buffer;
		ssize_t numBytes = -1;
		while (numBytes != 0)
		{
			size_t bytesRemaining = *bufferSize - bytesRead;
			numBytes = read(fileDescriptor, bufferPtr, bytesRemaining);
//			NSLog(@"ExecuteBytes: numBytes = %ld, bytesRead = %ld, bytesRemaining = %ld, bufferPtr = 0x%x (0x%x)", numBytes, bytesRead, bytesRemaining, bufferPtr, buffer);
			if (numBytes == -1)
			{
				if (bytesRead == 0)
				{
					// failed to read any data
					retryCount--;
					if (retryCount > 0)
					{
						// retry
						NSLog(@"ExecuteBytes: Error reading from display - retrying - %s (%d)", strerror(errno), errno);
						sleep(1);
					}
					else
					{
						// give up
						NSLog(@"ExecuteBytes: Error reading from display - giving up - %s (%d)", strerror(errno), errno);
						break;
					}
				}
				else
				{
					// data was read, clear numBytes to exit loop
					numBytes = 0;
				}
			}
			
			if (numBytes > 0)
			{
				bytesRead += numBytes;
				bufferPtr += numBytes;
				
				//NSLog(@"ExecuteBytes: Read %ld bytes \"%s\"\n", numBytes, LogBytes(buffer, bytesRead));

				result = true;
			}
		}
	}

	*bufferSize = bytesRead;
	
	return (result);
}


kern_return_t FindSerialPorts(io_iterator_t *matchingServices)
{
	kern_return_t kernResult; 
	CFMutableDictionaryRef	classesToMatch;

	// Serial devices are instances of class IOSerialBSDClient
	classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue);
	if (classesToMatch == NULL)
	{
		NSLog(@"FindSerialPorts: IOServiceMatching returned a NULL dictionary");
		kernResult = kIOReturnError;
		goto exit;
	}
	else {
		CFDictionarySetValue(classesToMatch,
							 CFSTR(kIOSerialBSDTypeKey),
							 CFSTR(kIOSerialBSDRS232Type));
		
		// Each serial device object has a property with key
		// kIOSerialBSDTypeKey and a value that is one of kIOSerialBSDAllTypes,
		// kIOSerialBSDModemType, or kIOSerialBSDRS232Type. You can experiment with the
		// matching by changing the last parameter in the above call to CFDictionarySetValue.
		
		// As shipped, this sample is only interested in modems,
		// so add this property to the CFDictionary we're matching on. 
		// This will find devices that advertise themselves as modems,
		// such as built-in and USB modems. However, this match won't find serial modems.
	}

	kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, classesToMatch, matchingServices);    
	if (KERN_SUCCESS != kernResult)
	{
		NSLog(@"FindSerialPorts: IOServiceGetMatchingServices returned %d", kernResult);
		goto exit;
	}
		
exit:
	return kernResult;
}
	
// Given an iterator across a set of modems, return the BSD path to the first one.
// If no modems are found the path name is set to an empty string.
kern_return_t GetSerialPortPath(io_iterator_t serialPortIterator, char *bsdPath, CFIndex maxPathSize)
{
	io_object_t		modemService;
	kern_return_t	kernResult = KERN_FAILURE;
	Boolean			modemFound = false;
	
	// Initialize the returned path
	*bsdPath = '\0';
	
	// Iterate across all modems found. In this example, we bail after finding the first modem.
	
	while ((modemService = IOIteratorNext(serialPortIterator)) && !modemFound)
	{
		CFTypeRef	bsdPathAsCFString;

		// Get the callout device's path (/dev/cu.xxxxx). The callout device should almost always be
		// used: the dialin device (/dev/tty.xxxxx) would be used when monitoring a serial port for
		// incoming calls, e.g. a fax listener.
	
		bsdPathAsCFString = IORegistryEntryCreateCFProperty(modemService,
				CFSTR(kIOCalloutDeviceKey),
				kCFAllocatorDefault,
				0);
		if (bsdPathAsCFString)
		{
			Boolean result;
			
			// Convert the path from a CFString to a C (NUL-terminated) string for use
			// with the POSIX open() call.
		
			result = CFStringGetCString(bsdPathAsCFString,
										bsdPath,
										maxPathSize, 
										kCFStringEncodingUTF8);
			CFRelease(bsdPathAsCFString);
			
			if (result)
			{
//				NSLog(@"GetSerialPortPath: Serial port found with BSD path: %s", bsdPath);
				modemFound = true;
				kernResult = KERN_SUCCESS;
			}
		}

		printf("\n");

		// Release the io_service_t now that we are done with it.
	
		(void) IOObjectRelease(modemService);
	}
		
	return kernResult;
}

// Given the path to a serial device, open the device and configure it.
// Return the file descriptor associated with the device.
int OpenSerialPort(const char *bsdPath)
{
	int fileDescriptor = -1;
	struct termios options;
	
	// Open the serial port read/write, with no controlling terminal, and don't wait for a connection.
	// The O_NONBLOCK flag also causes subsequent I/O on the device to be non-blocking.
	// See open(2) ("man 2 open") for details.
	
	fileDescriptor = open(bsdPath, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fileDescriptor == -1)
	{
		NSLog(@"OpenSerialPort: Error opening serial port %s - %s (%d)", bsdPath, strerror(errno), errno);
		goto error;
	}

	// Note that open() follows POSIX semantics: multiple open() calls to the same file will succeed
	// unless the TIOCEXCL ioctl is issued. This will prevent additional opens except by root-owned
	// processes.
	// See tty(4) ("man 4 tty") and ioctl(2) ("man 2 ioctl") for details.
	
	if (ioctl(fileDescriptor, TIOCEXCL) == -1)
	{
		NSLog(@"OpenSerialPort: Error setting TIOCEXCL on %s - %s (%d).", bsdPath, strerror(errno), errno);
		goto error;
	}

	// setup non-blocking i/o -- so read() will return -1 when no data is available from the serial connection
	if (fcntl(fileDescriptor, F_SETFL, O_NONBLOCK) == -1)
	{
		NSLog(@"OpenSerialPort: Error setting O_NONBLOCK on %s - %s (%d)", bsdPath, strerror(errno), errno);
		goto error;
	}
	
	// turn off caching
	if (fcntl(fileDescriptor, F_NOCACHE, 1) == -1)
	{
		NSLog(@"OpenSerialPort: Error setting F_NOCACHE on %s - %s (%d)", bsdPath, strerror(errno), errno);
		goto error;
	}
	
	// Get the current options and save them so we can restore the default settings later.
	if (tcgetattr(fileDescriptor, &gOriginalTTYAttrs) == -1)
	{
		NSLog(@"OpenSerialPort: Error getting tty attributes %s - %s (%d)", bsdPath, strerror(errno), errno);
		goto error;
	}

	// The serial port attributes such as timeouts and baud rate are set by modifying the termios
	// structure and then calling tcsetattr() to cause the changes to take effect. Note that the
	// changes will not become effective without the tcsetattr() call.
	// See tcsetattr(4) ("man 4 tcsetattr") for details.
	
	options = gOriginalTTYAttrs;
	
	// Print the current input and output baud rates.
	// See tcsetattr(4) ("man 4 tcsetattr") for details.
	
//	printf("Current input baud rate is %d\n", (int) cfgetispeed(&options));
//	printf("Current output baud rate is %d\n", (int) cfgetospeed(&options));
	
	// Set raw input (non-canonical) mode, with reads blocking until either a single character 
	// has been received or a one second timeout expires.
	// See tcsetattr(4) ("man 4 tcsetattr") and termios(4) ("man 4 termios") for details.
	
	cfmakeraw(&options);
	options.c_cc[VMIN] = 1;
	options.c_cc[VTIME] = 10;
		
	// The baud rate, word length, and handshake options can be set as follows:
	
	cfsetspeed(&options, B19200);		// Set 19200 baud    
	options.c_cflag |= (CS8  | 	// Use 8 bit words
				PARENB);	// Parity enable (even parity if PARODD not also set)


	// Print the new input and output baud rates. Note that the IOSSIOSPEED ioctl interacts with the serial driver 
	// directly bypassing the termios struct. This means that the following two calls will not be able to read
	// the current baud rate if the IOSSIOSPEED ioctl was used but will instead return the speed set by the last call
	// to cfsetspeed.
	
//	printf("Input baud rate changed to %d\n", (int) cfgetispeed(&options));
//	printf("Output baud rate changed to %d\n", (int) cfgetospeed(&options));
	
	// Cause the new options to take effect immediately.
	if (tcsetattr(fileDescriptor, TCSANOW, &options) == -1)
	{
		NSLog(@"OpenSerialPort: Error setting tty attributes %s - %s (%d)", bsdPath, strerror(errno), errno);
		goto error;
	}

	// Success
	return fileDescriptor;
	
	// Failure path
error:
	if (fileDescriptor != -1)
	{
		close(fileDescriptor);
	}
	
	return -1;
}

void ResetDisplay(int fileDescriptor)
{
	char output[256];

	// clear display
	sprintf(output, "%c%c", 0xfe, 0x58);
	SendString(fileDescriptor, output);
	
	// setup bar graph characters
	sprintf(output, "%c%c", 0xfe, 's'); // or 'v' for wide bars
	SendString(fileDescriptor, output);

	// print labels
//	sprintf(output, "%c%c%c%c CPU  Disk  Net   Sw", 0xfe, 0x47, 1, 1);
//	SendString(fileDescriptor, output);

	// clear keypad buffer
	sprintf(output, "%c%c", 0xfe, 0x45);
	SendString(fileDescriptor, output);
}


// Given the file descriptor for a modem device, attempt to initialize the modem by sending it
// a standard AT command and reading the response. If successful, the modem's response will be "OK".
// Return true if successful, otherwise false.
Boolean SetupDisplay(int fileDescriptor)
{
	Boolean		result = false;

	char output[256];
	unsigned char buffer[256];
	int bufferSize;

	// establish a connection with the device by clearing the display several times
//	int i;
//	for (i = 0; i < 5; i++)
//	{
//		sprintf(output, "%c%c", 0xfe, 0x58);
//		SendString(fileDescriptor, output);
//	}

/*		
	// clear keypad buffer
	sprintf(output, "%c%c", 0xfe, 0x45);
	if (SendString(fileDescriptor, output))
*/
	{
		// make sure that we're talking to a LK202-24-USB by checking the device type
		sprintf(output, "%c%c", 0xfe, 0x37);
		bufferSize = 256;
		if (ExecuteBytes(fileDescriptor, (unsigned char *)output, 2, buffer, &bufferSize))
	//	if (ExecuteString(fileDescriptor, output))
		{
			if (bufferSize >= 1 && buffer[0] == 0x36)
			{
				// get the version number of the firmware
				sprintf(output, "%c%c", 0xfe, 0x36);
				bufferSize = 256;
				if (ExecuteBytes(fileDescriptor, (unsigned char *)output, 2, buffer, &bufferSize))
				{
					if (bufferSize == 1 && buffer[0] >= 0x21)
					{
						result = true;

						ResetDisplay(fileDescriptor);
					}
				}
			}
		}
	}
	
	return result;
}

// Given the file descriptor for a serial device, close that device.
void CloseSerialPort(int fileDescriptor)
{
	// Block until all written output has been sent from the device.
	// Note that this call is simply passed on to the serial device driver. 
	// See tcsendbreak(3) ("man 3 tcsendbreak") for details.
	if (tcdrain(fileDescriptor) == -1)
	{
		NSLog(@"CloseSerialPort: Error waiting for drain - %s (%d)", strerror(errno), errno);
	}
	
	// Traditionally it is good practice to reset a serial port back to
	// the state in which you found it. This is why the original termios struct
	// was saved.
	if (tcsetattr(fileDescriptor, TCSANOW, &gOriginalTTYAttrs) == -1)
	{
		NSLog(@"CloseSerialPort: Error resetting tty attributes - %s (%d)", strerror(errno), errno);
	}

	close(fileDescriptor);
}

/*
// Replace non-printable characters in str with '\'-escaped equivalents.
// This function is used for convenient logging of data traffic.
static char *LogString(char *str, Boolean showPrint)
{
	static char     buf[2048];
	char            *ptr = buf;
	unsigned char             i;

	*ptr = '\0';

	while (*str)
	{
		if (isprint(*str) && showPrint)
		{
			*ptr++ = *str++;
		}
		else {
			i = *str;
			(void)sprintf(ptr, "0x%02x ", i);
			ptr += 5;

			str++;
		}

		*ptr = '\0';
	}

	return buf;
}

static char *LogBytes(char *bytes, size_t count)
{
	static char     buf[2048];
	char            *ptr = buf;
	unsigned char             i;
	size_t pos;
	
	*ptr = '\0';

	for (pos = 0; pos < count; pos++)
	{
		i = bytes[pos];
		(void)sprintf(ptr, "0x%02x ", i);
		ptr += 5;
	}
	*ptr = '\0';

	return buf;
}
*/

#pragma mark -

/*
									1	1	1	1	1	1	1	1	1	1	2
1	2	2	4	5	6	7	8	9	0	1	2	3	4	5	6	7	8	9	0
----------------------------------------------------------------------------------------------------------
[]	1	.	0	[]	[]	1	.	0	M	[]	[]	1	.	0	M	[]	[]		5
[]	4	9	º	[]	[]	0	.	2	K	[]	[]	0	.	2	K	[]	[]	*	*

	C	P	U			D	i	s	k			N	e	t		
C				R	W					T	R					I	O
	
									1	1	1	1	1	1	1	1	1	1	2
1	2	2	4	5	6	7	8	9	0	1	2	3	4	5	6	7	8	9	0
----------------------------------------------------------------------------------------------------------
[]	1	0	.	0	[]	[]	1	.	0	M	[]	[]	1	.	0	M	[]	[]
•	1	2	3	º	r	w	0	.	2	K	r	t	0	.	2	K	i	o

CPU					Disk						Net						Swap
	
*/

void graphMatrixOrbital(int serialDevice, float level, unsigned char column, char label)
{
	unsigned char output[5];

	unsigned char meter = (level * 17.0);

	if (meter == 0)
	{
/*
		// force label every 10 seconds
		time_t now = time(NULL);
		struct tm *nowTime = localtime(&now);
		if (nowTime->tm_sec % 10 != 0)
		{
			label = ' ';
		}
*/
		
		output[0] = 0xfe;
		output[1] = 'G';
		output[2] = column;
		output[3] = 2;
		output[4] = label;
		if (! SendBytes(serialDevice, output, 5))
		{
			serialDevice = -1;
		}
		else
		{
			output[0] = 0xfe;
			output[1] = 'G';
			output[2] = column;
			output[3] = 1;
			output[4] = ' ';
			if (! SendBytes(serialDevice, output, 5))
			{
				serialDevice = -1;
			}
		}
/*
		char string[256];
		
		sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 1, label);
		if (! SendString(serialDevice, string))
		{
			serialDevice = -1;
		}
		else
		{
			sprintf(string, "%c%c%c%c ", 0xfe, 0x47, column, 2);
			if (! SendString(serialDevice, string))
			{
				serialDevice = -1;
			}
		}
*/
	}
	else
	{
		output[0] = 0xfe;
		output[1] = '=';
		output[2] = column;
		output[3] = meter;
		if (! SendBytes(serialDevice, output, 4))
		{
			serialDevice = -1;
		}
	}
}

char *formatUnits[] = {" ", "K", "M", "G", "T", "P"};
char *formatString[] = {"%3.1f%s", "%3.0f%s", "%3.0f%s"};

void buildValueOutput(float inputBytes, char *outputString)
{ 
	if (inputBytes == 0)
	{
		sprintf(outputString, " %c%c ", 0xa5, 0xa5);
	}
	else if (inputBytes < 1000)
	{
		sprintf(outputString, " -- ");
	}
	else
	{
		int logIndex = (int)(floor(log10(inputBytes) / 3.0));
		float unitScale = 1000.0;
		//int logIndex = (int)(floor((log(inputBytes)/log(2)) / 10.0)); // log(value)/log(2) == log2(value)
		//float unitScale = 1024.0;
		
		if (logIndex >= 0 && logIndex <= 6)
		{
			float outputValue = inputBytes / pow(unitScale, logIndex);
			char *outputUnits = formatUnits[logIndex];
			int formatIndex = (int)(floor(log10(inputBytes))) % 3;
			if (formatIndex < 0 || formatIndex >= 3)
			{
				formatIndex = 0;
			}
			
			sprintf(outputString, formatString[formatIndex], outputValue, outputUnits);
		}
		else
		{
		sprintf(outputString, " ++ ");
		}
	}
}

//char clockSymbols[] = {'+', 'x' };

- (void)updateMatrixOrbital
{
//	kern_return_t  kernResult;
	

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	{
		float level; // 0.0 to 1.0
//		unsigned char meter;
		unsigned char column;
//		unsigned char output[4];
		char string[256];

//		sprintf(string, "%c%c%c%cC   RW    TR    IO", 0xfe, 0x47, 1, 1);
//		SendString(serialDevice, string);

		// temperature
		{
			TemperatureData temperatureData;
			int numTemperatures;
		
			[temperatureInfo getCurrent:&temperatureData];
			numTemperatures = temperatureData.temperatureCount;
		
			if (numTemperatures > 0)
			{
				float temperatureCelsius;
				if (numTemperatures == 1)
				{
					temperatureCelsius = temperatureData.temperatureLevel[0];
				}
				else
				{
					temperatureCelsius = (temperatureData.temperatureLevel[0] + temperatureData.temperatureLevel[1]) / 2.0;
				}
				float temperatureFahrenheit = ((9.0 / 5.0) * temperatureCelsius) + 32.0;

				column = 2;
				sprintf(string, "%c%c%c%c%3.0f\337", 0xfe, 0x47, column, 2, temperatureFahrenheit);
				SendString(serialDevice, string);		
			}
		}

		// load
		{
			double currentLoad = 0.0;
			
			// get current load
			{
				host_load_info_data_t loadstat;
				mach_msg_type_number_t count = HOST_LOAD_INFO_COUNT;
		
				if (host_statistics(mach_host_self(), HOST_LOAD_INFO, (host_info_t) &loadstat, &count) == KERN_SUCCESS)
				{
					currentLoad = (double)loadstat.avenrun[0] / (double)LOAD_SCALE;
				}
			}

			column = 2;
			sprintf(string, "%c%c%c%c%4.1f", 0xfe, 0x47, column, 1, currentLoad);
			SendString(serialDevice, string);		
		}
		
			{
				CPUData cpudata;
			
				[processorInfo getCurrent:&cpudata];

				int i;
				float sum = 0;
				
				for (i = 0; i < cpudata.processorCount; i++)
				{
					if ([defaults boolForKey:PROCESSOR_INCLUDE_NICE_KEY])
					{
						sum = sum + cpudata.nice[i] + cpudata.user[i] + cpudata.system[i];

					}
					else
					{
						sum = sum + cpudata.user[i] + cpudata.system[i];
					}
				}
				
				level = sum / cpudata.processorCount;

				column = 1;
				graphMatrixOrbital(serialDevice, level, column, 0xa5);
			}

			{
				float readLevel, writeLevel;
				DiskData diskdata;
			
				float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

				int scaleType = [defaults integerForKey:DISK_SCALE_KEY];
				float peakRead = (peakReadBytes / interval);
				float scaleRead = [self computeScaleForGauge:scaleType withPeak:peakRead];
				float peakWrite = (peakWriteBytes / interval);
				float scaleWrite = [self computeScaleForGauge:scaleType withPeak:peakWrite];
				
				[diskInfo getCurrent:&diskdata];
				{
					readLevel = [self scaleValueForGauge:(diskdata.readBytes / interval) scaleType:scaleType scale:scaleRead];

					writeLevel = [self scaleValueForGauge:(diskdata.writeBytes / interval) scaleType:scaleType scale:scaleWrite];
				}

				//float readBytes = (diskdata.readBytes / interval);
				//float writeBytes = (diskdata.writeBytes / interval);
				float readSum = 0.0;
				int readCounter = 0;
				float readAverage;
				float writeSum = 0.0;
				int writeCounter = 0;
				float writeAverage;

				int x;
				[diskInfo startIterate];
				for (x = 0; [diskInfo getNext:&diskdata]; x++)
				{
					readSum += diskdata.readBytes;
					readCounter += 1;

					writeSum += diskdata.writeBytes;
					writeCounter += 1;
				}
				readAverage = (readSum / (float) readCounter) / interval;
				writeAverage = (writeSum / (float) writeCounter) / interval;

				
				column = 6;
				graphMatrixOrbital(serialDevice, readLevel, column, 'r');

				column = 7;
				graphMatrixOrbital(serialDevice, writeLevel, column, 'w');

				char outputString[32];
				buildValueOutput(readAverage, outputString);
				//NSLog(@"readAverage = %3.1f, output = %s", readAverage, outputString);
				
				column = 8;
				sprintf(string, "%c%c%c%c%s", 0xfe, 0x47, column, 1, outputString);
				SendString(serialDevice, string);		

				buildValueOutput(writeAverage, outputString);
				//NSLog(@"writeBytes = %3.1f, output = %s", writeBytes, outputString);

				column = 8;
				sprintf(string, "%c%c%c%c%s", 0xfe, 0x47, column, 2, outputString);
				SendString(serialDevice, string);		
			}

			{
				float inputLevel, outputLevel;
				NetData netdata;
			
				float interval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;

				int scaleType = [defaults integerForKey:NETWORK_SCALE_KEY];
				float peakIn = (peakPacketsInBytes / interval);
				float scaleIn = [self computeScaleForGauge:scaleType withPeak:peakIn];
				float peakOut = (peakPacketsOutBytes / interval);
				float scaleOut = [self computeScaleForGauge:scaleType withPeak:peakOut];
				
				[networkInfo getCurrent:&netdata];
				{
					inputLevel = [self scaleValueForGauge:(netdata.packetsInBytes / interval) scaleType:scaleType scale:scaleIn];

					outputLevel = [self scaleValueForGauge:(netdata.packetsOutBytes / interval) scaleType:scaleType scale:scaleOut];
				}

				//float readBytes = (netdata.packetsInBytes / interval);
				//float writeBytes = (netdata.packetsOutBytes / interval);
				float readSum = 0.0;
				int readCounter = 0;
				float readAverage;
				float writeSum = 0.0;
				int writeCounter = 0;
				float writeAverage;

				int x;
				[networkInfo startIterate];
				for (x = 0; [networkInfo getNext:&netdata]; x++)
				{
					readSum += netdata.packetsInBytes;
					readCounter += 1;

					writeSum += netdata.packetsOutBytes;
					writeCounter += 1;
				}
				readAverage = ((readSum / (float) readCounter) / interval) * 8.0;
				writeAverage = ((writeSum / (float) writeCounter) / interval) * 8.0;
				
				column = 12;
				graphMatrixOrbital(serialDevice, inputLevel, column, 'r');

				column = 13;
				graphMatrixOrbital(serialDevice, outputLevel, column, 't');

				char outputString[32];
				
				buildValueOutput(readAverage, outputString);
				//NSLog(@"readBytes = %3.1f, output = %s", readBytes, outputString);
				
				column = 14;
				sprintf(string, "%c%c%c%c%s", 0xfe, 0x47, column, 1, outputString);
				SendString(serialDevice, string);		

				buildValueOutput(writeAverage, outputString);
				//NSLog(@"writeBytes = %3.1f, output = %s", writeBytes, outputString);

				column = 14;
				sprintf(string, "%c%c%c%c%s", 0xfe, 0x47, column, 2, outputString);
				SendString(serialDevice, string);		
			}

			{
				float inputLevel, outputLevel;
				VMData vmdata;
			
				[memoryInfo getCurrent:&vmdata];
				{
					inputLevel = vmdata.pageins;
					if (inputLevel > 100.0)
					{
						inputLevel = 100.0;
					}
					inputLevel = inputLevel / 100.0;
					
					outputLevel = vmdata.pageouts;
					if (outputLevel > 100.0)
					{
						outputLevel = 100.0;
					}
					outputLevel = outputLevel / 100.0;
				}
				
				column = 18;
				graphMatrixOrbital(serialDevice, inputLevel, column, 'i');

				column = 19;
				graphMatrixOrbital(serialDevice, outputLevel, column, 'o');
			}

			{
				struct tm *nowTime = localtime(&now);
#if 0
				float timeLevel = (float) (nowTime->tm_sec) / 59.0;

				column = 20;
				graphMatrixOrbital(serialDevice, timeLevel, column, ' ');
#else
#if 1
				column = 20;
				if (nowTime->tm_sec % 2 == 0)
				{					
					sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 1, 0xa5);
					SendString(serialDevice, string);		
					sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 2, ' ');
					SendString(serialDevice, string);
				}
				else
				{
					sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 1, ' ');
					SendString(serialDevice, string);		
					sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 2, 0xa5);
					SendString(serialDevice, string);
				}
#else
				column = 20;
				int symbolIndex = nowTime->tm_sec % 2;
				sprintf(string, "%c%c%c%c%c", 0xfe, 0x47, column, 1, clockSymbols[symbolIndex]);
				SendString(serialDevice, string);						
#endif
#endif
			}
		
	}
}

#pragma mark -

void powerCallback(void *refCon, io_service_t service, natural_t messageType, void *messageArgument)
{
	[(MainController *)refCon powerMessageReceived: messageType withArgument: messageArgument];
}
	
- (void)deregisterForSleepWakeNotification
{
	IODeregisterForSystemPower(&notifier);
}
	
- (void)powerMessageReceived:(natural_t)messageType withArgument:(void *) messageArgument
{
	switch (messageType)
	{
		case kIOMessageSystemWillSleep:
			IOAllowPowerChange(root_port, (long)messageArgument);
//			NSLog(@"powerMessageReceived: system will sleep");
			break;			
	
		case kIOMessageCanSystemSleep:
			// I don’t know if this will ever be asked…
			IOAllowPowerChange(root_port, (long)messageArgument);
			break; 
	
		case kIOMessageSystemHasPoweredOn:
//			NSLog(@"powerMessageReceived: system has powered on");
#if 1
	#if 1
			if (serialDevice != -1)
			{
				ResetDisplay(serialDevice);
			}
	#else
			if (serialDevice != -1)
			{
				// Block until all written output has been sent from the device.
				// Note that this call is simply passed on to the serial device driver. 
				// See tcsendbreak(3) ("man 3 tcsendbreak") for details.
//				if (tcdrain(serialDevice) == -1)
//				{
//					NSLog(@"CloseSerialPort: Error waiting for drain - %s (%d)", strerror(errno), errno);
//				}
				
				// Traditionally it is good practice to reset a serial port back to
				// the state in which you found it. This is why the original termios struct
				// was saved.
				if (tcsetattr(serialDevice, TCSANOW, &gOriginalTTYAttrs) == -1)
				{
					NSLog(@"CloseSerialPort: Error resetting tty attributes - %s (%d)", strerror(errno), errno);
				}

				ResetDisplay(serialDevice);
			}
	#endif
#else
		{
			close(serialDevice);
			serialDevice = -1;
			
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			BOOL checkMatrixOrbital = [defaults boolForKey:APPLICATION_CHECK_MATRIX_ORBITAL_KEY];
			if (checkMatrixOrbital)
			{
				// initialize Matrix Orbital display (if present)
				io_iterator_t	serialPortIterator;
				kern_return_t kernResult = FindSerialPorts(&serialPortIterator);
				if (kernResult == KERN_SUCCESS)
				{
					char bsdPath[MAXPATHLEN];
					kernResult = GetSerialPortPath(serialPortIterator, bsdPath, sizeof(bsdPath));
					
					IOObjectRelease(serialPortIterator);
					if (kernResult == KERN_SUCCESS)
					{
						// check format of bsdPath to be something like: "/dev/cu.usbserial-00004917";
						if (strstr(bsdPath, "usbserial") != NULL)
						{
							serialDevice = OpenSerialPort(bsdPath);
							if (serialDevice != -1)
							{
								if (! SetupDisplay(serialDevice))
								{
									// setup failed, ignore the serial device
									serialDevice = -1;
								}
								else
								{
									// register for sleep and wake so we can update display
									[self registerForSleepWakeNotification];
								}
							}
						}
					}
				}
			}
		}
			
#endif
			break;
	}
}
	
- (void)registerForSleepWakeNotification
{
	IONotificationPortRef notificationPort;
	root_port = IORegisterForSystemPower(self, &notificationPort, powerCallback, &notifier);
	NSAssert(root_port != MACH_PORT_NULL, @"IORegisterForSystemPower failed");
	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
}

#endif // OPTION_INCLUDE_MATRIX_ORBITAL	


#pragma mark -

- (void)drawImages
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL drawTextOnIcon = [defaults boolForKey:GLOBAL_DOCK_INCLUDE_TEXT_KEY];

	[iconImage lockFocus];

	// erase previous graph
	[[[NSColor blackColor] colorWithAlphaComponent:0.0] set];
	NSRectFill (NSMakeRect(0.0, 0.0, GRAPH_SIZE, GRAPH_SIZE));

	// draw gauges that appear in both the dock and window
	[self drawGaugeBackground];	
	[self drawGaugeGrid];
	
	[self drawSwappingGauge];
	[self drawNetworkGauge];
	[self drawMemoryGauge];
	[self drawDiskGauge];
	[self drawProcessorGauge];
	[self drawClockDateGauge];
	[self drawClockTimeGauge];
	[self drawHistoryGauge];	
	[self drawMobilityGauge];

	if (drawTextOnIcon)
	{
		// draw text
		[self drawMemoryText];
		[self drawSwappingText];
		[self drawProcessorText];
		[self drawNetworkText];
		[self drawDiskText];
	}

	// finished with application icon
	[iconImage unlockFocus];
	
	// draw the floating window
	[graphImage lockFocus];	

	// start with the icon image used for the application icon
	[iconImage drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];

	if (! drawTextOnIcon)
	{
		// draw text that only appears in window
		[self drawMemoryText];
		[self drawSwappingText];
		[self drawProcessorText];
		[self drawNetworkText];
		[self drawDiskText];
	}

	[graphImage unlockFocus];

	if ([defaults boolForKey:GLOBAL_SHOW_STATUS_KEY])
	{
		[statusImage lockFocus];

		// draw background for menubar
		[self drawStatusBackground];	
		
		// draw upper bar
		switch ([defaults integerForKey:GLOBAL_STATUS_UPPER_BAR_TYPE_KEY])
		{
		default:
		case 0:
			// none
			break;
		case 1:
			// CPU
			[self drawProcessorStatusAt:upperBar];
			break;
		case 2:
			// network
			[self drawNetworkStatusAt:upperBar];
			break;
		case 3:
			// disk
			[self drawDiskStatusAt:upperBar];
			break;
		case 4:
			// swap
			[self drawSwappingStatusAt:upperBar];
			break;
		}
		
		// draw upper dot
		switch ([defaults integerForKey:GLOBAL_STATUS_UPPER_DOT_TYPE_KEY])
		{
		default:
		case 0:
			// none
			break;
		case 2:
			// network
			[self drawNetworkStatusAt:upperDots];
			break;
		case 3:
			// disk
			[self drawDiskStatusAt:upperDots];
			break;
		case 4:
			// swap
			[self drawSwappingStatusAt:upperDots];
			break;
		}
		
		// draw lower bar
		switch ([defaults integerForKey:GLOBAL_STATUS_LOWER_BAR_TYPE_KEY])
		{
		default:
		case 0:
			// none
			break;
		case 1:
			// CPU
			[self drawProcessorStatusAt:lowerBar];
			break;
		case 2:
			// network
			[self drawNetworkStatusAt:lowerBar];
			break;
		case 3:
			// disk
			[self drawDiskStatusAt:lowerBar];
			break;
		case 4:
			// swap
			[self drawSwappingStatusAt:lowerBar];
			break;
		}
		
		// draw lower dot
		switch ([defaults integerForKey:GLOBAL_STATUS_LOWER_DOT_TYPE_KEY])
		{
		default:
		case 0:
			// none
			break;
		case 2:
			// network
			[self drawNetworkStatusAt:lowerDots];
			break;
		case 3:
			// disk
			[self drawDiskStatusAt:lowerDots];
			break;
		case 4:
			// swap
			[self drawSwappingStatusAt:lowerDots];
			break;
		}
				
		[statusImage unlockFocus];
	}
}

- (void)updateIconAndWindow
{
	//float version = [self systemVersion];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	[self drawImages];
	
	if ([defaults boolForKey:GLOBAL_SHOW_STATUS_KEY])
	{
		if (! statusItem)
		{
			statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:STATUS_WIDTH + STATUS_ITEM_PADDING];
			[statusItem retain];
		}
		
		[statusItem setImage:statusImage];
	}
	else
	{
		if (statusItem)
		{
			[statusItem setImage:nil];
			[statusItem setLength:0.0];

			[statusItem release];
			statusItem = nil;
		}
	}
	
	if ([defaults boolForKey:GLOBAL_SHOW_DOCK_KEY])
	{
		[NSApp setApplicationIconImage:iconImage];
		applicationIconIsDefault = NO;
	}
	else
	{
		if (! applicationIconIsDefault)
		{
			[NSApp setApplicationIconImage:[NSImage imageNamed:@"iPulse.icns"]];	
			applicationIconIsDefault = YES;
		}
	}
	
	if ([defaults boolForKey:WINDOW_SHOW_FLOATING_KEY])
	{
		if (majorVersion == 10 && minorVersion >= 2)
		{
			// display the view without flushing
			[graphWindow disableFlushWindow];
			[graphView display];
			[graphWindow enableFlushWindow];
			[graphWindow flushWindow];
		}
		
		if ([defaults boolForKey:WINDOW_FLOATING_SHADOW_KEY])
		{
			if (majorVersion == 10 && minorVersion < 2)
			{	
				// the next two lines reset the CoreGraphics window shadow (calculated around the custom 
				// window shape content) so it's recalculated for the new shape.
			
				[graphWindow setHasShadow:NO];
				[graphWindow setHasShadow:YES];
			}
			else
			{
				[graphWindow setHasShadow:YES];
				[graphWindow invalidateShadow];
			}
		}
		else
		{
			if ([graphWindow hasShadow])
			{
				// order out and front makes the shadow go away completely, but it flashes
				[graphWindow orderOut:self];
				[graphWindow setHasShadow:NO];
				[graphWindow orderFront:self];
			}
		}

		if (majorVersion == 10 && minorVersion < 2)
		{
			[graphWindow disableFlushWindow];
			[graphView display];
			[graphWindow enableFlushWindow];
			[graphWindow flushWindow];
		}
	}
}

- (void)refreshAndDisplay
{
	// get new samples as necessary, refresh the dock and window icons, and redisplay the info window

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	now = time(NULL); // all time based measurements pivot around this call for time()
	struct tm *nowTime = localtime(&now);

	[processorInfo refresh];
	[memoryInfo refresh];
	[diskInfo refresh];
	[networkInfo refresh];

	if ([powerInfo isAvailable] && [defaults boolForKey:MOBILITY_BATTERY_SHOW_GAUGE_KEY])
	{
		[powerInfo refresh];
	}
	
	if ([airportInfo isAvailable] && [defaults boolForKey:MOBILITY_WIRELESS_SHOW_GAUGE_KEY])
	{
		[airportInfo refresh];
	}

	// check temperature every 15 seconds
	if (nowTime->tm_sec % 15 == 0)
	{
		[temperatureInfo refresh];
	}
		
	// refresh only on one minute intervals
	if (nowTime->tm_min != lastMinute)
	{
		//[powerInfo refresh];
		[loadInfo refresh];
		lastMinute = nowTime->tm_min;
	}

	[self updateIconAndWindow];

	if ([infoWindow isVisible])
	{
		[self updateInfo];
	}

#if OPTION_INCLUDE_MATRIX_ORBITAL	
	if (serialDevice)
	{
		[self updateMatrixOrbital];
	}
#endif
}

#pragma mark -

- (void)setCurtainTimer
{
	//NSLog(@"MainController: setCurtainTimer %d", curtain);

	[self updateIconAndWindow];

	curtain += 4;
	if (curtain > EFFECT_STEPS)
	{
		[curtainTimer invalidate];
		[curtainTimer release];
	}
	else
	{
		[graphWindow setAlphaValue:((float)curtain / (float)EFFECT_STEPS)];
	}
}

- (void)setFadeTimer
{
	//NSLog(@"MainController: setFadeTimer %d", fade);

	fade += fadeIncrement;
	if (fade < 0 || fade > EFFECT_STEPS)
	{
		[fadeTimer invalidate];
		[fadeTimer release];
		fadeTimer = nil;

		if (fade < 0)
		{
			[infoWindow orderOut:nil];
		}
		if (fade > EFFECT_STEPS)
		{
			[infoWindow setAlphaValue:1.0];
		}
	}
	else
	{
		[infoWindow setAlphaValue:((float)fade / (float)EFFECT_STEPS)];
	}
}

- (void)setRefreshTimer
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	double newInterval = [defaults floatForKey:GLOBAL_UPDATE_FREQUENCY_KEY] / 10.0;
	
	if (refreshTimer)
	{
		if (fabs([refreshTimer timeInterval] - newInterval) < 0.001)
		{
			return; // interval has not changed
		}
		[refreshTimer invalidate];
		[refreshTimer release];
	}
	refreshTimer = [NSTimer scheduledTimerWithTimeInterval:newInterval target:self selector:@selector(refreshAndDisplay) userInfo:nil repeats:YES];
	[refreshTimer retain];
}


#pragma mark -

- (void)awakeFromNib
{
	if (!sparkleUpdater) {
		sparkleUpdater = [[SUUpdater alloc] init];
	}
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	NSString *iPulsePath = [[NSBundle mainBundle] bundlePath];
	
	NSDictionary *registerDefaults = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Contents/Resources/defaults.plist", iPulsePath]];
	[[NSUserDefaults standardUserDefaults] registerDefaults:registerDefaults];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:GLOBAL_SHOW_DOCK_ICON_KEY]) {
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	}
	[NSApp activateIgnoringOtherApps:YES];

	// check if we can access the Finder process and use that to enable or disable the process listings
	NSRunningApplication *finderApplication = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"] lastObject];
	if (finderApplication) {
		if (! [AGProcess processForProcessIdentifier:[finderApplication processIdentifier]]) {
			// NOTE: to reset the task port and test this code, use the following on the command line:
			// security authorize -ld system.privilege.taskport
			
			[[NSAlert alertWithMessageText:@"Process Authorization Denied" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Developer Tools Access is required to display information about processes.\n\nProcess listings will be disabled until authorization is granted when you launch iPulse."] runModal];
			haveAuthorizedTaskPort = NO;
		}
		else {
			haveAuthorizedTaskPort = YES;
		}
	}
	else {
		haveAuthorizedTaskPort = YES;
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	startTime = time(NULL);
	now = time(NULL);
	struct tm *nowTime = localtime(&now);

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	lastMinute = nowTime->tm_min;
	lastHour = nowTime->tm_hour;

	// application icon in dock has not been updated
	applicationIconIsDefault = YES;

	// get OS version information
	majorVersion = 0;
	minorVersion = 0;
	updateVersion = 0;
	sscanf([[[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"] objectForKey:@"ProductVersion"] cString], "%d.%d.%d", &majorVersion, &minorVersion, &updateVersion);

	// check OS version for minimum requirement
	BOOL isSupported = YES;
	if (! (majorVersion >= 10 && minorVersion >= 5))
	{
		isSupported = NO;
	}
	if (! isSupported)
	{
		[[NSAlert alertWithMessageText:@"Unsupported version of Mac OS X" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"You are running Mac OS X version %d.%d.%d. iPulse requires Mac OS X version 10.5 or later. Please upgrade and try again.", majorVersion, minorVersion, updateVersion] runModal];
		[NSApp terminate:self];
	}
	
	// allocate the data objects
	preferences = [[Preferences alloc] init];
	memoryInfo = [[MemoryInfo alloc] initWithCapacity:SAMPLE_SIZE];
	processorInfo = [[ProcessorInfo alloc] initWithCapacity:SAMPLE_SIZE];
	diskInfo = [[DiskInfo alloc] initWithCapacity:SAMPLE_SIZE];
	networkInfo = [[NetworkInfo alloc] initWithCapacity:SAMPLE_SIZE];
	powerInfo = [[PowerInfo alloc] initWithCapacity:SAMPLE_SIZE];
	temperatureInfo = [[TemperatureInfo alloc] initWithCapacity:SAMPLE_SIZE];
	airportInfo = [[AirportInfo alloc] initWithCapacity:SAMPLE_SIZE];
	loadInfo = [[LoadInfo alloc] initWithCapacity:60];
	

	// setup toolbar selection mechanism
	[preferences setDoToolbarSelection:YES];
	
	// get information from Info.plist
	{
		NSString *iPulsePath = [[NSBundle mainBundle] bundlePath];
		NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Contents/Info.plist", iPulsePath]];
		
		// get version number
		{
			NSString *version = [infoDictionary objectForKey:@"CFBundleVersion"];
	
			applicationVersion = [NSLocalizedString(@"Version", nil) stringByAppendingString:version]; 
			[applicationVersion retain];
			
			[preferences setApplicationVersion:applicationVersion];
		}
		
		// check if we are running dockless
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		if (! [defaults boolForKey:GLOBAL_SHOW_DOCK_ICON_KEY]) {
			// force dock icon off
			[defaults setObject:[NSNumber numberWithInt:0] forKey:GLOBAL_SHOW_DOCK_KEY];

			// force floating window on
			[defaults setObject:[NSNumber numberWithInt:1] forKey:WINDOW_SHOW_FLOATING_KEY];

			[defaults synchronize];
		}
	}

	// sample now rather than waiting for next minute to elapse
	[powerInfo refresh];
	[loadInfo refresh];
	[temperatureInfo refresh];

	// create initial icon and graph images
	iconImage = [[NSImage allocWithZone:[self zone]] initWithSize:NSMakeSize(GRAPH_SIZE, GRAPH_SIZE)];
	graphImage = [[NSImage allocWithZone:[self zone]] initWithSize:NSMakeSize(GRAPH_SIZE, GRAPH_SIZE)];
	statusImage = [[NSImage allocWithZone:[self zone]] initWithSize:NSMakeSize(STATUS_WIDTH, STATUS_HEIGHT)];
	[self drawImages];

	// setup color panel to allow alpha
	[[NSColorPanel sharedColorPanel] setShowsAlpha:YES];
	
	// create graph window
	graphWindow = [[TranslucentWindow allocWithZone:[self zone]]
			initWithContentRect:NSMakeRect(0.0, 0.0, GRAPH_SIZE, GRAPH_SIZE)
			styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	if ([defaults boolForKey:APPLICATION_TRACK_MOUSE_KEY])
	{
		[graphWindow setAcceptsMouseMovedEvents:YES];
	}
	
	// create view for graph window
	graphView = [[GraphView allocWithZone:[self zone]] initWithFrame:NSMakeRect(0.0, 0.0, GRAPH_SIZE, GRAPH_SIZE)];
	[graphWindow setContentView:graphView];
	[graphWindow makeFirstResponder:graphView];
	[graphView setContentDrawer:self method:@selector(drawGraphImage)];
	[graphView setAutoresizingMask:(NSViewHeightSizable | NSViewWidthSizable)];
	[graphView setMenu:contextMenu];
	[graphView addTrackingRect:NSMakeRect(0.0, 0.0, GRAPH_SIZE, GRAPH_SIZE) owner:graphView userData:NULL assumeInside:NO];

	// reset window position
	{
		UInt32 modifiers = GetCurrentKeyModifiers();
		if (modifiers & (optionKey | rightOptionKey))
		{
			[self resetGraphLocation];
		}
	}
	[self setGraphLocation];

	// create info window
	infoWindow = [[TranslucentWindow allocWithZone:[self zone]]
			initWithContentRect:NSMakeRect(0.0, 0.0, INFO_WIDTH, INFO_HEIGHT)
			styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	[infoWindow setLevel:kCGPopUpMenuWindowLevel]; // above dock

	// make info window transparent to clicks
	[infoWindow setIgnoresMouseEvents:YES];

	// create a status item in the menubar
	if ([defaults boolForKey:GLOBAL_SHOW_STATUS_KEY])
	{
		statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:STATUS_WIDTH + STATUS_ITEM_PADDING];
		[statusItem retain];
	}
	else
	{
		statusItem = nil;
	}
	
	// set initial location for info window
	[self setInfoLocation];

	// set window level & mouse transparency (both for graph and info windows)
	[self setWindows];
	
	// make sure background images for window and status bar are loaded
	[self updateWindow];
	[self updateStatus];
	
	// create view for info window
	infoView = [[InfoView alloc] initWithFrame:NSMakeRect(0.0, 0.0, INFO_WIDTH, INFO_HEIGHT)];
	[infoView setContentDrawer:self method:@selector(drawInfo)];
	[infoWindow setContentView: infoView];
	[infoWindow orderOut:nil];

	if ([defaults boolForKey:APPLICATION_IGNORE_EXPOSE_KEY])
	{
		[graphWindow setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary)];
		[infoWindow setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary)];
	}
	else {
		[graphWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
		[infoWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
	}
		
	// setup notifications
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setWindows) name:PREFERENCES_CHANGED object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateIconAndWindow) name:PREFERENCES_CHANGED object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setRefreshTimer) name:PREFERENCES_CHANGED object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateWindow) name:PREFERENCES_WINDOW_CHANGED object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateStatus) name:PREFERENCES_STATUS_CHANGED object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateHotkeys) name:PREFERENCES_HOTKEY_CHANGED object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(graphWindowMoved) name:GRAPH_VIEW_MOVED object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(graphWindowEntered) name:GRAPH_VIEW_ENTERED object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(graphWindowUpdate) name:GRAPH_VIEW_UPDATE object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(graphWindowExited) name:GRAPH_VIEW_EXITED object:nil];

	[self setRefreshTimer];

	// initialize fader
	fade = -1;
	fadeTimer = nil;
	delayTimer = nil;

	// initialize curtain
	curtainTimer = [NSTimer scheduledTimerWithTimeInterval:EFFECT_INTERVAL target:self selector:@selector(setCurtainTimer) userInfo:nil repeats:YES];
	[curtainTimer retain];
	curtain = 0;

	// change priority
	{
		int priority = [[defaults objectForKey:GLOBAL_SCHEDULING_PRIORITY_KEY] intValue];
		int result = setpriority(PRIO_PROCESS, 0, priority);
		if (result != 0)
		{
			NSLog(@"MainController: applicationDidFinishLaunching: setpriority failed with %d", result);
		}
	}
	

	// reset peak indicators
	peakPacketsInBytes = 0;
	timePeakPacketsInBytes = now;
	peakPacketsOutBytes = 0;
	timePeakPacketsOutBytes = now;
	peakReadBytes = 0;
	timePeakReadBytes = now;
	peakWriteBytes = 0;
	timePeakWriteBytes = now;
	
	// initialize process list
	{
		int i;
		for (i = 0; i < PROCESS_LIST_SIZE; i++)
		{
			processList[i].pid = 0;
			processList[i].average = 0.0;
			processList[i].current = 0.0;
			processList[i].isCurrent = NO;
		}
	}
	
	// initialize swapping list
	{
		int i;
		for (i = 0; i < SWAPPING_LIST_SIZE; i++)
		{
			swappingList[i].pid = INT_MAX;
			swappingList[i].pageins = 0;
			swappingList[i].lastPageins = 0;
			swappingList[i].faults = 0;
			swappingList[i].lastFaults = 0;
			swappingList[i].isCurrent = NO;
		}
	}
		
	selfPid = getpid();
	
	// setup application wide global variables
	{
		alternativeActivity = [defaults boolForKey:APPLICATION_ALTERNATIVE_ACTIVITY_KEY];
		plotArea = [defaults boolForKey:APPLICATION_PLOT_PROCESSOR_AREA_KEY];
		infoDelay = [defaults floatForKey:APPLICATION_INFO_DELAY_KEY];
		if (infoDelay <= 0.0)
		{
			infoDelay = 1.0;
		}
		statusAlertThreshold = [defaults floatForKey:APPLICATION_STATUS_ALERT_THRESHOLD_KEY];
		if (statusAlertThreshold < 0.0 || statusAlertThreshold > 1.0)
		{
			statusAlertThreshold = 0.9;
		}
	}

	// initialize hotkeys
	[self updateHotkeys];
	
#if OPTION_INCLUDE_MATRIX_ORBITAL		
	serialDevice = -1;
	BOOL checkMatrixOrbital = [defaults boolForKey:APPLICATION_CHECK_MATRIX_ORBITAL_KEY];
	if (checkMatrixOrbital)
	{
		// initialize Matrix Orbital display (if present)
		io_iterator_t	serialPortIterator;
		kern_return_t kernResult = FindSerialPorts(&serialPortIterator);
		if (kernResult == KERN_SUCCESS)
		{
			char bsdPath[MAXPATHLEN];
			kernResult = GetSerialPortPath(serialPortIterator, bsdPath, sizeof(bsdPath));
		
			IOObjectRelease(serialPortIterator);
			if (kernResult == KERN_SUCCESS)
			{
				// check format of bsdPath to be something like: "/dev/cu.usbserial-00004917";
				if (strstr(bsdPath, "usbserial") != NULL)
				{
					serialDevice = OpenSerialPort(bsdPath);
					if (serialDevice != -1)
					{
						if (! SetupDisplay(serialDevice))
						{
							// setup failed, ignore the serial device
							serialDevice = -1;
						}
						else
						{
							// register for sleep and wake so we can update display
							[self registerForSleepWakeNotification];
						}
					}
				}
			}
		}
	}
#endif

	infoWindowIsLocked = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
//	NSLog(@"MainController: applicationDidBecomeActive");
}

- (void)applicationWillTerminate:(NSNotification *)aNotification 
{
	if (refreshTimer) {
		[refreshTimer invalidate];
		[refreshTimer release];
		refreshTimer = nil;
	}
	
	// if you try to release the status item, you get a crash on exit -- go figure
	// [statusItem release];

	[NSApp setApplicationIconImage:[NSImage imageNamed:@"iPulse.icns"]];

#if OPTION_INCLUDE_MATRIX_ORBITAL	
	if (serialDevice != -1)
	{
		char output[256];
		sprintf(output, "%c%c", 0xfe, 0x58);
		SendString(serialDevice, output);

		// give the device some time to handle the command
		sleep(1);
		
		// return serial port to standard configuration
		CloseSerialPort(serialDevice);
	}
#endif
}

#pragma mark -

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
	BOOL result;
	
	//NSLog(@"MainController: openFile: filename = %@", filename);
	
	if (preferences)
	{
		NSURL *URL = [NSURL fileURLWithPath:filename];
		result = [preferences loadSettingsFromURL:URL];
		[preferences updatePanel];
	}
	else
	{
		result = NO;
	}
	
	return (result);
}

#pragma mark -

- (void)applicationWillHide:(NSNotification *)aNotification
{
	//NSLog(@"MainController: applicationWillHide");

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL neverHide = [defaults boolForKey:APPLICATION_NEVER_HIDE_KEY];
	if (neverHide)
	{
		[NSApp unhideWithoutActivation];
	}
}

- (void)resetGraphLocation
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	[defaults setObject:[NSNumber numberWithInt:0] forKey:WINDOW_FLOATING_RELATIVE_POSITION_KEY];
	[defaults setObject:[NSNumber numberWithFloat:74.0] forKey:WINDOW_FLOATING_CENTER_X_KEY];
	[defaults setObject:[NSNumber numberWithFloat:74.0] forKey:WINDOW_FLOATING_CENTER_Y_KEY];
	[defaults setObject:[NSNumber numberWithFloat:74.0] forKey:WINDOW_FLOATING_RELATIVE_X_KEY];
	[defaults setObject:[NSNumber numberWithFloat:74.0] forKey:WINDOW_FLOATING_RELATIVE_Y_KEY];
}

- (void)setGraphLocation
{
	//NSLog(@"MainController: setGraphLocation");
	
	int i;
	NSArray *screens = [NSScreen screens];
	NSScreen *screen;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSRect graphWindowFrame = NSZeroRect;
	NSPoint graphWindowCenter;
	NSPoint delta;
	int position;
	float size;

	NSRect screenFrame;
	NSRect originScreenFrame = NSMakeRect(0.0, 0.0, 0.0, 0.0);
	NSRect graphWindowScreenFrame = NSMakeRect(0.0, 0.0, 0.0, 0.0);
	BOOL graphWindowOnScreen = NO;
	
	graphWindowCenter.x = [defaults floatForKey:WINDOW_FLOATING_CENTER_X_KEY];
	graphWindowCenter.y = [defaults floatForKey:WINDOW_FLOATING_CENTER_Y_KEY];
	delta.x = [defaults floatForKey:WINDOW_FLOATING_RELATIVE_X_KEY];
	delta.y = [defaults floatForKey:WINDOW_FLOATING_RELATIVE_Y_KEY];
	position = [defaults integerForKey:WINDOW_FLOATING_RELATIVE_POSITION_KEY];
	size = [defaults floatForKey:WINDOW_FLOATING_SIZE_KEY];
	
	//NSLog(@"Window center = (%.2f, %.2f) delta = (%.2f, %.2f) [%d]", graphWindowCenter.x, graphWindowCenter.y, delta.x, delta.y, position);

	for (i = 0; i < [screens count]; i++)
	{
		screen = [screens objectAtIndex: i];
		screenFrame = [screen frame]; // with menu bar and/or dock
		//NSLog(@"Screen %d frame = (%.2f, %.2f) [%.2f, %.2f]", i, screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height);
		
		if (NSEqualPoints(screenFrame.origin, NSZeroPoint))
		{
			//NSLog(@"Screen %d is origin screen", i);
			originScreenFrame = screenFrame;
		}
		
		if (NSPointInRect(graphWindowCenter, screenFrame))
		{
			//NSLog(@"Screen %d contains graphWindow center", i);
			graphWindowScreenFrame = screenFrame;
			graphWindowOnScreen = YES;
		}
	}

	if (graphWindowOnScreen)
	{
		screenFrame = graphWindowScreenFrame;
	}
	else
	{
		screenFrame = originScreenFrame;
	}
	
	//NSLog(@"Placing @ screenFrame = (%.2f, %.2f) [%.2f, %.2f]  delta=(%.2f, %.2f) [%d]", screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height, delta.x, delta.y, position);

	switch (position)
	{
	case 0: // lower-left
		graphWindowFrame.origin.x = NSMinX(screenFrame) + delta.x - (size / 2.0);
		graphWindowFrame.origin.y = NSMinY(screenFrame) + delta.y - (size / 2.0);
		break;
	case 1: // upper-left
		graphWindowFrame.origin.x = NSMinX(screenFrame) + delta.x - (size / 2.0);
		graphWindowFrame.origin.y = NSMaxY(screenFrame) - delta.y - (size / 2.0);
		break;
	case 2: // upper-right
		graphWindowFrame.origin.x = NSMaxX(screenFrame) - delta.x - (size / 2.0);
		graphWindowFrame.origin.y = NSMaxY(screenFrame) - delta.y - (size / 2.0);
		break;
	case 3: // lower-left
		graphWindowFrame.origin.x = NSMaxX(screenFrame) - delta.x - (size / 2.0);
		graphWindowFrame.origin.y = NSMinY(screenFrame) + delta.y - (size / 2.0);
		break;
	}
	graphWindowFrame.size = NSMakeSize(size, size);
	[graphWindow setFrame:graphWindowFrame display:YES];

	//NSLog(@"New graphWindow frame = (%.2f, %.2f) [%.2f, %.2f]", graphWindowFrame.origin.x, graphWindowFrame.origin.y, graphWindowFrame.size.width, graphWindowFrame.size.height);
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)aNotification
{
	//NSLog(@"MainController: applicationDidChangeScreenParameters");

	// see if windows are off screen -- if so, bring them back on for window repositioning	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL windowInvisible = NO;
	if (! [defaults boolForKey:WINDOW_SHOW_FLOATING_KEY])
	{
		//NSLog(@"MainController: applicationDidChangeScreenParameters: windows are invisible");
		windowInvisible = YES;
	}
	if (windowInvisible)
	{
		[graphWindow orderFront:self];
		[infoWindow orderFront:self];
		[infoWindow setAlphaValue:1.0];
	}
	
	[self setGraphLocation];
	
	// update info window to reflect new graph window position
	[self setInfoLocation];

	// if we put windows on screen for repositioning, take them off screen again
	if (windowInvisible)
	{
		[graphWindow orderOut:self];
		[infoWindow orderOut:self];
		[infoWindow setAlphaValue:0.0];
	}
}

#pragma mark -

- (void)graphWindowMoved
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSRect graphWindowFrame;
	NSPoint graphWindowCenter;
	NSArray *screens = [NSScreen screens];
	int i;
	NSScreen *screen;
	NSRect screenFrame = NSZeroRect;
	NSPoint screenCenter;
	NSPoint delta;
	int position;
	
	//NSLog(@"MainController: graphWindowMoved");

	if ([defaults boolForKey:APPLICATION_HIDE_INFO_ON_DRAG_KEY])
	{
		[infoWindow orderOut:nil];
	}

	graphWindowFrame = [graphWindow frame];	
	//NSLog(@"Window frame = (%.2f, %.2f) [%.2f, %.2f]", graphWindowFrame.origin.x, graphWindowFrame.origin.y, graphWindowFrame.size.width, graphWindowFrame.size.height);

	graphWindowCenter.x = NSMidX(graphWindowFrame);
	graphWindowCenter.y = NSMidY(graphWindowFrame);
	//NSLog(@"Window center = (%.2f, %.2f)", graphWindowCenter.x, graphWindowCenter.y);

	for (i = 0; i < [screens count]; i++)
	{
		screen = [screens objectAtIndex: i];
		
		screenFrame = [screen frame];
		//NSLog(@"Screen %d frame = (%.2f, %.2f) [%.2f, %.2f]", i, screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height);
		
		if (NSPointInRect(graphWindowCenter, screenFrame))
		{
			//NSLog(@"Window center in screen %d", i);
			break;
		}
	}

	screenCenter.x = NSMidX(screenFrame);
	screenCenter.y = NSMidY(screenFrame);
	//NSLog(@"Screen center = (%.2f, %.2f)", screenCenter.x, screenCenter.y);

	[defaults setObject:[NSNumber numberWithFloat:graphWindowCenter.x] forKey:WINDOW_FLOATING_CENTER_X_KEY];
	[defaults setObject:[NSNumber numberWithFloat:graphWindowCenter.y] forKey:WINDOW_FLOATING_CENTER_Y_KEY];
	
	if (graphWindowCenter.x < screenCenter.x)
	{
		delta.x = graphWindowCenter.x - NSMinX(screenFrame);
		if (graphWindowCenter.y < screenCenter.y)
		{
			delta.y = graphWindowCenter.y - NSMinY(screenFrame);
			position = 0;
		}
		else
		{
			delta.y = NSMaxY(screenFrame) - graphWindowCenter.y;
			position = 1;
		}
	}
	else
	{
		delta.x = NSMaxX(screenFrame) - graphWindowCenter.x;
		if (graphWindowCenter.y < screenCenter.y)
		{
			delta.y = graphWindowCenter.y - NSMinY(screenFrame);
			position = 3;
		}
		else
		{
			delta.y = NSMaxY(screenFrame) - graphWindowCenter.y;
			position = 2;
		}
	}

	[defaults setObject:[NSNumber numberWithFloat:delta.x] forKey:WINDOW_FLOATING_RELATIVE_X_KEY];
	[defaults setObject:[NSNumber numberWithFloat:delta.y] forKey:WINDOW_FLOATING_RELATIVE_Y_KEY];
	[defaults setObject:[NSNumber numberWithInt:position] forKey:WINDOW_FLOATING_RELATIVE_POSITION_KEY];

	// update info window to reflect new graph window position
	[self setInfoLocation];
}

- (void)startFade
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	//NSLog(@"MainController: startFade");

	if (delayTimer)
	{
		[delayTimer invalidate];
		[delayTimer release];
		delayTimer = nil;
	}
	
	[self updateInfo];

	[infoWindow setAlphaValue:0.0];
	[infoWindow orderFront:nil];
	[self setInfoLocation];

	if (! fadeTimer)
	{
		fade = 0;
		fadeTimer = [NSTimer scheduledTimerWithTimeInterval:EFFECT_INTERVAL target:self selector:@selector(setFadeTimer) userInfo:nil repeats:YES];
		[fadeTimer retain];
	}

	fade = 0;
	fadeIncrement = [defaults integerForKey:WINDOW_INFO_FADE_IN_KEY];
}


- (void)graphWindowEntered
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	//NSLog(@"MainController: graphWindowEntered");

	if (! infoWindowIsLocked)
	{
		if ([defaults boolForKey:WINDOW_INFO_DELAY_KEY])
		{
			if (! delayTimer)
			{
				delayTimer = [NSTimer scheduledTimerWithTimeInterval:infoDelay target:self selector:@selector(startFade) userInfo:nil repeats:YES];
				[delayTimer retain];
			}
		}
		else
		{
			[self startFade];
		}
	}
}

- (void)graphWindowUpdate
{
	//NSLog(@"MainController: graphWindowUpdate");

	if (! infoWindowIsLocked)
	{
		[self updateInfo];
	}
}

- (void)graphWindowExited
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	//NSLog(@"MainController: graphWindowExited");

	if (! infoWindowIsLocked)
	{
		if (delayTimer)
		{
			[delayTimer invalidate];
			[delayTimer release];
			delayTimer = nil;
		}

		if (! fadeTimer)
		{
			fade = EFFECT_STEPS;
			fadeTimer = [NSTimer scheduledTimerWithTimeInterval:EFFECT_INTERVAL target:self selector:@selector(setFadeTimer) userInfo:nil repeats:YES];
			[fadeTimer retain];
		}
		fadeIncrement = [defaults integerForKey:WINDOW_INFO_FADE_OUT_KEY] * -1;
	}
}

#pragma mark -

- (IBAction)checkForUpdates:(id)sender
{
	[[SUUpdater sharedUpdater] checkForUpdates:sender];
}

- (void)openIconfactory:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iconfactory.com/"]];
}

- (void)openHomePage:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iconfactory.com/software/ipulse"]];
}

- (void)openGallery:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iconfactory.com/freeware/ipulse"]];
}

- (void)openFAQ:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://iconfactory.com/software/ipulse_support"]];
}

- (void)mailSupport:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://support.iconfactory.com"]];
}

- (void)launchProcessViewer:(id)sender
{
	[[NSWorkspace sharedWorkspace] launchApplication:@"Activity Monitor"];
}

- (void)launchTerminal:(id)sender
{
	[[NSWorkspace sharedWorkspace] launchApplication:@"Terminal"];
}

- (void)launchNetworkUtility:(id)sender
{
	[[NSWorkspace sharedWorkspace] launchApplication:@"Network Utility"];
}

- (void)showAboutBox:(id)sender
{
	if (! aboutBox) 
	{
		if ([NSBundle loadNibNamed:@"About" owner:self])
		{
			[aboutBox center];
		}
		else
		{
			NSLog (@"MainController: showAboutBox: Failed to load About.nib");
			return;
		}
	}
	[versionNumber setStringValue:applicationVersion];
	[aboutBox makeKeyAndOrderFront:nil];
}

- (void)showPreferences:(id)sender
{
	[preferences showPreferences:self];
}

- (void)toggleFloatingWindow:(id)sender
{
	//NSLog(@"MainController: toggleFloatingWindow");
	
	[preferences toggleFloatingWindow];
}

- (void)toggleIgnoreMouse:(id)sender
{
	[preferences toggleIgnoreMouse];
}

- (void)lockInfoWindow:(id)sender
{
	if (infoWindowIsLocked)
	{
		//NSLog(@"Unlocking info window...");
	
		infoWindowIsLocked = NO;
		[self graphWindowExited];
	}
	else
	{
		//NSLog(@"Locking info window...");

		infoWindowIsLocked = YES;
		[self startFade];
	}
}

- (void)toggleStatusItem:(id)sender
{
	[preferences toggleStatusItem];
}


@end

// 8200+ lines — Do I win a prize?
