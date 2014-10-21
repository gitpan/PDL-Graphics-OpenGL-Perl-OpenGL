/*  Last saved: Sat 13 Jun 2009 03:00:43 PM*/

/*  Copyright (c) 1998 Kenneth Albanowski. All rights reserved.
 *  Copyright (c) 2007 Bob Free. All rights reserved.
 *  This program is free software; you can redistribute it and/or
 *  modify it under the same terms as Perl itself.
 */

/* All OpenGL constants---should split */
#define IN_POGL_CONST_XS

/* This ends up being OpenGL.pm */
/* #define IN_POGL_MAIN_XS */

#include <stdio.h>

#include "pgopogl.h"


#ifdef HAVE_GL
#include "gl_util.h"
#endif

#ifdef HAVE_GLX
#include "glx_util.h"
#endif

#ifdef HAVE_GLU
#include "glu_util.h"
#endif

#if defined(HAVE_GLUT) || defined(HAVE_FREEGLUT)
#ifndef GLUT_API_VERSION
#define GLUT_API_VERSION 4
#endif
#include "glut_util.h"
#endif


/* These macros used in neoconstant */
#define i(test) if (strEQ(name, #test)) return newSViv((int)test);
#define f(test) if (strEQ(name, #test)) return newSVnv((double)test);

static SV *
neoconstant(char * name, int arg)
{
#include "gl_const.h"
#include "glu_const.h"
#include "glut_const.h"
#include "glx_const.h"
#include "glpm_const.h"
	;
	return 0;
}

#undef i
#undef f



MODULE = PDL::Graphics::OpenGL::Perl::OpenGL::Const		PACKAGE = PDL::Graphics::OpenGL::Perl::OpenGL

#ifdef IN_POGL_CONST_XS

#// Define a POGL Constant
SV *
constant(name,arg)
	char *	name
	int	arg
	CODE:
	{
		RETVAL = neoconstant(name, arg);
		if (!RETVAL)
			RETVAL = newSVsv(&PL_sv_undef);
	}
	OUTPUT:
	RETVAL

#endif /* End IN_POGL_CONST_XS */
