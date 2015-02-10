// AGProcess.m
//
// Copyright (c) 2002-2003 Aram Greenman. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// 3. The name of the author may not be used to endorse or promote products derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Version History:
//
// 0.1 - February 13, 2003
//	Initial release - Aram Greenman
//
// 0.2 - August 4, 2003
//	Added code to check OS versions in computations for task memory usage - Aram Greenman
//	Added methods to retrieve task events (pageins, faults, etc.) - Craig Hockenberry
//	Fixed compilation warnings in AGGetMachThreadPriority - Craig Hockenberry
//	Fixed -siblings method to exclude the receiver - Steve Gehrman
//
// 0.3 - November 3, 2003
//	Added code in doProcargs to handle command names with UTF-8 characters - Craig Hockenberry
//	Changed code to weed out bogus entries in the argument list (isprint only works with 7-bit ASCII characters) - Craig Hockenberry
//
// 0.4 - May 31, 2005
//	Cleaned up parsing in doProcargs - Craig Hockenberry
//		Fixed the parser to handle the buffer returned by KERN_PROCARGS (the contents vary depending on the version of Mac OS X)
//		Added a special case for Tiger that uses KERN_PROCARGS2 -- this version provides an argument count for more reliable results
//		Fixed a bug with parsing arguments on Japanese systems
//		Tested the parser on Jaguar, Panther and Tiger (10.2 to 10.4)
//	Added an annotation for Java and DashboardClient commands - Craig Hockenberry
//		Added an -annotation method which can be used to distinguish multiple instances of each command
//		Added an -annotatedCommand method which produces a composite of the command and annotation strings
//	Changed the computation of VM sizes to match the "top" command (which differs from how "ps" does it) - Craig Hockenberry
//	Fixed compilation warnings when using GCC 4.0 and Xcode 2.0 - Craig Hockenberry
//	Updated the ProcessTest application to use new methods and shown unknown values - Craig Hockenberry
//
// 0.5 - August 8, 2005
//	Cleaned up parsing in doProcargs - Craig Hockenberry
//		Fixed a bug with the parser's argument count causing a NSRangeException for processes with no arguments running from
//		a bash shell
//	Fixed a memory leak during command allocation when the parser failed - Steve Gehrman
//	Fixed a memory leak when deallocating an instance -- the annotation was not being freed - Craig Hockenberry
//	Added annotations for Konfabulator widgets - Craig Hockenberry


#import "AGProcess.h"
#import <Foundation/Foundation.h>
#include <mach/mach_host.h>
#include <mach/mach_port.h>
#include <mach/mach_traps.h>
#include <mach/shared_region.h>
#include <mach/task.h>
#include <mach/thread_act.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>

static int argument_buffer_size;
static int major_version;
static int minor_version;
static int update_version;

// call this before any of the AGGetMach... functions
// sets the correct split library segment for running kernel
// should work at least through Darwin 6.6 (Mac OS X 10.2.6)
static kern_return_t
AGMachStatsInit() {
	int mib[2];
	size_t len = 256;
	char rel[len];
	
	// get the OS version and set the correct split library segment for the kernel
	mib[0] = CTL_KERN;
	mib[1] = KERN_OSRELEASE;

	if (sysctl(mib, 2, &rel, &len, NULL, 0) < 0)
		return KERN_FAILURE;
	
	major_version = 0;
	minor_version = 0;
	update_version = 0;
	sscanf(rel, "%d.%d.%d", &major_version, &minor_version, &update_version);
	//NSLog(@"AGProcess: AGMacStatsInit: major_version = %d, minor_version = %d, update_version = %d", major_version, minor_version, update_version);
	
	// get the buffer size that will be large enough to hold the maximum arguments
	size_t	size = sizeof(argument_buffer_size);
	
	mib[0] = CTL_KERN;
	mib[1] = KERN_ARGMAX;

	if (sysctl(mib, 2, &argument_buffer_size, &size, NULL, 0) == -1) {
		//NSLog(@"AGProcess: AGMachStatsInit: using default for argument_buffer_size");
		argument_buffer_size = 4096; // kernel failed to provide the maximum size, use a default of 4K
	}
	if (major_version < 7) // kernel version < 7.0 (Mac OS X 10.3 - Panther)
	{
		if (argument_buffer_size > 8192) {
			//NSLog(@"AGProcess: AGMachStatsInit: adjusting argument_buffer_size = %d", argument_buffer_size);
			argument_buffer_size = 8192; // avoid a kernel bug and use a maximum of 8K
		}
	}
	
	//NSLog(@"AGProcess: AGMachStatsInit: argument_buffer_size = %d", argument_buffer_size);

	return KERN_SUCCESS;
}

///////////////////

static inline cpu_type_t cpu_type(pid_t pid) {
    cpu_type_t cputype = 0;
	
    int mib[CTL_MAXNAME];
    size_t miblen = CTL_MAXNAME;
    if (sysctlnametomib("sysctl.proc_cputype", mib, &miblen) != -1) {
        mib[miblen] = pid;
		size_t len = sizeof(cputype);
        if (sysctl(mib, miblen + 1, &cputype, &len, 0, 0) == -1) {
            cputype = 0;
        }
    }
	
    return cputype;
}

