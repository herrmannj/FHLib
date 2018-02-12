#TODO install memory evaluating process, ie https://tech.binary.com/tracing-perl-memory-leaks-with-devel-mat/
package FHCore;

my %constants;
BEGIN {
  %constants = (
    'LOG_FATAL'     =>  0,
    'LOG_ERROR'     =>  1,
    'LOG_ALERT'     =>  2,
    'LOG_COMMAND'   =>  3,
    'LOG_PROTOCOL'  =>  4,
    'LOG_DEBUG'     =>  5,
    'EXT_DEBUG'     =>  16,   # bitmask for extended logging
  );
  @FHCore::EXPORT_OK = keys(%constants);
  %FHCore::EXPORT_TAGS = (
    'all'     => \@EXPORT_OK,
  );
}

use constant \%constants;
use base 'Exporter';


###############################################################################

package MemWatch;
use strict;
use warnings;
use utf8;

sub new {
  my ($type) = @_;
  return bless {}, $type;
};

sub DESTROY {
  print "MEMORY FREE \n";
};
###############################################################################

package Core;
use strict;
use warnings;
use utf8;
use Time::HiRes qw ( time );
use Scalar::Util qw( blessed refaddr weaken );
use FHCore qw( :all );

sub
new {
  my ($type, %args) = @_;
  
  # try to guess parent
  #my $p;
  #package DB {
  #  my @c;
  #  my $a;
  #  my $i = 1;
  #  do {
  #    @c = caller($i);
  #    $a = \@DB::args;
  #    print "$i: $c[3] \n";
  #    $i++;
  #  } until ( Scalar::Util::blessed($a->[0]) or (not $c[3]));
  #  $p = $a->[0] if (Scalar::Util::blessed($a->[0]));
  #};
  #use Data::Dumper;
  #print Dumper $a->[0];
  
  #my $p = $a->[0];
  #print Dumper $p;
  #if (blessed($p)) {
  #  print "NAME ".$p->{NAME}."\n";
  #  print "PARENT ".$p->{'.FHLib'}->{PARENT}."\n";
  #  print "CLID ".$p->{'.FHLib'}->{CLID}."\n";
  #}
  
  my $class = ref $type || $type;
  my $self = {};
  bless $self, $class;
  
  $self->{NAME} = $args{NAME} if ($args{NAME});
  $self->{'.FHLib'}->{'CLID'} = refaddr ($self); # context local ID
  # defer interaction with parent. 
  # log, handler, timer, io etc, who relying on the existence of parent, will queue their actions  (until parent is set)
  $self->{'.FHLib'}->{'DEFER'} = 1 unless ($args{'DEFER'}||1 eq 0);
  $self->{'.FHLib'}->{'QUEUE'}->{'LOG'} = [];
  
  $self->setUp(%args);
  $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'element CLID %s (%s) created', $self->getCLID(), ref $self );
  #$self->SysLog (LOG_DEBUG, 'parent guess \'%s\' (%s)', $p->getName(), $p->{'.FHLib'}->{'CLID'} ) if $p;
  return $self;
}

sub
setUp {
  my ($self, %args) = @_;
}

###############################################################################
# creates an unique key for an given hash(ref)
sub
getUniqueKey {
  my ($self, $hashRef) = @_;
  my $key;
  my @chars = ("A".."F", "0".."9");
  do {
    $key = 'FHLib_';
    $key .= $chars[rand @chars] for 1..8; 
  } while (exists ($hashRef->{$key}) );
  return $key;
};

sub
getCLID {
  my ($self) = @_;
  if ( exists($self->{'.FHLib'}) and exists($self->{'.FHLib'}->{CLID}) 
      and defined($self->{'.FHLib'}->{CLID}) ) {
    if ($self->{'.FHLib'}->{CLID} eq refaddr($self)) {
      return $self->{'.FHLib'}->{CLID};
    } else {
      return $self->{'.FHLib'}->{CLID} . ' [REAL:' . refaddr($self) . ']';
    }
  } else {
    return 'ALT:' . refaddr($self);
  };
};

sub
getName {
  my ($self) = @_;
  if ( exists($self->{NAME}) and $self->{NAME}) {
    return $self->{NAME};
  } else {
    return 'UNKNOWN';
  };
};

sub
setParent {
  my ($self, $parent) = @_;
  if ($self->getParent())  {
    return $self if ( (refaddr($parent) or 0) == $self->getParent()->getCLID() ); # avoid recursion
    # beim parent: abmelden
  }
  $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'set CLID %s \'%s\' as PARENT', $parent->getCLID(), $parent->getName());;
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  $self->{'.FHLib'}->{'DEFER'} = undef;
  $self->doDeferedSysLog();
  # $parent->(can('setElement')
  # pendig log, io or timer ? do it ... 
  return $self;
}

sub
getParent {
  my ($self) = @_;
  return $self->{'.FHLib'}->{PARENT};
}

# local storage for persitent values
sub
Item : lvalue {
  my ($self, $name) = @_;
  return $self->{'.FHLib'}->{STORAGE}->{ITEM}->{$name};
}

sub
getRootElement {
  my ($self) = @_;
  my $r = $self;
  while ($r->getParent()) {
    $r = $r->getParent();
  }
  return $r;
}

