/*
 *  Phase.c
 *
 *  Created by Craig Hockenberry on Mon Jul 21 2003.
 */

#include "Phase.h"

#include "MathDefinitions.h"

/* Adapted from "moontool.c" by John Walker, Release 2.0. */

#include <stdio.h>
#include <math.h>
//#include "tws.h"

/* Astronomical constants. */

#define epoch	    2444238.5	   /* 1980 January 0.0 */

/* Constants defining the Sun's apparent orbit. */

#define elonge	    278.833540	   /* ecliptic longitude of the Sun
				        at epoch 1980.0 */
#define elongp	    282.596403	   /* ecliptic longitude of the Sun at
				        perigee */
#define eccent      0.016718       /* eccentricity of Earth's orbit */
#define sunsmax     1.495985e8     /* semi-major axis of Earth's orbit, km */
#define sunangsiz   0.533128       /* sun's angular size, degrees, at
				        semi-major axis distance */

/* Elements of the Moon's orbit, epoch 1980.0. */

#define mmlong      64.975464      /* moon's mean lonigitude at the epoch */
#define mmlongp     349.383063	   /* mean longitude of the perigee at the
				        epoch */
#define mlnode	    151.950429	   /* mean longitude of the node at the
				        epoch */
#define minc        5.145396       /* inclination of the Moon's orbit */
#define mecc        0.054900       /* eccentricity of the Moon's orbit */
#define mangsiz     0.5181         /* moon's angular size at distance a
				        from Earth */
#define msmax       384401.0       /* semi-major axis of Moon's orbit in km */
#define mparallax   0.9507	   /* parallax at distance a from Earth */
#define lunatbase   2423436.0      /* base date for E. W. Brown's numbered
				        series of lunations (1923 January 16) */

/* Properties of the Earth. */

#define earthrad    6378.16	   /* radius of Earth in kilometres */


/* jdate - convert internal GMT date and time to Julian day and fraction */

static long jdate(struct tm* t)
//struct tws *t;
{
	long c, m, y;

	y = t->tm_year + 1900;
	m = t->tm_mon + 1;
	if (m > 2)
	   m = m - 3;
	else {
	   m = m + 9;
	   --y;
	}
	c = y / 100L;		/* compute century */
	y -= 100L * c;
	return (t->tm_mday + (c * 146097L) / 4 + (y * 1461L) / 4 + (m * 153L + 2) / 5 + 1721119L);
}

/* jtime - convert internal date and time to astronomical Julian
**	     time (i.e. Julian date plus day fraction, expressed as
**	     a double)
*/

double jtime(struct tm* t)
//struct tws *t;
{
//	int c;
//
//	c = - t->tw_zone;
//	if ( t->tw_flags & TW_DST )
//		c += 60;
//	return (jdate(t) - 0.5) + (t->tw_sec + 60 * (t->tw_min + c + 60 * t->tw_hour)) / 86400.0;

	return (((double)jdate(t) - 0.5) + (double)(t->tm_sec + 60 * (t->tm_min + 60 * t->tm_hour)) / 86400.0);
}

/* jyear - convert Julian date to year, month, day, which are
**	     returned via integer pointers to integers
*/

static void jyear(td, yy, mm, dd)
double td;
int *yy, *mm, *dd;
{
	double j, d, y, m;

	td += 0.5;		   /* astronomical to civil */
	j = floor(td);
	j = j - 1721119.0;
	y = floor(((4 * j) - 1) / 146097.0);
	j = (j * 4.0) - (1.0 + (146097.0 * y));
	d = floor(j / 4.0);
	j = floor(((4.0 * d) + 3.0) / 1461.0);
	d = ((4.0 * d) + 3.0) - (1461.0 * j);
	d = floor((d + 4.0) / 4.0);
	m = floor(((5.0 * d) - 3) / 153.0);
	d = (5.0 * d) - (3.0 + (153.0 * m));
	d = floor((d + 5.0) / 5.0);
	y = (100.0 * y) + j;
	if (m < 10.0)
	   m = m + 3;
	else {
	   m = m - 9;
	   y = y + 1;
	}
	*yy = y;
	*mm = m;
	*dd = d;
}

/* meanphase - calculates mean phase of the Moon for a given base date
**               and desired phase:
**		     0.0   New Moon
**		     0.25  First quarter
**		     0.5   Full moon
**		     0.75  Last quarter
**		 Beware!!!  This routine returns meaningless
**               results for any other phase arguments.  Don't
**		 attempt to generalise it without understanding
**		 that the motion of the moon is far more complicated
**		 that this calculation reveals.
*/

static double meanphase(sdate, phase, usek)
double sdate, phase;
double *usek;
{
	int yy, mm, dd;
	double k, t, t2, t3, nt1;

	jyear(sdate, &yy, &mm, &dd);

	k = (yy + ((mm - 1) * (1.0 / 12.0)) - 1900) * 12.3685;

	/* Time in Julian centuries from 1900 January 0.5. */
	t = (sdate - 2415020.0) / 36525;
	t2 = t * t;		   /* square for frequent use */
	t3 = t2 * t;		   /* cube for frequent use */

	*usek = k = floor(k) + phase;
	nt1 = 2415020.75933 + synmonth * k
	      + 0.0001178 * t2
	      - 0.000000155 * t3
	      + 0.00033 * dsin(166.56 + 132.87 * t - 0.009173 * t2);

	return nt1;
}

