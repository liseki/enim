import macros
import strutils, strscans, strformat


type
  Directive = enum
    dvEvaluation,
    dvExpression,
    dvEscape,
    dvComment,
    dvGrammar,
    dvIndentation,
    dvNoop

  Token = ref object
    directive: Directive
    text: string

  EnimError = object of Exception
  UnknownDirectiveError = object of EnimError
  MultipleDirectivesError = object of EnimError
  UnclosedTagError = object of EnimError
  EmptyCommandError = object of EnimError

const
  DirectiveSymbols: set[char] = {'=', '%', '#', '@', '!'}



proc dup(t: Token): Token =
  Token(directive: t.directive, text: t.text)

proc `$`(t: Token): string =
  if t.isNil:
    "Nil"
  else:
    $t.directive & ": " & t.text

proc `&`(a, b: Token): bool =
  if a.isNil or
     b.isNil or
     not (a.directive == dvNoop) or
     not (b.directive == dvNoop):
    return false

  a.text = a.text & b.text
  result = true

proc parseCommand(input: string, i: var int, t: Token): int =
  let start = i
  var
    directive = ""
    chompNewline = false

  proc addDirective(c: char) =
    if c in DirectiveSymbols:
      if directive.len > 0:
        raise newException(
          MultipleDirectivesError,
          fmt"Multiple directives not allowed: '{directive}{c}'"
        )
      else:
        directive.add(c)
    else:
      raise newException(
        UnknownDirectiveError,
        fmt"Unknown directive: '{c}'"
      )

  proc doChompNewline() =
    chompNewline = true

  proc parseCommandText(s: string, start: int, txt: var string): int =
    var
      i = start

    while i < s.len:
      var j = i
      if scanp(s, j, +`Whitespace`, ?'-', "%>"):
        if result == 0:
          raise newException(
            EmptyCommandError,
            "Command can not be empty!"
          )
        else:
          break
      else:
        i.inc
        result.inc

    if i == s.len:
      raise newException(
        UnclosedTagError,
        fmt"Input end with unclosed command tag: {s}"
      )

    result = i - start
    txt = s[start..i-1]

  if scanp(input, i, "<%"):
    try:
      if scanp(input, i,
               *(~`Whitespace` -> addDirective($_)),
               +`Whitespace`,
               parseCommandText($input, $index, t.text),
               +`Whitespace`,
               ?('-' -> doChompNewline()),
               "%>"):
        if directive.len > 0:
          t.directive = case directive[0]
            of '=': dvExpression
            of '%': dvEscape
            of '#': dvComment
            of '@': dvGrammar
            else: dvNoop
        else:
          t.directive = dvEvaluation

        if chompNewline and input[i] == '\n':
          i.inc
      else:
        echo "Directive end not found!"
        discard
      discard #echo "This is not a directive!"
    except UnclosedTagError as e:
      i = start
      raise e

  result = i - start

proc parseText(input: string, i: var int, t: Token): int =
  let start = i

  while i < input.len:
    if input[i] == '<' and input[i + 1] == '%':
      break
    else:
      i.inc

  if i > start:
    t.directive = dvNoop
    t.text = input[start..i-1]

  return i - start

iterator parse(input: string): Token =
  var
    t = Token()
    a, b, token: Token
    buffer: string
    i: int

  proc queueToken(t: Token): bool =
    result = true

    if a.isNil:
      a = t
    elif b.isNil:
      b = t
    else:
      result = false

  proc processTokenQueue(): bool =
    if a & b:
      b = nil
      result = true

  proc popTokenQueue(): Token =
    result = a
    a = b
    b = nil

    
  for line in splitLines(input, true):
    if i < buffer.len:
      buffer = buffer & line
    else:
      buffer = line
      i = 0

    while i < buffer.len:
      try:
        if parseText(buffer, i, t) > 0 or parseCommand(buffer, i, t) > 0:
          token = t.dup()

          if not queueToken(token):
            if not processTokenQueue(): yield popTokenQueue()
            assert queueToken(token)
        else:
          break
      except UnclosedTagError:
        break

  discard processTokenQueue()

  token = popTokenQueue()
  while not token.isNil:
    yield token
    token = popTokenQueue()

  if i < buffer.len:
    raise newException(
      UnclosedTagError,
      fmt"Input end with unclosed command tag: {buffer.substr(i)}"
    )

macro compile(input: string): untyped =
  var code = ""

  for token in parse(input.strVal):
    echo "> ", $token.directive, ": ", token.text
    # case token.directive
    # of dvEvaluation:
    # of dvExpression:
    # of dvEscape:
    # of dvComment:
    #   discard
    # of dvGrammar:
    # of dvNoop:

macro compileFile(path: string): untyped =
  newCall("compile", newStrLitNode(staticRead(path.strVal)))


when isMainModule:
  compileFile("../../tmp/sample2.enim")
