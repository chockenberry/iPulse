//
//	Preferences.m - Preferences Controller Class
//


#import "Preferences.h"

// for hotkey library
#import "KeyCombo.h"
#import "KeyComboPanel.h"
#import "HotKeyCenter.h"


@implementation Preferences

+ (NSColor *) colorAlphaFromString:(NSString *)string
{
	float	r, g, b, a;
	const char *cString = [string UTF8String];
	if (cString == NULL)
	{
		r = 0.0; g = 0.0; b = 0.0; a = 1.0;
	}
	else
	{
		sscanf(cString, "%f %f %f %f", &r, &g, &b, &a);
	}
	
	//NSLog(@"Preferences: colorAlphaFromString: %@ -> NSColor with %f, %f, %f, %f", string, r, g, b, a);
	
	return ([NSColor colorWithCalibratedRed:r green:g blue:b alpha:a]);
}

+ (NSString *) stringFromColorAlpha:(NSColor *)color
{
	NSString *result;
	CGFloat r, g, b, a;
	[[color colorUsingColorSpaceName:@"NSCalibratedRGBColorSpace"] getRed:&r green:&g blue:&b alpha:&a];

	result = [NSString stringWithFormat:@"%f %f %f %f", r, g, b, a];

	//NSLog(@"Preferences: stringFromColorAlpha: NSColor with %f, %f, %f, %f -> %@", r, g, b, a, result);
	
	return (result);
}

#pragma mark -

- (void) awakeFromNib
{
	// retain the accesory view that's used in the save panel since it is automatically released after a save
	[saveAccessoryView retain];

	// update dock icon controls
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		
		BOOL showDockIcon = [defaults boolForKey:GLOBAL_SHOW_DOCK_ICON_KEY];
		if (showDockIcon) {
			[globalShowDockIcon setState:1];
		}
		else {
			[globalShowDockIcon setState:0];
			
			[globalShowDock setState:0];
			[globalShowDock setEnabled:NO];
			[globalDockIncludeText setEnabled:NO];
			
			[windowShowFloating setState:1];
			[windowShowFloating setEnabled:NO];
		}
	}
	
	// disable PowerMate
	{
		[globalUsePowerMate setState:0];
		[globalUsePowerMate setEnabled:NO];
		[globalPowerMateOutputType setEnabled:NO];
		[globalPowerMateInputType setEnabled:NO];
	}
}

#pragma mark -

- (BOOL)preferencesCanBeUpdated
{
	BOOL result = NO;
	
	BOOL isDirty = [[[NSUserDefaults standardUserDefaults] objectForKey:MISCELLANEOUS_IS_DIRTY] boolValue];

	if (! isDirty)
	{
		result = YES;
	}
	else
	{
		int choice = NSRunAlertPanel(NSLocalizedString(@"PreferencesWarningLabel", nil),
				NSLocalizedString(@"PreferencesWarningMessage", nil),
				NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"Continue", nil), nil);
		if (choice != NSAlertDefaultReturn)
		{
			result = YES;
		}
	}
	
	return (result);
}

#pragma mark -

- (void)showUpdateFrequency:(int)freq
{
	NSString *updateSpeedString = NSLocalizedString(@"UpdateSpeed", nil);
	float rate = freq / 10.0;
	[globalUpdateFrequencyLabel setStringValue:[NSString stringWithFormat:updateSpeedString, rate, (1.0 / rate) * 60.0]];
}

- (void)showSchedulingPriority:(int)priority
{
	NSString *string = NSLocalizedString(@"SchedulingPriority", nil);
	[globalSchedulingPriorityLabel setStringValue:[NSString stringWithFormat:string, priority]];
}

- (void)showHoldTime:(float)holdExponent
{
	float holdTimeSeconds = rint(pow(60.0, holdExponent));
	
	NSString *stringFormat;
	NSString *string;
	if (holdTimeSeconds <= 60.0)
	{
		stringFormat = NSLocalizedString(@"HoldTimeSeconds", nil);
		string = [NSString stringWithFormat:stringFormat, holdTimeSeconds];
	}
	else
	{
		stringFormat = NSLocalizedString(@"HoldTimeMinutes", nil);
		string = [NSString stringWithFormat:stringFormat, (holdTimeSeconds / 60.0)];
	}
	[globalHoldTimeLabel setStringValue:string];
}

- (void)showWindowSize:(float)size
{
	NSString *windowSizeString = NSLocalizedString(@"WindowSize", nil);
	[windowFloatingSizeLabel setStringValue:[NSString stringWithFormat:windowSizeString, size, size, (100.0 * (size/128.0))]];
}

#pragma mark -

- (void)setApplicationVersion:(NSString *)newApplicationVersion
{
	[newApplicationVersion retain];

	[applicationVersion release];

	applicationVersion = newApplicationVersion;
}

- (void)setPowerMateIsAvailable:(BOOL)newPowerMateIsAvailable
{
	powerMateIsAvailable = newPowerMateIsAvailable;
	
	[self updatePanel];
}

#pragma mark -

