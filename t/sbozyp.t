#!/usr/bin/perl

use strict;
use warnings;
use v5.34.0;

use Test2::V0 -no_srand => 1;
use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

use Capture::Tiny qw(capture);
use File::Temp;
use File::stat;
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Copy qw(mv);
use Getopt::Long qw(:config no_ignore_case bundling);
use Cwd qw(getcwd);
use FindBin qw($Bin);
require "$Bin/../bin/sbozyp";

$SIG{INT} = sub { die "sbozyp.t: got a SIGINT ... going down!\n" };

            ####################################################
            #                      HELPERS                     #
            ####################################################

# url_exists_or_bail() is used for future proofing this test script. We downloads files from the internet that could disappear at any time. All urls should be checked for existence before executing tests that will download them. This prevents us from getting failures that appear to be with a problem with sbozyp, but are actually caused by the url we are testing against no longer existing.
sub url_exists_or_bail {
    my ($url) = @_;
    unless (0 == system('wget', '--spider', $url)) {
        bail_out("url '$url' no longer exists. This test script likely needs to be updated. You need to find software in the SBo 14.1 repo whos DOWNLOAD url(s) still exist");
    }
}

            ####################################################
            #                       TESTS                      #
            ####################################################

my $TEST_DIR = File::Temp->newdir(DIR => '/tmp', TEMPLATE => 'sbozyp.tXXXXXX', CLEANUP => 1);

subtest 'sbozyp_die()' => sub {
    like(dies { Sbozyp::sbozyp_die('dead') },
         qr/^sbozyp: error: dead$/,
         'dies with an sbozyp error prefix'
    );

    like(dies { Sbozyp::sbozyp_die("dead\n") },
         qr/^sbozyp: error: dead\n$/,
         'does not chomp death message'
    );
};

subtest 'sbozyp_system()' => sub {
    ok(lives { Sbozyp::sbozyp_system('true') }, 'lives if system command succeeds');

    my ($stdout) = capture { Sbozyp::sbozyp_system('echo foo') };
    is($stdout, "foo\n", 'produces output to stdout');

    my (undef, $stderr) = capture { Sbozyp::sbozyp_system('>&2 echo foo') };
    is($stderr, "foo\n", 'produces output to stderr');

    ($stdout) = capture { Sbozyp::sbozyp_system('echo', 'foo') };
    is($stdout, "foo\n", 'accepts list');

    ok(dies { Sbozyp::sbozyp_system('false') }, 'dies if system command fails');

    like(dies { Sbozyp::sbozyp_system('false') },
         qr/^sbozyp: error: system command 'false' exited with status 1$/,
         'dies with error message containing the exit status when system command fails'
    );
};

subtest 'sbozyp_qx()' => sub {
    ok(lives { Sbozyp::sbozyp_qx('true') }, 'lives if system command succeeds');

    is(Sbozyp::sbozyp_qx('echo foo'), 'foo', 'returns stdout with chomped newline when called in scalar context');

    is([Sbozyp::sbozyp_qx('echo -e "foo\nbar"')],
       ['foo', 'bar'],
       'returns list of chomped lines when called in list context'
    );

    ok(dies { Sbozyp::sbozyp_qx('false') },
       'dies if system command fails'
    );

    like(dies { Sbozyp::sbozyp_qx('false') },
         qr/^sbozyp: error: system command 'false' exited with status 1$/,
         'dies with error message containing the exit status when system command fails'
     );
};

subtest 'sbozyp_open()' => sub {
    ok(lives { Sbozyp::sbozyp_open('>', "$TEST_DIR/foo") }, 'lives if open() succeeds');

    my $fh = Sbozyp::sbozyp_open('>', "$TEST_DIR/foo");
    ok(lives { close $fh }, 'returns filehandle');

    like(dies { Sbozyp::sbozyp_open('<', "$TEST_DIR/bar") },
         qr/^sbozyp: error: could not open file '\Q$TEST_DIR\E\/bar': No such file or directory$/,
         'dies with useful error message if open() fails'
     );
};