static inline mach_vm_size_t shared_region_size(cpu_type_t cputype) {
    switch(cputype) {
        case CPU_TYPE_POWERPC:
            return SHARED_REGION_SIZE_PPC;
        case CPU_TYPE_POWERPC64:
            return SHARED_REGION_SIZE_PPC64;
        case CPU_TYPE_I386:
            return SHARED_REGION_SIZE_I386;
        case CPU_TYPE_X86_64:
            return SHARED_REGION_SIZE_X86_64;
        default: // unknown CPU type
            return 0;
    }
}

static inline int in_shared_region(cpu_type_t cputype, mach_vm_address_t address) {
    if (cputype == CPU_TYPE_POWERPC &&
        address >= SHARED_REGION_BASE_PPC &&
        address <= (SHARED_REGION_BASE_PPC + SHARED_REGION_SIZE_PPC)) {
        return 1;
    }
	
    if (cputype == CPU_TYPE_POWERPC64 &&
        address >= SHARED_REGION_BASE_PPC64 &&
        address <= (SHARED_REGION_BASE_PPC64 + SHARED_REGION_SIZE_PPC64)) {
        return 1;
    }
    
    if (cputype == CPU_TYPE_I386 &&
        address >= SHARED_REGION_BASE_I386 &&
        address <= (SHARED_REGION_BASE_I386 + SHARED_REGION_SIZE_I386)) {
        return 1;
    }
    
    if (cputype == CPU_TYPE_X86_64 &&
        address >= SHARED_REGION_BASE_X86_64 &&
        address <= (SHARED_REGION_BASE_X86_64 + SHARED_REGION_SIZE_X86_64)) {
        return 1;
    }
    
    return 0;
}

static kern_return_t
AGGetMachTaskVirtualMemoryUsage(pid_t pid, task_t task, mach_vm_size_t *virtual_size) {
	// derived from the libtop.c source code for Darwin: http://www.opensource.apple.com/source/top/top-67/libtop.c
	// with a little bit of Chromium thrown in: http://src.chromium.org/svn/trunk/src/base/process_util_mac.mm
	
	kern_return_t error = KERN_SUCCESS;
	
	vm_size_t pagesize;
	host_page_size(mach_host_self(), &pagesize);

	cpu_type_t cputype = cpu_type(pid);
	
	mach_vm_size_t vprvt = 0;
	
	// check all vm regions
	mach_vm_size_t size;
	mach_vm_address_t address;
	for (address = MACH_VM_MIN_ADDRESS; ; address += size) {
		vm_region_top_info_data_t info;
		mach_msg_type_number_t count = VM_REGION_TOP_INFO_COUNT;
		mach_port_t object_name;
		if (mach_vm_region(task, &address, &size, VM_REGION_TOP_INFO, (vm_region_info_t)&info, &count, &object_name) != KERN_SUCCESS) {
			// the error indicates that there are no more vm regions to look at
			break;
		}
		
		if (in_shared_region(cputype, address)) {
			// skip the vm region if it is not a shared private region
			if (info.share_mode != SM_PRIVATE) {
				continue;
			}
		}
		
		if (info.share_mode == SM_COW && info.ref_count == 1) {
			// treat a SM_COW region with a single reference as SM_PRIVATE
			info.share_mode = SM_PRIVATE;
		}

		if (info.share_mode == SM_PRIVATE) {
			vprvt += size;
		}
		else if (info.share_mode == SM_COW) {
			vprvt += info.private_pages_resident * pagesize;
		}
	}
	
	*virtual_size = vprvt;
	
	return error;
}

static kern_return_t
AGGetMachTaskMemoryUsage(task_t task, vm_size_t *resident_size, double *percent) {
	kern_return_t error;
	
	struct task_basic_info t_info;
	mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;		
	if ((error = task_info(task, TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count)) != KERN_SUCCESS)
		return error;
	
	if (percent != NULL) {
		vm_statistics_data_t vm_stat;
		vm_size_t pagesize;
		mach_msg_type_number_t host_count;

		host_page_size( mach_host_self(), &pagesize );
		host_count = sizeof(vm_stat)/sizeof(integer_t);

		if ((error = host_statistics( mach_host_self(), HOST_VM_INFO, (host_info_t)&vm_stat, &host_count )) != KERN_SUCCESS)
			return error;

		vm_size_t physicalRam = ( vm_stat.active_count + vm_stat.inactive_count + vm_stat.wire_count + vm_stat.free_count ) * pagesize;

		*percent = (double)t_info.resident_size / (double)physicalRam;
	}

	if (resident_size != NULL) {
		*resident_size = t_info.resident_size;
	}
	
	return error;
}

static kern_return_t
AGGetMachThreadCPUUsage(thread_t thread, double *user_time, double *system_time, double *percent) {
	kern_return_t error;
	struct thread_basic_info th_info;
	mach_msg_type_number_t th_info_count = THREAD_BASIC_INFO_COUNT;
	
	if ((error = thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&th_info, &th_info_count)) != KERN_SUCCESS)
		return error;
	
	if (user_time != NULL) *user_time = th_info.user_time.seconds + th_info.user_time.microseconds / 1e6;
	if (system_time != NULL) *system_time = th_info.system_time.seconds + th_info.system_time.microseconds / 1e6;
	if (percent != NULL) *percent = (double)th_info.cpu_usage / TH_USAGE_SCALE;
	
	return error;
}

