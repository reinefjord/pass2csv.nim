import os, osproc, parseopt, strformat, strutils

type
  GetField = tuple
    name: string
    pattern: string

proc parse(data: string, getFields: seq[GetField]) =
  echo(data)

proc decrypt(gpgBinary: string,
             filename: string): tuple[output: string, exitCode: int] =
  let cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  result = execCmdEx(cmd)

proc main(storePath: string,
          groupingBase: string,
          gpgBinary: string,
          outFile: string,
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
    parse(output, getFields)
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
          let field: GetField = (name: fieldName, pattern: val)
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
