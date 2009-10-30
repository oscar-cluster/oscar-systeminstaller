use ExtUtils::MakeMaker;
use lib '/usr/local/lib/systemimager/perl','/usr/lib/systemimager/perl';

# The global version is stored here so that it can be used by 
# the man page string in rewriting POD2MAN_EXE

my $version = "2.4.5";
my $release = "1";
my $releasex = "1";

sub MY::postamble {
    my $string = <<EOF;

POD2MAN5_EXE = \$(POD2MAN) "--section=5"
PKGDEST=

deb :: manifest rpm_prep dist
\tmkdir -p /tmp/scdeb
\tmv \$(NAME)-$version.tar.gz /tmp/scdeb \\
\t\t&& cd /tmp/scdeb && tar -xvzf \$(NAME)-$version.tar.gz
\t\@if [ -n "\$\$UNSIGNED_OSCAR_PKG" ]; then \\
\t\techo "dpkg-buildpackage -rfakeroot -us -uc"; \\
\t\tcd /tmp/scdeb/\$(NAME)-$version && dpkg-buildpackage -rfakeroot -us -uc; \\
\telse \\
\t\techo "dpkg-buildpackage -rfakeroot";\\
\t\tcd /tmp/scdeb/\$(NAME)-$version && dpkg-buildpackage -rfakeroot; \\
\tfi
\t\@if [ -n "\$(PKGDEST)" ]; then \\
\t\tmv /tmp/scdeb/\$(NAME)*.deb \$(PKGDEST); \\
\t\techo "Debian packages are available in \$(PKGDEST)"; \\
\telse \\
\t\techo "Debian packages are available in /tmp/scdeb"; \\
\tfi
\trm -rf /tmp/scdeb/\$(NAME)-$version

rpm_prep ::
\tsed -e 's/\%define version\\b.*/\%define version         $version/' \\
\t-e 's/\%define release\\b.*/\%define release         $release/' \\
\t-e 's/\%define releasex\\b.*/\%define releasex         $releasex/' sin-oscar.spec.in > sin-oscar.spec

rpm :: srpm
\trpmbuild -tb --target noarch \$(NAME)-\$(VERSION).tar.gz
\t\@if [ -n "\$(PKGDEST)" ]; then \\
\t\tmv `rpm --eval '%{_topdir}'`/RPMS/noarch/\$(NAME)-*.noarch.rpm \$(PKGDEST); \\
\tfi

srpm :: rpm_prep manifest dist
\trpmbuild -ts --target noarch --nodeps \$(NAME)-\$(VERSION).tar.gz

ext_install :: conf
\tmkdir -p \$(DESTDIR)\$(PREFIX)/../var/lib/sis
\ttouch  \$(DESTDIR)\$(PREFIX)/../var/lib/sis/image
\ttouch  \$(DESTDIR)\$(PREFIX)/../var/lib/sis/adapter
\ttouch  \$(DESTDIR)\$(PREFIX)/../var/lib/sis/client

\$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/systeminstaller.conf : samples/systeminstaller.conf \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller
\tinstall samples/systeminstaller.conf \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/

\$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/tksis.conf : samples/tksis.conf \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller
\tinstall samples/tksis.conf \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/

\$(DESTDIR)\$(PREFIX)/../etc/systeminstaller :
\tinstall -d \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller

conf: \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/tksis.conf \$(DESTDIR)\$(PREFIX)/../etc/systeminstaller/systeminstaller.conf

img_install ::
\tinstall -d \$(DESTDIR)\$(PREFIX)/share/systeminstaller/images
\tinstall tksis/images/monitor.xpm \$(DESTDIR)\$(PREFIX)/share/systeminstaller/images
\tinstall tksis/images/image.xpm \$(DESTDIR)\$(PREFIX)/share/systeminstaller/images

manifest :

\t if [[ -f MANIFEST ]]; then \\
\t\t mv MANIFEST MANIFEST.bak; \\
\t fi
\t cp MANIFEST.stub MANIFEST

manext_install ::
\tcd doc && \\
\tinstall -d \$(DESTINSTALLMAN1DIR)/../man5 && \\
\t\$(POD2MAN5_EXE) systeminstaller.conf.pod \$(DESTINSTALLMAN1DIR)/../man5/systeminstaller.conf.5 && \\
\t\$(POD2MAN5_EXE) SIS.pod \$(DESTINSTALLMAN1DIR)/../man1/SIS.1 && \\
\tcd ..

install :: all pure_install doc_install ext_install manext_install img_install 

set_ver::
\tperl -pi.bak -e 's/SIVERSION=.*/SIVERSION="$version";/' ./lib/SystemInstaller/Env.pm
\tperl -pi.bak -e 's/SIVERSION=.*/SIVERSION="$version";/' ./blib/lib/SystemInstaller/Env.pm

all :: set_ver

EOF
}
#all :: set_ver pure_all htmlifypods manifypods

WriteMakefile(
              'VERSION' => $version,
              'NAME' => 'systeminstaller-oscar',
              'EXE_FILES' => [qw(
				bin/mksiadapter
				bin/mksidisk
				bin/mksiimage 
				bin/mksimachine
				bin/mksirange
				bin/mkdhcpconf
				tksis/tksis
                bin/scconf_tool
                bin/scconf_kernel 
				)],
              'INSTALLBIN' => "/usr/bin",
              'INSTALLSITELIB' => "/usr/lib/systeminstaller",
              'PREREQ_PM' => {
			      MLDBM => '2',
                              AppConfig => '1.52',
                             },
              'realclean' => {FILES => "*.old *.bak *.spec *.tar.gz Makefile MANIFEST"},
             );
