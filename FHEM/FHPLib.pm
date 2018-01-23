package FHJson::Data;
use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Tie::Scalar Base );

# adapt for more speed
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm

sub
TIESCALAR {
  my ($class, $parent) = @_;
  my $self = bless {}, $class;
  $self->{'.FHLib'}->{PARENT} = $parent;
  weaken $self->{'.FHLib'}->{PARENT};
  return $self;
}

sub
FETCH {
  my ($self) = @_;
  return $self->{'DATA'};
}

sub
STORE {
  my ($self, $value) = @_;
  $self->{'DATA'} = $value;
  use Data::Dumper;
  #print Dumper $self->{'DATA'};
  return $self;
}

package FHJson::Stream;
use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Tie::Scalar Base );

sub
TIESCALAR {
  my ($class, $parent) = @_;
  my $self = bless {}, $class;
  $self->{'.FHLib'}->{'DEFER'} = 1;
  $self->{'.FHLib'}->{'QUEUE'}->{'LOG'} = [];
  $self->SysLog (EXT_DEBUG|LOG_DEBUG, 'create tie %s', 000);
  $self->setParent($parent);
  $self->setElement(new FHJson::StreamReader(
    'NAME'        =>  'StreamReader',
  ));
  return $self;
}

sub
FETCH {
  my ($self) = @_;
  return $self->{'STREAM'};
}

sub
STORE {
  my ($self, $value) = @_;
  $self->{'STREAM'} = $value;
  my $t = Time::HiRes::time();
  my $data;
  eval {
    use JSON::XS;
    #$data = JSON::XS::encode_json($value);
    $data = JSON::XS->new->decode($value);
    1;
  } if (0);
  if (1 or $@) {
    $self->SysLog(LOG_ERROR, "json XS %s", $@);
    $data = $self->getElementByName('StreamReader')->parse($value);
  }
  $self->getParent->Data = $data;
  $self->SysLog(LOG_COMMAND, "json conversation took %03.2fms", (Time::HiRes::time() - $t) * 1000);
  return $self;
}

package FHJson::Escape;
use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw( blessed refaddr weaken );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

