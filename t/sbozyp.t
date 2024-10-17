#!/usr/bin/perl

use strict;
use warnings;
use v5.34.0; # The Perl version on Slackware 15.0 (sbozyp's min supported version)

use Test2::V0 -no_srand => 1;
use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

use Capture::Tiny qw(capture);
use File::Temp;
use File::stat;
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Basename qw(basename);
use Getopt::Long qw(:config no_ignore_case bundling);
use Cwd qw(getcwd);
use FindBin;

require "$FindBin::Bin/../bin/sbozyp"; # import sbozyp

$SIG{INT} = sub { die "\nsbozyp.t: got a SIGINT ... going down!\n" };

            ####################################################
            #                       TESTS                      #
            ####################################################

subtest 'is_multilib_system()' => sub {
    if (-f '/etc/profile.d/32dev.sh') {
        ok(Sbozyp::is_multilib_system(), 'true if system is multilib');
    } else {
        ok(!Sbozyp::is_multilib_system(), 'false if system is not multilib');
    }
};

subtest 'arch()' => sub {
    chomp(my $arch = `uname -m`);
    is(Sbozyp::arch(), $arch, 'returns the systems architecture');
};

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
         qr/^sbozyp: error: the following system command exited with status 1: false$/,
         'dies with error message containing the exit status and failing command when system command fails'
    );
};

subtest 'sbozyp_qx()' => sub {
    ok(lives { Sbozyp::sbozyp_qx('true') }, 'lives if system command succeeds');

    is(Sbozyp::sbozyp_qx('echo foo'), 'foo', 'returns stdout with chomped newline when called in scalar context');

    is([Sbozyp::sbozyp_qx('/bin/echo -e "foo\nbar"')],
       ['foo', 'bar'],
       'returns list of chomped lines when called in list context'
    );

    ok(dies { Sbozyp::sbozyp_qx('false') },
       'dies if system command fails'
    );

    like(dies { Sbozyp::sbozyp_qx('false') },
         qr/^sbozyp: error: the following system command exited with status 1: false$/,
         'dies with error message containing the exit status when system command fails'
     );
};

