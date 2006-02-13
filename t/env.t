use Test;
use Carp;

BEGIN {
	plan tests => 3;
}

# 1 use
eval {
	use SystemInstaller::Env;
	return 1;
};
ok($@,'') or croak("Couldn't use Env.pm");

# 2-x vars defined

ok(defined $config->binpath);
ok(defined $config->rpmrc);
