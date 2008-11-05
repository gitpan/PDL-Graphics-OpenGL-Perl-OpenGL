
# This is the Perl OpenGL build configuration file.
# It contains the final OpenGL build arguements from
# the configuration process.  Access the values by
# use OpenGL::Config which defines the variable
#  containing the hash arguments from
# the WriteMakefile() call.
#
$PDL::Graphics::OpenGL::Perl::OpenGL::Config = {
                                                 'NAME' => 'PDL::Graphics::OpenGL::Perl::OpenGL',
                                                 'LIBS' => '-L/usr/lib -L/usr/X11R6/lib -L/usr/local/lib -L/usr/openwin/lib -L/usr/lib/xorg/modules -L/usr/X11R6/lib/modules -L/usr/lib/xorg/modules/extensions -L/usr/X11R6/lib/modules/extensions  -lGLUT -lGL -lOSMesa -lGLUT -lglitz-glx -lglu -lXext -lXmu -lXi -lICE -lX11 -lm',
                                                 'INC' => '-I/usr/include -I/usr/X11R6/include -I/usr/local/include -I/usr/openwin/include',
                                                 'AUTHOR' => 'Bob \'grafman\' Free <grafman at graphcomp.com>',
                                                 'DEFINE' => '-DHAVE_VER -DHAVE_FREEGLUT -DHAVE_GL -DHAVE_GLU -DHAVE_GLUT -DHAVE_GLX -DHAVE_MESA -DHAVE_GLX -DGL_GLEXT_LEGACY',
                                                 'dynamic_lib' => {},
                                                 'OBJECT' => '$(BASEEXT)$(OBJ_EXT) gl_util$(OBJ_EXT)',
                                                 'clean' => {
                                                              'FILES' => 'utils/glversion.txt utils/glversion.exe utils/glversion.o'
                                                            },
                                                 'LDFROM' => '$(OBJECT) ',
                                                 'OPTIMIZE' => undef,
                                                 'PM' => {
                                                           'OpenGL.pm' => '$(INST_LIBDIR)/OpenGL.pm',
                                                           'Config.pm' => '$(INST_LIBDIR)/OpenGL/Config.pm',
                                                           'OpenGL.pod' => '$(INST_LIBDIR)/OpenGL.pod'
                                                         },
                                                 'EXE_FILES' => [],
                                                 'VERSION_FROM' => 'OpenGL.pm',
                                                 'XSPROTOARG' => '-noprototypes'
                                               };

1;
__END__
