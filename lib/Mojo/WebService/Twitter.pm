package Mojo::WebService::Twitter;
use Mojo::Base -base;

use Carp 'croak';
use Scalar::Util 'blessed', 'weaken';
use Mojo::Collection;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(b64_encode url_escape);
use Mojo::WebService::Twitter::Error 'twitter_tx_error';
use Mojo::WebService::Twitter::Tweet;
use Mojo::WebService::Twitter::User;
use WWW::OAuth;

our $VERSION = '0.001';

our $API_BASE_URL = 'https://api.twitter.com/1.1/';
our $OAUTH_BASE_URL = 'https://api.twitter.com/oauth/';
our $OAUTH2_BASE_URL = 'https://api.twitter.com/oauth2/';

has ['api_key','api_secret'];
has 'ua' => sub { Mojo::UserAgent->new };

sub authentication {
	my $self = shift;
	return $self->{authentication} // croak 'No authentication set' unless @_;
	my $auth = shift;
	if (ref $auth eq 'CODE') {
		$self->{authentication} = $auth;
	} elsif (ref $auth eq 'HASH') {
		if (defined $auth->{access_token}) {
			$self->{authentication} = $self->_oauth2(token => $auth->{access_token});
		} elsif (defined $auth->{oauth_token} and defined $auth->{oauth_token_secret}) {
			$self->{authentication} = $self->_oauth(token => $auth->{oauth_token}, token_secret => $auth->{oauth_token_secret});
		} else {
			croak 'Unrecognized authentication hashref (no oauth_token or access_token)';
		}
	} elsif ($auth eq 'oauth') {
		$self->{authentication} = $self->_oauth(@_);
	} elsif ($auth eq 'oauth2') {
		$self->{authentication} = $self->_oauth2(@_);
	} else {
		croak "Unknown authentication $auth";
	}
	return $self;
}

sub request_oauth {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $url) = @_;
	$url //= 'oob';
	
	my $ua = $self->ua;
	my $tx = $ua->build_tx(POST => _oauth_url('request_token'));
	$self->_oauth->($tx->req, { oauth_callback => $url });
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			my $res = $self->_from_oauth_request($tx) // return $self->$cb('OAuth callback was not confirmed');
			$self->$cb(undef, $res);
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		my $res = $self->_from_oauth_request($tx) // die "OAuth callback was not confirmed\n";
		return $res;
	}
}

sub _from_oauth_request {
	my ($self, $tx) = @_;
	my $params = Mojo::Parameters->new($tx->res->text)->to_hash;
	return undef unless $params->{oauth_callback_confirmed} eq 'true'
		and defined $params->{oauth_token} and defined $params->{oauth_token_secret};
	$self->{request_token_secrets}{$params->{oauth_token}} = $params->{oauth_token_secret};
	return $params;
}

sub verify_oauth {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $verifier, $request_token, $request_token_secret) = @_;
	
	$request_token_secret //= delete $self->{request_token_secrets}{$request_token} // croak "Unknown request token";
	
	my $ua = $self->ua;
	my $tx = $ua->build_tx(POST => _oauth_url('access_token'));
	$self->_oauth(token => $request_token, token_secret => $request_token_secret)
		->($tx->req, { oauth_verifier => $verifier });
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			my $res = $self->_from_verify_oauth($tx) // return $self->$cb('No OAuth token returned');
			$self->$cb(undef, $res);
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		my $res = $self->_from_verify_oauth($tx) // die "No OAuth token returned\n";
		return $res;
	}
}

sub _from_verify_oauth {
	my ($self, $tx) = @_;
	my $params = Mojo::Parameters->new($tx->res->text)->to_hash;
	return undef unless defined $params->{'oauth_token'} and defined $params->{'oauth_token_secret'};
	return $params;
}

