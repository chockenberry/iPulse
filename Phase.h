/*
 *  Phase.h
 *
 *  Created by Craig Hockenberry on Mon Jul 21 2003.
 */

#include <time.h>

/* Adapted from "moontool.c" by John Walker, Release 2.0. */

/* phase - calculate phase of moon as a fraction:
**
**	The argument is the time for which the phase is requested,
**	expressed as a Julian date and fraction.  Returns the terminator
**	phase angle as a percentage of a full circle (i.e., 0 to 1),
**	and stores into pointer arguments the illuminated fraction of
**      the Moon's disc, the Moon's age in days and fraction, the
**	distance of the Moon from the centre of the Earth, and the
**	angular diameter subtended by the Moon as seen by an observer
**	at the centre of the Earth.
*/

//double pdate;
//double *pphase; 		   /* illuminated fraction */
//double *mage;			   /* age of moon in days */
//double *dist;			   /* distance in kilometres */
//double *angdia; 		   /* angular diameter in degrees */
//double *sudist; 		   /* distance to Sun */
//double *suangdia;                  /* sun's angular diameter */

// synodic month (new Moon to new Moon)
#define synmonth    29.53058868

double phase(double pdate, double *pphase, double *mage, double *dist, double *angdia, double *sudist, double *suangdia);
double jtime(struct tm* t);