###############################################################################
# log function:
# ask parent to log a message.
# it is expected that an element, higher in the hierarchy, knows how to drop 
# message. that element should overwrite the SysLog function and perform actual 
# logging to disc. Normal use case is that some ancestor (thread, module) 
# add specific informations and forward the message via channel to some 
# logging authority. if no ancestor capable of logging can be found, a backup 
# logs to stdout. 
###############################################################################
sub
stacktrace {
  my ($self) = @_;
  my $i = 1;
  print STDERR "Stack Trace:\n";
  package DB {
    while ( (my @call_details = (caller($i++))) ){
      my $args = \@DB::args;
      #print STDERR $call_details[1].":".$call_details[2]." in function ".$call_details[3]."\n";
      foreach my $arg (@$args) {
        #print $arg."\n";
      };
    };
  };
};

sub
SysLog {
  my ($self, $verbose, $message, @args) = @_;
  #$self->stacktrace();
  my $ext = $verbose & 0xF0;
  $verbose &= 0x0F;
  if ($verbose == LOG_DEBUG) {
    my @c = caller(1);
    my $t = blessed($self);
    my $r = refaddr($self);
    $r .= ",'$self->{NAME}'" if ($self->{NAME});

    $c[3] ||= 'MAIN';
    my $d = "[$t $c[3],$r]";
    if (-t STDOUT) {
      $message = "\033[1;31m$d\033[0m CONSOLE $message";
    } else {
      $message = "$d HTML $message";
    };    
  };
  my $name = $self->getRootElement()->getName();
  $message = "$name: $message";
  $self->doSysLog($verbose, $message, @args);
};

sub
doSysLog {
  my ($self, $verbose, $message, @args) = @_;
     
  if ($self->{'.FHLib'}->{'DEFER'}) {
    push @{$self->{'.FHLib'}->{'QUEUE'}->{'LOG'}}, {
      'TIME' =>  Time::HiRes::time(),
      'VERBOSE' => $verbose,
      'MSG' => $message,
      'ARGS' => \@args,
    };
  } elsif (blessed ($self->getParent()) and $self->getParent()->can('doSysLog')) {
    $self->getParent()->doSysLog($verbose, $message, @args);
  } else {
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
  }
}

sub
doDeferedSysLog {
  my ($self) = @_;
  while (@{$self->{'.FHLib'}->{'QUEUE'}->{'LOG'}}) {
    my $e = shift @{$self->{'.FHLib'}->{'QUEUE'}->{'LOG'}};
    my $t = Time::HiRes::time() - $e->{'TIME'};
    my $name = $self->getRootElement()->getName();
    my $msg = $e->{'MSG'};
    $msg =~ s/\G[^:]*/$name/;
    $msg = sprintf ('%s (defered %0.3f msec)', $msg, $t*1000);
    $self->doSysLog ($e->{'VERBOSE'}, $e->{'MSG'}, @{$e->{'ARGS'}});
    #$self->doSysLog (0, $msg, @{$e->{'ARGS'}});  
  }
}

###############################################################################
# store some FHLib element into local storage
# 
# 
###############################################################################
sub
setElement {
  my ($self, $element) = @_;
  return undef if ( ! defined ($element) ); # to support chain of creation
  
  my $clid = refaddr ($element);
  # sanity check #1
  if ( ! $clid ) {
    $self->SysLog (LOG_ALERT, 'setElemenet called on scalar %s', ($element or 'UNDEFINED' ) );
    return undef;
  };
  # sanity check #2
  if ( $clid ne $element->{'.FHLib'}->{CLID} ) {
    $self->SysLog (EXT_DEBUG|LOG_ALERT, '\'%s\' CLID corrected found: %s, stored: %s', $element->getName(), $clid, $element->{'.FHLib'}->{CLID} );
    $element->{'.FHLib'}->{CLID} = $clid;
  };
  $self->SysLog (LOG_DEBUG, 'store CLID %s as \'%s\'', $clid, $element->getName() );
  # sanity check #3
  $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$clid} = $element;
  # set parent
  $element->setParent($self);
  # set descriptor
  if ($element->{NAME}) {
    my $name = $element->{NAME};
    # remove if an element with the same name is stored
    if (exists($self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name}) and
        defined($self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name})) {
      $self->removeElement($self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name});
    };
    $self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name} = $clid; # TODO how to deal with duplicates ?
  };
  $element->start() if ($element->can('start'));
  return $element;
};

sub
getElementByName {
  my ($self, $name) = @_;
  if ( exists($self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name}) ) {
    my $clid = $self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$name};
    $self->SysLog (LOG_DEBUG, '\'%s\' as CLID %s', $name, $clid);
    return $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$clid};
  } else {
    $self->SysLog (LOG_DEBUG, '\'%s\' not found', $name );
    return undef;
  };
};

sub
removeElement {
  my ($self, $c) = @_;
  $self->SysLog (LOG_DEBUG, 'remove CLID: %s', $c);
  if (ref $c) {
    foreach my $k (keys %{$self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}}) {
      my $o = $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$k};
      if ($c and $o and (refaddr($c) == refaddr($o))) {
        delete $self->{'.FHLib'}->{'STORAGE'}->{'NAME'}->{$o->getName()}; # TODO how to deal with duplicates ?
        delete $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$k}; # TODO push into return
        #$self->removeElementByIDRef($o);
      };
    };
  };
};

