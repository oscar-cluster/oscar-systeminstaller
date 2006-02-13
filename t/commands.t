use Test;
use Carp;

BEGIN {
	plan tests => 4;
}
$PERLC = "perl -cw -Iblib/lib";

# Check commands syntax 
ok(system("$PERLC blib/script/mksidisk > /dev/null 2>&1"),0);
ok(system("$PERLC blib/script/mksiimage > /dev/null 2>&1"),0);
ok(system("$PERLC blib/script/mksimachine > /dev/null 2>&1"),0);
ok(system("$PERLC blib/script/mksiadapter > /dev/null 2>&1"),0);

