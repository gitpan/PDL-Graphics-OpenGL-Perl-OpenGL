/*  Last saved: Sat 13 Jun 2009 07:15:04 PM */

/*  Copyright (c) 1998 Kenneth Albanowski. All rights reserved.
 *  Copyright (c) 2007 Bob Free. All rights reserved.
 *  This program is free software; you can redistribute it and/or
 *  modify it under the same terms as Perl itself.
 */

/* OpenGL *GLUT bindings */
#define IN_POGL_GLUT_XS

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

#ifdef IN_POGL_GLUT_XS
#if defined(HAVE_GLUT) || defined(HAVE_FREEGLUT)
#ifndef GLUT_API_VERSION
#define GLUT_API_VERSION 4
#endif
#include "glut_util.h"
#endif

static int _done_glutInit = 0;
#endif /* End IN_POGL_GLUT_XS */



/* This does not seem to be used */
#if 0
static char *SWIZZLE[4] = {"x","y","z","w"}; */
#endif 

/* This does not seem to be used */
#if 0
static int
not_here(s)
char *s;
{
    croak("%s not implemented on this architecture", s);
    return -1;
}
#endif


#ifdef IN_POGL_GLUT_XS
#ifndef __PM__
#  define DO_perl_call_sv(handler, flag) perl_call_sv(handler, flag)
#  define ENSURE_callback_thread
#  define GLUT_PUSH_NEW_SV(sv)		XPUSHs(sv_2mortal(newSVsv(sv)))
#  define GLUT_PUSH_NEW_IV(i)		XPUSHs(sv_2mortal(newSViv(i)))
#  define GLUT_PUSH_NEW_U8(c)		XPUSHs(sv_2mortal(newSViv((int)c)))
#  define GLUT_EXTEND_STACK(sp,n)
#  define GLUT_PUSHMARK(sp)		PUSHMARK(sp)
#else
/* GLUT on OS/2 PM runs callbacks from a secondary thread.  This thread
   is not instrumented to run EMX CRTL functions.  Basically, no Perl
   function may be run from this thread.
   We create a ternary thread via CRTL _beginthread() call, and communicate
   the requests to this thread via inter-thread communication (ITC).  */

#  define GLUT_PUSHMARK(sp)

#  include "sys/builtin.h"
#  include "sys/fmutex.h"

#  include "os2pm_X.h"

#  define DO_perl_call_sv(handler, flag) 				\
    STMT_START {   	PUSHs(handler);					\
			PUTBACK;					\
			extend_by = 0;					\
			RUN_perl_call_sv();				\
    } STMT_END

#  define GLUT_START_PUSHING		7
#  define GLUT_PUSHING_IVP		17
#  define GLUT_PUSHING_U8		27
#  define GLUT_PUSHING_SV		37

#  define GLUT_EXTEND_STACK(p,n)					\
    STMT_START {   if (PL_stack_max - p < 2*(n)+4) {			\
		     extend_by = 2*(n)+4;				\
		     RUN_perl_call_sv();				\
		   }							\
		   SPAGAIN;						\
		   PUSHs((SV*)GLUT_START_PUSHING);			\
    } STMT_END

#  define GLUT_PUSH_NEW_SV(sv)	(PUSHs(sv), PUSHs((SV*)GLUT_PUSHING_SV))
#  define GLUT_PUSH_NEW_IV(i)	(PUSHs((SV*)&i), PUSHs((SV*)GLUT_PUSHING_IVP))
#  define GLUT_PUSH_NEW_U8(c)	(PUSHs((SV*)(int)c), PUSHs((SV*)GLUT_PUSHING_U8))

_fmutex run_mutex, result_mutex;
static int worker_started;
static int extend_by;

void
RUN_perl_call_sv(void)
{
    char *s = NULL;
    
    if (_fmutex_release(&run_mutex))
	s = "Error unlocking the callback thread";
    /* result_mutex is requested on entry!  Block until looper finishes. */
    else if (_fmutex_request(&result_mutex, _FMR_IGNINT))
	s = "Error requesting the callback thread";
    if (s)
	write(2, s, strlen(s));
    return;
}

/* Main event handler for callbacks */
void
callback_thread_looper(void *dummy)
{
    while (1) {
	/* It is requested already!  Wait until somebody requests a run */
	if (_fmutex_request(&run_mutex, _FMR_IGNINT)) {
	    warn("Error unlocking in the callback thread");
	    worker_started = 0;
	    return;
	}
	if (extend_by) {  /* Need to extend the stack */
	    dSP;

	    EXTEND(sp, extend_by);
	} else {
	    dSP;
	    SV* handler = POPs;
	    STRLEN n_a;
	    SV **last = sp, **f;

	    /* The rest is put on stack in a "raw" pointer form */
	    while (1) {
		switch ((IV)*sp) {
		case GLUT_START_PUSHING:
		    goto start_found;
		    break;
		case GLUT_PUSHING_IVP:
		case GLUT_PUSHING_SV:
		case GLUT_PUSHING_U8:
		    break;
		default:
		    croak("Panic: broken descriptor/down when ITC for Glut: %#lx", (unsigned long)*sp);
		    break;
		}
		sp -= 2;
	    }
	  start_found:
	    f = sp + 1;
	    sp--;
	    PUSHMARK(sp);
	    while (f < last) {
		switch ((IV)f[1]) {
		case GLUT_PUSHING_IVP:
		    PUSHs(sv_2mortal(newSViv(*(IV*)*f)));
		    break;
		case GLUT_PUSHING_U8:
		    PUSHs(sv_2mortal(newSViv((IV)*f)));
		    break;
		case GLUT_PUSHING_SV:
		    PUSHs(sv_2mortal(newSVsv(*f)));
		    break;
		default:
		    croak("Panic: broken descriptor/up when ITC for Glut: %#lx", (unsigned long)f[1]);
		    break;
		}
		f += 2;
	    }
	    PUTBACK;
	    perl_call_sv(handler, G_DISCARD|G_EVAL);
	    if (SvTRUE(ERRSV))
		fprintf(stderr, "Error in a GLUT Callback: %s", SvPV(ERRSV, n_a));
	}
	if (_fmutex_release(&result_mutex)) {
	    warn("Error in a callback thread");
	    worker_started = 0;
	    return;
	}	
    }
}

