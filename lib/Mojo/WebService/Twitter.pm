package Mojo::WebService::Twitter;
use Mojo::Base -base;

use Carp 'croak';
use Scalar::Util 'weaken';
use Mojo::Collection;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(b64_encode url_escape);
use Mojo::WebService::Twitter::Error 'twitter_tx_error';
use Mojo::WebService::Twitter::OAuth;
use Mojo::WebService::Twitter::OAuth2;
use Mojo::WebService::Twitter::Tweet;
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

our $API_BASE_URL = 'https://api.twitter.com/1.1/';
our $OAUTH_BASE_URL = 'https://api.twitter.com/oauth/';
our $OAUTH2_BASE_URL = 'https://api.twitter.com/oauth2/';

has ['api_key','api_secret'];
has 'ua' => sub { Mojo::UserAgent->new };

sub authorization {
	my $self = shift;
	return $self->{authorization} //= $self->_oauth2 unless @_;
	my $auth = shift;
	if (ref $auth) {
		$self->{authorization} = $auth;
	} elsif ($auth eq 'oauth') {
		$self->{authorization} = $self->_oauth(@_);
	} elsif ($auth eq 'oauth2') {
		$self->{authorization} = $self->_oauth2(@_);
	} else {
		croak "Unknown authorization $auth";
	}
	return $self;
}

sub get_tweet {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $id) = @_;
	croak 'Tweet id is required for get_tweet' unless defined $id;
	my $ua = $self->ua;
	my $tx = $ua->build_tx(GET => _api_url('statuses/show.json')->query(id => $id));
	$self->authorization->authorize_request($tx);
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
	$self->authorization->authorize_request($tx);
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
	$self->authorization->authorize_request($tx);
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
	$self->authorization->authorize_request($tx);
	
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

sub _oauth {
	my $self = shift;
	my $oauth = Mojo::WebService::Twitter::OAuth->new(twitter => $self, @_);
	weaken($oauth->{twitter});
	return $oauth;
}

sub _oauth2 {
	my $self = shift;
	my $oauth2 = Mojo::WebService::Twitter::OAuth2->new(twitter => $self, @_);
	weaken($oauth2->{twitter});
	return $oauth2;
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
 $twitter->authorization->get_bearer_token;
 
 # Blocking
 my $user = $twitter->get_user(screen_name => $name);
 say $user->screen_name . ' was created on ' . $user->created_at->ymd;
 
 # Non-blocking
 $twitter->get_tweet($tweet_id, sub {
   my ($twitter, $err, $tweet) = @_;
   say $err ? "Error: $err" : 'Tweet: ' . $tweet->text;
 });
 Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
 
 # Some requests require user-specific authentication
 $twitter->authorization('oauth', access_token => $token, access_secret => $secret);
 my $user = $twitter->verify_credentials;

=head1 DESCRIPTION

L<Mojo::WebService::Twitter> is a L<Mojo::UserAgent> based
L<Twitter|https://twitter.com> API client that can perform requests
synchronously or asynchronously. An API key and secret for a
L<Twitter Application|https://apps.twitter.com> are required.

API requests are authorized by the L</"authorization"> object, which can either
be a L<Mojo::WebService::Twitter::OAuth2> object to authorize requests on
behalf of the application itself, or a more complex
L<Mojo::WebService::Twitter::OAuth> object to authorize requests on behalf of a
specific user.

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

=head2 authorization

 my $oauth = $twitter->authorization;
 $twitter  = $twitter->authorization($oauth);
 $twitter  = $twitter->authorization('oauth2', bearer_token => $token);
 $twitter  = $twitter->authorization('oauth', access_token => $token, access_secret => $secret);

Get or set object used to authorize API requests. If the first argument is
C<oauth>, a L<Mojo::WebService::Twitter::OAuth> object will be created. If the
first argument is C<oauth2>, a L<Mojo::WebService::Twitter::OAuth2> object will
be created. Defaults to OAuth 2.

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
L<Mojo::WebService::Twitter::User> object. Requires OAuth 1.0a authorization.

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Net::Twitter>
