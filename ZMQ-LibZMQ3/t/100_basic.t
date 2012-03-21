use strict;
use warnings;
use File::Spec;

use Test::More;
use ZMQ::LibZMQ3;
use ZMQ::Constants ':v3.1.1', ':all';
use Storable qw/nfreeze thaw/;

subtest 'connect before server socket is bound (should fail)' => sub {
    my $cxt = zmq_init;
    my $sock = zmq_socket($cxt, ZMQ_PAIR); # Receiver

    # too early, server socket not created:
    my $client = zmq_socket($cxt, ZMQ_PAIR);
    eval { zmq_connect($client, "inproc://myPrivateSocket"); };
    ok($@ && "$@" =~ /Connection refused/);
};

subtest 'basic inproc communication' => sub {
    my $cxt = zmq_init;
    my $sock = zmq_socket($cxt, ZMQ_PAIR); # Receiver
    eval {
        zmq_bind($sock, "inproc://myPrivateSocket");
    };
    ok !$@, "bind to inproc socket";

    my $client = zmq_socket($cxt, ZMQ_PAIR); # sender
    eval {
        zmq_connect($client, "inproc://myPrivateSocket");
    };
    ok !$@, "connect to inproc socket";

    ok(!defined(zmq_recvmsg($sock, ZMQ_DONTWAIT())), "recv before sending anything should return nothing");
    ok(zmq_sendmsg($client, zmq_msg_init_data("Talk to me") ) == 0);

    # These tests are potentially dangerous when upgrades happen....
    # I thought of plain removing, but I'll leave it for now
    my ($major, $minor, $micro) = ZMQ::LibZMQ3::zmq_version();
    SKIP: {
        skip( "Need to be exactly zeromq 2.1.0", 3 )
            if ($major != 2 || $minor != 1 || $micro != 0);
        ok(!zmq_getsockopt($sock, ZMQ_RCVMORE), "no ZMQ_RCVMORE set");
        ok(zmq_getsockopt($sock, ZMQ_AFFINITY) == 0, "no ZMQ_AFFINITY");
        ok(zmq_getsockopt($sock, ZMQ_RATE) == 100, "ZMQ_RATE is at default 100");
    }

    my $msg = zmq_recvmsg($sock);
    ok(defined $msg, "received defined msg");
    is(zmq_msg_data($msg), "Talk to me", "received correct message");

    # now test with objects, just for kicks.

    my $obj = {
        foo => 'bar',
        baz => [1..9],
        blah => 'blubb',
    };
    my $frozen = nfreeze($obj);
    ok(zmq_sendmsg($client, zmq_msg_init_data($frozen) ) == 0);
    $msg = zmq_recvmsg($sock);
    ok(defined $msg, "received defined msg");
    isa_ok($msg, 'ZMQ::LibZMQ3::Message');
    is(zmq_msg_data($msg), $frozen, "got back same data");
    my $robj = thaw(zmq_msg_data($msg));
    is_deeply($robj, $obj);
};


subtest 'invalid bind' => sub {
    my $cxt = zmq_init(0); # must be 0 theads for in-process bind
    my $sock = zmq_socket($cxt, ZMQ_REP); # server like reply socket
    eval {zmq_bind($sock, "bulls***");};
    ok($@ && "$@" =~ /Invalid argument/);
};

done_testing;
