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
$ su -
# wget
# chmod +x 
# upgradepkg --reinstall --install-new
```

# AUTHORS

Do not hesitate to open an issue!

Run the test code:

```
$ cpanm --installdeps
$ perl t/sbozyp.t
```

New release:

* Update version in bin/sbozyp and Makefile.PL
* Update Changes file
* In case the manual was updated: `cp bin/sbozyp sbozyp.pod`
* Perform a GitHub release
```
