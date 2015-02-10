//
//	NetworkInfo.m - Network Usage History Container Class
//


#import "NetworkInfo.h"

#include <net/if.h>
#include <net/if_var.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <net/if_mib.h>
#include <net/ethernet.h>
#include <net/route.h>

@implementation NetworkInfo

#if DEBUG
#define DEBUG_STATS 1
#else
#define DEBUG_STATS 0
#endif
#define FILTER_DROPS 0

// this will only work on 10.4
static BOOL getTotalStats(struct iftot *sum)
{
	int name[6];
	size_t len;
	unsigned int ifcount, i;
	struct ifmibdata *ifmdall = 0;

	name[0] = CTL_NET;
	name[1] = PF_LINK;
	name[2] = NETLINK_GENERIC;

	len = sizeof(int);
	name[3] = IFMIB_SYSTEM;
	name[4] = IFMIB_IFCOUNT;
	if (sysctl(name, 5, &ifcount, &len, 0, 0) == 1)
	{
		// sysctl failed, fall back on ipstat/tcpstat
		return(NO);
	}

	len = ifcount * sizeof(struct ifmibdata);
	ifmdall = malloc(len);
	if (ifmdall == 0)
	{
		// malloc failed, fall back on ipstat/tcpstat
		return(NO);
	}
	bzero(ifmdall, len);

	len = ifcount * sizeof(struct ifmibdata);
	name[3] = IFMIB_IFALLDATA;
	name[4] = 0;
	name[5] = IFDATA_GENERAL;
	if (sysctl(name, 6, ifmdall, &len, (void *)0, 0) == -1)
	{
		// sysctl failed, fall back on ipstat/tcpstat
		return(NO);
	}
		
	sum->ift_ip = 0;
	sum->ift_ie = 0;
	sum->ift_ib = 0;
	sum->ift_op = 0;
	sum->ift_oe = 0;
	sum->ift_ob = 0;
	sum->ift_co = 0;
	sum->ift_dr = 0;
	for (i = 0; i < ifcount; i++) {
		struct ifmibdata *ifmd = ifmdall + i;

		unsigned int flags = ifmd->ifmd_flags;
		char *interfaceName = ifmd->ifmd_name;
		
		if ((flags & IFF_UP) && (flags & IFF_RUNNING))
		{
			// check for valid interface names and filter out the loopback interface
			BOOL firstCharacterValid = ((interfaceName[0] >= 'a' && interfaceName[0] <= 'z') || (interfaceName[0] >= 'A' && interfaceName[0] <= 'Z'));
			if (firstCharacterValid && (strlen(interfaceName) > 0) && (strlen(interfaceName) < IFNAMSIZ))
			{
				// ignore the loopback address
				if (strncmp(interfaceName, "lo0", 3) != 0) {
#if FILTER_DROPS
					if (ifmd->ifmd_snd_drops > 0) {
#if DEBUG_STATS
						// drops in the send queue are an indicator that bogus data has been read for the interface
						NSLog(@"NetworkInfo: ignoring interface %ld = '%-8s' flags = 0x%08x, ifmd_snd_drops = %u, ifi_ipackets = %10lld, ifi_opackets = %10lld, ift_ib = %10lld, ift_ob = %10lld", (long)i, interfaceName, ifmd->ifmd_flags, ifmd->ifmd_snd_drops, ifmd->ifmd_data.ifi_ipackets, ifmd->ifmd_data.ifi_opackets, ifmd->ifmd_data.ifi_ibytes, ifmd->ifmd_data.ifi_obytes);
#endif
					}
					else
#endif
					{
						sum->ift_ip += ifmd->ifmd_data.ifi_ipackets;
						sum->ift_ie += ifmd->ifmd_data.ifi_ierrors;
						sum->ift_ib += ifmd->ifmd_data.ifi_ibytes;
						sum->ift_op += ifmd->ifmd_data.ifi_opackets;
						sum->ift_oe += ifmd->ifmd_data.ifi_oerrors;
						sum->ift_ob += ifmd->ifmd_data.ifi_obytes;
						sum->ift_co += ifmd->ifmd_data.ifi_collisions;
						sum->ift_dr += ifmd->ifmd_snd_drops;
						//NSLog(@"NetworkInfo: processed interface %ld = '%-8s' flags = 0x%08x, ifi_ipackets = %10lld, ifi_opackets = %10lld, ift_ib = %10lld, ift_ob = %10lld", (long)i, interfaceName, ifmd->ifmd_flags, ifmd->ifmd_data.ifi_ipackets, ifmd->ifmd_data.ifi_opackets, ifmd->ifmd_data.ifi_ibytes, ifmd->ifmd_data.ifi_obytes);
					}
				}
			}
#if DEBUG_STATS
			else {
				NSLog(@"NetworkInfo: invalid interface %ld = '%-8s' flags = 0x%08x, ifmd_snd_drops = %u, ifi_ipackets = %10lld, ifi_opackets = %10lld, ift_ib = %10lld, ift_ob = %10lld", (long)i, interfaceName, ifmd->ifmd_flags, ifmd->ifmd_snd_drops, ifmd->ifmd_data.ifi_ipackets, ifmd->ifmd_data.ifi_opackets, ifmd->ifmd_data.ifi_ibytes, ifmd->ifmd_data.ifi_obytes);
			}
#endif
		}
	}
	
	free(ifmdall);

	return(YES);
}