#  define ENSURE_callback_thread					\
	if (!worker_started)						\
	    start_callback_thread()

/* Spin a thread for a callback */
void
start_callback_thread()
{
    unsigned long rc;

    if (worker_started)
	return;
    if (  CheckOSError(_fmutex_create(&run_mutex, 0))
	  || CheckOSError(_fmutex_create(&result_mutex, 0))
	  || CheckOSError(_fmutex_request(&run_mutex, _FMR_IGNINT))
	  || CheckOSError(_fmutex_request(&result_mutex, _FMR_IGNINT)))
	croak("Error creating semaphores");
    worker_started = _beginthread(&callback_thread_looper, NULL,
				   8*1024*1024, NULL);
    if (worker_started == -1) {
	worker_started = 0;
	croak("Error creating callback thread");
    }
}
#endif	/* __PM__ */
#endif /* End IN_POGL_GLUT_XS */

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




/*
#define PackCallbackST(av,first)					\
	if (SvROK(ST(first)) && (SvTYPE(SvRV(ST(first))) == SVt_PVAV)){	\
		int i;							\
		AV * x = (AV*)SvRV(ST(first));				\
		for(i=0;i<=av_len(x);i++) {				\
			av_push(av, newSVsv(*av_fetch(x, i, 0)));	\
		}							\
	} else {							\
		int i;							\
		for(i=first;i<items;i++)				\
			av_push(av, newSVsv(ST(i)));			\
	}

*/

#ifdef IN_POGL_GLUT_XS

#ifdef GLUT_API_VERSION

static AV * glut_handlers = 0;

/* Attach a handler to a window */
static void set_glut_win_handler(int win, int type, SV * data)
{
	SV ** h;
	AV * a;
	
	if (!glut_handlers)
		glut_handlers = newAV();
	
	h = av_fetch(glut_handlers, win, FALSE);
	
	if (!h) {
		a = newAV();
		av_store(glut_handlers, win, newRV_inc((SV*)a));
		SvREFCNT_dec(a);
	} else if (!SvOK(*h) || !SvROK(*h))
		croak("Unable to establish glut handler");
	else 
		a = (AV*)SvRV(*h);
	
	av_store(a, type, newRV_inc(data));
	SvREFCNT_dec(data);
}

/* Get a window's handler */
static SV * get_glut_win_handler(int win, int type)
{
	SV ** h;
	
	if (!glut_handlers)
		croak("Unable to locate glut handler");
	
	h = av_fetch(glut_handlers, win, FALSE);

	if (!h || !SvOK(*h) || !SvROK(*h))
		croak("Unable to locate glut handler");
	
	h = av_fetch((AV*)SvRV(*h), type, FALSE);
	
	if (!h || !SvOK(*h) || !SvROK(*h))
		croak("Unable to locate glut handler");

	return SvRV(*h);
}

/* Release a window's handlers */
static void destroy_glut_win_handlers(int win)
{
	SV ** h;
	
	if (!glut_handlers)
		return;
	
	h = av_fetch(glut_handlers, win, FALSE);
	
	if (!h || !SvOK(*h) || !SvROK(*h))
		return;

	av_store(glut_handlers, win, newSVsv(&PL_sv_undef));
}

/* Release a handler */
static void destroy_glut_win_handler(int win, int type)
{
	SV ** h;
	AV * a;
	
	if (!glut_handlers)
		glut_handlers = newAV();
	
	h = av_fetch(glut_handlers, win, FALSE);
	
	if (!h || !SvOK(*h) || !SvROK(*h))
		return;

	a = (AV*)SvRV(*h);
	
	av_store(a, type, newSVsv(&PL_sv_undef));
}

/* Begin window callback definition */
#define begin_decl_gwh(type, params, nparam)				\
									\