sub
RELEASE {
  my ($self) = @_;
  $self->{NAME} |= 'UNKNOWN';
  print "release: $self $self->{NAME} \n";
  foreach my $k (keys %{$self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}}) {
    my $o = $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$k};
    if (blessed ($o) and $o->can('RELEASE')) {
      my $c = ($o->can('RELEASE'))?$o->getCLID():'RECALCULATED: '.refaddr ($o);
      $c .= ($o->can('getName'))?' ('.$o->getName().')':'';
      $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'invoke RELEASE for CLID %s', $c);
      $o->RELEASE();
    };
    # TODO clear NAME
    delete $self->{'.FHLib'}->{'STORAGE'}->{'ELEMENT'}->{$k};
    # TODO self->defer
    # TODO self->remove parent
  };  
};

sub 
DESTROY {
  my ($self) = @_;
  # avoid warnings during global destruction. perl 5.14 required
  return if ( ${^GLOBAL_PHASE} eq 'DESTRUCT');
  $self->RELEASE() if ($self->can('RELEASE'));
  $self->SysLog (EXT_DEBUG|LOG_COMMAND, 'element CLID %s (%s) destroyed %s', $self->getCLID(), ref $self, $self->getName() );
};

#sub 
#DESTROY {
#  my ($self) = @_;
#  #use Devel::Cycle;
#  #find_cycle($self);
#  
#  $self->SysLog (EXT_DEBUG|LOG_COMMAND, 'element CLID %s (%s) destroyed', $self->getCLID(), ref $self );
#}

###############################################################################
package Handler;
use strict;
use warnings;
use Scalar::Util qw( weaken );
use FHCore qw( :all );

# bind eventName to handler (object function)
sub
bindEvent {
  my ($self, $eventName, $handler) = @_;
  if ($handler) {
    $self->{'.FHLib'}->{STORAGE}->{HANDLER}->{$eventName} = $handler;
  } else {
    delete $self->{'.FHLib'}->{STORAGE}->{HANDLER}->{$eventName};
  };
};

# if an event is fired, it name will be 'exchanged' if mapped
# that is to overwrite built in behaviour of elements 
sub
mapEvent {
  my ($self, $eventName, $eventNameMapped) = @_;
  if ($eventNameMapped) {
    $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName} = $eventNameMapped;
  } else {
    delete $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName};
  };
};

# see if an event name should be exchanged (if mapped)
sub
resolveEvent {
  my ($self, $eventName) = @_;
  if (exists($self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName})) {
    $self->SysLog(LOG_DEBUG, '%s resolved as %s ', $eventName, $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName} );
    $eventName = $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName};
  }
  return $eventName;
}

sub
fireEvent {
  my ($self, $eventName, $e) = @_;
  $self->SysLog(LOG_DEBUG, 'event \'%s\'', $eventName);
  if ( ($self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}) and 
    (@{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}}) ) {
    $self->SysLog(LOG_DEBUG, 'retain event \'%s\' ', $self->{NAME}, $eventName);
    push @{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}}, {
      'NAME'  => $eventName,
      'EVENT' => $e,
    };
    return;
  };

  do {
    $eventName = $self->resolveEvent($eventName);
    if (exists($self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName}) && $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName}) {
      my $handlerName = $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName};
      $self->doHandler($handlerName, $e);
    } elsif ($self->getParent()) {
      $self->getParent()->fireEvent($eventName, $e);
    } else {
      $self->SysLog(LOG_DEBUG, 'no object to handle event \'%s\' found', $eventName);
    };
    my $t = shift @{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}} if ($self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'});
    return if ( ! $t );
    $eventName = $t->{'NAME'};
    $e = $t->{'EVENT'};
  } while (1);
};

sub
doHandler {
  my ($self, $handlerName, $e) = @_;
  $self->SysLog(LOG_DEBUG, 'handler \'%s\'', $handlerName);
  #for my $i (0 .. $#args) {
  #  if (ref $args[$i]) {
  #    weaken $args[$i];
  #  }
  #}
  if ( $self->can($handlerName) ) {
    $self->$handlerName($e);
  } else {
    # TODO log
    $self->SysLog(LOG_DEBUG, 'handler \'%s\' not found', $handlerName);
  }
}

###############################################################################
package CoreAsync;
use strict;
use warnings;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Core );

# bind eventName to handler (object function)
sub
bindEvent {
  my ($self, $eventName, $handler) = @_;
  if ($handler) {
    $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName} = $handler;
  } else {
    delete $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName};
  };
};

# if an event is fired, it name will be 'exchanged' if mapped
# that is to overwrite built in behaviour of elements 
sub
mapEvent {
  my ($self, $eventName, $eventNameMapped) = @_;
  if ($eventNameMapped) {
    $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName} = $eventNameMapped;
  } else {
    delete $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName};
  };
};

# see if an event name should be exchanged (if mapped)
sub
resolveEvent {
  my ($self, $eventName) = @_;
  if (exists($self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName})) {
    $self->SysLog(LOG_DEBUG, '%s resolved as %s ', $eventName, $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName} );
    $eventName = $self->{'.FHLib'}->{STORAGE}->{EVENTMAP}->{$eventName};
  }
  return $eventName;
}

