//
//	MainController.h - Main Application Controller Class
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#import "MemoryInfo.h"
#import "ProcessorInfo.h"
#import "LoadInfo.h"
#import "NetworkInfo.h"
#import "DiskInfo.h"
#import "PowerInfo.h"
#import "TemperatureInfo.h"
#import "AirportInfo.h"
#import "Preferences.h"
#import "GraphView.h"
#import "InfoView.h"
#import "TranslucentWindow.h"

#define OPTION_INCLUDE_MATRIX_ORBITAL 0

#define OPTION_RESIZE_INFO 0

#define OPTION_MOON_TEST 0
#define OPTION_REPLACE_TOKEN_TEST 0

#define DISK_LIST_SIZE 14

#define PROCESS_LIST_SIZE 13
struct processEntry {
	int pid;
	float average;
	float current;
	BOOL isCurrent;
};

#define SWAPPING_LIST_SIZE 2048
struct swappingEntry  {
	int pid;
	int lastPageins;
	int pageins;
	int lastFaults;
	int faults;
	BOOL isCurrent;
};

@interface MainController : NSObject
{
	IBOutlet id aboutBox; // the about box
	IBOutlet id versionNumber; // the version number in the about box
	IBOutlet id contextMenu; // the context menu
	
	Preferences *preferences;	// the preferences

	// data sources
	MemoryInfo *memoryInfo;
	ProcessorInfo *processorInfo;
	LoadInfo *loadInfo;
	NetworkInfo *networkInfo;
	DiskInfo *diskInfo;
	PowerInfo *powerInfo;
	TemperatureInfo *temperatureInfo;
	AirportInfo *airportInfo;
	
	time_t startTime;
	time_t now;

	NSImage *backgroundImage; // the image used as a background
	NSImage *statusBackgroundImage; // the image used as a background on the menubar
	NSImage *iconImage; // the image used in the dock
	NSImage *graphImage; // the image used in the window
	NSImage *statusImage; // the image used in the menubar
	
	TranslucentWindow *graphWindow; // window for the graph
	GraphView *graphView; // view for the graph window

	TranslucentWindow *infoWindow; // window for the gauge info
	InfoView *infoView;

	NSStatusItem *statusItem; // menubar status item
	
	NSTimer *refreshTimer; // timer for graph refreshs
	NSTimer *registrationTimer; // timer for registration checks
	NSTimer *curtainTimer; // timer for opening curtain
	NSTimer *fadeTimer; // timer for fading info window
	NSTimer *delayTimer; // timer for delaying display of info window

	int lastHour; // last hour displayed in graph
	int lastMinute; // last minute displayed in graph

	int curtain; // curtain increment
	
	int fade; // info window fade
	int fadeIncrement; // positive when fading in, negative when fading out
	
	NSString *applicationVersion; // version number for application
	
	int majorVersion; // version number for Mac OS X
	int minorVersion;
	int updateVersion;
	
	UInt64 peakPacketsInBytes; // peak indicators
	time_t timePeakPacketsInBytes;
	UInt64 peakPacketsOutBytes;
	time_t timePeakPacketsOutBytes;
	UInt64 peakReadBytes;
	time_t timePeakReadBytes;
	UInt64 peakWriteBytes;
	time_t timePeakWriteBytes;
	
	struct processEntry processList[PROCESS_LIST_SIZE]; // process monitoring lists
	struct swappingEntry swappingList[SWAPPING_LIST_SIZE];
	int selfPid;

	BOOL alternativeActivity;
	BOOL plotArea;
	float infoDelay;
	float statusAlertThreshold;
	
	BOOL applicationIconIsDefault;
	
	NSAttributedString *processorInfoString;
	NSAttributedString *mobilityInfoString;
	NSAttributedString *memoryInfoString;
	NSAttributedString *swappingInfoString;
	NSAttributedString *diskInfoString;
	NSAttributedString *networkInfoString;
	NSAttributedString *clockInfoString;
	NSAttributedString *generalInfoString;
	NSAttributedString *registerInfoString;
	
#if OPTION_INCLUDE_MATRIX_ORBITAL	
	int serialDevice;
#endif
	
	// for sleep & wake notifications
	io_connect_t root_port;
	io_object_t notifier;

	BOOL infoWindowIsLocked;
	GraphPoint lockedGraphPoint;
	
	BOOL haveAuthorizedTaskPort;
}

- (NSPoint)pointAtCenter:(NSPoint)center atAngle:(float)angle atRadius:(float)radius;
- (float) angleAtCenter:(NSPoint)center ofPoint:(NSPoint)point;
- (float) radiusAtCenter:(NSPoint)center ofPoint:(NSPoint)point;

- (NSString *)stringForValue:(float)value;
- (NSString *)stringForValue:(float)value withBytes:(BOOL)withBytes;
- (NSString *)stringForValue:(float)value withBytes:(BOOL)withBytes withDecimal:(BOOL)withDecimal;
- (NSString *)stringForValue:(float)value powerOf10:(BOOL)isPowerOf10 withBytes:(BOOL)withBytes;
- (NSString *)stringForValue:(float)value powerOf10:(BOOL)isPowerOf10 withBytes:(BOOL)withBytes withDecimal:(BOOL)withDecimal;

- (void)updateInfo;
- (void)drawInfo;
- (void)setInfoLocation;
#if OPTION_RESIZE_INFO
- (void)setInfoSize:(NSString *)infoText;
#endif

- (void)resetGraphLocation;
- (void)setGraphLocation;

- (IBAction)checkForUpdates:(id)sender;

- (void)showPreferences:(id)sender;
- (void)openIconfactory:(id)sender;
- (void)openHomePage:(id)sender;
- (void)openGallery:(id)sender;
- (void)openFAQ:(id)sender;
- (void)mailSupport:(id)sender;
- (void)launchProcessViewer:(id)sender;
- (void)launchTerminal:(id)sender;
- (void)launchNetworkUtility:(id)sender;
- (void)showAboutBox:(id)sender;
- (void)toggleFloatingWindow:(id)sender;
- (void)toggleIgnoreMouse:(id)sender;
- (void)lockInfoWindow:(id)sender;

- (void)updateIconAndWindow;

#if OPTION_INCLUDE_MATRIX_ORBITAL	
- (void)deregisterForSleepWakeNotification;
- (void)powerMessageReceived:(natural_t)messageType withArgument:(void *) messageArgument;
- (void)registerForSleepWakeNotification;
#endif

@end
