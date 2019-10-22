import strscans
import macros


type
  Directive = enum
    dvImport,
    dvArgument,
    dvExpression,
    dvEscape,
    dvComment,
    dvTemplate,
    dvNoop

  DirectiveSuffix = enum
    dsChompNewLine = "-",
    dsChompEmptyLines = "*",
    dsNoop = "!"

  Token = ref object
    directive: Directive
    suffix: DirectiveSuffix
    strVal: string


let
  Symbols: set[char] = {'&', '^', '=', '%', '#', '~'. '!'}
  SuffixSymbols: set[char] = {'-', '*', '!'}



proc peekDirectiveStart(input: string, i: int): bool =
  result = input[i] == '<' and input[i + 1] == '%'

proc peekDirectiveEnd(input: string, i: int): bool =
  result = input[i] == '%' and input[i + 1] == '>'

proc scanText(input: string, start: int, t: Token): bool =
  let maxLen = input.len
  var i = start

  while i < maxLen:
    if maxLen - i >= 2:
      if peekDirectiveStart(input, i):
        break

    i.inc

  result = i - start > 0

  if result:
    t.directive = dvNoop
    t.suffix = dsNoop
    t.strVal = input[start..i-1]

proc scanDirective(input: string, start: int, t: Token): bool =
  proc dvStart(input: string, s: var string, i: int): int =
    if peekDirectiveStart(input, i):
      result = 2
      s = input[i..i+1]

  proc dvEnd(input: string, s: var string, i: int): int =
    if peekDirectiveEnd(input, i):
      result = 2
      s = input[i..i+1]
      elif input[i] in 

macro compile(input: string): untyped =
  var
    start = 0
    tokensIdx = 0
    tokens: array[2, Token]

  proc compileToken(t: Token) =


  proc processTokens =
    let x = process(tokens[0], tokens[1])

    if x == 1:
      tokensIdx = 1

  proc addToken(t: Token) =
    tokens[tokensIdx] = t
    tokensIdx = (tokensIdx + 1) mod 2

    if tokensIdx == 0:
      processTokens()

      if tokensIdx == 0:
        compileToken(tokens[0])

        tokens[0] = tokens[1]
        tokensIdx = 1


  while true:
    if input[start] == '\0':
      break

    if peekDirectiveStart(input, start):
      addToken scanDirective(input, start)
    else:
      addToken scanText(input, start)
