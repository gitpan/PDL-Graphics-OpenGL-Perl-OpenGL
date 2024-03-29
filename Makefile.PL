use ExtUtils::MakeMaker;
use ExtUtils::Liblist;
use Data::Dumper;
use Config;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

# ExtUtils::Liblist is broken
@findlib::ISA = qw(ExtUtils::Liblist);
sub findlib::lsdir { shift; grep /$_[0]/, <$_[1]>}
sub findlib::file_name_is_absolute { 1 } # Used for warnings only...

 
# Supported windowing interfaces
our $is_valid_interface =
{
  'FREEGLUT'	=> 'FreeGLUT, preferred over GLUT',
  'GLUT'	=> 'GLUT; this really FreeGLUT on Linux',
  'GLX'		=> 'X11; requires a running XServer',
  'AGL'		=> 'GLUT framework on Mac OS X',
  'W32API'	=> 'Uses FreeGLUT on CYGWIN, instead of GLX/X11'
};


# Makefile.PL Usage
sub Usage
{
  print "\n@_\n\n";

  print qq
  {
    USAGE: perl Makefile.PL [OPTIONS]


    OPTIONS include:

    help                This help message

    verbose             Display additional status info

    dist=NO_EXCLUSIONS  Build with no OpenGL Extension exclusions
    dist=EXCLUSIONS     Override NO_EXCLUSIONS default for Win32

    interface=XFACE     Build for a specific windowing interface
                        Currently supports:
  };

  print "\n";
  foreach $xface (sort keys %$is_valid_interface)
  {
    print substr("      $xface                  ",0,24).
      "$is_valid_interface->{$xface}\n";
  }
  print "\n";
  exit(0);
}
Usage() if ($ARGV[0] =~ m|^([-/]*)?h(elp)?|i);


# Detect CYGWIN - some versions don't report $^O correctly
open(SAVEERR, ">&STDERR");
close(STDERR);
my $uname = `uname`;
open(STDERR, ">&SAVEERR");
our $IS_CYGWIN = ($uname =~ m|^CYGWIN|);
our $IS_W32API = ($IS_CYGWIN && grep { m/^interface=W32API/i } @ARGV );


# Detect MINGW
our $IS_MINGW = 0;
if ($^O eq 'MSWin32' && !$IS_CYGWIN)
{
#  open(SAVEERR, ">&STDERR");
#  close(STDERR);
#  $IS_MINGW = `gcc -dumpversion`;
#  open(STDERR, ">&SAVEERR");

  $IS_MINGW = (($Config{make} eq 'dmake') && ($Config{cc} eq 'gcc'))
}


# Get debugging flags
our $verbose = 1;
if ( grep { m/^verbose/i } @ARGV )
{
  $verbose = 1;
  # Strip out interface args
  @ARGV = grep { !m/^verbose=/i } @ARGV;
}


# Get distribution build flags
our $dist_flags = {};
if ( grep { m/^dist=/i } @ARGV )
{
  foreach my $arg (@ARGV)
  {
    $dist_flags->{uc($1)}++ if ($arg =~ m/^dist=(\w+)/i);
  }

  # Setting both EXCLUSIONS and NO_EXCLUSIONS cancels each other out
  if ($dist_flags->{NO_EXCLUSIONS} && $dist_flags->{EXCLUSIONS})
  {
    delete($dist_flags->{NO_EXCLUSIONS});
    delete($dist_flags->{EXCLUSIONS});
  }

  # Strip out interface args
  @ARGV = grep { !m/^dist=/i } @ARGV;
}
# Default to NO_EXCLUSIONS on Windows
if ($^O eq 'MSWin32' || $IS_W32API)
{
  $dist_flags->{NO_EXCLUSIONS} = $dist_flags->{EXCLUSIONS} ? 0 : 1;
}


# Look for available libs
our @libdirs = qw
{
  -L/usr/lib
  -L/usr/X11R6/lib
  -L/usr/local/lib
  -L/usr/openwin/lib
  -L/usr/lib/xorg/modules
  -L/usr/X11R6/lib/modules
  -L/usr/lib/xorg/modules/extensions
  -L/usr/X11R6/lib/modules/extensions
};

