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

my $report_to_run = $ARGV[0];

# Read login information
my $config_file = 'config';
open (my $CONFIG, "<", $config_file) or die q/Cannot open config file. Will contain JSON: { "user":"username","pass":"password","domotarget":"user@instance"}/;

my $config_json;
do { local $/; $config_json = <$CONFIG>; };
close $CONFIG;
my $config = decode_json($config_json);

if (!$config->{user}) {
    warn q/config file must include username for campspot: { "user":"username" }/;
}
if (!$config->{pass}) {
    warn q/config file must include password for campspot user {"user":"username", "pass":"mypassword"}/;
}
die if !($config->{user} && $config->{pass});


#Read report information
my $report_file = 'reports';
open (my $REPORTS, "<", $report_file) or die "Cannot open report file ($report_file). It should be a JSON file listing reports to run:" .
    q/[ { "name":"accountingReport","params":["startDate","endDate","format"],"domo":"238497ab..." } ]/;
my $report_json;
do { local $/; $report_json = <$REPORTS>; };
close $REPORTS;
my $reports = decode_json($report_json);

# check we have a report by this name
if ($report_to_run) {
    my $matchCount = 0;
    for (@$reports) { if ($_->{name} eq $report_to_run) { $matchCount++; } }
    die "Cannot find report named '$report_to_run' in reports file" if !$matchCount;
}

# Attempt Login
my $login_resp = $ua->post("https://reservation.campspot.com/api/v2/authentication/login",
			   Content => q/{"username":"/.$config->{user}.q/","password":"/.$config->{pass}.q/"}/,
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
my $end_date = DateTime
    ->today(time_zone=>'America/Los_Angeles')
    ->add(days=>180)
    ->set_time_zone("UTC")
    ->strftime("%FT%TZ");

print "$start_date -> $end_date\n";

my $domo_instance = $config->{domotarget}.".import.domo.com";
for my $rep (@$reports) {
    next if ($report_to_run && $rep->{name} ne $report_to_run);
    
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
			       ':content_file' => $fname,
    			       Cookie=>$authCookie);

    if ($report_resp->code() == 200) {
	if (my $target =$rep->{domo}) {
	    # upload it to domo
	    my $output = `scp $fname $domo_instance:$target`;
	    carp "Upload failed to $domo_instance:$target\n$output" if $?;
	}
    }
}
