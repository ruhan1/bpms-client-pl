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
my $resource = "process"; # process/task/repository/history/deployment, etc.
my $action = "start"; #start/abort/signal for process; claim/release/start/complete for task
my $params = "";

#print Dumper(@ARGV);

while (@ARGV) {
  $_ = shift @ARGV;
  switch($_) {
    case /^-d$/ {
      if (not $params) { $params .= "?"; }
      my $kv = $ARGV[0];
      if ($kv =~ /(\w+)\=(\S+)/) {
        my $k = $1;
        if ($k !~ /^map_/) { substr($k, 0,0) = 'map_'; }
        $kv = $k . '=' . uri_escape($2) 
      }
      $params .= ($kv . "&");
    }
    case /^-/ {
      $args->{$_} = $ARGV[0];
    }
    case /process|task|repository|history|deployment/ { 
      $resource = $_;
    }
    case /start|abort|signal|claim|release|start|complete/ { 
      $action = $_;
    }
  }
  shift @ARGV;
}
if ($args->{"-x"}) {
  $method = $args->{"-x"};
}
my $deploymentId = $args->{"-deploymentId"};
my $processDefId = $args->{"-processDefId"};
my $procInstanceID = $args->{"-procInstanceID"};

print Dumper($args);
print $resource . " " . $action . "\n";
print $params . "\n";

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
#print "$homeUrl\n";

my $url = $homeUrl . '/rest/task/query?potentialOwner=ruhan'; #for test

if ($resource eq "process") {
  $url = $homeUrl . "/rest/runtime/$deploymentId/process/$processDefId/$action";
}
$url .= $params;
print $url . "\n";

my $agent = LWP::UserAgent->new();

# By default, an LWP::UserAgent object doesn't implement cookies. Making it do so is as simple as this
$agent->cookie_jar( {} );

# Access home url to force authentication via Kerberos keytab if run kinit
my $response = $agent->get( $homeUrl );

my @ns_headers = ('Accept' => 'application/json');

# Issue the request
my $request = HTTP::Request->new(uc $method => $url);
$response = $agent->request($request, @ns_headers);
#print Dumper($response);

# Get 401 Unauthorized if not authenticated
if ($response->{"_rc"} =~ /401/) {
  print "Enter username: ";
  chomp ($user = <STDIN>);
  print "Enter password: ";
  ReadMode('noecho'); # don't echo
  chomp($pass = <STDIN>);
  ReadMode(0);        # back to normal
  $basicAuth = 1;
}

# Basic Authentication
if ($basicAuth) {
  my $request = HTTP::Request->new(uc $method => $url);
  $request->authorization_basic($user, $pass);
  $response = $agent->request($request, @ns_headers);
}

die "Couldn't get $url" unless defined $response;
die "Error: ", $response->status_line unless $response->is_success;

print $response->content . "\n";