subtest 'sbozyp_unlink()' => sub {
    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;
    Sbozyp::sbozyp_unlink("$TEST_DIR/foo");
    ok(! -f "$TEST_DIR/foo", 'successfully unlinks file');

    like(dies { Sbozyp::sbozyp_unlink("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not unlink file '\Q$TEST_DIR\E\/foo': No such file or directory$/,
         'dies with useful error message if unlink() fails'
    );
};

subtest 'sbozyp_copy()' => sub {
    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;

    my $umask = umask();
    my $perm = $umask == 0666 ? 0555 : 0666;

    chmod $perm, "$TEST_DIR/foo";
    Sbozyp::sbozyp_copy("$TEST_DIR/foo", "$TEST_DIR/bar");
    ok(-f "$TEST_DIR/foo" && -f "$TEST_DIR/bar", 'successfully copied file');
    is(stat("$TEST_DIR/bar")->mode & 0777, $perm, 'copies permission of source file to target file');
    is(umask(), $umask, 'does not modify umask');
    unlink "$TEST_DIR/foo" or die;
    unlink "$TEST_DIR/bar" or die;

    make_path("$TEST_DIR/baz/quux") or die;
    open $fh, '>', "$TEST_DIR/baz/foo" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/baz/quux/bar" or die;
    close $fh or die;
    mkdir "$TEST_DIR/dest" or die;
    Sbozyp::sbozyp_copy("$TEST_DIR/baz", "$TEST_DIR/dest");
    is([do{ my @files; File::Find::find(sub { push @files, $File::Find::name}, "$TEST_DIR/dest"); @files }],
       ["$TEST_DIR/dest", "$TEST_DIR/dest/foo", "$TEST_DIR/dest/quux",  "$TEST_DIR/dest/quux/bar"],
       'clones only contents of directory recursively'
    );

    remove_tree("$TEST_DIR/baz") or die;
    remove_tree("$TEST_DIR/dest") or die;

    like(dies { Sbozyp::sbozyp_copy("$TEST_DIR/foo", "$TEST_DIR/bar") },
         qr/^sbozyp: error: system command 'cp -a \Q$TEST_DIR\E\/foo \Q$TEST_DIR\E\/bar' exited with status 1$/,
         q(dies with error message about system command failure if 'cp' command fails)
    );
};

subtest 'sbozyp_move()' => sub {
    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;
    mkdir "$TEST_DIR/bar" or die;

    my $umask = umask();
    my $perm = $umask == 0666 ? 0555 : 0666;
    chmod $perm, "$TEST_DIR/foo";

    Sbozyp::sbozyp_move("$TEST_DIR/foo", "$TEST_DIR/bar");
    ok(! -f "$TEST_DIR/foo" && -f "$TEST_DIR/bar/foo", 'successfully moved file');
    is(stat("$TEST_DIR/bar/foo")->mode & 0777, $perm, 'saves permissions');
    is(umask(), $umask, 'did not modify umask');

    remove_tree("$TEST_DIR/bar") or die;

    like(dies { Sbozyp::sbozyp_move("$TEST_DIR/foo", "$TEST_DIR/bar") },
         qr/^sbozyp: error: could not move '\Q$TEST_DIR\E\/foo' to '\Q$TEST_DIR\E\/bar': No such file or directory$/,
        'dies with useful error message if mv() fails'
    );
};

subtest 'sbozyp_readdir()' => sub {
    is([Sbozyp::sbozyp_readdir($TEST_DIR)], [], 'throws away . and ..');
    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/bar" or die;
    close $fh or die;
    is([Sbozyp::sbozyp_readdir($TEST_DIR)], ["$TEST_DIR/bar", "$TEST_DIR/foo"], 'returns full paths');
    unlink "$TEST_DIR/foo" or die;
    unlink "$TEST_DIR/bar" or die;

    open $fh, '>', "$TEST_DIR/.foo" or die;
    close $fh or die;
    is([Sbozyp::sbozyp_readdir($TEST_DIR)], ["$TEST_DIR/.foo"], 'keeps dotfiles');
    unlink "$TEST_DIR/.foo" or die;

    like(dies { Sbozyp::sbozyp_readdir("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not opendir '\Q$TEST_DIR\E\/foo': No such file or directory$/,
         'dies with useful error message if cannot opendir()'
    );
};

subtest 'sbozyp_chdir()' => sub {
    my $orig_dir = getcwd(); # save this so we can switch back

    Sbozyp::sbozyp_chdir($TEST_DIR);
    is(getcwd(), "$TEST_DIR", 'successfully changes working directory');

    chdir $orig_dir or die;

    like(dies { Sbozyp::sbozyp_chdir("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not chdir to '\Q$TEST_DIR\E\/foo': No such file or directory$/,
         'dies with useful error message if cannot chdir()'
     );
};

subtest 'sbozyp_mkdir()' => sub {
    my $dir = Sbozyp::sbozyp_mkdir("$TEST_DIR/foo/bar/baz");
    ok(-d "$TEST_DIR/foo/bar/baz", 'creates entire path');
    is($dir, "$TEST_DIR/foo/bar/baz", 'returns created path');

    remove_tree("$TEST_DIR/foo") or die;

    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;

    like(dies { Sbozyp::sbozyp_mkdir("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not mkdir '\Q$TEST_DIR\E\/foo': File exists$/,
         'dies with useful error message if cannot make_path()'
    );

    unlink "$TEST_DIR/foo" or die;
};

subtest 'sbozyp_mkdir_empty()' => sub {
    my $dir = Sbozyp::sbozyp_mkdir_empty("$TEST_DIR/foo/bar");
    ok(-d "$TEST_DIR/foo/bar", 'creates entire path');
    is($dir, "$TEST_DIR/foo/bar", 'returns created path');

    Sbozyp::sbozyp_mkdir_empty("$TEST_DIR/foo");
    ok(! -d "$TEST_DIR/foo/bar", 'removes directory contents');
    ok(-d "$TEST_DIR/foo", 'leaves input dir');

    remove_tree("$TEST_DIR/foo") or die;

    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;

    like(dies { Sbozyp::sbozyp_mkdir_empty("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not mkdir '\Q$TEST_DIR\E\/foo': File exists$/,
         'dies with useful error message if cannot make_path()'
    );

    unlink "$TEST_DIR/foo" or die;
};

subtest 'i_am_root_or_die()' => sub {
    if ($> == 0) {
        ok(lives { Sbozyp::i_am_root_or_die() }, 'lives if $> == 0');
    } else {
        like(dies { Sbozyp::i_am_root_or_die() }, qr/^sbozyp: error: must be root$/, 'dies if $> != 0');
    }
};

subtest 'parse_config_file()' => sub {
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'/tmp/sbozyp',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo',REPO_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_GIT_BRANCH=>'15.0'},
       '%CONFIG has correct default values'
    );

    my $test_config = "$TEST_DIR/test_sbozyp.conf";

    open my $fh, '>', $test_config or die;
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'/tmp/sbozyp',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo',REPO_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_GIT_BRANCH=>'15.0'},
       'parsing empty config does not change %CONFIG'
    );

    open $fh, '>', $test_config or die;
    print $fh <<"END";
TMPDIR=foo
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'foo',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo',REPO_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_GIT_BRANCH=>'15.0'},
       'only modifies %CONFIG values specified in the config file'
    );

    open $fh, '>', $test_config or die;
    print $fh <<"END";
# CLEANUP=note_the_comment

TMPDIR = bar # eol comment

CLEANUP   =   bar # eol comment
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'bar',CLEANUP=>'bar',REPO_ROOT=>'/var/lib/sbozyp/SBo',REPO_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_GIT_BRANCH=>'15.0'},
       'ignores comments, eol comments, whitespace, and blank lines'
    );

    open $fh, '>', $test_config or die;
    print $fh <<'END';
TMPDIR=foo
CLEANUP=foo
REPO_ROOT=foo
REPO_GIT_URL=foo
REPO_GIT_BRANCH=foo
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'foo',CLEANUP=>'foo',REPO_ROOT=>'foo',REPO_GIT_URL=>'foo',REPO_GIT_BRANCH=>'foo'},
       'successfully parses config file and updates %CONFIG'
    );

    open $fh, '>', $test_config or die;
    print $fh <<'END';
 =foo # no key
END
    close $fh or die;
    like(dies { Sbozyp::parse_config_file($test_config) },
         qr/^sbozyp: error: could not parse line 1 ' =foo # no key': '\Q$test_config\E'$/,
         'dies with useful error message if there is an empty key'
    );

    open $fh, '>', $test_config or die;
    print $fh <<'END';
TMPDIR= # no value
END
    close $fh or die;
    like(dies { Sbozyp::parse_config_file($test_config) },
         qr/^sbozyp: error: could not parse line 1 'TMPDIR= # no value': '\Q$test_config\E'$/,
         'dies with useful error message if there is an empty value'
    );

    open $fh, '>', $test_config or die;
    print $fh <<'END';
foo=bar
END
    close $fh or die;
    like(dies { Sbozyp::parse_config_file($test_config) },
         qr/^sbozyp: error: invalid setting on line 1 'foo': '\Q$test_config\E'$/,
         'dies with useful error message if config file contains invalid setting'
    );

    # Set %CONFIG to the value we want for the rest of our testing
    open $fh, '>', $test_config or die;
    print $fh <<"END";
TMPDIR=$TEST_DIR
CLEANUP=1
REPO_ROOT=$TEST_DIR/var/lib/sbozyp/SBo
REPO_GIT_URL=git://git.slackbuilds.org/slackbuilds.git
# SBo Version 14.1 is very unlikely to be updated, which means our tests should
# not start randomly failing due to updates to the packages we test against.
REPO_GIT_BRANCH=14.1
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>"$TEST_DIR", CLEANUP=>1,REPO_ROOT=>"$TEST_DIR/var/lib/sbozyp/SBo",REPO_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_GIT_BRANCH=>'14.1'},
       '%CONFIG is properly set for use by the test of this test script'
    );
};

subtest 'sync_repo()' => sub {
    Sbozyp::sync_repo();
    ok(-d "$TEST_DIR/var/lib/sbozyp/SBo/.git", 'clones SBo repo to $CONFIG{REPO_ROOT} if it has not yet been cloned');
    ok(`git -C '$TEST_DIR/var/lib/sbozyp/SBo' branch --show-current` =~ /^14\.1$/, 'clones branch specified by $CONFIG{REPO_GIT_BRANCH}');

    system("git -C '$TEST_DIR/var/lib/sbozyp/SBo' checkout -b 14.2");
    Sbozyp::sync_repo();
    ok(`git -C '$TEST_DIR/var/lib/sbozyp/SBo' branch --show-current` =~ /^14\.1$/, 're-clones if repo branch is not set to $CONFIG{REPO_GIT_BRANCH}');

    # this is a fake test but there is no good way (that I can think of) to actually know if we are performing a git pull.
    Sbozyp::sync_repo(); pass('pulls repo if it is already cloned');
};

subtest 'all_categories()' => sub {
    is([Sbozyp::all_categories()],
       ['academic','accessibility','audio','business','desktop','development','games','gis','graphics','ham','haskell','libraries','misc','multimedia','network','office','perl','python','ruby','system'],
       'returns correct package categories (sorted)'
    );
};

subtest 'all_pkgnames()' => sub {
    my @all_pkgnames = Sbozyp::all_pkgnames();
    ok(scalar(grep { $_ eq 'office/mu' } @all_pkgnames), 'returns list of pkgnames');
    ok(!scalar(grep /\.git/, @all_pkgnames), 'ignores .git');
    is(scalar(@all_pkgnames), 5743, 'returns complete list of packages. If this test fails then the SBo 14.1 repo has been modified');
};

subtest 'find_pkgname()' => sub {
    is(Sbozyp::find_pkgname('mu'), 'office/mu', 'finds pkgname');
    is(Sbozyp::find_pkgname('office/mu'), 'office/mu', 'accepts full pkgname');
    ok(!defined Sbozyp::find_pkgname('NOTAPACKAGE'), 'returns undef if given non-existent prgnam');
    ok(!defined Sbozyp::find_pkgname('FOO/NOTAPACKAGE'), 'returns undef if given non-existent pkgname');
    ok(!defined Sbozyp::find_pkgname('perl/NOTAPACKAGE'), 'rejects pkgname with valid category');
    ok(!defined Sbozyp::find_pkgname('perl/mu'), 'rejects non-existent pkgname with valid category and valid prgnam');
    ok(!defined Sbozyp::find_pkgname('MU'), 'case sensitive');
    ok(!defined Sbozyp::find_pkgname(''), 'rejects empty string');
    ok(!defined Sbozyp::find_pkgname(' '), 'rejects blank string');
    ok(!defined Sbozyp::find_pkgname(), 'rejects undef');
};

subtest 'parse_info_file()' => sub {
    my $info_file = "$Sbozyp::CONFIG{REPO_ROOT}/office/mu/mu.info";
    is({Sbozyp::parse_info_file($info_file)},
       {PRGNAM=>'mu',VERSION=>'0.9.15',HOMEPAGE=>'http://www.djcbsoftware.nl/code/mu/',DOWNLOAD=>'https://github.com/djcb/mu/archive/0.9.15.tar.gz',MD5SUM=>'afbd704c8eb0bf2218a44bd4475cc457',DOWNLOAD_x86_64=>'',MD5SUM_x86_64=>'',REQUIRES=>'xapian-core',MAINTAINER=>'Jostein Berntsen',EMAIL=>'jbernts@broadpark.no'},
       'parses info file into correct hash'
    );

    $info_file = "$Sbozyp::CONFIG{REPO_ROOT}/system/virtualbox/virtualbox.info";
    is({Sbozyp::parse_info_file($info_file)},
       {PRGNAM=>'virtualbox',VERSION=>'4.3.24',HOMEPAGE=>'http://www.virtualbox.org',DOWNLOAD=>'http://download.virtualbox.org/virtualbox/4.3.24/VirtualBox-4.3.24.tar.bz2 http://download.virtualbox.org/virtualbox/4.3.24/VBoxGuestAdditions_4.3.24.iso http://download.virtualbox.org/virtualbox/4.3.24/UserManual.pdf http://download.virtualbox.org/virtualbox/4.3.24/SDKRef.pdf',MD5SUM=>'c9711ee4a040de131c638168d321f3ff a1a4ccd53257c881214aa889f28de9b6 c087b4a00b8d475fdfdc50fab47c1231 6ca97ffd038cb760bff403b615329009',DOWNLOAD_x86_64=>'UNTESTED','MD5SUM_x86_64'=>'',REQUIRES=>'acpica virtualbox-kernel',MAINTAINER=>'Heinz Wiesinger',EMAIL=>'pprkut@liwjatan.at'},
       'squishes newline-escapes into single spaces'
    );

    like(dies { Sbozyp::parse_info_file("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not open file '\Q$TEST_DIR\E\/foo': No such file or directory$/,
         'dies with useful error if given non-existent info file'

    );
};

subtest 'pkg()' => sub {
    url_exists_or_bail('http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz');

    is({Sbozyp::pkg('system/password-store')},
       {PRGNAM=>'password-store',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/README",PKGNAME=>'system/password-store',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store",VERSION=>'1.4.2',HOMEPAGE=>'http://zx2c4.com/projects/password-store/',DOWNLOAD=>['http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz'],MD5SUM=>['c6382dbf5be4036021bf1ce61254b04b'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['xclip','pwgen'],MAINTAINER=>'Michael Ren',EMAIL=>'micron33@gmail.com'},
       'creates correct pkg hash'
    );

    is({Sbozyp::pkg('password-store')},
       {PRGNAM=>'password-store',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/README",PKGNAME=>'system/password-store',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store",VERSION=>'1.4.2',HOMEPAGE=>'http://zx2c4.com/projects/password-store/',DOWNLOAD=>['http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz'],MD5SUM=>['c6382dbf5be4036021bf1ce61254b04b'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['xclip','pwgen'],MAINTAINER=>'Michael Ren',EMAIL=>'micron33@gmail.com'},
       'accepts just a prgnam'
    );

    is(ref(Sbozyp::pkg('system/password-store')), 'HASH', 'returns hashref in scalar context');

    like(dies { Sbozyp::pkg('FOO') },
         qr/^sbozyp: error: could not find a package named 'FOO'$/,
         'dies with useful error message if passed invalid prgnam'
    );

    open my $fh_r, '<', "$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info" or die;
    open my $fh_w, '>', "$TEST_DIR/password-store.info.tmp" or die;
    while (<$fh_r>) { if (/^PRGNAM/) { print $fh_w qq(PRGNAM="FOO"\n) } else { print $fh_w $_ } }
    close $fh_r or die;
    close $fh_w or die;
    rename "$TEST_DIR/password-store.info.tmp", "$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info" or die;

    is({Sbozyp::pkg('system/password-store')},
       {PRGNAM=>'password-store',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/README",PKGNAME=>'system/password-store',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store",VERSION=>'1.4.2',HOMEPAGE=>'http://zx2c4.com/projects/password-store/',DOWNLOAD=>['http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz'],MD5SUM=>['c6382dbf5be4036021bf1ce61254b04b'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['xclip','pwgen'],MAINTAINER=>'Michael Ren',EMAIL=>'micron33@gmail.com'},
       'caches pkgs by default'
    );

    is({Sbozyp::pkg('system/password-store', 1)},
       {PRGNAM=>'FOO',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/README",PKGNAME=>'system/password-store',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store",VERSION=>'1.4.2',HOMEPAGE=>'http://zx2c4.com/projects/password-store/',DOWNLOAD=>['http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz'],MD5SUM=>['c6382dbf5be4036021bf1ce61254b04b'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['xclip','pwgen'],MAINTAINER=>'Michael Ren',EMAIL=>'micron33@gmail.com'},
       'ignores cache if passed true value as second argument'
    );

    is({Sbozyp::pkg('system/password-store')},
       {PRGNAM=>'FOO',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/password-store.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store/README",PKGNAME=>'system/password-store',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/system/password-store",VERSION=>'1.4.2',HOMEPAGE=>'http://zx2c4.com/projects/password-store/',DOWNLOAD=>['http://git.zx2c4.com/password-store/snapshot/password-store-1.4.2.tar.xz'],MD5SUM=>['c6382dbf5be4036021bf1ce61254b04b'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['xclip','pwgen'],MAINTAINER=>'Michael Ren',EMAIL=>'micron33@gmail.com'},
       'overwrites existing cached package when ignoring cache'
    );
};

subtest 'pkg_queue()' => sub {
    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('office/ccal')))],
       [scalar(Sbozyp::pkg('office/ccal'))],
       'returns single elem list containing input package when it has no deps'
    );

    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('office/mu')))],
       [scalar(Sbozyp::pkg('xapian-core')), scalar(Sbozyp::pkg('office/mu'))],
       'returns two elem list in correct order for pkg with single dependency'
    );

    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('perl/perl-Net-SMTP-SSL')))],
       [scalar(Sbozyp::pkg('perl/perl-Net-LibIDN')), scalar(Sbozyp::pkg('perl/Net-SSLeay')), scalar(Sbozyp::pkg('perl/perl-IO-Socket-SSL')), scalar(Sbozyp::pkg('perl/perl-Net-SMTP-SSL'))],
       'resolves recursive dependencies'
    );

    my ($stdout) = capture { Sbozyp::pkg_queue(scalar(Sbozyp::pkg('system/openrc'))) };
    like($stdout,
         qr/^sbozyp: pkg 'system\/openrc' has optional dependencies specified in its README file$/,
         q(outputs message about pkg having optional deps specified in its README file if '%README%' is in its 'REQUIRES')
     );
};

