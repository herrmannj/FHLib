package FHLayer;
use strict;
use warnings;
use utf8;
use Sys::Hostname;
use lib './FHEM';
use FHCore qw( :all );

sub
import {
  my ($lib, @param) = @_; # main or thread
  my $c = caller(); # TODO return if $c ne 'modul';
   
  # should not happen:
  if (exists($main::defs{'distributor'})) {
    main::Log3(undef, 1, "distributor already installed");
    return;
  };
  
  my $host = (exists($ENV{'FHLIB_HOOST'}) and $ENV{'FHLIB_HOOST'})?$ENV{'FHLIB_HOOST'}:hostname;
  my $distributor = $main::defs{'distributor'} =  new FHDistributor((
    'NAME'  => 'distributor',
    'HOST'  =>  $host,
  ));
  # my $Connector = $distributor->setElement(new FHConnector((
  #  'NAME'  => 'FHConnector'
  # )));
  return;
  # TODO   
  #print "import from $c called \n";
  $ENV{'FHLIB_PORT'} = '49152';
  local $SIG{CHLD} = 'IGNORE';
  my $pid = fork();
  #warn "unable to fork: $!" unless defined($pid);
  if (!$pid) {  # child
    use POSIX();
    #setpgrp(0,0);
    print "$^X is perl \n";
    exec('#perl fhem_thread.pl threadfactory') or do {
      POSIX::_exit(0);
    };
  };
};

###############################################################################
# 
###############################################################################
package FHDistributor;
use strict;
use warnings;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my @c = caller(); # TODO return if $c ne 'modul';
  #print Data::Dumper->new([$self],[qw(FHMultiplexer)])->Indent(1)->Quotekeys(1)->Dump;
  $self->{NAME} = 'distributor';
  $self->{TYPE} = 'Distributor';
  $self->{STATE} = 'Initialized';
  $self->{NR} = $main::devcount++;;
  $self->{DEF} = 'no definition';
  $self->{HOST} = $args{'HOST'};
  $self->{TEMPORARY} = 1;
  #
  $main::modules{'Distributor'}{ORDER} = -1;
  $main::modules{'Distributor'}{LOADED} = 1;
  $main::modules{'Distributor'}{'ShutdownFn'} = 'FHDistributor::shutdown';
  
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  
  my %events = ( 
    'onlocalDeviceStored'       =>  'localDeviceStored',
    'onlocalInternalStored'     =>  'localInternalStored',
  );
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
  $self->{'.FHLib'}->{'DEFER'} = 0;
  # TODO $self->{'.FHLib'}->{'DEVICESTORE'} = tie (%main::defs, 'DeviceStorage', $self, \%main::defs);
  
  $self->bindEvent('onConnection', 'newConnection');
  # sent by FHIPC if new connections arrive
  $self->bindEvent('connecting', 'connectGate');
};

#TODO notice, maybe we should catch the event instead
sub
shutdown {
  my ($self) = @_;
  
  # inform far end about shutdown
  # we switch to blocking conversation cause fhem wont wait otherwise
  #if (my $fh = $self->getElementByName('FHConnector')->Item('FH')) {
  #  my $s = syswrite $fh, "{\"cmd\": \"SHUTDOWN\"}\r\n";
  #};
  # wait for ack  
  return;
};

# listener accept, create new connection
sub
newConnection {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'MAIN CONN new connection from %s:%s', $event->{'REMOTE_HOST'}, $event->{'REMOTE_PORT'});
  $self->Item('FH') = $event->{'FH'};
  $self->setElement( new FHIPCResponder (
    'FH'  => $event->{'FH'},
    'NAME' => '.FHCONN_'.$event->{'REMOTE_HOST'}.'_'.$event->{'REMOTE_PORT'},
  ));
};

# receives FHIPC CONNECT event
# approve or deny, set up routes and call the callback (APPROVED, DENIED, ERROR)
# for now each conn is ok
sub
connectGate {
  my ($self, $event) = @_;
  # test if incoming connection is approved. here it is
  my $o = $event->{'self'}->can($event->{'approved'});
  $o->($event->{'self'}, {});
};