static kern_return_t
AGGetMachTaskCPUUsage(task_t task, double *user_time, double *system_time, double *percent) {
	kern_return_t error;
	struct task_basic_info t_info;
	thread_array_t th_array;
	mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT, th_count;
	int i;
	double my_user_time = 0, my_system_time = 0, my_percent = 0;
	
	if ((error = task_info(task, TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count)) != KERN_SUCCESS)
		return error;
	if ((error = task_threads(task, &th_array, &th_count)) != KERN_SUCCESS)
		return error;
	
	// sum time for live threads
	for (i = 0; i < th_count; i++) {
		double th_user_time, th_system_time, th_percent;
		if ((error = AGGetMachThreadCPUUsage(th_array[i], &th_user_time, &th_system_time, &th_percent)) != KERN_SUCCESS)
			break;
		my_user_time += th_user_time;
		my_system_time += th_system_time;
		my_percent += th_percent;
	}
	
	// destroy thread array
	for (i = 0; i < th_count; i++)
		mach_port_deallocate(mach_task_self(), th_array[i]);
	vm_deallocate(mach_task_self(), (vm_address_t)th_array, sizeof(thread_t) * th_count);
	
	// check last error
	if (error != KERN_SUCCESS)
		return error;
	
	// add time for dead threads
	my_user_time += t_info.user_time.seconds + t_info.user_time.microseconds / 1e6;
	my_system_time += t_info.system_time.seconds + t_info.system_time.microseconds / 1e6;
	
	if (user_time != NULL) *user_time = my_user_time;
	if (system_time != NULL) *system_time = my_system_time;
	if (percent != NULL) *percent = my_percent;
		
	return error;
}

static kern_return_t
AGGetMachThreadPriority(thread_t thread, integer_t *current_priority, integer_t *base_priority) {
	kern_return_t error;
	struct thread_basic_info th_info;
	mach_msg_type_number_t th_info_count = THREAD_BASIC_INFO_COUNT;
	int my_current_priority = 0;
	int my_base_priority = 0;
	
	if ((error = thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&th_info, &th_info_count)) != KERN_SUCCESS)
		return error;
	
	switch (th_info.policy) {
	case POLICY_TIMESHARE: {
		struct policy_timeshare_info pol_info;
		mach_msg_type_number_t pol_info_count = POLICY_TIMESHARE_INFO_COUNT;
		
		if ((error = thread_info(thread, THREAD_SCHED_TIMESHARE_INFO, (thread_info_t)&pol_info, &pol_info_count)) != KERN_SUCCESS)
			return error;
		my_current_priority = pol_info.cur_priority;
		my_base_priority = pol_info.base_priority;
		break;
	} case POLICY_RR: {
		struct policy_rr_info pol_info;
		mach_msg_type_number_t pol_info_count = POLICY_RR_INFO_COUNT;
		
		if ((error = thread_info(thread, THREAD_SCHED_RR_INFO, (thread_info_t)&pol_info, &pol_info_count)) != KERN_SUCCESS)
			return error;
		my_current_priority = my_base_priority = pol_info.base_priority;
		break;
	} case POLICY_FIFO: {
		struct policy_fifo_info pol_info;
		mach_msg_type_number_t pol_info_count = POLICY_FIFO_INFO_COUNT;
		
		if ((error = thread_info(thread, THREAD_SCHED_FIFO_INFO, (thread_info_t)&pol_info, &pol_info_count)) != KERN_SUCCESS)
			return error;
		my_current_priority = my_base_priority = pol_info.base_priority;
		break;
	}
	}
	
	if (current_priority != NULL) *current_priority = my_current_priority;
	if (base_priority != NULL) *base_priority = my_base_priority;
		
	return error;
}

static kern_return_t
AGGetMachTaskPriority(task_t task, integer_t *current_priority, integer_t *base_priority) {
	kern_return_t error;
	thread_array_t th_array;
	mach_msg_type_number_t th_count;
	int i;
	int my_current_priority = 0, my_base_priority = 0;
	
	if ((error = task_threads(task, &th_array, &th_count)) != KERN_SUCCESS)
		return error;
	
	for (i = 0; i < th_count; i++) {
		int th_current_priority, th_base_priority;
		if ((error = AGGetMachThreadPriority(th_array[i], &th_current_priority, &th_base_priority)) != KERN_SUCCESS)
			break;
		if (th_current_priority > my_current_priority)
			my_current_priority = th_current_priority;
		if (th_base_priority > my_base_priority)
			my_base_priority = th_base_priority;
	}
	
	// destroy thread array
	for (i = 0; i < th_count; i++)
		mach_port_deallocate(mach_task_self(), th_array[i]);
	vm_deallocate(mach_task_self(), (vm_address_t)th_array, sizeof(thread_t) * th_count);
	
	// check last error
	if (error != KERN_SUCCESS)
		return error;
	
	if (current_priority != NULL) *current_priority = my_current_priority;
	if (base_priority != NULL) *base_priority = my_base_priority;
	
	return error;
}