sub request_oauth2 {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	
	my $ua = $self->ua;
	my $tx = $ua->build_tx(POST => _oauth2_url('token'), form => { grant_type => 'client_credentials' });
	$self->_oauth2_request->($tx->req);
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			my $res = $self->_from_oauth2_request($tx) // return $self->$cb('No bearer token returned');
			$self->$cb(undef, $res);
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		my $res = $self->_from_oauth2_request($tx) // die "No bearer token returned\n";
		return $res;
	}
}

sub _from_oauth2_request {
	my ($self, $tx) = @_;
	my $params = $tx->res->json // {};
	return undef unless defined $params->{access_token};
	return $params;
}

sub get_tweet {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $id) = @_;
	croak 'Tweet id is required for get_tweet' unless defined $id;
	my $ua = $self->ua;
	my $tx = $ua->build_tx(GET => _api_url('statuses/show.json')->query(id => $id));
	$self->authentication->($tx->req);
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, $self->_tweet_object($tx->res->json));
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return $self->_tweet_object($tx->res->json);
	}
}

sub get_user {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, %params) = @_;
	my %query;
	$query{user_id} = $params{user_id} if defined $params{user_id};
	$query{screen_name} = $params{screen_name} if defined $params{screen_name};
	croak 'user_id or screen_name is required for get_user' unless %query;
	my $ua = $self->ua;
	my $tx = $ua->build_tx(GET => _api_url('users/show.json')->query(%query));
	$self->authentication->($tx->req);
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, $self->_user_object($tx->res->json));
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return $self->_user_object($tx->res->json);
	}
}

sub search_tweets {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $q, %params) = @_;
	croak 'Search query is required for search_tweets' unless defined $q;
	my %query;
	$query{q} = $q;
	my $geocode = $params{geocode};
	if (ref $geocode) {
		my ($lat, $long, $rad);
		($lat, $long, $rad) = @$geocode if ref $geocode eq 'ARRAY';
		($lat, $long, $rad) = @{$geocode}{'latitude','longitude','radius'} if ref $geocode eq 'HASH';
		$geocode = "$lat,$long,$rad" if defined $lat and defined $long and defined $rad;
	}
	$query{geocode} = $geocode if defined $geocode;
	$query{$_} = $params{$_} for grep { defined $params{$_} } qw(lang result_type count until since_id max_id);
	my $ua = $self->ua;
	my $tx = $ua->build_tx(GET => _api_url('search/tweets.json')->query(%query));
	$self->authentication->($tx->req);
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, Mojo::Collection->new(@{$tx->res->json->{statuses} // []}));
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return Mojo::Collection->new(@{$tx->res->json->{statuses} // []});
	}
}

sub verify_credentials {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self) = @_;
	
	my $ua = $self->ua;
	my $tx = $ua->build_tx(GET => _api_url('account/verify_credentials.json'));
	$self->authentication->($tx->req);
	
	if ($cb) {
		$ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			my $user = Mojo::WebService::Twitter::User->new(twitter => $self)->from_source($tx->res->json);
			$self->$cb(undef, $user);
		});
	} else {
		$tx = $ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		my $user = Mojo::WebService::Twitter::User->new(twitter => $self)->from_source($tx->res->json);
		return $user;
	}
}

sub _api_url { Mojo::URL->new($API_BASE_URL)->path(shift) }

sub _oauth_url { Mojo::URL->new($OAUTH_BASE_URL)->path(shift) }

sub _oauth2_url { Mojo::URL->new($OAUTH2_BASE_URL)->path(shift) }

sub _oauth {
	my $self = shift;
	my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my %args = @_;
	my $oauth = WWW::OAuth->new(
		client_id => $api_key,
		client_secret => $api_secret,
		token => $args{token},
		token_secret => $args{token_secret},
	);
	return sub { $oauth->authenticate(@_) };
}

sub _oauth2_request {
	my $self = shift;
	my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my $token = b64_encode(url_escape($api_key) . ':' . url_escape($api_secret), '');
	return sub { shift->headers->authorization("Basic $token") };
}

sub _oauth2 {
	my $self = shift;
	my %args = @_;
	my $token = $args{token} // croak 'OAuth2 access token is required';
	return sub { shift->headers->authorization("Bearer $token") };
}