sub
fireEvent {
  my ($self, $eventName, $e) = @_;
  $self->SysLog(LOG_DEBUG, 'event \'%s\'', $eventName);
  if ( ($self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}) and 
    (@{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}}) ) {
    $self->SysLog(LOG_DEBUG, 'retain event \'%s\' ', $self->{NAME}, $eventName);
    push @{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}}, {
      'NAME'  => $eventName,
      'EVENT' => $e,
    };
    return;
  };

  do {
    $eventName = $self->resolveEvent($eventName);
    if (exists($self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName}) && $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName}) {
      my $handlerName = $self->{'.FHLib'}->{'STORAGE'}->{'HANDLER'}->{$eventName};
      $self->doHandler($handlerName, $e);
    } elsif ($self->getParent()) {
      $self->getParent()->fireEvent($eventName, $e);
    } else {
      $self->SysLog(LOG_DEBUG, 'no object to handle event \'%s\' found', $eventName);
    };
    my $t = shift @{$self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'}} if ($self->{'.FHLib'}->{'STORAGE'}->{'EVENTQUEUE'});
    return if ( ! $t );
    $eventName = $t->{'NAME'};
    $e = $t->{'EVENT'};
  } while (1);
};

sub
doHandler {
  my ($self, $handlerName, $e) = @_;
  $self->SysLog(LOG_DEBUG, 'handler \'%s\'', $handlerName);
  #for my $i (0 .. $#args) {
  #  if (ref $args[$i]) {
  #    weaken $args[$i];
  #  }
  #}
  if ( $self->can($handlerName) ) {
    $self->$handlerName($e);
  } else {
    # TODO log
    $self->SysLog(LOG_DEBUG, 'handler \'%s\' not found', $handlerName);
  }
}

###############################################################################
package FHTimer;
use strict;
use warnings;
use utf8;
use Time::HiRes qw ( time );
use Scalar::Util qw( weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( CoreAsync );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onTimer' => 'defaultTimer',
  );
   
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
  
  #$self->{'TIMER'} = Time::HiRes::time()+10;
  $self->Item('DELAY') = $args{'DELAY'} if exists $args{'DELAY'};
  return $self;
};

sub
start {
  my ($self, %args) = @_;
  # TODO if running restart
  $self->Item('DELAY') = $args{'DELAY'} if exists $args{'DELAY'};
  $self->Item('DELAY') //= 0; #/
  $self->{'TIMER'} = Time::HiRes::time() + $self->Item('DELAY');
  
  if ($self->getParent() and $self->getParent()->can('setTimer')) {
    $self->getParent()->setTimer($self);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setTimer, no ancestor is capable');
  };
  return $self;
};  
  
#sub 
#setTimer {
#  my ($self, $elemTimer) = @_;
#  if ($self->getParent() and $self->getParent()->can('setTimer')) {
#    $self->getParent()->setTimer($elemTimer);
#  } else {
#    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setTimer, no ancestor is capable');
#  }
#};

sub
cancelTimer {
};

sub
doTimer {
  my ($self) = @_;
  $self->fireEvent('onTimer');
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'timeout %s', $self->getName() );
  $self->getParent()->removeElement($self);
};

###############################################################################
package Base;
use strict;
use warnings;
use utf8;
use Time::HiRes qw ( time );
use Scalar::Util qw( weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( CoreAsync );

sub
setIOSelect {
  my ($self, $elemIO) = @_;
  if ($self->getParent() and $self->getParent()->can('setIOSelect')) {
    $self->getParent()->setIOSelect($elemIO);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setIOSelect, no ancestor is capable');
  }
}

sub
removeIOSelect {
  my ($self, $elemIO) = @_;
  if ($self->getParent() and $self->getParent()->can('removeIOSelect')) {
    $self->getParent()->removeIOSelect($elemIO);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'removeIOSelect, no ancestor is capable');
  }
}

sub 
setTimer {
  my ($self, $elemTimer) = @_;
  if ($self->getParent() and $self->getParent()->can('setTimer')) {
    $self->getParent()->setTimer($elemTimer);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setTimer, no ancestor is capable');
  }
}

##############################################################################
# interface to system methods
# all of those generic methods calling PARENT, 
# in trust that that can do that.
##############################################################################
package GenSys;
use strict;
use warnings;
use FHCore qw( :all );

# The IO Element need to implement some basic behaviour as required by
# fhem %select. FHLib IO Elements implement an directWriteFn and directReadFn
# as the only iface.
sub
setIOSelect {
  my ($self, $elemIO) = @_;
  print "setIOSelect self: $self->{'.FHLib'}->{CLID} \n";
  if ($self->getParent() and $self->getParent()->can('setIOSelect')) {
    $self->getParent()->setIOSelect($elemIO);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setIOSelect, no ancestor is capable');
  }
}

sub
removeIOSelect {
  my ($self, $elemIO) = @_;
  if ($self->getParent() and $self->getParent()->can('removeIOSelect')) {
    $self->getParent()->removeIOSelect($elemIO);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'removeIOSelect, no ancestor is capable');
  }
}

# The IO Element need to implement some basic behaviour as required by
sub 
setTimer {
  my ($self) = @_;
  if ($self->getParent() and $self->getParent()->can('setTimer')) {
    #$self->getParent()->setTimer($elemIO);
  } else {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'setTimer, no ancestor is capable');
  }
}