static void generic_glut_ ## type ## _handler params			\
{									\
	int win = glutGetWindow();					\
	AV * handler_data = (AV*)get_glut_win_handler(win, HANDLE_GLUT_ ## type);\
	SV * handler;							\
	int i;								\
	dSP;								\
									\
	handler = *av_fetch(handler_data, 0, 0);			\
									\
	GLUT_PUSHMARK(sp);						\
	GLUT_EXTEND_STACK(sp,av_len(handler_data)+nparam);		\
	for (i=1;i<=av_len(handler_data);i++)				\
		GLUT_PUSH_NEW_SV(*av_fetch(handler_data, i, 0));

/* End window callback definition */
#define end_decl_gwh()							\
	PUTBACK;							\
	DO_perl_call_sv(handler, G_DISCARD);				\
}

/* Activate a window callback handler */
#define decl_gwh_xs(type)						\
	{								\
		int win = glutGetWindow();				\
									\
		if (!handler || !SvOK(handler)) {			\
			destroy_glut_win_handler(win, HANDLE_GLUT_ ## type);\
			glut ## type ## Func(NULL);			\
		} else {						\
			AV * handler_data = newAV();			\
									\
			PackCallbackST(handler_data, 0);		\
									\
			set_glut_win_handler(win, HANDLE_GLUT_ ## type, (SV*)handler_data);\
									\
			glut ## type ## Func(generic_glut_ ## type ## _handler);\
		}							\
	ENSURE_callback_thread;}

/* Activate a window callback handler; die on failure */
#define decl_gwh_xs_nullfail(type, fail)				\
	{								\
		int win = glutGetWindow();				\
									\
		if (!handler || !SvOK(handler)) {			\
			croak fail;					\
		} else {						\
			AV * handler_data = newAV();			\
									\
			PackCallbackST(handler_data, 0);		\
									\
			set_glut_win_handler(win, HANDLE_GLUT_ ## type, (SV*)handler_data);\
									\
			glut ## type ## Func(generic_glut_ ## type ## _handler);\
		}							\
	ENSURE_callback_thread;}


/* Activate a global state callback handler */
#define decl_ggh_xs(type)						\
	{								\
		if (glut_ ## type ## _handler_data)			\
			SvREFCNT_dec(glut_ ## type ## _handler_data);	\
									\
		if (!handler || !SvOK(handler)) {			\
			glut_ ## type ## _handler_data = 0;		\
			glut ## type ## Func(NULL);			\
		} else {						\
			AV * handler_data = newAV();			\
									\
			PackCallbackST(handler_data, 0);		\
									\
			glut_ ## type ## _handler_data = handler_data;	\
									\
			glut ## type ## Func(generic_glut_ ## type ## _handler);\
		}							\
	ENSURE_callback_thread;}


/* Begin a global state callback definition */
#define begin_decl_ggh(type, params, nparam)				\
									\
static AV * glut_ ## type ## _handler_data = 0;				\
									\
static void generic_glut_ ## type ## _handler params			\
{									\
	AV * handler_data = glut_ ## type ## _handler_data;		\
	SV * handler;							\
	int i;								\
	dSP;								\
									\
	handler = *av_fetch(handler_data, 0, 0);			\
									\
	GLUT_PUSHMARK(sp);						\
	GLUT_EXTEND_STACK(sp,av_len(handler_data)+nparam);		\
	for (i=1;i<=av_len(handler_data);i++)				\
		GLUT_PUSH_NEW_SV(*av_fetch(handler_data, i, 0));

/* End a global state callback definition */
#define end_decl_ggh()							\
	PUTBACK;							\
	DO_perl_call_sv(handler, G_DISCARD);				\
}

/* Define callbacks */
enum {
	HANDLE_GLUT_Display,
	HANDLE_GLUT_OverlayDisplay,
	HANDLE_GLUT_Reshape,
	HANDLE_GLUT_Keyboard,
	HANDLE_GLUT_KeyboardUp,
	HANDLE_GLUT_Mouse,
        HANDLE_GLUT_MouseWheel,             /* Open/FreeGLUT -chm */
	HANDLE_GLUT_Motion,
	HANDLE_GLUT_PassiveMotion,
	HANDLE_GLUT_Entry,
	HANDLE_GLUT_Visibility,
	HANDLE_GLUT_WindowStatus,
	HANDLE_GLUT_Special,
	HANDLE_GLUT_SpecialUp,
        HANDLE_GLUT_Joystick,               /* Open/FreeGLUT -chm */
	HANDLE_GLUT_SpaceballMotion,
	HANDLE_GLUT_SpaceballRotate,
	HANDLE_GLUT_SpaceballButton,
	HANDLE_GLUT_ButtonBox,
	HANDLE_GLUT_Dials,
	HANDLE_GLUT_TabletMotion,
	HANDLE_GLUT_TabletButton,
        HANDLE_GLUT_MenuDestroy,            /* Open/FreeGLUT -chm */
	HANDLE_GLUT_Close
};

/* Callback for glutDisplayFunc */
begin_decl_gwh(Display, (void), 0)
end_decl_gwh()

/* Callback for glutOverlayDisplayFunc */
begin_decl_gwh(OverlayDisplay, (void), 0)
end_decl_gwh()

/* Callback for glutReshapeFunc */
begin_decl_gwh(Reshape, (int width, int height), 2)
	GLUT_PUSH_NEW_IV(width);
	GLUT_PUSH_NEW_IV(height);
end_decl_gwh()

/* Callback for glutKeyboardFunc */
begin_decl_gwh(Keyboard, (unsigned char key, int width, int height), 3)
	GLUT_PUSH_NEW_U8(key);
	GLUT_PUSH_NEW_IV(width);
	GLUT_PUSH_NEW_IV(height);
end_decl_gwh()

/* Callback for glutKeyboardUpFunc */
begin_decl_gwh(KeyboardUp, (unsigned char key, int width, int height), 3)
	GLUT_PUSH_NEW_U8(key);
	GLUT_PUSH_NEW_IV(width);
	GLUT_PUSH_NEW_IV(height);
end_decl_gwh()

/* Callback for glutMouseFunc */
begin_decl_gwh(Mouse, (int button, int state, int x, int y), 4)
	GLUT_PUSH_NEW_IV(button);
	GLUT_PUSH_NEW_IV(state);
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutMouseWheelFunc */	/* Open/FreeGLUT -chm */
begin_decl_gwh(MouseWheel, (int wheel, int direction, int x, int y), 4)
	GLUT_PUSH_NEW_IV(wheel);
	GLUT_PUSH_NEW_IV(direction);
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutPassiveMotionFunc */
begin_decl_gwh(PassiveMotion, (int x, int y), 2)
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutMotionFunc */
begin_decl_gwh(Motion, (int x, int y), 2)
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutVisibilityFunc */
begin_decl_gwh(Visibility, (int state), 1)
	GLUT_PUSH_NEW_IV(state);
end_decl_gwh()

/* Callback for glutWindowStatusFunc */
begin_decl_gwh(WindowStatus, (int state), 1)
	GLUT_PUSH_NEW_IV(state);
end_decl_gwh()

/* Callback for glutEntryFunc */
begin_decl_gwh(Entry, (int state), 1)
	GLUT_PUSH_NEW_IV(state);
end_decl_gwh()

/* Callback for glutSpecialFunc */
begin_decl_gwh(Special, (int key, int width, int height), 3)
	GLUT_PUSH_NEW_IV(key);
	GLUT_PUSH_NEW_IV(width);
	GLUT_PUSH_NEW_IV(height);
end_decl_gwh()

/* Callback for glutSpecialUpFunc */
begin_decl_gwh(SpecialUp, (int key, int width, int height), 3)
	GLUT_PUSH_NEW_IV(key);
	GLUT_PUSH_NEW_IV(width);
	GLUT_PUSH_NEW_IV(height);
end_decl_gwh()

/* Callback for glutJoystickFunc */	/* Open/FreeGLUT -chm */
begin_decl_gwh(Joystick, (unsigned int buttons, int xaxis, int yaxis, int zaxis), 4)
	GLUT_PUSH_NEW_IV(buttons);
	GLUT_PUSH_NEW_IV(xaxis);
	GLUT_PUSH_NEW_IV(yaxis);
	GLUT_PUSH_NEW_IV(zaxis);
end_decl_gwh()


/* Callback for glutSpaceballMotionFunc */
begin_decl_gwh(SpaceballMotion, (int x, int y, int z), 3)
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
	GLUT_PUSH_NEW_IV(z);
end_decl_gwh()

/* Callback for glutSpaceballRotateFunc */
begin_decl_gwh(SpaceballRotate, (int x, int y, int z), 3)
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
	GLUT_PUSH_NEW_IV(z);
end_decl_gwh()

/* Callback for glutSpaceballButtonFunc */
begin_decl_gwh(SpaceballButton, (int button, int state), 2)
	GLUT_PUSH_NEW_IV(button);
	GLUT_PUSH_NEW_IV(state);
end_decl_gwh()

/* Callback for glutButtonBoxFunc */
begin_decl_gwh(ButtonBox, (int button, int state), 2)
	GLUT_PUSH_NEW_IV(button);
	GLUT_PUSH_NEW_IV(state);
end_decl_gwh()

/* Callback for glutDialsFunc */
begin_decl_gwh(Dials, (int dial, int value), 2)
	GLUT_PUSH_NEW_IV(dial);
	GLUT_PUSH_NEW_IV(value);
end_decl_gwh()

/* Callback for glutTabletMotionFunc */
begin_decl_gwh(TabletMotion, (int x, int y), 2)
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutTabletButtonFunc */
begin_decl_gwh(TabletButton, (int button, int state, int x, int y), 4)
	GLUT_PUSH_NEW_IV(button);
	GLUT_PUSH_NEW_IV(state);
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_gwh()

/* Callback for glutIdleFunc */
begin_decl_ggh(Idle, (void), 0)
end_decl_ggh()

/* Callback for glutMenuStatusFunc */
begin_decl_ggh(MenuStatus, (int status, int x, int y), 3)
	GLUT_PUSH_NEW_IV(status);
	GLUT_PUSH_NEW_IV(x);
	GLUT_PUSH_NEW_IV(y);
end_decl_ggh()

/* Callback for glutMenuStateFunc */
begin_decl_ggh(MenuState, (int status), 1)
	GLUT_PUSH_NEW_IV(status);
end_decl_ggh()

/* Callback for glutMenuDestroyFunc */		/* Open/FreeGLUT -chm */
begin_decl_gwh(MenuDestroy, (void), 0)
end_decl_gwh()

/* Callback for glutCloseFunc */
static void generic_glut_Close_handler(void)
{
	int win = glutGetWindow();
	AV * handler_data = (AV*)get_glut_win_handler(win, HANDLE_GLUT_Close);
	SV * handler = *av_fetch(handler_data, 0, 0);
	dSP;

	GLUT_PUSHMARK(sp);
	GLUT_EXTEND_STACK(sp,1);
	GLUT_PUSH_NEW_IV(win);

	PUTBACK;
	DO_perl_call_sv(handler, G_DISCARD);
}

/* Callback for glutTimerFunc */
static void generic_glut_timer_handler(int value)
{
	AV * handler_data = (AV*)value;
	SV * handler;
	int i;
	dSP;

	handler = *av_fetch(handler_data, 0, 0);

	GLUT_PUSHMARK(sp);
	GLUT_EXTEND_STACK(sp,av_len(handler_data));
	for (i=1;i<=av_len(handler_data);i++)
		GLUT_PUSH_NEW_SV(*av_fetch(handler_data, i, 0));

	PUTBACK;
	DO_perl_call_sv(handler, G_DISCARD);
	
	SvREFCNT_dec(handler_data);
}

static AV * glut_menu_handlers = 0;

/* Callback for glutMenuFunc */
static void generic_glut_menu_handler(int value)
{
	AV * handler_data;
	SV * handler;
	SV ** h;
	int i;
	dSP;
	
	h = av_fetch(glut_menu_handlers, glutGetMenu(), FALSE);
	if (!h || !SvOK(*h) || !SvROK(*h))
		croak("Unable to locate menu handler");
	
	handler_data = (AV*)SvRV(*h);

	handler = *av_fetch(handler_data, 0, 0);

	GLUT_PUSHMARK(sp);
	GLUT_EXTEND_STACK(sp,av_len(handler_data) + 1);
	for (i=1;i<=av_len(handler_data);i++)
		GLUT_PUSH_NEW_SV(*av_fetch(handler_data, i, 0));

	GLUT_PUSH_NEW_IV(value);

	PUTBACK;
	DO_perl_call_sv(handler, G_DISCARD);
}


#endif /* def GLUT_API_VERSION */

#endif /* End IN_POGL_GLUT_XS */


#if 0
typedef void * ptr;
#endif  /* Does not seem to be used.  Uncomment if breaks. chm 29-May-2009 */


#if 0
/* Get a Perl parameter, cast to C type */
#define SvItems(type,offset,count,dst)					\
{									\
	GLuint i;							\
	switch (type)							\
	{								\
		case GL_UNSIGNED_BYTE:					\
		case GL_BITMAP:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLubyte*)(dst))[i] = (GLubyte)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_BYTE:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLbyte*)(dst))[i] = (GLbyte)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_UNSIGNED_SHORT:					\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLushort*)(dst))[i] = (GLushort)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_SHORT:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLshort*)(dst))[i] = (GLshort)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_UNSIGNED_INT:					\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLuint*)(dst))[i] = (GLuint)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_INT:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLint*)(dst))[i] = (GLint)SvIV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_FLOAT:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLfloat*)(dst))[i] = (GLfloat)SvNV(ST(i+(offset)));	\
			}						\
			break;						\
		case GL_DOUBLE:						\
			for (i=0;i<(count);i++)				\
			{						\
			  ((GLdouble*)(dst))[i] = (GLdouble)SvNV(ST(i+(offset)));	\
			}						\
			break;						\
		default:						\
			croak("unknown type");				\
	}								\
}
#endif /* Moved SvItems to gl_util.h */