subtest 'sbozyp_getopts()' => sub {
    my @args = ('-f', '-b', 'foo', 'quux');
    Sbozyp::sbozyp_getopts(\@args, 'f' => \my $foo, 'b=s' => \my $bar);
    ok(($foo and $bar eq 'foo'), 'parses options with Getopt::Long::GetOptionsFromArray()');
    is([@args], ['quux'], 'mutates input array to remove options');
    like(dies { Sbozyp::sbozyp_getopts(['-b'], 'f' => \my $blah) },
         qr/^sbozyp: error: unknown option: b$/,
         'dies with useful error message if option parsing fails'
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

subtest 'sbozyp_print_file()' => sub {
    my $file = '/etc/slackware-version';
    my ($stdout) = capture { Sbozyp::sbozyp_print_file($file) };
    like($stdout, qr/^Slackware/, 'prints file contents to STDOUT');
    like(dies { Sbozyp::sbozyp_print_file('/NOT/A/FILE') },
         qr/^sbozyp: error: could not open file '\/NOT\/A\/FILE': No such file or directory$/,
         'dies with useful message if the file cannot be opened'
    );
};

subtest 'sbozyp_pod2usage()' => sub {
    like(Sbozyp::sbozyp_pod2usage('COMMANDS/INSTALL'),
         qr/Install.+Install or upgrade a package.+Options are:.+--help.+Examples:.+sbozyp install/s,
         'returns pod as string for given section'
    );
};

subtest 'command_usage()' => sub {
    like(Sbozyp::command_usage('install'), qr/^Usage: sbozyp <install\|in> \[-h\].+<pkgname>$/, 'returns usage if given command name');

    like(Sbozyp::command_usage('main'), qr/^Usage: sbozyp \[global_opts\].+\[<command_args>\]$/, q(handles special case of 'main'))
};

subtest 'command_help_msg()' => sub {
    like(Sbozyp::command_help_msg('install'), qr/^Usage: sbozyp <install\|in>.+[\n]Install or upgrade a package.+Options are:.+Examples:/s, 'returns help msg if given command name. Properly strips off leading whitespace.');

    like(Sbozyp::command_help_msg('main'), qr/^Usage: sbozyp \[global_opts\].+Commands are.+Examples:/s, q(handles special case of 'main'));
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
         qr/^sbozyp: error: the following system command exited with status 1: cp -a \Q$TEST_DIR\E\/foo \Q$TEST_DIR\E\/bar$/,
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

subtest 'sbozyp_find_files_recursive()' => sub {
    make_path("$TEST_DIR/foo/bar/baz") or die;
    open my $fh, '>', "$TEST_DIR/foo/foo_f" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/foo/bar_f" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/foo/bar/foo_f" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/foo/bar/baz/baz_f" or die;
    close $fh or die;
    open $fh, '>', "$TEST_DIR/foo/bar/baz/quux_f" or die;
    close $fh or die;

    is([Sbozyp::sbozyp_find_files_recursive("$TEST_DIR/foo")],
       ["$TEST_DIR/foo/bar/baz/baz_f","$TEST_DIR/foo/bar/baz/quux_f","$TEST_DIR/foo/bar/foo_f","$TEST_DIR/foo/bar_f","$TEST_DIR/foo/foo_f"],
       'returns all files in directory recursively'
    );

    like(dies { Sbozyp::sbozyp_find_files_recursive("$TEST_DIR/bar") },
         qr/^sbozyp: error: could not opendir '\Q$TEST_DIR\E\/bar': No such file or directory$/,
         'dies with useful error message if cannot opendir()'
    );

    like(dies { Sbozyp::sbozyp_find_files_recursive("$TEST_DIR/foo/bar_f") },
         qr/^sbozyp: error: could not opendir '\Q$TEST_DIR\E\/foo\/bar_f': Not a directory$/,
         'dies with useful error message if passed a plain file'
    );

    remove_tree("$TEST_DIR/foo") or die;
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
    my @dirs = Sbozyp::sbozyp_mkdir("$TEST_DIR/foo/bar/baz","$TEST_DIR/foo/quux");
    ok(-d "$TEST_DIR/foo/bar/baz" && -d "$TEST_DIR/foo/quux", 'creates entire path for all args');
    is([@dirs], ["$TEST_DIR/foo/bar/baz", "$TEST_DIR/foo/quux"], 'returns created paths');

    remove_tree("$TEST_DIR/foo") or die;

    open my $fh, '>', "$TEST_DIR/foo" or die;
    close $fh or die;

    like(dies { Sbozyp::sbozyp_mkdir("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not mkdir '\Q$TEST_DIR\E\/foo': File exists$/,
         'dies with useful error message if cannot make_path()'
    );

    unlink "$TEST_DIR/foo" or die;
};

subtest 'sbozyp_rmdir()' => sub {
    mkdir "$TEST_DIR/tmp" or die;
    Sbozyp::sbozyp_rmdir("$TEST_DIR/tmp");
    ok(! -d "$TEST_DIR/tmp", 'removes one level directory');
    Sbozyp::sbozyp_mkdir("$TEST_DIR/tmp/multi");
    dies { Sbozyp::sbozyp_rmdir("$TEST_DIR/tmp/multi") };
    ok (-d "$TEST_DIR/tmp", 'only removes one level directory');
    # cleanup
    rmdir "$TEST_DIR/tmp" or die;
};

subtest 'sbozyp_rmdir_rec()' => sub {
    mkdir "$TEST_DIR/tmp" or die;
    Sbozyp::sbozyp_rmdir_rec("$TEST_DIR/tmp");
    ok(! -d "$TEST_DIR/tmp", 'removes one level directory');
    Sbozyp::sbozyp_mkdir("$TEST_DIR/tmp/multi");
    Sbozyp::sbozyp_rmdir_rec("$TEST_DIR/tmp");
    ok (! -d "$TEST_DIR/tmp", 'removes multi level directory');
    Sbozyp::sbozyp_mkdir("$TEST_DIR/tmp/.multi");
    Sbozyp::sbozyp_rmdir_rec("$TEST_DIR/tmp");
    ok (! -d "$TEST_DIR/tmp", 'removes dot files');
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
       {TMPDIR=>'/tmp',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo'},
       '%CONFIG has correct default values'
    );

    my $test_config = "$TEST_DIR/test_sbozyp.conf";

    open my $fh, '>', $test_config or die;
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'/tmp',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo'},
       'parsing empty config file leaves %CONFIG as its default value'
    );

    open $fh, '>', $test_config or die;
    print $fh <<"END";
TMPDIR=foo
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'foo',CLEANUP=>1,REPO_ROOT=>'/var/lib/sbozyp/SBo'},
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
       {TMPDIR=>'bar',CLEANUP=>'bar',REPO_ROOT=>'/var/lib/sbozyp/SBo'},
       'ignores comments, eol comments, whitespace, and blank lines'
    );

    open $fh, '>', $test_config or die;
    print $fh <<'END';
TMPDIR=foo
CLEANUP=foo
REPO_ROOT=foo
REPO_PRIMARY=foo
REPO_0_NAME=foo
REPO_0_GIT_BRANCH=foo
REPO_0_GIT_URL=foo
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>'foo',CLEANUP=>'foo',REPO_ROOT=>'foo',REPO_0_GIT_URL=>'foo',REPO_0_NAME=>'foo',REPO_PRIMARY=>'foo',REPO_0_GIT_BRANCH=>'foo'},
       'successfully parses config file and updates %CONFIG. Note that REPO_NAME is not set to REPO_PRIMARY.'
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
    # TODO
    # like(dies { Sbozyp::parse_config_file($test_config) },
    #      qr/^sbozyp: error: invalid setting on line 1 'foo': '\Q$test_config\E'$/,
    #      'dies with useful error message if config file contains invalid setting'
    # );

    # Set %CONFIG to the value we want for the rest of our testing
    open $fh, '>', $test_config or die;
    print $fh <<"END";
TMPDIR=$TEST_DIR
CLEANUP=1
REPO_ROOT=$TEST_DIR/var/lib/sbozyp/SBo
REPO_PRIMARY=14.1

REPO_0_NAME=14.1
REPO_0_GIT_URL=git://git.slackbuilds.org/slackbuilds.git
REPO_0_GIT_BRANCH=14.1

REPO_1_NAME=14.2
REPO_1_GIT_URL=git://git.slackbuilds.org/slackbuilds.git
REPO_1_GIT_BRANCH=14.2

REPO_2_NAME=15.0
REPO_2_GIT_URL=git://git.slackbuilds.org/slackbuilds.git
REPO_2_GIT_BRANCH=15.0
END
    close $fh or die;
    Sbozyp::parse_config_file($test_config);
    is(\%Sbozyp::CONFIG,
       {TMPDIR=>"$TEST_DIR", CLEANUP=>1,REPO_ROOT=>"$TEST_DIR/var/lib/sbozyp/SBo",REPO_0_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_1_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_1_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_2_GIT_URL=>'git://git.slackbuilds.org/slackbuilds.git',REPO_0_GIT_BRANCH=>'14.1',REPO_1_GIT_BRANCH=>'14.2',REPO_2_GIT_BRANCH=>'15.0',REPO_0_NAME=>'14.1',REPO_1_NAME=>'14.2',REPO_2_NAME=>'15.0',REPO_PRIMARY=>'14.1'},
       '%CONFIG is properly set for use by the rest of this test script'
    );

    unlink $test_config or die;
};

# set REPO_NAME to REPO_PRIMARY ('14.1') for the rest of the tests. Normally this happens in main(), which we havent tested yet.
$Sbozyp::CONFIG{REPO_NAME} = $Sbozyp::CONFIG{REPO_PRIMARY};

# the sbozyp_tee() subtest must come after the parse_config_file() subtest, as sbozyp_tee()'s implementation uses CONFIG{TMPDIR} which is set in the parse_config_file() subtest.
subtest 'sbozyp_tee()' => sub {
    my $teed_stdout;
    my ($real_stdout) = capture { $teed_stdout = Sbozyp::sbozyp_tee('echo -e "foo\nbar\nbaz"') };
    is($teed_stdout, $real_stdout, 'captures stdout');
    is(Sbozyp::sbozyp_tee('1>&2 echo foo'), '', 'returns empty string if command produces no output to STDOUT');
    ($real_stdout) = capture { $teed_stdout = Sbozyp::sbozyp_tee('echo foo && echo bar ; echo baz') };
    is($teed_stdout, $real_stdout, 'captures stdout of shell command with meta chars');
    is([Sbozyp::sbozyp_readdir($Sbozyp::CONFIG{TMPDIR})], [], 'cleans up tmp file from $CONFIG{TMPDIR}');
    like(dies { Sbozyp::sbozyp_tee('false') },
         qr/^sbozyp: error: the following system command exited with status 1: bash -c set -o pipefail && \( false \) \| tee '[^']+'$/,
         'dies with useful error message is system command fails'
    );
    is([Sbozyp::sbozyp_readdir($Sbozyp::CONFIG{TMPDIR})], [], 'cleans up tmp file from $CONFIG{TMPDIR} after a failed system command');
};

