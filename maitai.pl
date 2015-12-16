#!/usr/bin/env perl
 
use strict;
use warnings;

use Data::Dumper;
use LWP::UserAgent;
use LWP::Authen::Negotiate;
use Net::SSL;
use HTTP::Request;
use HTTP::Cookies;
use Term::ReadKey;
use URI::Escape;
use Switch;

$ENV{HTTPS_DEBUG} = 0;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $args = {};

my $method = "GET"; # POST/PUT/DELETE
my $resource = "process"; 
my $action = "start"; 
my $params = "";

my %ns_headers = ();

print Dumper(@ARGV) if defined $ENV{DEBUG};

while (@ARGV) {
  $_ = shift @ARGV;
  my $do_shift = 1;
  switch($_) {
    case /^-H$/ {
      my $h = $ARGV[0];
      if ($h =~ /(\S+)\s*\:\s*(\S+)/) {
        $ns_headers{$1} = $2;
      }
    }
    case /^-d$|-D$/ {
      if (not $params) { $params .= "?"; }
      my $kv = $ARGV[0];
      if (/^-d/ && ($kv =~ /(\w+)\=([\w\s]+)/)) {
        my $k = $1;
        if ($k !~ /^map_/) { substr($k, 0,0) = 'map_'; }
        $kv = $k . '=' . uri_escape($2);
      }
      $params .= ($kv . "&");
    }
    case /^-/ {
      $args->{$_} = $ARGV[0];
    }
    case /process|task|repository|history|deployment/ { 
      $resource = $_;
      $do_shift = 0;
    }
    case /start|abort|signal|query|claim|release|complete/ { 
      $action = $_;
      $do_shift = 0;
    }
  }
  if ($do_shift) { shift @ARGV; }
}
print Dumper(\%ns_headers) if defined $ENV{DEBUG};

if ($args->{"-x"}) {
  $method = $args->{"-x"};
}
my $deploymentId = $args->{"-deploymentId"};
my $processDefId = $args->{"-processDefId"};
my $procInstanceId = $args->{"-procInstanceId"};
my $taskId = $args->{"-taskId"};

print Dumper($args) if defined $ENV{DEBUG};
print $resource . " " . $action . "\n" if defined $ENV{DEBUG};
print $params . "\n" if defined $ENV{DEBUG};

my $user = '';
my $pass = '';
my $basicAuth = 0;

my $homeUrl = $ENV{BPMS_HOME};
if (not $homeUrl) {
  $homeUrl = 'https://maitai-bpms-01.app.test.eng.nay.redhat.com'; #default
}
if ($homeUrl !~ /\/$/) {
  $homeUrl .= '/';
}
$homeUrl .= 'business-central';

my $url = '';

if ($resource eq "process") {
  $url = $homeUrl . "/rest/runtime/$deploymentId/process/$processDefId/$action";
} elsif ($resource eq "task") {
  if ($action eq "query") {
    $url = $homeUrl . "/rest/task/$action";
  } else {
    $url = $homeUrl . "/rest/task/$taskId/$action";
  }
}
$url .= $params;
print $url . "\n" if defined $ENV{DEBUG};

my $agent = LWP::UserAgent->new();

# By default, LWP::UserAgent object doesn't implement cookies. Making it do so is as simple as this
$agent->cookie_jar( {} );

# Access homeUrl to force Kerberos authentication if use kinit
my $response = $agent->get( $homeUrl );

# Send the request
my $request = HTTP::Request->new(uc $method => $url);
$response = $agent->request($request, %ns_headers);
#print Dumper($response) if defined $ENV{DEBUG};

# Get 401 Unauthorized if not authenticated
if ($response->{"_rc"} =~ /401/) {
  print "Enter username: ";
  chomp ($user = <STDIN>);
  print "Enter password: ";
  ReadMode('noecho'); # don't echo
  chomp($pass = <STDIN>);
  ReadMode(0);        # back to normal
  $basicAuth = 1;
  print "\n";
}

# Basic Authentication
if ($basicAuth) {
  my $request = HTTP::Request->new(uc $method => $url);
  $request->authorization_basic($user, $pass);
  $response = $agent->request($request, %ns_headers);
}

die "Couldn't get $url" unless defined $response;
die "Error: ", $response->status_line unless $response->is_success;

print $response->content . "\n";



=head1 NAME

BPMS 6.x client tool

=head1 SYNOPSIS

./maitai.pl <resource> <action> [parameters...]

=head1 DESCRIPTION

This is a tool to access BPMS 6.x via REST APIs. It can use either BASIC or Kerberos (kinit) authentication. It supports basic process and task operations, such as start a process, complete a task, etc. 

For example, to start a process "./maitai.pl process start -deploymentId com.myorganization.myprojects:test:1.9 -processDefId test.testparams -d aString='Hello,world!' -d aInt=200i -d aLong=30"; to query my tasks "./maitai.pl task query -D potentialOwner=ruhan". 

This program uses a system varible BPMS_HOME to identify the target server. If not specified, the default is 'https://maitai-bpms-01.app.test.eng.nay.redhat.com'.

=head2 Resources

process/task/history/deployment

=head2 Actions

start/abort/signal for process; query/claim/release/start/complete for task; list for deployment. 

=head2 Parameters

=over 12

=item C<-deploymentId>

Artifact deployment id, such as "com.myorganization.myprojects:test:1.9"

=item C<-processDefId>

Process definition id, such as "test.testparams"

=item C<-taskId>

Task id. User can find all tasks via task query action.

=item C<-d>

Specify process or task input arguments, e.g, "-d aString='Hello,world!'". For integer, append "i" to the number, e.g, "-d aInt=200i" (by default a number will be converted to a Long). For boolean, use true or false, e.g, "-d aBoolean=true". 

=item C<-D>

Specify HTTP query arguments, such as "-D potentialOwner=ruhan"

=item C<-H>

Specify HTTP headers, such as "-H 'Accept: application/json'"

=back

=head1 AUTHOR

Rui Han - <ruhan@redhat.com>

=cut
