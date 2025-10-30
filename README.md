# SBOZYP

sbozyp is a package manager for Slackware's [SlackBuilds.org](https://slackbuilds.org/).

The goal of sbozyp is to strike a balance between working like a "normal" package manager such as apt or dnf, while still being transparent and manual in a traditional Slackware-like way.

I created sbozyp because I wanted to and do not claim that it is better, worse, or the same compared to its alternatives.

# USER MANUAL

The user manual can be viewed online [here](https://metacpan.org/release/NHUBBARD/App-sbozyp-0.8.0/view/bin/sbozyp), or after installation with `$ man sbozyp`.

# FEATURES

* Dependency resolution
* Multiple repository support
* Pure CLI user interface (no ncurses)
* Safe recursive package removal
* Advanced package querying capabilities
* Requires zero dependencies on a full Slackware install
* Bash and Zsh completion
* Supports Slackware 15.0, current, and greater

# INSTALL / UPGRADE

```
# VERSION=0.8.0
# wget https://cpan.metacpan.org/authors/id/N/NH/NHUBBARD/App-sbozyp-$VERSION.tar.gz
# tar -xf App-sbozyp-$VERSION.tar.gz
# chmod +x App-sbozyp-$VERSION/package/sbozyp.SlackBuild
# App-sbozyp-$VERSION/package/sbozyp.SlackBuild
# upgradepkg --reinstall --install-new /tmp/sbozyp-$VERSION-noarch-1_nbh.tgz
```

Copy the example configuration:
```
# cp /etc/sbozyp/sbozyp.conf.example /etc/sbozyp/sbozyp.conf
```

If you are using slackpkg then you probably don't want it to manage sbozyp:
```
# echo sbozyp >> /etc/slackpkg/blacklist
```

Note that if you remove sbozyp, any SlackBuilds.org repositories in your `$REPO_ROOT` are not automatically removed.

# PRE-1.0 RELEASE

sbozyp is still in pre-1.0 release, meaning I can and will make backwards compatibility breaking changes without updating the major version. Please consult the [Changes](./Changes) file for information about what comes with a new release before updating. There will be a 1.0 release when I think the program is of the highest possible quality and do not foresee a future need to make a backwards compatibility breaking change. At that point sbozyp will be made available on SlackBuilds.org, meaning it will be able to update itself.

# CONTRIBUTING

Do not hesitate to open an [issue](https://github.com/NicholasBHubbard/sbozyp/issues/new) or [pull request](https://github.com/NicholasBHubbard/sbozyp/pulls)!

Running the test code:

```
$ cpanm --installdeps .    # sbozyp has test dependencies
$ perl t/sbozyp.t
```

Note that many tests require root permissions.

Creating a new release:

* Update version in README.md, Changes, bin/sbozyp, and package/sbozyp.SlackBuild
* Update Changes file to reflect new changes
* Perform a CPAN release
