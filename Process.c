/*
 *  Process.c
 *
 *  Created by Craig Hockenberry on Fri Jul 25 2003.
 *
 *  Process accounting ripped out of top
 */

#include "Process.h"


#include <mach/mach.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <strings.h>
#include <nlist.h>
#include <fcntl.h>
#include <string.h>

#include <sys/types.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/time.h>

#include <mach/bootstrap.h>
#include <mach/host_info.h>
#include <mach/mach_error.h>
#include <mach/mach_types.h>
#include <mach/message.h>
#include <mach/vm_region.h>
#include <mach/vm_map.h>
#include <mach/vm_types.h>
#include <mach/vm_prot.h>
#include <mach/shared_memory_server.h>

#include <device/device_types.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>

#include <kvm.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_var.h>

#include <libc.h>
#include <termios.h>
#include <curses.h>
#include <sys/ioctl.h>


/*
 *	Translate thread state to a number in an ordered scale.
 *	When collapsing all the threads' states to one for the
 *	entire task, the lower-numbered state dominates.
 */
#define	STATE_MAX	7

int
mach_state_order(s, sleep_time)
        int s;
        long sleep_time;
 {
	switch (s) {
	case TH_STATE_RUNNING:		return(1);
	case TH_STATE_UNINTERRUPTIBLE:
					return(2);
	case TH_STATE_WAITING:		return((sleep_time > 20) ? 4 : 3);
	case TH_STATE_STOPPED:		return(5);
	case TH_STATE_HALTED:		return(6);
	default:			return(7);
	}
}
			    /*01234567 */
char	mach_state_table[] = "ZRUSITH?";

char *	state_name[] = {
		"zombie",
		"running",
		"stuck",
		"sleeping",
		"idle",
		"stopped",
		"halted",
		"unknown",
};
int state_breakdown[STATE_MAX+1];



int nproc;
int total_procs;
//int old_procs;
struct kinfo_proc *kbase;
struct kinfo_proc *kpb;
struct proc_info *proc;
struct proc_info *pp;
struct proc_info *oldproc;
struct proc_info **pref;
struct proc_info **prefp;

//int		topn  = 0;
//int             wanted_topn = 0;
//vm_size_t	pagesize;

int total_threads;

mach_port_t host_priv_port;
//mach_port_t host_port;

unsigned long long total_fw_private;

int do_proc0_vm = 1; // TODO: determine if this is really a good idea or not (equivalent to top -k, reports PID 0)
int events_only = 0; // TODO: this events mode will be useful for getting FAULTS/PAGEINS/COW_FAULTS in swapping gauge


void grab_task(task)
	task_t	task;
{
	int			pid;
	size_t			size;
	kern_return_t		ret;
	struct kinfo_proc	ki;
	int			mib[4];

	ret = pid_for_task(task, &pid);
	if (ret != KERN_SUCCESS)
		return;
	size = sizeof(ki);
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PID;
	mib[3] = pid;

	if (sysctl(mib, 4, &ki, &size, NULL, 0) < 0) {
	        perror("failure calling sysctl");
		exit(1);
	}
	if (ki.kp_proc.p_stat == 0) {
	        state_breakdown[0]++;
		return;
	}
	if (total_procs == nproc) {
		nproc *= 2;
		kbase = (struct kinfo_proc *) realloc(kbase,
						      nproc*sizeof(struct kinfo_proc));
		bzero(&kbase[total_procs], total_procs*sizeof(struct kinfo_proc));
		proc  = (struct proc_info *) realloc(proc,
						     nproc*sizeof(struct proc_info));
		bzero(&proc[total_procs], total_procs*sizeof(struct proc_info));
		oldproc  = (struct proc_info *) realloc(oldproc,
							nproc*sizeof(struct proc_info));
		bzero(&oldproc[total_procs], total_procs*sizeof(struct proc_info));
		pref  = (struct proc_info **) realloc(pref,
						      nproc*sizeof(struct proc_info *));
		bzero(&pref[total_procs], total_procs*sizeof(struct proc_info *));
	}
	kbase[total_procs] = ki;
	total_procs++;
}


