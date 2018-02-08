package main;
use strict;
use warnings;
use utf8;
use FHModuleGen;

# avrdude -v -p atmega2560 -c stk500 -P /dev/ttyUSB0 -b 115200 -D -U flash:w:/home/pi/RFLink.cpp.hex:i

Modul->Init(
  thread    => 1,
);

###############################################################################
package RFLink;
use strict;
use warnings;
use utf8;
use FHCore qw( :all ); # import constants
use parent -norequire, qw ( Modul );

sub
setOption {
  my ($self, $option, $value) = @_;
  $self->SysLog(LOG_COMMAND, "define '%s' as '%s'", $option, $value||'');
  if ($option eq 'if') {
    my ($dev, $param) = split '@', $value;
    $self->{INTERFACE} = $dev;
    $self->{'.INTERFACE_PARAM'} = $param;
    #print "if = $dev, p = $param\n";
  } 
}

# def consumend, validate
sub
validateDefinition {
  my ($self) = @_;
  my $name = $self->{NAME};
}

sub run {
  my ($self) = @_;
  
  $self->SysLog(3, "entering runstate 0");
  subscribe('device,.*,test', 'onTest');
  $self->setElement( new FHTimer (
    
  ));
  $self->bindEvent('onDeviceConnect', 'deviceOpened');
  $self->bindEvent('onDeviceOpenError', 'deviceOpenError');
  $self->setElement( new SerialConnect (
    'onConnect' =>  'onDeviceConnect',
    'onError'   =>  'onDeviceOpenError',
  ))->connect();
  #$self->readStream;
  #$self->{'data'} = [1,2,3,['äöüß"',"nl: (\r\n)",'€'],{'k' => 'v'}, 4];
  #$self->writeStream;
}

sub deviceOpened {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev success');
  $self->bindEvent('onMessageIn', 'messageIn');
  $self->setElement( new GenIO (
    'NAME' =>  'RFLINK_DEVICE',
    'FH'   =>  $event->{'FH'},
    'onMessage' => 'onMessageIn',
  ))->enableIO();
};

sub deviceOpenError {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev failed');
};

sub messageIn {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: %s', $event->{'MESSAGE'});
  readingsSingleUpdate($self, 'LAST_IN', $event->{'MESSAGE'}, 1);
};

1;
