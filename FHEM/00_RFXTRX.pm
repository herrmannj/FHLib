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
package RFXTRX;
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
    'NAME'  =>  'RFXTRX_CONNECT_TIMEOUT',
    'DELAY' =>  3,
  ));
  $self->bindEvent('onDeviceConnect', 'deviceOpened');
  $self->bindEvent('onDeviceOpenError', 'deviceOpenError');
  $self->setElement( new SerialConnect (
    'NAME'      =>  'RFXTRX_CONNECT',
    'onConnect' =>  'onDeviceConnect',
    'onError'   =>  'onDeviceOpenError',
    'INTERFACE' =>  $self->{'INTERFACE'},
    'BAUD'      =>  38400,
  ))->connect();
}

sub deviceOpened {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev success');
  # TODO error handling, disconnect etc
  $self->bindEvent('onReadIn', 'readIn');
  $self->setElement( new GenIO (
    'NAME' =>  'RFXTRX_DEVICE',
    'FH'   =>  $event->{'FH'},
    #'DELIMITER' => "\r\n",
    'onRead' => 'onReadIn',
  ))->enableIO();
  sleep(5); # TODO timer
  $self->getElementByName('RFXTRX_DEVICE')->write(pack('C*', 0x0D, (0x00) x 0x0D));
  sleep(1); # TODO timer
  $self->getElementByName('RFXTRX_DEVICE')->write(pack('C*', 0x0D, 0x00, 0x00, 0x01, 0x02, (0x00) x 9));
  $self->getElementByName('RFXTRX_DEVICE')->write(pack('C*', 0x0D, 0x00, 0x00, 0x02, 0x07, (0x00) x 9));
};

sub deviceOpenError {
  my ($self, $event) = @_;
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'open dev failed');
};

sub readIn {
  my ($self, $event) = @_;
  my $fb = $event->{INBUFFER};
  
  my $dbgStr = unpack("H*", $$fb);
  $dbgStr = join(' ', unpack("(A2)*", $dbgStr));
  $self->SysLog(EXT_DEBUG|LOG_ERROR, 'INBUFFER RAW: %s', $dbgStr);
  
  my $plen = ord($$fb);
  while (length($$fb) > $plen) {
    my $raw = substr ($$fb, 0, $plen +1);
    my $hex = unpack('H*', $raw);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'RAW: %s', $hex);
    
    my ($l, $type, $subType, $seq, $id, $temperature, $hum) = unpack('CCCCnnC', $raw); #0a 52 0c 00 000300d2050289
    if ($temperature & 0x8000) {
      $temperature -= 0x8000;
      $temperature *= -1;
    };
    $temperature /= 10;
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'DECODED: l:%s, t:0x%X, sub:0x%X, seq:%s, id:%s, temp:%s, hum:%s', $l, $type, $subType, $seq, $id, $temperature, $hum);
    
    $$fb = substr ($$fb, $plen +1);
    $plen = ord($$fb);
  };
};

sub readInX {
  my ($self, $event) = @_;
  my $fb = $event->{INBUFFER};
  
  my @in = unpack( "C*", $$fb );
  #print "*********************\n";
  #use Data::Dumper;
  #print Dumper @in;
  #my $plen = $in[0];
  my $plen = ord( substr ($$fb, 0, 1));
  
  #while (scalar(@in) > $plen) {
  while (length($$fb) >= $plen) {
    #print "l fb:";
    #print length($$fb);
    #print " l in:";
    #print scalar(@in);
    #print " p:";
    #print $plen."\n";
    
    $$fb = substr $$fb, $plen +1;
    my $packetType = $in[1];
    my $subType = $in[2];
    my $seqnbr = $in[3];
    splice @in, 0, 4;
    my @msg = splice @in, 0, $plen -3;
    my $id = sprintf('%X', $msg[0] * 256 + $msg[1]);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'read p:0x%X, s:0x%X', $packetType, $subType);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: eId:%s:%s:%s', 'Imagintronix', $id, '00');
    my $temperature = $msg[2] * 256 + $msg[3];
    if ($temperature & 0x8000) {
      $temperature -= 0x8000;
      $temperature *= -1;
    };
    $temperature /= 10;
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: temperature:%s', $temperature);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: humidity:%s', $msg[4]);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: battery:%s', $msg[6] & 0x0F);
    $self->SysLog(EXT_DEBUG|LOG_ERROR, 'Message: rssi:%s', ($msg[6] & 0xF0) >> 4 );
    #$e->{'TEMPERATURE'} = $temperature;
    
    #@in = splice @in, 0, $plen;
    $plen = (scalar(@in))?$in[0]:0;
  };
  #use Data::Dumper;
  #print Dumper @in;
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
