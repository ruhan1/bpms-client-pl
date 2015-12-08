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

$ENV{HTTPS_DEBUG} = 0;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

my $user = '';
my $pass = '';
my $basicAuth = 0;

my $homeUrl = $ENV{BPMS_HOME};
if (not $homeUrl) {
  $homeUrl = 'https://maitai-bpms.engineering.redhat.com';
}
if ($homeUrl !~ /\/$/) {
  $homeUrl .= '/';
}
$homeUrl .= 'business-central';
#print "$homeUrl\n";

my $url = $homeUrl . '/rest/task/query?potentialOwner=ruhan';

my $agent = LWP::UserAgent->new();

# By default, an LWP::UserAgent object doesn't implement cookies. Making it do so is as simple as this
$agent->cookie_jar( {} );

# Access home url to force authentication via Kerberos keytab if run kinit
my $response = $agent->get( $homeUrl );

# Issue the request
$response = $agent->get( $url ); 
print Dumper($response);

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
  my $request = HTTP::Request->new(GET => $url);
  $request->authorization_basic($user, $pass);
  $response = $agent->request($request);
}

die "Couldn't get $url" unless defined $response;
die "Error: ", $response->status_line unless $response->is_success;

print $response->content;