MODULE = PDL::Graphics::OpenGL::Perl::OpenGL::GLUT		PACKAGE = PDL::Graphics::OpenGL::Perl::OpenGL




#ifdef IN_POGL_GLUT_XS

#// Test for done with glutInit
int
done_glutInit()
	CODE:
	RETVAL = _done_glutInit;
	OUTPUT:
	RETVAL

#endif /* End IN_POGL_GLUT_XS */


##################### GLU #########################


############################## GLUT #########################

#ifdef IN_POGL_GLUT_XS

#ifdef GLUT_API_VERSION

# GLUT

#//# glutInit();
void
glutInit()
	CODE:
	{
	int argc;
	char ** argv;
	AV * ARGV;
	SV * ARGV0;
	SV * sv;
	int i;

			if (_done_glutInit)
				croak("illegal glutInit() reinitialization attempt");

			argv  = 0;
			ARGV = perl_get_av("ARGV", FALSE);
			ARGV0 = perl_get_sv("0", FALSE);
			
			argc = av_len(ARGV)+2;
			if (argc) {
				argv = malloc(sizeof(char*)*argc);
				argv[0] = SvPV(ARGV0, PL_na);
				for(i=0;i<=av_len(ARGV);i++)
					argv[i+1] = SvPV(*av_fetch(ARGV, i, 0), PL_na);
			}
			
			i = argc;
			glutInit(&argc, argv);

			_done_glutInit = 1;

			while(argc<i--)
				sv = av_shift(ARGV);
			
			if (argv)
				free(argv);
	}

