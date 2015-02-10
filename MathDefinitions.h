/*
 *  MathDefinitions.h
 *
 *  Created by Craig Hockenberry on Mon Jul 21 2003.
 */

#include <math.h>

// handy mathematical functions

// extract sign
#define sgn(x) (((x) < 0) ? -1 : ((x) > 0 ? 1 : 0))

// absolute value
#define abs(x) ((x) < 0 ? (-(x)) : (x))

// fix angle
#define fixangle(a) ((a) - 360.0 * (floor((a) / 360.0)))

// degrees to radians
#define torad(d) ((d) * (M_PI / 180.0))

// radians to degrees
#define todeg(d) ((d) * (180.0 / M_PI))

// sin using degrees
#define dsin(x) (sin(torad((x))))

// cos using degrees
#define dcos(x) (cos(torad((x))))

