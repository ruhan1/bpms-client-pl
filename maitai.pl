#!/usr/bin/env perl
 
use strict;
use warnings;

# CPAN install -> LWP::Authen::Negotiate, XML::Simple, Switch, Config::Simple
use Data::Dumper;
use LWP::UserAgent;
use LWP::Authen::Negotiate;
use Net::SSL;
use HTTP::Request;
use HTTP::Cookies;
use Term::ReadKey;
use URI::Escape;
use XML::Simple;
use Switch;
use Config::Simple;

$ENV{HTTPS_DEBUG} = 0;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my $args = {};
my %process_methods = ();
my %task_methods = (query=>'get');
my %deployment_methods = ();
my $resource = ""; 
my $action = ""; 
my $params = "";

my %ns_headers = ();

print Dumper(@ARGV) if defined $ENV{MAITAI_DEBUG};

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
    case /^process$|^task$|^repository$|^history$|^deployment$|^conf$/ { 
      $resource = $_;
      $do_shift = 0;
    }
    else { # actions: start|abort|signal, query|claim|release|complete 
      $action = $_;
      $do_shift = 0;
    }
  }
  if ($do_shift) { shift @ARGV; }
}
print Dumper(\%ns_headers) if defined $ENV{MAITAI_DEBUG};

my $cfg = get_config();
die "Can not load config file" unless defined $cfg;

my $deploymentId = $args->{"-deploymentId"};
my $processDefId = $args->{"-processDefId"};
my $procInstanceId = $args->{"-procInstanceId"};
my $taskId = $args->{"-taskId"};
my $requestContent;

#get_latest_version(\$deploymentId); # append the latest version if not specified
#exit;

print Dumper($args) if defined $ENV{MAITAI_DEBUG};
print $resource . " " . $action . "\n" if defined $ENV{MAITAI_DEBUG};
print $params . "\n" if defined $ENV{MAITAI_DEBUG};

my $user = '';
my $pass = '';
my $basicAuth = 0;

my $homeUrl = $ENV{BPMS_HOME};
if (not $homeUrl) {
  $homeUrl = $cfg->param('homeUrl'); # Get from config
}
if ($homeUrl !~ /\/$/) {
  $homeUrl .= '/';
}
$homeUrl .= 'business-central';

my $url = '';
my $method = '';

if ($resource eq "process") {
  get_latest_version(\$deploymentId);
  $url = $homeUrl . "/rest/runtime/$deploymentId/process/$processDefId/$action";
  $method = $process_methods{$action} || 'post';
} elsif ($resource eq "task") {
  if ($action eq "query") {
    $url = $homeUrl . "/rest/task/$action";
  } else {
    $url = $homeUrl . "/rest/task/$taskId/$action";
  }
  $method = $task_methods{$action} || 'post';
} elsif ($resource eq "deployment") { # deploy/undeploy/processes
  $url = $homeUrl . "/rest/deployment";
  if ($deploymentId) { $url .= "/$deploymentId"; }
  if ($action) { 
    if ($action =~ /processes/) { # no api, have to exec GetProcessIdsCommand
      $url = $homeUrl . "/rest/execute";
      $requestContent = "<command-request><get-process-ids/><deployment-id>$deploymentId</deployment-id></command-request>";
    } else {
      $url .= "/$action"; 
    }
    $method = 'post'; 
  } else {
    $method = 'get';
  }
} elsif ($resource eq "conf") {
  if ($action =~ /(\w+)\=([\w\:\/]+)/) {
    $cfg->param($1, $2);
    $cfg->save();
  } else {
    print $cfg->param($action) . "\n";
  }
  exit;
} else {
  die "$resource not exist!";
}
$url .= $params;
print $url . "\n" if defined $ENV{MAITAI_DEBUG};

my $agent = LWP::UserAgent->new();

# By default, LWP::UserAgent object doesn't implement cookies. Making it do so is as simple as this
$agent->cookie_jar( {} );

# Access homeUrl to force Kerberos authentication if use kinit
my $response = $agent->get( $homeUrl );

