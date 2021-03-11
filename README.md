# pass2csv.nim

This is a rewrite of [pass2csv](https://github.com/reinefjord/pass2csv)
in [Nim](https://nim-lang.org) with a more flexible cli interface and
less messy code.

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
