//
//	NetworkInfo.h - Network Usage History Container Class
//


#import <Cocoa/Cocoa.h>

#import "sys/socket.h"
#import "net/if.h"
#import "net/if_types.h"

#import "netinet/in.h"

#import "sys/sysctl.h"
#import "sys/socketvar.h"
#import "netinet/ip_var.h"
#import "netinet/tcp.h"
#import "netinet/tcp_timer.h"
#import "netinet/tcp_var.h"

struct	iftot {
	u_int64_t	ift_ip;			/* input packets */
	u_int64_t	ift_ie;			/* input errors */
	u_int64_t	ift_op;			/* output packets */
	u_int64_t	ift_oe;			/* output errors */
	u_int64_t	ift_co;			/* collisions */
	u_int64_t	ift_dr;			/* drops */
	u_int64_t	ift_ib;			/* input bytes */
	u_int64_t	ift_ob;			/* output bytes */
};

typedef struct netdata {
	u_int64_t packetsIn;
	u_int64_t packetsInTotal;
	u_int64_t packetsInError;
	u_int64_t packetsInBytes;
	u_int64_t packetsInBytesTotal;
	u_int64_t packetsOut;
	u_int64_t packetsOutTotal;
	u_int64_t packetsOutError;
	u_int64_t packetsOutBytes;
	u_int64_t packetsOutBytesTotal;
	u_int64_t packetsCollision;
}	NetData, *NetDataPtr;


@interface NetworkInfo : NSObject
{
	int size;
	int inptr;
	int outptr;
	NetDataPtr netdata;

	struct iftot lastTotalStats;
}

- (NetworkInfo *)initWithCapacity:(unsigned)numItems;
- (void)refresh;
- (void)startIterate;
- (BOOL)getNext:(NetDataPtr)ptr;
- (void)getCurrent:(NetDataPtr)ptr;
- (void)getLast:(NetDataPtr)ptr;
- (int)getSize;

@end