# one connection subsripe one topic / channel
# 'topic'
# 

sub
addChannelSubscription {
  my ($self, $channelName) = @_;
  my $a = $self->Item('ChannelReceiver')->{$channelName};
  
};

sub pushToChannel {
  my ($self, $channel, $data) = @_;
  # channel 2 subscriber mapping exit ?
  #if exists($csm->{$channel}) {
  #  my $s = $csm->{$channel};
  #  foreach my $rcv (keys %$s) {
      # send
  #  };
  #} else {
  #  foreach my $k (keys %$sc) {
  #  };
  #};
};

###########################################################

# begin of modify
sub
alter {
  my ($self) = @_;
  return if ($self->Item('ALTER'));
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'device transaction begin');
  $self->Item('ALTER') = 1;
  main::InternalTimer(0, 'FHDistributor::commit', $self, 0);
  return;
};

sub
commit {
  my ($self) = @_;
  $self->Item('ALTER') = undef;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'device transaction commit');
};

sub
setIOSelect {
  my ($self, $elemIO) = @_;
  my $s = '.FHLib_'.$elemIO->getCLID();
  $main::selectlist{$s} = $elemIO;
};

sub
removeIOSelect {
  my ($self, $elemIO) = @_;
  my $s = '.FHLib_'.$elemIO->getCLID();
  delete $main::selectlist{$s};
};

sub 
setTimer {
 my ($self, $elemTimer) = @_;
 my $pkg = blessed ($elemTimer);
 my $fn = defined($pkg)?$pkg.'::doTimer':'doTimer';
 my $tim = $elemTimer->{'TIMER'};
 main::InternalTimer($tim, $fn, $elemTimer);
};

###############################################################################
sub
localDeviceStored {
  my ($self, $event) = @_;
  #use Data::Dumper;
  #print Data::Dumper->new([$event],[qw(device)])->Indent(1)->Quotekeys(1)->Dump;
  use FHPLib;
  my $json = $self->getElementByName('StreamWriter')->parse($event);
  print $json;
  print "\n";
  
};

sub
localInternalStored {
  my ($self, $event) = @_;
  #use Data::Dumper;
  #print Data::Dumper->new([$event],[qw(device)])->Indent(1)->Quotekeys(1)->Dump;
  use FHPLib;
  my $json = $self->getElementByName('StreamWriter')->parse($event);
  print $json;
  print "\n";
};

###############################################################################
# 
###############################################################################
package FHConnector;
use strict;
use warnings;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use FHPLib;
use FHIPC;
use parent -norequire, qw ( Base );

sub
start {
  my ($self) = @_;
  $self->setElement( new GenListener (
    'NAME' => 'Listener',
  ))->listen(
    'IP' => '127.0.0.1',
    'PORT' => '49152', # https://stackoverflow.com/questions/8748396/ipc-port-ranges
  );
  # TODO move away to thread factory fork
  $self->setElement( new FHTimer (
    'onTimer' => 'onConnectionTimeout',
  ));
  $self->bindEvent('onConnectionTimeout', 'ConnectionTimeout');
  return $self;
};

sub
ConnectionTimeout {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'thread factory connection timeout');
};

###############################################################################
# represent a single readinsg pair
###############################################################################
package ReadingsPair;
use strict;
use warnings;
use utf8;
use lib './FHEM';
use Scalar::Util qw( blessed refaddr weaken );
use Tie::Hash;
use FHCore qw ( :all );
use base qw( Tie::StdHash Base );

sub TIEHASH  {
  my ($class, $parent, $readings, $device, $name) = @_;
  my $self = bless {}, $class;
  
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  $self->{'.FHLib'}->{'DEFER'} = 0; 
  $self->{NAME} = $device.'_'.$name.'_ReadingsPair';
  $self->{DEVICE} = $device;
  
  foreach my $key (keys %{$readings}) {
    $self->STORE($key, $readings->{$key});
  };
  
  return $self;
};