subtest 'sync_repo()' => sub {
    Sbozyp::sbozyp_mkdir( "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}");

    Sbozyp::sync_repo();
    ok(-d "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/.git",
       'clones SBo repo to $CONFIG{REPO_ROOT}/$CONFIG{REPO_NAME} if it has not yet been cloned'
    );

    my ($stdout) = capture { Sbozyp::sync_repo() };
    like($stdout,
         qr/HEAD is now at/i,
         'uses git fetch and git reset if repo has already been cloned'
    );
};

# add our mock packages to the SBo 14.1 repo we just cloned in the sync_repo() subtest
Sbozyp::sbozyp_copy("$FindBin::Bin/mock-packages", "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc");

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
};

subtest 'find_pkgname()' => sub {
    is(Sbozyp::find_pkgname('sbozyp-basic'), 'misc/sbozyp-basic', 'finds pkgname');
    is(Sbozyp::find_pkgname('misc/sbozyp-basic'), 'misc/sbozyp-basic', 'accepts full pkgname');
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
    my $info_file = "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/sbozyp-basic.info";
    is({Sbozyp::parse_info_file($info_file)},
       {PRGNAM=>'sbozyp-basic',VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=>'https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz',MD5SUM=>'1973a308d90831774a0922e9ec0085ff',DOWNLOAD_x86_64=>'',MD5SUM_x86_64=>'',REQUIRES=>'',MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net'},
       'parses info file into correct hash'
    );

    $info_file = "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-multiple-download/sbozyp-multiple-download.info";
    is({Sbozyp::parse_info_file($info_file)},
       {PRGNAM=>'sbozyp-multiple-download',VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=>'https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz',MD5SUM=>'1973a308d90831774a0922e9ec0085ff 1973a308d90831774a0922e9ec0085ff 1973a308d90831774a0922e9ec0085ff',DOWNLOAD_x86_64=>'','MD5SUM_x86_64'=>'',REQUIRES=>'',MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net'},
       'squishes newline-escapes into single spaces'
    );

    like(dies { Sbozyp::parse_info_file("$TEST_DIR/foo") },
         qr/^sbozyp: error: could not open file '\Q$TEST_DIR\E\/foo': No such file or directory$/,
         'dies with useful error if given non-existent info file'

    );
};

subtest 'pkg()' => sub {
    is({Sbozyp::pkg('misc/sbozyp-basic')},
       {PRGNAM=>'sbozyp-basic',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/sbozyp-basic.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/sbozyp-basic.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/README",PKGNAME=>'misc/sbozyp-basic',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic",VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=>['https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz'],MD5SUM=>['1973a308d90831774a0922e9ec0085ff'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>[],MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net',ARCH_UNSUPPORTED=>0,HAS_EXTRA_DEPS=>0},
       'creates correct pkg hash'
    );

    is({Sbozyp::pkg('sbozyp-basic')},
       {PRGNAM=>'sbozyp-basic',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/sbozyp-basic.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/sbozyp-basic.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic/README",PKGNAME=>'misc/sbozyp-basic',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-basic",VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=>['https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz'],MD5SUM=>['1973a308d90831774a0922e9ec0085ff'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>[],MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net',ARCH_UNSUPPORTED=>0,HAS_EXTRA_DEPS=>0},
       'accepts just a prgnam'
    );

    is({Sbozyp::pkg('misc/sbozyp-readme-extra-deps')},
       {PRGNAM=>'sbozyp-readme-extra-deps',DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-readme-extra-deps/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-readme-extra-deps/sbozyp-readme-extra-deps.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-readme-extra-deps/sbozyp-readme-extra-deps.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-readme-extra-deps/README",PKGNAME=>'misc/sbozyp-readme-extra-deps',PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/misc/sbozyp-readme-extra-deps",VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=>['https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz'],MD5SUM=>['1973a308d90831774a0922e9ec0085ff'],DOWNLOAD_x86_64=>[],MD5SUM_x86_64=>[],REQUIRES=>['sbozyp-basic'],MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net',ARCH_UNSUPPORTED=>0,HAS_EXTRA_DEPS=>1},
       'specifies HAS_EXTRA_DEPS=>1 if %README% is in .info files requires, and does not include %README% in the pkgs REQUIRES field'
    );

    my $is_x86_64 = Sbozyp::arch() eq 'x86_64';
    my $unsupported_pkgname = $is_x86_64 ? 'misc/sbozyp-unsupported-x86_64' : 'misc/sbozyp-unsupported-no-x86_64';
    my $unsupported_prgnam = basename($unsupported_pkgname);
    is({Sbozyp::pkg($unsupported_pkgname)},
       {PRGNAM=>$unsupported_prgnam,DESC_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/$unsupported_pkgname/slack-desc",INFO_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/$unsupported_pkgname/$unsupported_prgnam.info",SLACKBUILD_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/$unsupported_pkgname/$unsupported_prgnam.SlackBuild",README_FILE=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/$unsupported_pkgname/README",PKGNAME=>$unsupported_pkgname,PKGDIR=>"$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/$unsupported_pkgname",VERSION=>'1.0',HOMEPAGE=>'https://github.com/NicholasBHubbard/sbozyp/releases/tag/SbozypFakeRelease-1.0',DOWNLOAD=> $is_x86_64 ? ['https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz'] : [],MD5SUM=> $is_x86_64 ? ['1973a308d90831774a0922e9ec0085ff'] : [],DOWNLOAD_x86_64=> $is_x86_64 ? ['UNSUPPORTED'] : ['https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1.0.tar.gz'],MD5SUM_x86_64=> $is_x86_64 ? [] : ['1973a308d90831774a0922e9ec0085ff'],REQUIRES=>[],MAINTAINER=>'Nicholas Hubbard',EMAIL=>'nicholashubbard@posteo.net',ARCH_UNSUPPORTED=>'unsupported',HAS_EXTRA_DEPS=>0},
       'creates correct pkg for package that is unsupported on this architecture'
    );

    is(ref(Sbozyp::pkg('system/password-store')), 'HASH', 'returns hashref in scalar context');

    like(dies { Sbozyp::pkg('FOO') },
         qr/^sbozyp: error: could not find a package named 'FOO'$/,
         'dies with useful error message if passed invalid prgnam'
    );
};

subtest 'pkg_queue()' => sub {
    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-E')))],
       [scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-E'))],
       'returns single elem list containing input package when it has no deps'
    );

    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-B')))],
       [scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-D')), scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-B'))],
       'returns two elem list in correct order for pkg with single dependency'
    );

    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-A')))],
       [scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-E')), scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-C')), scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-D')), scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-B')), scalar(Sbozyp::pkg('misc/sbozyp-recursive-dep-A'))],
       'resolves recursive dependencies'
    );

    is([Sbozyp::pkg_queue(scalar(Sbozyp::pkg('misc/sbozyp-readme-extra-deps')))],
       [scalar(Sbozyp::pkg('misc/sbozyp-basic')), scalar(Sbozyp::pkg('misc/sbozyp-readme-extra-deps'))],
       'does not trip up from %README% being in the .info files REQUIRES'
    );
};