void read_proc_table()
{

	mach_port_t	host;
	processor_set_t	*psets;
//	processor_set_name_array_t *psets;
	task_t		*tasks;
	unsigned int	pcount, tcount;
	kern_return_t	ret;
	processor_set_t	p;
	int		i, j;

	total_procs = 0;
	total_threads = 0;

	host = mach_host_self(); // host_priv_port;

	if (host == MACH_PORT_NULL) {
		printf("Insufficient privileges.\n");
		exit(0);
	}
	ret = host_processor_sets(host, &psets, &pcount);
	if (ret != KERN_SUCCESS) {
		mach_error("host_processor_sets", ret);
		exit(0);
	}
	for (i = 0; i < pcount; i++) {
		ret = host_processor_set_priv(host, psets[i], &p);
		if (ret != KERN_SUCCESS) {
			mach_error("host_processor_set_priv", ret);
			exit(0);       
		}
		
		ret = processor_set_tasks(p, &tasks, &tcount);
		if (ret != KERN_SUCCESS) {
			mach_error("processor_set_tasks", ret);
			exit(0);
		}
		for (j = 0; j < tcount; j++) {
			grab_task(tasks[j]);
			// don't delete our own task port
			if (tasks[j] != mach_task_self())
				mach_port_deallocate(mach_task_self(),	
				tasks[j]);
		}
		vm_deallocate(mach_task_self(), (vm_address_t)tasks,
			      tcount * sizeof(task_t));
		mach_port_deallocate(mach_task_self(), p);
		mach_port_deallocate(mach_task_self(), psets[i]);
	}
	vm_deallocate(mach_task_self(), (vm_address_t)psets,
		 pcount * sizeof(processor_set_t));
}



struct object_info {
        int 	            id;
        int                 pid;
        int                 share_type;
        int                 resident_page_count;
        int                 ref_count;
        int                 task_ref_count;
        int                 size;
        struct object_info  *next;
};

#define OBJECT_TABLE_SIZE	537
#define OT_HASH(object) (((unsigned)object)%OBJECT_TABLE_SIZE)

struct object_info      *shared_hash_table[OBJECT_TABLE_SIZE];

struct object_info *of_free_list = 0;


void
shared_hash_enter(int obj_id, int share_type, int resident_page_count, int ref_count, int size, int pid)
{
        register struct object_info **bucket;
        register struct object_info *of;

	of = shared_hash_table[OT_HASH(obj_id/OBJECT_TABLE_SIZE)];
	while (of) {
	        if (of->id == obj_id) {
		        of->size += size;
		        of->task_ref_count++;
			of->pid = pid;
			return;
		}
		of = of->next;
	}
	bucket = &shared_hash_table[OT_HASH(obj_id/OBJECT_TABLE_SIZE)];

	if (of = of_free_list)
	        of_free_list = of->next;
	else
	        of = (struct object_info *) malloc(sizeof(*of));

	of->resident_page_count = resident_page_count;
	of->id = obj_id;
	of->share_type = share_type;
	of->ref_count = ref_count;
	of->task_ref_count = 1;
	of->pid = pid;
	of->size = size;

	of->next = *bucket;
	*bucket = of;
}


