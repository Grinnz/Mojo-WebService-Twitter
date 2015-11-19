use Mojolicious::Lite;
use Mojo::Loader 'data_section';
use List::Util 'first';
use Time::Piece;

my %tweet_data = (
	'657606994744860672' => {
		data_section => 'tweet',
		coordinates => undef,
		created_at => scalar gmtime(1445620699),
		favorites => 382,
		retweets => 289,
		text => q{The @Space_Station crew works  ~9.5 hours a day, with ~4 hours free time during the week... https://t.co/2cdarZPqND https://t.co/HlAnj3eTKk},
		user_id => '1451773004',
	},
	'657324783294676992' => {
		data_section => 'tweet_reply',
		coordinates => undef,
		created_at => scalar gmtime(1445553415),
		favorites => 21,
		retweets => 13,
		text => q{@starlingLX @bnjacobs @StationCDRKelly @Flickr The higher-res is added but doesn't have @StationCDRKelly's edits...https://t.co/wnKeCAdLfg},
		user_id => '1451773004',
	},
	'657627567948587008' => {
		data_section => 'tweet_retweet',
		coordinates => undef,
		created_at => scalar gmtime(1445625604),
		favorites => 0,
		retweets => 35897,
		text => q{RT @StationCDRKelly: Hurricane #Patricia looks menacing from @space_station. Stay safe below, #Mexico. #YearInSpace https://t.co/6LP2xCYcGD},
		user_id => '1451773004',
	},
);

my %user_data = (
	'1451773004' => {
		data_section => 'user',
		created_at => scalar gmtime(1369322728),
		description => q{NASA's page for updates from the International Space Station, the world-class lab orbiting Earth 250 miles above. For the latest research, follow @ISS_Research.},
		followers => 314219,
		friends => 230,
		last_tweet_ts => scalar gmtime(1445625604),
		name => 'Intl. Space Station',
		protected => 0,
		screen_name => 'Space_Station',
		statuses => 3228,
		time_zone => 'Central Time (US & Canada)',
		url => 'http://t.co/9Gk2GZYDsP',
		utc_offset => -18000,
		verified => 1,
	},
);

post '/token' => { format => 'json', text => data_section('main', 'token') };
get '/api/statuses/show.json' => sub {
	my $c = shift;
	my $id = $c->param('id');
	die "Unknown tweet ID $id" unless defined $id and exists $tweet_data{$id};
	my $data_section = $tweet_data{$id}{data_section} // 'tweet';
	$c->render(format => 'json', text => data_section('main', $data_section));
};
get '/api/users/show.json' => sub {
	my $c = shift;
	my $id;
	if ($id = $c->param('user_id')) {
		die "Unknown user ID $id" unless exists $user_data{$id};
	} elsif (my $name = $c->param('screen_name')) {
		$id = first { lc $user_data{$_}{screen_name} eq lc $name } keys %user_data;
		die "Unknown user screen name $name" unless defined $id;
	}
	my $data_section = $user_data{$id}{data_section} // 'user';
	$c->render(format => 'json', text => data_section('main', $data_section));
};

use Test::More;
use Mojo::WebService::Twitter;

my $api_key = $ENV{TWITTER_API_KEY};
my $api_secret = $ENV{TWITTER_API_SECRET};

if (defined $api_key and defined $api_secret) {
	diag 'Running online test for Twitter';
} else {
	diag 'Running offline test for Twitter; set TWITTER_API_KEY/TWITTER_API_SECRET for online test';
	$Mojo::WebService::Twitter::OAUTH2_ENDPOINT = '/token';
	$Mojo::WebService::Twitter::API_BASE_URL = '/api/';
	$api_key = 'foo';
	$api_secret = 'bar';
}

my $twitter = Mojo::WebService::Twitter->new;
$twitter->ua->server->app->log->level('fatal');

ok !eval { $twitter->get_tweet("657618739492474880"); 1 }, 'no API key set';
is $twitter->api_key($api_key)->api_key, $api_key, 'set API key';
is $twitter->api_secret($api_secret)->api_secret, $api_secret, 'set API secret';

foreach my $id (keys %tweet_data) {
	my $data = $tweet_data{$id};
	my $tweet;
	ok(eval { $tweet = $twitter->get_tweet($id); 1 }, "retrieved tweet $id") or diag $@;
	is $tweet->id, $id, 'right tweet ID';
	is_deeply $tweet->coordinates, $data->{coordinates}, 'right coordinates';
	is $tweet->created_at, $data->{created_at}, 'right creation timestamp';
	ok $tweet->favorites >= $data->{favorites}, "at least $data->{favorites} favorites";
	ok $tweet->retweets >= $data->{retweets}, "at least $data->{retweets} retweets";
	is $tweet->text, $data->{text}, 'right text';
	is $tweet->user->id, $data->{user_id}, 'right user';
}

foreach my $id (keys %user_data) {
	my $data = $user_data{$id};
	my $name = $data->{screen_name};
	my $user;
	ok(eval { $user = $twitter->get_user(user_id => $id); 1 }, "retrieved user $id") or diag $@;
	is $user->id, $id, 'right user ID';
	is lc $user->screen_name, lc $name, 'right user screen name';
	my $user2;
	ok(eval { $user2 = $twitter->get_user(screen_name => $name); 1 }, "retrieved user $name") or diag $@;
	is $user2->id, $id, 'right user ID';
	is lc $user2->screen_name, lc $name, 'right user screen name';
	
	is $user->created_at, $data->{created_at}, 'right creation timestamp';
	is $user->description, $data->{description}, 'right description';
	ok $user->followers >= $data->{followers}, "at least $data->{followers} followers";
	ok $user->friends >= $data->{friends}, "at least $data->{friends} friends";
	is $user->name, $data->{name}, 'right name';
	ok !($user->protected xor $data->{protected}), 'right protected status';
	ok $user->statuses >= $data->{statuses}, "at least $data->{statuses} statuses";
	is $user->time_zone, $data->{time_zone}, 'right time zone';
	is $user->url, $data->{url}, 'right url';
	cmp_ok $user->utc_offset, '==', $data->{utc_offset}, 'right UTC offset';
	ok !($user->verified xor $data->{verified}), 'right verified status';
	ok $user->last_tweet->created_at >= $data->{last_tweet_ts}, "last tweet after $data->{last_tweet_ts}";
}

done_testing;

__DATA__

@@ token
{"token_type":"bearer","access_token":"thisisafakeaccesstoken"}

@@ user
{"id":1451773004,"id_str":"1451773004","name":"Intl. Space Station","screen_name":"Space_Station","location":"Low Earth Orbit","profile_location":null,"description":"NASA's page for updates from the International Space Station, the world-class lab orbiting Earth 250 miles above. For the latest research, follow @ISS_Research.","url":"http:\/\/t.co\/9Gk2GZYDsP","entities":{"url":{"urls":[{"url":"http:\/\/t.co\/9Gk2GZYDsP","expanded_url":"http:\/\/www.nasa.gov\/station","display_url":"nasa.gov\/station","indices":[0,22]}]},"description":{"urls":[]}},"protected":false,"followers_count":314219,"friends_count":230,"listed_count":3711,"created_at":"Thu May 23 15:25:28 +0000 2013","favourites_count":1233,"utc_offset":-18000,"time_zone":"Central Time (US & Canada)","geo_enabled":false,"verified":true,"statuses_count":3228,"lang":"en","status":{"created_at":"Fri Oct 23 18:40:04 +0000 2015","id":657627567948587008,"id_str":"657627567948587008","text":"RT @StationCDRKelly: Hurricane #Patricia looks menacing from @space_station. Stay safe below, #Mexico. #YearInSpace https:\/\/t.co\/6LP2xCYcGD","source":"\u003ca href=\"http:\/\/twitter.com\/download\/iphone\" rel=\"nofollow\"\u003eTwitter for iPhone\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":null,"in_reply_to_status_id_str":null,"in_reply_to_user_id":null,"in_reply_to_user_id_str":null,"in_reply_to_screen_name":null,"geo":null,"coordinates":null,"place":null,"contributors":null,"retweeted_status":{"created_at":"Fri Oct 23 18:05:00 +0000 2015","id":657618739492474880,"id_str":"657618739492474880","text":"Hurricane #Patricia looks menacing from @space_station. Stay safe below, #Mexico. #YearInSpace https:\/\/t.co\/6LP2xCYcGD","source":"\u003ca href=\"http:\/\/twitter.com\" rel=\"nofollow\"\u003eTwitter Web Client\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":null,"in_reply_to_status_id_str":null,"in_reply_to_user_id":null,"in_reply_to_user_id_str":null,"in_reply_to_screen_name":null,"geo":null,"coordinates":null,"place":null,"contributors":null,"retweet_count":35624,"favorite_count":22474,"entities":{"hashtags":[{"text":"Patricia","indices":[10,19]},{"text":"Mexico","indices":[73,80]},{"text":"YearInSpace","indices":[82,94]}],"symbols":[],"user_mentions":[{"screen_name":"Space_Station","name":"Intl. Space Station","id":1451773004,"id_str":"1451773004","indices":[40,54]}],"urls":[],"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[95,118],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}}}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"lang":"en"},"retweet_count":35624,"favorite_count":0,"entities":{"hashtags":[{"text":"Patricia","indices":[31,40]},{"text":"Mexico","indices":[94,101]},{"text":"YearInSpace","indices":[103,115]}],"symbols":[],"user_mentions":[{"screen_name":"StationCDRKelly","name":"Scott Kelly","id":65647594,"id_str":"65647594","indices":[3,19]},{"screen_name":"Space_Station","name":"Intl. Space Station","id":1451773004,"id_str":"1451773004","indices":[61,75]}],"urls":[],"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[116,139],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}},"source_status_id":657618739492474880,"source_status_id_str":"657618739492474880","source_user_id":65647594,"source_user_id_str":"65647594"}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"lang":"en"},"contributors_enabled":false,"is_translator":false,"is_translation_enabled":false,"profile_background_color":"C0DEED","profile_background_image_url":"http:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_image_url_https":"https:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_tile":false,"profile_image_url":"http:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_image_url_https":"https:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_banner_url":"https:\/\/pbs.twimg.com\/profile_banners\/1451773004\/1434028060","profile_link_color":"0084B4","profile_sidebar_border_color":"FFFFFF","profile_sidebar_fill_color":"DDEEF6","profile_text_color":"333333","profile_use_background_image":true,"has_extended_profile":false,"default_profile":false,"default_profile_image":false,"following":null,"follow_request_sent":null,"notifications":null}

@@ tweet
{"created_at":"Fri Oct 23 17:18:19 +0000 2015","id":657606994744860672,"id_str":"657606994744860672","text":"The @Space_Station crew works  ~9.5 hours a day, with ~4 hours free time during the week... https:\/\/t.co\/2cdarZPqND https:\/\/t.co\/HlAnj3eTKk","source":"\u003ca href=\"http:\/\/twitter.com\/download\/android\" rel=\"nofollow\"\u003eTwitter for Android\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":null,"in_reply_to_status_id_str":null,"in_reply_to_user_id":null,"in_reply_to_user_id_str":null,"in_reply_to_screen_name":null,"user":{"id":1451773004,"id_str":"1451773004","name":"Intl. Space Station","screen_name":"Space_Station","location":"Low Earth Orbit","description":"NASA's page for updates from the International Space Station, the world-class lab orbiting Earth 250 miles above. For the latest research, follow @ISS_Research.","url":"http:\/\/t.co\/9Gk2GZYDsP","entities":{"url":{"urls":[{"url":"http:\/\/t.co\/9Gk2GZYDsP","expanded_url":"http:\/\/www.nasa.gov\/station","display_url":"nasa.gov\/station","indices":[0,22]}]},"description":{"urls":[]}},"protected":false,"followers_count":314231,"friends_count":230,"listed_count":3711,"created_at":"Thu May 23 15:25:28 +0000 2013","favourites_count":1233,"utc_offset":-18000,"time_zone":"Central Time (US & Canada)","geo_enabled":false,"verified":true,"statuses_count":3228,"lang":"en","contributors_enabled":false,"is_translator":false,"is_translation_enabled":false,"profile_background_color":"C0DEED","profile_background_image_url":"http:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_image_url_https":"https:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_tile":false,"profile_image_url":"http:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_image_url_https":"https:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_banner_url":"https:\/\/pbs.twimg.com\/profile_banners\/1451773004\/1434028060","profile_link_color":"0084B4","profile_sidebar_border_color":"FFFFFF","profile_sidebar_fill_color":"DDEEF6","profile_text_color":"333333","profile_use_background_image":true,"has_extended_profile":false,"default_profile":false,"default_profile_image":false,"following":null,"follow_request_sent":null,"notifications":null},"geo":null,"coordinates":null,"place":null,"contributors":null,"is_quote_status":false,"retweet_count":289,"favorite_count":382,"entities":{"hashtags":[],"symbols":[],"user_mentions":[{"screen_name":"Space_Station","name":"Intl. Space Station","id":1451773004,"id_str":"1451773004","indices":[4,18]}],"urls":[{"url":"https:\/\/t.co\/2cdarZPqND","expanded_url":"http:\/\/www.nasa.gov\/feature\/5-fun-things-to-do-without-gravity","display_url":"nasa.gov\/feature\/5-fun-\u2026","indices":[92,115]}],"media":[{"id":657606857159143425,"id_str":"657606857159143425","indices":[116,139],"media_url":"http:\/\/pbs.twimg.com\/tweet_video_thumb\/CSBJ89LU8AEPKrl.png","media_url_https":"https:\/\/pbs.twimg.com\/tweet_video_thumb\/CSBJ89LU8AEPKrl.png","url":"https:\/\/t.co\/HlAnj3eTKk","display_url":"pic.twitter.com\/HlAnj3eTKk","expanded_url":"http:\/\/twitter.com\/Space_Station\/status\/657606994744860672\/photo\/1","type":"photo","sizes":{"medium":{"w":400,"h":258,"resize":"fit"},"small":{"w":340,"h":219,"resize":"fit"},"large":{"w":400,"h":258,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"}}}]},"extended_entities":{"media":[{"id":657606857159143425,"id_str":"657606857159143425","indices":[116,139],"media_url":"http:\/\/pbs.twimg.com\/tweet_video_thumb\/CSBJ89LU8AEPKrl.png","media_url_https":"https:\/\/pbs.twimg.com\/tweet_video_thumb\/CSBJ89LU8AEPKrl.png","url":"https:\/\/t.co\/HlAnj3eTKk","display_url":"pic.twitter.com\/HlAnj3eTKk","expanded_url":"http:\/\/twitter.com\/Space_Station\/status\/657606994744860672\/photo\/1","type":"animated_gif","sizes":{"medium":{"w":400,"h":258,"resize":"fit"},"small":{"w":340,"h":219,"resize":"fit"},"large":{"w":400,"h":258,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"}},"video_info":{"aspect_ratio":[200,129],"variants":[{"bitrate":0,"content_type":"video\/mp4","url":"https:\/\/pbs.twimg.com\/tweet_video\/CSBJ89LU8AEPKrl.mp4"}]}}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"possibly_sensitive_appealable":false,"lang":"en"}

@@ tweet_reply
{"created_at":"Thu Oct 22 22:36:55 +0000 2015","id":657324783294676992,"id_str":"657324783294676992","text":"@starlingLX @bnjacobs @StationCDRKelly @Flickr The higher-res is added but doesn't have @StationCDRKelly's edits...https:\/\/t.co\/wnKeCAdLfg","source":"\u003ca href=\"http:\/\/twitter.com\" rel=\"nofollow\"\u003eTwitter Web Client\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":657257155855294465,"in_reply_to_status_id_str":"657257155855294465","in_reply_to_user_id":348968125,"in_reply_to_user_id_str":"348968125","in_reply_to_screen_name":"starlingLX","user":{"id":1451773004,"id_str":"1451773004","name":"Intl. Space Station","screen_name":"Space_Station","location":"Low Earth Orbit","description":"NASA's page for updates from the International Space Station, the world-class lab orbiting Earth 250 miles above. For the latest research, follow @ISS_Research.","url":"http:\/\/t.co\/9Gk2GZYDsP","entities":{"url":{"urls":[{"url":"http:\/\/t.co\/9Gk2GZYDsP","expanded_url":"http:\/\/www.nasa.gov\/station","display_url":"nasa.gov\/station","indices":[0,22]}]},"description":{"urls":[]}},"protected":false,"followers_count":314238,"friends_count":230,"listed_count":3711,"created_at":"Thu May 23 15:25:28 +0000 2013","favourites_count":1233,"utc_offset":-18000,"time_zone":"Central Time (US & Canada)","geo_enabled":false,"verified":true,"statuses_count":3228,"lang":"en","contributors_enabled":false,"is_translator":false,"is_translation_enabled":false,"profile_background_color":"C0DEED","profile_background_image_url":"http:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_image_url_https":"https:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_tile":false,"profile_image_url":"http:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_image_url_https":"https:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_banner_url":"https:\/\/pbs.twimg.com\/profile_banners\/1451773004\/1434028060","profile_link_color":"0084B4","profile_sidebar_border_color":"FFFFFF","profile_sidebar_fill_color":"DDEEF6","profile_text_color":"333333","profile_use_background_image":true,"has_extended_profile":false,"default_profile":false,"default_profile_image":false,"following":null,"follow_request_sent":null,"notifications":null},"geo":null,"coordinates":null,"place":null,"contributors":null,"is_quote_status":false,"retweet_count":13,"favorite_count":21,"entities":{"hashtags":[],"symbols":[],"user_mentions":[{"screen_name":"starlingLX","name":"Alex von Eckartsberg","id":348968125,"id_str":"348968125","indices":[0,11]},{"screen_name":"bnjacobs","name":"Bob Jacobs","id":17897744,"id_str":"17897744","indices":[12,21]},{"screen_name":"StationCDRKelly","name":"Scott Kelly","id":65647594,"id_str":"65647594","indices":[22,38]},{"screen_name":"Flickr","name":"Flickr","id":21237045,"id_str":"21237045","indices":[39,46]},{"screen_name":"StationCDRKelly","name":"Scott Kelly","id":65647594,"id_str":"65647594","indices":[88,104]}],"urls":[{"url":"https:\/\/t.co\/wnKeCAdLfg","expanded_url":"https:\/\/www.flickr.com\/photos\/nasa2explore\/21772465134\/in\/dateposted-public\/","display_url":"flickr.com\/photos\/nasa2ex\u2026","indices":[115,138]}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"possibly_sensitive_appealable":false,"lang":"en"}

@@ tweet_retweet
{"created_at":"Fri Oct 23 18:40:04 +0000 2015","id":657627567948587008,"id_str":"657627567948587008","text":"RT @StationCDRKelly: Hurricane #Patricia looks menacing from @space_station. Stay safe below, #Mexico. #YearInSpace https:\/\/t.co\/6LP2xCYcGD","source":"\u003ca href=\"http:\/\/twitter.com\/download\/iphone\" rel=\"nofollow\"\u003eTwitter for iPhone\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":null,"in_reply_to_status_id_str":null,"in_reply_to_user_id":null,"in_reply_to_user_id_str":null,"in_reply_to_screen_name":null,"user":{"id":1451773004,"id_str":"1451773004","name":"Intl. Space Station","screen_name":"Space_Station","location":"Low Earth Orbit","description":"NASA's page for updates from the International Space Station, the world-class lab orbiting Earth 250 miles above. For the latest research, follow @ISS_Research.","url":"http:\/\/t.co\/9Gk2GZYDsP","entities":{"url":{"urls":[{"url":"http:\/\/t.co\/9Gk2GZYDsP","expanded_url":"http:\/\/www.nasa.gov\/station","display_url":"nasa.gov\/station","indices":[0,22]}]},"description":{"urls":[]}},"protected":false,"followers_count":314525,"friends_count":230,"listed_count":3712,"created_at":"Thu May 23 15:25:28 +0000 2013","favourites_count":1233,"utc_offset":-18000,"time_zone":"Central Time (US & Canada)","geo_enabled":false,"verified":true,"statuses_count":3228,"lang":"en","contributors_enabled":false,"is_translator":false,"is_translation_enabled":false,"profile_background_color":"C0DEED","profile_background_image_url":"http:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_image_url_https":"https:\/\/pbs.twimg.com\/profile_background_images\/517439388741931008\/iRbQw1ch.jpeg","profile_background_tile":false,"profile_image_url":"http:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_normal.jpg","profile_image_url_https":"https:\/\/pbs.twimg.com\/profile_images\/647082562125459456\/pmT48eHQ_nor mal.jpg","profile_banner_url":"https:\/\/pbs.twimg.com\/profile_banners\/1451773004\/1434028060","profile_link_color":"0084B4","profile_sidebar_border_color":"FFFFFF","profile_sidebar_fill_color":"DDEEF6","profile_text_color":"333333","profile_use_background_image":true,"has_extended_profile":false,"default_profile":false,"default_profile_image":false,"following":null,"follow_request_sent":null,"notifications":null},"geo":null,"coordinates":null,"place":null,"contributors":null,"retweeted_status":{"created_at":"Fri Oct 23 18:05:00 +0000 2015","id":657618739492474880,"id_str":"657618739492474880","text":"Hurricane #Patricia looks menacing from @space_station. Stay safe below, #Mexico. #YearInSpace https:\/\/t.co\/6LP2xCYcGD","source":"\u003ca href=\"http:\/\/twitter.com\" rel=\"nofollow\"\u003eTwitter Web Client\u003c\/a\u003e","truncated":false,"in_reply_to_status_id":null,"in_reply_to_status_id_str":null,"in_reply_to_user_id":null,"in_reply_to_user_id_str":null,"in_reply_to_screen_name":null,"user":{"id":65647594,"id_str":"65647594","name":"Scott Kelly","screen_name":"StationCDRKelly","location":"International Space Station","description":"","url":null,"entities":{"description":{"urls":[]}},"protected":false,"followers_count":566929,"friends_count":137,"listed_count":5419,"created_at":"Fri Aug 14 14:31:39 +0000 2009","favourites_count":9,"utc_offset":null,"time_zone":null,"geo_enabled":true,"verified":true,"statuses_count":1712,"lang":"en","contributors_enabled":false,"is_translator":false,"is_translation_enabled":false,"profile_background_color":"010505","profile_background_image_url":"http:\/\/pbs.twimg.com\/profile_background_images\/31467382\/Scott_Twitter.jpg","profile_background_image_url_https":"https:\/\/pbs.twimg.com\/profile_background_images\/31467382\/Scott_Twitter.jpg","profile_background_tile":false,"profile_image_url":"http:\/\/pbs.twimg.com\/profile_images\/558447158597136385\/P9TpCaRn_normal.jpeg","profile_image_url_https":"https:\/\/pbs.twimg.com\/profile_images\/558447158597136385\/P9TpCaRn_normal.jpeg","profile_banner_url":"https:\/\/pbs.twimg.com\/profile_banners\/65647594\/1445202282","profile_link_color":"3B94D9","profile_sidebar_border_color":"838582","profile_sidebar_fill_color":"262626","profile_text_color":"727273","profile_use_background_image":true,"has_extended_profile":false,"default_profile":false,"default_profile_image":false,"following":null,"follow_request_sent":null,"notifications":null},"geo":null,"coordinates":null,"place":null,"contributors":null,"is_quote_status":false,"retweet_count":35897,"favorite_count":22703,"entities":{"hashtags":[{"text":"Patricia","indices":[10,19]},{"text":"Mexico","indices":[73,80]},{"text":"YearInSpace","indices":[82,94]}],"symbols":[],"user_mentions":[{"screen_name":"Space_Station","name":"Intl. Space Station","id":1451773004,"id_str":"1451773004","indices":[40,54]}],"urls":[],"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[95,118],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}}}]},"extended_entities":{"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[95,118],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}}}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"possibly_sensitive_appealable":false,"lang":"en"},"is_quote_status":false,"retweet_count":35897,"favorite_count":0,"entities":{"hashtags":[{"text":"Patricia","indices":[31,40]},{"text":"Mexico","indices":[94,101]},{"text":"YearInSpace","indices":[103,115]}],"symbols":[],"user_mentions":[{"screen_name":"StationCDRKelly","name":"Scott Kelly","id":65647594,"id_str":"65647594","indices":[3,19]},{"screen_name":"Space_Station","name":"Intl. Space Station","id":1451773004,"id_str":"1451773004","indices":[61,75]}],"urls":[],"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[116,139],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}},"source_status_id":657618739492474880,"source_status_id_str":"657618739492474880","source_user_id":65647594,"source_user_id_str":"65647594"}]},"extended_entities":{"media":[{"id":657618738447958017,"id_str":"657618738447958017","indices":[116,139],"media_url":"http:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","media_url_https":"https:\/\/pbs.twimg.com\/media\/CSBUwibUwAEg0fF.jpg","url":"https:\/\/t.co\/6LP2xCYcGD","display_url":"pic.twitter.com\/6LP2xCYcGD","expanded_url":"http:\/\/twitter.com\/StationCDRKelly\/status\/657618739492474880\/photo\/1","type":"photo","sizes":{"medium":{"w":600,"h":399,"resize":"fit"},"small":{"w":340,"h":226,"resize":"fit"},"thumb":{"w":150,"h":150,"resize":"crop"},"large":{"w":1024,"h":681,"resize":"fit"}},"source_status_id":657618739492474880,"source_status_id_str":"657618739492474880","source_user_id":65647594,"source_user_id_str":"65647594"}]},"favorited":false,"retweeted":false,"possibly_sensitive":false,"possibly_sensitive_appealable":false,"lang":"en"}
