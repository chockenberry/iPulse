//
//	Preferences.h - Preferences Controller Class
//


#import <Cocoa/Cocoa.h>

// prefix for saved preferences
#define SETTINGS_PREFIX @"com.iconfactory.iPulse."

// prefix for registration info
#define REGISTRATION_PREFIX @"IFRegistration"

// CPU
#define PROCESSOR_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.ProcessorShowGauge"
#define PROCESSOR_SHOW_TEXT_KEY @"com.iconfactory.iPulse.ProcessorShowText"
#define PROCESSOR_SYSTEM_COLOR_KEY @"com.iconfactory.iPulse.ProcessorSystem"
#define PROCESSOR_USER_COLOR_KEY @"com.iconfactory.iPulse.ProcessorUser"
#define PROCESSOR_NICE_COLOR_KEY @"com.iconfactory.iPulse.ProcessorNice"
#define PROCESSOR_LOAD_COLOR_KEY @"com.iconfactory.iPulse.ProcessorLoadColor"
#define PROCESSOR_INCLUDE_NICE_KEY @"com.iconfactory.iPulse.ProcessorIncludeNice"

// Memory
#define MEMORY_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.MemoryShowGauge"
#define MEMORY_SHOW_TEXT_KEY @"com.iconfactory.iPulse.MemoryShowText"
#define MEMORY_SYSTEMACTIVE_COLOR_KEY @"com.iconfactory.iPulse.MemorySystemActive"
#define MEMORY_INACTIVEFREE_COLOR_KEY @"com.iconfactory.iPulse.MemoryInactiveFree"
#define MEMORY_SWAPPING_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.MemorySwappingShowGauge"
#define MEMORY_SWAPPING_SHOW_TEXT_KEY @"com.iconfactory.iPulse.MemorySwappingShowText"
#define MEMORY_SWAPPING_IN_COLOR_KEY @"com.iconfactory.iPulse.MemorySwappingIn"
#define MEMORY_SWAPPING_OUT_COLOR_KEY @"com.iconfactory.iPulse.MemorySwappingOut"

// Disk
#define DISK_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.DiskShowGauge"
#define DISK_SHOW_TEXT_KEY @"com.iconfactory.iPulse.DiskShowText"
#define DISK_SUM_ALL_KEY @"com.iconfactory.iPulse.DiskSumAll"
#define DISK_USED_COLOR_KEY @"com.iconfactory.iPulse.DiskUsed"
#define DISK_WARNING_COLOR_KEY @"com.iconfactory.iPulse.DiskWarning"
#define DISK_BACKGROUND_COLOR_KEY @"com.iconfactory.iPulse.DiskBackground"
#define DISK_IO_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.DiskIOShowGauge"
#define DISK_READ_COLOR_KEY @"com.iconfactory.iPulse.DiskRead"
#define DISK_WRITE_COLOR_KEY @"com.iconfactory.iPulse.DiskWrite"
#define DISK_HIGH_COLOR_KEY @"com.iconfactory.iPulse.DiskHigh"
#define DISK_SHOW_ACTIVITY_KEY @"com.iconfactory.iPulse.DiskShowActivity"
#define DISK_SHOW_PEAK_KEY @"com.iconfactory.iPulse.DiskShowPeak"
#define DISK_SCALE_KEY @"com.iconfactory.iPulse.DiskScale"

// Network
#define NETWORK_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.NetworkShowGauge"
#define NETWORK_SHOW_TEXT_KEY @"com.iconfactory.iPulse.NetworkShowText"
#define NETWORK_IN_COLOR_KEY @"com.iconfactory.iPulse.NetworkIn"
#define NETWORK_OUT_COLOR_KEY @"com.iconfactory.iPulse.NetworkOut"
#define NETWORK_HIGH_COLOR_KEY @"com.iconfactory.iPulse.NetworkHigh"
#define NETWORK_SHOW_ACTIVITY_KEY @"com.iconfactory.iPulse.NetworkShowActivity"
#define NETWORK_SHOW_PEAK_KEY @"com.iconfactory.iPulse.NetworkShowPeak"
#define NETWORK_SCALE_KEY @"com.iconfactory.iPulse.NetworkScale"

