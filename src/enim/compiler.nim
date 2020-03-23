import macros
import strutils, strscans, strformat
import sequtils

import ./iomap


type
  TokenKind = enum
    tkCmd
    tkCmdStart
    tkCmdBody
    tkCmdEnd
    tkText

  CmdDirective = enum
    dvEvaluation,
    dvExpression,
    dvComment,
    dvGrammar

  Token = ref object
    indentation: string
    text: string
    case kind: TokenKind
    of tkCmd, tkCmdStart, tkCmdBody, tkCmdEnd:
      directive: CmdDirective
      newline: bool
      chompNewline: bool
    else:
      nil

  EnimError = object of Exception
  UnknownDirectiveError = object of EnimError
  MultipleDirectivesError = object of EnimError
  UnclosedTagError = object of EnimError
  EmptyCommandError = object of EnimError

const
  Indentation: set[char] = {' ', '\t'}
  DirectiveSymbols: set[char] = {'=', '#', '@'}



proc dup(t: Token): Token =
  result = Token(
    kind: t.kind,
    indentation: t.indentation,
    text: t.text
  )

  if result.kind != tkText:
    result.directive = t.directive
    result.newline = t.newline
    result.chompNewline = t.chompNewline

proc copy(a, b: Token) =
  a.kind = b.kind
  a.indentation = b.indentation
  a.text = b.text

  if b.kind != tkText:
    a.directive = b.directive
    a.newline = b.newline
    a.chompNewline = b.chompNewline

proc isBlockScope(t: Token): bool =
  t.text[t.text.len - 1] == ':'

proc isBlockEnd(t: Token): bool =
  t.text == "end"

proc `$`(t: Token): string =
  if t.isNil:
    "Nil"
  elif t.kind == tkText:
    $t.kind & ":" & t.indentation & " - " & t.text & "|"
  else:
    $t.kind & "(" & $t.directive & "):" & t.indentation & " - " & t.text &
    "[" & $t.newline & ", " & $t.chompNewline & "]"

proc `&`(a, b: Token): bool =
  if b.isNil: return

  # TODO: This might not go through if the comment is token `a`!
  if b.kind == tkCmd:
    if b.directive == dvComment:
      if b.newline:
        b.text = if b.chompNewline: "" else: "\n"

        # If the comment is the lone item on the line, drop the indentation so
        # that it does not affect the following token.
        if b.indentation.len > 0: b.indentation = ""
        b.kind = tkText
      else:
        b.text = ""
        b.kind = tkText

  if a.kind in [tkCmdStart, tkCmdBody]:
    if a.directive == dvEvaluation:
      if isBlockScope(b):
        if not isBlockScope(a): b.indentation = a.indentation
    elif a.directive == dvComment:
      a.copy(b)
      return true

  if a.kind == tkCmdEnd:
    if a.newline and not a.chompNewline:
      if b.kind == tkText:
        a.newline = false
        a.chompNewline = false
        b.text = "\n" & b.indentation & b.text
        b.indentation = ""

        if a.directive == dvComment:
          a.copy(b)
          return true
    elif a.directive == dvComment:
      a.copy(b)
      return true

  if a.kind == tkText:
    case b.kind
    of tkCmd, tkCmdStart:
      if b.indentation.len > 0 and
        (b.directive == dvExpression or b.directive == dvGrammar):
        a.text = a.text & b.indentation
        b.indentation = ""

    of tkCmdEnd:
      discard

    of tkText:
      a.text = a.text & b.indentation & b.text
      return true
    else:
      discard

proc parseGrammar(t: Token): tuple[cmd: string, args: seq[string]] =
  assert t.kind == tkCmd and t.directive == dvGrammar

  let args = t.text.split({' ', '"', ':'}).filter(proc (s: string): bool =
    s.len > 0)

  (args[0], args[1..args.len-1])

proc parseIndentation(input: string, i: var int): int =
  let start = i

  # This should really just be looking at `space` here, not tabs.
  discard scanp(input, i, +`Indentation`)
  return i - start

proc parseText(input: string, i: var int, t: Token): int =
  let start = i
  var j = 0

  while i < input.len:
    j = i

    if scanp(input, j, "<%"):
      if scanp(input, j, '%'):
        i = j
      else:
        break
    else:
      i.inc

  if i > start:
    t.kind = tkText
    t.text = input[start..i-1]
    t.indentation = ""

  return i - start

