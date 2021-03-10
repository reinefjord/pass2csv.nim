import os, osproc, parseopt, re, strformat, strutils

type
  GetField = object
    name: string
    pattern: Regex

  EntryData = object
    group: string
    title: string
    password: string
    fields: seq[tuple[fieldName: string, value: string]]
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
        let
          inverseMatch = line[0 ..< match[0]] & line[match[1] + 1 .. ^1]
          value = strutils.strip(inverseMatch)
          fieldMatch = (fieldName: field.name, value: value)
        entry.fields.add(fieldMatch)
        tail.delete(i)
        break
  entry.notes = tail.join("\n")

proc decrypt(gpgBinary, filename: string): tuple[output: string, exitCode: int] =
  let cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  result = execCmdEx(cmd)

proc main(storePath, groupingBase, gpgBinary, outFile: string;
          exclude: seq[Regex]; getFields: seq[GetField]) =
  var failures: seq[string]
  for path in walkDirRec(storePath, relative = true):
    if path.startsWith(".git"):
      continue
    if not path.endsWith(".gpg"):
      continue
    echo("Processing " & path)
    let (output, exitCode) = decrypt(gpgBinary, joinPath(storePath, path))
    if exitCode != 0:
      echo(&"{gpgBinary} exited with code {exitCode}:")
      echo(output)
      failures.add(path)
      continue
    var entry: EntryData
    entry.setMeta(joinPath(storePath, path), groupingBase)
    entry.setData(output, exclude, getFields)
    echo(entry)
  if failures.len() > 0:
    echo("Failed to decrypt: ")
    for failed in failures:
      echo(failed)

when isMainModule:
  var
    storePath: string
    groupingBase: string
    gpgBinary = "gpg"
    outFile = "-"
    exclude: seq[Regex]
    getFields: seq[GetField]
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      if storePath != "":
        echo(&"Unexpected argument '{key}', only one path can be given.")
        quit(1)
      storePath = key.expandTilde().normalizedPath()
    of cmdLongOption, cmdShortOption:
      case key
      of "gpgbinary", "g":
        gpgBinary = val
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
            echo(&"Missing a pattern for field '{fieldName}'.")
            quit(1)
          let pattern = re(val, flags = {reStudy, reIgnoreCase})
          let field = GetField(name: fieldName, pattern: pattern)
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
  main(storePath, groupingBase, gpgBinary, outFile, exclude, getFields)
