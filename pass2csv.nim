import os, osproc, parseopt, re, strformat, strutils, tables

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
        let value = strutils.strip(inverseMatch)
        entry.fields[field.name] = value
        tail.delete(i)
        break
  entry.notes = tail.join("\n").strip()

proc decrypt(gpgBinary, filename: string): tuple[output: string, exitCode: int] =
  let cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  return execCmdEx(cmd)

proc write(outFile: string; entries: seq[EntryData]; getFields: seq[GetField]) =
  var file: File
  if outFile == "-":
    file = stdout
  else:
    file = open(outFile, fmWrite)
  for entry in entries:
    var fields: seq[string]
    for field in getFields:
      fields.add(entry.fields.getOrDefault(field.name))
    var columns = @[entry.group, entry.title, entry.password] & fields & @[entry.notes]
    for i, col in columns:
      if col.contains({',', '\n', '"'}):
        let quotesEscaped = col.replace("\"", "\"\"")
        columns[i] = &"\"{quotesEscaped}\""
    let row = columns.join(",")
    file.writeLine(row)

proc main(storePath, groupingBase, gpgBinary, outFile: string;
          exclude: seq[Regex]; getFields: seq[GetField]) =
  var entries: seq[EntryData]
  var failures: seq[string]
  for path in walkDirRec(storePath, relative = true):
    if path.startsWith(".git"):
      continue
    if not path.endsWith(".gpg"):
      continue
    writeLine(stderr, "Processing " & path)
    let (output, exitCode) = decrypt(gpgBinary, joinPath(storePath, path))
    if exitCode != 0:
      writeLine(stderr, &"{gpgBinary} exited with code {exitCode}:")
      writeLine(stderr, output)
      failures.add(path)
      continue
    var entry: EntryData
    entry.setMeta(joinPath(storePath, path), groupingBase)
    entry.setData(output, exclude, getFields)
    writeLine(stderr, entry)
    entries.add(entry)
  if failures.len() > 0:
    writeLine(stderr, "Failed to decrypt: ")
    for failed in failures:
      writeLine(stderr, failed)
  outFile.write(entries, getFields)

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
        writeLine(stderr, &"Unexpected argument '{key}', only one path can be given.")
        quit(1)
      storePath = key.expandTilde().normalizedPath()
    of cmdLongOption, cmdShortOption:
      case key
      of "gpg", "g":
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
            writeLine(stderr, &"Missing a pattern for field '{fieldName}'.")
            quit(1)
          let pattern = re(val, flags = {reStudy, reIgnoreCase})
          let field = GetField(name: fieldName, pattern: pattern)
          getFields.add(field)
        else:
          writeLine(stderr, &"Unknown argument '{key}'.")
          quit(1)
    of cmdEnd:
      assert(false)
  if storePath == "":
    writeLine(stderr, "Please provide a path to your password store.")
    quit(1)
  if groupingBase == "":
    groupingBase = storePath
  main(storePath, groupingBase, gpgBinary, outFile, exclude, getFields)