sub
removeTimer {
}

sub 
doLogging {
  my ($self) = @_;
}


###############################################################################
# listen at given port and accept incomming connections

package GenListener;
use strict;
use warnings;
use Socket qw( :DEFAULT inet_pton :addrinfo );
use Fcntl;
use Scalar::Util qw( weaken openhandle );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onConnect'     =>  'defaultConnect',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );
  
  $self->{directReadFn} = sub {
    my ($self) = @_;
    $self->fireEvent('onConnect', {
      'FH' => $self->{FH},
    });
  };
  
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  }
  $self->Item('IP') = $args{'IP'} if exists $args{'IP'};
  $self->Item('PORT') = $args{'PORT'} if exists $args{'PORT'};
  return $self;
}

sub
listen {
  my ($self, %args) = @_;
  
  $self->Item('IP') = $args{'IP'} if exists $args{'IP'};
  $self->Item('PORT') = $args{'PORT'} if exists $args{'PORT'};
    
  my $port = $self->Item('PORT');
  my $server_ip = $self->Item('IP');
  
  my $socket;
  my $res = socket($socket, PF_INET, SOCK_STREAM, scalar getprotobyname('tcp'));
  # http://flylib.com/books/en/3.214.1.37/1/
  setsockopt($socket, SOL_SOCKET, SO_REUSEADDR,1) or print "setsockopt $! \n";
  my $flags = fcntl($socket, F_GETFL, 0) or print ("fcntl: $!");
  fcntl ($socket, F_SETFL, $flags | O_NONBLOCK) or print ("fcntl: $!");
  bind ($socket, pack_sockaddr_in($port, inet_aton($server_ip)));
  listen ($socket, SOMAXCONN);
  $self->SysLog(LOG_DEBUG, 'listen at %s:%s', $server_ip, $port);
  
  $self->{FH} = $socket;
  $self->{FD} = $self->{FH}->fileno() if $self->{FH};
  $self->enableIO();
  return $self;
}

sub
defaultConnect {
  my ($self, $event) = @_;
  my $client;
  accept ($client, $event->{FH});
  if (!openhandle($client)) { # shutdown, sig, ...
    $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'connect called with closed fh');
    return;
  };
  my $flags = fcntl($client, F_GETFL, 0) || print ("fcntl: $!");
  fcntl ($client, F_SETFL, $flags | O_NONBLOCK) || print ("fcntl: $!");
  my $remote = getpeername($client);
  my ($rport, $iaddr) = sockaddr_in($remote);
  #my $rhost = gethostbyaddr($iaddr, AF_INET); # TODO rewrite getaddrinfo
  my $rstraddr = inet_ntoa($iaddr);
  $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'incoming connection from %s:%s', $rstraddr, $rport);
  $self->fireEvent('onConnection', {
    'FH' => $client,
    'REMOTE_HOST' => $rstraddr,
    'REMOTE_PORT' => $rport,
  });
}

sub enableIO {
  my ($self) = @_;
  $self->setIOSelect($self);
  return $self;
};

sub disableIO {
  my ($self) = @_;
  $self->removeIOSelect($self);
  return $self;
};
  
  
###############################################################################
# non blocking connect

package GenConnect;
use strict;
use warnings;
use utf8;
use Socket qw( :DEFAULT inet_pton :addrinfo );
use Fcntl;
use Scalar::Util qw( weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onConnect'     =>  'defaultConnect',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );
      
  # raw read
  $self->{directWriteFn} = sub {
    my ($self) = @_;
    #weaken $self; #TODO required ?   
    my $option = getsockopt($self->{FH}, SOL_SOCKET, SO_ERROR);
    $self->removeIOSelect($self);
    if (0 != ($! = unpack('i', $option))) {
      $self->SysLog (EXT_DEBUG|LOG_ERROR, 'connect to %s:%s ERROR %s', $self->Item('IP'), $self->Item('PORT'), $!);
      #$self->removeIOSelect($self);
      $self->fireEvent('onError', {});
      return;
    }
    $self->fireEvent('onConnect', {
      'FH' => $self->{'FH'},
      'REMOTE_HOST' => $self->Item('IP'),
      'REMOTE_PORT' => $self->Item('PORT'),
    });
  };

  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
  $self->Item('IP') = $args{'IP'} if exists $args{'IP'};
  $self->Item('PORT') = $args{'PORT'} if exists $args{'PORT'};
  return $self;
}

