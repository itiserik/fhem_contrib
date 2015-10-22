###############################################################################
#
# A module to comunicate with Toon.
#
# written        2015 by itserik
#
###############################################################################

package main;

use HttpUtils;
use utf8;
use JSON;
use URI::Escape;
use Data::UUID;

my %sets = (
  "message" => 1
);

#------------------------------------------------------------------------------
sub Toon_Initialize($$)
#------------------------------------------------------------------------------
{
  my ($hash) = @_;
 $hash->{DefFn}    = "Toon_Define";
# $hash->{SetFn}    = "Toon_Set";
  $hash->{AttrList}= "disable:0,1 ".$readingFnAttributes;

  Log3 $hash, 3, "Toon initialized";

  return undef;
}

#------------------------------------------------------------------------------
sub Toon_Define($$)
#------------------------------------------------------------------------------
{
  my ($hash, $def) = @_;
  
  my @args = split("[ \t]+", $def);
  
  if (int(@args) < 4)
  {
    return "Invalid number of arguments: define <name> Toon <interval> <username> <password>";
  }
  
  my ($name, $type, $interval, $username, $password) = @args;
  
  $hash->{STATE}       = 'Initialized';
  $hash->{helper}{Url} = "https://toonopafstand.eneco.nl/toonMobileBackendWeb/client/";
   
  $hash->{interval} = $interval;
  $hash->{helper}{username} = $username;
  $hash->{helper}{password} = $password;

  my $firstTrigger = gettimeofday() + 2;
  $hash->{TRIGGERTIME}     = $firstTrigger;
  $hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
  RemoveInternalTimer("update:$name");
  InternalTimer($firstTrigger, "Toon_DoAuth", "update:$name", 0);
  Log3 $name, 5, "$name: InternalTimer set to call GetUpdate in 2 seconds for the first time";

  Log3 $hash, 3, "Toon defined for user: " . $username;

  return undef;
}

sub Toon_DoAuth($){
  
  my ($calltype,$name) = split(':', $_[0]);
  my $hash = $defs{$name};
  my ($data,$err,$resp,$decoded);
  my $name = $hash->{NAME};
  Log3 $hash, 3, "Toon doAuth";
  $data = "username=".$hash->{helper}{username}."&password=".$hash->{helper}{password};
   
  ($err,$resp)    = HttpUtils_BlockingGet({
    url           => $hash->{helper}{Url} . "login",
    method        => "POST"	,
    header        => "Content-Type: application/x-www-form-urlencoded",
    data          => $data
  });
  
  $data = "" if( !$data );
  $resp = "" if( !$resp );
  
  Log3 $hash, 4, "FHEM -> Toon: " . $data; 
  Log3 $hash, 4, "Toon -> FHEM: " . $resp;
  
  $decoded  = decode_json($resp); 
  Log3 $hash, 5, 'dec: ' . $decoded;
  Log3 $hash, 5, 'cid: ' . $decoded->{'clientId'};
  
  
  $hash->{helper}{clientId} = $decoded->{'clientId'};
  $hash->{helper}{clientIdChecksum} = $decoded->{'clientIdChecksum'};
  $hash->{helper}{agreementId} = $decoded->{'agreements'}[0]{'agreementId'};
  $hash->{helper}{agreementIdChecksum} = $decoded->{'agreements'}[0]{'agreementIdChecksum'};
  $ug = Data::UUID->new;
  
  ($err,$resp)    = HttpUtils_BlockingGet({
    url           => $hash->{helper}{Url} . "auth/start?clientId=".$hash->{helper}{clientId}.
							"&clientIdChecksum=".$hash->{helper}{clientIdChecksum}.
							"&agreementId=".$hash->{helper}{agreementId}.
							"&agreementIdChecksum=".$hash->{helper}{agreementIdChecksum}.
							"&random=".$ug->create_str(),
    method        => "GET"
  });
  
    Log3 $hash, 4, "Toon -> FHEM: " . $resp;
	
	$decoded  = decode_json($resp) if ($resp);
	if ($decoded->{"success"})
	{
		$hash->{STATE}       = 'Authenticated';
		my $firstTrigger = gettimeofday() + $hash->{interval};
		$hash->{TRIGGERTIME}     = $firstTrigger;
		$hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
		InternalTimer($firstTrigger, "Toon_Update", "update:$name", 0);
	}
  return undef;
}

