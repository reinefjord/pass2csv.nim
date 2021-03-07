import os, osproc, parseopt, strformat, strutils

proc parse(data: string) =
  echo(data)

proc decrypt(gpgBinary: string,
             filename: string): tuple[output: TaintedString, exitCode: int] =
  let cmd = &"{gpgBinary} --decrypt --quiet {quoteShell(filename)}"
  let (output, exitCode) = execCmdEx(cmd)
  return (output, exitCode)

proc main(storePath: string,
          groupingBase: string,
          gpgBinary: string,
          outFile: string) =
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
    parse(output)
  echo("Failed to decrypt: ")
  for failed in failures:
    echo(failed)

when isMainModule:
  var storePath: string
  var groupingBase: string
  var gpgBinary = "gpg"
  var outFile = "-"
  var getFields: seq[tuple[name: string, pattern: string]]
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
          let field = (name: fieldName, pattern: val)
          getFields.add(field)
        else:
          echo(&"Unknown argument '{key}'.")
          quit(QuitFailure)
    of cmdEnd:
      assert(false)
  if storePath == "":
    echo("Please provide a path to your password store.")
    quit(1)
  if groupingBase == "":
    groupingBase = storePath
  echo(getFields)
  main(storePath, groupingBase, gpgBinary, outFile)