sub STORE    {
  use Data::Dumper;
  my ($self, $key, $value) = @_;
  print "ReadingsStore $self->{NAME} key $key \n";
  print Data::Dumper->new([$value],[qw(ReadingsPair)])->Indent(1)->Quotekeys(1)->Dump;
  #main::Log3 (undef, 3, "readings pair $self->{DEVICE} R:$self->{NAME}: create key [$key] as [".($value or '<UNDEF>')."] -> ". (ref $value or 'SCALAR') );
  if (ref $value eq 'HASH') {
    #print Dumper $value;
  }
  $self->{readings}->{$key} = $value;
  
  if (UNIVERSAL::isa($value, 'HASH' )) {
    my $node = {}; # temporary copy
    foreach my $k (keys %{$value}) {
      $node->{$k} = $_[2]->{$k};
    }
  }
}

sub 
FETCH {
  my ($self, $key) = @_;
  if (exists $self->{readings}->{$key}) {
    my $value = $self->{readings}->{$key};
    #main::Log3 (undef, 3, "local device $self->{NAME}: fetch key [$key] as [$value] -> ". ref $value);
    return $value;
  } else {
    main::Log3 (undef, 3, "readings pair $self->{DEVICE}: fetch NONEXISTENT key [$key]");
    return undef;
  }
}

sub
DELETE {
  my ($self, $key) = @_;
  main::Log3 (undef, 3, "readings pair $self->{DEVICE}: delete key $key");
  delete $self->{readings}->{$key};
}

sub
CLEAR {
  my ($self) = @_;
  main::Log3 (undef, 3, "readings pair $self->{DEVICE}: clear");
} 

sub
EXISTS {
  my ($self, $key) = @_;
  #main::Log3 (undef, 3, "local device $self->{NAME}: exists $key");
  return exists $self->{readings}->{$key};
}

sub
FIRSTKEY {
  my ($self) = @_;
  my $tmp = keys %{$self->{readings}};  # reset each() iterator
  each %{$self->{readings}};
}

sub
NEXTKEY {
  my ($self) = @_;
  each %{$self->{readings}};
}

###############################################################################
# readings sub group
###############################################################################
package ReadingsStore;
use strict;
use warnings;
use utf8;
use lib './FHEM';
use Scalar::Util qw( blessed refaddr weaken );
use Tie::Hash;
use FHCore qw ( :all );
use base qw( Tie::StdHash Base );

sub TIEHASH  {
  my ($class, $parent, $readings, $device) = @_;
  my $self = bless {}, $class;
  
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  $self->{'.FHLib'}->{'DEFER'} = 0; 
  $self->{NAME} = $device.'_ReadingsStore';
  $self->{DEVICE} = $device;
  
  foreach my $key (keys %{$readings}) {
    $self->STORE($key, $readings->{$key});
  };
  return $self;
};

sub STORE    {
  use Data::Dumper;
  my ($self, $key, $value) = @_;
  print "ReadingsStore $self->{NAME} key $key \n";
  print Data::Dumper->new([$value],[qw(ReadingsStore)])->Indent(1)->Quotekeys(1)->Dump;
  #main::Log3 (undef, 3, "readings store $self->{DEVICE}: create key [$key] as [".($value or '<UNDEF>')."] -> ". (ref $value or 'SCALAR') );
  tie (%{$value}, 'ReadingsPair', $self, $value, $self->{DEVICE}, $key);
  $self->{readings}->{$key} = $value;
};

sub 
FETCH {
  my ($self, $key) = @_;
  if (exists $self->{readings}->{$key}) {
    my $value = $self->{readings}->{$key};
    #main::Log3 (undef, 3, "local device $self->{NAME}: fetch key [$key] as [$value] -> ". ref $value);
    return $value;
  } else {
    main::Log3 (undef, 3, "readings store $self->{DEVICE}: fetch NONEXISTENT key [$key]");
    return undef;
  };
};