// Mobility
#define MOBILITY_BATTERY_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.MobilityBatteryShowGauge"
#define MOBILITY_BATTERY_COLOR_KEY @"com.iconfactory.iPulse.MobilityBatteryColor"
#define MOBILITY_BATTERY_CHARGE_COLOR_KEY @"com.iconfactory.iPulse.MobilityBatteryChargeColor"
#define MOBILITY_BATTERY_FULL_COLOR_KEY @"com.iconfactory.iPulse.MobilityBatteryFullColor"
#define MOBILITY_WIRELESS_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.MobilityWirelessShowGauge"
#define MOBILITY_WIRELESS_COLOR_KEY @"com.iconfactory.iPulse.MobilityWirelessColor"
#define MOBILITY_BACKGROUND_COLOR_KEY @"com.iconfactory.iPulse.MobilityBackgroundColor"
#define MOBILITY_WARNING_COLOR_KEY @"com.iconfactory.iPulse.MobilityWarningColor"

// History
#define HISTORY_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.HistoryShow"
#define HISTORY_LOAD_COLOR_KEY @"com.iconfactory.iPulse.HistoryLoadColor"
#define HISTORY_LOAD_MINIMUM_KEY @"com.iconfactory.iPulse.HistoryLoadMinimum"
#define HISTORY_LOAD_MAXIMUM_KEY @"com.iconfactory.iPulse.HistoryLoadMaximum"

// Time
#define TIME_SHOW_GAUGE_KEY @"com.iconfactory.iPulse.TimeShowGauge"
#define TIME_TRADITIONAL_KEY @"com.iconfactory.iPulse.TimeTraditional"
#define TIME_USE_24_HOUR_KEY @"com.iconfactory.iPulse.TimeUse24Hour"
#define TIME_NOON_AT_TOP_KEY @"com.iconfactory.iPulse.TimeNoonAtTop"
#define TIME_HANDS_COLOR_KEY @"com.iconfactory.iPulse.TimeHandsColor"
#define TIME_SECONDS_COLOR_KEY @"com.iconfactory.iPulse.TimeSecondsColor"
#define TIME_DATE_FOREGROUND_COLOR_KEY @"com.iconfactory.iPulse.TimeDateForegroundColor"
#define TIME_DATE_BACKGROUND_COLOR_KEY @"com.iconfactory.iPulse.TimeDateBackgroundColor"
#define TIME_DATE_STYLE_KEY @"com.iconfactory.iPulse.TimeDateStyle"
#define TIME_RING_KEY @"com.iconfactory.iPulse.TimeRing"
#define TIME_RING_SOUND_KEY @"com.iconfactory.iPulse.TimeRingSound"
#define TIME_SHOW_WEEK_KEY @"com.iconfactory.iPulse.TimeShowWeek"

// Other
#define OTHER_MARKER_COLOR_KEY @"com.iconfactory.iPulse.OtherMarkerColor"
#define OTHER_TEXT_COLOR_KEY @"com.iconfactory.iPulse.OtherTextColor"
#define OTHER_TEXT_SHADOW_DARK_KEY @"com.iconfactory.iPulse.OtherTextShadowDark"
#define OTHER_BACKGROUND_COLOR_KEY @"com.iconfactory.iPulse.OtherBackgroundColor"
#define OTHER_IMAGE_TRANSPARENCY_KEY @"com.iconfactory.iPulse.OtherImageTransparency"
#define OTHER_IMAGE_KEY @"com.iconfactory.iPulse.OtherImage"