#//# glutInitWindowSize($width, $height);
void
glutInitWindowSize(width, height)
	int	width
	int	height

#//# glutInitWindowPosition($x, $y);
void
glutInitWindowPosition(x, y)
	int	x
	int	y

#//# glutInitDisplayMode($mode);
void
glutInitDisplayMode(mode)
	int	mode

#//# glutInitDisplayString($string);
void
glutInitDisplayString(string)
	char *	string

#//# glutMainLoop();
void
glutMainLoop()

#//# glutCreateWindow($name);
int
glutCreateWindow(name)
	char *	name
	CODE:
	RETVAL = glutCreateWindow(name);
	destroy_glut_win_handlers(RETVAL);
	OUTPUT:
	RETVAL

#//# glutCreateSubWindow($win, $x, $y, $width, $height);
int
glutCreateSubWindow(win, x, y, width, height)
	int	win
	int	x
	int	y
	int	width
	int	height
	CODE:
	RETVAL = glutCreateSubWindow(win, x, y, width, height);
	destroy_glut_win_handlers(RETVAL);
	OUTPUT:
	RETVAL

#//# glutSetWindow($win);
void
glutSetWindow(win)
	int	win

#//# glutGetWindow();
int
glutGetWindow()

#//# glutDestroyWindow($win);
void
glutDestroyWindow(win)
	int	win
	CODE:
	glutDestroyWindow(win);
	destroy_glut_win_handlers(win);

#//# glutPostRedisplay();
void
glutPostRedisplay()

#//# glutSwapBuffers();
void
glutSwapBuffers()

#//# glutPositionWindow($x, $y);
void
glutPositionWindow(x, y)
	int	x
	int	y

#//# glutReshapeWindow($width, $height);
void
glutReshapeWindow(width, height)
	int	width
	int	height

#if GLUT_API_VERSION >= 3

#//# glutFullScreen();
void
glutFullScreen()

#endif

#//# glutPopWindow();
void
glutPopWindow()

#//# glutPushWindow();
void
glutPushWindow()