void
pmem_doit(task_port_t task, int pid, int *shared, int *private, int *aliased, int *obj_count, int *vprivate, vm_size_t *vsize, unsigned long long *fw_private)
{
	vm_address_t	address = 0;
	kern_return_t	err = 0;
	register int    i;
	int             split = 0;

	*obj_count = *aliased = *shared = *private = *vprivate = 0;

	while (1) {
		mach_port_t		object_name;
		vm_region_top_info_data_t info;
		mach_msg_type_number_t  count;
	        vm_size_t		size;

		count = VM_REGION_TOP_INFO_COUNT;

		if (err = vm_region(task, &address, &size, VM_REGION_TOP_INFO, (vm_region_info_t)&info,
				    &count, &object_name))
		        break;

		if (address >= GLOBAL_SHARED_TEXT_SEGMENT && address < (GLOBAL_SHARED_DATA_SEGMENT + SHARED_DATA_REGION_SIZE)) {

			*fw_private += info.private_pages_resident * vm_page_size;

			if ( !split && info.share_mode == SM_EMPTY) {
			        vm_region_basic_info_data_64_t    b_info;
			  
				count = VM_REGION_BASIC_INFO_COUNT_64;
				if (err = vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO, (vm_region_info_t)&b_info,
					    &count, &object_name))
				        break;

				if (b_info.reserved)
				        split = 1;
			}
		        if (info.share_mode != SM_PRIVATE) {
			        address += size;
			        continue;
			}
		}
		address += size;

		*obj_count += 1;

		switch (info.share_mode) {

		case SM_PRIVATE:
		        *private  += info.private_pages_resident * vm_page_size;
		        *vprivate += size;
		        break;

		case SM_COW:
		        if (info.ref_count == 1)
    			        info.share_mode = SM_PRIVATE;
			if (pid && info.share_mode == SM_COW)
                                shared_hash_enter(info.obj_id, SM_COW, info.shared_pages_resident,
						  info.ref_count, size, pid);
			if (info.share_mode == SM_PRIVATE)
			        *private += info.shared_pages_resident * vm_page_size;
		        *private  += info.private_pages_resident * vm_page_size;
			
			if (info.share_mode == SM_PRIVATE)
			        *vprivate += size;
			else
			        *vprivate += info.private_pages_resident * vm_page_size;
			break;

		case SM_SHARED:
			if (pid)
                                shared_hash_enter(info.obj_id, SM_SHARED, info.shared_pages_resident,
						  info.ref_count, size, pid);
		        break;
		}
        }
        for (i = 0; i < OBJECT_TABLE_SIZE; i++) {
	        register struct object_info *sl;

	        sl = shared_hash_table[i];
		
	        while (sl) {
		        if (sl->pid == pid) {
			        if (sl->share_type == SM_SHARED) {
				        if (sl->ref_count == sl->task_ref_count) {
					        sl->share_type = SM_PRIVATE_ALIASED;
				
						*aliased  += sl->resident_page_count * vm_page_size;
						*vprivate += sl->size;
					}
				}
				if (sl->share_type != SM_PRIVATE_ALIASED)
				        *shared += sl->resident_page_count * vm_page_size;
			}
			sl->task_ref_count = 0;

			sl = sl->next;
		}
	}
	if (split)
	        *vsize -= (SHARED_TEXT_REGION_SIZE + SHARED_DATA_REGION_SIZE);
}


int
get_real_command_name(int pid, char *cbuf, int csize)
{
        /*
	 *      Get command and arguments.
	 */
	volatile int   *ip, *savedip;
	volatile char  *cp;
	char            c;
	char           *end_argc;
	int             mib[4];
	char           *arguments;
	int             arguments_size = 4096;
	volatile unsigned int *valuep;
	unsigned int    value;
	int             blahlen=0, skiplen=0;

	/*
	 * A sysctl() is made to find out the full path that the command
	 * was called with.
	 */
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROCARGS;
	mib[2] = pid;
	mib[3] = 0;

	arguments = (char *) malloc(arguments_size);
	if (sysctl(mib, 3, arguments, (size_t *)&arguments_size, NULL, 0) < 0) {
	        free(arguments);
		return(0);
	}
	end_argc = &arguments[arguments_size];

	ip = (int *)end_argc;
	ip -= 2;                /* last arg word and .long 0 */
	while (*--ip) {
	        if (ip == (int *)arguments) {
		        free(arguments);
			return(0);
		}
	}        
	savedip = ip;
	savedip++;
	cp = (char *)savedip;
	while (*--ip) {
	        if (ip == (int *)arguments) {
		        free(arguments);
			return(0);
		}
	}        
	ip++;
        valuep = (unsigned int *)ip;
        value = *valuep;

        if ((value & 0xbfff0000) == 0xbfff0000) {
	        ip++; ip++;
		valuep = ip;
		blahlen = strlen((char *)ip);
		skiplen = (blahlen +3 ) /4 ;
		valuep += skiplen;
		cp = (char *)valuep;
		while (!*cp)
		        cp++;
		savedip = (int *)cp;
        }
        for (cp = (char *)savedip; cp < (end_argc-1); cp++) {
	        c = *cp & 0177;

		if (c == 0)
		        break;
        }
        *cp = 0;

	if (cp > (char *)savedip)
	        cp--;

	while (cp > (char *)savedip) {
	        if (*cp == '/') {
		        cp++;
		        break;
		}
		cp--;
	}
        if (cp[0] == '-' || cp[0] == '?' || cp[0] <= ' ') {
	        /*
		 *  Not enough information
		 */
	        free(arguments);
		return(0);
        }
	(void) strncpy(cbuf, (char *)cp, csize);
	cbuf[csize] = '\0';

	free(arguments);
	return(1);
}