// Window (not persisted in settings file)
#define WINDOW_SHOW_FLOATING_KEY @"IFWindowShowFloating"
#define WINDOW_FLOATING_SHADOW_KEY @"IFWindowFloatingShadow"
#define WINDOW_FLOATING_NO_HIDE_KEY @"IFWindowFloatingNoHide"
#define WINDOW_FLOATING_IGNORE_CLICK_KEY @"IFWindowFloatingIgnoreClick"
#define WINDOW_FLOATING_LEVEL_KEY @"IFWindowFloatingLevel"
#define WINDOW_FLOATING_SIZE_KEY @"IFWindowFloatingSize"
#define WINDOW_SHOW_INFO_KEY @"IFWindowShowInfo"
#define WINDOW_INFO_DELAY_KEY @"IFWindowInfoDelay"
#define WINDOW_INFO_FADE_IN_KEY @"IFWindowInfoFadeIn"
#define WINDOW_INFO_FADE_OUT_KEY @"IFWindowInfoFadeOut"
#define WINDOW_INFO_FOREGROUND_COLOR_KEY @"IFWindowInfoForegroundColor"
#define WINDOW_INFO_BACKGROUND_COLOR_KEY @"IFWindowInfoBackgroundColor"
#define WINDOW_INFO_HIGHLIGHT_COLOR_KEY @"IFWindowInfoHighlightColor"

// Window (updated by dragging only, not persisted in settings file)
#define WINDOW_FLOATING_RELATIVE_POSITION_KEY @"IFWindowFloatingRelativePosition"
#define WINDOW_FLOATING_CENTER_X_KEY @"IFWindowFloatingCenterX" 
#define WINDOW_FLOATING_CENTER_Y_KEY @"IFWindowFloatingCenterY"
#define WINDOW_FLOATING_RELATIVE_X_KEY @"IFWindowFloatingRelativeX"
#define WINDOW_FLOATING_RELATIVE_Y_KEY @"IFWindowFloatingRelativeY"

// Global (not persisted in settings file)
#define GLOBAL_SHOW_DOCK_ICON_KEY @"IFGlobalShowDockIcon"
#define GLOBAL_SHOW_DOCK_KEY @"IFGlobalShowDock"
#define GLOBAL_DOCK_INCLUDE_TEXT_KEY @"IFGlobalDockIncludeText"
#define GLOBAL_UPDATE_FREQUENCY_KEY @"IFGlobalUpdateFrequency"
#define GLOBAL_SCHEDULING_PRIORITY_KEY @"IFGlobalSchedulingPriority"
#define GLOBAL_HOLD_TIME_KEY @"IFGlobalHoldTime"
#define GLOBAL_UNITS_TYPE_KEY @"IFGlobalUnitsType"
#define GLOBAL_SHOW_SELF_KEY @"IFGlobalShowSelf"
#define GLOBAL_TOGGLE_FLOATING_WINDOW_KEY @"IFGlobalToggleFloatingWindow"
#define GLOBAL_TOGGLE_IGNORE_MOUSE_KEY @"IFGlobalToggleIgnoreMouse"
#define GLOBAL_LOCK_INFO_WINDOW_KEY @"IFGlobalLockInfoWindow"
#define GLOBAL_TOGGLE_STATUS_ITEM_KEY @"IFGlobalToggleStatusItem"
#define GLOBAL_SHOW_STATUS_KEY @"IFGlobalShowStatus"
#define GLOBAL_USE_POWERMATE_KEY @"IFGlobalUsePowerMate"
#define GLOBAL_POWERMATE_OUTPUT_TYPE_KEY @"IFGlobalPowerMateOutputType"
#define GLOBAL_POWERMATE_INPUT_TYPE_KEY @"IFGlobalPowerMateInputType"
#define GLOBAL_STATUS_UPPER_BAR_TYPE_KEY @"IFGlobalStatusUpperBarType"
#define GLOBAL_STATUS_UPPER_BAR_COLOR_LEFT_KEY @"IFGlobalStatusUpperBarColorLeft"
#define GLOBAL_STATUS_UPPER_BAR_COLOR_RIGHT_KEY @"IFGlobalStatusUpperBarColorRight"
#define GLOBAL_STATUS_UPPER_BAR_COLOR_ALERT_KEY @"IFGlobalStatusUpperBarColorAlert"
#define GLOBAL_STATUS_UPPER_DOT_TYPE_KEY @"IFGlobalStatusUpperDotType"
#define GLOBAL_STATUS_UPPER_DOT_COLOR_LEFT_KEY @"IFGlobalStatusUpperDotColorLeft"
#define GLOBAL_STATUS_UPPER_DOT_COLOR_RIGHT_KEY @"IFGlobalStatusUpperDotColorRight"
#define GLOBAL_STATUS_UPPER_DOT_COLOR_ALERT_KEY @"IFGlobalStatusUpperDotColorAlert"
#define GLOBAL_STATUS_LOWER_BAR_TYPE_KEY @"IFGlobalStatusLowerBarType"
#define GLOBAL_STATUS_LOWER_BAR_COLOR_LEFT_KEY @"IFGlobalStatusLowerBarColorLeft"
#define GLOBAL_STATUS_LOWER_BAR_COLOR_RIGHT_KEY @"IFGlobalStatusLowerBarColorRight"
#define GLOBAL_STATUS_LOWER_BAR_COLOR_ALERT_KEY @"IFGlobalStatusLowerBarColorAlert"
#define GLOBAL_STATUS_LOWER_DOT_TYPE_KEY @"IFGlobalStatusLowerDotType"
#define GLOBAL_STATUS_LOWER_DOT_COLOR_LEFT_KEY @"IFGlobalStatusLowerDotColorLeft"
#define GLOBAL_STATUS_LOWER_DOT_COLOR_RIGHT_KEY @"IFGlobalStatusLowerDotColorRight"
#define GLOBAL_STATUS_LOWER_DOT_COLOR_ALERT_KEY @"IFGlobalStatusLowerDotColorAlert"
#define GLOBAL_STATUS_IMAGE_KEY @"IFGlobalStatusImage"

