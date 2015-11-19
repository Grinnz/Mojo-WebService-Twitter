package Mojo::WebService::Twitter::Util;

use strict;
use warnings;
use Exporter 'import';
use Time::Piece ();

our $VERSION = '0.001';

our @EXPORT_OK = qw(parse_twitter_timestamp);

sub parse_twitter_timestamp { Time::Piece->strptime(shift, '%a %b %d %H:%M:%S %z %Y') }

1;

=head1 NAME

Mojo::WebService::Twitter::Util - Utility functions for Twitter client

=head1 SYNOPSIS

 use Mojo::WebService::Twitter::Util 'parse_twitter_timestamp';

 my $epoch = parse_twitter_timestamp('Fri Oct 23 17:18:19 +0100 2015')->epoch;

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::Util> contains utility functions used by
L<Mojo::WebService::Twitter> for interacting with the L<Twitter|https://twitter.com>
API. All functions are exportable on demand.

=head1 FUNCTIONS

=head2 parse_twitter_timestamp

 my $time = parse_twitter_timestamp($ts);

Takes a timestamp string in the format returned by Twitter and returns a
corresponding L<Time::Piece> object in UTC.

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
