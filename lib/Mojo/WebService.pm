package Mojo::WebService;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::UserAgent;

our $VERSION = '0.001';

has 'ua' => sub { Mojo::UserAgent->new };

my %methods = map { ($_ => 1) } qw(DELETE GET HEAD OPTIONS PATCH POST PUT);
sub ua_request {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $method, @args) = @_;
	$method = uc $method;
	croak "Unknown HTTP method $method" unless exists $methods{$method};
	my $req_tx = $self->ua->build_tx($method => @args);
	my $allow_http_errors = delete $self->{_allow_http_errors};
	if ($cb) {
		$self->ua->start($req_tx, sub {
			my ($ua, $tx) = @_;
			my $err;
			$err = _ua_error($tx->error) if $tx->error
				and !($allow_http_errors and $tx->error->{code});
			$self->$cb($err, $tx->res);
		});
	} else {
		my $tx = $self->ua->start($req_tx);
		croak _ua_error($tx->error) if $tx->error
			and !($allow_http_errors and $tx->error->{code});
		return $tx->res;
	}
}

sub ua_request_lenient {
	my $self = shift;
	local $self->{_allow_http_errors} = 1;
	return $self->ua_request(@_);
}

sub _ua_error {
	my $err = shift;
	return $err->{code}
		? "HTTP error $err->{code}: $err->{message}"
		: "Connection error: $err->{message}";
}

1;

=head1 NAME

Mojo::WebService - Simple API client base class

=head1 SYNOPSIS

 package Mojo::WebService::Stuff;
 use Mojo::Base 'Mojo::WebService';
 
 sub get_stuff {
   my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
   my ($self, $stuff) = @_;
   my $url = Mojo::URL->new('http://example.com')->query(stuff => $stuff);
   if ($cb) {
     $self->ua_request(get => $url, sub {
       my ($self, $err, $res) = @_;
       return $self->$cb($err) if $err;
       $self->$cb(undef, $res->json);
     });
   } else {
     return $self->ua_request(get => $url)->json;
   }
 }

=head1 DESCRIPTION

L<Mojo::WebService> is a base class for L<Mojo::UserAgent> based API clients.

=head1 ATTRIBUTES

=head2 ua

 my $ua      = $webservice->ua;
 $webservice = $webservice->ua(Mojo::UserAgent->new);

HTTP user agent object to use for synchronous and asynchronous requests,
defaults to a L<Mojo::UserAgent> object.

=head1 METHODS

=head2 ua_request

 my $res     = $webservice->ua_request($method => @args);
 $webservice = $webservice->ua_request($method => @args, sub {
   my ($webservice, $err, $res) = @_;
 });

Build a HTTP request using L<Mojo::UserAgent/"build_tx"> and run blocking or
non-blocking with L<Mojo::UserAgent/"start">. In blocking mode, the
L<Mojo::Message::Response> is returned on success, and an exception is thrown
on connection or HTTP error. If a callback is passed, the request will be
performed non-blocking, and the connection or HTTP error (if any) will instead
be passed to the callback.

=head2 ua_request_lenient

Run a HTTP request via L</"ua_request">, but HTTP errors will not throw an
exception or be returned in the callback. C<< $res->error >> can be used to
check for HTTP errors manually, see L<Mojo::Message/"error">. Connection errors
will still be reported normally.

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Mojo::UserAgent>