sub
connect {
  my ($self, %args) = @_;
  
  my $socket;
  my $res;
  
  $self->Item('IP') = $args{'IP'} if exists $args{'IP'};
  $self->Item('PORT') = $args{'PORT'} if exists $args{'PORT'};
  
  my $ip = $self->Item('IP');
  my $port = $self->Item('PORT');
  
  if (! $ip or ! $port) {
    $self->fireEvent('onError', {});
    return;
  };
  
  $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'connect to %s:%s', $ip, $port);
  #my $ip = '127.0.0.1';
  #my $ip = '54.221.212.171'; # httpbin
  #my $ip = '216.58.205.227'; # google
  #my $ip = '104.31.86.157'; # jsonplaceholder.typicode.com
  
  #print "\n***********************************************************\n";
  #eval {
  #  print "$ip\n";
  #  $ip = inet_aton('sonplaceholder.typicode.com');
  #  print "[$ip]\n";
  #  $ip = gethostbyname('jsonplaceholder.typicode.com');
  #  $ip = inet_ntoa($ip);
  #  print $ip;
  #} or print $@;
  #print "\n***********************************************************\n";
  
  use Data::Dumper;
  $res = socket($socket, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
  $self->{FH} = $socket;
  $self->{FD} = $socket->fileno(); #if $args{FH};
  # set the socket to non-blocking mode  
  my $flags = 0;
  $flags = fcntl($socket, F_GETFL, $flags) || die("fcntl: $!");
  fcntl($socket, F_SETFL, $flags | O_NONBLOCK) || die("fcntl: $!");
  if ( ! connect($socket, sockaddr_in($port, inet_pton(AF_INET, $ip))) ) {
    if ($!{EINPROGRESS}) {
      $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'connect to %s:%s EINPROGESS', $ip, $port);
      $self->setIOSelect($self);
      return $self;
    } else {
      $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'connect to %s:%s ERROR %s', $!);
      $self->removeIOSelect($self);
      $self->fireEvent('onError', {});
      return $self;
    }
  }
  self->removeIOSelect($self);
  $self->fireEvent('onConnect', {
    'FH' => $self->{'FH'},
    'REMOTE_HOST' => $self->Item('IP'),
    'REMOTE_PORT' => $self->Item('PORT'),
  });
}

# dummy functions
#sub
#defaultConnect {
#  my ($self, $event) = @_;
#  $self->SysLog(2, "default connection Handler onConnect called");
#  return undef;
#}

#sub
#defaultError {
#  my ($self, $event) = @_;
#  $self->SysLog(2, "default connection Handler onError called");
#  return undef;
#}


###############################################################################
package PosixSerialConnect;
use strict;
use warnings;
use utf8;
use Scalar::Util qw( weaken );
use Fcntl;
use POSIX qw(:termios_h);
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onConnect'     =>  'defaultConnect',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );

  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
  $self->Item('INTERFACE') = $args{'INTERFACE'} if exists $args{'INTERFACE'};
  $self->Item('BAUD') = $args{'BAUD'} if exists $args{'BAUD'};
  return $self;
};

#http://hasyweb.desy.de/services/computing/perl/node138.html
#https://www.cmrr.umn.edu/~strupp/serial.html 
sub connect 
{
  my ($self, %args) = @_;
  
  my %speed = (
    '0' => 	0,
    '50'  => 	1,
    '75'  => 	2,
    '110' => 	3,
    '134' => 	4,
    '150' => 	5,
    '200' => 	6,
    '300' => 	7,
    '600'	=>  8,
    '1200'  => 	9,
    '1800'  => 	10,
    '2400'  => 	11,
    '4800'  => 	12,
    '9600'  => 	13,
    '19200' => 	14,
    '38400' => 	15,
    '57600' => 	4097,
    '115200'  => 	4098,
    '230400'  => 	4099,
    '460800'  => 	4100,
    '500000'  => 	4101,
    '576000'  => 	4102,
    '921600'  => 	4103,
    '1000000' => 	4104,
    '1152000' => 	4105,
    '2000000' => 	4107,
    '2500000' => 	4108,
    '3000000' => 	4109,
    '3500000' => 	4110,
    '4000000' => 	4111,
  );
  
  $self->Item('INTERFACE') = $args{'INTERFACE'} if exists $args{'INTERFACE'};
  my $if = $self->Item('INTERFACE') || '';
  $self->Item('BAUD') = $args{'BAUD'} if exists $args{'BAUD'};
  my $baud = $self->Item('BAUD') || '38400';
  my $portSpeed = (exists($speed{$baud}))?$speed{$baud}:0;
  
  $self->SysLog(EXT_DEBUG|LOG_COMMAND, 'open serial connection %s %s', $if, $baud);
  my $fh;
  if (not sysopen ($fh, $if, O_NONBLOCK|O_RDWR)) {
    $self->fireEvent('onError', {
    });
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open %s failed', $if);
  };
  POSIX::tcflush( fileno($fh), &POSIX::TCIOFLUSH );
  my $term = POSIX::Termios->new;
  if (not $term->getattr(fileno($fh))) {
    $self->fireEvent('onError', {
    });
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'getattr failed');
    return;
  };
  $term->setospeed( $portSpeed );
  $term->setispeed( $portSpeed );
  
  #my $c_iflag = $term->getiflag();
  #$c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  #$term->setiflag ( $c_iflag );
  $term->setiflag( &POSIX::IGNBRK ); 
  
  #my $c_oflag = $term->getoflag();
  #$c_oflag &= ~OPOST;
  $term->setoflag( 0 );
  
  #my $c_lflag = $term->getlflag();
  #print "LFLAG I". $c_lflag +0 . "\n";
  #$c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  #print "LFLAG O". unpack("C", $c_lflag) . "\n";
  $term->setlflag( 0 );
  
  my $c_cflag = $term->getcflag();
  $c_cflag &= ~(CSIZE | PARENB | CSTOPB);
  $c_cflag |= CS8;
  $term->setcflag( $c_cflag );
  
  $term->setattr( fileno($fh), &POSIX::TCSAFLUSH );
  $self->fireEvent('onConnect', {
    'FH'  => $fh,
  });
};