subtest 'parse_slackware_pkgname()' => sub {
    is([Sbozyp::parse_slackware_pkgname('acpica-20220331-x86_64-1_SBo')],
       ['development/acpica', '20220331'],
       'parses non-hyphened pkgname'
    );

    is([Sbozyp::parse_slackware_pkgname('password-store-1.7.4-noarch-1_SBo')],
       ['system/password-store', '1.7.4'],
       'parses single-hyphened pkgname'
    );

    is([Sbozyp::parse_slackware_pkgname('perl-File-Copy-Recursive-0.2.3-x86_64-1_SBo')],
       ['perl/perl-File-Copy-Recursive', '0.2.3'],
       'parses many-hyphened pkgname'
    );

    is([Sbozyp::parse_slackware_pkgname('functools32-3.2.3_1-x86_64-1_SBo')],
       ['python/functools32', '3.2.3_1'],
       'parses pkgname containing numbers'
    );

    is([Sbozyp::parse_slackware_pkgname('virtualbox-kernel-6.1.40_6.1.12-x86_64-1_SBo')],
       ['system/virtualbox-kernel', '6.1.40_6.1.12'],
       'parses version containing underscore'
    );

    is([Sbozyp::parse_slackware_pkgname('acpica-20220331-x86_64-1000_SBo')],
       ['development/acpica', '20220331'],
       'parses pkgname with multi-digit revision'
    );

    ok(!defined Sbozyp::parse_slackware_pkgname('acpica-20220331-x86_64-1'), q(rejects pkgname without '_SBo' tag));
};