proc parseCommand(input: string, i: var int, t: Token): int =
  let start = i
  var directive = ""

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

  proc doChompNewline = (t.chompNewline = true)

  proc parseCommandText(s: string, start: int, txt: var string): int =
    var
      i = start

    while i < s.len:
      var j = i
      if scanp(s, j, +`Indentation`, ?'-', "%>"):
        if j == start:
          raise newException(
            EmptyCommandError,
            "Command can not be empty!"
          )
        else:
          break
      else:
        j = i
        if scanp(s, j, '\L'):
          break
        else:
          i.inc

    result = i - start
    txt = s[start..i-1]

  if scanp(input, i, "<%"):
    t.kind = tkCmd
    t.newline = false
    t.chompNewline = false

    if scanp(input, i,
             *(~`Indentation` -> addDirective($_)),
             +`Indentation`):

      if directive.len > 0:
        t.directive =
          case directive[0]
          of '=': dvExpression
          of '#': dvComment
          else: dvGrammar
      else:
        t.directive = dvEvaluation

      if scanp(input, i,
               parseCommandText($input, $index, t.text),
               +`Indentation`,
               ?('-' -> doChompNewline()),
               "%>"):
        if scanp(input, i, '\L'):
          t.newline = true

        if t.directive == dvEvaluation and t.text == "end":
          t.kind = tkCmdEnd
      else:
        t.kind = tkCmdStart

        if scanp(input, i, '\L'):
          t.newline = true
    else:
      raise newException(
        EnimError,
        fmt"Directive could not be parsed: '{input.substr(i-2)}'"
      )

  result = i - start

proc parseCommandBody(input: string, i: var int, t: Token): int =
  let start = i
  var
    cmdEnd = false
    j = 0

  proc doChompNewline = (t.chompNewline = true)

  t.kind = tkCmdBody
  t.newline = false
  t.chompNewline = false

  while i < input.len:
    j = i

    if scanp(input, j, +`Indentation`, ?('-' -> doChompNewline()), "%>"):
      cmdEnd = true
      break
    else:
      j = i

      if scanp(input, j, '\L'):
        break
      else:
        i.inc

  if i > start:
    t.text = input[start..i-1]
    t.indentation = ""
    t.newline = false

    if cmdEnd:
      t.kind = tkCmdEnd
      i = j

    if scanp(input, i, '\L'):
      t.newLine = true

  return i - start

iterator parse(input: string): Token =
  var
    a, b, token, lastToken: Token
    i: int

    t = Token()
    indentation = ""
    parsed = false

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

  proc peepLastToken(): Token =
    if b.isNil: a else: b

    
  for line in splitLines(input, true):
    i = 0

    if parseIndentation(line, i) > 0:
      indentation = line[0..i-1]

    while i < line.len:
      lastToken = peepLastToken()

      if not lastToken.isNil and
        (lastToken.kind == tkCmdStart or
         lastToken.kind == tkCmdBody):
        parsed = parseCommandBody(line, i, t) > 0

        if parsed:
          t.directive = lastToken.directive
      else:
        parsed = parseText(line, i, t) > 0 or parseCommand(line, i, t) > 0

      if parsed:
        token = t.dup()
        token.indentation = indentation

        if not queueToken(token):
          if not processTokenQueue(): yield popTokenQueue()
          assert queueToken(token)

      indentation = ""

  discard processTokenQueue()

  token = popTokenQueue()
  while not token.isNil:
    yield token
    token = popTokenQueue()

when debug:
  macro compileDebug(input: string): untyped =
    for token in parse(input.strVal):
      echo token