subtest 'merge_pkg_queues()' => sub {
    my $pkg1 = Sbozyp::pkg('sbozyp-basic');
    my $pkg2 = Sbozyp::pkg('sbozyp-basic');
    my $pkg3 = Sbozyp::pkg('sbozyp-nested-dir');

    my @queue = Sbozyp::merge_pkg_queues($pkg1, $pkg3, $pkg1, $pkg3, $pkg3, $pkg1, $pkg3);
    is(\@queue,
       [$pkg1, $pkg3],
       'removes all duplicate pkgs, leaving only the first occurence'
    );

    @queue = Sbozyp::merge_pkg_queues($pkg1, $pkg2);
    is(\@queue,
       [$pkg1],
       'removes duplicate pkgs by PKGNAME'
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

    is([Sbozyp::parse_slackware_pkgname('python-e_dbus-12.2-x86_64-1_SBo')],
       ['libraries/python-e_dbus', '12.2'],
       'parses prgnam containing underscore'
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
    my $pkg = Sbozyp::pkg('sbozyp-basic');
    my $staging_dir = Sbozyp::prepare_pkg($pkg);
    is([Sbozyp::sbozyp_readdir($staging_dir)],
       ["$staging_dir/README","$staging_dir/SbozypFakeRelease-1.0.tar.gz","$staging_dir/sbozyp-basic.SlackBuild","$staging_dir/sbozyp-basic.info","$staging_dir/slack-desc"],
       'returns tmp dir containing all of the pkgs files and its downloaded source code'
    );

    $pkg = Sbozyp::pkg('sbozyp-nested-dir');
    $staging_dir = Sbozyp::prepare_pkg($pkg);
    is([do { my @files; File::Find::find(sub { push @files, $File::Find::name if -f $File::Find::name }, "$staging_dir"); sort @files }],
       ["$staging_dir/README","$staging_dir/SbozypFakeRelease-1.0.tar.gz","$staging_dir/nested-dir/bar.txt","$staging_dir/nested-dir/foo.txt","$staging_dir/sbozyp-nested-dir.SlackBuild","$staging_dir/sbozyp-nested-dir.info","$staging_dir/slack-desc"],
       'includes files in nested directories of the package'
    );

    if (Sbozyp::arch() eq 'x86_64') {
        $pkg = Sbozyp::pkg('sbozyp-unsupported-not-x86_64');
        $staging_dir = Sbozyp::prepare_pkg($pkg);
        is([Sbozyp::sbozyp_readdir($staging_dir)],
           ["$staging_dir/README","$staging_dir/SbozypFakeRelease-1.0.tar.gz","$staging_dir/sbozyp-unsupported-not-x86_64.SlackBuild","$staging_dir/sbozyp-unsupported-not-x86_64.info","$staging_dir/slack-desc"],
           'properly prepares package only supported on x86_64'
        );
    }

    $pkg = Sbozyp::pkg('sbozyp-nonexistent-url');
    ok(dies { Sbozyp::prepare_pkg($pkg) },
       'dies if packages download url does not exist'
    );

    $pkg = Sbozyp::pkg('sbozyp-md5sum-mismatch');
    like(dies { Sbozyp::prepare_pkg($pkg) },
         qr|^sbozyp: error: md5sum mismatch for 'https://github\.com/NicholasBHubbard/sbozyp/archive/refs/tags/SbozypFakeRelease-1\.0\.tar\.gz': expected '29b3a308d97831774aa926e94c00a59f': got '1973a308d90831774a0922e9ec0085ff'$|,
         'dies with useful error message if there is an md5sum mismatch'
    );
};

subtest 'build_slackware_pkg()' => sub {
    skip_all('build_slackware_pkg() requires root') unless $> == 0;
    my $pkg = Sbozyp::pkg('sbozyp-basic');
    my $slackware_pkg;
    my $stdout = capture { $slackware_pkg = Sbozyp::build_slackware_pkg($pkg) };
    is($slackware_pkg,
       "$Sbozyp::CONFIG{TMPDIR}/sbozyp-basic-1.0-noarch-1_SBo.tgz",
       'successfully builds slackware pkg and outputs it to $CONFIG{TMPDIR}'
    );
    like($stdout,
         qr/Slackware package \Q$Sbozyp::CONFIG{TMPDIR}\E\/sbozyp-basic-1\.0-noarch-1_SBo\.tgz created/,
         'SlackBuild output produces to STDOUT'
    );

    unlink $slackware_pkg or die;
};

subtest 'install_slackware_pkg()' => sub {
    skip_all('install_slackware_pkg() requires root') unless $> == 0;

    # change the install destination
    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    my $pkg = Sbozyp::pkg('sbozyp-basic');
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));
    ok(-f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-1.0-noarch-1_SBo",
       'successfully installs slackware pkg'
    );

    my $stdout = capture { Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg)) };
    like($stdout,
         qr/Package sbozyp-basic-1\.0-noarch-1_SBo\.tgz installed/,
         'reinstalls pkg that is already installed'
    );

    $pkg = Sbozyp::pkg('sbozyp-basic-2.0');
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));
    ok(-f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-2.0-noarch-1_SBo" && !-f  "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-1.0-noarch-1_SBo",
       'upgrades package if older version already exists'
    );

    remove_tree "$TEST_DIR/tmp_root" or die;
};

