use Test;
use Carp;

BEGIN {
	plan tests => 1
}

eval {
        use SystemInstaller::Partition;
        return 1;
};
ok($@,'') or croak("Couldn't use Partition.pm");

