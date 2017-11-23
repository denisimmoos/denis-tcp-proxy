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
my $daemonize = 1;
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

#===============================================================================
# DEMONIZE
#===============================================================================

sub daemonize {
   use POSIX;
   POSIX::setsid or die "setsid: $!";
   my $pid = fork() // die $!; #//
   exit(0) if $pid;

   chdir "/";
   umask 0;
   for (0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024))
      { POSIX::close $_ }
   open (STDIN, "</dev/null");
   open (STDOUT, ">/dev/null");
   open (STDERR, ">&STDOUT");
 
  return $pid;
 }

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
    my $lockfile = shift;

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

        # the connection is established
	if  ( -f $lockfile ) { 
		unlink $lockfile or warn "Could not unlink $lockfile: $!\n";
        }

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
		    $client->shutdown("2");

		    if  ( not -f "$lockfile" ) {
		    	system("$script_on_failure"); 
                        open(my $fh, '>', "$lockfile" ) or warn "Cannot create $lockfile";
		        print $fh "";
                        close($fh) or warn "Cannot close $lockfile";
                    }
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

die "Usage: $0 <local port> <remote_host:remote_port> <refresh in seconds>" unless @ARGV >= 2;

# 
if ($daemonize) {
	my $pid = &daemonize();
}

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
<style>
p {
  text-align: center;
  font-size: 60px;
}
</style>
</head>
   <body>
<p>
Your service will be loaded in ... 
</p>
<br />
<p id="demo"></p>
<script>
// Set the date we're counting down to
var countDownDate = new Date();
    countDownDate.setSeconds(countDownDate.getSeconds() + $refresh + 1);
    countDownDate.getTime();
    
// Update the count down every 1 second
var x = setInterval(function() {

    // Get todays date and time
    var now = new Date().getTime();
    
    // Find the distance between now an the count down date
    var distance = countDownDate - now;
    
    // Time calculations for days, hours, minutes and seconds
    var days = Math.floor(distance / (1000 * 60 * 60 * 24));
    var hours = Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    var minutes = Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60));
    var seconds = Math.floor((distance % (1000 * 60)) / 1000);
    
    // Output the result in an element with id="demo"
    document.getElementById("demo").innerHTML = days + "d " + hours + "h "
    + minutes + "m " + seconds + "s ";
    
    // If the count down is over, write some text 
    if (distance < 0) {
        clearInterval(x);
        document.getElementById("demo").innerHTML = "launching ...";
        location.reload(); 
    }
}, 1000);
</script>
</body>
</html>

END_MESSAGE


my $script_on_failure = 'none';
if ( -f "$script_dir/$remote_host:$remote_port.sh" ) {
	$script_on_failure = "$script_dir/$remote_host:$remote_port.sh";
    	print "Using $script_on_failure\n" if $debug;
}

my $lockfile = "/tmp/$remote_host:$remote_port.lock";

if  ( -f $lockfile ) { 
	unlink $lockfile or warn "Could not unlink $lockfile: $!\n";
}

print "Starting a server on 0.0.0.0:$local_port\n";
my $server = new_server('0.0.0.0', $local_port);
$ioset->add($server);

while (1) {
    for my $socket ($ioset->can_read) {
        if ($socket == $server) {
                print "Trying to connect to $remote_host:$remote_port.\n" if $debug;
		new_connection($server, $remote_host, $remote_port, $script_on_failure, $msg, $lockfile );
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
