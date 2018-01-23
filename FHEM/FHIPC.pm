package FHIPCResponder;
use strict;
use warnings;
#use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw( :all );
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
  };
  
  my @args_ok = qw ( FH );
  
  foreach my $k (@args_ok) {
    $self->Item($k) = $args{$k} if exists $args{$k};
  };
  
  return $self;
};

sub
start {
  my ($self) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "start IPCRCV0");
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  $self->bindEvent('onMessageIn', 'firstMessage');
  $self->setElement( new GenIO (
    'NAME'      =>  $self->getName().'_connection',
    'FH'        =>  $self->Item('FH'),
    'onMessage' =>  'onMessageIn',
    'onClosed'  =>  'onRemoteClosed',
  ))->enableIO();
  $self->Item('MSGCOUNT_OUT') = 0;
};

sub
firstMessage {
  my ($self, $event) = @_;
  my $msg = $self->getElementByName('StreamReader')->parse($event->{'MESSAGE'});
  use Data::Dumper;
  #print Data::Dumper->new([$msg],[qw(rMessageIn)])->Indent(1)->Quotekeys(1)->Dump;
  $self->SysLog(EXT_DEBUG|LOG_COMMAND, 'received: %s', Data::Dumper->new([$msg],[qw(msg)])->Indent(1)->Quotekeys(1)->Dump);
  $self->fireEvent('connecting', {
    'id'        => $msg->{'id'},
    'auth'      => $msg->{'auth'},
    'approved'  => 'approved',
    'denied'    => 'denied',
    'self'      => $self,
  });
  #$self->SysLog(EXT_DEBUG|LOG_COMMAND, 'IPCRCVROOT: %s', $r);
};

sub
approved {
  my ($self) = @_;
  my $json = $self->getElementByName('StreamWriter')->parse({
    'cmd'   => 'ACK',
    'val'   => '0',
    #'time'  =>  
  });
  $self->getElementByName($self->getName().'_connection')->write($json."\r\n");
  $self->SysLog(EXT_DEBUG|LOG_COMMAND, 'connection approved');
};

package FHIPCInitiator;
use strict;
use warnings;
use utf8;
use lib './FHEM';
use FHCore qw( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  
  my %events = ( 
    'onConnected'   =>  'defaultConnected',
    'onError'       =>  'defaultError',
    'onTimeout'     =>  'defaultTimeout',
  );
  
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
  
  my @args_ok = qw ( IP PORT );
  
  foreach my $k (@args_ok) {
    $self->Item($k) = $args{$k} if exists $args{$k};
  };
  
  return $self;
};

sub
start {
  my ($self) = @_;
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, "start IPCTRX0");
  $self->setElement(new FHJson::StreamWriter(
    'NAME'        =>  'StreamWriter',
  ));
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  $self->bindEvent('onConnection', 'connection');
  $self->setElement( new GenConnect (
    'NAME'      =>  $self->getName().'_connect',
    'IP'        =>  $self->Item('IP'),
    'PORT'      =>  $self->Item('PORT'),
    'onConnect' =>  'onConnection',
  ))->connect();

};

sub
connection {
  my ($self, $event) = @_;
  my $json = $self->getElementByName('StreamWriter')->parse({
    'cmd'   => 'HELO',
    'seq'   =>  $self->Item('MSGCOUNT_OUT')++,
    'id'    =>  'threadfactory',
    'auth'  =>  '01234',
  });
  $self->bindEvent('onMessageIn', 'firstMessage');
  $self->setElement( new GenIO (
    'NAME'      =>  $self->getName().'_connection',
    'FH'        =>  $event->{'FH'},
    'onMessage' =>  'onMessageIn',
    'onClosed'  =>  'onRemoteClosed',
  ))->enableIO()->write($json."\r\n");
};

sub
firstMessage {
  my ($self, $event) = @_;
  my $msg = $self->getElementByName('StreamReader')->parse($event->{'MESSAGE'});
  use Data::Dumper;
  #print Data::Dumper->new([$msg],[qw(rMessageIn)])->Indent(1)->Quotekeys(1)->Dump;
  $self->SysLog(EXT_DEBUG|LOG_COMMAND, 'received: %s', Data::Dumper->new([$msg],[qw(msg)])->Indent(1)->Quotekeys(1)->Dump);
  $self->fireEvent('onConnected', {
    'TIME' => 'approved',
  });
  #$self->SysLog(EXT_DEBUG|LOG_COMMAND, 'IPCRCVROOT: %s', $r);
};


1;
