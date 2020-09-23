#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use Carp;

use Data::Dumper;

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

print $login_resp->content;

# TODO fetch parkid from login response. It's in JSON.
# eg. {"parks":[{"id":123,"name":"xxxxx"}],"userId":456}
my $parkid = "";

my $baseurl = "https://reservation.campspot.com/api/v2/parks/$parkid/reports";
my $start_date = "2020-08-01T07:00:00.000Z";
my $end_date = "2020-10-01T07:00:00.000Z";
my $report_resp = $ua->get($baseurl."/accountingReport?format=csv&startDate=$start_date&endDate=$end_date",
    Cookie=>$authCookie);

#print Dumper($report_resp);
