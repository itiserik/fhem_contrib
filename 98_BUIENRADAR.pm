package main;

use strict;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;

sub
BUIENRADAR_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "BUIENRADAR_Define";
  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5,6 ".
                        "interval ".
                        "$readingFnAttributes";
}

sub
BUIENRADAR_Define($$)
{
  my ($hash, $def) = @_;
  my $name=$hash->{NAME};
  my @a = split("[ \t][ \t]*", $def);

  my $interval=$a[2];
  my $lat=$a[3];
  my $lon=$a[4];
  $attr{$name}{interval}=$interval if $interval;

  return "Usage: define <name> BUIENRADAR <poll-interval> <lat> <lon>" if(int(@a) != 5);

  $hash->{Lat} = $lat;
  $hash->{Lon} = $lon; 
 
  InternalTimer(gettimeofday()+$interval, "BUIENRADAR_GetStatus", $hash, 0);
 
  return;
}

sub
BUIENRADAR_GetStatus($)
{
	my ($hash) = @_;
	my $err_log='';
	my $line;

	my $name = $hash->{NAME};

	my $interval=$attr{$name}{interval}||300;
	InternalTimer(gettimeofday()+$interval, "BUIENRADAR_GetStatus", $hash, 0);

	my $lat = $hash->{Lat};
	my $lon = $hash->{Lon};

	my $URL="http://gps.buienradar.nl/getrr.php?lat=".$lat."&lon=".$lon;
	my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 3);
	my $header = HTTP::Request->new(GET => $URL);
	my $request = HTTP::Request->new('GET', $URL, $header);
	my $response = $agent->request($request);

	$err_log.= "Can't get $URL -- ".$response->status_line
                unless $response->is_success;

	if($err_log ne "")
	{
		Log GetLogLevel($name,2), "BUIENRADAR $name ".$err_log;
		return;
	}

	my $body =  $response->content;
	my $text='';


        #while($body =~ /([^\n]+)\n?/g){
	#	Log GetLogLevel($name,2), "BUIENRADAR $name ... ".$1;
        #        }
	my @values=split(/\n/,$body);
	my $last=$values[$#values];
        my $counter = 0;
        readingsBeginUpdate($hash);
        foreach my $item (@values)
        {
                my @rain_time=split(/\|/,$item);
                my $rain_raw = int($rain_time[0]);
                if ($rain_raw > 0) 
                {
                    my $rain_calc = 10**(($rain_raw-109)/32);
	            readingsBulkUpdate($hash, "rain".sprintf("%02d",$counter), sprintf("%.3f", $rain_calc));
	            #readingsBulkUpdate($hash, "rain".$counter, sprintf("%.3f", $rain_calc));
		#Log GetLogLevel($name,2), "BUIENRADAR $name . ".$rain_calc." ".$rain_raw;
                }
                else
                {
	            readingsBulkUpdate($hash, "rain".sprintf("%02d",$counter), 0);
                }
                $counter++;
        }
        readingsEndUpdate($hash, 1);
	return;
}

1;

=pod
=begin html

<a name="BUIENRADAR"></a>
<h3>BUIENRADAR</h3>
<ul>
	<a name="BUIENRADAR_Set"></a>
	<b>Set</b>
	<ul>
		N/A
	</ul>
	<br/><br />

	<a name="BUIENRADAR_Get"></a>
	<b>Get</b>
	<ul>
		N/A
	</ul>
	<br/><br />
	
	<a name="BUIENRADAR_Attr"></a>
	<b>Attr</b>
	<ul>
		N/A
	</ul>
</ul>	
=end html
=cut