void get_proc_info(kpb, pi)
	struct kinfo_proc	*kpb;
	struct proc_info	*pi;
{
	task_port_t	task;
	mach_port_array_t	names, types;
	unsigned int	ncnt, tcnt;

	pi->uid	= kpb->kp_eproc.e_ucred.cr_uid;
	pi->pid	= kpb->kp_proc.p_pid;
	pi->ppid	= kpb->kp_eproc.e_ppid;
	pi->pgrp	= kpb->kp_eproc.e_pgid;
	pi->status	= kpb->kp_proc.p_stat;
	pi->flag	= kpb->kp_proc.p_flag;

	/*
	 *	Find the other stuff
	 */
	if (task_for_pid(mach_task_self(), pi->pid, &task) != KERN_SUCCESS) {
		pi->status = SZOMB;
	}

	else {
		task_basic_info_data_t	ti;
		unsigned int		count;
		unsigned int            aliased;
		thread_array_t		thread_table;
		unsigned int		table_size;
		thread_basic_info_t	thi;
		thread_basic_info_data_t thi_data;
		int			i, t_state;

		count = TASK_BASIC_INFO_COUNT;
		if (task_info(task, TASK_BASIC_INFO, (task_info_t)&ti,
				&count) != KERN_SUCCESS) {
			pi->status = SZOMB;
		} else {
			pi->virtual_size = ti.virtual_size;

			pi->resident_size = ti.resident_size;

			if ((pi->pid || do_proc0_vm) && (!events_only)) {
			        pmem_doit(task, pi->pid, &pi->shared, &pi->private, &aliased, &pi->obj_count, &pi->vprivate, &pi->virtual_size, &total_fw_private);
				pi->private += aliased;
			} else {
			        pi->shared    = 0;
			        pi->private   = 0;
				pi->vprivate  = 0;
			        pi->obj_count = 0;
			}
		        pi->orig_virtual_size = pi->virtual_size;
			pi->total_time = ti.user_time;
			time_value_add(&pi->total_time, &ti.system_time);
			
			pi->idle_time.seconds = 0;
			pi->idle_time.microseconds = 0;

			if (task_threads(task, &thread_table, &table_size) != KERN_SUCCESS)
			        pi->status = SZOMB;
			else {
			        pi->state = STATE_MAX;
				pi->pri = 255;
				pi->base_pri = 255;
				pi->all_swapped = TRUE;
				pi->has_idle_thread = FALSE;

				thi = &thi_data;

				pi->num_threads = table_size;
				total_threads += table_size;

				for (i = 0; i < table_size; i++) {
				        count = THREAD_BASIC_INFO_COUNT;
					if (thread_info(thread_table[i], THREAD_BASIC_INFO,
							(thread_info_t)thi, &count) == KERN_SUCCESS) {

					        if (thi->flags & TH_FLAGS_IDLE) {
						        pi->has_idle_thread = TRUE;
						    
							time_value_add(&pi->idle_time, 
								       &thi->user_time);
							time_value_add(&pi->idle_time,
								       &thi->system_time);
						} else {
						        time_value_add(&pi->total_time, 
								       &thi->user_time);
							time_value_add(&pi->total_time,
								       &thi->system_time);
						}
						t_state = mach_state_order(thi->run_state,
									   thi->sleep_time);
						if (t_state < pi->state)
						        pi->state = t_state;
// update priority info based on schedule policy
//					        if (thi->cur_priority < pi->pri)
//						        pi->pri = thi->cur_priority;
//					        if (thi->base_priority < pi->base_pri)
//						        pi->base_pri = thi->base_priority;
						if ((thi->flags & TH_FLAGS_SWAPPED) == 0)
						        pi->all_swapped = FALSE;

					}
					if (task != mach_task_self()) {
					        mach_port_deallocate(mach_task_self(),
								     thread_table[i]);
					}
				}
				(void) vm_deallocate(mach_task_self(), (vm_offset_t)thread_table,
						     table_size * sizeof(*thread_table));

				if (!events_only) {
				        if (mach_port_names(task, &names, &ncnt,
							    &types, &tcnt) == KERN_SUCCESS) {
					        pi->num_ports = ncnt;
						pi->orig_num_ports = ncnt;
						(void) vm_deallocate(mach_task_self(),
								     (vm_offset_t) names,
								     ncnt * sizeof(*names));
						(void) vm_deallocate(mach_task_self(),
								     (vm_offset_t) types,
								     tcnt * sizeof(*types));
					} else {
					        pi->num_ports = -1;
					}
				} else
				        pi->num_ports = 0;

				if (events_only) {
				        task_events_info_data_t	tei;

					count = TASK_EVENTS_INFO_COUNT;
					if (task_info(task, TASK_EVENTS_INFO, (task_info_t)&tei,
						      &count) != KERN_SUCCESS) {
					        pi->status = SZOMB;
					} else {
					        pi->tei = tei;
						
					}
				}
			}
		}
		if (task != mach_task_self()) {
			mach_port_deallocate(mach_task_self(), task);
		}
	}
	if ( strncmp (kpb->kp_proc.p_comm, "LaunchCFMA", 10) ||
	     !get_real_command_name(pi->pid, pi->command, sizeof(kpb->kp_proc.p_comm)-1)) {
	        (void) strncpy(pi->command, kpb->kp_proc.p_comm,
			       sizeof(kpb->kp_proc.p_comm)-1);
		pi->command[sizeof(kpb->kp_proc.p_comm)-1] = '\0';
	}
}


