package FHFactory;
use strict;
use warnings;
use diagnostics;
use utf8;
use Time::HiRes;
use lib './FHEM';
use FHCore qw ( :all );
use FHPLib;
use parent -norequire, qw ( Base );

sub
doSysLog {
  my ($self, $verbose, $message, @args) = @_;
  local $| = 1;
  my $t = Time::HiRes::time();
  my ($sec, $min, $hr, $day, $mon, $year) = localtime($t);
  my $ts = sprintf("%04d.%02d.%02d %02d:%02d:%02d.%07.3f", 1900 + $year, $mon + 1, $day, $hr, $min, $sec, ($t - int($t)) * 1000 );
  my $m = "$ts: ". ($verbose & 0x0F) . " " . sprintf($message, @args);
  print "$m \n" if ( ($verbose & 0x0F) <= 5);
};

sub
setIOSelect {
  my ($self, $elemIO) = @_;
  my $id = $elemIO->getCLID();
  my $name = $elemIO->getName();
  $self->SysLog(LOG_DEBUG, 'add %s (%s) to IO list', $id, $name);
  $self->Item('.FHSselect')->{$id} = $elemIO;
};

sub
removeIOSelect {
  my ($self, $elemIO) = @_;
  my $id = $elemIO->getCLID();
  my $name = $elemIO->getName();
  $self->SysLog(LOG_DEBUG, 'remove %s (%s) from IO list', $id, $name);
  delete $self->Item('.FHSselect')->{$id};
};

sub
doIOSelect {
  my ($self, $timeout) = @_;
  $timeout = $self->HandleTimeout();
  $timeout = (defined($timeout))?$timeout:3;
  my $select = $self->Item('.FHSselect');
  $select = (defined($select))?$select:{};
  
  my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');
  foreach my $k (keys %{$select} ) {
    my $o = $select->{$k};
    vec($rin, $o->{FD}, 1) = 1 if $o->{directReadFn};
    vec($win, $o->{FD}, 1) = 1 if $o->{directWriteFn};
  };
  my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);
  
  foreach my $k (keys %{$select} ) {
    my $o = $select->{$k};
    if(defined($o->{FD}) && vec($rout, $o->{FD}, 1)) {
      #print "SEL ".$o->getCLID()."\n";
      $o->{directReadFn}->($o);
    };
    if(defined($o->{FD}) && vec($wout, $o->{FD}, 1)) {
      $o->{directWriteFn}->($o);
    };
  };
};

sub 
setTimer {
 my ($self, $elemTimer) = @_;
 my $pkg = blessed ($elemTimer);
 my $fn = defined($pkg)?$pkg.'::doTimer':'doTimer';
 my $tim = $elemTimer->{'TIMER'};
 $self->setInternalTimer($tim, $fn, $elemTimer);
};

sub
HandleTimeout {
  my ($self) = @_;
  my $timerQueue = $self->Item('.FHTimerQueue');
  return unless (defined($timerQueue) and @{$timerQueue});
 
  my $now = gettimeofday();
  if($now < $timerQueue->[0]->{'TRIGGERTIME'}) {
    #$selectTimestamp = $now;
    return ($timerQueue->[0]->{'TRIGGERTIME'} - $now);
  };
  my $t = shift @{$timerQueue};
  my $fn = $t->{'FN'};
  my $arg = $t->{'ARG'};
  print "call $fn \n";
  if (ref $fn eq 'CODE') {
    $fn->($arg);
  } else {
    (\&$fn)->($arg);
  }; 
  return HandleTimeout();
};

sub
setInternalTimer {
  my ($self, $tim, $fn, $arg) = @_;
  print "insert $tim $fn \n";
  my $timerQueue = $self->Item('.FHTimerQueue');
  if (defined($timerQueue) and @{$timerQueue}) {
    my $i = 0;
    foreach (@{$timerQueue}) {
      if ($timerQueue->[$i]->{'TRIGGERTIME'} > $tim) {
        splice @{$timerQueue}, $i, 0, {
          'TRIGGERTIME' => $tim,
          'FN' => $fn,
          'ARG' => $arg,
        };
        return;
      };
      $i++;
    };
    $timerQueue->[$i] = {
      'TRIGGERTIME' => $tim,
      'FN' => $fn,
      'ARG' => $arg,
    };
    return;   
  } else {
    $timerQueue->[0] = {
      'TRIGGERTIME' => $tim,
      'FN' => $fn,
      'ARG' => $arg,
    };
    return;
  };
};



package ThreadFactory;
use strict;
use warnings;
use diagnostics;
use utf8;
use Time::HiRes;
use lib './FHEM';
use FHCore qw ( :all );
use FHPLib;
use FHIPC;
use parent -norequire, qw ( FHFactory );