static kern_return_t
AGGetMachThreadState(thread_t thread, int *state) {
	kern_return_t error;
	struct thread_basic_info th_info;
	mach_msg_type_number_t th_info_count = THREAD_BASIC_INFO_COUNT;
	int my_state;
	
	if ((error = thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&th_info, &th_info_count)) != KERN_SUCCESS)
		return error;
		
	switch (th_info.run_state) {
	case TH_STATE_RUNNING:
		my_state = AGProcessStateRunnable;
		break;
	case TH_STATE_UNINTERRUPTIBLE:
		my_state = AGProcessStateUninterruptible;
		break;
	case TH_STATE_WAITING:
		my_state = th_info.sleep_time > 20 ? AGProcessStateIdle : AGProcessStateSleeping;
		break;
	case TH_STATE_STOPPED:
		my_state = AGProcessStateSuspended;
		break;
	case TH_STATE_HALTED:
		my_state = AGProcessStateZombie;
		break;
	default:
		my_state = AGProcessStateUnknown;
	}
	
	if (state != NULL) *state = my_state;
	
	return error;
}

static kern_return_t
AGGetMachTaskState(task_t task, int *state) {
	kern_return_t error;
	thread_array_t th_array;
	mach_msg_type_number_t th_count;
	int i;
	int my_state = INT_MAX;
	
	if ((error = task_threads(task, &th_array, &th_count)) != KERN_SUCCESS)
		return error;
	
	for (i = 0; i < th_count; i++) {
		int th_state;
		if ((error = AGGetMachThreadState(th_array[i], &th_state)) != KERN_SUCCESS)
			break;
		// most active state takes precedence
		if (th_state < my_state)
			my_state = th_state;
	}
	
	// destroy thread array
	for (i = 0; i < th_count; i++)
		mach_port_deallocate(mach_task_self(), th_array[i]);
	vm_deallocate(mach_task_self(), (vm_address_t)th_array, sizeof(thread_t) * th_count);
	
	// check last error
	if (error != KERN_SUCCESS)
		return error;
		
	if (state != NULL) *state = my_state;
	
	return error;
}

static kern_return_t
AGGetMachTaskThreadCount(task_t task, integer_t *count) {
	kern_return_t error;
	thread_array_t th_array;
	mach_msg_type_number_t th_count;
	int i;
	
	if ((error = task_threads(task, &th_array, &th_count)) != KERN_SUCCESS)
		return error;
	
	for (i = 0; i < th_count; i++)
		mach_port_deallocate(mach_task_self(), th_array[i]);
	vm_deallocate(mach_task_self(), (vm_address_t)th_array, sizeof(thread_t) * th_count);
	
	if (count != NULL) *count = th_count;
	
	return error;
}

static kern_return_t
AGGetMachTaskEvents(task_t task, integer_t *faults, integer_t *pageins, integer_t *cow_faults, integer_t *messages_sent, integer_t *messages_received, integer_t *syscalls_mach, integer_t *syscalls_unix, integer_t *csw) {
	kern_return_t error;
	task_events_info_data_t t_events_info;
	mach_msg_type_number_t t_events_info_count = TASK_EVENTS_INFO_COUNT;
	
	if ((error = task_info(task, TASK_EVENTS_INFO, (task_info_t)&t_events_info, &t_events_info_count)) != KERN_SUCCESS)
		return error;

	if (faults != NULL) *faults = t_events_info.faults;
	if (pageins != NULL) *pageins = t_events_info.pageins;
	if (cow_faults != NULL) *cow_faults = t_events_info.cow_faults;
	if (messages_sent != NULL) *messages_sent = t_events_info.messages_sent;
	if (messages_received != NULL) *messages_received = t_events_info.messages_received;
	if (syscalls_mach != NULL) *syscalls_mach = t_events_info.syscalls_mach;
	if (syscalls_unix != NULL) *syscalls_unix = t_events_info.syscalls_unix;
	if (csw != NULL) *csw = t_events_info.csw;
	
	return error;
}

@interface AGProcess (Private)
+ (NSArray *)processesForThirdLevelName:(int)name value:(int)value;
- (void)doProcargs;
@end

@implementation AGProcess (Private)

// this function is taken from: http://mikeash.com/pyblog/friday-qa-2011-03-18-random-numbers.html
// modified slightly so that it calls srandom() for us if it hasn't
static int RandomUnder(int topPlusOne)
{
    static BOOL initialized = NO;
    
    if (!initialized) {
        srandom(time(NULL));
        initialized = YES;
    }
    
    const unsigned two31 = 1U << 31;
    const unsigned maxUsable = (two31 / topPlusOne) * topPlusOne;
    
    while (1) {
        const unsigned num = random();
        if(num < maxUsable) {
            return num % topPlusOne;
        }
    }
}

+ (NSArray *)processesForThirdLevelName:(int)name value:(int)value {
	AGProcess *proc;
	NSMutableArray *processes = [NSMutableArray array];
	int mib[4] = { CTL_KERN, KERN_PROC, name, value };
	struct kinfo_proc *info;
	size_t length;
	int level, count, i;
	
	// KERN_PROC_ALL has 3 elements, all others have 4
	level = name == KERN_PROC_ALL ? 3 : 4;
	
	if (sysctl(mib, level, NULL, &length, NULL, 0) < 0)
		return processes;
	if (!(info = NSZoneMalloc(NULL, length)))
		return processes;
	if (sysctl(mib, level, info, &length, NULL, 0) < 0) {
		NSZoneFree(NULL, info);
		return processes;
	}
	
	// number of processes
	count = length / sizeof(struct kinfo_proc);
		
	for (i = 0; i < count; i++) {
		pid_t pid = info[i].kp_proc.p_pid;
		//NSLog(@"AGProcess: processesForThirdLevelName: pid = %d", pid);
		if (pid != 0) {
			proc = [self processForProcessIdentifier:pid];
			if (proc) {
				[processes addObject:proc];
			}
		}
	}
	
	NSZoneFree(NULL, info);
	return processes;
}

