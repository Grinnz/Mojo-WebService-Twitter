package Mojo::WebService::Twitter::Tweet;
use Mojo::Base -base;

use Date::Parse;

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