sub
start {
  my ($self) = @_;
  # thread factory to main 
  $self->bindEvent('onMainConnected', 'mainConnected');
  $self->setElement( new FHIPCInitiator (
    'onConnected' => 'onMainConnected',
    'NAME'        => 'MainConnection',
    'IP'          => '127.0.0.1',
    'PORT'        => 49152, # https://stackoverflow.com/questions/8748396/ipc-port-ranges
  ));
  return $self;
};

sub
mainConnected {
  my ($self, $event) = @_;
  #$self->getElementByName('MainConnection')->send();
};


###############################################################################
# protocol factory -> main
package FMController;
use strict;
use warnings;
use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use FHPLib;
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onConnect'     =>  'defaultConnect',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );
   
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  }
  $self->Item('FH') = $args{'FH'} if exists $args{'FH'};
  return $self;
};

sub
start {
  my ($self) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "start");
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  $self->bindEvent('onMainMessage', 'MsgIn_IMSG');
  $self->bindEvent('onMainClosed', 'Closed');
  $self->setElement( new GenIO (
    'NAME'      =>  'Main_connection',
    'FH'        =>  $self->Item('FH'),
    'onMessage' =>  'onMainMessage',
    'onClosed'  =>  'onMainClosed',
  ))->enableIO();
  $self->Item('MSGCOUNT_OUT') = 0;
  my $json = $self->getElementByName('StreamWriter')->parse({
    $self->Item('MSGCOUNT_OUT')++ =>  {
      'c' =>  'HELO',
      'v' =>  {
        'name'  => 'FHThreadFactory',
        'type' => 'perl',
        'version' => '1',
        'id' => '01234',
      },
    }
  });
  $self->getElementByName('Main_connection')->write($json."\r\n");
};

sub
Closed {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "close connection");
  $self->getRootElement()->Item('SHUTDOWN') = 1;
  # TODO clean exit (shutdown treads)
  exit(0);
};

###############################################################################
# protocol factory -> worker
package FWController;
use strict;
use warnings;
use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use FHPLib;
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onConnect'     =>  'defaultConnect',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );
   
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  }
  $self->Item('FH') = $args{'FH'} if exists $args{'FH'};
  return $self;
};

sub
start {
  my ($self) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "start");
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  $self->setElement( new GenIO (
    'NAME'      =>  'ThreadWorker_connection',
    'FH'        =>  $self->Item('FH'),
    'onMessage' =>  'onWorkerMessage',
    'onClosed'  =>  'onWorkerClosed',
  ))->enableIO();
  $self->Item('MSGCOUNT_OUT') = 0;
  $self->bindEvent('onWorkerMessage', 'MsgIn_IMSG');
  $self->bindEvent('onWorkerClosed', 'Closed');
};

sub
MsgIn_IMSG {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "message: %s", $event->{'MESSAGE'});
  my $msg = $self->getElementByName('StreamReader')->parse($event->{'MESSAGE'});
  # first MSGCOUNT_IN is 0, cmd is HELO
  my $cmd = $msg->{'0'}->{'c'};
  my $cid = $msg->{'0'}->{'v'};
  $self->SysLog(EXT_DEBUG|LOG_PROTOCOL, "received HELO for %s", $cid);
  # TODO do we expect it ?
  my $json = $self->getElementByName('StreamWriter')->parse({
    $self->Item('MSGCOUNT_OUT')++ =>  {
      'c' =>  'ACK',
      'v' =>  0,
      'CID' => $cid,
    }
  });
  $self->getElementByName('ThreadWorker_connection')->write($json."\r\n");
};

sub
Closed {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "close connection");
  $self->getRootElement()->Item('SHUTDOWN') = 1;
};

###############################################################################
package ThreadWorker;
use strict;
use warnings;
use diagnostics;
use utf8;

# TODO, non linux: paths must be translated. see pod
use lib './FHEM';
use FHCore qw ( :all );

our @ISA = qw( Base );

sub
doSysLog {
  my ($self, $verbose, $message, @args) = @_;
     
  #my ($sec, $min, $hr, $day, $mon, $year) = localtime;
  #printf("%04d.%02d.%02d %02d:%02d:%02d ", 1900 + $year, $mon + 1, $day, $hr, $min, $sec);
  #print "$verbose: [NO LOGDEVICE] ";
  #printf ($message, @args);
  #print "\n";
  local $| = 1;
  my $t = Time::HiRes::time();
  my ($sec, $min, $hr, $day, $mon, $year) = localtime($t);
  my $ts = sprintf("%04d.%02d.%02d %02d:%02d:%02d.%07.3f", 1900 + $year, $mon + 1, $day, $hr, $min, $sec, ($t - int($t)) * 1000 );
  my $m = "$ts: ". ($verbose & 0x0F) . " " . sprintf($message, @args);
  print "$m \n" if ( ($verbose & 0x0F) <= 5);
};

