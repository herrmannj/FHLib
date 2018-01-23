package Modul;
#use strict;
#use warnings;
#use Scalar::Util qw( weaken );
#use utf8;
#require FHCore;
#use FHLayer qw( Test );

use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use FHLayer qw( Test );
use parent -norequire, qw ( CoreAsync );

#our @ISA = qw( Core Handler Timer );
#our @ISA = qw( Core );

sub
Init {
  my ($p, $fname, $line) = caller;
  my $name = getModuleName($fname);
  main::Log3 (undef, 1, "modul $name Init");
  my $_Define = sub {
    my ($hash, $def) = @_;
    my ($devName, $devType, $options) = split(/ /, $def, 3);
    # convenient interface to legacy methods
    my $_Log3 = sub {
      my ($n, $v, $msg) = @_;
      main::Log3($n, $v, $msg);
    };
    {no strict 'refs'; *{$name.'::Log3'} = $_Log3;}
    my $_readingsSingleUpdate = sub {
      my ($hash, $reading, $value, $dotrigger)= @_;
      main::readingsSingleUpdate($hash, $reading, $value, $dotrigger);
    };
    {no strict 'refs'; *{$name.'::readingsSingleUpdate'} = $_readingsSingleUpdate;}
###############################################################################
    my $o = new $name($hash);
    print "create loader $name ::subscribe 000\n";
    { no strict 'refs'; 
      print "create loader $name ::subscribe \n";
      *{$name.'::subscribe'} = sub {
        my ($channel, $event) = @_;
        $o->subscribe($channel, $event);
      };
    }
    # consume options
    while ($options && ((my $option, $options) = split /\s/, $options, 2)) {
      $o->configure($option, $options);
    }
    $o->validateDefinition();
    # TODO return any errors, if ref $o = string -> ERROR
    # $main::defs{$devName} = $o;
    # mimic fhem.pl
    %main::ntfyHash = ();
    $o->run() if $main::init_done;
    return undef;
  };
  my $_Undef = sub {
    my ($hash) = @_;
  };
  
  my $_Notify = sub {
    my ($o, $ntfyDev) = @_;
    $o->_eventFn($ntfyDev);
  };
  my $_Get = sub {
    my ($o, $devName, $getName, @options) = @_;
    $o->_doGet($getName, @options);
  };
  my $_Set = sub {
    my ($o, $devName, $setName, @options) = @_;
    $o->_doSet($setName, @options);
  };
  my $_fwDetail = sub {
    my ($FW_wname, $device, $FW_room) = @_;
    my $o = $main::defs{$device};
    $o->_doFwDetail($FW_wname, $device, $FW_room);
  };
  my $_Init = sub {
    my ($hash) = @_;
    main::Log3 (undef, 1, "Modul ($name) Initialize");
    $hash->{DefFn}        = $name.'_Define';
    $hash->{UndefFn}      = $name.'_Undef';
    $hash->{NotifyFn}     = $name.'_Notify';
    $hash->{GetFn}        = $name.'_Get';
    $hash->{SetFn}        = $name.'_Set';
    $hash->{FW_detailFn}  = $name.'_fwDetail';
    # TYPE specific
    # physical, 
    
    {no strict 'refs'; 
      *{'main::'.$name.'_Define'}   = sub {
        my ($hash, $def) = @_;
        my ($devName, $devType, $options) = split(/ /, $def, 3);
        my $o = new $name($hash);
        %main::ntfyHash = ();
        { no strict 'refs'; 
          print "create loader $name ::subscribe \n";
          *{$name.'::subscribe'} = sub {
            my ($channel, $event) = @_;
            $o->_subscribe($channel, $event);
          };
        }
        $o->run() if $main::init_done;
        return;
      };
      *{'main::'.$name.'_Undef'}    = sub {
        my ($hash) = @_;
        print "undef $hash->{NAME} ... \n";
        return;
      };
      #*{'main::'.$name.'_Undef'}    = $_Undef;
      *{'main::'.$name.'_Get'}      = $_Get;
      *{'main::'.$name.'_Notify'}   = $_Notify;
      #*{'main::'.$name.'_Notify'}   = sub {
      #  my ($hash) = @_;
      #  print "notify $hash->{NAME} ... \n";
      #};
      *{'main::'.$name.'_Set'}      = $_Set;
      *{'main::'.$name.'_fwDetail'} = $_fwDetail;       
    }
    return;
  };
  {no strict 'refs'; *{'main::'.$name.'_Initialize'} = $_Init;}
  ### various options 
};

