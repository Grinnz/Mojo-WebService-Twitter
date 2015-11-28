package Mojo::WebService::Twitter::OAuth2;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::URL;
use Mojo::Util qw(b64_encode url_escape);
use Mojo::WebService::Twitter;
use Mojo::WebService::Twitter::Error 'twitter_tx_error';

our $VERSION = '0.001';

has 'bearer_token';
has 'twitter' => sub { Mojo::WebService::Twitter->new };

sub authorize_request {
	my ($self, $tx, $token) = @_;
	$token //= $self->bearer_token // croak 'OAuth 2 bearer token is required to authorize requests';
	$tx->req->headers->authorization("Bearer $token");
	return $tx;
}

sub get_bearer_token {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	
	my ($api_key, $api_secret) = ($self->twitter->api_key, $self->twitter->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my $token = b64_encode(url_escape($api_key) . ':' . url_escape($api_secret), '');
	my $ua = $self->twitter->ua;
	my $tx = $ua->build_tx(POST => _oauth2_url('token'), form => { grant_type => 'client_credentials' });
	$self->authorize_request($tx, $token);
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->bearer_token(my $token = $tx->res->json->{access_token});
			$self->$cb(undef, $self);
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		$self->bearer_token(my $token = $tx->res->json->{access_token});
		return $self;
	}
}

sub _oauth2_url { Mojo::URL->new($Mojo::WebService::Twitter::OAUTH2_BASE_URL)->path(shift) }

1;

=head1 NAME

Mojo::WebService::Twitter::OAuth2 - OAuth 2 authorization for Twitter

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 $twitter->authorization('oauth2');
 my $oauth2 = $twitter->authorization;
 $oauth2->get_bearer_token->authorize_request($tx);

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuth2> allows L<Mojo::WebService::Twitter> to
authorize actions on behalf of the application itself using OAuth 2.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuth2> implements the following attributes.

=head2 twitter

 my $twitter = $oauth2->twitter;
 $oauth2     = $oauth2->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 bearer_token

 my $token = $oauth2->bearer_token;
 $oauth2   = $oauth2->bearer_token($token);

OAuth 2 bearer token used to authorize API requests.

=head1 METHODS

L<Mojo::WebService::Twitter::OAuth2> inherits all methods from L<Mojo::Base>,
and implements the following new ones.

=head2 authorize_request

 $tx = $oauth2->authorize_request($tx);
 $tx = $oauth2->authorize_request($tx, $token);

Authorize a L<Mojo::Transaction> for OAuth 2 using the given bearer token or
L</"bearer_token">.

=head2 get_bearer_token

 $oauth2 = $oauth2->get_bearer_token;
 $oauth2->get_bearer_token(sub {
   my ($oauth2, $error) = @_;
 });

Retrieve the OAuth 2 bearer token to use for authorization and store it as
L</"bearer_token">. The token does not expire and can be used until it is
invalidated.

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Mojo::WebService::Twitter>