###############################################################################
package SerialConnect;
use strict;
use warnings;
use utf8;
use Scalar::Util qw( weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub new {
  my ($type, %args) = @_;
  return new PosixSerialConnect(%args);
};

###############################################################################
package DirectWriteBindig;
use strict;
use warnings;
use Scalar::Util qw( weaken );
use Tie::Scalar;
our @ISA = qw( Tie::Scalar );

sub
TIESCALAR {
  my ($type, $parent) = @_;
  #use Data::Dumper;
  #print Dumper $parent;
  my $class = ref $type || $type;
  my $self = {};
  $self->{'.FHLib'}->{'PARENT'} = $parent;
  weaken $self->{'.FHLib'}->{'PARENT'};
  $self->{writeFn} = sub {
    my ($self) = @_;
    #weaken $self;    
    $self->fireEvent('onRawWrite', {
      'FH' => $self->{'FH'},
      'OUTBUFFER' => \$self->{'.FHLib'}->{'PARENT'}->Item('OUTBUFFER'),
    });
  };
  bless $self, $class;
}

sub 
FETCH {
  my ($self) = @_;
  return  $self->{'.FHLib'}->{'PARENT'}->Item('OUTBUFFER')?$self->{writeFn}:undef;
}

###############################################################################
package GenIO;
use strict;
use warnings;
use POSIX;
use Fcntl;
use Scalar::Util qw( weaken );
use FHCore qw( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my %events = ( 
    'onRawRead'     =>  'defaultRawRead',
    'onRead'        =>  'defaultRead',
    'onMessage'     =>  'defaultOnMessage',
    'onRawWrite'    =>  'defaultRawWrite',
    'onStreamEnd'   =>  'defaultOnStreamEnd',
    'onDisconnect'  =>  'defaultOnDisconnect',
    'onError'       =>  'defaultOnError',
    'onClose'       =>  'defaultClose',
    'onClosed'      =>  'defaultClosed'
  );
  
  $self->Item('INBUFFER') = '';
  $self->Item('OUTBUFFER') = '';
  $self->Item('DELIMITER') = "\r\n";
  $self->{FH} = $args{FH};
  $self->{FD} = $args{FH}->fileno() if $args{FH};
  $self->nonblock($self->{FH}); # handle vs descriptor
  
  # raw read
  $self->{directReadFn} = sub {
    my ($self) = @_;
    $self->fireEvent('onRawRead', {
      'FH' => $self->{FH},
      'INBUFFER' => \$self->Item('INBUFFER'),
    });
    #$self->fireEvent('onRawRead', $self, $self->{FH}, \$self->{INTERNAL}->{IO}->{BUFFER}->{IN}); # handle, ref buffer
  };
  tie $self->{directWriteFn}, 'DirectWriteBindig', $self;
  
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  }
  if (exists $args{'DELIMITER'}) {
    $self->Item('DELIMITER') = $args{DELIMITER};
  }
  return $self;
}

sub
nonblock {
  my ($self, $fh) = @_;
  my ($flags, $e);   
  $flags = fcntl($fh, F_GETFL, 0) or $e = $!;
  fcntl($fh, F_SETFL, $flags | O_NONBLOCK) or $e = $!;
  return "$self->{NAME}: $e " if defined($e); # TODO
}

sub 
enableIO {
  my ($self) = @_;
  #tie $self->{directWriteFn}, 'DirectWriteBindig', $self;
  $self->setIOSelect($self);
  return $self;
}

sub 
disableIO {
  my ($self) = @_;
  $self->removeIOSelect($self);
  return $self;
}

# 
sub
setDelimiter {
  my ($self, $delimiter) = @_;
  $self->Item('DELIMITER') = $delimiter;
}

sub
defaultRawRead {
  my ($self, $event) = @_;
  my $fh = $event->{FH};
  my $fb = $event->{INBUFFER};
  my $msg;
  my $rv = sysread $fh, $msg, POSIX::BUFSIZ;
  $self->SysLog (LOG_DEBUG, "defaultRawRead '%s'", $msg);
  if (not defined($rv)) {
    if (my $err = $!) {
      $self->fireEvent('onError', {
        'FH' => $self->{'FH'},
        'ERROR' => $err,
      });
    } else {
      $self->fireEvent('onDisconnect', {
        'FH' => $self->{'FH'},
      });
    }
    return;
  } elsif ($rv == 0) {
    $self->fireEvent('onStreamEnd', {
      'FH' => $self->{'FH'},
    });
    return;
  } else {
    $$fb .= $msg;
  }
  #use FHCore::MemWatch -norequire;
  $self->fireEvent('onRead', {
    'INBUFFER' => \$self->Item('INBUFFER'),
    #'D' => new MemWatch(),
  });
}

sub
defaultRead {
  my ($self, $event) = @_;
  my $fb = $event->{INBUFFER};
  
  #my @ascii = unpack("C*", $$fb);
  #print join ':', @ascii;
  #print " (END FB) \n";
  my $d = $self->Item('DELIMITER');
  if ($$fb and ($$fb =~ /(.*)$d(.*)/s)) {
    my $msg = $1; #msg
    $$fb = $2; #remainder
    $self->fireEvent('onMessage', {
      'MESSAGE' => $msg,
    });
    if ($$fb) {
      $self->fireEvent('onRead', {
        'INBUFFER' => $fb,
      });
    }
  }
}

