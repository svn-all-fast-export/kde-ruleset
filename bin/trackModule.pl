#!/bin/env perl
#

use strict;
use warnings;
use Switch;

my @commands = ();

sub listSubDirs($$$)
{
    print("Getting a list of subdirs...");
    my ($repository, $revision, $path) = @_;
    my $cmd = "svn ls $repository/$path\@$revision";
    push( @commands, $cmd );

    my @dirs;
    open( CMD, "$cmd |" ) || die "listSubDirs: Failed to run \"$cmd\": $!\n";

    print( "listSubDirs: Getting subdirs of '$repository/$path\@$revision'\n" );
    while( <CMD> ) {
        chomp;
        if( /(\S+)\/$/ ) {
            print( "listSubDirs:\tFound subdir: '$_'\n" );
            push( @dirs, "$path/$1" );
        }
    }
    close( CMD );
    print(" done\n");
    return @dirs;
}

sub getCopyFrom($$$)
{
    my ($repository, $revision, $path ) = @_;
    my $cmd = "svn log -v --stop-on-copy $repository$path\@$revision";
    push( @commands, $cmd );
    my $fromRevision = 0;
    my $fromPath = "";

    my @log = ();

    open( CMD, "$cmd |" ) || die "getCopyFrom: Failed to run \"$cmd\": $!\n";
    #print( "getCopyFrom: Getting origin of '$repository $path @ $revision'\n");
    while( <CMD> ) {
        chomp;
        if( /^r(\d+) \| / ) {
            @log = ();
        }
        push( @log, $_ );
    }

    my $cvs2svnUsed = 0;
    my $cvs2svnCandidate = 0;
    my $currentRev = 0;

    foreach( @log ) {
        if( /^r(\d+) \| / ) {
            $currentRev = $1;
        }
        if( /\s+(?:A|R) (\/\S+) \(from (\/\S+):(\d+)\)/ ) {
            my $origPath = $2;
            my $newPath = $1;
            my $fromRev = $3;
            $fromRevision = $fromRev;
            my @components = split( /\//, $path );
            my $subdir = pop( @components );
            my $shortPath = join( "/", @components );
            #print("> ------\n");
            #print("> \$path:         $path\n");
            #print("> \$newPath:      $newPath\n");
            #print("> \$origPath:     $origPath\n");
            #print("> \$fromRevision: $fromRevision\n");
            #print("> \$subdir:       $subdir\n");
            #print("> \shortPath:     $shortPath\n");

            # case 1: the dir is moved/replaced
            if( $newPath =~ /$path$/ ) {
                print( "getCopyFrom:\t\@r$currentRev: Found '$newPath' from '$origPath' at rev $fromRev\n" );
                $fromPath = $origPath;
                last;
            }

            # case 2: A parent is moved/replaced
            if( $shortPath eq $newPath ) {
                print( "getCopyFrom:\t\@r$currentRev: Found parent move '$shortPath' from '$origPath' at rev $fromRev\n" );
                $fromPath = "$origPath/$subdir";
                last;
            }
        }

        # case 3: A cvs2svn server side move
        # Directory add followed by every file as a svn cp
        if( /\s+A\s+$path/ ) {
            $cvs2svnCandidate = 1;
        }
        if( $cvs2svnCandidate && /cvs2svn/ ) {
            $cvs2svnUsed = 1;
            last;
        }
    }

    if( $cvs2svnUsed ) {
        foreach( @log ) {
            if( /^r(\d+) \| / ) {
                $currentRev = $1;
            }
            if( /\s+A\s+$path\S+\s+\(from (\S+):(\d+)\)/ ) {
                my $origPath = $1;
                my $fromRev = $2;
                my @components = split( /\//, $path );
                my $subdir = pop( @components );
                my $shortPath = join( "/", @components );
                my $component = "";
                my @origComponents = split( /\//, $origPath );
                do {
                    $component = pop( @origComponents );
                } while( $component && $component ne $subdir );
                $origPath = join( "/", @origComponents ) . "/" . $component;

                if( $origPath eq "/" ) {
                    print( "\n==========================\n" );
                    print( "Unable to determine the source of the move, aborting this operation.\n" );
                    print( "To manually track this start with \"svn log -v -c$currentRev $repository\"\n" );
                    print( "You may then restart this tool with the new parameters or you can do it manually.\n" );
                    print( "Sorry for the extra trouble!\n" );
                    print( "==========================\n" );
                    my @returnValue = (0,"");
                    return @returnValue;
                }

                print( "getCopyFrom:\t\@r$currentRev: Found cv2svn move '$path' from '$origPath' at rev $fromRev\n" );
                $fromPath = $origPath;
                $fromRevision = $fromRev;
                last;
            }
        }
    }

    close( CMD );
    if( $fromPath eq "" ) {
        $fromRevision = 0;
    }
    my @returnVale = ( $fromRevision, $fromPath );
    return @returnVale;
}

sub getCopyFromRecursive($$$$)
{
    my ($repository, $module, $revision, $path ) = @_;
    my @history = ();

    push( @history, [$path, $revision] );
    #if( $revision ne "HEAD" ) {
    #    $revision -= 1;
    #}
    do {
        ($revision, $path) = getCopyFrom( $repository, $revision, $path );
        #if( $revision ne "HEAD" ) {
        #    $revision -= 1;
        #}
        if( $revision > 1) {
            push( @history, [$path, $revision] );
            #print( "getCopyFromRecursive: $path @ $revision\n" );
        }
    } while( $revision > 0 );

    print("===================================\n");
    print(" Directory rules (skeleton)...\n\n");
    my $minRevision = 0;
    for my $historyPart ( reverse( @history ) ) {
        #print( "\t[ @$historyPart ]\n");
        push( @$historyPart, $minRevision );
        $minRevision = @$historyPart[1];
    }

    for my $historyPart (@history) {
        #print( "\t[ @$historyPart ]\n");

        print( "match @$historyPart[0]/\n");
        print( "    repository KDE/$module\n");
        print( "    branch master\n");
        print( "    max-revision @$historyPart[1]\n") if( @$historyPart[1] ne "HEAD" );
        print( "    min-revision @$historyPart[2]\n" ) if( @$historyPart[2] != 0 );
        print( "end match\n");
    }
}

my $repository;
my $path;
my $revision = "HEAD";
my $module;
my $argnum;
my $subdirs = 0;
my $showcommands = 0;

for($argnum = 0; $argnum <= $#ARGV; $argnum++ ) {
    print "Argument #$argnum: $ARGV[$argnum]\n";
    switch ($ARGV[$argnum]) {
        case "--repo"   { $repository = $ARGV[++$argnum]; }
        case "--path"   { $path = $ARGV[++$argnum]; }
        case "--module" { $module = $ARGV[++$argnum]; }
        case "--rev"    { $revision = $ARGV[++$argnum]; }
        case "--subdirs"{ $subdirs = 1; }
        case "--showcommands" { $showcommands = 1; }
        else            { print "Unknown option: $ARGV[$argnum]\n"; exit; }
    }
}
if( $#ARGV < 5 || $#ARGV > 9 ) {
    print( "Usage: trackModule.pl --repo repository --path path --module module [--rev revision] [--subdirs] [--showcommands]\n");
    exit;
}
print <<EOF;
Got:
  \$repository: $repository
  \$path:       $path
  \$module:     $module
  \$revision:   $revision
  \$subdirs:    $subdirs
EOF

my @dirs;
if( $subdirs ) {
    my @subdirs = listSubDirs( $repository, $revision, $path );
    push( @dirs, @subdirs );
}

splice( @dirs, 0, 0, $path );

my %foundDirRevisions;

foreach( @dirs )
{
    print( "Scanning '$_'...\n" );
    getCopyFromRecursive( $repository, $module, $revision, $_ );
}

if( $showcommands ) {
    print( "Used commands...\n" );
    foreach( @commands ) {
        print( "$_\n" );
    }
}