void filter_proc(void)
{
//	char c;
	int i;
//	int n;
	int mpid;
	int active_procs;
//	int avenrun[3];
//	long curr_time;
//	long elapsed_secs;
//	unsigned long long total_fw_vsize;
	unsigned long long total_virtual_size;
	unsigned long long total_private_size;
//	unsigned long long total_shared_size;
	unsigned int total_memory_regions = 0;
//	unsigned int total_shared_objects;
//	unsigned int total_fw_code_size;
//	unsigned int total_fw_data_size;
//	unsigned int total_fw_linkedit_size;
//	unsigned int total_frameworks;
//	vm_statistics_data_t	vm_stat;
//	struct host_load_info load_data;
//	int	host_count;
//	kern_return_t	error;
//	char    tbuf[256];
//	char    *dp;
//	int     clen;


	host_priv_port = mach_host_self(); // get_host_priv();

	/* read all of the process information */
	read_proc_table();


	/* count up process states and get pointers to interesting procs */

	mpid = 0;
	active_procs = 0;
	total_virtual_size = 0;
	total_private_size = 0;
	total_fw_private   = 0;

	prefp = pref;
	for (kpb = kbase, pp = proc, i = 0;
				i < total_procs;
				kpb++, pp++, i++) {

	        /* place pointers to each valid proc structure in pref[] */
	        get_proc_info(kpb, pp);

		if (kpb->kp_proc.p_stat != 0) {
		        *prefp++ = pp;
			active_procs++;
			if (pp->pid > mpid)
			        mpid = pp->pid;
			
			if ((unsigned int)pp->state > (unsigned int)STATE_MAX)
			        pp->state = STATE_MAX;
			state_breakdown[pp->state]++;
			total_virtual_size += pp->virtual_size;
			total_private_size += pp->private;
			total_memory_regions += pp->obj_count;
		}
		else
		        state_breakdown[0]++;
	}

	for (prefp = pref, i = 0; i < active_procs; prefp++, i++)
	{
		pp = *prefp;

		fprintf(stderr, "pid: %5d command: %-40.40s", pp->pid, pp->command);
	}
	
#if 0
		
		sprintf(tbuf, "%5d", pp->pid);	                /* pid */
		clen = strlen(tbuf);
		sprintf(&tbuf[clen], " %-10.10s ", pp->command); /* command */
		clen = clen + strlen(&tbuf[clen]);

		print_usage(&tbuf[clen], pp->cpu_usage);
		clen = clen + strlen(&tbuf[clen]);

		sprintf(&tbuf[clen], " ");
		clen++;

		print_time(&tbuf[clen], pp->total_time);	/* cputime */
		clen = clen + strlen(&tbuf[clen]);


		if (events_only) {
		    if (events_delta) {
			sprintf(&tbuf[clen], " %6d", pp->deltatei.faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %5d", pp->deltatei.pageins);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], "/%-4d", pp->deltatei.cow_faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %5d", pp->deltatei.messages_sent);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], "/%-4d", pp->deltatei.messages_received);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %5d", pp->deltatei.syscalls_unix);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], "/%-5d", pp->deltatei.syscalls_mach);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], "%6d", pp->deltatei.csw);
			clen = clen + strlen(&tbuf[clen]);
		    } else if (events_accumulate) {
			sprintf(&tbuf[clen], "  %-8d", pp->deltatei.faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-8d", pp->deltatei.pageins);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->deltatei.cow_faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->deltatei.messages_sent);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->deltatei.messages_received);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->deltatei.syscalls_unix);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-11d", pp->deltatei.syscalls_mach);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-8d", pp->deltatei.csw);
			clen = clen + strlen(&tbuf[clen]);
		    } else {
			sprintf(&tbuf[clen], "  %-8d", pp->tei.faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-8d", pp->tei.pageins);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->tei.cow_faults);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->tei.messages_sent);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->tei.messages_received);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-10d", pp->tei.syscalls_unix);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-11d", pp->tei.syscalls_mach);
			clen = clen + strlen(&tbuf[clen]);
			sprintf(&tbuf[clen], " %-8d", pp->tei.csw);
			clen = clen + strlen(&tbuf[clen]);
		    }
		} else {

		sprintf(&tbuf[clen], " %3d", pp->num_threads);	/* # of threads */
		clen = clen + strlen(&tbuf[clen]);
		sprintf(&tbuf[clen], " %5d", pp->num_ports);	/* # of ports */
		clen = clen + strlen(&tbuf[clen]);
	
		if (wide_output) {
		        if (pp->dnum_ports)
			        sprintf(&tbuf[clen], "(%5d)", pp->dnum_ports);
			else
			        sprintf(&tbuf[clen], "       ");
			clen = clen + strlen(&tbuf[clen]);
		}
		if (pp->pid || do_proc0_vm)
		        sprintf(&tbuf[clen], "  %4d", pp->obj_count);
		else
		        sprintf(&tbuf[clen], "     -");
		clen = clen + strlen(&tbuf[clen]);

		if (wide_output) {
		        if (pp->pid || do_proc0_vm) {
			        sprintf(&tbuf[clen], "  %5.5s", mem_to_string((unsigned long long)pp->vprivate));	/* res size */
				clen = clen + strlen(&tbuf[clen]);
			        sprintf(&tbuf[clen], "  %5.5s", mem_to_string((unsigned long long)pp->private));	/* res size */
				clen = clen + strlen(&tbuf[clen]);

				if (pp->drprvt)
				        sprintf(&tbuf[clen], "(%5.5s)", offset_to_string(pp->drprvt));
				else
				        sprintf(&tbuf[clen], "       ");
			} else
			        sprintf(&tbuf[clen], "      -      -       ");
		} else {
		        if (pp->drprvt == 0)
			        dp = " ";
			else if ((int)pp->drprvt > 0)
			        dp = "+";
			else
			        dp = "-";

		        if (pp->pid || do_proc0_vm)
			        sprintf(&tbuf[clen], "  %5.5s%s", mem_to_string((unsigned long long)pp->private), dp);        /* res size */
			else
			        sprintf(&tbuf[clen], "      -");
		}
		clen = clen + strlen(&tbuf[clen]);

		if (wide_output) {
		        if (pp->pid || do_proc0_vm) {
			        sprintf(&tbuf[clen], "  %5.5s", mem_to_string((unsigned long long)pp->shared));
				clen = clen + strlen(&tbuf[clen]);

				if (pp->drshrd)
				        sprintf(&tbuf[clen], "(%5.5s)", offset_to_string(pp->drshrd));
				else
				        sprintf(&tbuf[clen], "       ");
			} else
			        sprintf(&tbuf[clen], "      -       ");
		} else {
		        if (pp->drshrd == 0)
			        dp = " ";
			else if ((int)pp->drshrd > 0)
			        dp = "+";
			else
			        dp = "-";

		        if (pp->pid || do_proc0_vm)
			        sprintf(&tbuf[clen], " %5.5s%s", mem_to_string((unsigned long long)pp->shared), dp);
			else
			        sprintf(&tbuf[clen], "      - ");
		}
		clen = clen + strlen(&tbuf[clen]);

		if (wide_output) {
		        sprintf(&tbuf[clen], "  %5.5s", mem_to_string((unsigned long long)pp->resident_size));	/* res size */
			clen = clen + strlen(&tbuf[clen]);

		        if (pp->drsize)
			        sprintf(&tbuf[clen], "(%5.5s)", offset_to_string(pp->drsize));
			else
			        sprintf(&tbuf[clen], "       ");
		} else {
		        if (pp->drsize == 0)
			        dp = " ";
			else if ((int)pp->drsize > 0)
			        dp = "+";
			else
			        dp = "-";

			sprintf(&tbuf[clen], " %5.5s%s", mem_to_string((unsigned long long)pp->resident_size), dp);	/* res size */
		}
		clen = clen + strlen(&tbuf[clen]);

		if (wide_output) {
		        sprintf(&tbuf[clen], "  %5.5s", mem_to_string((unsigned long long)pp->virtual_size));	/* size */
			clen = clen + strlen(&tbuf[clen]);

		        if (pp->rvsize)
			        sprintf(&tbuf[clen], "(%5.5s)", offset_to_string(pp->rvsize));
			else
			        sprintf(&tbuf[clen], "       ");
		} else {
		        if (pp->dvsize == 0)
			        dp = " ";
			else if ((int)pp->dvsize > 0)
			        dp = "+";
			else
			        dp = "-";

		        sprintf(&tbuf[clen], " %5.5s%s", mem_to_string((unsigned long long)pp->virtual_size), dp);	/* size */
		}
		clen = clen + strlen(&tbuf[clen]);

		} /* else not events only */