sub
doHandler {
  my ($self, $handlerName, @args) = @_;
  $self->SysLog(LOG_DEBUG, 'handler \'%s\'', $handlerName);
  if ( $self->can($handlerName) ) {
    $self->$handlerName(@args);
  } else {
    # TODO log
    my $test = "main::$handlerName";
    no strict 'refs';
    if (defined (&$test)) {
      $test->(@args);
    } else {
      $self->SysLog(LOG_DEBUG, 'handler \'%s\' not found', $handlerName);
    }
  }
}

sub
setIOSelect {
  my ($self, $elemIO) = @_;
  my $id = $elemIO->getCLID();
  my $name = $elemIO->getName();
  $self->SysLog(LOG_DEBUG, 'add %s (%s) to IO list', $id, $name);
  $self->Item('selectlist')->{$id} = $elemIO;
}

sub
removeIOSelect {
  my ($self, $elemIO) = @_;
  my $id = $elemIO->getCLID();
  my $name = $elemIO->getName();
  $self->SysLog(LOG_DEBUG, 'remove %s (%s) from IO list', $id, $name);
  delete $self->Item('selectlist')->{$id};
}

sub
doIOSelect {
  my ($self, $timeout) = @_;
  $timeout = (defined($timeout))?$timeout:3;
  my $select = $self->Item('selectlist');
  $select = (defined($select))?$select:{};
  
  my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');
  foreach my $k (keys %{$select} ) {
    my $o = $select->{$k};
    vec($rin, $o->{FD}, 1) = 1 if $o->{directReadFn};
    vec($win, $o->{FD}, 1) = 1 if $o->{directWriteFn};
  }
  my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);
  #{$| = 1; print "select in factory found $nfound \n";}
  foreach my $k (keys %{$select} ) {
    my $o = $select->{$k};
    if(defined($o->{FD}) && vec($rout, $o->{FD}, 1)) {
      $o->{directReadFn}->($o);
    }
    if(defined($o->{FD}) && vec($wout, $o->{FD}, 1)) {
      $o->{directWriteFn}->($o);
    }
  }
  return $nfound;
}

sub
start {
  my ($self) = @_;
  $self->setElement( new WFController (
    'NAME'    =>  'WFC_'.$self->getName(),
  ))->connect();
  do {
    $self->doIOSelect(1);
  } until ($self->Item('RUN'));
  return $self;
};


###############################################################################
# protocol worker -> factory
package WFController;
use strict;
use warnings;
use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

#sub 
#new {
#  my $class = shift;
#  use Data::Dumper;
#  print Dumper $class;
#  my $self = $class->SUPER::new(@_);
#  return $self;
#};

sub
setUp {
  my ($self, %args) = @_;
};

sub
start {
  my ($self) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "start");
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  $self->setElement( new GenConnect (
    'NAME'        =>  'FactoryConnect',
    'onConnect'   =>  'FactoryConnected',
  ));
  $self->Item('MSGCOUNT_OUT') = 0;
}

sub
connect {
  my ($self, %args) = @_;
  $self->bindEvent('FactoryConnected', 'Connected');
  $self->getElementByName('FactoryConnect')->connect(
    'IP' => '127.0.0.1',
    'PORT' => 49153,
  );
};

# connected to factory
sub
Connected {
  my ($self, $event) = @_;

  my $fh = $event->{FH};
  my $msg = {
    $self->Item('MSGCOUNT_OUT')++ => {
      'c' => 'HELO',
      'v' =>  $self->getRootElement()->Item('CID'),
    }
  };
  my $json = $self->getElementByName('StreamWriter')->parse($msg);
  
  $self->bindEvent('FactoryConnected', undef);
  $self->removeElement($self->getElementByName('FactoryConnect')); # connect completed
  $self->bindEvent('ThreadMessage', 'MsgIn_IMSG_ACK');
  $self->setElement( new GenIO (
    'NAME'        =>  'FactoryConnection',
    'FH'          =>  $fh,
    'onMessage' =>  'ThreadMessage',
    'onClosed'  =>  'ThreadClosed',
  ))->enableIO()->write($json."\r\n");

}

#initial msg ACK
sub
MsgIn_IMSG_ACK {
  my ($self, $event) = @_;
  $self->SysLog(LOG_DEBUG, 'received \'%s\'', $event->{MESSAGE});
  $self->getRootElement()->Item('RUN') = 1;
  #$self->Item('Content') .= $event->{MESSAGE} . "\n";
}



sub
ThreadFactoryClosed {
  my ($self, $event) = @_;
  #$self->getRoot()->Item('RUN') = 1;
  print "***********************************\n";
  #print $event->{'MESSAGE'};
  print "\n***********************************\n";
  
}
1;

# t2f 
# { "01": {"cmd": "new_session", "id":"id"}};
# f2t ok
# t2f -> log
# t2f -> start app