// Miscellaneous
#define MISCELLANEOUS_IS_DIRTY @"IFMiscellaneousIsDirty"

// Application Configuration
#define APPLICATION_PLOT_PROCESSOR_AREA_KEY @"IFApplicationPlotProcessorArea"
#define APPLICATION_ALWAYS_HOVER_TIME_KEY @"IFApplicationAlwaysHoverTime"
#define APPLICATION_NEVER_HIDE_KEY @"IFApplicationNeverHide"
#define APPLICATION_HIDE_INFO_ON_DRAG_KEY @"IFApplicationHideInfoOnDrag"
#define APPLICATION_ALTERNATIVE_ACTIVITY_KEY @"IFApplicationAlternativeActivity"
#define APPLICATION_CHECK_MATRIX_ORBITAL_KEY @"IFApplicationCheckMatrixOrbital"

#define APPLICATION_SWAPFILES_PATH_KEY @"IFApplicationSwapfilesPath"
#define APPLICATION_CHUD_WORKAROUND_KEY @"IFApplicationCHUDWorkaround"

#define APPLICATION_INFO_DELAY_KEY @"IFApplicationInfoDelay"
#define APPLICATION_STATUS_ALERT_THRESHOLD_KEY @"IFApplicationStatusAlertThreshold"

#define APPLICATION_TRACK_MOUSE_KEY @"IFApplicationTrackMouse"

#define APPLICATION_IGNORE_EXPOSE_KEY @"IFApplicationIgnoreExpose"

#define APPLICATION_CHECK_MOTHERBOARD_TEMPERATURE_KEY @"IFApplicationCheckMotherboardTemperature"
#define APPLICATION_CHECK_DIODE_TEMPERATURE_KEY @"IFApplicationCheckDiodeTemperature"
#define APPLICATION_CHECK_SMC_TEMPERATURE_KEY @"IFApplicationCheckSMCTemperature"

// Registration
#define REGISTRATION_NAME_KEY @"IFRegistrationName"
#define REGISTRATION_NUMBER_KEY @"IFRegistrationNumber"
#define REGISTRATION_COUNT_KEY @"IFRegistrationCount"


// Notifications
#define PREFERENCES_CHANGED @"IFPreferencesChanged"
#define PREFERENCES_WINDOW_CHANGED @"IFPreferencesWindowChanged"
#define PREFERENCES_STATUS_CHANGED @"IFPreferencesStatusChanged"
#define PREFERENCES_HOTKEY_CHANGED @"IFPreferencesHotkeyChanged"


@interface Preferences : NSObject <NSToolbarDelegate>
{
	IBOutlet NSPanel *panel;
	IBOutlet NSView *mainView;
	IBOutlet NSView *cpuView;
	IBOutlet NSView *memoryView;
	IBOutlet NSView *diskView;
	IBOutlet NSView *networkView;
	IBOutlet NSView *timeView;
	IBOutlet NSView *mobilityView;
	IBOutlet NSView *historyView;
	IBOutlet NSView *otherView;
	IBOutlet NSView *windowView;
	IBOutlet NSView *globalView;

