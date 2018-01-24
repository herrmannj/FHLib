package main;
use strict;
use warnings;
#use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use FHThreadFactory;

#use sigtrap qw(BUS SEGV PIPE ABRT);
use sigtrap qw(handler my_handler normal-signals stack-trace error-signals);

#use IO::Socket;
use POSIX ();

use threads ('stack_size' => 65535);
#use threads::shared;

#TODO redirect for log
#http://www.perlmonks.org/?node_id=637339


sub
my_handler {
  my($sig) = @_;
  print "\nmy handler called sig $sig PID $$\n";
  POSIX::_exit(0);
}


###############################################################################
# TODO switch to user fhem
# my $uid  = getuid();
# my $euid = geteuid();
# my @pw = getpwnam("fhem");



###############################################################################
# receives an copy of %main::defs from fhem.pl, stripped by GLOBs and CODE REFs
# see for deep nested structures:
# http://www.perlmonks.org/?node_id=259551
our %storage :shared;

# TODO setup port to fhem
# print "THREAD FACTORY $ENV{'FHLIB_PORT'} \n";

my $code = 
'package main;
use strict;
use warnings;

BEGIN { print "BEGIN CODE **************************************************************\n"; }

#use JSON;

our $x = 5;
#$self = undef;
#for (1..10) {setElement( new Core ());};

#use LWP::Simple;
#my $content = get("http://mysafeinfo.com/api/data?list=englishmonarchs&format=json");
#print $content ."\n";

Item("x") = $x;

bindEvent("test", "test");
fireEvent("test", "0", "1", "2");

print "Mein Name: ", $self->getName(), " ++++++\n";

#package test;
#exit(0);

sub 
test {
  #print "test sub " . ($_[0] or "undef") . " rdy \n";
  $x ++;
  #print Item("x");
  #print " .. test called $x \n";
  lock (%storage);
  #print "storage: ". $storage{"test"} . "\n";
  return $storage{"test"};
}

eval {
 #exit(0);
 die;
};
sleep 90;

#run();
#mumplputz();
';


sub
factory {
  
  my $self;
  my $setup = sub {
    $self = new ThreadFactory (
      'NAME'  =>  'ThreadFactory'
    )->start();
  };
  $setup->();
  
  for (my $i=0; $i<1; $i++) {
    #my $thr = threads->create( {'exit' => 'thread_only'}, \&worker, $code)->detach();
    newthr();
  };
  do {
    $self->doIOSelect(1);
  } until ($self->Item('SHUTDOWN'));
  #undef &factory;
};

sub 
newthr {
  my $cid = int(rand(2048));
  my $thr = threads->create( {'exit' => 'thread_only'}, \&worker, $cid, $code);
  print "new thread id ".$thr->tid(). "***************************\n";
  $thr->detach();
};

factory();
print ":$@ \n";
print "clean exit at factory\n";
exit;

#no strict 'vars';
# my $main = new GenConnect;

exit(0);
###############################################################################

#use subs qw( exit );

sub 
worker {
  my ($cid, $code) = @_;
  my $self;
    
  local *{main::setup} = sub {
    my $i = 0;
    my $name = 'main';
    $self = new ThreadWorker(
      'NAME'  =>  'Worker'.threads->tid(),
    );
    $self->Item('CID') = $cid;
    $self->start();
    
    {no strict 'refs'; 
      *{$name.'::run'} = sub {
        $self->SysLog(LOG_COMMAND, "do IO");
        while ($self->doIOSelect(10)) {};
        $self->SysLog(LOG_COMMAND, "redo IO");
        return;
        
        while ($i++ < 30) { # does the select
          #print "+++++++++++++++++\n";
          #print "$test ist ", defined (&$test)?"VORHANDEN":"NICHT DA";
          #print "\n+++++++++++++++++\n";
        
          my $timeout = 3;
          my $sel = $self->Item('selectlist');
          
          my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');
          foreach my $k (keys %{$sel} ) {
            my $o = $sel->{$k};
            vec($rin, $o->{FD}, 1) = 1 if $o->{directReadFn};
            vec($win, $o->{FD}, 1) = 1 if $o->{directWriteFn};
          }
          my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);
          {$| = 1; print "select $nfound \n";}
          foreach my $k (keys %{$sel} ) {
            my $o = $sel->{$k};
            if(defined($o->{FD}) && vec($rout, $o->{FD}, 1)) {
              $o->{directReadFn}->($o);
            }
            if(defined($o->{FD}) && vec($wout, $o->{FD}, 1)) {
              $o->{directWriteFn}->($o);
            }
          }
        }
      };
      *{$name.'::Item'} = sub : lvalue {
        $self->Item(@_);
      };
      # setElement
      *{$name.'::setElement'} = sub  {
        $self->setElement(@_);
      };
      *{$name.'::bindEvent'} = sub {
        $self->bindEvent($_[0], $_[1]);
      };
      *{$name.'::fireEvent'} = sub {
        my ($eventName, @args) = @_;
        printf ("event %s arg0 %s\n", $eventName, $args[0]);
        $self->fireEvent($eventName, @args);
      };
      # catch exit in user code
      *{$name.'::_FH_exit'} = sub {
        print "thread " . threads->tid() . " signaling exit() \n";
        #$e_ref->();
      };
      {
        no warnings 'once';
        *CORE::GLOBAL::exit = sub {
          print "my own exit ............................................\n";
          $self->getElementByName('T2FCommunication')->getElementByName('ThreadFactoryConnection')->write("DONE\r\n");
          #sleep 10;
          #exit(0);
          return;
        };
        *CORE::GLOBAL::sleep = sub {
          my ($t) = @_;
          if (defined($t)) {
            $t += 0;
          } else {
            $t = 0;
          }
          $self->SysLog(LOG_COMMAND, "enter sleep $t");
          # holdhandler
          while ($self->doIOSelect($t)) {};
          # release handler
          $self->SysLog(LOG_COMMAND, "release sleep");
        };
      };
    };
  };
  setup();
  $self->SysLog(LOG_COMMAND, "starting user code");
  {
    local $^P = 0x100;
    #my $self;
    eval $code;
  }
  print "\nnach EVAL $@\n";
  $self->SysLog(LOG_COMMAND, "finished user code");
  undef $self;
  undef $@;
  print "Thread gone .....\n";
  exit(0);
  return;# "result $@ \n";
}

#while (1) {
#  my $timeout = 10;
#  
#  my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');
#  foreach my $k (keys %selectlist) {
#    my $o = $selectlist{$k};
#    vec($rin, $o->{FD}, 1) = 1 if $o->{directReadFn};
#    vec($win, $o->{FD}, 1) = 1 if $o->{directWriteFn};
#  }
#  my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);
#  print "select $nfound \n";
#  foreach my $k (keys %selectlist) {
#    my $o = $selectlist{$k};
#    if(defined($o->{FD}) && vec($rout, $o->{FD}, 1)) {
#      $o->{directReadFn}->($o);
#    }
#    if(defined($o->{FD}) && vec($wout, $o->{FD}, 1)) {
#      $o->{directWriteFn}->($o);
#    }
#  }
#  exit(0);
#}


1;