# Send the request
my $request = HTTP::Request->new(uc $method => $url);
if ($requestContent) {
  $request->content($requestContent);
  $ns_headers{"Content-Type"} = "application/xml";
}

while (my ($key, $value) = each (%ns_headers)) {
  $request->header($key => $value);
}

print Dumper($request) if defined $ENV{MAITAI_DEBUG};

$response = $agent->request($request);
print Dumper($response) if defined $ENV{MAITAI_DEBUG};

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
  $request->authorization_basic($user, $pass);
  $response = $agent->request($request);
}

die "Couldn't get $url" unless defined $response;
die "Error: ", $response->status_line unless $response->is_success;

print_friendly($response->content, $resource, $action);



### functions

sub get_default_homeUrl {
  return "https://maitai-bpms.host.dev.eng.pek2.redhat.com";
}

sub get_config {
  my $configdir = $ENV{"HOME"} . "/.maitai";
  mkdir $configdir unless -d $configdir; # Check if dir exists. If not create it.
  my $configfile = "$configdir/config";
  if (not -e $configfile) {
    open my $fh, ">>", $configfile or die "Can not open file $!";
    print $fh "homeUrl=" . get_default_homeUrl() . "\n";
    close $fh;
  }
  return new Config::Simple("$configfile");
}

sub apply_latest_version {
  my $deploymentIdRef = shift;
  my $deploymentId = ${$deploymentIdRef};
  my @gav = split(/:/, $deploymentId);
  if (scalar @gav == 3) { 
    return; 
  }
  my $version = get_latest_version($deploymentId);
  ${$deploymentIdRef} = $deploymentId . $version;
}

# TODO 
sub get_latest_version {
}

sub print_friendly {
  my ($content, $resource, $action) = @_;
  if ($resource eq "process") {
    print $content . "\n";
  } elsif ($resource eq "task") {
    if ($action eq "query") {
      print $content . "\n";
    } else {
      print $content . "\n";
    }
  } elsif ($resource eq "deployment") {
    print_deployment($content, $deploymentId, $action);
  } else {
    print $content . "\n";
  }
}

sub print_deployment {
  my ($content, $deploymentId, $action) = @_;
  if ($deploymentId) {
    if ($action =~ /processes/) {
      print_deployment_processes($content);
    } else {
      print $content . "\n";
    }
  } else {
    print_deployment_all($content);
  }
}

sub print_deployment_processes {
  my $config = XMLin(shift);
  foreach my $str (@ { $config->{"string-list"}->{"string"} }) {
    print "$str\n";
  }
}

sub print_deployment_all {
  my $config = XMLin(shift);
  my $hash_ref = {};
  foreach my $unit (@ { $config->{"deployment-unit"} }) {
    my $key = $unit->{"groupId"} . ":" . $unit->{"artifactId"};
    if (my $ver = $hash_ref->{ $key }) {
      if ($unit->{"version"} lt $ver) { # version less than existing version
        next;
      }
    }
    $hash_ref->{ $key } = $unit->{"version"};
  }
  while (my ($key, $value) = each (%$hash_ref)) {
    print $key . ":" . $value . "\n";
  }
}


=head1 NAME

BPMS 6.x client tool

=head1 SYNOPSIS

./maitai.pl <resource> <action> [parameters...]

=head1 DESCRIPTION

This is a tool to access BPMS 6.x via REST APIs. It can use either BASIC or Kerberos (kinit) authentication. It supports basic process and task operations, such as start a process, complete a task, etc. 

For example, to start a process "./maitai.pl process start -deploymentId com.myorganization.myprojects:test:1.9 -processDefId test.testparams -d aString='Hello,world!' -d aInt=200i -d aLong=30"; to query my tasks "./maitai.pl task query -D potentialOwner=ruhan". 

This program uses system varible BPMS_HOME (if exists) to identify the target server. Also you can use "./maitai.pl conf homeUrl=http://host[:port]" to specify the Url (it will be saved in ~/.maitai/config and you only need to do it once). 

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