- (void)updatePanel
{
	if (panel)
	{
		float floatValue;
		int intValue;

		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		if (applicationVersion)
		{
			[mainVersionNumber setStringValue:applicationVersion];
		}

		// set the image name
		{
			NSData *data = [defaults objectForKey:OTHER_IMAGE_KEY];
			if (data)
			{
				NSImage *image = [NSUnarchiver unarchiveObjectWithData:data];
				if (image)
				{
					NSString *imageName = [image name];
					if (imageName)
					{
						[otherImageLabel setStringValue:[image name]];
					}
					else
					{
						[otherImageLabel setStringValue:NSLocalizedString(@"None", nil)];
					}
				}
				else
				{
					[otherImageLabel setStringValue:NSLocalizedString(@"None", nil)];
				}
			}
			else
			{
				[otherImageLabel setStringValue:NSLocalizedString(@"None", nil)];
			}
		}

		// set the image name
		{
			NSData *data = [defaults objectForKey:GLOBAL_STATUS_IMAGE_KEY];
			if (data)
			{
				NSImage *image = [NSUnarchiver unarchiveObjectWithData:data];
				if (image)
				{
					NSString *imageName = [image name];
					if (imageName)
					{
						[globalStatusImageLabel setStringValue:[image name]];
					}
					else
					{
						[globalStatusImageLabel setStringValue:@""];
					}
				}
				else
				{
					[globalStatusImageLabel setStringValue:@""];
				}
			}
			else
			{
				[globalStatusImageLabel setStringValue:@""];
			}
		}

		[processorShowGauge setState:[[defaults objectForKey:PROCESSOR_SHOW_GAUGE_KEY] boolValue]];
		[processorShowText setState:[[defaults objectForKey:PROCESSOR_SHOW_TEXT_KEY] boolValue]];
		[processorSystemColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_SYSTEM_COLOR_KEY]]];
		[processorUserColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_USER_COLOR_KEY]]];
		[processorNiceColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_NICE_COLOR_KEY]]];
		[processorLoadColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:PROCESSOR_LOAD_COLOR_KEY]]];
		[processorIncludeNice setState:[[defaults objectForKey:PROCESSOR_INCLUDE_NICE_KEY] boolValue]];
	
		[memoryShowGauge setState:[[defaults objectForKey:MEMORY_SHOW_GAUGE_KEY] boolValue]];
		[memoryShowText setState:[[defaults objectForKey:MEMORY_SHOW_TEXT_KEY] boolValue]];
		[memorySystemActiveColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SYSTEMACTIVE_COLOR_KEY]]];
		[memoryInactiveFreeColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_INACTIVEFREE_COLOR_KEY]]];
		[memorySwappingShowGauge setState:[[defaults objectForKey:MEMORY_SWAPPING_SHOW_GAUGE_KEY] boolValue]];
		[memorySwappingShowText setState:[[defaults objectForKey:MEMORY_SWAPPING_SHOW_TEXT_KEY] boolValue]];
		[memorySwappingInColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SWAPPING_IN_COLOR_KEY]]];
		[memorySwappingOutColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MEMORY_SWAPPING_OUT_COLOR_KEY]]];
	
		[diskShowGauge setState:[[defaults objectForKey:DISK_SHOW_GAUGE_KEY] boolValue]];
		[diskShowText setState:[[defaults objectForKey:DISK_SHOW_TEXT_KEY] boolValue]];
		[diskSumAll setState:[[defaults objectForKey:DISK_SUM_ALL_KEY] boolValue]];
		[diskUsedColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_USED_COLOR_KEY]]];
		[diskWarningColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_WARNING_COLOR_KEY]]];
		[diskBackgroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_BACKGROUND_COLOR_KEY]]];
		[diskIOShowGauge setState:[[defaults objectForKey:DISK_IO_SHOW_GAUGE_KEY] boolValue]];
		[diskReadColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_READ_COLOR_KEY]]];
		[diskWriteColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_WRITE_COLOR_KEY]]];
		[diskHighColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:DISK_HIGH_COLOR_KEY]]];
		[diskShowActivity setState:[[defaults objectForKey:DISK_SHOW_ACTIVITY_KEY] boolValue]];
		[diskShowPeak setState:[[defaults objectForKey:DISK_SHOW_PEAK_KEY] boolValue]];
		[diskScale selectItemAtIndex:[diskScale indexOfItemWithTag:[[defaults objectForKey:DISK_SCALE_KEY] intValue]]];
		
		[networkShowGauge setState:[[defaults objectForKey:NETWORK_SHOW_GAUGE_KEY] boolValue]];
		[networkShowText setState:[[defaults objectForKey:NETWORK_SHOW_TEXT_KEY] boolValue]];
		[networkInColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_IN_COLOR_KEY]]];
		[networkOutColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_OUT_COLOR_KEY]]];
		[networkHighColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:NETWORK_HIGH_COLOR_KEY]]];
		[networkShowActivity setState:[[defaults objectForKey:NETWORK_SHOW_ACTIVITY_KEY] boolValue]];
		[networkShowPeak setState:[[defaults objectForKey:NETWORK_SHOW_PEAK_KEY] boolValue]];
		[networkScale selectItemAtIndex:[networkScale indexOfItemWithTag:[[defaults objectForKey:NETWORK_SCALE_KEY] intValue]]];
	
		[mobilityBatteryShowGauge setState:[[defaults objectForKey:MOBILITY_BATTERY_SHOW_GAUGE_KEY] boolValue]];
		[mobilityBatteryColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_COLOR_KEY]]];
		[mobilityBatteryChargeColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_CHARGE_COLOR_KEY]]];
		[mobilityBatteryFullColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BATTERY_FULL_COLOR_KEY]]];
		[mobilityWirelessShowGauge setState:[[defaults objectForKey:MOBILITY_WIRELESS_SHOW_GAUGE_KEY] boolValue]];
		[mobilityWirelessColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_WIRELESS_COLOR_KEY]]];
		[mobilityBackgroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_BACKGROUND_COLOR_KEY]]];
		[mobilityWarningColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:MOBILITY_WARNING_COLOR_KEY]]];
	
		[historyShowGauge setState:[[defaults objectForKey:HISTORY_SHOW_GAUGE_KEY] boolValue]];
		[historyLoadColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:HISTORY_LOAD_COLOR_KEY]]];
		floatValue = [[defaults objectForKey:HISTORY_LOAD_MINIMUM_KEY] floatValue];
		[historyLoadMinimum setFloatValue:floatValue];
		[historyLoadMinimumLabel setStringValue:[NSString stringWithFormat:@"%.2f", floatValue]];
		floatValue = [[defaults objectForKey:HISTORY_LOAD_MAXIMUM_KEY] floatValue];
		[historyLoadMaximum setFloatValue:floatValue];
		[historyLoadMaximumLabel setStringValue:[NSString stringWithFormat:@"%.2f", floatValue]];
	
		[timeShowGauge setState:[[defaults objectForKey:TIME_SHOW_GAUGE_KEY] boolValue]];
		[timeTraditional setState:[[defaults objectForKey:TIME_TRADITIONAL_KEY] boolValue]];
		[timeUse24Hour setState:[[defaults objectForKey:TIME_USE_24_HOUR_KEY] boolValue]];
		[timeNoonAtTop setState:[[defaults objectForKey:TIME_NOON_AT_TOP_KEY] boolValue]];
		[timeHandsColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:TIME_HANDS_COLOR_KEY]]];
		[timeSecondsColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:TIME_SECONDS_COLOR_KEY]]];
		[timeDateForegroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_FOREGROUND_COLOR_KEY]]];
		[timeDateBackgroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:TIME_DATE_BACKGROUND_COLOR_KEY]]];
		[timeDateStyle selectItemAtIndex:[timeDateStyle indexOfItemWithTag:[[defaults objectForKey:TIME_DATE_STYLE_KEY] intValue]]];
		[timeRing setState:[[defaults objectForKey:TIME_RING_KEY] boolValue]];
		intValue = [timeRingSound indexOfItemWithTitle:[defaults stringForKey:TIME_RING_SOUND_KEY]];
		if (intValue < 0 || intValue >= [timeRingSound numberOfItems])
		{
			intValue = 0; // if list of sounds changes, reset to first position
		}
		[timeRingSound selectItemAtIndex:intValue];
		[timeShowWeek setState:[[defaults objectForKey:TIME_SHOW_WEEK_KEY] boolValue]];
	
		[otherTextShadowDark setState:[[defaults objectForKey:OTHER_TEXT_SHADOW_DARK_KEY] boolValue]];
		[otherMarkerColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:OTHER_MARKER_COLOR_KEY]]];
		[otherTextColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:OTHER_TEXT_COLOR_KEY]]];
		[otherTextShadowDark setState:[[defaults objectForKey:OTHER_TEXT_SHADOW_DARK_KEY] boolValue]];
		[otherBackgroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:OTHER_BACKGROUND_COLOR_KEY]]];
		[otherImageTransparency setFloatValue:[[defaults objectForKey:OTHER_IMAGE_TRANSPARENCY_KEY] floatValue]];

		[windowShowFloating setState:[[defaults objectForKey:WINDOW_SHOW_FLOATING_KEY] boolValue]];
		[windowFloatingShadow setState:[[defaults objectForKey:WINDOW_FLOATING_SHADOW_KEY] boolValue]];
		[windowFloatingNoHide setState:[[defaults objectForKey:WINDOW_FLOATING_NO_HIDE_KEY] boolValue]];
		[windowFloatingIgnoreClick setState:[[defaults objectForKey:WINDOW_FLOATING_IGNORE_CLICK_KEY] boolValue]];
		[windowFloatingLevel selectItemAtIndex:[windowFloatingLevel indexOfItemWithTag:[[defaults objectForKey:WINDOW_FLOATING_LEVEL_KEY] intValue]]];
		floatValue = [[defaults objectForKey:WINDOW_FLOATING_SIZE_KEY] floatValue];
		[self showWindowSize:floatValue];
		[windowFloatingSize setFloatValue:floatValue];		
		[windowShowInfo setState:[[defaults objectForKey:WINDOW_SHOW_INFO_KEY] boolValue]];
		[windowInfoDelay setState:[[defaults objectForKey:WINDOW_INFO_DELAY_KEY] boolValue]];
		[windowInfoFadeIn selectItemAtIndex:[windowInfoFadeIn indexOfItemWithTag:[[defaults objectForKey:WINDOW_INFO_FADE_IN_KEY] intValue]]];
		[windowInfoFadeOut selectItemAtIndex:[windowInfoFadeOut indexOfItemWithTag:[[defaults objectForKey:WINDOW_INFO_FADE_OUT_KEY] intValue]]];
		[windowInfoForegroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_FOREGROUND_COLOR_KEY]]];
		[windowInfoBackgroundColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_BACKGROUND_COLOR_KEY]]];
		[windowInfoHighlightColor setColor:[Preferences colorAlphaFromString:[defaults stringForKey:WINDOW_INFO_HIGHLIGHT_COLOR_KEY]]];
	
		[globalShowDockIcon setState:[[defaults objectForKey:GLOBAL_SHOW_DOCK_ICON_KEY] boolValue]];
		[globalShowDock setState:[[defaults objectForKey:GLOBAL_SHOW_DOCK_KEY] boolValue]];
		[globalDockIncludeText setState:[[defaults objectForKey:GLOBAL_DOCK_INCLUDE_TEXT_KEY] boolValue]];
		intValue = [[defaults objectForKey:GLOBAL_UPDATE_FREQUENCY_KEY] intValue];
		[self showUpdateFrequency:intValue];
		[globalUpdateFrequency setIntValue:intValue];
		intValue = [[defaults objectForKey:GLOBAL_SCHEDULING_PRIORITY_KEY] intValue];
		[self showSchedulingPriority:intValue];
		[globalSchedulingPriority setIntValue:intValue];
		floatValue = [[defaults objectForKey:GLOBAL_HOLD_TIME_KEY] floatValue];
		[self showHoldTime:floatValue];
		[globalHoldTime setFloatValue:floatValue];
		[globalUnitsType selectItemAtIndex:[globalUnitsType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_UNITS_TYPE_KEY] intValue]]];
		[globalShowSelf setState:[[defaults objectForKey:GLOBAL_SHOW_SELF_KEY] boolValue]];
		[globalToggleFloatingWindowHotkeyLabel setStringValue:[[defaults keyComboForKey:GLOBAL_TOGGLE_FLOATING_WINDOW_KEY] userDisplayRep]];
		[globalToggleIgnoreMouseHotkeyLabel setStringValue:[[defaults keyComboForKey:GLOBAL_TOGGLE_IGNORE_MOUSE_KEY] userDisplayRep]];
		[globalLockInfoWindowHotkeyLabel setStringValue:[[defaults keyComboForKey:GLOBAL_LOCK_INFO_WINDOW_KEY] userDisplayRep]];
		[globalToggleStatusItemHotkeyLabel setStringValue:[[defaults keyComboForKey:GLOBAL_TOGGLE_STATUS_ITEM_KEY] userDisplayRep]];
		[globalShowStatus setState:[[defaults objectForKey:GLOBAL_SHOW_STATUS_KEY] boolValue]];
		[globalUsePowerMate setState:[[defaults objectForKey:GLOBAL_USE_POWERMATE_KEY] boolValue]];
		[globalPowerMateOutputType selectItemAtIndex:[globalPowerMateOutputType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_POWERMATE_OUTPUT_TYPE_KEY] intValue]]];
		[globalPowerMateInputType selectItemAtIndex:[globalPowerMateInputType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_POWERMATE_INPUT_TYPE_KEY] intValue]]];
		if (powerMateIsAvailable)
		{
			[globalUsePowerMate setEnabled:YES];
			[globalPowerMateOutputType setEnabled:YES];
			[globalPowerMateInputType setEnabled:YES];
		}
		else
		{
			[globalUsePowerMate setState:0];
			[globalUsePowerMate setEnabled:NO];
			[globalPowerMateOutputType setEnabled:NO];
			[globalPowerMateInputType setEnabled:NO];
		}

		[globalStatusUpperBarType selectItemAtIndex:[globalStatusUpperBarType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_STATUS_UPPER_BAR_TYPE_KEY] intValue]]];
		[globalStatusUpperBarColorLeft setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY]]];
		[globalStatusUpperBarColorRight setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY]]];
		[globalStatusUpperBarColorAlert setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY]]];

		[globalStatusUpperDotType selectItemAtIndex:[globalStatusUpperDotType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_STATUS_UPPER_DOT_TYPE_KEY] intValue]]];
		[globalStatusUpperDotColorLeft setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY]]];
		[globalStatusUpperDotColorRight setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY]]];
		[globalStatusUpperDotColorAlert setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY]]];

		[globalStatusLowerBarType selectItemAtIndex:[globalStatusLowerBarType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_STATUS_LOWER_BAR_TYPE_KEY] intValue]]];
		[globalStatusLowerBarColorLeft setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY]]];
		[globalStatusLowerBarColorRight setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY]]];
		[globalStatusLowerBarColorAlert setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY]]];

		[globalStatusLowerDotType selectItemAtIndex:[globalStatusLowerDotType indexOfItemWithTag:[[defaults objectForKey:GLOBAL_STATUS_LOWER_DOT_TYPE_KEY] intValue]]];
		[globalStatusLowerDotColorLeft setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY]]];
		[globalStatusLowerDotColorRight setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY]]];
		[globalStatusLowerDotColorAlert setColor:[Preferences colorAlphaFromString:[defaults stringForKey:GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY]]];
	}
}

