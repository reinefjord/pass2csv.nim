# pass2csv.nim

This is a rewrite of [pass2csv](https://github.com/reinefjord/pass2csv)
in [Nim](https://nim-lang.org) with a more flexible cli interface and
less messy code. The source code is available at
[GitHub](https://github.com/reinefjord/pass2csv.nim).

## Usage

```
$ pass2csv -h
Usage: pass2csv <path> [options]

The path may be a subdirectory in your password-store to only extract passwords
from that subdirectory.

Options:
  -h, --help                       Print a long help message.
  -b:path, --base:path             Path to use as base for grouping passwords.
  -g:path, --gpg:path              Which gpg binary you wish to use
                                   (default: 'gpg').
  -a, --use-agent                  Asks gpg to connect to an agent. Does
                                   nothing with gpg2 as gpg2 always uses
                                   an agent.
  -o:filename, --outfile:filename  File to write data to (default: stdout).
  -e:regexp, --exclude:regexp      Exclude lines containing a regexp match.
  --get-<name>:regexp              Search for regexp and put the rest of the
                                   line in a field named <name>.

Note that arguments to options must be separated by : or =.

The CSV format as you would input it to the KeePass Generic CSV Importer is:
Group(/),Title,Password,[custom fields,...],Notes

The group is relative to the path, or the --base if given.
Given the password: ~/.password-store/site/login/password.gpg
$ pass2csv ~/.password-store/site
    Password will have group "login"
$ pass2csv ~/.password-store/site --base:~/.password-store
    Password will have group "site/login"

The --get-<name> option will search for lines with a match for the provided
regexp, remove the match from the line and strip the resulting line from
leading and trailing whitespace. Only the first match will be added, other
matches will be added to the notes field.

Lines matching --exclude will not be considered for custom fields.

You may specify --get- and --exclude multiple times.
Regexps are case-insensitive.

All other lines will be put in the "notes" field. The notes field is stripped
from leading and trailing whitespace.

Example:
* Password entry (~/.password-store/sites/example/login.gpg):
password123
---
username: user_name
email user@example.com
url:example.com
Some note

* Command
pass2csv ~/.password-store \
  --exclude:'^---$' \
  --get-Username:'(username|email):?' \
  --get-URL:'url:?'

* Output
Group(/),Title,Password,Username,URL,Notes
sites/example,login,password123,user_name,example.com,email user@example.com\nSome note
```


## gpg-agent password timeout

If your private key is protected by a password, `gpg` will ask for it
with the `pinentry` program if you haven't set it to something else. If
using `gpg2` or the `-a` option with `gpg`, by default, the password is
cached for 10 minutes but the timer is reset when using a key. After 2
hours the cache will be cleared even if it has been accessed recently.

You can set these values in your `~/.gnupg/gpg-agent.conf`:

```
default-cache-ttl 600
max-cache-ttl 7200
```