- (void)doProcargs
{       
	id args = [NSMutableArray array];
	id env = [NSMutableDictionary dictionary];
	int mib[3];

	// make sure this is only executed once for an instance
	if (command)
		return;
	
	if (major_version >= 8) { // kernel version >= 8.0 (Mac OS X 10.4 - Tiger)
		// a newer sysctl selector is available -- it includes the number of arguments as an integer at the beginning of the buffer
		mib[0] = CTL_KERN;
		mib[1] = KERN_PROCARGS2;
		mib[2] = process;
	} else {
		// use the older sysctl selector -- the argument/environment boundary will be determined heuristically
		mib[0] = CTL_KERN;
		mib[1] = KERN_PROCARGS;
		mib[2] = process;
	}
	
	size_t length = argument_buffer_size;
	char *buffer = (char *)malloc(length);;
	
	BOOL parserFailure = NO;
	if (sysctl(mib, 3, buffer, &length, NULL, 0) == 0) {  
		char *cp;
		BOOL isFirstArgument = YES;
		BOOL createAnnotation = NO;
		
		int argumentCount;
		if (major_version >= 8) { // kernel version >= 8.0 (Mac OS X 10.4 - Tiger)
			memcpy(&argumentCount, buffer, sizeof(argumentCount));
			cp = buffer + sizeof(argumentCount);
		} else {
			cp = buffer;
			argumentCount = -1;
		}

		//NSLog(@"AGProcess: doProcArgs: argumentCount = %d", argumentCount);

		// skip the exec_path
		BOOL execPathFound = NO;
		for (; cp < buffer + length; cp++) {
			if (*cp == '\0') {
				execPathFound = YES;
				break;
			}
		}
		if (execPathFound) {
			// skip trailing '\0' characters
			BOOL argumentStartFound = NO;
			for (; cp < buffer + length; cp++) {
				if (*cp != '\0') {
					// beginning of first argument reached
					argumentStartFound = YES;
					break;
				}
			}
			if (argumentStartFound) {
				char *currentItem = cp;
				
				NSString *lastItemString = nil;
				
				// get all arguments
				for (; cp < buffer + length; cp++) {
					if (*cp == '\0') {
						if (strlen(currentItem) > 0) {
							NSString *itemString = [NSString stringWithUTF8String:currentItem];
							if (itemString) {
								//NSLog(@"AGProcess: doProcArgs: itemString = %@, lastItemString = %@", itemString, lastItemString);

								NSString *lastPathComponent = [itemString lastPathComponent];

								if (! [lastPathComponent isEqualToString:@"LaunchCFMApp"]) {
									if (isFirstArgument) {
										// save command
										command = lastPathComponent;
										isFirstArgument = NO;
										
										// these are the commands we will annotate
										if ([command isEqualToString:@"DashboardClient"]) {
											createAnnotation = YES;
										} else if ([command isEqualTo:@"Yahoo! Widget Engine"]) {
											createAnnotation = YES;
										} else if ([command isEqualTo:@"java"]) {
											createAnnotation = YES;
										}
									} else {
										// the command argument is sometimes duplicated (for CFM apps?) -- ignore the argument if it is the same as the last one
										if (! [itemString isEqualToString:lastItemString]) {
											// add to the argument list
											[args addObject:itemString];
										}
										else
										{
											argumentCount--;
											//NSLog(@"AGProcess: doProcArgs: duplicate, argumentCount = %d", argumentCount);
											//NSLog(@"AGProcess: doProcArgs: duplicate, itemString = %@, lastItemString = %@", itemString, lastItemString);
										}
										
										// check if we need to annotate
										if (createAnnotation && (! annotation)) {
											NSString *pathExtension = [itemString pathExtension];
											
											if ([pathExtension isEqualTo:@"wdgt"]) { // for DashboardClient
												annotation = [lastPathComponent stringByDeletingPathExtension];
											} else if ([pathExtension isEqualTo:@"widget"]) { // for Konfabulator
												annotation = [lastPathComponent stringByDeletingPathExtension];
											} else if ([pathExtension isEqualTo:@"jar"]) { // for java
												annotation = lastPathComponent;
											}
										}
									}
								} else {
									argumentCount--;
									//NSLog(@"AGProcess: doProcArgs: CFM app, argumentCount = %d", argumentCount);
									//NSLog(@"AGProcess: doProcArgs: CFM app, lastPathComponent = %@", lastPathComponent);
								}
								
								lastItemString = itemString;
							} else {
								NSLog(@"AGProcess: doProcArgs: couldn't convert 0x%lx (0x%lx) [%ld of %ld] = '%s' (%ld) to NSString", (long)currentItem, (long)buffer, (long)(currentItem - buffer), (long)length, currentItem, (long)currentItem);
							}
						}
							
						currentItem = cp + 1;
					}
				}
			} else {
				NSLog(@"AGProcess: doProcArgs: start of argument list not found for pid = %d", process);
				parserFailure = YES;
			}
		} else {
			NSLog(@"AGProcess: doProcArgs: exec_path not found for pid = %d", process);
			parserFailure = YES;
		}

		// extract environment variables from the argument list
		if (argumentCount >= 0) {
			// we're using the newer sysctl selector, so use the argument count (less one for the command argument)
			if (argumentCount == 0)
			{
				NSLog(@"AGProcess: doProcArgs: new sysctl, argumentCount = %d, count = %ld", argumentCount, (long)[args count]);
				NSLog(@"AGProcess: doProcArgs: new sysctl, args = %@", [args description]);
				argumentCount = 1;
			}
			int i;
			for (i = [args count] - 1; i >= (argumentCount - 1); i--) {
				//NSLog(@"AGProcess: doProcArgs: i = %d", i);
				NSString *string = [args objectAtIndex:i];
				//NSLog(@"AGProcess: doProcArgs: string = %@", string);
				NSUInteger index = [string rangeOfString:@"="].location;
				if (index != NSNotFound)
					[env setObject:[string substringFromIndex:index + 1] forKey:[string substringToIndex:index]];
			}
			args = [args subarrayWithRange:NSMakeRange(0, i + 1)];
		} else {
			// we're using the older sysctl selector, so we just guess by looking for an '=' in the argument
			//NSLog(@"AGProcess: doProcArgs: new sysctl, argumentCount = %d, count = %d", argumentCount, [args count]);
			//NSLog(@"AGProcess: doProcArgs: new sysctl, args = %@", [args description]);
			int i;
			for (i = [args count] - 1; i >= 0; i--) {
				NSString *string = [args objectAtIndex:i];
				NSUInteger index = [string rangeOfString:@"="].location;
				if (index == NSNotFound)
					break;
				[env setObject:[string substringFromIndex:index + 1] forKey:[string substringToIndex:index]];
			}
			args = [args subarrayWithRange:NSMakeRange(0, i + 1)];
		}
	} else {
		parserFailure = YES;
	}
	
	if (parserFailure) {
		// probably caused by a zombie or exited process, but could also be bad data in the process arguments buffer
		// try to get the accounting name to partially recover from the error
		struct kinfo_proc info;
		size_t length = sizeof(struct kinfo_proc);
		int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
		
		if (sysctl(mib, 4, &info, &length, NULL, 0) < 0) {
			command = [[[NSString alloc] init] autorelease];
			NSLog(@"AGProcess: doProcArgs: no command");
		} else {
			command = [[[NSString alloc] initWithUTF8String:info.kp_proc.p_comm] autorelease];
			NSLog(@"AGProcess: doProcArgs: info.kp_proc.p_comm = %s", info.kp_proc.p_comm);
		}
	}

	//NSLog(@"AGProcess: doProcArgs: command = '%@', annotation = '%@', args = %@, env = %@", command, annotation, [args description], [env description]);
	
	[command retain];
	[annotation retain];
		
	free(buffer);
	
	arguments = [args retain];
	environment = [env retain];
}    