- (IBAction)showPreferences:(id)sender
{
	if (! panel) {
		if ([NSBundle loadNibNamed:@"Preferences" owner:self])
		{
			[panel center];
			
			[self setupToolbar];
			[self setViewForPanel:mainView];
		}
		else
		{
			NSLog (@"Preferences: showPreferences: Failed to load Preferences.nib");
			return;
		}

		{
			NSMenu *newMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@"Sounds"];
	
			NSString *file;
			NSDirectoryEnumerator *enumerator;
			BOOL needSeparator = YES;
			
			enumerator = [[NSFileManager defaultManager] enumeratorAtPath:@"/System/Library/Sounds"];
			while (file = [enumerator nextObject])
			{
				if ([[file pathExtension] isEqualToString:@"aiff"])
				{
					NSMenuItem *newItem;
					newItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:[file stringByDeletingPathExtension] action:NULL keyEquivalent:@""];
					[newMenu addItem:newItem];
					[newItem release];
				}
			}
	
			enumerator = [[NSFileManager defaultManager] enumeratorAtPath:[@"~/Library/Sounds" stringByExpandingTildeInPath]];
			while (file = [enumerator nextObject])
			{
				if ([[file pathExtension] isEqualToString:@"aiff"])
				{
					NSMenuItem *newItem;
					
					if (needSeparator)
					{
						[newMenu addItem:[NSMenuItem separatorItem]];
						needSeparator = NO;
					}
				
					newItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:[file stringByDeletingPathExtension] action:NULL keyEquivalent:@""];
					[newMenu addItem:newItem];
					[newItem release];
					
				}
			}
	
			[timeRingSound setMenu:newMenu];
			[newMenu release];
		}
	}
	
	[self updatePanel];
	
	[panel makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark -

- (void)resetDefaults
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSEnumerator *enumerator = [[[defaults dictionaryRepresentation] allKeys] objectEnumerator];
	
	// the images are special because they send notifications
	[self removeStatusImage:self];
	[self removeImage:self];
	
	NSString *key;
	while (key = [enumerator nextObject])
	{
		// remove everything except registration info
		if ([key hasPrefix:REGISTRATION_PREFIX] == NO)
		{
			[defaults removeObjectForKey:key];
		}
	}

	[defaults synchronize];
}

