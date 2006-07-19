use ExtUtils::MakeMaker;
use lib '/usr/local/lib/systemimager/perl','/usr/lib/systemimager/perl';

# The global version is stored here so that it can be used by 
# the man page string in rewriting POD2MAN_EXE

my $version = "2.1";
my $release = "1";
my $releasex = "1";

sub MY::postamble {
    my $string = <<EOF;

POD2MAN5_EXE = \$(POD2MAN) "--section=5"

deb_prep ::
\tperl -pi.bak -e 's/^VERSION.*/VERSION = $version/' debian/rules

deb :: deb_prep dist
\tmkdir -p /tmp/scdeb
\tmv systeminstaller-$version.tar.gz /tmp/scdeb && cd /tmp/scdeb && tar -xvzf systeminstaller-$version.tar.gz && cd systeminstaller-$version && dpkg-buildpackage && rm -rf /tmp/scdeb/systeminstaller-$version
\techo "Debian Packages have been built in /tmp/scdeb"

rpm_prep ::
\tperl -pi.bak -e 's/\%define version\\b.*/\%define version         $version/' sin.spec
\tperl -pi.bak -e 's/\%define release\\b.*/\%define release         $release/' sin.spec
\tperl -pi.bak -e 's/\%define releasex\\b.*/\%define releasex         $releasex/' sin.spec

rpm :: srpm
\trpm -tb --target noarch \$(NAME)-\$(VERSION).tar.gz

srpm :: rpm_prep dist
\trpm -ts --target noarch \$(NAME)-\$(VERSION).tar.gz

ext_install :: conf
\tmkdir -p \$(PREFIX)/../var/lib/sis
\ttouch  \$(PREFIX)/../var/lib/sis/image
\ttouch  \$(PREFIX)/../var/lib/sis/adapter
\ttouch  \$(PREFIX)/../var/lib/sis/client

\$(PREFIX)/../etc/systeminstaller/systeminstaller.conf : samples/systeminstaller.conf \$(PREFIX)/../etc/systeminstaller
\tinstall samples/systeminstaller.conf \$(PREFIX)/../etc/systeminstaller/

\$(PREFIX)/../etc/systeminstaller/tksis.conf : samples/tksis.conf \$(PREFIX)/../etc/systeminstaller
\tinstall samples/tksis.conf \$(PREFIX)/../etc/systeminstaller/

\$(PREFIX)/../etc/systeminstaller :
\tinstall -d \$(PREFIX)/../etc/systeminstaller

conf: \$(PREFIX)/../etc/systeminstaller/tksis.conf \$(PREFIX)/../etc/systeminstaller/systeminstaller.conf

img_install ::
\tinstall -d \$(PREFIX)/share/systeminstaller/images
\tinstall tksis/images/monitor.xpm \$(PREFIX)/share/systeminstaller/images
\tinstall tksis/images/image.xpm \$(PREFIX)/share/systeminstaller/images

distinfo_install ::

\t for file in `find distinfo | grep -v CVS`; do \\
\t\t if [[ -d \$\$file ]]; then \\
\t\t\t install -d \$(PREFIX)/share/systeminstaller/\$\$file; \\
\t\t else \\
\t\t\t install \$\$file \$(PREFIX)/share/systeminstaller/\$\$file; \\
\t\t fi; \\
\t done


manifest :

\t if [[ -f MANIFEST ]]; then \\
\t\t mv MANIFEST MANIFEST.bak; \\
\t fi
\t cp MANIFEST.stub MANIFEST

manext_install ::
\tcd doc && \\
\tinstall -d \$(INSTALLMAN1DIR)/../man5 && \\
\t\$(POD2MAN5_EXE) systeminstaller.conf.pod \$(INSTALLMAN1DIR)/../man5/systeminstaller.conf.5 && \\
\t\$(POD2MAN5_EXE) SIS.pod \$(INSTALLMAN1DIR)/../man1/SIS.1 && \\
\tcd ..

install :: all pure_install doc_install ext_install manext_install img_install distinfo_install

set_ver::
\tperl -pi.bak -e 's/SIVERSION=.*/SIVERSION="$version";/' ./lib/SystemInstaller/Env.pm
\tperl -pi.bak -e 's/SIVERSION=.*/SIVERSION="$version";/' ./blib/lib/SystemInstaller/Env.pm

all :: set_ver

EOF
}
#all :: set_ver pure_all htmlifypods manifypods

WriteMakefile(
              'VERSION' => $version,
              'NAME' => 'systeminstaller',
              'EXE_FILES' => [qw(
				bin/mksiadapter
				bin/mksidisk
				bin/mksiimage 
				bin/mksimachine
				bin/mksirange
				bin/mkdhcpconf
                                bin/scconf_tool
                                bin/scconf_kernel
				tksis/tksis
				)],
              'INSTALLBIN' => "/usr/bin",
              'INSTALLSITELIB' => "/usr/lib/systeminstaller",
              'PREREQ_PM' => {
			      MLDBM => '2',
                              AppConfig => '1.52',
                             },
             );