@end

@implementation AGProcess

// was hoping to preauthorize the app using something like this:
// https://blogs.oracle.com/dns/entry/understanding_the_authorization_framework_on
// and here:
// http://os-tres.net/blog/2010/02/17/mac-os-x-and-task-for-pid-mach-call/
// instead, we just try to get access to a known process (the Finder) instead.
/*
+ (BOOL)authorize {
	BOOL result = YES;
	
	OSStatus status;
//	AuthorizationItem taskport_item[] = {{"system.privilege.taskport:"}};
//	AuthorizationRights rights = {1, taskport_item}, *out_rights = NULL;
	AuthorizationRef authorization;
	
//	AuthorizationFlags auth_flags = kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | ( 1 << 5);
	AuthorizationFlags auth_flags = kAuthorizationFlagDefaults;
	
	status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, auth_flags, &authorization);
	if (status != errAuthorizationSuccess) {
		NSLog(@"AGProcess: AuthorizationCreate failed, status = %ld", (long)status);
		result = NO;
    }

	//status = AuthorizationCopyRights(authorization, &rights, kAuthorizationEmptyEnvironment, auth_flags, &out_rights);

	AuthorizationItem right = { "system.privilege.taskport", 0, 0, 0 };
    AuthorizationItem items[] = { right };
    AuthorizationRights rights = { sizeof(items) / sizeof(items[0]), items };
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights | kAuthorizationFlagPreAuthorize;

	status = AuthorizationCopyRights(authorization, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
	if (status != errAuthorizationSuccess) {
		NSLog(@"AGProcess: AuthorizationCopyRights failed, status = %ld", (long)status);
		result = NO;
    }
	
	AuthorizationExternalForm externalForm;
	status =  AuthorizationMakeExternalForm(authorization, &externalForm);
	if (status != errAuthorizationSuccess) {
		NSLog(@"AGProcess: AuthorizationMakeExternalForm failed, status = %ld", (long)status);
		result = NO;
    }

	return result;
}
*/

+ (void)initialize {
	AGMachStatsInit();
	[super initialize];
}