subtest 'prepare_pkg()' => sub {
    # used to mock STDIN
    local *STDIN;
    my $stdin;

    url_exists_or_bail('http://download.savannah.gnu.org/releases/jcal/jcal-0.4.1.tar.gz');
    my $dir = Sbozyp::prepare_pkg(scalar(Sbozyp::pkg('libraries/jcal')));
    is([Sbozyp::sbozyp_readdir("$dir")],
       ["$dir/slack-desc","$dir/jcal.info","$dir/jcal.SlackBuild","$dir/README","$dir/jcal-0.4.1.tar.gz"],
       'downloads and copies correct files to tmp dir'
    );

    if (`uname -m` =~ /^x86_64$/) {
        url_exists_or_bail('http://sourceforge.net/projects/libemf/files/libemf/1.0.7/libEMF-1.0.7.tar.gz');

        my $pkg = Sbozyp::pkg('libraries/libEMF'); # libEMF is UNSUPPORTED on x86_64

        open $stdin, '<', \ "i\n";
        *STDIN = $stdin;
        $dir = Sbozyp::prepare_pkg($pkg);
        is([Sbozyp::sbozyp_readdir("$dir")],
           ["$dir/slack-desc","$dir/libEMF.info","$dir/libEMF.SlackBuild","$dir/README","$dir/libEMF-1.0.7.tar.gz"],
           'ignores unsupported package and prepares anyways if user decides to (i)gnore'
        );

        open $stdin, '<', \ "a\n";
        *STDIN = $stdin;
        like(dies { Sbozyp::prepare_pkg($pkg) },
             qr/^$/,
             'dies if user decides to (a)bort due to unsupported package'
        );

        open $stdin, '<', \ "FOO\ni\n";
        *STDIN = $stdin;
        $dir = Sbozyp::prepare_pkg($pkg);
        is([Sbozyp::sbozyp_readdir("$dir")],
           ["$dir/slack-desc","$dir/libEMF.info","$dir/libEMF.SlackBuild","$dir/README","$dir/libEMF-1.0.7.tar.gz"],
           're-prompts if user provides an invalid option'
        );

    } else {
        url_exists_or_bail('http://downloads.teeworlds.com/teeworlds-0.6.3-linux_x86_64.tar.gz');

        my $pkg = Sbozyp::pkg('games/teeworlds'); # games/teeworlds is UNSUPPORTED on non-x86_64 systems

        open $stdin, '<', \ "i\n";
        *STDIN = $stdin;
        $dir = Sbozyp::prepare_pkg($pkg);
        is([Sbozyp::sbozyp_readdir($dir)],
           ["$dir/teeworlds.png","$dir/teeworlds.info","$dir/teeworlds.desktop","$dir/teeworlds.SlackBuild","$dir/slack-desc","$dir/doinst.sh","$dir/README","$dir/teeworlds-0.6.3-linux_x86_64.tar.gz"],
           'ignores unsupported package and prepares anyways if user decides to (i)gnore'
        );

        open $stdin, '<', \ "a\n";
        like(dies { Sbozyp::prepare_pkg($pkg) },
             qr/^$/,
             'dies if user decides to (a)bort due to unsupported package'
        );

        open $stdin, '<', \ "FOO\ni\n";
        *STDIN = $stdin;
        $dir = Sbozyp::prepare_pkg($pkg);
        is([Sbozyp::sbozyp_readdir($dir)],
           ["$dir/teeworlds.png","$dir/teeworlds.info","$dir/teeworlds.desktop","$dir/teeworlds.SlackBuild","$dir/slack-desc","$dir/doinst.sh","$dir/README","$dir/teeworlds-0.6.3-linux_x86_64.tar.gz"],
           're-prompts if user provides an invalid option'
        );
    }

    url_exists_or_bail('https://cpan.metacpan.org/authors/id/M/MG/MGRABNAR/File-Tail-1.3.tar.gz');
    # force an md5sum mismatch to test how prepare_pkg() deals with this situation. Note that 'perl/perl-File-Tail' should no longer be used in tests for the rest of the suite.
    open my $fh_r, '<', "$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Tail/perl-File-Tail.info" or die;
    open my $fh_w, '>', "$TEST_DIR/tmp.info";
    while (<$fh_r>) {
        if (/^MD5SUM/) { print $fh_w qq(MD5SUM="foo"\n) }
        else { print $fh_w $_ }
    }
    close $fh_r or die;
    close $fh_w or die;
    mv("$TEST_DIR/tmp.info", "$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Tail/perl-File-Tail.info") or die;

    open $stdin, '<', \ "i\n";
    *STDIN = $stdin;
    $dir = Sbozyp::prepare_pkg(scalar(Sbozyp::pkg('perl/perl-File-Tail')));
    is([Sbozyp::sbozyp_readdir("$dir")],
       ["$dir/perl-File-Tail.info","$dir/slack-desc","$dir/perl-File-Tail.SlackBuild","$dir/README","$dir/File-Tail-1.3.tar.gz"],
       'ignores md5sum mismatch and continues preparation if user decides to (i)gnore'
    );

    open $stdin, '<', \"a\n";
    *STDIN = $stdin;
    like(dies { Sbozyp::prepare_pkg(scalar(Sbozyp::pkg('perl/perl-File-Tail'))) },
         qr/^$/,
         'dies on md5sum mismatch if user decides to (a)bort'
     );

    open $stdin, '<', \"r\na\n";
    *STDIN = $stdin;
    like(dies { Sbozyp::prepare_pkg(scalar(Sbozyp::pkg('perl/perl-File-Tail'))) },
         qr/^$/,
         'retries download if user decides to (r)etry'
     );

    open $stdin, '<', \ "FOO\ni\n";
    *STDIN = $stdin;
    $dir = Sbozyp::prepare_pkg(scalar(Sbozyp::pkg('perl/perl-File-Tail')));
    is([Sbozyp::sbozyp_readdir("$dir")],
       ["$dir/perl-File-Tail.info","$dir/slack-desc","$dir/perl-File-Tail.SlackBuild","$dir/README","$dir/File-Tail-1.3.tar.gz"],
       're-prompts if user provides an invalid option'
    );
};

