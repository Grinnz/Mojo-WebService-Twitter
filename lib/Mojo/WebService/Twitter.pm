package Mojo::WebService::Twitter;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Collection;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(b64_encode url_escape);
use Mojo::WebService::Twitter::Error 'twitter_tx_error';
use Mojo::WebService::Twitter::OAuth;
use Mojo::WebService::Twitter::Tweet;
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

our $API_BASE_URL = 'https://api.twitter.com/1.1/';
our $OAUTH_BASE_URL = 'https://api.twitter.com/oauth/';
our $OAUTH2_BASE_URL = 'https://api.twitter.com/oauth2/';

has ['api_key','api_secret'];
has 'ua' => sub { Mojo::UserAgent->new };

sub get_tweet {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $id) = @_;
	croak 'Tweet id is required for get_tweet' unless defined $id;
	my $url = _api_url('statuses/show.json')->query(id => $id);
	if ($cb) {
		$self->_oauth2_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			my $tx = _authorize_oauth2($self->ua->build_tx(GET => $url), $token);
			$self->ua->start($tx, sub {
				my ($ua, $tx) = @_;
				return $self->$cb(twitter_tx_error($tx)) if $tx->error;
				$self->$cb(undef, $self->_tweet_object($tx->res->json));
			});
		});
	} else {
		my $token = $self->_oauth2_access_token;
		my $tx = $self->ua->start(_authorize_oauth2($self->ua->build_tx(GET => $url), $token));
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
	my $url = _api_url('users/show.json')->query(%query);
	if ($cb) {
		$self->_oauth2_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			my $tx = _authorize_oauth2($self->ua->build_tx(GET => $url), $token);
			$self->ua->start($tx, sub {
				my ($ua, $tx) = @_;
				return $self->$cb(twitter_tx_error($tx)) if $tx->error;
				$self->$cb(undef, $self->_user_object($tx->res->json));
			});
		});
	} else {
		my $token = $self->_oauth2_access_token;
		my $tx = $self->ua->start(_authorize_oauth2($self->ua->build_tx(GET => $url), $token));
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
	my $url = _api_url('search/tweets.json')->query(%query);
	if ($cb) {
		$self->_oauth2_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			my $tx = _authorize_oauth2($self->ua->build_tx(GET => $url), $token);
			$self->ua->start($tx, sub {
				my ($ua, $tx) = @_;
				return $self->$cb(twitter_tx_error($tx)) if $tx->error;
				$self->$cb(undef, Mojo::Collection->new(@{$tx->res->json->{statuses} // []}));
			});
		});
	} else {
		my $token = $self->_oauth2_access_token;
		my $tx = $self->ua->start(_authorize_oauth2($self->ua->build_tx(GET => $url), $token));
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return Mojo::Collection->new(@{$tx->res->json->{statuses} // []});
	}
}

sub oauth { my $self = shift; return Mojo::WebService::Twitter::OAuth->new(twitter => $self, @_) }

sub _api_url { Mojo::URL->new($API_BASE_URL)->path(shift) }

sub _oauth2_url { Mojo::URL->new($OAUTH2_BASE_URL)->path(shift) }

sub _oauth2_access_token {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	if (exists $self->{_oauth2_access_token}) {
		return $cb ? $self->$cb(undef, $self->{_oauth2_access_token}) : $self->{_oauth2_access_token};
	}
	
	my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
	croak 'Twitter API key and secret are required'
		unless defined $api_key and defined $api_secret;
	my $url = _oauth2_url('token');
	my $bearer_token = b64_encode(url_escape($api_key) . ':' . url_escape($api_secret), '');
	my $tx = $self->ua->build_tx(POST => $url, form => { grant_type => 'client_credentials' });
	_authorize_oauth2($tx, $bearer_token);
	
	if ($cb) {
		$self->ua->start($tx, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(twitter_tx_error($tx)) if $tx->error;
			$self->$cb(undef, $self->{_oauth2_access_token} = $tx->res->json->{access_token});
		});
	} else {
		$tx = $self->ua->start($tx);
		die twitter_tx_error($tx) . "\n" if $tx->error;
		return $self->{_oauth2_access_token} = $tx->res->json->{access_token};
	}
}

sub _authorize_oauth2 {
	my ($tx, $token) = @_;
	$tx->req->headers->authorization("Bearer $token");
	return $tx;
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
 
 # Blocking
 my $user = $twitter->get_user(screen_name => $name);
 say $user->screen_name . ' was created on ' . $user->created_at->ymd;
 
 # Non-blocking
 $twitter->get_tweet($tweet_id, sub {
   my ($twitter, $err, $tweet) = @_;
   say $err ? "Error: $err" : 'Tweet: ' . $tweet->text;
 });
 Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::WebService::Twitter> is a L<Mojo::UserAgent> based
L<Twitter|https://twitter.com> API client that can perform requests
synchronously or asynchronously. An API key and secret for a
L<Twitter Application|https://apps.twitter.com> are required.

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

=head2 oauth

 my $oauth = $twitter->oauth;
 my $oauth = $twitter->oauth(access_token => $token, access_secret => $secret);

Returns a new L<Mojo::WebService::Twitter::OAuth> object for interacting with
the Twitter API on behalf of a specific user.

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
