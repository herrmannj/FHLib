package main;
use strict;
use warnings;
use FHModuleGen;

# avrdude -v -p atmega2560 -c stk500 -P /dev/ttyUSB0 -b 115200 -D -U flash:w:/home/pi/RFLink.cpp.hex:i

Modul->Init(
  thread    => 1,
);

###############################################################################
package Universal;
use strict;
use warnings;
our @ISA= qw( Modul );

#sub
#new {
#  my ($type, %args) = @_;
#  my $class = ref $type || $type;
#  my $self = $class->SUPER::new(%args);
#  return bless $self, $class;
#}

sub
setOption {
  my ($self, $option, $value) = @_;
  $self->SysLog('DEBUG', "define '%s' as '%s'", $option, $value||'');
  if ($option eq 'if') {
    my ($dev, $param) = split '@', $value;
    $self->{INTERFACE} = $dev;
    $self->{'.INTERFACE_PARAM'} = $param;
    print "if = $dev, p = $param\n";
  } 
}

# def consumend, validate
sub
validateDefinition {
  my ($self) = @_;
  my $name = $self->{NAME};
}

sub
run {
  my ($self) = @_;
  
  $self->SysLog(3, "entering runstate 0");
  subscribe('device,.*,test', 'onTest');
  $self->setElement( new FHTimer (
    
  ));
  #$self->readStream;
  #$self->{'data'} = [1,2,3,['äöüß"',"nl: (\r\n)",'€'],{'k' => 'v'}, 4];
  #$self->writeStream;
}


###############################################################################
sub
_doFwDetail {
  my ($self, $FW_wname, $device, $FW_room) = @_;
 
  my $r = <<'DOC';
<script>
const FHWebConfig = {
  device: $device,
  test: 'test'
};

var myCodeMirror;

//var cssEl = $('<link>', { rel: 'stylesheet', type: 'text/css', 'href': 'fhem/www/codemirror/codemirror.css' });
//cssEl.appendTo('head').on("load", function() {
  //defer.resolve();
//  window.console&&console.log('css done');
//});



//http://jsfiddle.net/gokul2287/nhwvU/
var fh = $('#hdr ').detach();
var fc = $('#content ').detach();
$('<div id="content"/>').css({top: "0px"}).insertAfter('#menuScrollArea ');

// http://callmenick.com/post/slide-down-menu-with-jquery-and-css

// menu struct

$('<nav id="eMenu"/>').appendTo('#content');
$('<ul id="eTopMenu"/>').appendTo('#eMenu');
$('<li><a id="eTopMenuEntrySave" href="javascript:void(0)">Save</a></li>').appendTo('#eTopMenu');
$('<li><a href="javascript:void(0)">Edit</a></li>').appendTo('#eTopMenu');
$('<li><a id="eTopMenuEntryRestart" href="javascript:void(0)">Restart fhem</a></li>').appendTo('#eTopMenu');

// menu style

$('nav').css({
  "padding": "0 0"   // "padding": "10px 0"
});

$("nav ul").css({
  "list-style-type": "none",
  "margin": 0,
  "padding": 0
});

$("nav ul li").css({
  "display": "inline-block",
  "position": "relative"
});

$("nav li ul").css({
  "position": "absolute",
  "left": 0,
  "top": "40px",
  "width": "200px"
});

$("nav li li").css({
  "position": "relative",
  "margin": 0,
  "display": "block"
});

$("nav li li ul").css({
  "position": "absolute",
  "top": 0,
  "left": "200px",
  "margin": 0
});

$("nav a").css({
  "line-height": "40px",
  "padding": "0 12px",
  "margin": "0 12px",
  "text-decoration": "none",
  "display": "block"
});

$("nav a:hover, nav a:focus, nav a:active").css({
  "color": "rgb(50,50,50)"
});

//https://jsfiddle.net/vfjtzsd2/2/
//$('<textarea id="editor"/>').css({height: "calc(100vh - 46px)", width: "100vh"}).insertAfter('#navigator ');
$('<textarea id="editor"/>').insertAfter('#eMenu ');

var cssEl = $('<link>', { rel: 'stylesheet', type: 'text/css', 'href': 'fhem/www/codemirror/codemirror.css' });
cssEl.appendTo('head').on("load", function() {
  //defer.resolve();
  window.console&&console.log('css done');
  
  $.getScript('fhem/www/codemirror/codemirror.js', function (data, status, jqxhr) {
    //defer.resolve();
    window.console&&console.log('js done');
    var e = $('#editor')[0];
    myCodeMirror = CodeMirror.fromTextArea(e, {
      value: "function myScript(){return 100;}\n",
      lineNumbers: true,
      mode: "javascript",
      matchClosing: true,
    });
    // re-style
    myCodeMirror.setSize(null, "calc(100vh - 64px)");
    $('nav').css({'background-color': $('.CodeMirror-gutters').css('background-color')});
  }); 
});

https://stackoverflow.com/questions/105034/create-guid-uuid-in-javascript
function generateUUID () { // Public Domain/MIT
  var d = new Date().getTime();
  if (typeof performance !== 'undefined' && typeof performance.now === 'function'){
    d += performance.now(); //use high-precision timer if available
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    var r = (d + Math.random() * 16) % 16 | 0;
    d = Math.floor(d / 16);
    return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
  });
}

$('#eTopMenuEntrySave').click(function() {
  //window.console&&console.log('save');
  var dev = 'u';
  var cmd = 'get';
  var arg = 'webif-data';
  var val = '';
  //var uuid = '.' + generateUUID() + '=';
  var uuid = '.getu=';
  var fw_id = $('body').attr('fw_id');
  
  //window.console.log (myCodeMirror.getValue());
  
  var msg = {
    cmd:  'save',
    //data: window.btoa(unescape(encodeURIComponent(myCodeMirror.getValue())))
    data: encodeURIComponent(myCodeMirror.getValue()) //https://www.rosettacode.org/wiki/URL_decoding#Perl
  };
  
  msg = JSON.stringify(msg);
  
  $.post('fhem?XHR=1&cmd.0=get u webif-data&fw_id=' + fw_id, 
    {
      'val.0': msg
    },    
    function(result) {
      window.console&&console.log(result);
    }
  );
});

$('#eTopMenuEntryRestart').click(function() {
  //window.console&&console.log('save');
  var dev = 'u';
  var cmd = 'get';
  var arg = 'webif-data';
  var val = '';
  //var uuid = '.' + generateUUID() + '=';
  var uuid = '.getu=';
  var fw_id = $('body').attr('fw_id');
  
  $.ajax({   
    //url: 'fhem?detail=u&dev' + uuid + dev + '&cmd' + uuid + cmd + '&arg' + uuid + arg + '&val' + uuid + val + '&xhr=1&fw_id=' + fw_id,
    url: 'fhem?XHR=1&cmd=shutdown restart&fw_id=' + fw_id,
    success: function(result) {
        window.console&&console.log(result);
    }
  });
});

</script>
DOC
###############################################################################
  $r =~ s/\$device([\W,;])/"\'$device\'".$1/ge;
  return $r;
}

1;