subtest 'build_slackware_pkg()' => sub {
    skip_all('build_slackware_pkg() requires root') unless $> == 0;
    url_exists_or_bail('http://download.savannah.gnu.org/releases/jcal/jcal-0.4.1.tar.gz');
    my $pkg = Sbozyp::pkg('libraries/jcal');
    is(Sbozyp::build_slackware_pkg($pkg),
       "$Sbozyp::CONFIG{TMPDIR}/jcal-0.4.1-x86_64-1_SBo.tgz",
       'successfully builds slackware pkg and outputs it to $CONFIG{TMPDIR}'
    );
};

subtest 'install_slackware_pkg()' => sub {
    skip_all('install_slackware_pkg() requires root') unless $> == 0;
    url_exists_or_bail('http://www.cpan.org/authors/id/A/AD/ADAMK/File-Which-1.09.tar.gz');

    my $pkg = Sbozyp::pkg('perl/perl-File-Which');
    my $slackware_pkg = Sbozyp::build_slackware_pkg($pkg);

    local $ENV{ROOT} = "$TEST_DIR/tmp_root"; # controls installpkg's install destination
    local $Sbozyp::CONFIG{CLEANUP} = 0;

    Sbozyp::install_slackware_pkg($slackware_pkg);
    ok(-f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-File-Which-1.09-x86_64-1_SBo",
       'successfully installs slackware pkg'
    );
    ok(-f $slackware_pkg, 'does not remove the slackware package when $CONFIG{CLEANUP} is false');

    local $Sbozyp::CONFIG{CLEANUP} = 1;
    Sbozyp::install_slackware_pkg($slackware_pkg);
    ok(! -f $slackware_pkg, 'removes slackware package when $CONFIG{CLEANUP} is true');

    # update the slackbuild for perl-File-Which version 1.23 and install it to test that install_slackware_pkg() automatically upgrades old packages
    url_exists_or_bail('https://cpan.metacpan.org/authors/id/P/PL/PLICEASE/File-Which-1.23.tar.gz');
    open my $fh_r, '<', "$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Which/perl-File-Which.info" or die;
    open my $fh_w, '>', "$TEST_DIR/perl-File-Which.info.tmp" or die;
    while (<$fh_r>) {
        if    (/^VERSION/)  { print $fh_w qq(VERSION="1.23"\n) }
        elsif (/^DOWNLOAD/) { print $fh_w qq(DOWNLOAD="https://cpan.metacpan.org/authors/id/P/PL/PLICEASE/File-Which-1.23.tar.gz"\n) }
        elsif (/^MD5SUM/)   { print $fh_w qq(MD5SUM="c8f054534c3c098dd7a0dada60aaae34"\n) }
        else                { print $fh_w $_ }
    }
    close $fh_r or die;
    close $fh_w or die;
    open $fh_r, '<', "$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Which/perl-File-Which.SlackBuild" or die;
    open $fh_w, '>', "$TEST_DIR/perl-File-Which.SlackBuild.tmp" or die;
    while (<$fh_r>) { if (/^VERSION=/) { print $fh_w 'VERSION=${VERSION:-1.23}',"\n" } else { print $fh_w $_ } }
    close $fh_r or die;
    close $fh_w or die;
    mv("$TEST_DIR/perl-File-Which.info.tmp","$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Which/perl-File-Which.info") or die;
    mv("$TEST_DIR/perl-File-Which.SlackBuild.tmp","$Sbozyp::CONFIG{REPO_ROOT}/perl/perl-File-Which/perl-File-Which.SlackBuild") or die;
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg(scalar(Sbozyp::pkg('perl/perl-File-Which', 'IGNORE_CACHE'))));
    ok(-f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-File-Which-1.23-x86_64-1_SBo" && ! -f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-File-Which-1.09-x86_64-1_SBo", 'upgrades pkg if we install a newer version of an existing pkg');
};

