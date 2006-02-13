use Test;
use Carp;
use SystemInstaller::Env;

BEGIN {
	plan tests => 1;
}

# 1 test use
eval {
	use SystemInstaller::Package::PackManSmart;
	return 1;
};
ok($@,'') or croak("Couldn't use PackManSmart.pm");