- (IBAction)restoreSettings:(id)sender
{
	if ([self preferencesCanBeUpdated])
	{
		[self resetDefaults];
		
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:0] forKey:MISCELLANEOUS_IS_DIRTY];

		[self showPreferences:nil];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_WINDOW_CHANGED object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_STATUS_CHANGED object:nil];
	}
}

- (IBAction)saveSettings:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];

	[savePanel setAccessoryView:saveAccessoryView];
	[savePanel setNameFieldStringValue:@"Settings.ipulse"];
	[savePanel beginSheetModalForWindow:panel completionHandler:^(NSInteger result) {
		if (result == NSFileHandlingPanelOKButton)
		{
			BOOL includeFloatingWindow = [saveIncludeFloatingWindow state];
			BOOL includeInfoWindow = [saveIncludeInfoWindow state];
			BOOL includeStatusItem = [saveIncludeStatusItem state];
			//NSLog(@"floatingWindow = %d, infoWindow = %d, statusItem = %d", includeFloatingWindow, includeInfoWindow, includeStatusItem);
			
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSDictionary *defaultsDictionary = [defaults dictionaryRepresentation];
			NSMutableDictionary *saveDictionary = [NSMutableDictionary dictionaryWithDictionary:defaultsDictionary];
			
			NSEnumerator *enumerator = [[saveDictionary allKeys] objectEnumerator];
			NSString *key;
			while (key = [enumerator nextObject])
			{
				BOOL removeKey = YES;
				
				if (includeFloatingWindow)
				{
					if ([key hasPrefix:SETTINGS_PREFIX])
					{
						removeKey = NO;
					}
				}
				if (includeInfoWindow)
				{
					if ([key isEqualToString:WINDOW_INFO_FOREGROUND_COLOR_KEY] ||
						[key isEqualToString:WINDOW_INFO_BACKGROUND_COLOR_KEY] ||
						[key isEqualToString:WINDOW_INFO_HIGHLIGHT_COLOR_KEY])
					{
						removeKey = NO;
					}
				}
				if (includeStatusItem)
				{
					if ([key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY] ||
						[key isEqualToString:GLOBAL_STATUS_IMAGE_KEY])
					{
						removeKey = NO;
					}
				}
				
				if (removeKey)
				{
					[saveDictionary removeObjectForKey:key];
				}
			}
			//NSLog(@"Preferences: saveSettingsSheetEnded: filename = %@", [sheet filename]);
			[saveDictionary writeToURL:[savePanel URL] atomically:NO];
			
			[defaults setObject:[NSNumber numberWithInt:0] forKey:MISCELLANEOUS_IS_DIRTY];
		}
	}];
}

- (BOOL)loadSettingsFromURL:(NSURL *)URL
{
	if ([self preferencesCanBeUpdated])
	{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

		// overwrite current settings
		{
			NSDictionary *loadDictionary = [NSDictionary dictionaryWithContentsOfURL:URL];
			
			BOOL hasStatusImage = NO;
			BOOL hasStatusOther = NO;
			
			NSEnumerator *enumerator = [[loadDictionary allKeys] objectEnumerator];
			NSString *key;
			while (key = [enumerator nextObject])
			{
				if ([key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY] ||
					[key isEqualToString:GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY])
				{
					hasStatusOther = YES;
				}
				if ([key isEqualToString:GLOBAL_STATUS_IMAGE_KEY])
				{
					hasStatusImage = YES;
				}
				
				[defaults setObject:[loadDictionary objectForKey:key] forKey:key]; 
			}
			
			if (hasStatusOther && ! hasStatusImage)
			{
				// special case: the file has status info in it, but no status image so we need to remove the current image
				// so that the default image will be used
				[defaults removeObjectForKey:GLOBAL_STATUS_IMAGE_KEY];
			}
			
			[defaults setObject:[NSNumber numberWithInt:0] forKey:MISCELLANEOUS_IS_DIRTY];
		}		
		[defaults synchronize];
	
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_WINDOW_CHANGED object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_STATUS_CHANGED object:nil];
		
		return (YES);
	}
	else
	{
		return (NO);
	}
}

- (void)loadSettingsSheetEnded:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSOKButton)
	{
		[self loadSettingsFromURL:[sheet URL]];

		[self showPreferences:nil];
	}
}

- (IBAction)loadSettings:(id)sender
{
	if ([self preferencesCanBeUpdated])
	{
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		NSArray *fileTypes = [NSArray arrayWithObjects:@"ipulse",nil];

		[openPanel setAllowedFileTypes:fileTypes];
		[openPanel beginSheetModalForWindow:panel completionHandler:^(NSInteger result) {
			if (result == NSFileHandlingPanelOKButton)
			{
				[self loadSettingsFromURL:[openPanel URL]];
				
				[self showPreferences:nil];
			}
		}];
	}
}

- (IBAction)loadImage:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	NSArray *fileTypes = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"pdf", @"png", @"icns", nil];
	
	[openPanel setAllowedFileTypes:fileTypes];
	[openPanel beginSheetModalForWindow:panel completionHandler:^(NSInteger result) {
		if (result == NSFileHandlingPanelOKButton)
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSURL *URL = [openPanel URL];
			NSImage *image = [[NSImage alloc] initWithContentsOfURL:URL];
			[image setName:[[[URL absoluteString] stringByDeletingPathExtension] lastPathComponent]];
			NSData *imageAsData = [NSArchiver archivedDataWithRootObject:image];
			[defaults setObject:imageAsData forKey:OTHER_IMAGE_KEY];
			[image release];
			
			// make image fully opaque to start with
			[defaults setObject:[NSNumber numberWithFloat:1.0] forKey:OTHER_IMAGE_TRANSPARENCY_KEY];
			
			[self showPreferences:nil];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_WINDOW_CHANGED object:nil];
		}
	}];
}