our @check_libs = qw
{
  -lGL
  -lopengl
  -lMesaGL
  -lGLU
  -lglu
  -lMesaGLU
  -lfreeglut
  -lGLUT
  -lglut
  -lMesaGLUT
  -lOSMesa
  -lGLX
  -lglx
  -lMesaGLX
};

our $found_libs = get_libs(@libdirs,@check_libs);
die "No OpenGL libs found\n" if (!scalar($found_libs));

if ($verbose)
{
  print "found libs:\n";
  foreach my $key (sort keys %$found_libs)
  {
    print "    $key = '$found_libs->{$key}'\n";
  }
}

# Check for OpenGL installation
our $DIST_DEFS = get_extensions($found_libs,$dist_flags->{NO_EXCLUSIONS});

# Don't build Makefile if we cannot compile+run glversion
exit(0) unless length($DIST_DEFS);

# Get user-specified interface
my $interface_lib;
if ( grep { m/^interface=/i } @ARGV )
{
  my @my_argv = @ARGV;    # safe copy
  my @interface_opts = ();
  my $fallback = 0;

  foreach my $arg (@my_argv)
  {
    if ($arg =~ m/^interface=(\w+)/i)
    {
      my $interface = uc($1);
      my $valid_type = $is_valid_interface->{$interface};
      if (!$valid_type)
      {
        Usage("Invalid interface: '$interface'");
        next;
      }

      # test if requested interfaces supported
      # !!! Should use lookup table
      if ($interface eq 'W32API')
      {
        if (!$found_libs->{FREEGLUT32} && !$found_libs->{GLUT32})
        {
          print "W32API interface requires GLUT or FreeGLUT\n";
          next;
        }
        if (!$found_libs->{OPENGL32})
        {
          print "W32API interface requires OpenGL32.dll\n";
          next;
        }
        if (!$found_libs->{GLU32})
        {
          print "W32API interface requires GLU32.dll\n";
          next;
        }
      }
      elsif ($interface eq 'AGL')
      {
        if ($^O ne 'darwin' || !$found_libs->{GLUT})
        {
          "AGL interface requires GLUT.framework\n";
          next;
        }
      }
      elsif ($interface =~ m|GLUT|)
      {
        if ($interface eq 'FREEGLUT')
        {
          if (!$found_libs->{FREEGLUT} && !$found_libs->{FREEGLUT32})
          {
            print "FREEGLUT interface requires FreeGLUT\n";

            if ($found_libs->{GLUT})
            {
              print "Falling back to the GLUT interface\n";
              $interface = 'GLUT';
              $fallback++;
            }
            else
            {
              print "Try installing FREEGLUT first\n";
              next;
            }
          }
        }

        if ($interface eq 'GLUT')
        {
          if (!$found_libs->{GLUT} && $found_libs->{FREEGLUT})
          {
            $found_libs->{GLUT} = $found_libs->{FREEGLUT};
          }

          if (!$found_libs->{GLUT32} && $found_libs->{FREEGLUT32})
          {
            $found_libs->{GLUT32} = $found_libs->{FREEGLUT32};
          }

          if ($found_libs->{GLUT})
          {
            delete($found_libs->{FREEGLUT});
          }

          if ($found_libs->{GLUT32})
          {
            delete($found_libs->{FREEGLUT32});
          }

          if (!$found_libs->{GLUT} && !$found_libs->{GLUT32})
          {
            print "GLUT interface requires GLUT or FreeGLUT\n";
            next;
          }
        }
      }
      elsif ($interface eq 'GLX')
      {
        if (!$found_libs->{GL} && !$found_libs->{MESA} && !$found_libs->{GLX})
        {
          print "GLX interface requires GLX/X11\n";
          next;
        }
      }
      elsif (!$found_libs->{$interface})
      {
        print "$interface interface not supported\n";
        next;
      }

      push(@interface_opts,$interface);
    }
  }

  my $interfaces = scalar(@interface_opts);
  if (!$interfaces)
  {
    die "ERROR: no supported interfaces found.\n";
  }
  elsif ($interfaces > 1)
  {
    die "ERROR: multiple opengl interfaces requested: @interface_opts.\n";
  }

  ($interface_lib) = @interface_opts;
  print "User set interface to $interface_lib\n" if ($verbose && !$fallback);

  # Strip out interface args
  @ARGV = grep { !m/^interface=/i } @ARGV;
}
# Otherwise use available defaults
elsif ($IS_CYGWIN)
{
  if ($found_libs->{FREEGLUT})
  {
    $interface_lib = 'FREEGLUT'; # CYGWIN will use X11 interface by default
  }
  elsif($found_libs->{GLUT})
  {
    $interface_lib = 'GLUT';
  }
  elsif($found_libs->{GLUT32} || $found_libs->{FREEGLUT32})
  {
    $interface_lib = 'W32API';
  }
  else
  {
    die "No suitable interface found for CYGWIN\n";
  }
}
elsif ($^O eq 'darwin' && $found_libs->{GLUT})
{
  $interface_lib = 'AGL';
}
elsif ($found_libs->{FREEGLUT})
{
  $interface_lib = 'FREEGLUT';
}
elsif ($found_libs->{FREEGLUT} || $found_libs->{FREEGLUT32})
{
  $interface_lib = 'FREEGLUT';
}
elsif ($found_libs->{GLUT} || $found_libs->{GLUT32})
{
  $interface_lib = 'GLUT';
}
elsif ($^O eq 'MSWin32')
{
  die "Windows requires FreeGLUT or GLUT\n";
}
else
{
  $interface_lib = 'GLX'; # otherwise default to GLX
}

