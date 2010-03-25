#!/bin/env perl

use strict;
use warnings;
use Cwd;
use List::Util qw(max);
use Data::Dumper;

my %blacklist = (409203 => "", 438982 => "", 455551 => "", 529888 => "", 571589 => "", 556928=>"", 121330=>"", 562352=>"", 710657=>"");

sub getSvnRevinfo($$)
{
  my ($path, $file) = @_;
  my %revisions;
  my $line = 0;
  my $rev = 0;
  my $cmd = "svn log $path/$file";
  open(CMD, "$cmd |") || die;
  while(<CMD>) {
    if(/^r(\d+) /) {
      $rev = $1;
      $revisions{$rev} = "";
      $line = 0;
    }
    chomp;
    $revisions{$rev} = $revisions{$rev} . "$_" if($line > 1 && $line < 3);
    $line++;
  }
  close(CMD);
  return %revisions;
}

sub getGitRevinfo($$)
{
  my ($dir, $file) = @_;
  my @revisions = ();
  my $cwd = getcwd();
  chdir($dir);
  my $cmd = "git log -C -C --follow $file";
  open(CMD, "$cmd |") || die;
  while(<CMD>) {
    if(/^\s+svn.*revision=(\d+)/) {
      push(@revisions, $1);
    }
  }
  close(CMD);
  chdir($cwd);
  return @revisions;
}

sub compare_git_svn_log($$$) {
  my ($gitpath, $svnpath, $file) = @_;
  my %svnrevs = getSvnRevinfo($svnpath, $file);
  my @gitrevs = getGitRevinfo($gitpath, $file);

  my $offset = 0;
  my @missingrevs = ();

  my @diff = ();
  my %count = ();

  foreach my $element (keys %svnrevs, @gitrevs) {
          $count{$element}++;
  };
  foreach my $element (sort keys %count) {
    push(@diff, $element) if( $count{$element} == 1 );
  };

  print("Found missing revisions ($#diff) for: $file\n") if($#diff > 0);
  my $rev;
  foreach $rev (@diff) {
    next if( exists($blacklist{$rev}));
    print( "\t$rev:\t$svnrevs{$rev}\n" ) if($svnrevs{$rev});
  }
}
sub getAllFiles()
{
  my @files = ();
  my $cmd = "git ls-files";
  open(CMD, "$cmd |") || die;
  while(<CMD>) {
    chomp;
    push(@files, $_);
  }
  close(CMD);
  return @files;
}

# $1 : Git dir (relative)
# $2 : SVN dir (relative)
my $CURDIR = getcwd();
my $GITDIR="$ARGV[1]";
my $SVNDIR="$ARGV[0]";
chdir($GITDIR);
my @allfiles=getAllFiles();
chdir($CURDIR);
my $DIR;
foreach $DIR (@allfiles) {
  compare_git_svn_log($GITDIR, $SVNDIR, $DIR);
}