- (IBAction)removeImage:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults removeObjectForKey:OTHER_IMAGE_KEY];
	
	[self showPreferences:nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_WINDOW_CHANGED object:nil];
}

- (IBAction)loadStatusImage:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	NSArray *fileTypes = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"pdf", @"png", @"icns", nil];
	
	[openPanel setAllowedFileTypes:fileTypes];
	[openPanel beginSheetModalForWindow:panel completionHandler:^(NSInteger result) {
		if (result == NSFileHandlingPanelOKButton)
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			NSURL *URL = [openPanel URL];
			NSImage *image = [[NSImage alloc] initWithContentsOfURL:URL];
			[image setName:[[[URL absoluteString] stringByDeletingPathExtension] lastPathComponent]];
			NSData *imageAsData = [NSArchiver archivedDataWithRootObject:image];
			[defaults setObject:imageAsData forKey:GLOBAL_STATUS_IMAGE_KEY];
			[image release];
			
			[self showPreferences:nil];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_STATUS_CHANGED object:nil];
		}
	}];
}

- (IBAction)removeStatusImage:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults removeObjectForKey:GLOBAL_STATUS_IMAGE_KEY];
	
	[self showPreferences:nil];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_STATUS_CHANGED object:nil];
}

- (IBAction)testSound:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	[[NSSound soundNamed:[defaults stringForKey:TIME_RING_SOUND_KEY]] play];
}

- (IBAction)loadIconfactory:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.iconfactory.com"]];
}

