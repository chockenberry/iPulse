//
//  KeyCombo.m
//
//  Created by Quentin D. Carnicelli on Tue Jun 18 2002.
//  Copyright (c) 2001 Quentin D. Carnicelli. All rights reserved.
//

#import "KeyCombo.h"

#import <AppKit/NSEvent.h>
#import <Carbon/Carbon.h>

@interface KeyCombo (Private)
	+ (NSString*)_stringForModifiers: (long)modifiers;
	+ (NSString*)_stringForKeyCode: (short)keyCode;
@end


@implementation KeyCombo

+ (id)keyCombo
{
	return [[[self alloc] init] autorelease];
}

+ (id)clearKeyCombo
{
	return [self keyComboWithKeyCode: -1 andModifiers: -1];
}

+ (id)keyComboWithKeyCode: (short)keycode andModifiers: (long)modifiers
{
	return [[[self alloc] initWithKeyCode: keycode andModifiers: modifiers] autorelease];
}

- (id)initWithKeyCode: (short)keycode andModifiers: (long)modifiers
{
	self = [super init];
	
	if( self )
	{
		mKeyCode = keycode;
		mModifiers = modifiers;
	}
	
	return self;
}

- (id)init
{
	return [self initWithKeyCode: -1 andModifiers: -1];
}

- (id)copyWithZone:(NSZone*)zone;
{
	return [self retain];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{	
	self = [self init];
	
	if( self )
	{
		[aDecoder decodeValueOfObjCType: @encode(signed short) at: &mKeyCode];
		[aDecoder decodeValueOfObjCType: @encode(signed int) at: &mModifiers];
	}
	
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{	
	[aCoder encodeValueOfObjCType: @encode(signed short) at: &mKeyCode];
	[aCoder encodeValueOfObjCType: @encode(signed int) at: &mModifiers];
}

- (BOOL)isEqual:(KeyCombo*)object
{
	BOOL equal;
	
	equal = ([object isKindOfClass: [KeyCombo class]]) &&
			([object keyCode] == [self keyCode])		 &&
			([object modifiers] == [self modifiers]);
	
	return equal;
}

- (NSString*)description
{
	return [self userDisplayRep];
}

#pragma mark -

- (short)keyCode
{
	return mKeyCode;
}

- (short)modifiers
{
	return mModifiers;
}

- (BOOL)isValid
{
#if 0
	return mKeyCode >= 0 && mModifiers > 0;
#else
	// HACK - allows function keys without modifiers to be registered
	BOOL isFunctionKey = ((mKeyCode >= 96 && mKeyCode <= 113) || mKeyCode == 118 || mKeyCode == 120 || mKeyCode == 122);
	BOOL isKeyWithModifier = (mKeyCode >= 0 && mModifiers > 0);
	return (isFunctionKey || isKeyWithModifier);
#endif
}

#pragma mark -

- (NSString*)userDisplayRep
{
	NSString* rep;
	
	if( [self isValid] == NO )
		rep = NSLocalizedString( @"None", @"Key Combo text for 'No Key Combo Set'" );
	else
	{
		rep = [NSString stringWithFormat: @"%@%@",
				[KeyCombo _stringForModifiers: mModifiers],
				[KeyCombo _stringForKeyCode: mKeyCode]];
	}

	return rep;
}

+ (NSString*)_stringForModifiers: (long)modifiers
{
	static long modToChar[4][2] =
	{
		{ cmdKey, 		0x23180000 },
		{ optionKey,	0x23250000 },
		{ controlKey,	0x005E0000 },
		{ shiftKey,		0x21e70000 }
	};

	NSString* str;
//	NSString* charStr;
	long i;

	str = [NSString string];

	for( i = 0; i < 4; i++ )
	{
		if( modifiers & modToChar[i][0] )
		{
			CFStringRef modCharRef = CFStringCreateWithBytes(NULL, (UInt8 *)&modToChar[i][1], 4, kCFStringEncodingUnicode, false);
			//long modChar = CFSwapInt16BigToHost(modToChar[i][1]);
			//charStr = [NSString stringWithCharacters: (const unichar*)&modChar length: 1];
			str = [str stringByAppendingString: (NSString *)modCharRef];
			CFRelease(modCharRef);
		}
	}

	//if( [str length] )
	//	str = [str stringByAppendingString: @" "];
	
	return str;
}

+ (NSString*)_stringForKeyCode: (short)keyCode
{
	NSDictionary* dict;
	id key;
	NSString* str;
	
	dict = [self keyCodesDictionary];
	key = [NSString stringWithFormat: @"%d", keyCode];
	str = [dict objectForKey: key];
	
	if( !str )
		str = [NSString stringWithFormat: @"%X", keyCode];
	
	return str;
}

+ (NSDictionary*)keyCodesDictionary
{
	static NSDictionary* keyCodes = nil;
	
	if( keyCodes == nil )
	{
		NSString* path;
		NSString* contents;
		
		path = [[NSBundle bundleForClass: [KeyCombo class]]
					pathForResource: @"KeyCodes" ofType: @"plist"];

		contents = [NSString stringWithContentsOfFile: path encoding:NSUTF8StringEncoding error:NULL];
		keyCodes = [[contents propertyList] retain];
	}
	
	return keyCodes;
}

@end

@implementation NSUserDefaults (KeyComboAdditions)

- (void)setKeyCombo: (KeyCombo*)combo forKey: (NSString*)key
{
	NSData* data;
	
	if( combo )
		data = [NSArchiver archivedDataWithRootObject: combo];
	else
		data = nil;
	
	[self setObject: data forKey: key];
}

- (KeyCombo*)keyComboForKey: (NSString*)key
{
	NSData* data;
	KeyCombo* combo;
	
	combo = nil;
	
	data = [self objectForKey: key];
	
	if( data )
		combo =  [NSUnarchiver unarchiveObjectWithData: data];

	if( combo == nil )
		combo = [KeyCombo clearKeyCombo];

	return combo;
}

@end





