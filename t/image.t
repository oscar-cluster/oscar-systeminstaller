use Test;
use Carp;

BEGIN {
	plan tests => 10;
}

# 1 use
eval {
	use SystemInstaller::Image;
	return 1;
};
ok($@,'') or croak("Couldn't use Image.pm");

#2-10 dirs exist
$IROOT="/tmp/SITEST.$$";
&SystemInstaller::Image::init_image($IROOT);

ok(-d $IROOT);
ok(-d "$IROOT/usr");
ok(-d "$IROOT/usr/lib");
ok(-d "$IROOT/var");
ok(-d "$IROOT/home");
ok(-d "$IROOT/tmp");
ok(-d "$IROOT/boot");
ok(-d "$IROOT/proc");
ok(-d "$IROOT/root");
