package Mojo::WebService::Twitter;
use Mojo::Base 'Mojo::WebService';

use Carp 'croak';
use Mojo::URL;
use Mojo::Util qw(b64_encode url_escape);
use Mojo::WebService::Twitter::Tweet;
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

use constant TWITTER_OAUTH_ENDPOINT => 'https://api.twitter.com/oauth2/token';
use constant TWITTER_API_BASE => 'https://api.twitter.com/1.1/';

has ['api_key','api_secret'];

sub get_tweet {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, $id) = @_;
	croak 'Tweet id is required for get_tweet' unless defined $id;
	if ($cb) {
		$self->_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			$self->request(_api_request($token, 'statuses/show.json', id => $id), sub {
				my ($self, $err, $res) = @_;
				return $self->$cb($err) if $err;
				$self->$cb(undef, $self->_tweet_object($res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $res = $self->request(_api_request($token, 'statuses/show.json', id => $id));
		return $self->_tweet_object($res->json);
	}
}

sub get_user {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my ($self, %params) = @_;
	my @query;
	push @query, user_id => $params{user_id} if defined $params{user_id};
	push @query, screen_name => $params{screen_name} if defined $params{screen_name};
	croak 'user_id or screen_name is required for get_user' unless @query;
	if ($cb) {
		$self->_access_token(sub {
			my ($self, $err, $token) = @_;
			return $self->$cb($err) if $err;
			$self->request(_api_request($token, 'users/show.json', @query), sub {
				my ($self, $err, $res) = @_;
				return $self->$cb($err) if $err;
				$self->$cb(undef, $self->_user_object($res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $res = $self->request(_api_request($token, 'users/show.json', @query));
		return $self->_user_object($res->json);
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
		$self->request(@token_request, sub {
			my ($self, $err, $res) = @_;
			return $self->$cb($err) if $err;
			$self->$cb(undef, $self->{_access_token} = $res->json->{access_token});
		});
	} else {
		my $res = $self->request(@token_request);
		return $self->{_access_token} = $res->json->{access_token};
	}
}

sub _access_token_request {
	my ($api_key, $api_secret) = @_;
	my $bearer_token = b64_encode(url_escape($api_key) . ':' . url_escape($api_secret), '');
	my $url = Mojo::URL->new(TWITTER_OAUTH_ENDPOINT);
	my %headers = (Authorization => "Basic $bearer_token",
		'Content-Type' => 'application/x-www-form-urlencoded;charset=UTF-8');
	my %form = (grant_type => 'client_credentials');
	return (post => $url, \%headers, form => \%form);
}

sub _api_request {
	my ($token, $endpoint, @query) = @_;
	my $url = Mojo::URL->new(TWITTER_API_BASE)->path($endpoint)->query(@query);
	my %headers = (Authorization => "Bearer $token");
	return (get => $url, \%headers);
}

sub _tweet_object {
	my ($self, $source) = @_;
	my $tweet = Mojo::WebService::Twitter::Tweet->new(twitter => $self, source => $source);
	return $tweet;
}

sub _user_object {
	my ($self, $source) = @_;
	my $user = Mojo::WebService::Twitter::User->new(twitter => $self, source => $source);
	return $user;
}

1;

=head1 NAME

Mojo::WebService::Twitter - Simple Twitter API client

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 
 # Blocking
 my $user = $twitter->get_user(screen_name => $name);
 
 # Non-blocking
 $twitter->get_tweet($tweet_id, sub {
   my ($twitter, $err, $tweet) = @_;
 });

=head1 DESCRIPTION

L<Mojo::WebService::Twitter> is a L<Mojo::UserAgent> based
L<Twitter|https://twitter.com> API client that can perform requests
synchronously or asynchronously. An API key and secret for a
L<Twitter Application|https://apps.twitter.com> are required.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter> inherits all attributes from L<Mojo::WebService>
and implements the following new ones.

=head2 api_key

 my $api_key = $twitter->api_key;
 $twitter    = $twitter->api_key($api_key);

API key for your L<Twitter Application|https://apps.twitter.com>.

=head2 api_secret

 my $api_secret = $twitter->api_secret;
 $twitter       = $twitter->api_secret($api_secret);

API secret for your L<Twitter Application|https://apps.twitter.com>.

=head1 METHODS

L<Mojo::WebService::Twitter> inherits all methods from L<Mojo::WebService> and
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

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<Mojo::WebService>
