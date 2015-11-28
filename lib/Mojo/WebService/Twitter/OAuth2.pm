package Mojo::WebService::Twitter::OAuth2;
use Mojo::Base -base;

use Carp 'croak';

our $VERSION = '0.001';

has 'bearer_token';

sub authorize_request {
	my ($self, $tx) = @_;
	my $token = $self->bearer_token // croak 'OAuth 2 bearer token is required to authorize requests';
	$tx->req->headers->authorization("Bearer $token");
	return $tx;
}

1;

=head1 NAME

Mojo::WebService::Twitter::OAuth2 - OAuth 2 authorization for Twitter

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 my $oauth2 = $twitter->request_oauth2;
 $twitter->authorization($oauth2);
 $oauth2->authorize_request($tx);

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuth2> allows L<Mojo::WebService::Twitter> to
authorize actions on behalf of the application itself using OAuth 2.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuth2> implements the following attributes.

=head2 bearer_token

 my $token = $oauth2->bearer_token;
 $oauth2   = $oauth2->bearer_token($token);

OAuth 2 bearer token used to authorize API requests.

=head1 METHODS

L<Mojo::WebService::Twitter::OAuth2> inherits all methods from L<Mojo::Base>,
and implements the following new ones.

=head2 authorize_request

 $tx = $oauth2->authorize_request($tx);

Authorize a L<Mojo::Transaction> for OAuth 2 using L</"bearer_token">.

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