- (IBAction)preferencesChanged:(id)sender
{
	float floatValue;
	int intValue;
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	[defaults setObject:[NSNumber numberWithInt:[processorShowGauge state]] forKey:PROCESSOR_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[processorShowText state]] forKey:PROCESSOR_SHOW_TEXT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[processorSystemColor color]] forKey:PROCESSOR_SYSTEM_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[processorUserColor color]] forKey:PROCESSOR_USER_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[processorNiceColor color]] forKey:PROCESSOR_NICE_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[processorLoadColor color]] forKey:PROCESSOR_LOAD_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[processorIncludeNice state]] forKey:PROCESSOR_INCLUDE_NICE_KEY];
	
	[defaults setObject:[NSNumber numberWithInt:[memoryShowGauge state]] forKey:MEMORY_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[memoryShowText state]] forKey:MEMORY_SHOW_TEXT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[memorySystemActiveColor color]] forKey:MEMORY_SYSTEMACTIVE_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[memoryInactiveFreeColor color]] forKey:MEMORY_INACTIVEFREE_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[memorySwappingShowGauge state]] forKey:MEMORY_SWAPPING_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[memorySwappingShowText state]] forKey:MEMORY_SWAPPING_SHOW_TEXT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[memorySwappingInColor color]] forKey:MEMORY_SWAPPING_IN_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[memorySwappingOutColor color]] forKey:MEMORY_SWAPPING_OUT_COLOR_KEY];
	
	[defaults setObject:[NSNumber numberWithInt:[diskShowGauge state]] forKey:DISK_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[diskShowText state]] forKey:DISK_SHOW_TEXT_KEY];
	[defaults setObject:[NSNumber numberWithInt:[diskSumAll state]] forKey:DISK_SUM_ALL_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskUsedColor color]] forKey:DISK_USED_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskWarningColor color]] forKey:DISK_WARNING_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskBackgroundColor color]] forKey:DISK_BACKGROUND_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[diskIOShowGauge state]] forKey:DISK_IO_SHOW_GAUGE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskReadColor color]] forKey:DISK_READ_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskWriteColor color]] forKey:DISK_WRITE_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[diskHighColor color]] forKey:DISK_HIGH_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[diskShowActivity state]] forKey:DISK_SHOW_ACTIVITY_KEY];
	[defaults setObject:[NSNumber numberWithInt:[diskShowPeak state]] forKey:DISK_SHOW_PEAK_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[diskScale selectedItem] tag]] forKey:DISK_SCALE_KEY];
	
	[defaults setObject:[NSNumber numberWithInt:[networkShowGauge state]] forKey:NETWORK_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[networkShowText state]] forKey:NETWORK_SHOW_TEXT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[networkInColor color]] forKey:NETWORK_IN_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[networkOutColor color]] forKey:NETWORK_OUT_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[networkHighColor color]] forKey:NETWORK_HIGH_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[networkShowActivity state]] forKey:NETWORK_SHOW_ACTIVITY_KEY];
	[defaults setObject:[NSNumber numberWithInt:[networkShowPeak state]] forKey:NETWORK_SHOW_PEAK_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[networkScale selectedItem] tag]] forKey:NETWORK_SCALE_KEY];
	
	[defaults setObject:[NSNumber numberWithInt:[mobilityBatteryShowGauge state]] forKey:MOBILITY_BATTERY_SHOW_GAUGE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityBatteryColor color]] forKey:MOBILITY_BATTERY_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityBatteryChargeColor color]] forKey:MOBILITY_BATTERY_CHARGE_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityBatteryFullColor color]] forKey:MOBILITY_BATTERY_FULL_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[mobilityWirelessShowGauge state]] forKey:MOBILITY_WIRELESS_SHOW_GAUGE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityWirelessColor color]] forKey:MOBILITY_WIRELESS_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityBackgroundColor color]] forKey:MOBILITY_BACKGROUND_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[mobilityWarningColor color]] forKey:MOBILITY_WARNING_COLOR_KEY];

	[defaults setObject:[NSNumber numberWithInt:[historyShowGauge state]] forKey:HISTORY_SHOW_GAUGE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[historyLoadColor color]] forKey:HISTORY_LOAD_COLOR_KEY];
	floatValue = [historyLoadMinimum floatValue];
	[historyLoadMinimumLabel setStringValue:[NSString stringWithFormat:@"%.2f", floatValue]];
	[defaults setObject:[NSNumber numberWithFloat:floatValue] forKey:HISTORY_LOAD_MINIMUM_KEY];
	floatValue = [historyLoadMaximum floatValue];
	[historyLoadMaximumLabel setStringValue:[NSString stringWithFormat:@"%.2f", floatValue]];
	[defaults setObject:[NSNumber numberWithFloat:[historyLoadMaximum floatValue]] forKey:HISTORY_LOAD_MAXIMUM_KEY];

	[defaults setObject:[NSNumber numberWithInt:[timeShowGauge state]] forKey:TIME_SHOW_GAUGE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[timeTraditional state]] forKey:TIME_TRADITIONAL_KEY];
	[defaults setObject:[NSNumber numberWithInt:[timeUse24Hour state]] forKey:TIME_USE_24_HOUR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[timeNoonAtTop state]] forKey:TIME_NOON_AT_TOP_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[timeHandsColor color]] forKey:TIME_HANDS_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[timeSecondsColor color]] forKey:TIME_SECONDS_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[timeDateForegroundColor color]] forKey:TIME_DATE_FOREGROUND_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[timeDateBackgroundColor color]] forKey:TIME_DATE_BACKGROUND_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[timeDateStyle selectedItem] tag]] forKey:TIME_DATE_STYLE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[timeRing state]] forKey:TIME_RING_KEY];
	[defaults setObject:[NSString stringWithString:[timeRingSound title]] forKey:TIME_RING_SOUND_KEY];
	[defaults setObject:[NSNumber numberWithInt:[timeShowWeek state]] forKey:TIME_SHOW_WEEK_KEY];

	[defaults setObject:[Preferences stringFromColorAlpha:[otherMarkerColor color]] forKey:OTHER_MARKER_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[otherTextColor color]] forKey:OTHER_TEXT_COLOR_KEY];
	[defaults setObject:[NSNumber numberWithInt:[otherTextShadowDark state]] forKey:OTHER_TEXT_SHADOW_DARK_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[otherBackgroundColor color]] forKey:OTHER_BACKGROUND_COLOR_KEY];	
	[defaults setObject:[NSNumber numberWithFloat:[otherImageTransparency floatValue]] forKey:OTHER_IMAGE_TRANSPARENCY_KEY];

	[defaults setObject:[NSNumber numberWithInt:[windowShowFloating state]] forKey:WINDOW_SHOW_FLOATING_KEY];
	[defaults setObject:[NSNumber numberWithInt:[windowFloatingShadow state]] forKey:WINDOW_FLOATING_SHADOW_KEY];
	[defaults setObject:[NSNumber numberWithInt:[windowFloatingNoHide state]] forKey:WINDOW_FLOATING_NO_HIDE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[windowFloatingIgnoreClick state]] forKey:WINDOW_FLOATING_IGNORE_CLICK_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[windowFloatingLevel selectedItem] tag]] forKey:WINDOW_FLOATING_LEVEL_KEY];
	floatValue = [windowFloatingSize floatValue];
	[self showWindowSize:floatValue];
	[defaults setObject:[NSNumber numberWithFloat:floatValue] forKey:WINDOW_FLOATING_SIZE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[windowShowInfo state]] forKey:WINDOW_SHOW_INFO_KEY];
	[defaults setObject:[NSNumber numberWithInt:[windowInfoDelay state]] forKey:WINDOW_INFO_DELAY_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[windowInfoFadeIn selectedItem] tag]] forKey:WINDOW_INFO_FADE_IN_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[windowInfoFadeOut selectedItem] tag]] forKey:WINDOW_INFO_FADE_OUT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[windowInfoForegroundColor color]] forKey:WINDOW_INFO_FOREGROUND_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[windowInfoBackgroundColor color]] forKey:WINDOW_INFO_BACKGROUND_COLOR_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[windowInfoHighlightColor color]] forKey:WINDOW_INFO_HIGHLIGHT_COLOR_KEY];
	
	[defaults setObject:[NSNumber numberWithInt:[globalShowDock state]] forKey:GLOBAL_SHOW_DOCK_KEY];
	[defaults setObject:[NSNumber numberWithInt:[globalDockIncludeText state]] forKey:GLOBAL_DOCK_INCLUDE_TEXT_KEY];
	intValue = [globalUpdateFrequency intValue];
	[self showUpdateFrequency:intValue];
	[defaults setObject:[NSNumber numberWithInt:intValue] forKey:GLOBAL_UPDATE_FREQUENCY_KEY];	
	intValue = [globalSchedulingPriority intValue];
	[self showSchedulingPriority:intValue];	
	[defaults setObject:[NSNumber numberWithInt:intValue] forKey:GLOBAL_SCHEDULING_PRIORITY_KEY];
	floatValue = [globalHoldTime floatValue];
	[self showHoldTime:floatValue];
	[defaults setObject:[NSNumber numberWithFloat:floatValue] forKey:GLOBAL_HOLD_TIME_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[globalUnitsType selectedItem] tag]] forKey:GLOBAL_UNITS_TYPE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[globalShowSelf state]] forKey:GLOBAL_SHOW_SELF_KEY];
	[defaults setObject:[NSNumber numberWithInt:[globalShowStatus state]] forKey:GLOBAL_SHOW_STATUS_KEY];
	[defaults setObject:[NSNumber numberWithInt:[globalUsePowerMate state]] forKey:GLOBAL_USE_POWERMATE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[globalPowerMateOutputType selectedItem] tag]] forKey:GLOBAL_POWERMATE_OUTPUT_TYPE_KEY];
	[defaults setObject:[NSNumber numberWithInt:[[globalPowerMateInputType selectedItem] tag]] forKey:GLOBAL_POWERMATE_INPUT_TYPE_KEY];

	[defaults setObject:[NSNumber numberWithInt:[[globalStatusUpperBarType selectedItem] tag]] forKey:GLOBAL_STATUS_UPPER_BAR_TYPE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperBarColorLeft color]] forKey:GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperBarColorRight color]] forKey:GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperBarColorAlert color]] forKey:GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY];

	[defaults setObject:[NSNumber numberWithInt:[[globalStatusUpperDotType selectedItem] tag]] forKey:GLOBAL_STATUS_UPPER_DOT_TYPE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperDotColorLeft color]] forKey:GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperDotColorRight color]] forKey:GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusUpperDotColorAlert color]] forKey:GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY];

	[defaults setObject:[NSNumber numberWithInt:[[globalStatusLowerBarType selectedItem] tag]] forKey:GLOBAL_STATUS_LOWER_BAR_TYPE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerBarColorLeft color]] forKey:GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerBarColorRight color]] forKey:GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerBarColorAlert color]] forKey:GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY];

	[defaults setObject:[NSNumber numberWithInt:[[globalStatusLowerDotType selectedItem] tag]] forKey:GLOBAL_STATUS_LOWER_DOT_TYPE_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerDotColorLeft color]] forKey:GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerDotColorRight color]] forKey:GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY];
	[defaults setObject:[Preferences stringFromColorAlpha:[globalStatusLowerDotColorAlert color]] forKey:GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY];

	[defaults setObject:[NSNumber numberWithInt:1] forKey:MISCELLANEOUS_IS_DIRTY];

	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
}

- (void)toggleFloatingWindow
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:WINDOW_SHOW_FLOATING_KEY])
	{
		[defaults setObject:[NSNumber numberWithInt:0] forKey:WINDOW_SHOW_FLOATING_KEY];
	}
	else
	{
		[defaults setObject:[NSNumber numberWithInt:1] forKey:WINDOW_SHOW_FLOATING_KEY];
	}

	[self updatePanel];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
}

- (void)toggleIgnoreMouse
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:WINDOW_FLOATING_IGNORE_CLICK_KEY])
	{
		[defaults setObject:[NSNumber numberWithInt:0] forKey:WINDOW_FLOATING_IGNORE_CLICK_KEY];
	}
	else
	{
		[defaults setObject:[NSNumber numberWithInt:1] forKey:WINDOW_FLOATING_IGNORE_CLICK_KEY];
	}

	[self updatePanel];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
}