#------------------------------------------------------------------------------
sub Toon_Update($@)
#------------------------------------------------------------------------------
{
  my ($calltype,$name) = split(':', $_[0]);
  my $hash = $defs{$name};
  my ($data,$err,$resp,$decoded);
  my $name = $hash->{NAME};
  ($err,$resp)    = HttpUtils_NonblockingGet({
    url           => $hash->{helper}{Url} . "auth/retrieveToonState".
							"?clientId=".$hash->{helper}{clientId}.
							"&clientIdChecksum=".$hash->{helper}{clientIdChecksum}.
							"&random=".$ug->create_str(),
	timeout     => 30,
    hash        => $hash,
    method      => "GET",
    callback    => \&Toon_Callback
  });

}

#------------------------------------------------------------------------------
sub Toon_Callback($)
#------------------------------------------------------------------------------
{
  my ($params, $err, $data) = @_;
  my $hash = $params->{hash};
Log3 $hash, 4, "Toon err -> FHEM: " . $err;
Log3 $hash, 4, "Toon data-> FHEM: " . $data;
  if($err ne "")
  {
    $returnObject = {
      success     => false,
      description => "Request could not be completed: " . $err
    };

    Toon_Parse_Result($hash, encode_json $returnObject);
  }

  elsif($data ne "")
  {
    Toon_Parse_Result($hash, $data);
  }

  return undef;
}

#------------------------------------------------------------------------------
sub Toon_Parse_Result($$$)
#------------------------------------------------------------------------------
{
  my ($hash, $result) = @_;
  my $name = $hash->{NAME};

  my $returnObject = decode_json $result;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "description", $returnObject->{"description"}) if ($returnObject->{"description"});
# readingsBulkUpdate($hash, "last-result-raw", $result);
  readingsBulkUpdate($hash, "last-success", $returnObject->{"success"});
  if ($returnObject->{"thermostatInfo"})
  {
    readingsBulkUpdate($hash, "currentTemp", $returnObject->{"thermostatInfo"}{"currentTemp"}*0.01);
    readingsBulkUpdate($hash, "realSetpoint", $returnObject->{"thermostatInfo"}{"realSetpoint"}*0.01);
    readingsBulkUpdate($hash, "currentSetpoint", $returnObject->{"thermostatInfo"}{"currentSetpoint"}*0.01);
    readingsBulkUpdate($hash, "burnerInfo", $returnObject->{"thermostatInfo"}{"burnerInfo"});
    readingsBulkUpdate($hash, "currentModulationLevel", $returnObject->{"thermostatInfo"}{"currentModulationLevel"});
  }
  
  readingsEndUpdate($hash, 1);
  
  	if ($returnObject->{"success"})
	{
		my $firstTrigger = gettimeofday() + $hash->{interval};
		$hash->{TRIGGERTIME}     = $firstTrigger;
		$hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);
		InternalTimer($firstTrigger, "Toon_Update", "update:$name", 0);
	}
}

    
1;

###############################################################################

=pod
=begin html

<a name="Toon"></a>
<h3>Toon</h3>
<ul>
  Toon is a service to from Eneco to operate the thermostat.
  You need an account to use this module.<br>
  For further information about the service see <a href="https://www.eneco.nl/tool" target="_blank">www.eneco.nl/tool</a>.<br>
  <br>
  <a name="ToonDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Toon &lt;interval&gt; &lt;username&gt; &lt;password&gt;</code><br>
    <br>
    <table>
      <colgroup>
        <col style="width: 100px";"></col>
        <col></col>
      </colgroup>
      <tr>
        <td>&lt;interval&gt;</td>
        <td>The update interval in seconds.</td>
      </tr>
      <tr>
        <td>&lt;username&gt;</td>
        <td>The eneco.nl username.</td>
      </tr>
	   <tr>
        <td>&lt;password&gt;</td>
        <td>The eneco.nl password.</td>
      </tr>
    </table>
    <br>
    Example:
    <ul>
      <code>define toon Toon 30 user pw</code>
    </ul>
  </ul>
  <br>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="ToonAttr"></a>
  <b>Attributes</b> <ul>N/A</ul><br>
  <ul>
  </ul>
  <br>
  <a name="ToonEvents"></a>
  <b>Generated events:</b>
  <ul>
     N/A
  </ul>
</ul>

=end html
=begin html_DE

=end html_DE
=cut
