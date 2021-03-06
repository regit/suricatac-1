#!/usr/bin/env perl
#
#  Copyright (C) 2012 aflab
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use IO::Socket;
use Getopt::Long qw(:config no_ignore_case bundling);
use Data::Dumper;
use JSON;


my $TIMEOUT = 10;
my $VERSION = "0.1";
my $PROMPT = ">>> ";

my %opts;

$SIG{ALRM} = sub {
	die "Response from server not received\n";	
};

GetOptions(
	\%opts,
	'verbose|v',
	'version|V',
	'socket|s=s'
	);

if( defined $opts{version} ) {
	print "Version: ",$VERSION,"\n";
	exit 0;
}


$opts{socket} = '/usr/local/var/run/suricata/suricata-command.socket' unless defined $opts{socket};

die "Invalid socket $opts{socket}: $!\n" unless -S $opts{socket};

my $server = IO::Socket::UNIX->new(
					Peer  => $opts{socket},
					Type => SOCK_STREAM,
	                                Timeout   => $TIMEOUT 
				) or die "Can't connect to $opts{socket}: $!";

my ($request, $response, $suricata_request);

$response = send_suricata({'version' => $VERSION});

die "Protocol mismatch", Dumper($response) unless $response->{return} eq 'OK';

print $PROMPT;

while($request = <STDIN>) {
	chomp $request;
	next unless $request;

	my ($cmd, @args) = split(/\s+/, $request);
	
	if( uc($cmd) eq 'EXIT' ) {
		print "bye!\n";
		last;
	}

	$suricata_request->{'command'} = $cmd;
	$suricata_request->{'arguments'} = {};

	if( scalar @args > 0 ) {
		foreach( @args ) {
			my($key, $value) = split(/=/, $_);
			$suricata_request->{'arguments'}{$key} = $value;
		}
	}

	$response = send_suricata($suricata_request);

	if( $response->{return} ne 'OK' ) {
		print "Error during command $cmd\n";
	}

	print Dumper($response),"\n";
	print $PROMPT;
}

$server->close();

sub send_suricata {
	my $msg = shift;

	my $json;
	my $response;
	my $buffer;

	$json = JSON->new->utf8->encode($msg);
	print "Request:\n",$json,"\n" if defined $opts{verbose};

	$server->send($json);

	undef $json;

	alarm $TIMEOUT;
	for(1..3) {
		$server->recv($buffer, 4096) or die "$@";
		$json .= $buffer;

		print "Response:\n",$buffer,"\n" if defined $opts{verbose};

		eval {
			$response = JSON->new->utf8->decode($json);
		};
		if( $@ ) {
			warn "Invalid json received: $json" if defined $opts{verbose};
			next;
		}

		last;
	}
	alarm 0;


	unless( defined $response->{return} ) {
		$response->{return} = 'NOK';
		$response->{message} = $json;
	}

	return $response;
}