subtest 'remove_slackware_pkg()' => sub {
    skip_all('remove_slackware_pkg() requires root') unless $> == 0;

    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    my $pkg = Sbozyp::pkg('sbozyp-basic');
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));
    Sbozyp::remove_slackware_pkg('sbozyp-basic');
    ok(!-f "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-1.0-noarch-1_SBo",
       'successfully removes slackware pkg'
    );

    remove_tree("$TEST_DIR/tmp_root") or die;
};

subtest 'installed_sbo_pkgs()' => sub {
    skip_all('need root access so we can install pkgs with install_slackware_pkg()') unless $> == 0;

    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    is(Sbozyp::installed_sbo_pkgs(), {}, 'returns empty hash if $root/var/lib/pkgtools/packages does not exist');

    my $pkg1 = Sbozyp::pkg('sbozyp-basic');
    my $pkg2 = Sbozyp::pkg('sbozyp-nested-dir');
    my $pkg3 = Sbozyp::pkg('sbozyp-readme-extra-deps');

    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg1));
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg2));
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg3));

    is({Sbozyp::installed_sbo_pkgs()},
       {'misc/sbozyp-basic'=>'1.0','misc/sbozyp-nested-dir'=>'1.0','misc/sbozyp-readme-extra-deps'=>'1.0'},
       'finds all installed SBo pkgs (respecting $ENV{ROOT}) and returns a hash assocating their pkgname to their version'
    );

    rename "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-1.0-noarch-1_SBo", "$TEST_DIR/tmp_root/var/lib/pkgtools/packages/sbozyp-basic-1.0-noarch-1" or die;

    is({Sbozyp::installed_sbo_pkgs()},
       {'misc/sbozyp-nested-dir'=>'1.0','misc/sbozyp-readme-extra-deps'=>'1.0'},
       q(only returns pkgs that have the '_SBo' tag)
    );

    remove_tree("$TEST_DIR/tmp_root") or die;
};

subtest 'pkg_installed()' => sub {
    skip_all('test for pkg_installed() requires root') unless $> == 0;

    # change the install destination
    local $ENV{ROOT} = "$TEST_DIR/tmp_root";
    mkdir $ENV{ROOT} or die;

    my $pkg1 = Sbozyp::pkg('sbozyp-basic');
    my $pkg2 = Sbozyp::pkg('sbozyp-nested-dir'); # not installed

    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg1));

    is('1.0', Sbozyp::pkg_installed($pkg1), 'returns version of installed package if it is installed');
    is(undef, Sbozyp::pkg_installed($pkg2), 'returns undef in pkg is not installed');

    remove_tree("$TEST_DIR/tmp_root") or die;
};

subtest 'repo_name_repo_num()'  => sub {
    my $repo_num_0 = Sbozyp::repo_name_repo_num('14.1');
    my $repo_num_1 = Sbozyp::repo_name_repo_num('14.2');
    my $repo_num_2 = Sbozyp::repo_name_repo_num('15.0');
    ok($repo_num_0 == 0 && $repo_num_1 == 1 && $repo_num_2 == 2, 'returns correct repo numbers');
    is(undef, Sbozyp::repo_name_repo_num('NOTAREPONAME'), 'returns undef if given invalid repo name');
};

subtest 'repo_num_git_branch()'  => sub {
    my $git_branch_0 = Sbozyp::repo_num_git_branch(0);
    my $git_branch_1 = Sbozyp::repo_num_git_branch(1);
    my $git_branch_2 = Sbozyp::repo_num_git_branch(2);
    ok($git_branch_0 eq '14.1' && $git_branch_1 eq '14.2' && $git_branch_2 eq '15.0', 'returns correct git branches');
};

subtest 'repo_num_git_url()'  => sub {
    my $url = 'git://git.slackbuilds.org/slackbuilds.git';
    my $git_url_0 = Sbozyp::repo_num_git_url(0);
    my $git_url_1 = Sbozyp::repo_num_git_url(1);
    my $git_url_2 = Sbozyp::repo_num_git_url(2);
    ok($git_url_0 eq $url && $git_url_1 eq $url && $git_url_2 eq $url, 'returns correct git urls');
};

subtest 'repo_git_branch()' => sub {
    is(Sbozyp::repo_git_branch(), '14.1', 'returns name of current repos branch');
};

subtest 'repo_git_url()' => sub {
    is(Sbozyp::repo_git_url(), 'git://git.slackbuilds.org/slackbuilds.git', 'returns name of current repos url');
};