#endif

}

// get command and arguments.
int getcommand(struct kinfo_proc *kp, char **command_name)
{
	int		command_length;
	char * cmdpath;
	volatile int 	*ip, *savedip;
	volatile char	*cp;
	int		nbad;
	char		c;
	char		*end_argc;
	int 		mib[4];
        char *		arguments;
	size_t 		arguments_size = 4096;
        int len=0;
        volatile unsigned int *valuep;
        unsigned int value;
        int blahlen=0, skiplen=0;
//        extern int eflg;
	int eflg = 0;



	/* A sysctl() is made to find out the full path that the command
	   was called with.
	*/

	mib[0] = CTL_KERN;
	mib[1] = KERN_PROCARGS;
	mib[2] = kp->kp_proc.p_pid;
	mib[3] = 0;

	arguments = (char *) malloc(arguments_size);
	if (sysctl(mib, 3, arguments, &arguments_size, NULL, 0) < 0) {
	  goto retucomm;
	}
    	end_argc = &arguments[arguments_size];


	ip = (int *)end_argc;
	ip -= 2;		/* last arg word and .long 0 */
	while (*--ip)
	    if (ip == (int *)arguments)
		goto retucomm;

        savedip = ip;
        savedip++;
        cp = (char *)savedip;
	while (*--ip)
	    if (ip == (int *)arguments)
		goto retucomm;
        ip++;
        
        valuep = (unsigned int *)ip;
        value = *valuep;
        if ((value & 0xbfff0000) == 0xbfff0000) {
                ip++;ip++;
		valuep = ip;
               blahlen = strlen(ip);
                skiplen = (blahlen +3 ) /4 ;
                valuep += skiplen;
                cp = (char *)valuep;
                while (!*cp) {
                    cp++;
                }
                savedip = cp;
        }
        
	nbad = 0;

	for (cp = (char *)savedip; cp < (end_argc-1); cp++) {
	    c = *cp & 0177;
	    if (c == 0)
		*cp = ' ';
	    else if (c < ' ' || c > 0176) {
		if (++nbad >= 5*(eflg+1)) {
		    *cp++ = ' ';
		    break;
		}
		*cp = '?';
	    }
	    else if (eflg == 0 && c == '=') {
		while (*--cp != ' ')
		    if (cp <= (char *)ip)
			break;
		break;
	    }
	}
	*cp = 0;
#if 0
	while (*--cp == ' ')
	    *cp = 0;
#endif
	cp = (char *)savedip;
	command_length = end_argc - cp;	/* <= MAX_COMMAND_SIZE */

	if (cp[0] == '-' || cp[0] == '?' || cp[0] <= ' ') {
	    /*
	     *	Not enough information - add short command name
	     */
             len = ((unsigned)command_length + MAXCOMLEN + 5);
	    cmdpath = (char *)malloc(len);
	    (void) strncpy(cmdpath, cp, command_length);
	    (void) strcat(cmdpath, " (");
	    (void) strncat(cmdpath, kp->kp_proc.p_comm, MAXCOMLEN+1);
	    (void) strcat(cmdpath, ")");
	   *command_name = cmdpath;
//            *cmdlen = len;
            free(arguments);
            return(1);
	}
	else {
                
	    cmdpath = (char *)malloc((unsigned)command_length + 1);
	    (void) strncpy(cmdpath, cp, command_length);
	    cmdpath[command_length] = '\0';
	   *command_name = cmdpath;
//            *cmdlen = command_length;
            free(arguments);
            return(1);
	}

    retucomm:
        len = (MAXCOMLEN + 5);
	cmdpath = (char *)malloc(len);
	(void) strcpy(cmdpath, " (");
	(void) strncat(cmdpath, kp->kp_proc.p_comm, MAXCOMLEN+1);
	(void) strcat(cmdpath, ")");
//	*cmdlen = len;
	   *command_name = cmdpath;
          free(arguments);
        return(1);
}

