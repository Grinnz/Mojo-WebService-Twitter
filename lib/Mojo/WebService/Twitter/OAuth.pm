package Mojo::WebService::Twitter::OAuth;
use Mojo::Base -base;

use Carp 'croak';
use Digest::SHA 'hmac_sha1';
use List::Util 'pairs';
use Mojo::Parameters;
use Mojo::URL;
use Mojo::Util qw(b64_encode encode url_escape);
use Mojo::WebService::Twitter;
use Mojo::WebService::Twitter::Error 'twitter_tx_error';
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

has 'twitter' => sub { Mojo::WebService::Twitter->new };
has 'user' => sub { Mojo::WebService::Twitter::User->new(twitter => shift->twitter) };
has [qw(access_token access_secret)];

sub get_authorize_url {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	
	my ($api_key, $api_secret) = ($self->twitter->api_key, $self->twitter->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my $tx = $self->twitter->ua->build_tx(POST => _oauth_url('request_token'), form => { oauth_callback => 'oob' });
	_authorize_oauth($tx, $api_key, $api_secret);
	
	if ($cb) {
		$self->twitter->ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			my $token = $self->_from_request($tx) // return $self->$cb('OAuth callback was not confirmed');
			$self->$cb(undef, _oauth_url('authorize')->query(oauth_token => $token));
		});
	} else {
		$tx = $self->twitter->ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		my $token = $self->_from_request($tx) // die "OAuth callback was not confirmed\n";
		return _oauth_url('authorize')->query(oauth_token => $token);
	}
}

sub _from_request {
	my ($self, $tx) = @_;
	my $params = Mojo::Parameters->new($tx->res->text)->to_hash;
	return undef unless $params->{oauth_callback_confirmed} eq 'true';
	$self->{_request_secret} = $params->{oauth_token_secret};
	return $self->{_request_token} = $params->{oauth_token};
}

sub verify_authorization {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $pin) = @_;
	
	my $request_token = $self->{_request_token} // croak 'Request token has not been generated';
	my $request_secret = $self->{_request_secret} // croak 'Request token has not been generated';
	
	my ($api_key, $api_secret) = ($self->twitter->api_key, $self->twitter->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my $tx = $self->twitter->ua->build_tx(POST => _oauth_url('access_token'), form => { oauth_verifier => $pin });
	_authorize_oauth($tx, $api_key, $api_secret, $request_token, $request_secret);
	
	if ($cb) {
		$self->twitter->ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, $self->_from_verify($tx));
		});
	} else {
		$tx = $self->twitter->ua->start($tx);
		return $self->_from_verify($tx);
	}
}

sub _from_verify {
	my ($self, $tx) = @_;
	my $params = Mojo::Parameters->new($tx->res->text)->to_hash;
	my ($token, $secret, $user_id, $screen_name) = @{$params}{'oauth_token','oauth_token_secret','user_id','screen_name'};
	$self->access_token($token);
	$self->access_secret($secret);
	$self->user(my $user = Mojo::WebService::Twitter::User->new(twitter => $self->twitter, id => $user_id, screen_name => $screen_name));
	return $user;
}

sub verify_credentials {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self) = @_;
	
	my ($api_key, $api_secret) = ($self->twitter->api_key, $self->twitter->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my ($access_token, $access_secret) = ($self->access_token, $self->access_secret);
	croak 'Access credentials are required' unless defined $access_token and defined $access_secret;
	
	my $tx = $self->twitter->ua->build_tx(GET => _api_url('account/verify_credentials.json'));
	_authorize_oauth($tx, $api_key, $api_secret, $access_token, $access_secret);
	
	if ($cb) {
		$self->twitter->ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->user(my $user = Mojo::WebService::Twitter::User->new(twitter => $self->twitter)->from_source($tx->res->json));
			$self->$cb(undef, $user);
		});
	} else {
		$tx = $self->twitter->ua->start($tx);
			warn $tx->res->body;
		$self->user(my $user = Mojo::WebService::Twitter::User->new(twitter => $self->twitter)->from_source($tx->res->json));
		return $user;
	}
}

sub _api_url { Mojo::URL->new($Mojo::WebService::Twitter::API_BASE_URL)->path(shift) }

sub _oauth_url { Mojo::URL->new($Mojo::WebService::Twitter::OAUTH_BASE_URL)->path(shift) }

