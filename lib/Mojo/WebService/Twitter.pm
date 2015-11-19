package Mojo::WebService::Twitter;
use Mojo::Base -base;

use Carp 'croak';
use Digest::SHA 'hmac_sha1';
use List::Util 'pairs';
use Mojo::Collection;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util qw(b64_encode encode url_escape);
use Mojo::WebService::Twitter::Error;
use Mojo::WebService::Twitter::Tweet;
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

our $OAUTH2_ENDPOINT = 'https://api.twitter.com/oauth2/token';
our $OAUTH_BASE_URL = 'https://api.twitter.com/oauth/';
our $API_BASE_URL = 'https://api.twitter.com/1.1/';

has ['api_key','api_secret'];
has 'ua' => sub { Mojo::UserAgent->new };

sub get_tweet {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $id) = @_;
	croak 'Tweet id is required for get_tweet' unless defined $id;
	if ($cb) {
		$self->_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			$self->ua->get(_api_url('statuses/show.json', id => $id), _api_headers($token), sub {
				my ($ua, $tx) = @_;
				return $self->$cb(_api_error($tx)) if $tx->error;
				$self->$cb(undef, $self->_tweet_object($tx->res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $tx = $self->ua->get(_api_url('statuses/show.json', id => $id), _api_headers($token));
		die _api_error($tx) . "\n" if $tx->error;
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
	if ($cb) {
		$self->_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			$self->ua->get(_api_url('users/show.json', %query), _api_headers($token), sub {
				my ($ua, $tx) = @_;
				return $self->$cb(_api_error($tx)) if $tx->error;
				$self->$cb(undef, $self->_user_object($tx->res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $tx = $self->ua->get(_api_url('users/show.json', %query), _api_headers($token));
		die _api_error($tx) . "\n" if $tx->error;
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
	if ($cb) {
		$self->_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			$self->ua->get(_api_url('search/tweets.json', %query), _api_headers($token), sub {
				my ($ua, $tx) = @_;
				return $self->$cb(_api_error($tx)) if $tx->error;
				$self->$cb(undef, Mojo::Collection->new(@{$tx->res->json->{statuses} // []}));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $tx = $self->ua->get(_api_url('search/tweets.json', %query), _api_headers($token));
		die _api_error($tx) . "\n" if $tx->error;
		return Mojo::Collection->new(@{$tx->res->json->{statuses} // []});
	}
}

sub _access_token {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	if (exists $self->{_access_token}) {
		return $cb ? $self->$cb(undef, $self->{_access_token}) : $self->{_access_token};
	}
	
	my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
	croak 'Twitter API key and secret are required'
		unless defined $api_key and defined $api_secret;
	my @token_request = _access_token_request($api_key, $api_secret);
	
	if ($cb) {
		$self->ua->post(@token_request, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(_api_error($tx)) if $tx->error;
			$self->$cb(undef, $self->{_access_token} = $tx->res->json->{access_token});
		});
	} else {
		my $tx = $self->ua->post(@token_request);
		die _api_error($tx) . "\n" if $tx->error;
		return $self->{_access_token} = $tx->res->json->{access_token};
	}
}

sub _access_token_request {
	my ($api_key, $api_secret) = @_;
	my $bearer_token = b64_encode(url_escape($api_key) . ':' . url_escape($api_secret), '');
	my $url = Mojo::URL->new($OAUTH2_ENDPOINT);
	my %headers = (Authorization => "Basic $bearer_token",
		'Content-Type' => 'application/x-www-form-urlencoded;charset=UTF-8');
	my %form = (grant_type => 'client_credentials');
	return ($url, \%headers, form => \%form);
}

sub _api_url {
	my ($endpoint, @query) = @_;
	return Mojo::URL->new($API_BASE_URL)->path($endpoint)->query(@query);
}

sub _api_headers {
	my $token = shift;
	return { Authorization => "Bearer $token" };
}

sub _request_token {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	
	my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
	croak 'Twitter API key and secret are required'
		unless defined $api_key and defined $api_secret;
	my @token_request = _request_token_request($api_key, $api_secret);
	
	if ($cb) {
		$self->ua->post(@token_request, sub {
			my ($ua, $tx) = @_;
			return $self->$cb(_api_error($tx)) if $tx->error;
			my $params = $tx->res->body_params->to_hash;
			return $self->$cb("OAuth callback was not confirmed")
				unless $params->{oauth_callback_confirmed} eq 'true';
			$self->$cb(undef, $self->_store_request_token($params));
		});
	} else {
		my $tx = $self->ua->post(@token_request);
		die _api_error($tx) . "\n" if $tx->error;
		my $params = $tx->res->body_params->to_hash;
		die "OAuth callback was not confirmed\n"
			unless $params->{oauth_callback_confirmed} eq 'true';
		return $self->_store_request_token($params);
	}
}

sub _store_request_token {
	my ($self, $params) = @_;
	my $token = $params->{oauth_token};
	$self->{_request_token_secrets}{$token} = $params->{oauth_token_secret};
	return $token;
}

sub _request_token_request {
	my ($api_key, $api_secret) = @_;
	return _oauth_request(
		api_key => $api_key,
		api_secret => $api_secret,
		method => 'POST',
		url => _oauth_url('request_token'),
		form => {oauth_callback => 'oob'},
	);
}

sub _oauth_url {
	my ($endpoint, @query) = @_;
	return Mojo::URL->new($OAUTH_BASE_URL)->path($endpoint)->query(@query);
}

sub _oauth_request {
	my %params = @_;
	my ($api_key, $api_secret, $oauth_token, $oauth_secret, $method, $url, $form)
		= @params{'api_key','api_secret','oauth_token','oauth_secret','method','url','form'};
	$method //= 'GET';
	$form //= {};
	
	my %oauth_params = (
		oauth_consumer_key => $api_key,
		oauth_nonce => _oauth_nonce(),
		oauth_signature_method => 'HMAC-SHA1',
		oauth_timestamp => time,
		oauth_version => '1.0',
	);
	$oauth_params{oauth_token} = $oauth_token if defined $oauth_token;
	# All oauth parameters should be moved to the header
	$oauth_params{$_} = delete $form->{$_} for grep { m/^oauth_/ } keys %$form;
	
	$oauth_params{oauth_signature} = _oauth_signature($method, $url->clone->fragment('')->query('')->to_string,
		[@{$url->params->pairs}, %{$form // {}}, %oauth_params], $api_secret, $oauth_secret);
	my $auth_str = join ', ', map { $_ . '="' . url_escape($oauth_params{$_}) . '"' } keys %oauth_params;
	
	my %headers = (Authorization => "OAuth $auth_str");
	return %$form ? ($url, \%headers, form => $form) : ($url, \%headers);
}

sub _oauth_nonce {
	my $str = b64_encode join('', map { chr int rand 256 } 1..32), '';
	$str =~ s/[^a-zA-Z0-9]//g;
	return $str;
}

sub _oauth_signature {
	my ($method, $url, $params, $api_secret, $oauth_secret) = @_;
	my @sorted_pairs = sort { $a->[0] cmp $b->[0] } pairs map { url_escape(encode 'UTF-8', $_) } @$params;
	my $params_str = join '&', map { $_->[0] . '=' . $_->[1] } @sorted_pairs;
	my $signature_str = uc($method) . '&' . url_escape($url) . '&' . url_escape($params_str);
	my $signing_key = url_escape($api_secret) . '&' . url_escape($oauth_secret // '');
	return b64_encode hmac_sha1($signature_str, $signing_key), '';
}

sub _tweet_object {
	my ($self, $source) = @_;
	return Mojo::WebService::Twitter::Tweet->new(twitter => $self)->from_source($source);
}

sub _user_object {
	my ($self, $source) = @_;
	return Mojo::WebService::Twitter::User->new(twitter => $self)->from_source($source);
}

sub _api_error { Mojo::WebService::Twitter::Error->new->from_tx(shift) }

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