if ($interface_lib eq 'GLX') {
   warn "GLUT or FreeGLUT not found, cannot build module!\n";
   exit 0;
}

print "\nUsing interface: $interface_lib\n\n";

# Marshall compiler defines
our $DEFS = $DIST_DEFS;
if (($^O eq 'MSWin32') || $IS_W32API || $IS_MINGW)
{
  delete($found_libs->{'GLX'});
  delete($found_libs->{'MESA'});
  $found_libs->{'FREEGLUT'} = $found_libs->{'FREEGLUT32'};
  $found_libs->{'GLUT'} = $found_libs->{'GLUT32'};
  $found_libs->{'GLU'} = $found_libs->{'GLU32'};
  $found_libs->{'GL'} = $found_libs->{'OPENGL32'};
}
elsif($IS_CYGWIN)
{
  delete($found_libs->{'FREEGLUT32'});
  delete($found_libs->{'GLUT32'});
  delete($found_libs->{'GLU32'});
  delete($found_libs->{'OPENGL32'});
}
if (!$found_libs->{'GL'})
{
  if ($found_libs->{'GLX'})
  {
    $found_libs->{'GL'} = $found_libs->{'GLX'};
  }
  elsif ($found_libs->{'MESA'})
  {
    $found_libs->{'GL'} = $found_libs->{'MESA'};
  }
}
print "resulting libs:\n" if ($verbose);
foreach my $key (sort keys %$found_libs)
{
  next if (!$found_libs->{$key});
  $DEFS .= " -DHAVE_$key";
  print "    $key = '$found_libs->{$key}'\n" if ($verbose);
}

