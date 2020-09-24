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

# Read login information
my $config_file = 'config';
open (my $CONFIG, "<", $config_file) or die "Cannot open config file. Will contain two lines. Line 1 is your username, Line 2 your password";
chomp(my $username = <$CONFIG>);
chomp(my $password = <$CONFIG>);
close $CONFIG;

#Read report information
my $report_file = 'reports';
open (my $REPORTS, "<", $report_file) or die "Cannot open report file ($report_file). It should be a JSON file listing reports to run:" .
    q/[ { "name":"accountingReport","params":["startDate","endDate","format"],"domo":"238497ab..." } ]/;
my $report_json;
do { local $/; $report_json = <$REPORTS>; };
close $REPORTS;
my $reports = decode_json($report_json);

# Attempt Login
my $login_resp = $ua->post("https://reservation.campspot.com/api/v2/authentication/login",
			   Content => qq/{"username":"$username","password":"$password"}/,
			   Content_Type => 'application/json;charset=utf-8'
    );

#Check if we were successful
my $authCookie;
for my $c ($login_resp->header('Set-Cookie')) {
    if ($c =~ /^(authorization\=[^;]+);/) {
	$authCookie = $1;
    }
}
die "No cookie set after authentication. Wrong username/password?"
    if !$authCookie;

# get user info from login
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

for my $rep (@$reports) {
    print "Report: ".$rep->{name}."\n";
    my @params;
    for my $param (@{$rep->{params}}) {
	if ($param eq "startDate") {
	    push @params, "startDate=$start_date";
	} elsif ($param eq "endDate") {
	    push @params, "endDate=$end_date";
	} elsif ($param eq "format") {
	    push @params, "format=csv";
	} else {
	    croak "Unknown report parameter: $param in report ".$rep->name;
	}
    }
	
    my $url = sprintf("%s/%s?%s", $baseurl, $rep->{name}, join("&", @params));
    my $fname = sprintf("data/%s.csv", $rep->{name});
    my $report_resp = $ua->get($url,
			       ':content-file' => $fname,
    			       Cookie=>$authCookie);

    if ($report_resp->code() == 200) {
	if (my $target =$rep->{domo}) {
	    # upload it to domo
	    my $output = `scp $fname $targetorg.import.domo.com:$target`;
	    carp "Upload failed to $targetorg.import.domo.com:$target\n$a" if $?;
	}
    }
}