- (id)initWithProcessIdentifier:(pid_t)pid {
	if (self = [super init]) {
		process = pid;
		//NSLog(@"AGProcess: initWithProcessIdentifier: pid = %d", pid);
		AGProcessState state = [self kernelState];
		if (state == AGProcessStateExited || state == AGProcessStateZombie) {
			// invalid process state, return nil
			[self release];
			return nil;
		}
		kern_return_t result;
		if ((result = task_for_pid(mach_task_self(), process, &task) != KERN_SUCCESS)) {
			// if we can't get a task, there's not much point in keeping the process around,
			// since we won't be able to query anything about the process
			[self release];
			return nil;
		}
	}
	return self;
}

+ (AGProcess *)currentProcess {
	return [self processForProcessIdentifier:getpid()];
}

+ (NSArray *)allProcesses {
	return [self processesForThirdLevelName:KERN_PROC_ALL value:0];
}

+ (NSArray *)userProcesses {
	return [self processesForUser:geteuid()];
}

+ (AGProcess *)processForProcessIdentifier:(pid_t)pid {
	const NSUInteger processCacheSize = 500;
	static NSMutableDictionary *processCache = nil;
	
	if (processCache == nil) {
		// a cache to keep track of the last 500 processes (since task_for_pid through taskgated is relatively slow)
		processCache = [[NSMutableDictionary dictionaryWithCapacity:processCacheSize] retain];
	}
	
	id result = [processCache objectForKey:[NSNumber numberWithInt:pid]];
	if (result) {
		if ([result isKindOfClass:[NSNull class]]) {
			// return nil instead of the null value in the cache
			result = nil;
		}
	}
	else {
		result = [[[self alloc] initWithProcessIdentifier:pid] autorelease];
		if (result) {
			NSUInteger processCacheCount = [processCache count];
			if (processCacheCount >= processCacheSize) {
				id randomKey = [[processCache allKeys] objectAtIndex:RandomUnder(processCacheCount)];
				[processCache removeObjectForKey:randomKey];
			}
			[processCache setObject:result forKey:[NSNumber numberWithInteger:pid]];
		}
		else {
			// no information available for this process, cache a null value to record the fact that we tried
			[processCache setObject:[NSNull null] forKey:[NSNumber numberWithInteger:pid]];
		}
	}

	return result;
}
	
+ (NSArray *)processesForProcessGroup:(int)pgid {
	return [self processesForThirdLevelName:KERN_PROC_PGRP value:pgid];
}
	
+ (NSArray *)processesForTerminal:(int)tty {
	return [self processesForThirdLevelName:KERN_PROC_TTY value:tty];
}
	
+ (NSArray *)processesForUser:(int)uid {
	return [self processesForThirdLevelName:KERN_PROC_UID value:uid];
}
	
+ (NSArray *)processesForRealUser:(int)ruid {
	return [self processesForThirdLevelName:KERN_PROC_RUID value:ruid];
}
	
+ (NSArray *)processesForCommand:(NSString *)comm {
	NSArray *all = [self allProcesses];
	NSMutableArray *result = [NSMutableArray array];
	int i, count = [all count];
	for (i = 0; i < count; i++)
		if ([[[all objectAtIndex:i] command] isEqualToString:comm])
			[result addObject:[all objectAtIndex:i]];
	return result;
}
	
+ (AGProcess *)processForCommand:(NSString *)comm {
	NSArray *processes = [self processesForCommand:comm];
	if ([processes count])
		return [processes objectAtIndex:0];
	return nil;
}
	
- (pid_t)processIdentifier {
	return process;
}
	
- (pid_t)parentProcessIdentifier {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_ppid;
}
	
- (pid_t)processGroup {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_pgid;
}
	
- (dev_t)terminal {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0 || info.kp_eproc.e_tdev == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_tdev;
}
	
- (pid_t)terminalProcessGroup {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0 || info.kp_eproc.e_tpgid == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_tpgid;
}

- (uid_t)userIdentifier {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_ucred.cr_uid;
}
	
- (uid_t)realUserIdentifier {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessValueUnknown;
	if (length == 0)
		return AGProcessValueUnknown;
	return info.kp_eproc.e_pcred.p_ruid;
}
	
- (NSString *)command {
	[self doProcargs];
	return command;
	return @"nothing";
}
	
- (NSString *)annotation {
	[self doProcargs];
	return annotation;
}
	
- (NSString *)annotatedCommand {
	[self doProcargs];
	if (annotation)
		return [NSString stringWithFormat:@"%@ (%@)", command, annotation];
	else
		return command;
}
	
- (NSArray *)arguments {
	[self doProcargs];
	return arguments;
}
	
- (NSDictionary *)environment {
	[self doProcargs];
	return environment;
}
	
- (AGProcess *)parent {
	return [[self class] processForProcessIdentifier:[self parentProcessIdentifier]];
}
	
- (NSArray *)children {
	NSArray *all = [[self class] allProcesses];
	NSMutableArray *children = [NSMutableArray array];
	int i, count = [all count];
	for (i = 0; i < count; i++)
		if ([[all objectAtIndex:i] parentProcessIdentifier] == process)
			[children addObject:[all objectAtIndex:i]];
	return children;
}
	