subtest 'manage_install_queue_ui()' => sub {
    # the pkgs picked here are arbitrary ...
    my $pkg1 = Sbozyp::pkg('sbozyp-basic');
    my $pkg2 = Sbozyp::pkg('sbozyp-nested-dir');
    my $pkg3 = Sbozyp::pkg('sbozyp-readme-extra-deps');
    my @queue = ($pkg1, $pkg2, $pkg3);

    my $stdin; # were gonna mock STDIN for the following tests.
    my $stdout; # some tests capture STDOUT into this variable

    open $stdin, '<', \"confirm\n" or die;
    local *STDIN = $stdin;
    is(\@queue, [Sbozyp::manage_install_queue_ui(@queue)], q('confirm' returns queue as is));
    close $stdin or die;

    open $stdin, '<', \"c\n" or die;
    local *STDIN = $stdin;
    is(\@queue, [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 'c' as abbreviation for 'confirm'));
    close $stdin or die;

    open $stdin, '<', \"INVALID\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/invalid input/, 'rejects invalid input');
    close $stdin or die;

    open $stdin, '<', \"quit\n" or die;
    local *STDIN = $stdin;
    is([], [Sbozyp::manage_install_queue_ui(@queue)], q('quit' returns empty list));
    close $stdin or die;

    open $stdin, '<', \"q\n" or die;
    local *STDIN = $stdin;
    is([], [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 'q' as abbreviation for 'quit'));
    close $stdin or die;

    open $stdin, '<', \"swap 0 2\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg3,$pkg2,$pkg1], [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 'swap' as well as just s));
    close $stdin or die;

    open $stdin, '<', \"s 0 1\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg2,$pkg1,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 's' as abbreviation for 'swap'));
    close $stdin or die;

    open $stdin, '<', \"swap 2 0\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg3,$pkg2,$pkg1], [Sbozyp::manage_install_queue_ui(@queue)], q('swap' doesnt care about order of indices));
    close $stdin or die;

    open $stdin, '<', \"swap 0 3\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/index.*out of range/, 'swap gives error message for index out of range');
    close $stdin or die;

    open $stdin, '<', \"swap 0 -1\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/invalid input/, 'rejects negative numbers as invalid input');
    close $stdin or die;

    open $stdin, '<', \"delete 1\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q('delete' deletes pkg at given index));
    close $stdin or die;

    open $stdin, '<', \"d 1\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 'd' as abbreviation for 'delete'));
    close $stdin or die;

    open $stdin, '<', \"d\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/invalid input/, q('delete' requires arg or else it rejects input));
    close $stdin or die;

    open $stdin, '<', \"d FOO\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/invalid input/, q('delete' requires arg to be numeric or else it rejects input));
    close $stdin or die;

    my $pkg4_prgnam = 'sbozyp-recursive-dep-B';
    my $pkg4_pkgname = 'misc/sbozyp-recursive-dep-B';
    my $pkg4 = Sbozyp::pkg($pkg4_prgnam); # $pkg4 is used in tests for 'add'

    open $stdin, '<', \"add 1 $pkg4_prgnam\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg4,$pkg2,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q('add' adds a pkg named PRGNAM to the queue at INDEX));
    close $stdin or die;

    open $stdin, '<', \"a 1 $pkg4_prgnam\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg4,$pkg2,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q(accepts 'a' as abbreviation for 'add'));
    close $stdin or die;

    open $stdin, '<', \"a 1 $pkg4_pkgname\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg4,$pkg2,$pkg3], [Sbozyp::manage_install_queue_ui(@queue)], q('add' accepts PKGNAME as well as PRGNAM));
    close $stdin or die;

    open $stdin, '<', \"a 3 $pkg4_prgnam\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg2,$pkg3,$pkg4], [Sbozyp::manage_install_queue_ui(@queue)], q('add' adds to end of queue when specifying one more than last IDX));
    close $stdin or die;

    open $stdin, '<', \"a 4 $pkg4_prgnam\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/index '4' is out of range \(0 - 3\)/, q('add' rejects IDX out of range));
    close $stdin or die;

    open $stdin, '<', \"a 3 NOTAREALPACKAGE\nc\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::manage_install_queue_ui(@queue) };
    like($stdout, qr/could not find a package named 'NOTAREALPACKAGE'/, q('add' rejects non-existent package));
    close $stdin or die;

    open $stdin, '<', \"a $pkg4_prgnam\nc\n" or die;
    local *STDIN = $stdin;
    is([$pkg1,$pkg2,$pkg3,$pkg4], [Sbozyp::manage_install_queue_ui(@queue)], q('add' allows IDX to be left out and defaults to adding to end of the queue));
    close $stdin or die;
};

subtest 'query_pkg_ui()' => sub {
    my $stdin; # were gonna mock STDIN for the following tests.
    my $stdout; # some tests capture STDOUT into this variable

    my $pkg = Sbozyp::pkg('sbozyp-basic');

    open $stdin, '<', \"q\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::query_pkg_ui($pkg) };
    like($stdout, qr/README.+\.info.+\.SlackBuild.+slack-desc/s,'lists pkg files in consistent order');
    close $stdin or die;

    local $ENV{PAGER} = 'cat'; # so we can actually capture STDOUT

    open $stdin, '<', \"1\nq\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::query_pkg_ui($pkg) };
    like($stdout, qr/There is nothing special about this package/, 'prints README file if it is selected');
    close $stdin or die;

    open $stdin, '<', \"3\nq\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::query_pkg_ui($pkg) };
    like($stdout, qr/makepkg/, 'prints .SlackBuild file if it is selected');
    close $stdin or die;

    open $stdin, '<', \"6\nq\n" or die;
    local *STDIN = $stdin;
    ($stdout) = capture { Sbozyp::query_pkg_ui($pkg) };
    like($stdout, qr/'6' is not a valid option/, 'rejects invalid input with useful message');
    close $stdin or die;
};

subtest 'path_to_pkgname()' => sub {
    my $path = "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}/office/mu";
    is(Sbozyp::path_to_pkgname($path), 'office/mu', 'returns correct pkgname');
};

subtest 'set_repo_name_or_die()' => sub {
    my $valid_repo_name = '15.0';
    my $invalid_repo_name = 'NOTAREPO';

    my $original_repo_name = $Sbozyp::CONFIG{REPO_NAME}; # we dont want to overwrite the REPO_NAME for the rest of the tests. Gonna set it back at the end.

    Sbozyp::set_repo_name_or_die($valid_repo_name);
    is($Sbozyp::CONFIG{REPO_NAME}, $valid_repo_name, 'sets $CONFIG{REPO_NAME} if passed valid repo name');

    like(dies { Sbozyp::set_repo_name_or_die($invalid_repo_name) },
         qr/^sbozyp: error: no repo named '\Q$invalid_repo_name\E'$/,
         'dies with useful error message if given invalid repo name'
    );

    # cleanup
    Sbozyp::set_repo_name_or_die($original_repo_name);
};

            ####################################################
            #                   MAIN TESTS                     #
            ####################################################