sub
defaultReadNumOctets {
  my ($self, $event) = @_;
  my $fb = $event->{INBUFFER};
  
  if (length($$fb) >= $self->Item('CONTENT-LENGTH')) {
    $self->fireEvent('onMessage', {
      'MESSAGE' => substr ($$fb, 0, $self->Item('CONTENT-LENGTH'), ''),
    });
  }
}

sub
write {
  my ($self, $msg) = @_;
  print "GenIO write: $msg \n";
  $self->Item('OUTBUFFER') .= $msg;
  # TODO return here if IO not enabled
  $self->fireEvent('onRawWrite', {
    'FH' => $self->{'FH'},
    'OUTBUFFER' => \$self->Item('OUTBUFFER'),
  });
  return undef;
}

sub
defaultRawWrite {
  my ($self, $event) = @_;
  my $fh = $event->{'FH'};
  my $fb = $event->{'OUTBUFFER'};
  my $dbgStr = join(' ', unpack("(A2)*", unpack("H*", $$fb)));
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'OUTBUFFER RAW: %s', $dbgStr);
  my $s = syswrite $fh, $$fb;
  print "send $s\n";  
  substr ($$fb, 0, $s) = '';
  return undef;
}

sub
defaultOnStreamEnd {
  my ($self, $event) = @_;
  $self->disableIO;
  $self->fireEvent('onClose', $event);
}

sub
defaultOnDisconnect {
  my ($self, $event) = @_;
  $self->disableIO;
  $self->fireEvent('onClose', $event);
}

sub
defaultOnError {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'IO condition: %s (%s)', $event->{'ERROR'}, $?);
  $self->disableIO;
  $self->fireEvent('onClose', $event);
}

sub
defaultClose {
  my ($self, $event) = @_;
  print "$self->{NAME} defaultClose fire onClosed \r\n";
  #$fh->shutdown(2) if (-S $fh);
  $event->{'FH'}->close;
  $self->fireEvent('onClosed', $event);
}

###############################################################################
package SerialIO;
use strict;
use warnings;
use Fcntl;
use Scalar::Util qw( weaken );
use Symbol qw( gensym );
use FHCore qw( :all );
use Device::SerialPort;
our @ISA = qw( GenIO );

sub 
openInterface {
  my ($self) = @_;
  my $dev = $self->{INTERNAL}->{INTERFACE};
  my $absent = (-e $dev)?'0':'1';
  
  if ($absent) {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'device %s absent', $dev);
    $self->fireEvent('onClosed', undef);
    return undef;
  }
  my $handle = gensym();
  my $po = tie (*$handle, 'Device::SerialPort', $dev);
  if (not $po) {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'error %s opening %s ', $dev, $!);
    $self->fireEvent('onClosed', undef);
    return undef;
  }
  #print "dev $dev is open \n";
  $po->baudrate( $self->{INTERNAL}->{BAUDRATE} );
  $po->databits(8);
  $po->parity("none");
  $po->stopbits(1);
  $po->user_msg('ON'); 
  $po->write_settings;
  $self->fireEvent('onOpened', $handle);
  return $handle;  
}

sub
setUp {
  my ($self, %args) = @_;
  $self->SUPER::setUp(%args);
  $self->{INTERNAL}->{INTERFACE} = $args{INTERFACE};
  $self->{INTERNAL}->{BAUDRATE} = $args{BAUDRATE};
  $self->{INTERNAL}->{DATABITS} = $args{DATABITS};
  $self->{INTERNAL}->{PARITY} = $args{PARITY};
  $self->{INTERNAL}->{STOPBITS} = $args{STOPBITS};
  my $fh = $self->openInterface();
  return undef if (not defined($fh));
  $self->{FH} = $fh;
  $self->{FD} = $fh->fileno();
  return $self;
}

sub
nonblock {
  my ($self, $fh) = @_;
}

sub
defaultRawRead {
  my ($self, $sender, $fh, $fb) = @_;
  my $msg;
  my $dev = $self->{INTERNAL}->{INTERFACE};
  
  my $absent = (-e $dev)?'0':'1';
  if ($absent) {
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'device %s absent', $dev);
    $self->fireEvent('onDisconnect', $sender, $fh);
    return undef;
  }
  my $rv = sysread $fh, $msg, 512; #POSIX::BUFSIZ;
  #my $rv = $fh->read($msg, POSIX::BUFSIZ);
  #main::Log3 (undef, 2, "$self->{NAME}: READ2 $msg");
  if (not defined($rv)) {
    if (my $err = $!) {
      $self->fireEvent('onError', $sender, $fh, $err);
    } else {
      $self->fireEvent('onDisconnect', $sender, $fh);
    }
    return;
  } elsif ($rv == 0) {
    $self->fireEvent('onStreamEnd', $sender, $fh);
    return;
  } else {
    $$fb .= $msg;
  }
  $self->fireEvent('onRead', $sender, $fh, $fb);
}

sub
DESTROY {
  my ($self) = @_;
  $self->disableIO;
  $self->{FH}->close if (defined($self->{FH}));
  $self->SUPER::DESTROY;
}
1;
