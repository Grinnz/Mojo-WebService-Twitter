use Mojolicious::Lite;

del     '/' => { json => ['delete'] };
get     '/' => { json => ['get'] };
options '/' => { json => ['options'] };
patch   '/' => { json => ['patch'] };
post    '/' => { json => ['post'] };
put     '/' => { json => ['put'] };

get '/die' => sub { die "Boom\n" };

use Mojo::IOLoop;
use Mojo::WebService;
use Test::More;

my @methods = qw(delete get options patch post put);

my $w = Mojo::WebService->new;
$w->ua->server->app->log->level('fatal');

# Blocking
is $w->ua_request($_ => '/')->json->[0], $_, 'right response' for @methods;
ok defined($w->ua_request(head => '/')), 'no error';

ok !eval { $w->ua_request(get => '/die'); 1 }, 'threw HTTP error';
ok !eval { $w->ua_request(get => '/foo'); 1 }, 'threw HTTP error';

is $w->ua_request_lenient(get => '/die')->error->{code}, '500', 'right HTTP error';
is $w->ua_request_lenient(get => '/foo')->error->{code}, '404', 'right HTTP error';

# Non-blocking
Mojo::IOLoop->delay(sub {
	my $delay = shift;
	$w->ua_request($_ => '/', $delay->begin) for @methods, 'head';
}, sub {
	my $delay = shift;
	foreach my $method (@methods, 'head') {
		my ($err, $res) = (shift, shift);
		is $err, undef, 'no error';
		unless ($method eq 'head') {
			is $res->json->[0], $method, 'right response';
		}
	}
})->wait;

Mojo::IOLoop->delay(sub {
	my $delay = shift;
	$w->ua_request(get => '/die', $delay->begin);
	$w->ua_request(get => '/foo', $delay->begin);
}, sub {
	my ($delay, $err1, $res1, $err2, $res2) = @_;
	like $err1, qr/500/, 'right HTTP error';
	like $err2, qr/404/, 'right HTTP error';
})->wait;

Mojo::IOLoop->delay(sub {
	my $delay = shift;
	$w->ua_request_lenient(get => '/die', $delay->begin);
	$w->ua_request_lenient(get => '/foo', $delay->begin);
}, sub {
	my ($delay, $err1, $res1, $err2, $res2) = @_;
	is $err1, undef, 'no connection error';
	is $res1->error->{code}, '500', 'right HTTP error';
	is $err2, undef, 'no connection error';
	is $res2->error->{code}, '404', 'right HTTP error';
})->wait;

# Transport errors
$w->ua->on(start => sub { $_[1]->res->error({message => "Boom"}) });

ok !eval { $w->ua_request(get => '/'); 1 }, 'threw connection error';
like $@, qr/Boom/, 'right error';
ok !eval { $w->ua_request_lenient(get => '/'); 1 }, 'threw connection error';
like $@, qr/Boom/, 'right error';

Mojo::IOLoop->delay(sub {
	my $delay = shift;
	$w->ua_request(get => '/', $delay->begin);
	$w->ua_request_lenient(get => '/', $delay->begin);
}, sub {
	my ($delay, $err1, $res1, $err2, $res2) = @_;
	like $err1, qr/Boom/, 'right error';
	like $err2, qr/Boom/, 'right error';
})->wait;

done_testing;