###############################################################################
# from FHEM to outer world
# https://docs.microsoft.com/en-us/sql/relational-databases/json/how-for-json-escapes-special-characters-and-control-characters-sql-server
# http://docs.activestate.com/activeperl/5.8/lib/pods/perlrecharclass.html
# https://perldoc.perl.org/Encode/Unicode.html#Surrogate-Pairs
# http://www.charbase.com/1f49d-unicode-heart-with-ribbon
sub
encode {
  my ($in) = @_;
  use constant SCE => {
  "\b" => 'b',
  "\f" => 'f',
  "\n" => 'n',
  "\r" => 'r',
  "\t" => 't',
  };

  my @codepoints = unpack 'U*', $in;
  my $out = join '', map {
    my $char = chr($_);
    if ($char =~ /[\"\\\/\b\f\n\r\t]/) {
      #"\\$char";
      '\\'.SCE->{$char};
    } elsif ($char =~ /\p{IsCntrl}/) {
      sprintf("\\u%04X", $_);
    } elsif ($char =~ /\p{IsASCII}/) {
      $char;
    } elsif ($_ >= 0x10000) {
      my $hi = ($_ - 0x10000) / 0x400 + 0xD800;
      my $lo = ($_ - 0x10000) % 0x400 + 0xDC00;
      sprintf("\\u%04X\\u%04X", $hi, $lo);
    } else {
      #utf8::encode($_);
      sprintf("\\u%04X", $_);
    };
  } @codepoints;
  return $out;
}

###############################################################################
# from outer world to FHEM
sub
decode {
  my ($in) = @_;
  use constant SCD => {
    'b' => "\b",
    'f' => "\f",
    'n' => "\n",
    'r' => "\r",
    't' => "\t",
  };
  my @octets = unpack 'U*', $in;
  my $out = '';
  for (my $i = 0; $i < @octets; $i++) {
    if (chr($octets[$i]) eq '\\') {
      if (chr($octets[$i+1]) =~ /[\"\\\/]/) {
        $out .= chr($octets[++$i]);
        #print "replaced one \" $out \n" if (chr($octets[$i]) eq '"');
      } elsif (chr($octets[$i+1]) =~ /[brnft]/i) {
        $out .= SCD->{lc(chr($octets[++$i]))};
      } elsif (chr($octets[$i+1]) eq 'u') {
        my $h = join '', map { chr($_) } @octets[$i+2 .. $i+5];
        $out .= ($h =~ qr/[[:xdigit:]]{4}/)?chr(hex($h)):'?'; # TODO surrogate pairs, 
        #$out .= chr(hex(join '', map { chr($_) } @octets[$i+2 .. $i+5])); # is hex?, 
        $i += 5;
      }
    } else {
      $out .= chr($octets[$i]);
    }
  }
  
  my $success = utf8::decode($out); 
  my $num_octets = utf8::upgrade($out);
  #my $flag = utf8::is_utf8($out);
  #print "ok: $flag, oct: $num_octets, $out l:". length($out) ."\n";
  return $out;
}

###############################################################################
# credits to David Oswald
# http://cpansearch.perl.org/src/DAVIDO/JSON-Tiny-0.58/lib/JSON/Tiny.pm
# his implementation is ~five times faster than original FHLib

package FHJson::StreamReader;
use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw ( looks_like_number refaddr );
use B;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  %{$self->{'ESCAPE'}} = (
    '"'     => '"',
    '\\'    => '\\',
    '/'     => '/',
    'b'     => "\x08",
    'f'     => "\x0c",
    'n'     => "\x0a",
    'r'     => "\x0d",
    't'     => "\x09",
    'u2028' => "\x{2028}",
    'u2029' => "\x{2029}"
  );
  #%{$self->{'REVERSE'}} = map { $self->{'ESCAPE'}->{$_} => "\\$_" } keys %{$self->{'ESCAPE'}};
  
  #for(0x00 .. 0x1f) {
  #  my $packed = pack 'C', $_;
  #  $self->{'REVERSE'}->{$packed} = sprintf '\u%.4X', $_ unless defined $self->{'REVERSE'}->{$packed};
  #};

  my %events = ( 
    'onError'       =>  'defaultError',
  );
  foreach my $k (keys %events) {
    $self->mapEvent($k, $args{$k}) if exists $args{$k}; # map if given by args
    $self->bindEvent($k, $events{$k}); # set default handler
  };
};

sub
parse {
  my ($self, $in) = @_;
  my $TRUE = 1;
  my $FALSE = 0;
  
  #my $exception;
  #my $_decode;
  #my $_decode_array;
  #my $_decode_object;
  #my $_decode_string;
  #my $_decode_value;
  
  local *exception = sub {
    my ($e) = @_;
    # Leading whitespace
    m/\G[\x20\x09\x0a\x0d]*/gc;
    # Context
    my $context = 'Malformed JSON: ' . shift;
    if (m/\G\z/gc) { 
      $context .= ' before end of data';
    } else {
      my @lines = split "\n", substr($_, 0, pos);
      $context .= ' at line ' . @lines . ', offset ' . length(pop @lines || '');
    };
    $self->SysLog(EXT_DEBUG|LOG_ERROR, "%s json decoder: %s", $self->getName(), $context);
    die "$context";
  };
  
  local *_decode = sub {
    my $valueref = shift;
    eval {
      # Missing input
      die "Missing or empty input\n" unless length( local $_ = shift );
      # UTF-8
      $_ = eval { Encode::decode('UTF-8', $_, 1) } unless shift;
      die "Input is not UTF-8 encoded\n" unless defined $_;
      # Value
      $$valueref = _decode_value();
      # Leftover data
      return m/\G[\x20\x09\x0a\x0d]*\z/gc || exception('Unexpected data');
    } ? return undef : chomp $@;
    return $@;
  };
  
  local *_decode_array = sub {
    my @array;
    until (m/\G[\x20\x09\x0a\x0d]*\]/gc) {
      # Value
      push @array, _decode_value();
      # Separator
      redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
      # End
      last if m/\G[\x20\x09\x0a\x0d]*\]/gc;
      # Invalid character
      exception('Expected comma or right square bracket while parsing array');
    };
    return \@array;
  };

  local *_decode_object = sub {
    my %hash;
    until (m/\G[\x20\x09\x0a\x0d]*\}/gc) {
      # Quote
      m/\G[\x20\x09\x0a\x0d]*"/gc
        or exception('Expected string while parsing object');
      # Key
      my $key = _decode_string();
      # Colon
      m/\G[\x20\x09\x0a\x0d]*:/gc
        or exception('Expected colon while parsing object');
      # Value
      $hash{$key} = _decode_value();
      # Separator
      redo if m/\G[\x20\x09\x0a\x0d]*,/gc;
      # End
      last if m/\G[\x20\x09\x0a\x0d]*\}/gc;
      # Invalid character
      exception('Expected comma or right curly bracket while parsing object');
    };

    return \%hash;
  };

  local *_decode_string = sub {
    my $pos = pos;
    
    # Extract string with escaped characters
    m!\G((?:(?:[^\x00-\x1f\\"]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4})){0,32766})*)!gc; # segfault on 5.8.x in t/20-mojo-json.t
    my $str = $1;

    # Invalid character
    unless (m/\G"/gc) { #"
      exception('Unexpected character or invalid escape while parsing string')
        if m/\G[\x00-\x1f\\]/;
      exception('Unterminated string');
    }

    # Unescape popular characters
    if (index($str, '\\u') < 0) {
      #no warnings;
      $str =~ s!\\(["\\/bfnrt])!$self->{'ESCAPE'}->{$1}!gs;
      return $str;
    };
   
    # Unescape everything else
    my $buffer = '';
    while ($str =~ m/\G([^\\]*)\\(?:([^u])|u(.{4}))/gc) {
      $buffer .= $1;
      # Popular character
      if ($2) { 
        $buffer .= $self->{'ESCAPE'}->{$2};
      } else { # Escaped
        my $ord = hex $3;
        # Surrogate pair
        if (($ord & 0xf800) == 0xd800) {
          # High surrogate
          ($ord & 0xfc00) == 0xd800
            or pos($_) = $pos + pos($str), exception('Missing high-surrogate');
          # Low surrogate
          $str =~ m/\G\\u([Dd][C-Fc-f]..)/gc
            or pos($_) = $pos + pos($str), exception('Missing low-surrogate');
          $ord = 0x10000 + ($ord - 0xd800) * 0x400 + (hex($1) - 0xdc00);
        };
        # Character
        $buffer .= pack 'U', $ord;
      };
    };
    # The rest
    return $buffer . substr $str, pos $str, length $str;
  };
  
  local *_decode_value = sub {
    # Leading whitespace
    m/\G[\x20\x09\x0a\x0d]*/gc;
    # String
    return _decode_string() if m/\G"/gc;
    # Object
    return _decode_object() if m/\G\{/gc;
    # Array
    return _decode_array() if m/\G\[/gc;
    # Number 
    # TODO failed with 0123 
    my ($i) = /\G([-]?(?:0(?!\d)|[1-9][0-9]*)(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)/gc;
    return 0 + $i if defined $i;
    # True
    { no warnings;
    return $TRUE if m/\Gtrue/gc;
    # False
    return $FALSE if m/\Gfalse/gc;};
    # Null
    return undef if m/\Gnull/gc;  ## no critic (return)
    # Invalid character
    exception('Expected string, array, object, number, boolean or null');
  };
  
  my $err = _decode(\my $value, $in, 1);
  return defined $err ? $err : $value;
};

package FHJson::StreamReader_old;
use strict;
use warnings;
use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  my @t = (
    ['^\s+', 'w'], # whitespace
    ['^{', 'O'], # object start tag
    ['^}', 'o'], # object end tag
    ['^\[', 'A'], # array start tag
    ['^\]', 'a'], # array end tag
    ['^:', 'p'],  # pair (object)
    ['^,', 'c'],  # comma (array)
    ['^true', 't'],  # true
    ['^false', 'f'],  # false
    ['^null', 'n'],  # null
    # the order is important:
    ['^[-+]?[0-9]*\.?[0-9]+[eE][-+]?[0-9]+', 'e'], # exp
    ['^[-+]?[0-9]*\.[0-9]+', 'r'],  # real
    ['^[-+]?\d+', 'i'],  # int    
    ['^"(?:[^\\\\"]|\\\\.)*"', 's'], #string
    ['^[^:,]*', 'u'], # garbage
  );
  # compile regex
  foreach my $l (@t) {
    my $re = qr/(@{$l}[0])/;
    push @{$l}, $re;
  }
  $self->{'TYPES'} = \@t;
  return $self;
}

sub
parse {
  my ($self, $stream) = @_;
  my $use_XS = 0;
  
  
  my $data;
  eval {
    use JSON::XS;
    #$data = JSON::XS::encode_json($value);
    $data = JSON::XS->new->decode($stream);
    1;
  } if ($use_XS);
  if ($use_XS and !$@) {
    return $self->{'.FHLib'}->{'STORAGE'}->{'DATA'} = $data;
  };
  $self->SysLog(LOG_ERROR, "json XS %s", $@) if ($use_XS and $@);

  $self->{'STREAM'} = \$stream;
  $self->{'POSITION'} = 0;
  $self->{'STREAMLEN'} = length($stream);
  $self->{'TAG'} = [];
  $self->{'TOKEN'} = [];
  $self->{'POS'} = [];
  $self->tokenize();
  $self->compile();
  
}

sub
getType {
  my ($self) = @_;
  my $types = $self->{'TYPES'};
  my $stream = $self->{'STREAM'};
  my ($t, $c);
  my $p = $self->{'STREAMLEN'} - length($$stream);
  foreach my $l (@$types) { # compiled regex
    if ($$stream =~ s/@{$l}[2]//) {
      $t = @{$l}[1];
      $c = $1;
      $c =~ s/^"|"$//g  if ($t eq 's'); # remove enclosing quotes for type string
      last;
    }
  }
  return ($t, $c, $p);
}

sub
addANode {
  my ($self) = @_;
  my $r = [];
  $self->SysLog(EXT_DEBUG | LOG_DEBUG, "create array");
  $self->{'POSITION'}++;
  while ((my $tag = $self->{'TAG'}->[$self->{'POSITION'}]) ne 'a') {
    # print "tag $tag \n";
    if ($tag =~ /[tfneris]/) {
      my $v = $self->{'TOKEN'}->[$self->{'POSITION'}++];
      if ($tag eq 's') {
        $v = FHJson::Escape::decode($v);
      } elsif ($tag eq 't') {
        $v = 1;
      } elsif ($tag eq 'f') {
        $v = 0;
      } elsif ($tag eq 'n') {
        $v = undef;
      }
      push @$r, $v;
      #push @$r, $self->{'TOKEN'}->[$self->{'POSITION'}++]; #$token[$self->{'position'}++];
    } elsif ($tag eq 'A') {
      push @$r, $self->addANode();
    } elsif ($tag eq 'O') {
      push @$r, $self->addONode();
    } else {
      $self->error("unexpected token");
      return [];
    }
    # must be comma 'c' or array close 'a' but not comma followed by close 'ca'
    if (($tag = $self->{'TAG'}->[$self->{'POSITION'}]) eq 'a') {
      next;
    } elsif ($tag eq 'c') {
      $self->{'POSITION'}++;
      if (($self->{'TAG'}->[$self->{'POSITION'}]) eq 'a') {
        $self->error("empty array element");
        return [];
      }
    } else {
      $self->error("comma or array-end-tag expected");
      return [];
    }      
  }
  $self->{'POSITION'}++;
  return $r;
}

sub
addONode {
  my ($self) = @_;
  my $r = {};
  $self->SysLog(EXT_DEBUG | LOG_DEBUG, "create object");
  $self->{'POSITION'}++;
  while ((my $tag = $self->{'TAG'}->[$self->{'POSITION'}]) ne 'o') {
    if ($tag eq 's') {
      my $k = FHJson::Escape::decode($self->{'TOKEN'}->[$self->{'POSITION'}++]);
      if (($tag = $self->{'TAG'}->[$self->{'POSITION'}]) eq 'p') {
        $self->{'POSITION'}++;
      } else {
        $self->error("pair seperator ':' expected");
        return {};
      }
      # read valid val types
      if (($tag = $self->{'TAG'}->[$self->{'POSITION'}]) =~ /t|f|n|e|r|i|s/) {
        my $v = $self->{'TOKEN'}->[$self->{'POSITION'}++];
        $v = FHJson::Escape::decode($v) if ($tag eq 's');
        $self->SysLog(EXT_DEBUG | LOG_DEBUG, "insert object member: '%s', value: '%s', tag: '%s'", $k, $v, $tag );
        $r->{$k} = $v;
      } elsif ($tag eq 'A') {
        $r->{$k} = $self->addANode();
      } elsif ($tag eq 'O') {
        $r->{$k} = $self->addONode();
      } else { 
        $self->error("unexpected token");
        return {};
      }
      # must be comma 'c' or object close 'o' but not comma followed by close 'co'
      if (($tag = $self->{'TAG'}->[$self->{'POSITION'}]) eq 'o') {
        next;
      } elsif ($tag eq 'c') {
        $self->{'POSITION'}++;
        if (($self->{'TAG'}->[$self->{'POSITION'}]) eq 'o') {
          $self->error("empty object element");
          return {};
        }
      }
    } else {
      $self->error("string expected");
      return {};
    }
  }
  $self->{'POSITION'}++;
  return $r;
}

sub
tokenize {
  my ($self) = @_;
  my $stream = $self->{'STREAM'};
  $self->SysLog(EXT_DEBUG | LOG_DEBUG, "start");
  my $i = 0;
  while (length($$stream)) {
    $i++;
    my ($t, $c, $p) = $self->getType(); # get next
    next if ($t eq 'w'); # remove whitespace
    push @{$self->{'TAG'}}, $t;
    push @{$self->{'TOKEN'}}, $c;
    push @{$self->{'POS'}}, $p;
    $self->SysLog(EXT_DEBUG | LOG_DEBUG, "TAG: %s, TOKEN: %s, POS: %s", $t, $c, $p);
  }
  push @{$self->{'TAG'}}, 'q';
  push @{$self->{'TOKEN'}}, 'eof';
  push @{$self->{'POS'}}, $self->{'STREAMLEN'};
}

sub
compile {
  my ($self) = @_;
  my $data;
  
  if ($self->{'TAG'}->[$self->{'POSITION'}] eq 'A') {
    $self->SysLog(EXT_DEBUG | LOG_DEBUG, "json root: array");
    $data = $self->addANode();
  } elsif ($self->{'TAG'}->[$self->{'POSITION'}] eq 'O') {
    $self->SysLog(EXT_DEBUG | LOG_DEBUG, "json root: object");
    $data = $self->addONode();
  } else { 
    $self->error ("json root must be an array or object");
  }
  $self->{'.FHLib'}->{'STORAGE'}->{'DATA'} = $data;
}

sub
error {
  my ($self, $text) = @_;
  my $pos = $self->{'POS'}->[$self->{'POSITION'}];
  my $source = $self->{'TOKEN'}->[$self->{'POSITION'}];
  $self->SysLog(EXT_DEBUG | LOG_ERROR, "JSON parse stream: $text at pos #$pos '$source'");
  $self->SysLog(EXT_DEBUG | LOG_DEBUG, "$text at pos #$pos '$source'");
}


package FHJson::StreamWriter;
use strict;
use warnings;
use diagnostics;
use utf8;
#use Scalar::Util qw ( looks_like_number );
use B;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  %{$self->{'ESCAPE'}} = (
    '"'     => '"',
    '\\'    => '\\',
    '/'     => '/',
    'b'     => "\x08",
    'f'     => "\x0c",
    'n'     => "\x0a",
    'r'     => "\x0d",
    't'     => "\x09",
    'u2028' => "\x{2028}",
    'u2029' => "\x{2029}"
  );
  %{$self->{'REVERSE'}} = map { $self->{'ESCAPE'}->{$_} => "\\$_" } keys %{$self->{'ESCAPE'}};
  
  for(0x00 .. 0x1f) {
    my $packed = pack 'C', $_;
    $self->{'REVERSE'}->{$packed} = sprintf '\u%.4X', $_ unless defined $self->{'REVERSE'}->{$packed};
  };

  my %events = ( 
    'onError'       =>  'defaultError',
  );
};

sub
parse {
  my ($self, $data) = @_;
  my $stream;
  
  if (my $ref = ref $data) {
    use Encode;
    return Encode::encode_utf8($self->addValue($data));
  };
};

sub
addValue {
  my ($self, $data) = @_;
  if (my $ref = ref $data) {
    return $self->addONode($data) if ($ref eq 'HASH');
    return $self->addANode($data) if ($ref eq 'ARRAY');
  }
  return 'null' unless defined $data;
  return $data
    if B::svref_2object(\$data)->FLAGS & (B::SVp_IOK | B::SVp_NOK)
    # filter out "upgraded" strings whose numeric form doesn't strictly match
    && 0 + $data eq $data
    # filter out inf and nan
    && $data * 0 == 0;
  # String
  return $self->addString($data);
}

sub 
addString {
  my ($self, $str) = @_;
  $str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$self->{'REVERSE'}->{$1}!gs;
  return "\"$str\"";
}

sub
addONode {
  my ($self, $object) = @_;
  my @pairs = map { $self->addString($_) . ':' . $self->addValue($object->{$_}) }
    sort keys %$object;
  return '{' . join(',', @pairs) . '}';
}

sub
addANode {
  my ($self, $array) = @_;
  return '[' . join(',', map { $self->addValue($_) } @{$array}) . ']';
}

###############################################################################
package FHJson::StreamWriter_old;
use strict;
use warnings;
use diagnostics;
use utf8;
use Scalar::Util qw ( looks_like_number );
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
parse {
  my ($self, $data) = @_;
  
  $self->{'STREAM'} = '';
  unless (ref $data) {
    $data = \$data;
  }
  $self->addNode($data);
  return $self->{'STREAM'};
}

sub
escape {
  my ($self, $in, $qmark) = @_;
  $in = FHJson::Escape::encode($in);
  if ( $qmark or ( $in and (substr($in, 0, 1) eq '0') ) or not looks_like_number( $in )) {
    $in = '"'.$in.'"' 
  } else {
    # remove leading zeros (rfc4627 2.4)
    $in += 0; 
  };
  return $in;
}

sub 
addANode {
  my ($self, $in) = @_;

  $self->{'STREAM'} .= '[';
  my $size = scalar @$in;
  my $i = 0;
  while ($i < $size) {
    $self->addNode(@$in[$i]);
    $self->{'STREAM'} .= ',' if (++$i < $size);
  }
  $self->{'STREAM'} .= ']';
}
  
sub 
addONode {
  my ($self, $in) = @_;       
  
  $self->{'STREAM'} .= '{';
  my @keys = keys %$in;
  my $size = scalar @keys;
  my $i = 0;
  while ($i < $size) {
    my $key = $keys[$i];
    $self->{'STREAM'} .=  $self->escape($key, 1).':';
    $self->addNode($in->{$key});
    $self->{'STREAM'} .= ',' if (++$i < $size);
  }
  $self->{'STREAM'} .= '}';
}

sub 
addNode {
  my ($self, $in) = @_;
 
  if (ref $in eq 'ARRAY') {
    $self->addANode($in);
  } elsif (ref $in eq 'HASH') {
    $self->addONode($in);
  } elsif (not ref $in) {
    $self->{'STREAM'} .=  $self->escape($in);
    #$self->{'STREAM'} .= $in; # TODO escape
  } else {
    # error
  }
};

package FHJson;
use strict;
use warnings;
use diagnostics;
use utf8;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

sub
setUp {
  my ($self, %args) = @_;
  tie $self->{'.FHLib'}->{'STORAGE'}->{'DATA'}, 'FHJson::Data', $self;
  tie $self->{'.FHLib'}->{'STORAGE'}->{'STREAM'}, 'FHJson::Stream', $self;
}

sub
Data : lvalue {
  my ($self) = @_;
  return $self->{'.FHLib'}->{'STORAGE'}->{'DATA'};
}

sub
Stream : lvalue {
  my ($self) = @_;
  return $self->{'.FHLib'}->{'STORAGE'}->{'STREAM'};
}

package FHFileGet;
use strict;
use warnings;
use diagnostics;
use lib './FHEM';
use FHCore qw ( :all );
use parent -norequire, qw ( Base );

1;

