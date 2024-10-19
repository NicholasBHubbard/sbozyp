# SBOZYP

sbozyp is a package manager for Slackware's [SlackBuilds.org](https://slackbuilds.org/).

I created sbozyp because I wanted to and do not claim that it is better, worse, or the same compared to its alternatives.

# USER MANUAL

The user manual can be viewed online [here](./sbozyp.pod), or after install with `$ man sbozyp`.

# FEATURES

* Built in dependency resolution
* Multiple repository support
* Pure CLI user interface (no ncurses)
* Package browsing, searching, and querying
* Requires zero dependencies on a full Slackware install
* Supports Slackware 15.0 and greater

# INSTALLATION

```
# LATEST_VERSION=0.0.1
# wget https://github.com/NicholasBHubbard/sbozyp/archive/refs/tags/sbozyp-$LATEST_VERSION.tar.gz
# mkdir sbozyp
# tar -xf sbozyp-$LATEST_VERSION.tar.gz -C sbozyp --strip-components=1
# chmod +x sbozyp/sbozyp.SlackBuild
# sbozyp/sbozyp.SlackBuild
# upgradepkg --reinstall --install-new /tmp/sbozyp-$LATEST_VERSION-noarch-1_nbh.tgz
# cp /etc/sbozyp/sbozyp.conf.example /etc/sbozyp/sbozyp.conf
# rm -rf sbozyp*
```

# DEVELOPERS

Do not hesitate to open an [issue](https://github.com/NicholasBHubbard/sbozyp/issues/new) or [pull request](https://github.com/NicholasBHubbard/sbozyp/compare)!

Run the test code:

```
$ cpanm --installdeps
$ perl t/sbozyp.t
```

New release:

* Update version in README.md, bin/sbozyp, and sbozyp.SlackBuild
* Update Changes file
* In case the manual was updated: `$ cp bin/sbozyp sbozyp.pod`
* Perform a GitHub release