void getcommand2(struct kinfo_proc *kp, char **command_name)
{
	ProcessSerialNumber psn;
	 
	if (GetProcessForPID(kp->kp_proc.p_pid, &psn) == noErr)
	{
		ProcessInfoRec processInfo;
		*command_name = (char *) malloc(256);

		processInfo.processName = *command_name;
		GetProcessInformation(&psn, &processInfo);
		
		p2cstrcpy(*command_name, *command_name);
	}
	else
	{
		*command_name = (char *) malloc(MAXCOMLEN + 2);
		sprintf(*command_name, "(%s)", kp->kp_proc.p_comm);
	}
}

void list_procs(void)
{
	int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
	size_t size = 0;
	struct kinfo_proc *kp, *kprocbuf;
	int nentries;
	int i;

/*
	if (uid != (uid_t) -1) {
		what = KERN_PROC_UID;
		flag = getuid();
	} else if (ttydev != NODEV) {
		what = KERN_PROC_TTY;
		flag = ttydev;
	} else if (pid != -1) {
		what = KERN_PROC_PID;
		flag = pid;
	} else {
		what = KERN_PROC_ALL;
		flag = 0;
	}
*/
	
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_UID; // what
	mib[3] = getuid(); // flag


	if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0)
	{
		perror("Failure calling sysctl for bufSize");
		return;
	}
	
	kprocbuf = (struct kinfo_proc *)malloc(size);
	

	if (sysctl(mib, 4, kprocbuf, &size, NULL, 0) < 0)
	{
		perror("Failure calling sysctl for buffer");
		return;
	}

	// this has to be after the second sysctl since the bufSize may have changed
	nentries = size/ sizeof(struct kinfo_proc);

	kp = kprocbuf;
//	for (i = nentries; --i >= 0; ++kp)
	for (i = 0; i < nentries; i++)
	{
		pid_t pid = kp->kp_proc.p_pid;

		char *command;
#if 0
	#if 0		
		{
			// get  the full path of the command that started the process
			
			mib[0] = CTL_KERN;
			mib[1] = KERN_PROCARGS;
			mib[2] = pid;
			mib[3] = 0;
			
			size = 4096;
			command = (char *) malloc(size);
			if (sysctl(mib, 3, command, &size, NULL, 0) < 0)
			{
				perror("Failure calling sysctl for command");
				sprintf(command, "(%s)", kp->kp_proc.p_comm);
			}
		}
	#else
		getcommand(kp, &command);
	#endif
#else
		getcommand2(kp, &command);
#endif

//		kinfo[i].ki_p = kp;
//		get_task_info(&kinfo[i]);

		printf("%3d: pid = %5d command=%s\n", i, pid, command);
		fflush(stdout);
		
		free(command);
		
		kp++;
	}


	free(kprocbuf);
}