sub _tweet_object {
	my ($self, $source) = @_;
	return Mojo::WebService::Twitter::Tweet->new(twitter => $self)->from_source($source);
}

sub _user_object {
	my ($self, $source) = @_;
	return Mojo::WebService::Twitter::User->new(twitter => $self)->from_source($source);
}

1;

=head1 NAME

Mojo::WebService::Twitter - Simple Twitter API client

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 $twitter->authentication($twitter->request_oauth2);
 
 # Blocking
 my $user = $twitter->get_user(screen_name => $name);
 say $user->screen_name . ' was created on ' . $user->created_at->ymd;
 
 # Non-blocking
 $twitter->get_tweet($tweet_id, sub {
   my ($twitter, $err, $tweet) = @_;
   say $err ? "Error: $err" : 'Tweet: ' . $tweet->text;
 });
 Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
 
 # Some requests require authentication on behalf of a user
 $twitter->authentication('oauth', token => $token, token_secret => $secret);
 my $authorizing_user = $twitter->verify_credentials;

=head1 DESCRIPTION

L<Mojo::WebService::Twitter> is a L<Mojo::UserAgent> based
L<Twitter|https://twitter.com> API client that can perform requests
synchronously or asynchronously. An API key and secret for a
L<Twitter Application|https://apps.twitter.com> are required.

API requests are authenticated by the L</"authentication"> coderef, which can
either use an OAuth 2.0 access token to authenticate requests on behalf of the
application itself, or OAuth 1.0 credentials to authenticate requests on behalf
of a specific user.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter> implements the following attributes.

=head2 api_key

 my $api_key = $twitter->api_key;
 $twitter    = $twitter->api_key($api_key);

API key for your L<Twitter Application|https://apps.twitter.com>.

=head2 api_secret

 my $api_secret = $twitter->api_secret;
 $twitter       = $twitter->api_secret($api_secret);

API secret for your L<Twitter Application|https://apps.twitter.com>.

=head2 ua

 my $ua      = $webservice->ua;
 $webservice = $webservice->ua(Mojo::UserAgent->new);

HTTP user agent object to use for synchronous and asynchronous requests,
defaults to a L<Mojo::UserAgent> object.

=head1 METHODS

L<Mojo::WebService::Twitter> inherits all methods from L<Mojo::Base>, and
implements the following new ones.

=head2 authentication

 my $code = $twitter->authentication;
 $twitter = $twitter->authentication($code);
 $twitter = $twitter->authentication({oauth_token => $access_token, oauth_token_secret => $access_token_secret});
 $twitter = $twitter->authentication('oauth', token => $access_token, token_secret => $access_token_secret);
 $twitter = $twitter->authentication({access_token => $access_token});
 $twitter = $twitter->authentication('oauth2', token => $access_token);

Get or set coderef used to authenticate API requests. Passing C<oauth> with
optional C<token> and C<token_secret>, or a hashref containing C<oauth_token>
and C<oauth_token_secret>, will set a coderef which uses a L<WWW::OAuth> to
authenticate requests. Passing C<oauth2> with required C<token> or a hashref
containing C<access_token> will set a coderef which authenticates using the
passed access token. The coderef will receive the L<Mojo::Message::Request>
object as the first parameter, and an optional hashref of C<oauth_> parameters.

=head2 request_oauth

 my $res = $twitter->request_oauth;
 my $res = $twitter->request_oauth($callback_url);
 $twitter->request_oauth(sub {
   my ($twitter, $error, $res) = @_;
 });

Send an OAuth 1.0 authorization request and return a hashref containing
C<oauth_token> and C<oauth_token_secret> (request token and secret). An
optional OAuth callback URL may be passed; by default, C<oob> is passed to use
PIN-based authorization. The user should be directed to the authorization URL
which can be retrieved by passing the request token to
L<Mojo::WebService::Twitter::Util/"twitter_authorize_url">. After
authorization, the user will either be redirected to the callback URL with the
query parameter C<oauth_verifier>, or receive a PIN to return to the
application. Either the verifier string or PIN should be passed to
L</"verify_oauth"> to retrieve an access token and secret.

