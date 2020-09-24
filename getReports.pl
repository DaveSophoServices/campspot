#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use Carp;
use JSON;

use Data::Dumper;
use DateTime;

use LWP::UserAgent qw();
use URI::Encode qw(uri_encode);

my $ua = LWP::UserAgent->new();

my $config_file = 'config';
open (my $CONFIG, "<", $config_file) or die "Cannot open config file. Will contain two lines. Line 1 is your username, Line 2 your password";
chomp(my $username = <$CONFIG>);
chomp(my $password = <$CONFIG>);
close $CONFIG;

my $login_resp = $ua->post("https://reservation.campspot.com/api/v2/authentication/login",
			   Content => qq/{"username":"$username","password":"$password"}/,
			   Content_Type => 'application/json;charset=utf-8'
    );

my $authCookie;
for my $c ($login_resp->header('Set-Cookie')) {
    if ($c =~ /^(authorization\=[^;]+);/) {
	$authCookie = $1;
    }
}

die "No cookie set after authentication. Wrong username/password?"
    if !$authCookie;

my $login = decode_json($login_resp->content);

# eg. {"parks":[{"id":123,"name":"xxxxx"}],"userId":456}
my $parkid;
if (@{$login->{parks}}) {
    $parkid = $login->{parks}[0]{id};
    carp "Park ID : $parkid";
} else {
    die "No default ParkID determinable from login response: ".$login_resp->content;
}

my $baseurl = "https://reservation.campspot.com/api/v2/parks/$parkid/reports";
my $start_date = "2020-08-01T07:00:00.000Z";
my $end_date = DateTime->today(time_zone=>'America/Los_Angeles')->set_time_zone("UTC")->strftime("%FT%TZ");

print "$start_date -> $end_date\n";


my $report_resp = $ua->get($baseurl."/accountingReport?format=csv&startDate=$start_date&endDate=$end_date",
     Cookie=>$authCookie);

print Dumper($report_resp);
