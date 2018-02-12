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
    $self->{'INTERFACE'} = $dev;
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
  #subscribe('device,.*,test', 'onTest');
  $self->setElement( new FHTimer (
    
  ));
  $self->bindEvent('onDeviceConnect', 'deviceOpened');
  $self->bindEvent('onDeviceOpenError', 'deviceOpenError');
  $self->setElement( new SerialConnect (
    'NAME'      =>  'RFLINK_CONNECT',
    'onConnect' =>  'onDeviceConnect',
    'onError'   =>  'onDeviceOpenError',
    'INTERFACE' =>  $self->{'INTERFACE'},
    'BAUD'      =>  57600,
  ))->connect();
  #$self->readStream;
  #$self->{'data'} = [1,2,3,['äöüß"',"nl: (\r\n)",'€'],{'k' => 'v'}, 4];
  #$self->writeStream;
}

sub deviceOpened {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev success');
  # TODO error handling, disconnect etc
  $self->bindEvent('onMessageIn', 'firstMessageIn');
  $self->setElement( new GenIO (
    'NAME' =>  'RFLINK_DEVICE',
    'FH'   =>  $event->{'FH'},
    'DELIMITER' => "\r\n",
    'onMessage' => 'onMessageIn',
  ))->enableIO();
};

sub deviceOpenError {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev failed');
};

sub firstMessageIn {
  my ($self, $event) = @_;
  my $msg = $event->{'MESSAGE'};
  # 20;00;Nodo RadioFrequencyLink - RFLink Gateway V1.1 - R48;
  if ($msg =~ m/.*20;00;Nodo RadioFrequencyLink - (.*) - (.*);/g) {
    $self->{'RECEIVER'} = $1;
    $self->{'FIRMWARE'} = $2;
    $self->Item('MSG_COUNTER') = 0;
    $self->bindEvent('onMessageIn', 'messageIn');
    $self->{'STATE'} = 'opened';
    return;
  };
};

sub messageIn {
  my ($self, $event) = @_;
  my $msg = $event->{'MESSAGE'};
  $self->SysLog(EXT_DEBUG|LOG_DEBUG, 'Message: %s', $msg);
  #readingsSingleUpdate($self, 'LAST_IN', $event->{'MESSAGE'}, 1);
  my $e;
  if ( $msg =~ s/20;([[:xdigit:]]+);(.+?);ID=(.+?);(?:SWITCH=([[:xdigit:]]+);)*//) {
  #if ( $msg =~ s/20;([[:xdigit:]]+);(.+?);ID=(.+?);//g) {
    my $counter = $1;
    my $protocoll = $2;
    my $id = $3;
    my $unit = $4;
    $protocoll =~ s/\s/_/g;
    $unit //= '00'; #/
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: counter:%s, proto:%s, id:%s, unit:%s, remainder:%s', $counter, $protocoll, $id, $unit, $msg);
    my $eId = "$protocoll:$id:$unit";
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: eId:%s', $eId);
    # temperature
    if ( $msg =~ s/TEMP=([[:xdigit:]]+);// ) {
      my $temperature = hex($1);
      if ($temperature & 0x8000) {
        $temperature -= 0x8000;
        $temperature *= -1;
      };
      $temperature /= 10;
      $e->{'TEMPERATURE'} = $temperature;
      $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: temperature:%s, remainder:%s', $temperature, $msg);
    };
    if ( $msg =~ s/HUM=(\d+);// ) {
      $e->{'HUMITIDY'} = $1;
      $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: humidity:%s, remainder:%s', $1, $msg);
    };
  };
  print $msg if $msg;
  use Data::Dumper;
  print Dumper $e;
};

1;
