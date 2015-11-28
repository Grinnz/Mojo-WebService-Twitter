package Mojo::WebService::Twitter::OAuthRequest;
use Mojo::Base -base;

use Mojo::URL;
use Mojo::WebService::Twitter;

our $VERSION = '0.001';

has [qw(request_token request_secret)];

sub authorize_url { _oauth_url('authorize')->query(oauth_token => shift->request_token) }

sub _oauth_url { Mojo::URL->new($Mojo::WebService::Twitter::OAUTH_BASE_URL)->path(shift) }

1;

=head1 NAME

Mojo::WebService::Twitter::OAuthRequest - OAuth 1.0a auth request for Twitter

=head1 SYNOPSIS

 my $twitter = Mojo::WebService::Twitter->new(api_key => $api_key, api_secret => $api_secret);
 my $oreq = $twitter->request_oauth;
 
 my $url = $oreq->authorize_url;
 my $oauth = $twitter->verify_authorization($oreq, $pin);
 $oauth->authorize_request($tx);
 $twitter->authorization($oauth);

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::OAuthRequest> allows L<Mojo::WebService::Twitter>
to request authorization for making requests on behalf of a specific user using
OAuth 1.0a.

=head1 ATTRIBUTES

L<Mojo::WebService::Twitter::OAuthRequest> implements the following attributes.

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
L<Mojo::WebService::Twitter/"verify_oauth"> along with this object to retrieve
the authorization.

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