subtest 'remove_slackware_pkg()' => sub {
    skip_all('remove_slackware_pkg() requires root') unless $> == 0;

    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    # this slackware pkg is installed from the 'install_slackware_pkg()' subtest
    Sbozyp::remove_slackware_pkg('perl-File-Which-1.23-x86_64-1_SBo');
    ok(! -f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-File-Which-1.23-x86_64-1_SBo",
       'successfully removes slackware pkg'
    );

    remove_tree("$TEST_DIR/tmp_root") or die;
};

subtest 'installed_sbo_pkgs()' => sub {
    skip_all('need root access so we can install pkgs with install_slackware_pkg()') unless $> == 0;

    url_exists_or_bail('www.cpan.org/authors/id/S/SA/SANKO/Readonly-2.00.tar.gz');
    url_exists_or_bail('http://search.cpan.org/CPAN/authors/id/E/ET/ETHER/Test-Pod-1.51.tar.gz');
    url_exists_or_bail('http://search.cpan.org/CPAN/authors/id/D/DO/DOY/Try-Tiny-0.22.tar.gz');

    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg(scalar(Sbozyp::pkg('perl/perl-Readonly'))));
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg(scalar(Sbozyp::pkg('perl/perl-Test-Pod'))));
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg(scalar(Sbozyp::pkg('perl/perl-Try-Tiny'))));

    is({Sbozyp::installed_sbo_pkgs()},
       {'perl/perl-Readonly'=>'2.00','perl/perl-Test-Pod'=>'1.51','perl/perl-Try-Tiny'=>'0.22'},
       'finds all installed SBo pkgs (respecting $ENV{ROOT}) and returns a hash assocating their pkgname to their version'
    );

    mv("$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-Try-Tiny-0.22-x86_64-1_SBo",
       "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/perl-Try-Tiny-0.22-x86_64-1"
    ) or die;
    is({Sbozyp::installed_sbo_pkgs()},
       {'perl/perl-Readonly'=>'2.00','perl/perl-Test-Pod'=>'1.51'},
       q(only returns pkgs that have the '_SBo' tag)
    );
};

done_testing;
