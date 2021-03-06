package CATS::Proxy;

use JSON::XS;
use LWP::UserAgent;

use CATS::Config;
use CATS::Web qw(param);

my @whitelist = qw(
    www.codechef.com
    judge.u-aizu.ac.jp
    compprog.win.tue.nl
    stats.ioinformatics.org
    scoreboard.ioinformatics.org
    rosoi.net
);

sub proxy {
    my $url = param('u') or die;
    my $r = join '|', map "\Q$_\E", @whitelist;
    $url =~ m[^http(s?)://($r)/] or die;
    my $is_https = $1;

    my $ua = LWP::UserAgent->new;
    # Workaround for LWP bug with https proxies, see http://www.perlmonks.org/?node_id=1028125
    # Use postfix 'if' to avoid trapping 'local' inside a block.
    local $ENV{https_proxy} = $CATS::Config::proxy if $CATS::Config::proxy;
    $ua->proxy($is_https ? (https => undef) : (http => "http://$CATS::Config::proxy")) if $CATS::Config::proxy;
    my $res = $ua->request(HTTP::Request->new(GET => $url, [ 'Accept', '*/*' ]));
    $res->is_success or die sprintf 'proxy http error: url=%s result=%s', $url, $res->status_line;

    if ((my $json = param('json')) =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/) {
        CATS::Web::content_type('application/json');
        print $json, '(', encode_json({ result => $res->content }), ')';
    }
    else {
        CATS::Web::content_type('text/plain');
        print $res->content;
    }
}

1;