# Configure MakeMaker
my($INCS,$LIBS,$OPTS,$CLEAN,$LDFROM);
my $EXES = [];
my $DYNS = {};
if ($IS_W32API || (($^O eq 'MSWin32') && !$IS_CYGWIN))		# Win32
{
  my $glut_lib = '-lopengl32 -lglu32 ';
  if ($interface_lib eq 'GLUT')
  {
    $glut_lib .= '-lglut32';
  }
  else
  {
    $glut_lib .= '-LFreeGLUT -lfreeglut';
  }

  if ($IS_MINGW)	# MINGW
  {
    $LDFROM = $glut_lib;
  }
  elsif ($IS_W32API)	# CYGWIN W32API
  {
     my $glut = ($found_libs->{FREEGLUT32}) ? $found_libs->{FREEGLUT32} : $found_libs->{GLUT32};

    $LIBS = "-L/usr/lib/w32api $glut_lib";
    $LDFROM = $glut_lib;
    $INCS = '-I/usr/include/w32api';
    $DEFS .= " -DHAVE_W32API";
    $DYNS = { OTHERLDFLAGS => '-Wl,--exclude-symbols,'."\x7F".$glut.'_NULL_THUNK_DATA' };
  }
  else			# Windows VC6
  {
    $LIBS = $glut_lib;
    $OPTS = "/ogity /GDs";
  }

  $EXES = ['FreeGLUT/freeglut.dll'];
}
elsif (0 && $IS_W32API)						# CYGWIN W32API
{
  my $glut_lib = ($found_libs->{FREEGLUT32}) ? $found_libs->{FREEGLUT32} :
    $found_libs->{GLUT32};

  $LIBS = "-L/usr/lib/w32api -lopengl32 -lglu32 -LFreeGLUT -l$glut_lib";
  $LDFROM ="-l$glut_lib";
  $INCS = '-I/usr/include/w32api';
  $DEFS .= " -DHAVE_W32API";
  $DYNS = { OTHERLDFLAGS => '-Wl,--exclude-symbols,'."\x7F".$glut_lib.'_NULL_THUNK_DATA' };
}
elsif ($interface_lib eq 'AGL')					# Mac OS X
{
  $INCS = '-Iinclude -I/usr/X11/include';
  $DYNS = { OTHERLDFLAGS => "-framework OpenGL -framework GLUT" };
}
elsif (($^O ne 'cygwin') && ($interface_lib =~ m|GLUT|))	# GLUT/FreeGLUT
{
  delete($found_libs->{GLX});
  $DEFS =~ s|-DHAVE_GLX||;

  my @includes = qw
  {
    -I/usr/include
    -I/usr/local/include
  };
  $INCS = "@includes";

  # Marshall libs
  my $libs = ' -l'.join(' -l',values(%$found_libs));
  $LIBS = "@libdirs $libs";
  $DEFS .= " -DGL_GLEXT_LEGACY";
}
else # Everyone else
{
  my @includes = qw
  {
    -I/usr/include
    -I/usr/X11R6/include
    -I/usr/local/include
    -I/usr/openwin/include
  };
  $INCS = "@includes";


  # Test for obfuscated GLX
  # quite often GLX is in -lGL...  Test for GL/glx.h instead...
  my $out = cfile_text('GL/glx.h');

  # The cpp would not let this macro through. Check for something else
  # that still exists after the cpp pass. a typedef, or type would work
  my $has_glx = ($out =~ m|GLXContext|);

  if ($has_glx)
  {
    #delete($found_libs->{GLX});
    $DEFS .= " -DHAVE_GLX";

    # Handle OS2 - why?
    if ($^O eq 'os2')
    {
       $DEFS .= ' -DOS2_GL_DISABLE_MISSING_EXT -DAPIENTRY= -D__PM__';
    }
  }
  elsif (!$found_libs->{GLX} && $verbose)
  {
    print "GLX not found (neither library, nor headers).";
  }


  # Marshall libs
  my $libs = ' -l'.join(' -l',values(%$found_libs));
  my @more_libs = qw
  {
    -lXext
    -lXmu
    -lXi
    -lICE
    -lX11
    -lm
  };
  #-lXIE
  $LIBS = "@libdirs $libs @more_libs";
  $DEFS .= " -DGL_GLEXT_LEGACY";


  # Handle obfuscated gcc
  my $no_lgcc = (grep /^NO_LGCC$/, @ARGV);
  @ARGV = grep !/^NO_LGCC$/, @ARGV;

  if (!$no_lgcc)
  {
    # This may be a gcc compiler in disguise.
    # Should check for gccversion as well.
    if ($Config{cc} ne 'gcc' && !$Config{gccversion})
    {
      my $gcclibdir;
      my $gccout = `gcc -v 2>&1`;
      if ($gccout =~ /specs from (.*)/)	# gcc present
      {
        ($gcclibdir = $1) =~ s,\bspecs\s*$,,;
        $LIBS .= " -L$gcclibdir -lgcc";

        print STDERR qq
        {
#
### Non-gcc compiler, and gcc is present.
### Adding -lgcc as a dependency: your OpenGL libraries may be gcc-compiled.
### Use NO_LGCC command-line option to disable this.
#
        };
      }
    }
  }
}


