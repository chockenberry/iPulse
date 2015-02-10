/*
 *  Process.h
 *
 *  Created by Craig Hockenberry on Fri Jul 25 2003.
 *
 */

#include <Carbon/Carbon.h>


struct	proc_info {
	uid_t			uid;
	short			pid;
	short			ppid;
	short			pgrp;
	int			status;
	int			flag;

	int			state;
	int			pri;
	int			base_pri;
	boolean_t		all_swapped;
        boolean_t               has_idle_thread;
	time_value_t		total_time;
	time_value_t		idle_time;
	time_value_t		beg_total_time;
	time_value_t		beg_idle_time;

	vm_size_t		virtual_size;
	vm_size_t		resident_size;
	vm_size_t		orig_virtual_size;
	vm_offset_t		drsize, dvsize;
	vm_offset_t		drprvt, drshrd;
        vm_offset_t		rvsize;
        unsigned int            shared;
        unsigned int            private;
        unsigned int            vprivate;
        int                     obj_count;
	int			cpu_usage;
	int			cpu_idle;

	char			command[20];

	int			num_ports;
        int                     orig_num_ports;
        int                     dnum_ports;
	int			num_threads;
	thread_basic_info_t	threads;	/* array */
        task_events_info_data_t tei;
        task_events_info_data_t deltatei;
        task_events_info_data_t accumtei;
};

typedef	struct proc_info	*proc_info_t;

void filter_proc(void);
void list_procs(void);