#//# glutShowWindow();
void
glutShowWindow()

#//# glutHideWindow();
void
glutHideWindow()

#//# glutIconifyWindow();
void
glutIconifyWindow()

#//# glutSetWindowTitle($title);
void
glutSetWindowTitle(title)
	char *	title

#//# glutSetIconTitle($title);
void
glutSetIconTitle(title)
	char *	title

#if GLUT_API_VERSION >= 3

#//# glutSetCursor(cursor);
void
glutSetCursor(cursor)
	int	cursor

#endif

# Overlays


#if GLUT_API_VERSION >= 3

#//# glutEstablishOverlay(); 
void
glutEstablishOverlay()

#//# glutUseLayer(layer);
void
glutUseLayer(layer)
	GLenum	layer

#//# glutRemoveOverlay();
void
glutRemoveOverlay()

#//# glutPostOverlayRedisplay();
void
glutPostOverlayRedisplay()

#//# glutShowOverlay();
void
glutShowOverlay()

#//# glutHideOverlay();
void
glutHideOverlay()

#endif

# Menus

#//# $ID = glutCreateMenu(\&callback);
int
glutCreateMenu(handler=0, ...)
	SV *	handler
	CODE:
	{
		if (!handler || !SvOK(handler)) {
			croak("A handler must be specified");
		} else {
			AV * handler_data = newAV();
		
			PackCallbackST(handler_data, 0);

			RETVAL = glutCreateMenu(generic_glut_menu_handler);
			
			if (!glut_menu_handlers)
				glut_menu_handlers = newAV();
			
			av_store(glut_menu_handlers, RETVAL, newRV_inc((SV*)handler_data));
			
			SvREFCNT_dec(handler_data);
			
		}
	}
	OUTPUT:
	RETVAL

#//# glutSetMenu($menu);
void
glutSetMenu(menu)
	int	menu

#//# glutGetMenu();
int
glutGetMenu()

#//# glutDestroyMenu($menu);
void
glutDestroyMenu(menu)
	int	menu
	CODE:
	{
		glutDestroyMenu(menu);
		av_store(glut_menu_handlers, menu, newSVsv(&PL_sv_undef));
	}

#//# glutAddMenuEntry($name, $value);
void
glutAddMenuEntry(name, value)
	char *	name
	int	value

#//# glutAddSubMenu($name, $menu);
void
glutAddSubMenu(name, menu)
	char *	name
	int	menu

#//# glutChangeToMenuEntry($entry, $name, $value);
void
glutChangeToMenuEntry(entry, name, value)
	int	entry
	char *	name
	int	value

#//# glutChangeToSubMenu($entry, $name, $menu);
void
glutChangeToSubMenu(entry, name, menu)
	int	entry
	char *	name
	int	menu

#//# glutRemoveMenuItem($entry);
void
glutRemoveMenuItem(entry)
	int	entry

#//# glutAttachMenu(button);
void
glutAttachMenu(button)
	int	button

#//# glutDetachMenu(button);
void
glutDetachMenu(button)
	int	button

# Callbacks

#//# glutDisplayFunc(\&callback);
void
glutDisplayFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs_nullfail(Display, ("Display function must be specified"))

#if GLUT_API_VERSION >= 3

#//# glutOverlayDisplayFunc(\&callback);
void
glutOverlayDisplayFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(OverlayDisplay)

#endif

#//# glutReshapeFunc(\&callback);
void
glutReshapeFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Reshape)

#//# glutKeyboardFunc(\&callback);
void
glutKeyboardFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Keyboard)

#if GLUT_API_VERSION >= 4

#//# glutKeyboardUpFunc(\&callback);
void
glutKeyboardUpFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(KeyboardUp)

#//# glutWindowStatusFunc(\&callback);
void
glutWindowStatusFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(WindowStatus)

#endif

#//# glutMouseFunc(\&callback);
void
glutMouseFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Mouse)

#//# glutMouseWheelFunc(\&callback);
void
glutMouseWheelFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(MouseWheel)

#//# glutMotionFunc(\&callback);
void
glutMotionFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Motion)

#//# glutPassiveMotionFunc(\&callback);
void
glutPassiveMotionFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(PassiveMotion)

#//# glutVisibilityFunc(\&callback);
void
glutVisibilityFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Visibility)

# OS/2 PM implementation calls itself v2, but does not support these functions
# It is very hard to test for this, so we check for some other omission...

#if !defined(GL_SRC_ALPHA_SATURATE) || defined(GL_CONSTANT_COLOR)

#//# glutEntryFunc(\&callback);
void
glutEntryFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Entry)

#endif

#if GLUT_API_VERSION >= 2

#//# glutSpecialFunc(\&callback);
void
glutSpecialFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Special)

# OS/2 PM implementation calls itself v2, but does not support these functions
# It is very hard to test for this, so we check for some other omission...

#  if !defined(GL_SRC_ALPHA_SATURATE) || defined(GL_CONSTANT_COLOR)

#//# glutJoystickFunc(\&callback);	/* Open/FreeGLUT -chm */
# void					/* Not implemented, don't know how */
# glutJoystickFunc(handler=0, ...)
# 	SV *	handler
# 	CODE:
# 	decl_gwh_xs(Joystick)

#//# glutSpaceballMotionFunc(\&callback);
void
glutSpaceballMotionFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(SpaceballMotion)

#//# glutSpaceballRotateFunc(\&callback);
void
glutSpaceballRotateFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(SpaceballRotate)

#//# glutSpaceballButtonFunc(\&callback);
void
glutSpaceballButtonFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(SpaceballButton)