sub
new {
  my ($type, $hash) = @_;
  my $class = ref $type || $type;
  my $name = $hash->{NAME};
  $hash->{'.FHLib'}->{'CLID'} = refaddr ($hash); # context local ID
  $hash->{'.FHLib'}->{'DEFER'} = 0;
  bless $hash, $class;
}

###############################################################################
# gen sys functions
sub
doSysLog {
  my ($self, $verbose, $message, @args) = @_;
  $verbose &= 0x0F;
  main::Log3($self, $verbose, sprintf($message, @args));
  return;
}

sub 
setTimer {
 my ($self, $elemTimer) = @_;
 my $pkg = blessed ($elemTimer);
 my $fn = defined($pkg)?$pkg.'::doTimer':'doTimer';
 my $tim = $elemTimer->{'TIMER'};
 main::InternalTimer($tim, $fn, $elemTimer);
};

sub
configure {
  my ($self, $option, $options) = @_;
  my ($k, $v) = split(/=/, $option);
  $self->setOption($k, $v);
}

sub
setOption {
  my ($self, $option, $value) = @_;
}

# def consumend, validate
sub
validateDefinition {
  my ($self) = @_;
}

sub
run {
  my ($self) = @_;
  $self->SysLog(LOG_COMMAND, 'enter run');
  
}

sub
_doGet {
  my ($self, $getName, @options) = @_;
  print "get called with $getName @options \n";
  if ($getName eq 'webif-data') {
    use Data::Dumper;
    my $s = $options[0];
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/eg; # später
    #utf8::decode($s);
    #binmode(STDOUT, ":encoding(utf8)");
    my $e =  Encode::decode('UTF-8', $s); # OUTSIDE WORLD TO PERL !!!
    no warnings 'utf8';
    print "utf: $e \n";
    #main::Log3 (undef, 1, $e);
    #main::Log3 (undef, 1, length $e);
    #main::Log3 (undef, 1, "我我");
    #main::Log3 (undef, 1, length "我我");
    return undef;
  }
}

sub
_doSet {
  my ($self, $setName, @options) = @_;
  if (exists($self->{INTERNAL}->{SETLIST}->{$setName})) {
    my $proc = $self->{INTERNAL}->{SETLIST}->{$setName}->{PROC};
    return $self->$proc(@options);
  } else {
    my $ret;
    foreach my $k (keys %{$self->{INTERNAL}->{SETLIST}}) {$ret .=" $k"};
    return ($ret)?"unknown set $setName, choose one of$ret":undef;
  }
}

sub 
addSet {
  my ($self, $setName, $setProcedure) = @_;
  $self->{INTERNAL}->{SETLIST}->{$setName}->{PROC} = $setProcedure; # TODO $self-can(...
}

sub
_eventFn {
  my ($self, $ntfyDev) = @_;
  foreach my $event (@{$ntfyDev->{CHANGED}}) {
    my @e = split(' ', $event);
    next unless defined($e[0]);
    $self->SysLog(LOG_COMMAND, 'EVENTFN %s', $ntfyDev->{NAME});
    if ($ntfyDev->{TYPE} eq 'Global') {
      # system events
      if ($e[0] eq 'INITIALIZED') {
        $self->run();
      } elsif ($e[0] eq 'SHUTDOWN') {
        $self->shutdown();
      }
    }
  }
  return undef;
}

sub
shutdown {
  my ($self) = @_;
  print "SHUTDOWN CALLED \r\n";
}

#https://stackoverflow.com/questions/246801/how-can-you-encode-a-string-to-base64-in-javascript
sub
_doFwDetail {
  my ($self, $FW_wname, $device, $FW_room) = @_;
  return undef;
}

# static
sub
getModuleName {
  my ($fname) = @_;
  $fname =~ m/.*?\/\d{2}_(.+?)\.pm$/;
  my $name = $1;
  return $name;
}

###############################################################################
# API

sub
_subscribe {
  my ($self, $channel, $event) = @_;
  $self->SysLog(LOG_DEBUG, 'subscribe %s EVENT %s', $channel, $event);
}

1;

