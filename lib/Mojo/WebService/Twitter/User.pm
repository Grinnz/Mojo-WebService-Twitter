package Mojo::WebService::Twitter::User;
use Mojo::Base -base;

use Mojo::WebService::Twitter::Util 'parse_twitter_timestamp';
use Scalar::Util 'weaken';

our $VERSION = '0.001';

has [qw(source twitter)];
has [qw(created_at description followers friends id last_tweet
	name protected screen_name statuses url verified)];

sub new {
	my $self = shift->SUPER::new(@_);
	$self->_populate if defined $self->source;
	return $self;
}

sub fetch {
	my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	my $self = shift;
	my %params = (user_id => $self->id, screen_name => $self->screen_name);
	if ($cb) {
		$self->twitter->get_user(%params, sub {
			my ($twitter, $err, $user) = @_;
			return $self->$cb($err) if $err;
			$self->$cb(undef, $user);
		});
	} else {
		return $self->twitter->get_user(%params);
	}
}

sub _populate {
	my $self = shift;
	my $source = $self->source;
	$self->created_at(parse_twitter_timestamp($source->{created_at}));
	$self->description($source->{description});
	$self->followers($source->{followers_count});
	$self->friends($source->{friends_count});
	$self->id($source->{id});
	$self->name($source->{name});
	$self->protected($source->{protected} ? 1 : 0);
	$self->screen_name($source->{screen_name});
	$self->statuses($source->{statuses_count});
	$self->url($source->{url});
	$self->verified($source->{verified} ? 1 : 0);
	if (defined $source->{status}) {
		$self->last_tweet(my $tweet = $self->twitter->_tweet_object($source->{status}));
		weaken($tweet->{user} = $self);
	}
}

1;

=head1 NAME

Mojo::WebService::Twitter::User - A Twitter user

=head1 SYNOPSIS

 use Mojo::WebService::Twitter::User;
 my $user = Mojo::WebService::Twitter::User->new(id => $user_id, twitter => $twitter)->fetch;
 
 my $username = $user->screen_name;
 my $name = $user->name;
 my $created_at = scalar localtime $user->created_at;
 my $description = $user->description;
 say "[$created_at] \@$username ($user): $description";

=head1 DESCRIPTION

L<Mojo::WebService::Twitter::User> is an object representing a
L<Twitter|https://twitter.com> user. See L<https://dev.twitter.com/overview/api/users>
for more information.

=head1 ATTRIBUTES

=head2 source

 my $source = $user->source;

Source data from Twitter API, used to construct the user's attributes.

=head2 twitter

 my $twitter = $user->twitter;
 $user       = $user->twitter(Mojo::WebService::Twitter->new);

L<Mojo::WebService::Twitter> object used to make API requests.

=head2 created_at

 my $ts = $user->created_at;

Unix epoch timestamp representing the creation time of the user.

=head2 description

 my $description = $user->description;

User's profile description.

=head2 followers

 my $count = $user->followers;

Number of followers of the user.

=head2 friends

 my $count = $user->friends;

Number of friends of the user.

=head2 id

 my $user_id = $user->id;

User identifier.

=head2 last_tweet

 my $tweet = $user->last_tweet;

Most recent tweet by the user (if any), as a L<Mojo::WebService::Twitter::Tweet>
object.

=head2 name

 my $name = $user->name;

User's full name.

=head2 protected

 my $bool = $user->protected;

Whether the user's tweets are protected.

=head2 screen_name

 my $screen_name = $user->screen_name;

User's twitter screen name.

=head2 statuses

 my $count = $user->statuses;

Number of tweets the user has sent.

=head2 url

 my $url = $user->url;

User's profile URL.

=head2 verified

 my $bool = $user->verified;

Whether the user is a L<Verified Account|https://twitter.com/help/verified>.

=head1 METHODS

=head2 new

 my $user = Mojo::WebService::Twitter::User->new(source => $source, twitter => $twitter);
 my $user = Mojo::WebService::Twitter::User->new(id => $user_id, twitter => $twitter)->fetch;
 my $user = Mojo::WebService::Twitter::User->new(screen_name => $screen_name, twitter => $twitter)->fetch;

Create a new L<Mojo::WebService::Twitter::User> object and populate attributes
from L</"source"> if available.

=head2 fetch

 $user = $user->fetch;

Fetch user from L</"twitter"> based on L</"id"> or L</"screen_name"> and return
a new L<Mojo::WebService::Twitter::User> object.

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