#//# glutButtonBoxFunc(\&callback);
void
glutButtonBoxFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(ButtonBox)

#//# glutDialsFunc(\&callback);
void
glutDialsFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(Dials)

#//# glutTabletMotionFunc(\&callback);
void
glutTabletMotionFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(TabletMotion)

#//# glutTabletButtonFunc(\&callback);
void
glutTabletButtonFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(TabletButton)

#  endif

#endif

#if GLUT_API_VERSION >= 3

#//# glutMenuStatusFunc(\&callback);
void
glutMenuStatusFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_ggh_xs(MenuStatus)

#endif

#//# glutMenuStateFunc(\&callback);
void
glutMenuStateFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_ggh_xs(MenuState)

#//# glutIdleFunc(\&callback);
void
glutIdleFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_ggh_xs(Idle)

#//# glutTimerFunc($msecs, \&callback);
void
glutTimerFunc(msecs, handler=0, ...)
	unsigned int	msecs
	SV *	handler
	CODE:
	{
		if (!handler || !SvOK(handler)) {
			croak("A handler must be specified");
		} else {
			AV * handler_data = newAV();
		
			PackCallbackST(handler_data, 1);
			
			glutTimerFunc(msecs, generic_glut_timer_handler, (int)handler_data);
		}
	ENSURE_callback_thread;}


# Colors

#//# glutSetColor($cell, $red, $green, $blue)
void
glutSetColor(cell, red, green, blue)
	int	cell
	GLfloat	red
	GLfloat	green
	GLfloat	blue

#//# glutGetColor($cell, $component);
GLfloat
glutGetColor(cell, component)
	int	cell
	int	component

#//# glutCopyColormap($win);
void
glutCopyColormap(win)
	int	win

# State

#//# glutGet($state);
int
glutGet(state)
	GLenum	state

#if GLUT_API_VERSION >= 3

#//# glutLayerGet(info);
int
glutLayerGet(info)
	GLenum	info

#endif

int
glutDeviceGet(info)
	GLenum	info

#if GLUT_API_VERSION >= 3

#//# glutGetModifiers();
int
glutGetModifiers()

#endif

#if GLUT_API_VERSION >= 2

#//# glutExtensionSupported($extension);
int
glutExtensionSupported(extension)
	char *	extension

#endif

# Font

#//# glutBitmapCharacter($font, $character);
void
glutBitmapCharacter(font, character)
	void *	font
	int	character

#//# glutStrokeCharacter($font, $character);
void
glutStrokeCharacter(font, character)
	void *	font
	int	character

# OS/2 PM implementation calls itself v2, but does not support these functions
# It is very hard to test for this, so we check for some other omission...

#if GLUT_API_VERSION >= 2 && (!defined(GL_SRC_ALPHA_SATURATE) || defined(GL_CONSTANT_COLOR))

#//# glutBitmapWidth($font, $character);
int
glutBitmapWidth(font, character)
	void *	font
	int	character

#//# glutStrokeWidth($font, $character);
int
glutStrokeWidth(font, character)
	void *	font
	int	character

#endif


#if GLUT_API_VERSION >= 3

#//# glutIgnoreKeyRepeat($ignore);
void
glutIgnoreKeyRepeat(ignore)
	int	ignore

#//# glutSetKeyRepeat($repeatMode);
void
glutSetKeyRepeat(repeatMode)
	int	repeatMode

#//# glutForceJoystickFunc();
void
glutForceJoystickFunc()

#endif


# Solids

#//# glutSolidSphere($radius, $slices, $stacks);
void
glutSolidSphere(radius, slices, stacks)
	GLdouble	radius
	GLint	slices
	GLint	stacks

#//# glutWireSphere($radius, $slices, $stacks);
void
glutWireSphere(radius, slices, stacks)
	GLdouble	radius
	GLint	slices
	GLint	stacks

#//# glutSolidCube($size);
void
glutSolidCube(size)
	GLdouble	size

#//# glutWireCube($size);
void
glutWireCube(size)
	GLdouble	size

#//# glutSolidCone($base, $height, $slices, $stacks);
void
glutSolidCone(base, height, slices, stacks)
	GLdouble	base
	GLdouble	height
	GLint	slices
	GLint	stacks

#//# glutWireCone($base, $height, $slices, $stacks);
void
glutWireCone(base, height, slices, stacks)
	GLdouble	base
	GLdouble	height
	GLint	slices
	GLint	stacks

#//# glutSolidTorus($innerRadius, $outerRadius, $nsides, $rings);
void
glutSolidTorus(innerRadius, outerRadius, nsides, rings)
	GLdouble	innerRadius
	GLdouble	outerRadius
	GLint	nsides
	GLint	rings

#//# glutWireTorus($innerRadius, $outerRadius, $nsides, $rings);
void
glutWireTorus(innerRadius, outerRadius, nsides, rings)
	GLdouble	innerRadius
	GLdouble	outerRadius
	GLint	nsides
	GLint	rings

#//# glutSolidDodecahedron();
void
glutSolidDodecahedron()

#//# glutWireDodecahedron();
void
glutWireDodecahedron()

#//# glutSolidOctahedron();
void
glutSolidOctahedron()

#//# glutWireOctahedron();
void
glutWireOctahedron()

#//# glutSolidTetrahedron();
void
glutSolidTetrahedron()

#//# glutWireTetrahedron();
void
glutWireTetrahedron()

#//# glutSolidIcosahedron();
void
glutSolidIcosahedron()

#//# glutWireIcosahedron();
void
glutWireIcosahedron()

#//# glutSolidTeapot(size);
void
glutSolidTeapot(size)
	GLdouble	size