macro compile*(input: string): untyped =
  var
    name, someVar: NimNode

    scope: seq[Token] = @[]
    vars = "var\n"
    cachedVars = "let\n"
    contentBlock = false
    body = ""
    val = ""
    n = 0

    list = genSym(nskVar, "list")
    map = genSym(nskVar, "map")


  proc addToBody(line: string) =
    let indentation = scope.len * 2
    body = body & indent(line, indentation) & "\n"

  proc startNewIOList(name: string = "") =
    addToBody fmt"""
{map.repr} = {map.repr} -> (name, {list.repr}.head)
name = "{name}"
{list.repr} = (emptyIOList(), emptyIOList())
"""

  proc addScope(t: Token) =
    if scope.len == 0:
      scope.add(t)
    else:
      let t0 = scope[scope.len - 1]
      if t.indentation.len > t0.indentation.len:
        scope.add(t)

  proc popScope =
    let t = scope.pop()

    if t.kind == tkCmd and t.directive == dvGrammar:
     if t.text[0..6] == "content":
       startNewIOList()

  proc endBlock =
    if contentBlock:
      contentBlock = false
      startNewIOList()
    else:
      popScope()

  proc varIndentation: int =
    var i = scope.len - 1
    if i < 0: return 0

    while i >= 0 and scope[i].kind in [tkCmdStart, tkCmdBody]:
      result.inc(2)
      i.dec


  vars = vars & fmt"""
  {map.repr}: Ends[IOMap] = (emptyIOMap(), emptyIOMap())
  {list.repr}: Ends[IOList] = (emptyIOList(), emptyIOList())
  name = ""
  """

  for token in parse(input.strVal):
    case token.kind
    of tkCmd:
      case token.directive
      of dvEvaluation:
        if token.newline and not token.chompNewline:
          addToBody fmt"{list.repr} = {list.repr} -> " & "\"\\n\""

        addToBody(token.text)
        if isBlockScope(token): addScope(token)

      of dvExpression:
        if token.indentation.len > 0:
          addToBody(
            fmt"{list.repr} = {list.repr} -> " &
            "\"" & token.indentation & "\" & " & token.text &
            (if token.newline and not token.chompNewline: " & \"\\n\"" else: "")
          )
        else:
          addToBody(
            fmt"{list.repr} = {list.repr} -> {token.text}" &
            (if token.newline and not token.chompNewline: " & \"\\n\"" else: "")
          )

      of dvComment:
        if token.newline and not token.chompNewline:
          addToBody fmt"{list.repr} = {list.repr} -> " & "\"\\n\""

      of dvGrammar:
        var grammar = token.parseGrammar()
        case grammar.cmd
        of "content":
          startNewIOList(grammar.args[0])
          contentBlock = true
        of "yield":
          startNewIOList(DEFAULT_MAP_NAME)
          startNewIOList()
        else:
          discard

    of tkCmdStart:
      case token.directive
      of dvEvaluation:
        addToBody(token.text)
        if isBlockScope(token): addScope(token)
      of dvExpression:
        someVar = genSym(nskVar, "s")
        val = token.text
        vars = vars & "\n" & fmt"  {someVar.repr} = {val}"

        # Block scope is for the variable definition rather than the proc body.
        if isBlockScope(token): addScope(token)
      of dvComment, dvGrammar:
        discard

    of tkCmdBody:
      case token.directive
      of dvEvaluation:
        addToBody(token.text)
        if isBlockScope(token): addScope(token)
      of dvExpression:
        # This goes to the variable definition that has already begun rather than
        # the proc body.
        vars = vars & "\n" & indent(fmt"  {token.text}", varIndentation())
        if isBlockScope(token): addScope(token)
      of dvComment, dvGrammar:
        discard

    of tkCmdEnd:
      case token.directive
      of dvEvaluation:
        if isBlockEnd(token):
          endBlock()
        else:
          addToBody(token.text)
          if isBlockScope(token): addScope(token)

        if token.newline and not token.chompNewline:
          addToBody fmt"{list.repr} = {list.repr} -> " & "\"\\n\""
      of dvExpression:
        let indentation = varIndentation()

        vars = vars & "\n" & indent(fmt"  {token.text}", indentation)
        if indentation > 0: endBlock()

        addToBody(
          fmt"{list.repr} = {list.repr} -> {someVar.repr}" &
          (if token.newline and not token.chompNewline: " & \"\\n\"" else: "")
        )
      of dvComment:
        if token.newline and not token.chompNewline:
          addToBody fmt"{list.repr} = {list.repr} -> " & "\"\\n\""
      of dvGrammar:
        discard

    of tkText:
      name = genSym(nskLet, "s")
      val = token.indentation & token.text

      cachedVars = cachedVars & "  " & (
        quote do:
          `name` {.global.} = `val`
      ).repr & "\n"

      addToBody fmt"{list.repr} = {list.repr} ~> {name.repr}"

  val = "l" & $n
  body = body & (
    quote do:
      `map` = `map` -> (`val`, `list`.head)
      if `map`.head.len == 1: `map`.head.name = DEFAULT_MAP_NAME
      `map`.head
  ).repr

  result = parseStmt(cachedVars & "\n" & vars & "\n" & body)

macro compileFile*(path: string): untyped =
  newCall("compile", newStrLitNode(staticRead(path.strVal)))


when isMainModule:
  type
    User = object
      id: int
      name: string

  proc footer(): string =
    "&copy; 2019 - All data rights reserved."
  proc hello(): string =
    "<p class=\"greeting\">Hello world!</p>"

  template funFormat(body: typed): auto =
    block:
      body
      "--- Fun formart: ---"

  proc isActivated(u: User): bool = true
  proc recentlyActive(u: User): bool = true
  proc isAdmin(u: User): bool = u.id > 50

  proc csrf_meta_tags: string =
    "<meta name=\"csrf\" content=\"219031j20dnshdasud8webfsdhfsdkfj\">"
  proc csp_meta_tag: string =
    "<meta name=\"csp-nonce\" content=\"1290dfjd7u4ASDNJK98r3403_\">"
  proc stylesheet_link_tag(name: string, reload: bool): string =
    "<link href=\"/assets/" & name & ".css\" media=\"screen\" rel=\"stylesheet\" />"
  proc javascript_include_tag(name: string, reload: bool): string =
    "<script src=\"/assets/" & name & ".debug-1284139606.js\"></script>"

  proc layout: IOMap =
    compileFile("../../tmp/sample3.enim")

  proc usersIndex(users: seq[User]): IOMap =
    compileFile("../../tmp/sample1.enim")

  proc userProfile(user: User): IOMap =
    compileFile("../../tmp/sample2.enim")

  var
    users: seq[User] = @[
      User(id: 19, name: "Ali"),
      User(id: 37, name: "Bruno"),
      User(id: 56, name: "Bruna"),
      User(id: 108, name: "Aloyce")
    ]

  echo "======================= Sample 1 ======================="
  echo usersIndex(users)

  echo "======================= Sample 2 ======================="
  echo userProfile(users[2])

  echo "================== Sample 2 with layout ================"
  echo userProfile(users[3]) |> layout()
