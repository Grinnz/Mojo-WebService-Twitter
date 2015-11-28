package Mojo::WebService::Twitter::OAuthRequest;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Parameters;
use Mojo::URL;
use Mojo::WebService::Twitter;
use Mojo::WebService::Twitter::Error 'twitter_tx_error';
use Mojo::WebService::Twitter::OAuth;
use Mojo::WebService::Twitter::User;
use Scalar::Util 'weaken';

our $VERSION = '0.001';

has [qw(request_token request_secret)];
has 'twitter' => sub { Mojo::WebService::Twitter->new };

sub authorize_url { _oauth_url('authorize')->query(oauth_token => shift->request_token) }

sub verify_authorization {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $verifier) = @_;
	
	my ($request_token, $request_secret) = ($self->request_token, $self->request_secret);
	croak 'Request token has not been generated' unless defined $request_token and defined $request_secret;
	
	my $ua = $self->twitter->ua;
	my $tx = $ua->build_tx(POST => _oauth_url('access_token'), form => { oauth_verifier => $verifier });
	my $authorizer = Mojo::WebService::Twitter::OAuth->new(twitter => $self->twitter,
		access_token => $request_token, access_secret => $request_secret);
	$authorizer->authorize_request($tx);
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, $self->_from_verify($tx));
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return $self->_from_verify($tx);
	}
}

sub _from_verify {
	my ($self, $tx) = @_;
	my $params = Mojo::Parameters->new($tx->res->text)->to_hash;
	my ($token, $secret, $user_id, $screen_name) = @{$params}{'oauth_token','oauth_token_secret','user_id','screen_name'};
	my $user = Mojo::WebService::Twitter::User->new(twitter => $self->twitter, id => $user_id, screen_name => $screen_name);
	my $oauth = Mojo::WebService::Twitter::OAuth->new(twitter => $self->twitter,
		access_token => $token, access_secret => $secret, user => $user);
	weaken $oauth->{twitter};
	weaken $user->{twitter};
	return $oauth;
}

sub _oauth_url { Mojo::URL->new($Mojo::WebService::Twitter::OAUTH_BASE_URL)->path(shift) }

1;

=head1 NAME

Mojo::WebService::Twitter::OAuthRequest - OAuth 1.0a auth request for Twitter

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 my $oreq = $twitter->request_oauth;
 
 my $url = $oreq->authorize_url;
 my $oauth = $oreq->verify_authorization($pin);
 $oauth->authorize_request($tx);
 $twitter->authorization($oauth);
 
=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuthRequest> allows L<Mojo::WebService::Twitter>
to request authorization for making requests on behalf of a specific user using
OAuth 1.0a.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuthRequest> implements the following attributes.

=head2 twitter

 my $twitter = $oreq->twitter;
 $oreq       = $oreq->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 request_token

 my $token = $oreq->request_token;
 $oreq     = $oreq->request_token($token);

OAuth request token used to request authorization.

=head2 request_secret

 my $secret = $oreq->request_secret;
 $oreq      = $oreq->request_secret($secret);

OAuth request token secret used to request authorization.

=head1 METHODS

L<Mojo::WebService::Twitter::OAuthRequest> inherits all methods from
L<Mojo::Base>, and implements the following new ones.

=head2 authorize_url

 my $url = $oreq->authorize_url;

Returns an OAuth authorization URL to present to the user using
L</"request_token">. Depending on the C<oauth_callback> provided when obtaining
the request token, the user will either be redirected to the callback or given
a PIN. The query parameter C<oauth_verifier> or the PIN should be passed to
L</"verify_authorization"> to retrieve an access token and secret.

=head2 verify_authorization

 my $oauth = $oreq->verify_authorization($verifier);
 $oreq->verify_authorization($verifier, sub {
   my ($oreq, $error, $oauth) = @_;
 });

Verify an authorization request with the verifier string or PIN from the
authorizing user. If successful, a L<Mojo::WebService::Twitter::OAuth> object
that can be used to authorize requests on behalf of the user will be returned.

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
