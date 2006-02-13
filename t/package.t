use Test;
use Carp;
use SystemInstaller::Env;

BEGIN {
	plan tests => 1;
}

# 1 use
eval {
	use SystemInstaller::Package;
	return 1;
};
ok($@,'') or croak("Couldn't use Package.pm");

# Unfortunately, there's not much to test. The new API
# needs real RPMs to query. This may get better in the 
# future, but for now...