sub
DELETE {
  my ($self, $key) = @_;
  #main::Log3 (undef, 3, "readings store $self->{DEVICE}: delete key $key");
  delete $self->{readings}->{$key};
}

sub
CLEAR {
  my ($self) = @_;
  #main::Log3 (undef, 3, "readings store $self->{DEVICE}: clear");
} 

sub
EXISTS {
  my ($self, $key) = @_;
  #main::Log3 (undef, 3, "local device $self->{NAME}: exists $key");
  return exists $self->{readings}->{$key};
}

sub
FIRSTKEY {
  my ($self) = @_;
  my $tmp = keys %{$self->{readings}};  # reset each() iterator
  each %{$self->{readings}};
}

sub
NEXTKEY {
  my ($self) = @_;
  each %{$self->{readings}};
}

sub 
DESTROY {
  my ($self) = @_;
  print "local device $self->{NAME} ReadingsStore gone ...\n";
}

###############################################################################
# represent local device level
# supply internals
###############################################################################
package LocalDevice;
use strict;
use warnings;
use utf8;
use lib './FHEM';
use Scalar::Util qw( blessed refaddr weaken );
use Tie::Hash;
use FHCore qw ( :all );
use base qw( Tie::StdHash Base );

sub TIEHASH  {
  my ($class, $parent, $device, $name) = @_;
  my $self = bless {}, $class;
  
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  $self->{'.FHLib'}->{'DEFER'} = 0; 
  $self->{NAME} = $name;

  foreach my $key (keys %{$device}) {
    $self->STORE($key, $device->{$key});
  }
  return $self;
}

sub STORE    {
  use Data::Dumper;
  my ($self, $key, $value) = @_;
  $self->getRootElement()->alter();
  #print "ALTER\n";
  #main::Log3 (undef, 3, "local device $self->{NAME}: create key [$key] as [".($value or '<UNDEF>')."] -> ". (ref $value or 'SCALAR') );
  my $action = (exists $self->{localDevice}->{$key})?'modify':'create';
  #print "LOCAL STORE DEVICE INTERNAL $key ; $value (".(ref $value).")\n";
  if (!ref $value) {
    #print "FIRE EVENT \n";
    $self->fireEvent('onlocalInternalStored', {
      'DEVICE'  =>  $self->{'NAME'},
      'NAME'    =>  $key,
      'VALUE'   =>  $value,
      'ACTION'  =>  $action,
    });
  } elsif ($key eq 'READINGS') {
    tie (%{$value}, 'ReadingsStore', $self, $value, $self->{NAME});
  };
  if (($key eq 'CHANGED') and (ref $value eq 'ARRAY')) {
    print "STORE CHANGED\n";
    print Dumper $value;
  };
  return $self->{'localDevice'}->{$key} = $value;
};

sub 
FETCH {
  my ($self, $key) = @_;
  if (exists $self->{localDevice}->{$key}) {
    my $value = $self->{localDevice}->{$key};
    #main::Log3 (undef, 3, "local device $self->{NAME}: fetch key [$key] as [$value] -> ". ref $value);
    return $value;
  } else {
    main::Log3 ('FHLayer', 1, "local device $self->{NAME}: fetch NONEXISTENT key [$key]");
    return if ($key ne 'room');     
     use Devel::StackTrace;
     my $trace = Devel::StackTrace->new;
     print $trace->as_string; # like carp

    # from top (most recent) of stack to bottom.
    #while ( my $frame = $trace->next_frame ) {
    #  print "Has args\n" if $frame->hasargs;
    #}
    #main::Log3 ('FHLayer', 5, "local device $self->{NAME}: fetch NONEXISTENT key [$key]");
    return undef;
  }
}

sub
DELETE {
  my ($self, $key) = @_;
  #main::Log3 ('FHLayer', 4, "local device $self->{NAME}: delete key $key");
  if ($key eq 'CHANGED') {
    print "DELETE CHANGED\n";
    print Dumper $self->{localDevice}->{$key};
  }
  delete $self->{localDevice}->{$key};
}