# This is the final build configuration
my $build_config =
{
  'NAME'	=> 'PDL::Graphics::OpenGL::Perl::OpenGL',
  'VERSION_FROM'=> 'OpenGL.pm',
  'PM' 		=>
  {
    'OpenGL.pm' => '$(INST_LIBDIR)/OpenGL.pm',
    'OpenGL.pod'=> '$(INST_LIBDIR)/OpenGL.pod',
    'Config.pm' => '$(INST_LIBDIR)/OpenGL/Config.pm'
  },
  'AUTHOR'	=> "Bob 'grafman' Free ".'<grafman at graphcomp.com>',
  'OBJECT' 	=> '$(BASEEXT)$(OBJ_EXT) gl_util$(OBJ_EXT) pogl_const$(OBJ_EXT) pogl_gl$(OBJ_EXT) pogl_glu$(OBJ_EXT) pogl_rpn$(OBJ_EXT) pogl_glut$(OBJ_EXT)',
  'XSPROTOARG'	=> '-noprototypes',
  'DEFINE'	=> $DEFS,
  'INC'		=> $INCS,
  'LIBS' 	=> $LIBS,
  'dynamic_lib'	=> $DYNS,
  'LDFROM'      => '$(OBJECT) '.$LDFROM,
  'EXE_FILES'	=> $EXES,
  'OPTIMIZE'	=> $OPTS,
  'clean'       => 
  {
    FILES =>
      "Config.pm ".
      "utils/glversion.txt ".
      "utils/glversion$Config{exe_ext} ".
      "utils/glversion$Config{obj_ext}"
  }
};

if ($verbose)
{
  print "\nMakeMaker configuration:\n";
}
else
{
  open(SAVEERR, ">&STDERR");
  close(STDERR);
}

close(CONF) if (open(CONF,">Config.pm"));	# Generate place-holder Config.pm
WriteMakefile( %$build_config );       		# Generate the Makefile
WriteConfigPM( $build_config );			# Regenerate final Config.pm

if (!$verbose)
{
  open(STDERR, ">&SAVEERR");
}


if ($found_libs->{GLX} && $ENV{TERM} ne 'xterm')
{
  print "\nThis configuration should be built under an X11 shell\n\n";
}

exit 0;



# test header files for extensions
sub cfile_text
{
  my($filename) = @_;

  # Use $Config{cpprun}, instead of $Config{cpp}. cpp is simply set to
  # 'cpp' after Configure has run, which is not useful, since it lives
  # in /lib/ on many systems, which is normally not on the path.  This
  # is documented, but silly behaviour.  $Config{cpprun} is what is
  # documented to be set to a cpp that will take stuff on stdin

  my $cmd = "echo '\#include \"$filename\"' | ".
    "$Config{cpprun} $INCS $Config{cppflags} $Config{cppminus} 2>&1";

  return `$cmd`;
}


# Find OpenGL-related Libs
sub get_libs
{
  my @glx_libs = @_;
  my $found = {};
  my $libs;

  # Mac OS X
  if ($^O eq 'darwin' && -d '/System/Library/Frameworks/OpenGL.framework')
  {
    $found->{GL} = 'OpenGL.framework';
    $found->{GLU} = 'AGL.framework';
    $found->{GLUT} = 'GLUT.framework';
    return $found;
  }

  # Win32
  if (($^O eq 'MSWin32') || $IS_W32API)
  {
    my $paths = $ENV{PATH};
    $paths =~ s|\\|/|g;
    my $sep = $IS_W32API ? ':' : ';';
    my @paths = split($sep.'\s*',$paths);

    my $sysroot = $ENV{'SYSTEMROOT'};
    @paths = ("$sysroot/system32",@paths) if ($sysroot);

    $libs = {OPENGL32=>'opengl32.dll',GLU32=>'glu32.dll',GLUT32=>'glut32.dll',FREEGLUT32=>'freeglut.dll'};
    foreach my $key (sort keys %$libs)
    {
      foreach my $path (@paths)
      {
        $path =~ s|/$||;
        my $lib = $libs->{$key};
        next if (!-e "$path/$lib");
        $lib =~ s/\.dll$//i;
        # print "  $key: $lib\n";
        $found->{$key} = $lib;
        last;
      }
    }

    # Install FreeGLUT if not found
    if (!$found->{FREEGLUT32})
    {
      my $dll_dir = $Config{installsitebin};

      my $exec;
      if ($IS_W32API)
      {
        $dll_dir = '/usr/local/bin' if ($dll_dir eq '/usr/bin');
        $exec = "cp FreeGLUT/freeglut.dll $dll_dir";
      }
      else
      {
        $exec = "copy FreeGLUT\\freeglut.dll $dll_dir";
      }
      `$exec`;

      if (! -x "$dll_dir/freeglut.dll")
      {
         my $mode = (stat("$dll_dir/freeglut.dll"))[2];
         my $perm = $mode & 07777;
         print "freeglut.dll not executable (perms=%4o), changing permissions...\n";
         chmod $perm|0755, "$dll_dir/freeglut.dll" or warn "Error changing freeglut.dll perms: $!";
      }


      if (-e "$dll_dir/freeglut.dll")
      {
        print "Installed freeglut.dll at $dll_dir\n";
        $found->{FREEGLUT32} = 'freeglut' 
      }
      else
      {
        print "Unable to install freeglut.dll to $dll_dir\n";
        print "Try manually copying FreeGLUT/freeglut.dll to a folder in your PATH.\n";
      }
    }

    return $found if (!$IS_W32API);
  }


  # Everyone else
  open(SAVEERR, ">&STDERR");
  close(STDERR);
  ($libs) = findlib->ext(join(' ',@glx_libs),0);
  open(STDERR, ">&SAVEERR");

  foreach my $lib (split(' ',$libs))
  {
    next if ($lib =~ m|^-L|);
    $lib =~ s/^-l//;
    #print "  $lib\n";

    if ($lib =~ m|([\w]*freeglut[\w]*)|i)
    {
      $found->{FREEGLUT} = $1;
    }
    elsif ($lib =~ m|([\w]*glut[\w]*)$|i)
    {
      $found->{GLUT} = $1;
    }
    elsif ($lib =~ m|([\w]*glu[\w]*)$|i)
    {
      $found->{GLU} = $1;
    }
    elsif ($lib =~ m|([\w-]*glx)$|i)
    {
      $found->{GLX} = $1;
    }
    elsif ($lib =~ m|([\w]*gl)$|i)
    {
      $found->{GL} = $1;
    }

    if ($lib =~ m|([\w]*mesa(gl)?.*)|i)
    {
      $found->{MESA} = $1;
    }
  }

  return $found;
}