- (void)toggleStatusItem
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([defaults boolForKey:GLOBAL_SHOW_STATUS_KEY])
	{
		[defaults setObject:[NSNumber numberWithInt:0] forKey:GLOBAL_SHOW_STATUS_KEY];
	}
	else
	{
		[defaults setObject:[NSNumber numberWithInt:1] forKey:GLOBAL_SHOW_STATUS_KEY];
	}

	[self updatePanel];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_CHANGED object:nil];
}

- (IBAction)setShowInDock:(id)sender
{
#if 0
	NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
	NSString *infoPlistFile = [NSString stringWithFormat:@"%@/Contents/Info.plist", bundlePath];
	NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPlistFile];
	
	if ([globalShowDockIcon state] == 0)
	{
		[infoDictionary setValue:@"1" forKey:@"LSUIElement"];

		[globalShowDock setState:0];
		[globalShowDock setEnabled:NO];
		[globalDockIncludeText setEnabled:NO];
		
		[windowShowFloating setState:1];
		[windowShowFloating setEnabled:NO];
		
		[self preferencesChanged:self];
	}
	else
	{
		[infoDictionary setValue:@"0" forKey:@"LSUIElement"];

		[globalShowDock setEnabled:YES];
		[globalDockIncludeText setEnabled:YES];
		
		[windowShowFloating setEnabled:YES];
	}
	[infoDictionary writeToFile:infoPlistFile atomically:NO];

	NSString *touchCommand = [NSString stringWithFormat:@"/usr/bin/touch '%@'", bundlePath];
	//NSLog(@"touchCommand = %@", touchCommand);
	system([touchCommand UTF8String]);
#else
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if ([globalShowDockIcon state] == 0)
	{
		[defaults setBool:NO forKey:GLOBAL_SHOW_DOCK_ICON_KEY];
		
		[globalShowDock setState:0];
		[globalShowDock setEnabled:NO];
		[globalDockIncludeText setEnabled:NO];
		
		[windowShowFloating setState:1];
		[windowShowFloating setEnabled:NO];
	}
	else
	{
		[defaults setBool:YES forKey:GLOBAL_SHOW_DOCK_ICON_KEY];
		
		[globalShowDock setEnabled:YES];
		[globalDockIncludeText setEnabled:YES];
		
		[windowShowFloating setEnabled:YES];
	}
	
	[self preferencesChanged:self];
#endif
	
	[[NSAlert alertWithMessageText:NSLocalizedString(@"DockChanged", nil) defaultButton:NSLocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString(@"DockChangedText", nil)] runModal];
}

#pragma mark -

- (IBAction)setToggleFloatingWindowHotkey:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	KeyComboPanel *keyComboPanel = [KeyComboPanel sharedPanel];
	int result;
	
	KeyCombo *keyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_FLOATING_WINDOW_KEY];
		
	[keyComboPanel setKeyCombo:keyCombo];

	result = [keyComboPanel runModal];

	if (result == NSOKButton)
	{
		[defaults setKeyCombo:[keyComboPanel keyCombo] forKey:GLOBAL_TOGGLE_FLOATING_WINDOW_KEY];
		
		[self updatePanel];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_HOTKEY_CHANGED object:nil];
	}
}

- (IBAction)setToggleIgnoreMouseHotkey:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	KeyComboPanel *keyComboPanel = [KeyComboPanel sharedPanel];
	int result;
	
	KeyCombo *keyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_IGNORE_MOUSE_KEY];
		
	[keyComboPanel setKeyCombo:keyCombo];
	
	result = [keyComboPanel runModal];

	if (result == NSOKButton)
	{
		[defaults setKeyCombo:[keyComboPanel keyCombo] forKey:GLOBAL_TOGGLE_IGNORE_MOUSE_KEY];

		[self updatePanel];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_HOTKEY_CHANGED object:nil];
	}		
}

- (IBAction)setLockInfoWindowHotkey:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	KeyComboPanel *keyComboPanel = [KeyComboPanel sharedPanel];
	int result;
	
	KeyCombo *keyCombo = [defaults keyComboForKey:GLOBAL_LOCK_INFO_WINDOW_KEY];
		
	[keyComboPanel setKeyCombo:keyCombo];
	
	result = [keyComboPanel runModal];

	if (result == NSOKButton)
	{
		[defaults setKeyCombo:[keyComboPanel keyCombo] forKey:GLOBAL_LOCK_INFO_WINDOW_KEY];

		[self updatePanel];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_HOTKEY_CHANGED object:nil];
	}		
}

- (IBAction)setToggleStatusItemHotkey:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	KeyComboPanel *keyComboPanel = [KeyComboPanel sharedPanel];
	int result;
	
	KeyCombo *keyCombo = [defaults keyComboForKey:GLOBAL_TOGGLE_STATUS_ITEM_KEY];
		
	[keyComboPanel setKeyCombo:keyCombo];
	
	result = [keyComboPanel runModal];

	if (result == NSOKButton)
	{
		[defaults setKeyCombo:[keyComboPanel keyCombo] forKey:GLOBAL_TOGGLE_STATUS_ITEM_KEY];

		[self updatePanel];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:PREFERENCES_HOTKEY_CHANGED object:nil];
	}		
}


#pragma mark -

- (int)windowNumber
{
	return (panel ? [panel windowNumber] : 0);
}

#define TOOLBAR_IDENTIFIER @"iPulse Toolbar"
#define MAIN_ITEM_IDENTIFIER @"Main"
#define CPU_ITEM_IDENTIFIER @"CPU"
#define MEMORY_ITEM_IDENTIFIER @"Memory"
#define DISK_ITEM_IDENTIFIER @"Disk"
#define NETWORK_ITEM_IDENTIFIER @"Network"
#define MOBILITY_ITEM_IDENTIFIER @"Mobility"
#define HISTORY_ITEM_IDENTIFIER @"History"
#define TIME_ITEM_IDENTIFIER @"Time"
#define OTHER_ITEM_IDENTIFIER @"Other"
#define WINDOW_ITEM_IDENTIFIER @"Window"
#define GLOBAL_ITEM_IDENTIFIER @"Global"

- (void)setDoToolbarSelection:(BOOL)flag
{
	doToolbarSelection = flag;
}

- (void) setupToolbar
{
	// Create a new toolbar instance, and attach it to our document window
	NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier: TOOLBAR_IDENTIFIER] autorelease];

	// Set up toolbar properties
	[toolbar setAllowsUserCustomization: NO];
	[toolbar setAutosavesConfiguration: NO];
	[toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];

	// We are the delegate
	[toolbar setDelegate: self];

	if (doToolbarSelection)
	{
		[toolbar setSelectedItemIdentifier: MAIN_ITEM_IDENTIFIER];
	}
	
	// Attach the toolbar to the document window
	[panel setToolbar: toolbar];
}


- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar 
{
	// Required delegate method Ê Returns the ordered list of items to be shown in the toolbar by default
	// If during the toolbar's initialization, no overriding values are found in the user defaults, or if the
	// user chooses to revert to the default items self set will be used
	return [NSArray arrayWithObjects:
			MAIN_ITEM_IDENTIFIER,
			NSToolbarSeparatorItemIdentifier,
			CPU_ITEM_IDENTIFIER, MEMORY_ITEM_IDENTIFIER, DISK_ITEM_IDENTIFIER,
			NETWORK_ITEM_IDENTIFIER, MOBILITY_ITEM_IDENTIFIER, HISTORY_ITEM_IDENTIFIER, TIME_ITEM_IDENTIFIER,
			OTHER_ITEM_IDENTIFIER, 
			NSToolbarSeparatorItemIdentifier,
			WINDOW_ITEM_IDENTIFIER, GLOBAL_ITEM_IDENTIFIER,
			//NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier,
			nil];
}

- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar 
{
	// Required delegate method Ê Returns the list of all allowed items by identifier Ê By default, the toolbar
	// does not assume any items are allowed, even the separator Ê So, every allowed item must be explicitly listed
	// The set of allowed items is used to construct the customization palette
	return [NSArray arrayWithObjects: 
			MAIN_ITEM_IDENTIFIER,
			CPU_ITEM_IDENTIFIER, MEMORY_ITEM_IDENTIFIER, DISK_ITEM_IDENTIFIER, NETWORK_ITEM_IDENTIFIER,
			WINDOW_ITEM_IDENTIFIER, OTHER_ITEM_IDENTIFIER, GLOBAL_ITEM_IDENTIFIER, TIME_ITEM_IDENTIFIER, MOBILITY_ITEM_IDENTIFIER,
			HISTORY_ITEM_IDENTIFIER,
			NSToolbarPrintItemIdentifier, NSToolbarShowColorsItemIdentifier, 
			NSToolbarShowFontsItemIdentifier, NSToolbarCustomizeToolbarItemIdentifier,
			NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, 
			NSToolbarSeparatorItemIdentifier, 
			nil];
}

- (NSArray *) toolbarSelectableItemIdentifiers: (NSToolbar *) toolbar 
{
	// Required delegate method Ê Returns the list of all allowed items by identifier Ê By default, the toolbar
	// does not assume any items are allowed, even the separator Ê So, every allowed item must be explicitly listed
	// The set of allowed items is used to construct the customization palette
	return [NSArray arrayWithObjects: 
			MAIN_ITEM_IDENTIFIER,
			CPU_ITEM_IDENTIFIER, MEMORY_ITEM_IDENTIFIER, DISK_ITEM_IDENTIFIER, NETWORK_ITEM_IDENTIFIER,
			WINDOW_ITEM_IDENTIFIER, OTHER_ITEM_IDENTIFIER, GLOBAL_ITEM_IDENTIFIER, TIME_ITEM_IDENTIFIER, MOBILITY_ITEM_IDENTIFIER,
			HISTORY_ITEM_IDENTIFIER, 
			nil];
}

- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier: (NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
	// Required delegate method Ê Given an item identifier, self method returns an item
	// The toolbar will use self method to obtain toolbar items that can be displayed in the customization sheet, or in the toolbar itself
	// Note that the toolbar knows how to make the standard NS supplied items all on its own, we don't have to do that.
	NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier: itemIdent] autorelease];

	if ([itemIdent isEqual: MAIN_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"MainLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"MainTooltip", nil);
		
		// Set the text label to be displayed in the toolbar and customization palette
		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		// Set up a reasonable tooltip, and image Ê Note, these aren't localized, but you will likely want to localize many of the item's 
		// properties
		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"iPulse"]];

		// Tell the item what message to send when it is clicked
		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showMainView:)];
	}
	else if ([itemIdent isEqual: CPU_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"CpuLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"CpuTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"CPU"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showCPUView:)];
	}
	else if ([itemIdent isEqual: MEMORY_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"MemoryLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"MemoryTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Memory"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showMemoryView:)];
	}
	else if ([itemIdent isEqual: DISK_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"DiskLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"DiskTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Disk"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showDiskView:)];
	}
	else if ([itemIdent isEqual: NETWORK_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"NetworkLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"NetworkTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Network"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showNetworkView:)];
	}
	else if ([itemIdent isEqual: OTHER_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"OtherLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"OtherTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Other"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showOtherView:)];
	}
	else if ([itemIdent isEqual: WINDOW_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"WindowLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"WindowTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Window"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showWindowView:)];
	}
	else if ([itemIdent isEqual: GLOBAL_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"GlobalLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"GlobalTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Global"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showGlobalView:)];
	}
	else if ([itemIdent isEqual: TIME_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"ClockLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"ClockTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Clock"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showTimeView:)];
	}
	else if ([itemIdent isEqual: MOBILITY_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"MobilityLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"MobilityTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"Mobility"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showMobilityView:)];
	}
	else if ([itemIdent isEqual: HISTORY_ITEM_IDENTIFIER]) 
	{
		NSString *labelString = NSLocalizedString(@"HistoryLabel", nil);
		NSString *toolTipString = NSLocalizedString(@"HistoryTooltip", nil);

		[toolbarItem setLabel:labelString];
		[toolbarItem setPaletteLabel:labelString];

		[toolbarItem setToolTip:toolTipString];
		[toolbarItem setImage: [NSImage imageNamed: @"History"]];

		[toolbarItem setTarget: self];
		[toolbarItem setAction: @selector(showHistoryView:)];
	}
	else
	{
		// itemIdent refered to a toolbar item that is not provide or supported by us or cocoa
		// Returning nil will inform the toolbar this kind of item is not supported
		toolbarItem = nil;
	}
	
	return toolbarItem;
}

- (void) setViewForPanel:(NSView *)view
{
	NSView *contentView = panel.contentView;
	NSRect contentFrame = contentView.frame;
	NSRect viewFrame = view.frame;
	NSRect panelFrame = panel.frame;
	NSRect newFrame = panelFrame;
	
	CGFloat toolbarHeight = panelFrame.size.height - contentFrame.size.height;
	CGFloat originOffset = contentFrame.size.height - viewFrame.size.height;

	newFrame.size.height = viewFrame.size.height + toolbarHeight;
	newFrame.origin.y = newFrame.origin.y + originOffset;
	
	[panel setContentView:view];
	[panel setFrame:newFrame display:YES animate:YES];
}

- (IBAction)showMainView:(id)sender
{
	[self setViewForPanel:mainView];
}

- (IBAction)showCPUView:(id)sender
{
	[self setViewForPanel:cpuView];
}

- (IBAction)showMemoryView:(id)sender
{
	[self setViewForPanel:memoryView];
}

- (IBAction)showDiskView:(id)sender
{
	[self setViewForPanel:diskView];
}

- (IBAction)showNetworkView:(id)sender
{
	[self setViewForPanel:networkView];
}

- (IBAction)showWindowView:(id)sender
{
	[self setViewForPanel:windowView];
}

- (IBAction)showOtherView:(id)sender
{
	[self setViewForPanel:otherView];
}

- (IBAction)showGlobalView:(id)sender
{
	[self setViewForPanel:globalView];
}

- (IBAction)showTimeView:(id)sender
{
	[self setViewForPanel:timeView];
}

- (IBAction)showMobilityView:(id)sender
{
	[self setViewForPanel:mobilityView];
}

- (IBAction)showHistoryView:(id)sender
{
	[self setViewForPanel:historyView];
}

@end