	// Main
	IBOutlet id mainVersionNumber;
	
	// CPU
	IBOutlet id processorShowGauge;
	IBOutlet id processorShowText;
	IBOutlet id processorSystemColor;
	IBOutlet id processorUserColor;
	IBOutlet id processorNiceColor;
	IBOutlet id processorLoadColor;
	IBOutlet id processorIncludeNice;
	
	// Memory
	IBOutlet id memoryShowGauge;
	IBOutlet id memoryShowText;
	IBOutlet id memorySystemActiveColor;
	IBOutlet id memoryInactiveFreeColor;
	IBOutlet id memorySwappingShowGauge;
	IBOutlet id memorySwappingShowText;
	IBOutlet id memorySwappingInColor;
	IBOutlet id memorySwappingOutColor;

	// Disk
	IBOutlet id diskShowGauge;
	IBOutlet id diskShowText;
	IBOutlet id diskSumAll;
	IBOutlet id diskUsedColor;
	IBOutlet id diskWarningColor;
	IBOutlet id diskBackgroundColor;
	IBOutlet id diskIOShowGauge;
	IBOutlet id diskReadColor;
	IBOutlet id diskWriteColor;
	IBOutlet id diskHighColor;
	IBOutlet id diskShowActivity;
	IBOutlet id diskShowPeak;
	IBOutlet id diskScale;

	// Network
	IBOutlet id networkShowGauge;
	IBOutlet id networkShowText;
	IBOutlet id networkInColor;
	IBOutlet id networkOutColor;
	IBOutlet id networkHighColor;
	IBOutlet id networkShowActivity;
	IBOutlet id networkShowPeak;
	IBOutlet id networkScale;

	// Mobility
	IBOutlet id mobilityBatteryShowGauge;
	IBOutlet id mobilityBatteryColor;
	IBOutlet id mobilityBatteryChargeColor;
	IBOutlet id mobilityBatteryFullColor;
	IBOutlet id mobilityWirelessShowGauge;
	IBOutlet id mobilityWirelessColor;
	IBOutlet id mobilityBackgroundColor;
	IBOutlet id mobilityWarningColor;
	
	// History
	IBOutlet id historyShowGauge;
	IBOutlet id historyLoadColor;
	IBOutlet id historyLoadMinimum;
	IBOutlet id historyLoadMinimumLabel;
	IBOutlet id historyLoadMaximum;
	IBOutlet id historyLoadMaximumLabel;

	// Clock
	IBOutlet id timeShowGauge;
	IBOutlet id timeTraditional;
	IBOutlet id timeUse24Hour;
	IBOutlet id timeNoonAtTop;
	IBOutlet id timeHandsColor;
	IBOutlet id timeSecondsColor;
	IBOutlet id timeDateForegroundColor;
	IBOutlet id timeDateBackgroundColor;
	IBOutlet id timeDateStyle;
	IBOutlet id timeRing;
	IBOutlet id timeRingSound;
	IBOutlet id timeShowWeek;
	
	// Other
	IBOutlet id otherMarkerColor;
	IBOutlet id otherBackgroundColor;
	IBOutlet id otherTextColor;
	IBOutlet id otherTextShadowDark;
	IBOutlet id otherImageTransparency;
	IBOutlet id otherImageLabel;
	
	// Window
	IBOutlet id windowShowFloating;
	IBOutlet id windowFloatingShadow;
	IBOutlet id windowFloatingNoHide;
	IBOutlet id windowFloatingIgnoreClick;
	IBOutlet id windowFloatingLevel;
	IBOutlet id windowFloatingSize;
	IBOutlet id windowFloatingSizeLabel;
	IBOutlet id windowShowInfo;
	IBOutlet id windowInfoDelay;
	IBOutlet id windowInfoFadeIn;
	IBOutlet id windowInfoFadeOut;
	IBOutlet id windowInfoForegroundColor;
	IBOutlet id windowInfoBackgroundColor;
	IBOutlet id windowInfoHighlightColor;

