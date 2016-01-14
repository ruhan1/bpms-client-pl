#!/usr/bin/perl -w

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
use Pod::Usage;

if (scalar @ARGV == 0) {
  pod2usage({-verbose => 2});
}

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

print Dumper(@ARGV) if defined $ENV{BPMS_DEBUG};

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
print Dumper(\%ns_headers) if defined $ENV{BPMS_DEBUG};

my $cfg = get_config();
die "Can not load config file" unless defined $cfg;

my $deploymentId = $args->{"-deploymentId"};
my $processDefId = $args->{"-processDefId"};
my $procInstanceId = $args->{"-procInstanceId"};
my $taskId = $args->{"-taskId"};
my $requestContent;
my $userpassRef;

print Dumper($args) if defined $ENV{BPMS_DEBUG};
print $resource . " " . $action . "\n" if defined $ENV{BPMS_DEBUG};
print $params . "\n" if defined $ENV{BPMS_DEBUG};

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

my $originalDeploymentId;
if ($deploymentId) {
  my $version = (split(/:/, $deploymentId))[2];
  if (not $version) {
    $originalDeploymentId = $deploymentId; # keep old one, use it when get latest version
    $deploymentId .= ":[version]";
  }
}

if ($resource eq "process") {
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
    if ($action =~ /processes/) { # no direct api, have to exec GetProcessIdsCommand
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
  if ($action =~ /(\w+)\=(.+)/) {
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
print $url . "\n" if defined $ENV{BPMS_DEBUG};

if ($url =~ /:\[version\]/) { # process version not specified
  $url = get_complete_url();
}

my $agent = get_agent();
my $request = HTTP::Request->new(uc $method => $url);
if ($requestContent) {
  $request->content($requestContent);
  $ns_headers{"Content-Type"} = "application/xml";
}

while (my ($key, $value) = each (%ns_headers)) {
  $request->header($key => $value);
}

print Dumper($request) if defined $ENV{BPMS_DEBUG};
my $response = do_request($request, $agent);
print Dumper($response) if defined $ENV{BPMS_DEBUG};

die "Couldn't get $url" unless defined $response;
die "Error: ", $response->status_line unless $response->is_success;

print_friendly($response->content, $resource, $action);



### functions ###

sub get_complete_url {
  my $agent = get_agent();
  my $request = HTTP::Request->new(GET => $homeUrl . "/rest/deployment");
  my $response = do_request($request, $agent);
  print Dumper($response) if defined $ENV{BPMS_DEBUG};
  my $hash_ref = get_deployment_hash_ref($response->content);
  my $version = $hash_ref->{$originalDeploymentId};
  $url =~ s/\[version\]/$version/;
  print $url . "\n" if defined $ENV{BPMS_DEBUG};
  return $url;
}

sub do_request {
  my ($request, $agent) = @_;
  my $response = $agent->request($request);
  if ($response->{"_rc"} =~ /401/) {
    if (not $userpassRef) {
      $userpassRef = prompt_for_userpasswd();
    }
    $request->authorization_basic(@ $userpassRef);
    $response = $agent->request($request); # do it again
  }
  return $response;
}

sub prompt_for_userpasswd {
  my $arrayref = [];
  print "Enter username: ";
  chomp (my $user = <STDIN>);
  print "Enter password: ";
  ReadMode('noecho'); # don't echo
  chomp(my $pass = <STDIN>);
  ReadMode(0); # back to normal
  print "\n";
  $$arrayref[0] = $user;
  $$arrayref[1] = $pass;
  return $arrayref;
}

sub get_agent {
  my $ua = LWP::UserAgent->new();
  # By default, LWP::UserAgent doesn't implement cookies. Making it do so is as simple as this
  $ua->cookie_jar( {} ); 
  # Access homeUrl to force Kerberos authentication if use kinit
  $ua->get( $homeUrl );
  return $ua; 
}

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
  return new Config::Simple($configfile);
}

sub print_friendly {
  my ($content, $resource, $action) = @_;
  if ($resource eq "deployment") {
    print_deployment($content, $deploymentId, $action);
  } else {
    my $config = eval { XMLin($content) };
    if($@) { # parse error
      print $content . "\n";
    } else {
      print Data::Dumper->Dump( [ $config ], [ qw(*result) ] );
    }
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
  my $config = XMLin(shift, ForceArray => [ 'string' ]);
  foreach my $str (@ { $config->{"string-list"}->{"string"} }) {
    print "$str\n";
  }
}

sub print_deployment_all {
  my $hash_ref = get_deployment_hash_ref(shift);
  while (my ($key, $value) = each (%$hash_ref)) {
    print $key . ":" . $value . "\n";
  }
}

sub get_deployment_hash_ref {
  my $config = XMLin(shift);
  my $hash_ref = {};
  foreach my $unit (@ { $config->{"deployment-unit"} }) {
    my $key = $unit->{"groupId"} . ":" . $unit->{"artifactId"};
    if (my $ver = $hash_ref->{ $key }) {
      if ($unit->{"version"} lt $ver) { # skip version less than existing version
        next;
      }
    }
    $hash_ref->{ $key } = $unit->{"version"};
  }
  return $hash_ref;
}


=pod

=head1 NAME

Maitai is jBPM/BPMS 6.x command tool, developed by Perl

=head1 SYNOPSIS

maitai <resource> <action> [parameters...]

=head1 DESCRIPTION

Maitai is a tool to access jBPM/BPMS 6.x via REST APIs. It can use either BASIC or Kerberos (kinit) authentication. It supports process and task operations, such as start process, complete task, etc. This program uses system variable BPMS_HOME to identify the target server. You can also use "./maitai conf homeUrl=http://host[:port]" to specify the Url. It will be remembered in ~/.maitai/config. 

For beginners, you may want to list all deployments and find the right process by:
  ./maitai deployment                                   # this will list all deployments
  ./maitai deployment processes -deploymentId <id>      # this will list all processes in a certain deployment

Start a process: 
  ./maitai process start -deploymentId <id> -processDefId <pid> [-d parameters...]

Query my tasks:
  ./maitai task query -D potentialOwner=<uid>

For example:
  ./maitai process start -deploymentId draft:test:1.0 -processDefId test.testparams -d aString='Hello,world!' -d aInt=200i -d aLong=30
  ./maitai task query -D potentialOwner=ruhan

=head2 Resources

process/task/history/deployment

=head2 Actions

start/abort/signal for process; query/claim/release/start/complete for task; processes for deployment. 

=head2 Parameters

=over 12

=item C<-deploymentId>

Project deployment id of format "groupId:artifactId:version", such as "draft:test:1.0"

=item C<-processDefId>

Process definition id, such as "test.testparams"

=item C<-taskId>

Task id. User can find all tasks via task query action.

=item C<-d>

Specify process or task input arguments, e.g, "-d aString='Hello,world!'". For integer, append "i" to the number, e.g, "-d aInt=200i" (by default number will be converted to Long). For boolean, use true or false, e.g, "-d aBoolean=true". 

=item C<-D>

Specify HTTP query arguments, such as "-D potentialOwner=ruhan"

=item C<-H>

Specify HTTP headers, such as "-H 'Accept: application/json'"

=back

=head1 AUTHOR

Rui Han - <ruhan@redhat.com>

=cut