#//# glutWireTeapot($size);
void
glutWireTeapot(size)
	GLdouble	size

#if GLUT_API_VERSION >= 4

#//# glutSpecialUpFunc(\&callback);
void
glutSpecialUpFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(SpecialUp)

#//# glutGameModeString($string);
GLboolean
glutGameModeString(string)
	char *	string
	CODE:
	{
		char mode[1024];
		if (!string || !string[0])
		{
			int w = glutGet(0x00C8);	// GLUT_SCREEN_WIDTH
			int h = glutGet(0x00C9);	// GLUT_SCREEN_HEIGHT

			sprintf(mode,"%dx%d:%d@%d",w,h,32,60);
			string = mode;
		}

		glutGameModeString(string);
		RETVAL = glutGameModeGet(0x0001);	// GLUT_GAME_MODE_POSSIBLE
	}
	OUTPUT:
		RETVAL

#//# glutEnterGameMode();
int
glutEnterGameMode()

#//# glutLeaveGameMode();
void
glutLeaveGameMode()

#//# glutGameModeGet($mode);
int
glutGameModeGet(mode)
	GLenum	mode

##//## CHM implementation of missing FreeGLUT/OpenGLUT features

#//# int  glutBitmapHeight (void *font)
int
glutBitmapHeight(font)
	void * font

#//# int  glutBitmapLength (void *font, const unsigned char *string)
int
glutBitmapLength(font, string)
	void * font
	const unsigned char * string

#//# void  glutBitmapString (void *font, const unsigned char *string)
void
glutBitmapString(font, string)
	void * font
	const unsigned char * string

#//# void *  glutGetMenuData (void)
# void *
# glutGetMenuData()

#//# void *  glutGetProcAddress (const char *procName)
# void *
# glutGetProcAddress(procName)
# 	const char * procName

#//# void *  glutGetWindowData (void)
# void *
# glutGetWindowData()

#//# void  glutMainLoopEvent (void)
void
glutMainLoopEvent()

#//# void  glutPostWindowOverlayRedisplay (int windowID)
void
glutPostWindowOverlayRedisplay(windowID)
	int windowID

#//# void  glutPostWindowRedisplay (int windowID)
void
glutPostWindowRedisplay(windowID)
	int windowID

#//# void  glutReportErrors (void)
void
glutReportErrors()

#//# void  glutSetMenuData (void *data)
# void
# glutSetMenuData(data)
# 	void * data

#//# void  glutSetWindowData (void *data)
# void
# glutSetWindowData(data)
# 	void * data

#//# void  glutSolidCylinder (GLdouble radius, GLdouble height, GLint slices, GLint stacks)
void
glutSolidCylinder(radius, height, slices, stacks)
	GLdouble radius
	GLdouble height
	GLint slices
	GLint stacks

#//# void  glutSolidRhombicDodecahedron (void)
void
glutSolidRhombicDodecahedron()

#//# void  glutSolidSierpinskiSponge (int num_levels, const GLdouble offset[3], GLdouble scale)
# void
# glutSolidSierpinskiSponge(num_levels, offset, scale)
# 	int num_levels
# 	const GLdouble offset[3]
# 	GLdouble scale

#//# float  glutStrokeHeight (void *font)
GLfloat
glutStrokeHeight(font)
	void * font

#//# float  glutStrokeLength (void *font, const unsigned char *string)
GLfloat
glutStrokeLength(font, string)
	void * font
	const unsigned char * string

#//# void  glutStrokeString (void *fontID, const unsigned char *string)
void
glutStrokeString(font, string)
	void * font
	const unsigned char * string

#//# void  glutWarpPointer (int x, int y)
void
glutWarpPointer(x, y)
	int x
	int y

#//# void  glutWireCylinder (GLdouble radius, GLdouble height, GLint slices, GLint stacks)
void
glutWireCylinder(radius, height, slices, stacks)
	GLdouble radius
	GLdouble height
	GLint slices
	GLint stacks

#//# void  glutWireRhombicDodecahedron (void)
void
glutWireRhombicDodecahedron()

#//# void  glutWireSierpinskiSponge (int num_levels, const GLdouble offset[3], GLdouble scale)
# void
# glutWireSierpinskiSponge(num_levels, offset, scale)
# 	int num_levels
# 	const GLdouble offset[3]
# 	GLdouble scale

#endif

# /* FreeGLUT APIs */

#//# glutSetOption($option_flag, $value);
void
glutSetOption(option_flag, value)
	GLenum		option_flag
	int		value
	CODE:
	{
#if defined HAVE_FREEGLUT
		glutSetOption(option_flag, value);
#endif
	}

#//# glutLeaveMainLoop();
void
glutLeaveMainLoop()
	CODE:
	{
#if defined HAVE_FREEGLUT
		glutLeaveMainLoop();
#else
		int win = glutGetWindow();
		glutDestroyWindow(win);
		destroy_glut_win_handlers(win);
#endif
	}

#//# glutMenuDestroyFunc(\&callback);
void
glutMenuDestroyFunc(handler=0, ...)
	SV *	handler
	CODE:
	decl_gwh_xs(MenuDestroy)


#//# glutCloseFunc(\&callback);
void
glutCloseFunc(handler=0, ...)
	SV *	handler
	CODE:
        {
#if defined HAVE_FREEGLUT
		decl_gwh_xs(Close)
#endif
        }

#endif /* def GLUT_API_VERSION */

#endif /* End IN_POGL_GLUT_XS */

# /* This is assigned to GLX for now.  The glp*() functions should be split out */