- (NetworkInfo *)initWithCapacity:(unsigned)numItems
{
	self = [super init];
	size = numItems;
	netdata = calloc(numItems, sizeof(NetData));
	if (netdata == NULL) {
		NSLog (@"Failed to allocate buffer for NetworkInfo");
		return (nil);
	}
	inptr = 0;
	outptr = -1;

	getTotalStats(&lastTotalStats);

	return (self);
}


- (void)refresh
{
	//NSLog(@"NetworkInfo: using total stats");
	struct iftot totalStats;
	getTotalStats(&totalStats);

	// Note: the total stats can be less than the last total stats if an interface (and is corresponding counters) goes away -- this is most likely
	// to happen with a PPP connection (used by VPN)
	
	netdata[inptr].packetsIn = ((totalStats.ift_ip > lastTotalStats.ift_ip) ? (totalStats.ift_ip - lastTotalStats.ift_ip) : 0);
	netdata[inptr].packetsInTotal = totalStats.ift_ip;
	netdata[inptr].packetsInError = ((totalStats.ift_ie > lastTotalStats.ift_ie) ? (totalStats.ift_ie - lastTotalStats.ift_ie) : 0);
	netdata[inptr].packetsInBytes = ((totalStats.ift_ib > lastTotalStats.ift_ib) ? (totalStats.ift_ib - lastTotalStats.ift_ib) : 0);
	netdata[inptr].packetsInBytesTotal = totalStats.ift_ib;
	//NSLog(@"NetworkInfo: **** totalStats.ift_ip = %10lld, lastTotalStats.ift_ip = %10lld, packetsIn = %4lld ****", totalStats.ift_ip, lastTotalStats.ift_ip, netdata[inptr].packetsIn);

	netdata[inptr].packetsOut = ((totalStats.ift_op > lastTotalStats.ift_op) ? (totalStats.ift_op - lastTotalStats.ift_op) : 0);
	netdata[inptr].packetsOutTotal = totalStats.ift_op;
	netdata[inptr].packetsOutError = ((totalStats.ift_oe > lastTotalStats.ift_oe) ? (totalStats.ift_oe - lastTotalStats.ift_oe) : 0);
	netdata[inptr].packetsOutBytes = ((totalStats.ift_ob > lastTotalStats.ift_ob) ? (totalStats.ift_ob - lastTotalStats.ift_ob) : 0);
	netdata[inptr].packetsOutBytesTotal = totalStats.ift_ob;
	//NSLog(@"NetworkInfo: **** totalStats.ift_op = %10lld, lastTotalStats.ift_op = %10lld, packetsOut = %4lld ****", totalStats.ift_op, lastTotalStats.ift_op, netdata[inptr].packetsOut);

	netdata[inptr].packetsCollision = ((totalStats.ift_co > lastTotalStats.ift_co) ? (totalStats.ift_co - lastTotalStats.ift_co) : 0);

#if DEBUG_STATS
	if ((netdata[inptr].packetsInBytes > 10000000) || (netdata[inptr].packetsOutBytes > 10000000)) {
		NSLog(@"DANGER WILL ROBINSON"); // Clearly these stats are wrong, but I don't understand why: I can't find any signed integers being used as unsigned.
	}
#endif
	
	lastTotalStats = totalStats;

	if (++inptr >= size)
		inptr = 0;
}


- (void)startIterate
{
	outptr = inptr;
}


- (BOOL)getNext:(NetDataPtr)ptr
{
	if (outptr == -1)
		return (FALSE);
	*ptr = netdata[outptr++];
	if (outptr >= size)
		outptr = 0;
	if (outptr == inptr)
		outptr = -1;
	return (TRUE);
}


- (void)getCurrent:(NetDataPtr)ptr
{
	*ptr = netdata[inptr ? inptr - 1 : size - 1];
}


- (void)getLast:(NetDataPtr)ptr
{
	*ptr = netdata[inptr > 1 ? inptr - 2 : size + inptr - 2];
}


- (int)getSize
{
	return (size);
}

@end