	// Global
	IBOutlet id globalShowDockIcon;
	IBOutlet id globalShowDock;
	IBOutlet id globalDockIncludeText;	
	IBOutlet id globalUpdateFrequency;
	IBOutlet id globalUpdateFrequencyLabel;
	IBOutlet id globalSchedulingPriority;
	IBOutlet id globalSchedulingPriorityLabel;		
	IBOutlet id globalHoldTime;
	IBOutlet id globalHoldTimeLabel;
	IBOutlet id globalUnitsType;
	IBOutlet id globalShowSelf;
	IBOutlet id globalToggleFloatingWindowHotkeyLabel;
	IBOutlet id globalToggleIgnoreMouseHotkeyLabel;
	IBOutlet id globalLockInfoWindowHotkeyLabel;
	IBOutlet id globalToggleStatusItemHotkeyLabel;
	IBOutlet id globalShowStatus;
	IBOutlet id globalUsePowerMate;
	IBOutlet id globalPowerMateOutputType;
	IBOutlet id globalPowerMateInputType;

	IBOutlet id globalStatusUpperBarType;
	IBOutlet id globalStatusUpperBarColorLeft;
	IBOutlet id globalStatusUpperBarColorRight;
	IBOutlet id globalStatusUpperBarColorAlert;

	IBOutlet id globalStatusUpperDotType;
	IBOutlet id globalStatusUpperDotColorLeft;
	IBOutlet id globalStatusUpperDotColorRight;
	IBOutlet id globalStatusUpperDotColorAlert;
	
	IBOutlet id globalStatusLowerBarType;
	IBOutlet id globalStatusLowerBarColorLeft;
	IBOutlet id globalStatusLowerBarColorRight;
	IBOutlet id globalStatusLowerBarColorAlert;
	
	IBOutlet id globalStatusLowerDotType;
	IBOutlet id globalStatusLowerDotColorLeft;
	IBOutlet id globalStatusLowerDotColorRight;
	IBOutlet id globalStatusLowerDotColorAlert;
	
	IBOutlet id globalStatusImageLabel;
	
	// Save panel
	IBOutlet NSView *saveAccessoryView;
	//NSSavePanel *savePanel;
	IBOutlet id saveIncludeFloatingWindow;
	IBOutlet id saveIncludeInfoWindow;
	IBOutlet id saveIncludeStatusItem;

	// Miscellaneous
	NSString *applicationVersion;
	BOOL powerMateIsAvailable;
	BOOL doToolbarSelection;
}

+ (NSColor *)colorAlphaFromString:(NSString *)string;
+ (NSString *)stringFromColorAlpha:(NSColor *)color;

- (BOOL)loadSettingsFromURL:(NSURL *)URL;

- (void)resetDefaults;

- (void)setDoToolbarSelection:(BOOL)flag;

- (void)setApplicationVersion:(NSString *)newApplicationVersion;
- (void)setPowerMateIsAvailable:(BOOL)newPowerMateIsAvailable;
- (void)updatePanel;

- (IBAction)showPreferences:(id)sender;
- (IBAction)restoreSettings:(id)sender;
- (IBAction)saveSettings:(id)sender;
- (IBAction)loadSettings:(id)sender;
- (IBAction)loadImage:(id)sender;
- (IBAction)removeImage:(id)sender;
- (IBAction)preferencesChanged:(id)sender;
- (IBAction)testSound:(id)sender;
- (IBAction)loadIconfactory:(id)sender;
- (IBAction)loadStatusImage:(id)sender;
- (IBAction)removeStatusImage:(id)sender;

- (void)toggleFloatingWindow;
- (void)toggleIgnoreMouse;
- (void)toggleStatusItem;

- (IBAction)setToggleFloatingWindowHotkey:(id)sender;
- (IBAction)setToggleIgnoreMouseHotkey:(id)sender;
- (IBAction)setLockInfoWindowHotkey:(id)sender;
- (IBAction)setToggleStatusItemHotkey:(id)sender;

- (IBAction)setShowInDock:(id)sender;

- (int)windowNumber;
- (void)setupToolbar;
- (void)setViewForPanel:(NSView *)view;

@end