# Test for available OpenGL Extensions
sub get_extensions
{
  my($found,$no_excl) = @_;
  print "Testing for OpenGL Extensions\n" if ($verbose);

  # clean up previous output files
  my $exc_file = 'gl_exclude.h';
  unlink($exc_file) if (-e $exc_file);
  my $glv_file = 'utils/glversion.txt';
  unlink($glv_file) if (-e $glv_file);

  # Only run the rest if GLUT is installed
  print "Testing GLUT version\n" if ($verbose);
  my($lib,$def);
  if ($found->{FREEGLUT32} || $found->{FREEGLUT})
  {
    $lib = $found->{FREEGLUT32} || $found->{FREEGLUT};
    $def = "HAVE_FREEGLUT";
  }
  elsif ($found->{GLUT32} || $found->{GLUT})
  {
    $lib = $found->{GLUT32} || $found->{GLUT};
    $def = "HAVE_GLUT";
  }
  elsif ($verbose)
  {
    print "GLUT not found\n";
  }

  # Platform-specific makefiles for glversion
  my $make_ver;
  if ($IS_MINGW)
  {
    $make_ver = "&mingw.bat";
#    $make_ver = '&dmake -f makefile.mingw GLUT_DEF='.$def;
    #print "mingw glversion: '$make_ver'\n";# if $verbose;
  }
  elsif ($IS_W32API)
  {
    $make_ver = ";make -f Makefile.cygwin GLUT_LIB=$lib GLUT_DEF=$def";
    #print "cygwin glversion: '$make_ver'\n" if $verbose;
  }
  elsif ($^O eq 'MSWin32')
  {
    $make_ver = '&nmake -f makefile.mak GLUT_DEF='.$def;
    #print "MSWin32 glversion: '$make_ver'\n" if $verbose;
  }
  elsif ($^O eq 'darwin')
  {
    $make_ver = ";make -f Makefile.macosx GLUT_LIB=$lib GLUT_DEF=$def";
    #print "MacOSX glversion: '$make_ver'\n" if $verbose;
  }
  else
  {
    if ($ENV{TERM} ne 'xterm')
    {
      print "\nIn order to test your GPU's capabilities, run this make under an X11 shell\n\n";
    }

    $make_ver = ";make -f Makefile GLUT_LIB=$lib GLUT_DEF=$def";
    #print "glversion: '$make_ver'\n" if $verbose;
  }
  my $exec = 'cd utils'."$make_ver clean".$make_ver;
  print "glversion: $exec\n" if ($verbose);
  my $stat = `$exec`;
  print "\n$stat\n\n" if ($verbose);


  # Parse glversion.txt file
  if ( !defined(open(GLDATA,$glv_file)) ) {
     print "get_extensions: could not open $glv_file: $!\n" if $verbose;
     return '';
  }
  my $gldata = {};
  my @gldata = <GLDATA>;
  close(GLDATA);

  foreach my $line (@gldata)
  {
    $line =~ s|[\r\n]+||;
    my($key,$val) = split('=',$line);
    $gldata->{$key} = $val;
  }
  if (!scalar(keys %$gldata)) {
     print "get_extensions: no extensions found in $glv_file\n" if $verbose;
     return '';
  }


  # Parse glext_procs.h file
  return '' if (!open(GLEXT,"glext_procs.h"));
  my @lines = <GLEXT>;
  close(GLEXT);

  my $no_ext = {};
  foreach my $line (@lines)
  {
    next if ($line !~ m|\#ifndef NO_([^\s]+)|);
    my $ext = $1;
    next if ($ext =~ m|^GL_VERSION_|);
    $no_ext->{$ext}++;
  }


  # Create gl_exclude.h
  die "Unable to write to $exc_file\n" if (!open(GLEXC,">$exc_file"));
  print GLEXC "// OpenGL Extension Exclusions - may be modified before building.\n";
  print GLEXC "//\n";
  print GLEXC "// Generated for ".$gldata->{VENDOR}.", ".$gldata->{RENDERER}."\n";
  print GLEXC "// OpenGL v".$gldata->{VERSION}.", using ";

  # Fix GLUT flags based on results
  if ($gldata->{GLUT} > 0)
  {
    print 'Found FreeGLUT v'.$gldata->{GLUT}."\n";
    print GLEXC 'FreeGLUT v'.$gldata->{GLUT}."\n";

    if (!$found->{FREEGLUT} && !$found->{FREEGLUT32})
    {
      $found->{FREEGLUT} = $lib;
    }
  }
  else
  {
    print "Found GLUT - unknown version\n";
  }

  # Make an empty exclusion file if a Windows distribution build
  if ($no_excl)
  {
    print "OpenGL Extension exclusions disabled\n";
    print GLEXC "//\n";
    print GLEXC "// Exclusions omitted for distribution build.\n";
  }
  else
  {
    print GLEXC "\n";
    if ($gldata->{VERSION} =~ m|^(\d\.\d+)|)
    {
      my $ver = $1;
      print GLEXC "#define NO_GL_VERSION_2_0\n" if ($ver < 2.0);
      print GLEXC "#define NO_GL_VERSION_1_5\n" if ($ver < 1.5);
      print GLEXC "#define NO_GL_VERSION_1_4\n" if ($ver < 1.4);
      print GLEXC "#define NO_GL_VERSION_1_3\n" if ($ver < 1.3);
      print GLEXC "#define NO_GL_VERSION_1_2\n" if ($ver < 1.2);
      print GLEXC "#define NO_GL_VERSION_1_1\n" if ($ver < 1.1);
    }

    foreach my $ext (split(' ',$gldata->{EXTENSIONS}))
    {
      next if (!$no_ext->{$ext});
      $no_ext->{$ext} = 0;
    }

    foreach my $ext (sort keys(%$no_ext))
    {
      next if (!$no_ext->{$ext});
      print GLEXC "#define NO_$ext\n";
    }
  }

  close(GLEXC);


  # return Distributable Defs
  print "Have Version Data\n" if ($verbose);
  return '-DHAVE_VER';
}

# Dump Config.pm
sub WriteConfigPM
{
  my($config) = @_;

  die "Unable to write to Config.pm\n" if (!open(CONFIGPM, ">Config.pm"));

  print CONFIGPM qq
{
# This is the Perl OpenGL build configuration file.
# It contains the final OpenGL build arguements from
# the configuration process.  Access the values by
# use OpenGL::Config which defines the variable
# $OpenGL::Config containing the hash arguments from
# the WriteMakefile() call.
#
};

  print CONFIGPM Data::Dumper->Dump( [$config], [qw(PDL::Graphics::OpenGL::Perl::OpenGL::Config)] );

  print CONFIGPM qq
{
1;
__END__
};

  close(CONFIGPM);
};