- (NSArray *)siblings {
	NSArray *all = [[self class] allProcesses];
	NSMutableArray *siblings = [NSMutableArray array];
	int i, count = [all count];
	pid_t ppid = [self parentProcessIdentifier];
	for (i = 0; i < count; i++) {
        AGProcess *p = [all objectAtIndex:i];
		if ([p parentProcessIdentifier] == ppid && [p processIdentifier] != process)
			[siblings addObject:p];
    }
	return siblings;
}
	
- (double)percentCPUUsage {
	double percent;
	if (AGGetMachTaskCPUUsage(task, NULL, NULL, &percent) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return percent;
}
	
- (double)totalCPUTime {
	double user, system;
	if (AGGetMachTaskCPUUsage(task, &user, &system, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return user + system;
}

- (double)userCPUTime {
	double user;
	if (AGGetMachTaskCPUUsage(task, &user, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return user;
}
	
- (double)systemCPUTime {
	double system;
	if (AGGetMachTaskCPUUsage(task, NULL, &system, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return system;
}    
	
- (double)percentMemoryUsage {
	double percent;
	if (AGGetMachTaskMemoryUsage(task, NULL, &percent) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return percent;
}
	
- (mach_vm_size_t)virtualMemorySize {
	mach_vm_size_t size;
	if (AGGetMachTaskVirtualMemoryUsage(process, task, &size) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return size;
}
	
- (vm_size_t)residentMemorySize {
	vm_size_t size;
	if (AGGetMachTaskMemoryUsage(task, &size, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return size;
}
	
- (AGProcessState)kernelState {
	struct kinfo_proc info;
	size_t length = sizeof(struct kinfo_proc);
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, process };
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return AGProcessStateExited;
	if (length == 0)
		return AGProcessStateExited;
	if (info.kp_proc.p_stat == SZOMB)
		return AGProcessStateZombie;
	return AGProcessStateUnknown;
}
	
- (AGProcessState)state {
	int state;
	state = [self kernelState];
	if (state == AGProcessStateUnknown)
		if (AGGetMachTaskState(task, &state) != KERN_SUCCESS)
			return AGProcessStateUnknown;
	return state;
}
	
- (integer_t)priority {
	integer_t priority;
	if (AGGetMachTaskPriority(task, &priority, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return priority;
}

- (integer_t)basePriority {
	integer_t priority;
	if (AGGetMachTaskPriority(task, NULL, &priority) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return priority;
}
	
- (integer_t)threadCount {
	integer_t count;
	if (AGGetMachTaskThreadCount(task, &count) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return count;
} 
	
- (NSUInteger)hash {
	return process;
}
	
- (BOOL)isEqual:(id)object {
	if (![object isKindOfClass:[self class]])
		return NO;
	return process == [(AGProcess *)object processIdentifier];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ process = %d, task = %u, command = %@, arguments = %@, environment = %@", [super description], process, task, [self command], [[self arguments] description], [[self environment] description]];
}
	
- (void)dealloc {
	mach_port_deallocate(mach_task_self(), task);
	[command release];
	[annotation release];
	[arguments release];
	[environment release];
	[super dealloc];
}
	
@end

@implementation AGProcess (Signals)

- (BOOL)suspend {
	return [self kill:SIGSTOP];
}
	
- (BOOL)resume {
	return [self kill:SIGCONT];
}
	
- (BOOL)interrupt {
	return [self kill:SIGINT];
}
	
- (BOOL)terminate {
	return [self kill:SIGTERM];
}
	
- (BOOL)kill:(int)signal {
	return kill(process, signal) == 0;
}

@end

@implementation AGProcess (MachTaskEvents)

- (integer_t)faults {
	integer_t faults;
	if (AGGetMachTaskEvents(task, &faults, NULL, NULL, NULL, NULL, NULL, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return faults;
}

- (integer_t)pageins {
	integer_t pageins;
	if (AGGetMachTaskEvents(task, NULL, &pageins, NULL, NULL, NULL, NULL, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return pageins;
}

- (integer_t)copyOnWriteFaults {
	integer_t cow_faults;
	if (AGGetMachTaskEvents(task, NULL, NULL, &cow_faults, NULL, NULL, NULL, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return cow_faults;
}

- (integer_t)messagesSent {
	integer_t messages_sent;
	if (AGGetMachTaskEvents(task, NULL, NULL, NULL, &messages_sent, NULL, NULL, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return messages_sent;
}

- (integer_t)messagesReceived {
	integer_t messages_received;
	if (AGGetMachTaskEvents(task, NULL, NULL, NULL, NULL, &messages_received, NULL, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return messages_received;
}

- (integer_t)machSystemCalls {
	integer_t syscalls_mach;
	if (AGGetMachTaskEvents(task, NULL, NULL, NULL, NULL, NULL, &syscalls_mach, NULL, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return syscalls_mach;
}

- (integer_t)unixSystemCalls {
	integer_t syscalls_unix;
	if (AGGetMachTaskEvents(task, NULL, NULL, NULL, NULL, NULL, NULL, &syscalls_unix, NULL) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return syscalls_unix;
}

- (integer_t)contextSwitches {
	integer_t csw;
	if (AGGetMachTaskEvents(task, NULL, NULL, NULL, NULL, NULL, NULL, NULL, &csw) != KERN_SUCCESS)
		return AGProcessValueUnknown;
	return csw;
}
	
@end
