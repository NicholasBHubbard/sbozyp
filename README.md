# SBOZYP

sbozyp is a package manager for Slackware's [SlackBuilds.org](https://slackbuilds.org/).

The goal of sbozyp is to strike a balance between working much like a "normal" package manager such as apt or dnf, while still being transparent and manual in a traditional Slackware-like way.

I created sbozyp because I wanted to and do not claim that it is better, worse, or the same compared to its alternatives.

# USER MANUAL

The user manual can be viewed online [here](https://metacpan.org/dist/App-sbozyp/view/bin/sbozyp) or after installation with `$ man sbozyp`.

# FEATURES

* Dependency resolution
* Multiple repository support
* Pure CLI user interface (no ncurses)
* Safe recursive package removal
* Advanced package querying capabilities
* Bash and Zsh completion
* Supports Slackware 15.0, current, and greater
* Zero dependencies on a full Slackware install

# INSTALL / UPGRADE

sbozyp is itself available on SlackBuilds.org as [system/sbozyp](https://slackbuilds.org/repository/15.0/system/sbozyp/). This means that after initially installing sbozyp, it can manage and update itself. Here are the commands to perform the initial installation (on Slackware 15.0):

```
# SLACKWARE_VERSION=15.0
# wget https://slackbuilds.org/slackbuilds/$SLACKWARE_VERSION/system/sbozyp.tar.gz
# tar -xf sbozyp.tar.gz
# cd sbozyp
# wget $(grep DOWNLOAD sbozyp.info | cut -d'"' -f2)
# ./sbozyp.SlackBuild
# installpkg /tmp/sbozyp-*.tgz
```

Once sbozyp is installed, it can be upgraded like any other package:

```
# sbozyp install sbozyp
```

# CONTRIBUTING

Do not hesitate to open an [issue](https://github.com/NicholasBHubbard/sbozyp/issues/new) or [pull request](https://github.com/NicholasBHubbard/sbozyp/pulls)!

Running the test code:

```
$ cpanm --installdeps .    # sbozyp has test dependencies
$ perl t/sbozyp.t
```

Note that the test code only runs on a Slackware system, and many tests require root permissions.
