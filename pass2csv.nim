import os, osproc, parseopt, re, strformat, strutils, tables

const helpShort = """
Usage: pass2csv <path> [options]

The path may be a subdirectory in your password-store to only extract passwords
from that subdirectory.

Options:
  -h, --help                       Print a long help message.
  -b:path, --base:path             Path to use as base for grouping passwords.
  -o:filename, --outfile:filename  File to write data to (default: stdout).
  -g:path, --gpg:path              Which gpg binary you wish to use
                                   (default: 'gpg').
  -a, --use-agent                  Asks gpg to connect to an agent. Does
                                   nothing with gpg2 as gpg2 always uses
                                   an agent.
  -e:regexp, --exclude:regexp      Exclude lines containing a regexp match.
  --get-<name>:regexp              Search for regexp and put the rest of the
                                   line in a field named <name>.

Note that arguments to options must be separated by : or =."""

const helpLong = helpShort & "\n\n" & """
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

"""

type
  GetField = object
    name: string
    pattern: Regex

  EntryData = object
    group: string
    title: string
    password: string
    fields: Table[string, string]
    notes: string

proc setMeta(entry: var EntryData; path, groupingBase: string) =
  let relPath = relativePath(path, groupingBase)
  let fileSplit = splitFile(relPath)
  entry.group = fileSplit.dir
  entry.title = fileSplit.name

proc setData(entry: var EntryData; data: string; exclude: seq[Regex];
             getFields: seq[GetField]) =
  let lines = splitLines(data)
  var tail = lines[1 .. ^1]
  entry.password = lines[0]
  for excludePattern in exclude:
    for i, line in tail:
      if match(line, excludePattern):
        tail.delete(i)
        break
  for field in getFields:
    for i, line in tail:
      let match = line.findBounds(field.pattern)
      if match != (-1, 0):
        let inverseMatch = line[0 ..< match[0]] & line[match[1] + 1 .. ^1]
        let value = inverseMatch.strip()
        entry.fields[field.name] = value
        tail.delete(i)
        break
  entry.notes = tail.join("\n").strip()

proc decrypt(gpgBinary, filename: string;
             useAgent: bool): tuple[output: string; exitCode: int] =
  var cmd: string
  if useAgent:
    cmd = &"{gpgBinary} --decrypt --quiet --use-agent {quoteShell(filename)}"
  else:
    cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  return execCmdEx(cmd)

proc fmtCsvRow(columns: seq[string]): string =
  var formatted: seq[string]
  for col in columns:
    if col.contains({',', '\n', '"'}):
      let quotesEscaped = col.replace("\"", "\"\"")
      formatted.add(&"\"{quotesEscaped}\"")
    else:
      formatted.add(col)
  return formatted.join(",")

proc write(outFile: string; entries: seq[EntryData]; getFields: seq[GetField]) =
  var file: File
  if outFile == "-":
    file = stdout
  else:
    file = open(outFile, fmWrite)

  var fieldNames: seq[string]
  for field in getFields:
    fieldNames.add(field.name)
  let header = @["Group(/)", "Title", "Password"] & fieldNames & @["Notes"]
  file.writeLine(fmtCsvRow(header))

  for entry in entries:
    var fields: seq[string]
    for field in getFields:
      fields.add(entry.fields.getOrDefault(field.name))
    var columns = @[entry.group, entry.title, entry.password] & fields & @[entry.notes]
    file.writeLine(fmtCsvRow(columns))

proc main(storePath, groupingBase, outFile, gpgBinary: string; useAgent: bool;
          exclude: seq[Regex]; getFields: seq[GetField]) =
  var entries: seq[EntryData]
  var failures: seq[string]
  for path in walkDirRec(storePath, relative = true):
    if path.startsWith(".git"):
      continue
    if not path.endsWith(".gpg"):
      continue
    stderr.writeLine("Processing " & path)
    let (output, exitCode) = decrypt(gpgBinary, joinPath(storePath, path), useAgent)
    if exitCode != 0:
      stderr.writeLine(&"{gpgBinary} exited with code {exitCode}:")
      stderr.writeLine(output)
      failures.add(path)
      continue
    var entry: EntryData
    entry.setMeta(joinPath(storePath, path), groupingBase)
    entry.setData(output, exclude, getFields)
    entries.add(entry)
  if failures.len() > 0:
    stderr.writeLine("\nFailed to decrypt: ")
    for failed in failures:
      stderr.writeLine(failed)
  outFile.write(entries, getFields)

when isMainModule:
  var
    storePath: string
    groupingBase: string
    gpgBinary = "gpg"
    useAgent = false
    outFile = "-"
    exclude: seq[Regex]
    getFields: seq[GetField]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      if storePath != "":
        stderr.writeLine(&"Unexpected argument '{key}', only one path can be given.")
        quit(1)
      storePath = key.expandTilde().normalizedPath()
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        stderr.write(helpLong)
        quit(0)
      of "gpg", "g":
        gpgBinary = val
      of "use-agent", "a":
        useAgent = true
      of "base", "b":
        groupingBase = val.expandTilde().normalizedPath()
      of "outfile", "o":
        outFile = val
      of "exclude", "e":
        exclude.add(re(val, flags = {reStudy, reIgnoreCase}))
      else:
        if key.startsWith("get-"):
          let fieldName = key[4 .. ^1]
          if val == "":
            stderr.writeLine(&"Missing a pattern for field '{fieldName}'.")
            quit(1)
          let pattern = re(val, flags = {reStudy, reIgnoreCase})
          let field = GetField(name: fieldName, pattern: pattern)
          getFields.add(field)
        else:
          stderr.writeLine(&"Unknown argument '{key}'.")
          quit(1)
    of cmdEnd:
      assert(false)
  if storePath == "":
    stderr.writeLine(helpShort)
    quit(1)
  if groupingBase == "":
    groupingBase = storePath
  main(storePath, groupingBase, outFile, gpgBinary, useAgent, exclude, getFields)