subtest 'install_command_main()' => sub {
    skip_all('install_command_main() requires root') unless $> == 0;

    local $ENV{ROOT} = "$TEST_DIR/tmp_root"; # were gonna install some packages

    my ($stdout, $stderr); # were gonna capture STDOUT and STDERR into these for some tests

    ($stdout) = capture { Sbozyp::install_command_main('-h') };
    like($stdout, qr/Usage.+Install or upgrade a package.+\-h.+Print this help message/s, 'prints help message if given -h option');

    ($stdout) = capture { Sbozyp::install_command_main('--help') };
    like($stdout, qr/Usage.+Install or upgrade a package.+\-h.+Print this help message/s, 'prints help message if given --help option');

    ($stdout) = capture { Sbozyp::install_command_main('-i', '--help', 'mu') };
    like($stdout, qr/Usage.+Install or upgrade a package.+\-h.+Print this help message/s, 'prints help message if given --help option regardless of other options');

    like(dies { Sbozyp::install_command_main('-H', 'mu') },
         qr/unknown option: H/,
         'dies with useful message if given invalid option'
    );

    like(dies { Sbozyp::install_command_main() },
         qr/^Usage/,
         'dies with usage if not given a package name'
    );

    like(dies { Sbozyp::install_command_main('NOTAPACKAGE') },
         qr/could not find a package named 'NOTAPACKAGE'/,
         'dies with useful message if the package does not exist'
    );

    like(dies { Sbozyp::install_command_main('mu', 'sbozyp-basic') },
         qr/^Usage:/,
         'dies with usage if given more than 1 pkgname arg'
    );

    local $Sbozyp::CONFIG{CLEANUP} = 1;

    Sbozyp::install_command_main('-i', 'sbozyp-basic');
    ok(Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-basic')}), 'installs a package');
    ok(! -f "$TEST_DIR/sbozyp-basic-1.0-noarch-1_SBo.tgz", 'removes slackware package after installing it if $ONFIG{CLEANUP} = 1');

    Sbozyp::install_command_main('-i', 'sbozyp-recursive-dep-A');
    ok(   Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-A')})
       && Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-B')})
       && Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-C')})
       && Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-D')})
       && Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-E')}),
       'installs a package along with its dependencies'
    );
    remove_tree "$TEST_DIR/tmp_root" or die; # cleanup for the next test

    Sbozyp::install_command_main('-i', '-n', 'sbozyp-recursive-dep-A');
    ok(   Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-A')})
       && not(Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-B')}))
       && not(Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-C')}))
       && not(Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-D')}))
       && not(Sbozyp::pkg_installed({Sbozyp::pkg('sbozyp-recursive-dep-E')})),
       'only installs package, not dependencies, when given -n option'
    );

    remove_tree "$TEST_DIR/tmp_root" or die;

    local $Sbozyp::CONFIG{CLEANUP} = 0;
    Sbozyp::install_command_main('-i', 'sbozyp-basic');
    ok(-f "$TEST_DIR/sbozyp-basic-1.0-noarch-1_SBo.tgz", 'does not remove slackware package after installing it if $ONFIG{CLEANUP} = 0');

    ($stdout) = capture { Sbozyp::install_command_main('-i', 'sbozyp-basic') };
    like($stdout, qr/skipping install of 'misc\/sbozyp-basic' as it is installed and up to date$/, 'by default skips install with useful message if package is already installed');

    ($stdout) = capture { Sbozyp::install_command_main('-i', '-f', 'sbozyp-basic') };
    like($stdout, qr/Installing package sbozyp-basic-1.0-noarch-1_SBo\.tgz/, 're-installs package if it is already installed if using \'-f\' option');

    remove_tree "$TEST_DIR/tmp_root" or die;
};

subtest 'query_command_main()' => sub {
    local $ENV{ROOT} = "$TEST_DIR/tmp_root";

    my ($stdout, $stderr); # were gonna capture STDOUT and STDERR into these for some tests

    ($stdout) = capture { Sbozyp::query_command_main('-h', 'mu') };
    like($stdout, qr/^Usage.+Query for information.+Options are/s, q(outputs help message if given '-h' option));

    ($stdout) = capture { Sbozyp::query_command_main('--help', 'mu') };
    like($stdout, qr/^Usage.+Query for information.+Options are/s, q(outputs help message if given '--help' option));

    ($stdout) = capture { Sbozyp::query_command_main('--help') };
    like($stdout, qr/^Usage.+Query for information.+Options are/s, q(--help options doesn't require a pkgname arg to be given));

    like(dies { Sbozyp::query_command_main('-Z', 'mu') },
         qr/sbozyp: error: unknown option: Z/,
         'dies with useful error if given an invalid option'
    );

    like(dies { Sbozyp::query_command_main('-d', '-i', '-p', 'mu') },
         qr/sbozyp: error: can only set 1 of options.+but 3 were set/,
         'dies with useful error message if multiple mutually exclusive options are given'
    );

    like(dies { Sbozyp::query_command_main('mu', 'sbozyp-basic') },
         qr/^Usage:/,
         'dies with usage if given more than 1 pkgname arg'
    );

    like(dies { Sbozyp::query_command_main('-d') }, qr/^Usage:/, 'dies with usage if missing the pkgname arg');

    ($stdout) = capture { Sbozyp::query_command_main('-d', 'sbozyp-basic') };
    like($stdout, qr/HOW TO EDIT THIS FILE.+sbozyp-basic/s, 'prints packages slack-desc file if given -d option');

    ($stdout) = capture { Sbozyp::query_command_main('sbozyp-basic', '-d') };
    like($stdout, qr/HOW TO EDIT THIS FILE.+sbozyp-basic/s, 'option can come after pkgname arg');

    ($stdout) = capture { Sbozyp::query_command_main('-i', 'sbozyp-basic') };
    like($stdout, qr/PRGNAM="sbozyp-basic".+VERSION=.+REQUIRES/s, 'prints .info file if given -i option');

    ($stdout) = capture { Sbozyp::query_command_main('-r', 'sbozyp-basic') };
    like($stdout, qr/This is a mock package to be used in sbozyp test code.+There is nothing special/s, 'prints README file if given -r option');

    ($stdout) = capture { Sbozyp::query_command_main('-s', 'sbozyp-basic') };
    like($stdout, qr/Slackware build script for sbozyp-basic.+make/s, 'prints .SlackBuild file if given -s option');

    ($stdout) = capture { Sbozyp::query_command_main('-q', 'sbozyp-recursive-dep-A') };
    like($stdout, qr|^misc/sbozyp-recursive-dep-E\nmisc/sbozyp-recursive-dep-C\nmisc/sbozyp-recursive-dep-D\nmisc/sbozyp-recursive-dep-B\nmisc/sbozyp-recursive-dep-A\n$|s, 'prints packages dependencies (in order and recursively) if given -q option');

    if ($> == 0) { # need to be root to install a package
        local $ENV{ROOT} = "$TEST_DIR/tmp_root"; # were gonna install some packages
        my $pkg = Sbozyp::pkg('sbozyp-basic');
        Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));

        ok(dies { Sbozyp::query_command_main('-p', 'sbozyp-nested-dir') },
             'dies if package is not installed with -p option'
        );

        ($stdout) = capture { Sbozyp::query_command_main('-p', 'sbozyp-basic') };
        like($stdout, qr/^1\.0$/s, 'outputs installed version and does not die if package is installed with -p option');

        remove_tree "$TEST_DIR/tmp_root" or die;
    }
};

subtest 'remove_command_main()' => sub {
    skip_all('remove_command_main() requires root') unless $> == 0;

    local $ENV{ROOT} = "$TEST_DIR/tmp_root"; # were gonna install some packages

    my $stdout; # were gonna capture STDOUT into this variable for some of these tests
    my $stdin;  # were gonna mock user input in some of these tests.

    ($stdout) = capture { Sbozyp::remove_command_main('-h') };
    like($stdout, qr/^Usage: sbozyp remove.+Remove a package.+Options are/s, q('-h' option prints a help string to STDOUT));

    ($stdout) = capture { Sbozyp::remove_command_main('--help') };
    like($stdout, qr/^Usage: sbozyp remove.+Remove a package.+Options are/s, q(also accepts '--help' instead of '-h'));

    ($stdout) = capture { Sbozyp::remove_command_main('--help', 'FOOBARBAZ') };
    like($stdout, qr/^Usage: sbozyp remove.+Remove a package.+Options are/s, q(ignores other arg if given '--help' option));


    like(dies { Sbozyp::remove_command_main() },
         qr/^Usage:/,
         'dies with usage if not give pkgname arg'
    );

    like(dies { Sbozyp::remove_command_main('mu', 'sbozyp-basic') },
         qr/^Usage:/,
         'dies with usage if given more than 1 pkgname arg'
    );

    like(dies { Sbozyp::remove_command_main('NOTAPACKAGE') },
         qr/^sbozyp: error: could not find a package named 'NOTAPACKAGE'$/,
         'dies with useful error message if given a non-existent package'
    );

    like(dies { Sbozyp::remove_command_main('sbozyp-basic') },
         qr/^sbozyp: error: the package 'misc\/sbozyp-basic' is not installed$/,
         'dies with useful error message if attempting to remove a package that is not installed'
     );

    my $pkg = Sbozyp::pkg('sbozyp-basic');

    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));
    open $stdin, '<', \"no\n" or die;
    local *STDIN = $stdin;
    Sbozyp::remove_command_main('sbozyp-basic');
    close $stdin;
    ok(defined(Sbozyp::pkg_installed($pkg)), 'prompts user if the really want to remove the package, and if they say no then does not remove');

    open $stdin, '<', \"yes\n" or die;
    local *STDIN = $stdin;
    Sbozyp::remove_command_main('sbozyp-basic');
    close $stdin;
    ok(!defined(Sbozyp::pkg_installed($pkg)), 'prompts user if the really want to remove the package, and if they say yes then removes the package');

    # install it again ...
    Sbozyp::install_slackware_pkg(Sbozyp::build_slackware_pkg($pkg));
    Sbozyp::remove_command_main('-i', 'sbozyp-basic');
    ok(!defined(Sbozyp::pkg_installed($pkg)), q(if given '-i' option then does not prompt user for confirmation and just goes ahead and removes the package));

    remove_tree("$TEST_DIR/tmp_root") or die;
};

subtest 'search_command_main()' => sub {
    my $stdout; # were gonna capture STDOUT into this variable for some of these tests

    ($stdout) = capture { Sbozyp::search_command_main('--help') };
    like($stdout, qr/^Usage.+Search for a package using a Perl regex.+Options are/s, q('-h' option prints a help string to STDOUT));

    ($stdout) = capture { Sbozyp::search_command_main('--help') };
    like($stdout, qr/^Usage.+Search for a package using a Perl regex.+Options are/s, q(also accepts '--help'));

    ($stdout) = capture { Sbozyp::search_command_main('--help', 'fooregex') };
    like($stdout, qr/^Usage.+Search for a package using a Perl regex.+Options are/s, q(prints help even if args are given afterwards));

    ($stdout) = capture { Sbozyp::search_command_main('^mu$') };
    like($stdout, qr/sbozyp: the following packages match the regex.+office\/mu\n$/s, 'returns matched package');

    ($stdout) = capture { Sbozyp::search_command_main('^MU$') };
    like($stdout, qr/sbozyp: the following packages match the regex.+office\/mu\n$/s, 'case-insensitive by default');

    like(dies { Sbozyp::search_command_main('-c','^MU$') },
         qr/^sbozyp: error: no packages match the regex '\^MU\$'$/,
         q(matches case-sensitive when given '-c' option)
    );

    like(dies { Sbozyp::search_command_main('.+','^MU$') },
         qr/^Usage:/,
         'dies with usage if given multiple args'
    );

    like(dies { Sbozyp::search_command_main('office/mu') },
         qr/^sbozyp.+no packages match the regex/,
         'by default does not match package categories'
    );

    ($stdout) = capture { Sbozyp::search_command_main('-n', 'office/mu') };
    like($stdout, qr/the following packages match the regex.+office\/mu/s, q(matches against PKGNAME instead of just PRGNAM if given '-n' option));

    ($stdout) = capture { Sbozyp::search_command_main('mu') };
    ok(10 < split("\n",$stdout), 'returns all packages that match the regex');
};

subtest 'sync_command_main()' => sub {
    skip_all('sync_command_main() requires root') unless $> == 0;

    my ($stdin,$stdout,$stderr); # were gonna capture STDOUT/STDERR into these variables for some tests

    ($stdout) = capture { Sbozyp::sync_command_main('-h') };
    like($stdout, qr/^Usage.+Sync a local SBo repository.+Options are/s, q('-h' option prints a help string to STDOUT));

    ($stdout) = capture { Sbozyp::sync_command_main('--help') };
    like($stdout, qr/^Usage.+Sync a local SBo repository.+Options are/s, q('--help' can be used instead of '-h'));

    like(dies { Sbozyp::sync_command_main('mu') },
         qr/^Usage:/,
         q(dies with usage if given an argument)
    );

    # test syncing
    system "rm -rf '$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}'" and die;
    mkdir "$Sbozyp::CONFIG{REPO_ROOT}/$Sbozyp::CONFIG{REPO_NAME}" or die;

    (undef, $stderr) = capture { Sbozyp::sync_command_main() };
    like($stderr, qr/Cloning into/i, 'clones git repo if it does not exist');

    ($stdout) = capture { Sbozyp::sync_command_main() };
    like($stdout, qr/HEAD is now at/i, 'git fetch and resets if git repo already exists');
};

done_testing;