sub
CLEAR {
  my ($self) = @_;
  #main::Log3 ('FHLayer', 5, "local device $self->{NAME}: clear");
} 

sub
EXISTS {
  my ($self, $key) = @_;
  #main::Log3 (undef, 3, "local device $self->{NAME}: exists $key");
  return exists $self->{localDevice}->{$key};
}

sub
FIRSTKEY {
  my ($self) = @_;
  my $tmp = keys %{$self->{localDevice}};  # reset each() iterator
  each %{$self->{localDevice}};
}

sub
NEXTKEY {
  my ($self) = @_;
  each %{$self->{localDevice}};
}

sub 
DESTROY {
  my ($self) = @_;
  print "local device $self->{NAME} gone ...\n";
  #use Data::Dumper;
  #print Data::Dumper->new([$self],[qw( LOCALDEVICE_A )])->Indent(1)->Quotekeys(1)->Dump;
  #print Data::Dumper->new([$main::defs{$self->{NAME}}],[qw( LOCALDEVICE_B )])->Indent(1)->Quotekeys(1)->Dump;
};

###############################################################################
# %defs
###############################################################################
package DeviceStorage;
use strict;
use warnings;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use Tie::Hash;
use FHCore qw( :all );
use base qw( Tie::StdHash Base );

sub TIEHASH  {
  my ($class, $parent, $defs) = @_;
  my $self = bless {}, $class;
  
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  $self->{'.FHLib'}->{'DEFER'} = 0;
  
  foreach my $dev (keys %{$defs}) {
    $self->STORE($dev, $defs->{$dev});
  }
  return $self;
}

sub STORE    {
  use Data::Dumper;
  my ($self, $key, $value) = @_;
  $self->getRootElement()->alter();
  print "BEGIN OF DEVICE STORAGE\n";
  #print "ALTER\n";
  #main::Log3 ('FHLayer', 3, "device storage: create device [$key] -> ". (ref $value or 'SCALAR') .' :'.$value );
  #$self->SysLog(LOG_COMMAND, "E:'NEW DEV', N:'%s', T:'%s'", $value->{NAME}, $value->{TYPE});
  my $action = (exists $self->{localDevice}->{$key})?'modify':'create';
  $self->fireEvent('onlocalDeviceStored', {
    'DEVICE'  =>  $key,
    'ACTION'  =>  $action,
    #'DEV'   =>  $value,
  });
  # convert to local device
  tie (%{$value}, 'LocalDevice', $self, $value, $key);
  print "END OF DEVICE STORAGE\n";
  return $self->{localDevice}->{$key} = $value;
}

sub 
FETCH {
  my ($self, $key) = @_;
  if (exists $self->{localDevice}->{$key}) {
    my $value = $self->{localDevice}->{$key};
    #main::Log3 (undef, 3, "device storage: fetch device [$key]-> ". ref $value);
    return $value;
  } else {
    main::Log3 ('FHLayer', 4, "device storage: fetch NONEXISTENT device [$key]");
    return undef;
  }
}

sub
DELETE {
  my ($self, $key) = @_;
  return if ($key eq 'distributor');
  main::Log3 ('FHLayer', 4, "device storage: delete device [$key]");
  delete $self->{localDevice}->{$key};
}

sub
CLEAR {
  my ($self) = @_;
  main::Log3 ('FHLayer', 4, "device storage: clear");
}

sub
EXISTS {
  my ($self, $key) = @_;
  main::Log3 (undef, 5, "device storage: exists $key");
  return exists $self->{localDevice}->{$key};
}

sub
FIRSTKEY {
  my ($self) = @_;
  my $tmp = keys %{$self->{localDevice}};  # reset each() iterator
  each %{$self->{localDevice}};
}

sub
NEXTKEY {
  my ($self) = @_;
  each %{$self->{localDevice}};
}


sub 
DESTROY {
  my ($self) = @_;
  #untie %main::defs;
  print "main defs gone ...\n";
}

1;