/* truephase - given a K value used to determine the mean phase of the
**               new moon, and a phase selector (0.0, 0.25, 0.5, 0.75),
**               obtain the true, corrected phase time
*/

static double truephase(k, phase)
double k, phase;
{
	double t, t2, t3, pt, m, mprime, f;
	int apcor = 0;

	k += phase;		   /* add phase to new moon time */
	t = k / 1236.85;	   /* time in Julian centuries from
				        1900 January 0.5 */
	t2 = t * t;		   /* square for frequent use */
	t3 = t2 * t;		   /* cube for frequent use */
	pt = 2415020.75933	   /* mean time of phase */
	     + synmonth * k
	     + 0.0001178 * t2
	     - 0.000000155 * t3
	     + 0.00033 * dsin(166.56 + 132.87 * t - 0.009173 * t2);

        m = 359.2242               /* Sun's mean anomaly */
	    + 29.10535608 * k
	    - 0.0000333 * t2
	    - 0.00000347 * t3;
        mprime = 306.0253          /* Moon's mean anomaly */
	    + 385.81691806 * k
	    + 0.0107306 * t2
	    + 0.00001236 * t3;
        f = 21.2964                /* Moon's argument of latitude */
	    + 390.67050646 * k
	    - 0.0016528 * t2
	    - 0.00000239 * t3;
	if ((phase < 0.01) || (abs(phase - 0.5) < 0.01)) {

	   /* Corrections for New and Full Moon. */

	   pt +=     (0.1734 - 0.000393 * t) * dsin(m)
		    + 0.0021 * dsin(2 * m)
		    - 0.4068 * dsin(mprime)
		    + 0.0161 * dsin(2 * mprime)
		    - 0.0004 * dsin(3 * mprime)
		    + 0.0104 * dsin(2 * f)
		    - 0.0051 * dsin(m + mprime)
		    - 0.0074 * dsin(m - mprime)
		    + 0.0004 * dsin(2 * f + m)
		    - 0.0004 * dsin(2 * f - m)
		    - 0.0006 * dsin(2 * f + mprime)
		    + 0.0010 * dsin(2 * f - mprime)
		    + 0.0005 * dsin(m + 2 * mprime);
	   apcor = 1;
	} else if ((abs(phase - 0.25) < 0.01 || (abs(phase - 0.75) < 0.01))) {
	   pt +=     (0.1721 - 0.0004 * t) * dsin(m)
		    + 0.0021 * dsin(2 * m)
		    - 0.6280 * dsin(mprime)
		    + 0.0089 * dsin(2 * mprime)
		    - 0.0004 * dsin(3 * mprime)
		    + 0.0079 * dsin(2 * f)
		    - 0.0119 * dsin(m + mprime)
		    - 0.0047 * dsin(m - mprime)
		    + 0.0003 * dsin(2 * f + m)
		    - 0.0004 * dsin(2 * f - m)
		    - 0.0006 * dsin(2 * f + mprime)
		    + 0.0021 * dsin(2 * f - mprime)
		    + 0.0003 * dsin(m + 2 * mprime)
		    + 0.0004 * dsin(m - 2 * mprime)
		    - 0.0003 * dsin(2 * m + mprime);
	   if (phase < 0.5)
	      /* First quarter correction. */
	      pt += 0.0028 - 0.0004 * dcos(m) + 0.0003 * dcos(mprime);
	   else
	      /* Last quarter correction. */
	      pt += -0.0028 + 0.0004 * dcos(m) - 0.0003 * dcos(mprime);
	   apcor = 1;
	}
	if (!apcor) {
           (void) fprintf(stderr, "truephase() called with invalid phase selector.\n");
		   pt = 0.0;
	}
	return pt;
}

/* phasehunt5 - find time of phases of the moon which surround the current
**                date.  Five phases are found, starting and ending with the
**                new moons which bound the current lunation
*/

void phasehunt5(sdate, phases)
double sdate;
double phases[5];
{
	double adate, k1, k2, nt1, nt2;

	adate = sdate - 45;
	nt1 = meanphase(adate, 0.0, &k1);
	for ( ; ; ) {
	   adate += synmonth;
	   nt2 = meanphase(adate, 0.0, &k2);
	   if (nt1 <= sdate && nt2 > sdate)
	      break;
	   nt1 = nt2;
	   k1 = k2;
	}
	phases[0] = truephase(k1, 0.0);
	phases[1] = truephase(k1, 0.25);
	phases[2] = truephase(k1, 0.5);
	phases[3] = truephase(k1, 0.75);
	phases[4] = truephase(k2, 0.0);
}


