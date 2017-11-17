#!/usr/bin/perl


use warnings;
use strict;
use Data::Dumper;

use IO::Socket::INET;
use IO::Select;

my @allowed_ips = ('all', '0.0.0.0');
my $ioset = IO::Select->new;
my %socket_map;

my $script_dir = '/home/ec2-user/denis-tcp-proxy/scripts'; 

my $debug = 1;
my $refresh_default = 120;

#===============================================================================
# SYGNALS - to syslog
#===============================================================================

# You can get all SIGNALS by:
# perl -e 'foreach (keys %SIG) { print "$_\n" }'
# $SIG{'INT'} = 'DEFAULT';
# $SIG{'INT'} = 'IGNORE';

sub INT_handler {
    my($signal) = @_;
    chomp $signal;
    use Sys::Syslog;
    my $msg = "INT: int($signal)\n";
    print $msg;
    syslog('info',$msg);
    exit(0);
}
$SIG{INT} = 'INT_handler';

sub DIE_handler {
    my($signal) = @_;

    use Sys::Syslog;
    my $msg = "DIE: die($signal)\n";
    print $msg;
    syslog('info',$msg);
}
$SIG{__DIE__} = 'DIE_handler';

sub WARN_handler {
    my($signal) = @_;
    chomp $signal;
    use Sys::Syslog;
    my $msg = "WARN: warn($signal)\n";
    print $msg;
    syslog('info',$msg);
}
$SIG{__WARN__} = 'WARN_handler';

#####################################################################

sub new_conn {
    my ($host, $port) = @_;
    return IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port
    );
}

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 100
    ) || die "Unable to listen on $host:$port: $!";
}

sub new_connection {
    my $server = shift;
    my $remote_host = shift;
    my $remote_port = shift;
    my $script_on_failure = shift;
    my $msg = shift;

    my $client = $server->accept;
    my $client_ip = client_ip($client);

    unless (client_allowed($client)) {
        print "Connection from $client_ip denied.\n" if $debug;
        $client->close;
        return;
    }

    print "Connection from $client_ip accepted.\n" if $debug;

    my $remote = new_conn($remote_host, $remote_port);

    if (ref($remote)) {
    	$ioset->add($client);
    	$ioset->add($remote);

    	$socket_map{$client} = $remote;
    	$socket_map{$remote} = $client;
    }
    else {
      print "Connection to $remote_host:$remote_port failed.\n" if $debug;
      if ($script_on_failure ne 'none') {
    		    my $client = $server->accept;
		    $client->send("$msg");
		    $client->shutdown("1");
		    system("$script_on_failure"); 
      }
    }

    return $remote;
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);
    my $remote = $socket_map{$client};
    
    $ioset->remove($client);
    $ioset->remove($remote);

    delete $socket_map{$client};
    delete $socket_map{$remote};

    $client->close;
    $remote->close;

    print "Connection from $client_ip closed.\n" if $debug;
}

sub client_ip {
    my $client = shift;
    return inet_ntoa($client->sockaddr);
}

sub client_allowed {
    my $client = shift;
    my $client_ip = client_ip($client);
    return grep { $_ eq $client_ip || $_ eq 'all' } @allowed_ips;
}


#
# Main
#

die "Usage: $0 <local port> <remote_host:remote_port> <on_failure_script>" unless @ARGV >= 2;

my $local_port = shift;
my ($remote_host, $remote_port) = split ':', shift();
my $refresh = shift || $refresh_default;

my $msg = <<"END_MESSAGE";
HTTP/1.1 404 Not Found
Server: denis-tcp-proxy
Content-Type: text/html
Connection: Closed

<html>
<head>
<meta http-equiv="refresh" content="$refresh" />
</head>
   <body>
    <img src="https://www.one-inside.com/wp-content/uploads/2015/10/Inside-Logo.png"> 
<pre>
Trying to launch the Service in $refresh seconds be patient ...
</pre>
 </body>
</html>

END_MESSAGE


my $script_on_failure = 'none';
if ( -f "$script_dir/$remote_host:$remote_port.sh" ) {
	$script_on_failure = "$script_dir/$remote_host:$remote_port.sh";
    	print "Using $script_on_failure\n" if $debug;
}

print "Starting a server on 0.0.0.0:$local_port\n";
my $server = new_server('0.0.0.0', $local_port);
$ioset->add($server);

while (1) {
    for my $socket ($ioset->can_read) {
        if ($socket == $server) {
                print "Trying to connect to $remote_host:$remote_port.\n" if $debug;
		new_connection($server, $remote_host, $remote_port, $script_on_failure, $msg);
        }
        else {
            next unless exists $socket_map{$socket};
            my $remote = $socket_map{$socket};

            my $buffer;
            my $read = $socket->sysread($buffer, 4096);
            if ($read) {
                $remote->syswrite($buffer);
            }
            else {
                close_connection($socket);
            }
        }
    }
}
