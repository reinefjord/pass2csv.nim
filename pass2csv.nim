import os, osproc, parseopt, strformat, strutils, unicode

type
  GetField = object
    name: string
    pattern: string

  EntryData = object
    group: string
    title: string
    password: string
    fields: seq[tuple[fieldName: string, value: string]]
    notes: string

proc setMeta(entry: var EntryData; groupingBase, path: string) =
  discard

proc setData(entry: var EntryData, data: string, getFields: seq[GetField]) =
  let lines = splitLines(data)
  var tail = lines[1 .. ^1]
  entry.password = lines[0]
  for field in getFields:
    for i, line in tail:
      if line.toLower().startsWith(field.pattern.toLower()):
        let
          value = strutils.strip(line.split(':', 1)[1])
          fieldMatch = (fieldName: field.name, value: value)
        entry.fields.add(fieldMatch)
        tail.delete(i)
        break
  entry.notes = tail.join("\n")

proc decrypt(gpgBinary, filename: string): tuple[output: string, exitCode: int] =
  let cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  result = execCmdEx(cmd)

proc main(storePath, groupingBase, gpgBinary, outFile: string,
          getFields: seq[GetField]) =
  var failures: seq[string]
  for path in walkDirRec(storePath, relative = true):
    if path.startsWith(".git"):
      continue
    if not path.endsWith(".gpg"):
      continue
    echo("Processing " & path)
    let (output, exitCode) = decrypt(gpgBinary, storePath & path)
    if exitCode != 0:
      echo(&"{gpgBinary} exited with code {exitCode}:")
      echo(output)
      failures.add(path)
      continue
    var entry: EntryData
    entry.setData(output, getFields)
    echo(entry)
  echo("Failed to decrypt: ")
  for failed in failures:
    echo(failed)

when isMainModule:
  var
    storePath: string
    groupingBase: string
    gpgBinary = "gpg"
    outFile = "-"
    getFields: seq[GetField]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      storePath = key
    of cmdLongOption, cmdShortOption:
      case key
      of "gpgbinary", "g":
        gpgBinary = val
      of "base", "b":
        groupingBase = val
      of "outfile", "o":
        outFile = val
      else:
        if key.startsWith("get-"):
          let fieldName = key[4 .. ^1]
          if val == "":
            echo(&"Missing a pattern for field '{fieldName}'.")
            quit(1)
          let field = GetField(name: fieldName, pattern: val)
          getFields.add(field)
        else:
          echo(&"Unknown argument '{key}'.")
          quit(1)
    of cmdEnd:
      assert(false)
  if storePath == "":
    echo("Please provide a path to your password store.")
    quit(1)
  if groupingBase == "":
    groupingBase = storePath
  main(storePath, groupingBase, gpgBinary, outFile, getFields)