/* phasehunt2 - find time of phases of the moon which surround the current
**                date.  Two phases are found.
*/

void phasehunt2(sdate, phases, which)
double sdate;
double phases[2];
double which[2];
{
	double adate, k1, k2, nt1, nt2;

	adate = sdate - 45;
	nt1 = meanphase(adate, 0.0, &k1);
	for ( ; ; ) {
	   adate += synmonth;
	   nt2 = meanphase(adate, 0.0, &k2);
	   if (nt1 <= sdate && nt2 > sdate)
	      break;
	   nt1 = nt2;
	   k1 = k2;
	}
	phases[0] = truephase(k1, 0.0);
	which[0] = 0.0;
	phases[1] = truephase(k1, 0.25);
	which[1] = 0.25;
	if ( phases[1] <= sdate ) {
	   phases[0] = phases[1];
	   which[0] = which[1];
	   phases[1] = truephase(k1, 0.5);
	   which[1] = 0.5;
	   if ( phases[1] <= sdate ) {
	      phases[0] = phases[1];
	      which[0] = which[1];
	      phases[1] = truephase(k1, 0.75);
	      which[1] = 0.75;
	      if ( phases[1] <= sdate ) {
		 phases[0] = phases[1];
		 which[0] = which[1];
		 phases[1] = truephase(k2, 0.0);
		 which[1] = 0.0;
	      }
	   }
	}
}


/* kepler - solve the equation of Kepler */

static double kepler(m, ecc)
double m, ecc;
{
	double e, delta;
#define EPSILON 1E-6

	e = m = torad(m);
	do {
	   delta = e - ecc * sin(e) - m;
	   e -= delta / (1 - ecc * cos(e));
	} while (abs(delta) > EPSILON);
	return e;
}

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

double phase(double pdate, double *pphase, double *mage, double *dist, double *angdia, double *sudist, double *suangdia)
{

	double Day, N, M, Ec, Lambdasun, ml, MM, Ev, Ae, A3, MmP,
	       mEc, A4, lP, V, lPP,
	       MoonAge, MoonPhase,
	       MoonDist, MoonDFrac, MoonAng,
	       F, SunDist, SunAng;

        /* Calculation of the Sun's position. */

	Day = pdate - epoch;			/* date within epoch */
	N = fixangle((360 / 365.2422) * Day);	/* mean anomaly of the Sun */
	M = fixangle(N + elonge - elongp);  /* convert from perigee
					         co-ordinates to epoch 1980.0 */
	Ec = kepler(M, eccent);			/* solve equation of Kepler */
	Ec = sqrt((1 + eccent) / (1 - eccent)) * tan(Ec / 2);
	Ec = 2 * todeg(atan(Ec));		/* true anomaly */
        Lambdasun = fixangle(Ec + elongp);	/* Sun's geocentric ecliptic
					             longitude */
	/* Orbital distance factor. */
	F = ((1 + eccent * cos(torad(Ec))) / (1 - eccent * eccent));
	SunDist = sunsmax / F;			/* distance to Sun in km */
        SunAng = F * sunangsiz;		/* Sun's angular size in degrees */


        /* Calculation of the Moon's position. */

        /* Moon's mean longitude. */
	ml = fixangle(13.1763966 * Day + mmlong);

        /* Moon's mean anomaly. */
	MM = fixangle(ml - 0.1114041 * Day - mmlongp);

	/* Evection. */
	Ev = 1.2739 * sin(torad(2 * (ml - Lambdasun) - MM));

	/* Annual equation. */
	Ae = 0.1858 * sin(torad(M));

	/* Correction term. */
	A3 = 0.37 * sin(torad(M));

	/* Corrected anomaly. */
	MmP = MM + Ev - Ae - A3;

	/* Correction for the equation of the centre. */
	mEc = 6.2886 * sin(torad(MmP));

	/* Another correction term. */
	A4 = 0.214 * sin(torad(2 * MmP));

	/* Corrected longitude. */
	lP = ml + Ev + mEc - Ae + A4;

	/* Variation. */
	V = 0.6583 * sin(torad(2 * (lP - Lambdasun)));

	/* True longitude. */
	lPP = lP + V;

	/* Calculation of the phase of the Moon. */

	/* Age of the Moon in degrees. */
	MoonAge = lPP - Lambdasun;

	/* Phase of the Moon. */
	MoonPhase = (1 - cos(torad(MoonAge))) / 2;

	/* Calculate distance of moon from the centre of the Earth. */

	MoonDist = (msmax * (1 - mecc * mecc)) /
	   (1 + mecc * cos(torad(MmP + mEc)));

        /* Calculate Moon's angular diameter. */

	MoonDFrac = MoonDist / msmax;
	MoonAng = mangsiz / MoonDFrac;

	*pphase = MoonPhase;
	*mage = synmonth * (fixangle(MoonAge) / 360.0);
	*dist = MoonDist;
	*angdia = MoonAng;
	*sudist = SunDist;
	*suangdia = SunAng;
	return torad(fixangle(MoonAge));
}