sub _authorize_oauth {
	my ($tx, $api_key, $api_secret, $oauth_token, $oauth_secret) = @_;
	
	my %oauth_params = (
		oauth_consumer_key => $api_key,
		oauth_nonce => _oauth_nonce(),
		oauth_signature_method => 'HMAC-SHA1',
		oauth_timestamp => time,
		oauth_version => '1.0',
	);
	$oauth_params{oauth_token} = $oauth_token if defined $oauth_token;
	
	# All oauth parameters should be moved to the header
	my $body_params = $tx->req->body_params;
	foreach my $name (grep { m/^oauth_/ } @{$body_params->names}) {
		$oauth_params{$name} = $body_params->param($name);
		$body_params->remove($name);
	}
	
	$oauth_params{oauth_signature} = _oauth_signature($tx, \%oauth_params, $api_secret, $oauth_secret);
	
	my $auth_str = join ', ', map { $_ . '="' . url_escape($oauth_params{$_}) . '"' } sort keys %oauth_params;
	$tx->req->headers->authorization("OAuth $auth_str");
	return $tx;
}

sub _oauth_nonce {
	my $str = b64_encode join('', map { chr int rand 256 } 1..24), '';
	$str =~ s/[^a-zA-Z0-9]//g;
	return $str;
}

sub _oauth_signature {
	my ($tx, $oauth_params, $api_secret, $oauth_secret) = @_;
	my $method = uc $tx->req->method;
	my $request_url = $tx->req->url;
	
	my @params = (@{$request_url->query->pairs}, @{$tx->req->body_params->pairs}, %$oauth_params);
	my @param_pairs = sort { $a->[0] cmp $b->[0] } pairs map { url_escape(encode 'UTF-8', $_) } @params;
	my $params_str = join '&', map { $_->[0] . '=' . $_->[1] } @param_pairs;
	
	my $base_url = $request_url->clone->fragment(undef)->query(undef)->to_string;
	my $signature_str = uc($method) . '&' . url_escape($base_url) . '&' . url_escape($params_str);
	my $signing_key = url_escape($api_secret) . '&' . url_escape($oauth_secret // '');
	return b64_encode(hmac_sha1($signature_str, $signing_key), '');
}

1;

=head1 NAME

Mojo::WebService::Twitter::OAuth - OAuth 1.0a client for Twitter

=head1 SYNOPSIS

 my $oauth = Mojo::WebService::Twitter::OAuth->new(twitter => $twitter);
 
 my $url = $oauth->get_authorize_url;
 my $user = $oauth->verify_authorization($pin);
 my $user = $oauth->verify_credentials;

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuth> is an OAuth 1.0a client for
L<Mojo::WebService::Twitter> to authorize actions on behalf of a specific user.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuth> implements the following attributes.

=head2 twitter

 my $twitter = $oauth->twitter;
 $oauth      = $oauth->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 access_token

 my $token = $oauth->access_token;
 $oauth    = $oauth->access_token($token);

OAuth access token used to authorize requests.

=head2 access_secret

 my $secret = $oauth->access_secret;
 $oauth     = $oauth->access_secret($secret);

OAuth access token secret used to authorize requests.

=head2 user

 my $user = $oauth->user;
 $oauth   = $oauth->user($user);

L<Mojo::WebService::Twitter::User> object representing authorizing user,
set by a successful L</"verify_authorization"> or L</"verify_credentials">.

=head1 METHODS

L<Mojo::WebService::Twitter> inherits all methods from L<Mojo::Base>, and
implements the following new ones.

=head2 get_authorize_url

 my $url = $oauth->get_authorize_url;
 $oauth->get_authorize_url(sub {
   my ($oauth, $error, $url) = @_;
 });

Retrieve a OAuth authorization URL to present to the user. After authorization,
the user will receive a PIN which can be passed to L</"verify_authorization">
to retrieve an access token and secret.

=head2 verify_authorization

 my $user = $oauth->verify_authorization($pin);
 $oauth->verify_authorization($pin, sub {
   my ($oauth, $error, $user) = @_;
 });

Verify an authorization via the URL from a previous call to
L</"get_authorize_url"> with the PIN from the authorizing user. If successful,
the OAuth token and secret will be stored as L</"access_token"> and
L</"access_secret">, and will be used for requests on behalf of the authorizing
user. The returned L<Mojo::WebService::Twitter::User> will be initialized with
the authorizing user's ID and screen name, and stored in the L</"user">
attribute.

=head2 verify_credentials

 my $user = $oauth->verify_credentials;
 $oauth->verify_credentials(sub {
   my ($oauth, $error, $user) = @_;
 });

Verify the stored L</"access_token"> and L</"access_secret">. On success, the
returned L<Mojo::WebService::Twitter::User> object will be fully initialized
and stored in the L</"user"> attribute.

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
