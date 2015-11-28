package Mojo::WebService::Twitter::OAuth;
use Mojo::Base -base;

use Carp 'croak';
use Digest::SHA 'hmac_sha1';
use List::Util 'pairs';
use Mojo::Util qw(b64_encode encode url_escape);
use Mojo::WebService::Twitter;
use Mojo::WebService::Twitter::User;

our $VERSION = '0.001';

has [qw(access_token access_secret)];
has 'twitter' => sub { Mojo::WebService::Twitter->new };
has 'user' => sub { Mojo::WebService::Twitter::User->new(twitter => shift->twitter) };

sub authorize_request {
	my ($self, $tx) = @_;
	my ($api_key, $api_secret) = ($self->twitter->api_key, $self->twitter->api_secret);
	croak 'Twitter API key and secret are required' unless defined $api_key and defined $api_secret;
	my ($token, $secret) = ($self->access_token, $self->access_secret);
	return _authorize_oauth($tx, $api_key, $api_secret, $token, $secret);
}

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
	
	my $base_url = $request_url->clone->fragment(undef)->query('')->to_string;
	my $signature_str = uc($method) . '&' . url_escape($base_url) . '&' . url_escape($params_str);
	my $signing_key = url_escape($api_secret) . '&' . url_escape($oauth_secret // '');
	return b64_encode(hmac_sha1($signature_str, $signing_key), '');
}

1;

=head1 NAME

Mojo::WebService::Twitter::OAuth - OAuth 1.0a authorization for Twitter

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 $twitter->authorization('oauth', access_token => $token, access_secret => $secret);
 $twitter->authorization->authorize_request($tx);
 
 my $oreq = $twitter->request_oauth;
 my $oauth = $oreq->verify_authorization($pin);
 $twitter->authorization($oauth);
 
=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuth> allows L<Mojo::WebService::Twitter> to
authorize actions on behalf of a specific user using OAuth 1.0a.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuth> implements the following attributes.

=head2 twitter

 my $twitter = $oauth->twitter;
 $oauth      = $oauth->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 access_token

 my $token = $oauth->access_token;
 $oauth    = $oauth->access_token($token);

OAuth access token used to authorize API requests.

=head2 access_secret

 my $secret = $oauth->access_secret;
 $oauth     = $oauth->access_secret($secret);

OAuth access token secret used to authorize API requests.

=head2 user

 my $user = $oauth->user;
 $oauth   = $oauth->user($user);

L<Mojo::WebService::Twitter::User> object representing authorizing user.

=head1 METHODS

L<Mojo::WebService::Twitter::OAuth> inherits all methods from L<Mojo::Base>,
and implements the following new ones.

=head2 authorize_request

 $tx = $oauth->authorize_request($tx);

Authorize a L<Mojo::Transaction> for OAuth 1.0a using L</"access_token"> and
L</"access_secret">.

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
