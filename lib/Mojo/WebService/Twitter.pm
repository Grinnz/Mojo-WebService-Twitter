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
			$self->ua_request(_api_request($token, 'statuses/show.json', id => $id), sub {
				my ($self, $err, $res) = @_;
				return $self->$cb($err) if $err;
				$self->$cb(undef, $self->_tweet_object($res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $res = $self->ua_request(_api_request($token, 'statuses/show.json', id => $id));
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
			$self->ua_request(_api_request($token, 'users/show.json', @query), sub {
				my ($self, $err, $res) = @_;
				return $self->$cb($err) if $err;
				$self->$cb(undef, $self->_user_object($res->json));
			});
		});
	} else {
		my $token = $self->_access_token;
		my $res = $self->ua_request(_api_request($token, 'users/show.json', @query));
		return $self->_user_object($res->json);
	}
}

sub _access_token {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	if ($cb) {
		return $self->$cb(undef, $self->{_access_token}) if exists $self->{_access_token};
		
		my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
		return $self->$cb('Twitter API key and secret are not set')
			unless defined $api_key and defined $api_secret;
		
		$self->ua_request(_access_token_request($api_key, $api_secret), sub {
			my ($self, $err, $res) = @_;
			return $self->$cb($err) if $err;
			$self->$cb(undef, $self->{_access_token} = $res->json->{access_token});
		});
	} else {
		return $self->{_access_token} if exists $self->{_access_token};
		
		my ($api_key, $api_secret) = ($self->api_key, $self->api_secret);
		croak 'Twitter API key and secret are not set'
			unless defined $api_key and defined $api_secret;
		
		my $res = $self->ua_request(_access_token_request($api_key, $api_secret));
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

=head1 DESCRIPTION

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