=head2 verify_oauth

 my $res = $twitter->verify_oauth($verifier, $request_token, $request_token_secret);
 $twitter->verify_oauth($verifier, $request_token, $request_token_secret, sub {
   my ($twitter, $error, $res) = @_;
 });

Verify an OAuth 1.0 authorization request with the verifier string or PIN from
the authorizing user, and the previously obtained request token and secret. The
secret is cached by L</"request_oauth"> and may be omitted. Returns a hashref
containing C<oauth_token> and C<oauth_token_secret> (access token and secret)
which may be passed directly to L</"authentication"> to authenticate requests
on behalf of the user.

=head2 request_oauth2

 my $res = $twitter->request_oauth2;
 $twitter->request_oauth2(sub {
   my ($twitter, $error, $res) = @_;
 });

Request OAuth 2 credentials and return a hashref containing an C<access_token>
that can be passed directly to L</"authentication"> to authenticate requests on
behalf of the application itself.

=head2 get_tweet

 my $tweet = $twitter->get_tweet($tweet_id);
 $twitter->get_tweet($tweet_id, sub {
   my ($twitter, $err, $tweet) = @_;
 });

Retrieve a L<Mojo::WebService::Twitter::Tweet> by tweet ID.

=head2 get_user

 my $user = $twitter->get_user(user_id => $user_id);
 my $user = $twitter->get_user(screen_name => $screen_name);
 $twitter->get_user(screen_name => $screen_name, sub {
   my ($twitter, $err, $user) = @_;
 });

Retrieve a L<Mojo::WebService::Twitter::User> by user ID or screen name.

=head2 search_tweets

 my $tweets = $twitter->search_tweets($query);
 my $tweets = $twitter->search_tweets($query, %options);
 $twitter->search_tweets($query, %options, sub {
   my ($twitter, $err, $tweets) = @_;
 });

Search Twitter and return a L<Mojo::Collection> of L<Mojo::WebService::Twitter::Tweet>
objects. Accepts the following options:

=over

=item geocode

 geocode => '37.781157,-122.398720,1mi'
 geocode => ['37.781157','-122.398720','1mi']
 geocode => {latitude => '37.781157', longitude => '-122.398720', radius => '1mi'}

Restricts tweets to the given radius of the given latitude/longitude. Radius
must be specified as C<mi> (miles) or C<km> (kilometers).

=item lang

 lang => 'eu'

Restricts tweets to the given L<ISO 639-1|http://en.wikipedia.org/wiki/List_of_ISO_639-1_codes>
language code.

=item result_type

 result_type => 'recent'

Specifies what type of search results to receive. Valid values are C<recent>,
C<popular>, and C<mixed> (default).

=item count

 count => 5

Limits the search results per page. Maximum C<100>, default C<15>.

=item until

 until => '2015-07-19'

Restricts tweets to those created before the given date, in the format
C<YYYY-MM-DD>.

=item since_id

 since_id => '12345'

Restricts results to those more recent than the given tweet ID. IDs should be
specified as a string to avoid issues with large integers. See
L<here|https://dev.twitter.com/rest/public/timelines> for more information on
filtering results with C<since_id> and C<max_id>.

=item max_id

 max_id => '54321'

Restricts results to those older than (or equal to) the given tweet ID. IDs
should be specified as a string to avoid issues with large integers. See
L<here|https://dev.twitter.com/rest/public/timelines> for more information on
filtering results with C<since_id> and C<max_id>.

=back

=head2 verify_credentials

 my $user = $twitter->verify_credentials;
 $twitter->verify_credentials(sub {
   my ($twitter, $error, $user) = @_;
 });

Verify the authorizing user's credentials and return a representative
L<Mojo::WebService::Twitter::User> object. Requires OAuth 1.0 authentication.

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Net::Twitter>, L<WWW::OAuth>
