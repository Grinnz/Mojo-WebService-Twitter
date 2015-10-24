package Mojo::WebService::Twitter::Tweet;
use Mojo::Base -base;

use Date::Parse;

our $VERSION = '0.001';

has [qw(source twitter)];
has [qw(created_at favorites id retweets text user)];

sub new {
	my $self = shift->SUPER::new(@_);
	$self->_populate if defined $self->source;
	return $self;
}

sub fetch {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	if ($cb) {
		$self->twitter->get_tweet($self->id, sub {
			my ($twitter, $err, $tweet) = @_;
			return $self->$cb($err) if $err;
			$self->$cb(undef, $tweet);
		});
	} else {
		return $self->twitter->get_tweet($self->id);
	}
}

sub _populate {
	my $self = shift;
	my $source = $self->source;
	$self->created_at(str2time($source->{created_at}, 0));
	$self->favorites($source->{favorite_count});
	$self->id($source->{id_str});
	$self->retweets($source->{retweet_count});
	$self->text($source->{text});
	if (defined $source->{user}) {
		$self->user($self->twitter->_user_object($source->{user}));
	}
}

1;

=head1 NAME

Mojo::WebService::Twitter::Tweet - A tweet

=head1 SYNOPSIS

 use Mojo::WebService::Twitter::Tweet;
 my $tweet = Mojo::WebService::Twitter::Tweet->new(id => $tweet_id, twitter => $twitter)->fetch;
 
 my $username = $tweet->user->screen_name;
 my $created_at = scalar localtime $tweet->created_at;
 my $text = $tweet->text;
 say "[$created_at] \@$username: $text";

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::Tweet> is an object representing a
L<Twitter|https://twitter.com> tweet. See L<https://dev.twitter.com/overview/api/tweets>
for more information.

=head1 ATTRIBUTES

=head2 source

 my $source = $tweet->source;

Source data from Twitter API, used to construct the tweet's attributes.

=head2 twitter

 my $twitter = $tweet->twitter;
 $tweet      = $tweet->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 created_at

 my $ts = $tweet->created_at;

Unix epoch timestamp representing the creation time of the tweet.

=head2 favorites

 my $count = $tweet->favorites;

Number of times the tweet has been favorited.

=head2 id

 my $tweet_id = $tweet->id;

Tweet identifier. Note that tweet IDs are usually too large to be represented
as a number, so should always be treated as a string.

=head2 retweets

 my $count = $tweet->retweets;

Number of times the tweet has been retweeted.

=head2 text

 my $text = $tweet->text;

Text contents of tweet.

=head2 user

 my $user = $tweet->user;

User who sent the tweet, as a L<Mojo::WebService::Twitter::User> object.

=head1 METHODS

=head2 new

 my $tweet = Mojo::WebService::Twitter::Tweet->new(source => $source, twitter => $twitter);
 my $tweet = Mojo::WebService::Twitter::Tweet->new(id => $tweet_id, twitter => $twitter)->fetch;

Create a new L<Mojo::WebService::Twitter::Tweet> object and populate attributes
from L</"source"> if available.

=head2 fetch

 $tweet = $tweet->fetch;

Fetch tweet from L</"twitter"> based on L</"id"> and return a new
L<Mojo::WebService::Twitter::Tweet> object.

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
