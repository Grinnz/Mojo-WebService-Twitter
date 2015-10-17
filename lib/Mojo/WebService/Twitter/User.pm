package Mojo::WebService::Twitter::User;
use Mojo::Base -base;

use Date::Parse;
use Scalar::Util 'weaken';

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
	$self->created_at(str2time($source->{created_at}, 0));
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

Mojo::WebService::Twitter::User - A user

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

