import tables


type
  IOList* = ref object
    base: string
    next: IOList

  Ends*[T] = tuple
    head: T
    tail: T

  IOMap* = ref object
    name*: string
    list: IOList
    next: IOMap


const DEFAULT_MAP_NAME* = "default"


proc emptyIOList*(): IOList = nil

iterator items*(list: IOList): string =
  var l = list
  while not l.isNil:
    yield l.base
    l = l.next

proc emptyIOMap*(): IOMap = nil

iterator items*(map: IOMap): string =
  var m = map
  while not m.isNil:
    for s in m.list: yield s
    m = m.next

iterator pairs*(map: IOMap): tuple[name: string, list: IOList] =
  var m = map
  while not m.isNil:
    yield (m.name, m.list)
    m = m.next

proc `$`*(map: IOMap): string =
  result = ""
  for s in map: result = result & s

proc len*(map: IOMap): int =
  for name, _ in map: result.inc

proc `->`*(head: IOList, s: string): Ends[IOList] =
  var tail = IOList(base: s)
  tail.base.shallow()

  if head.isNil:
    result = (tail, tail)
  else:
    head.next = tail
    result = (head, tail)

proc `->`*(list: Ends[IOList], s: string): Ends[IOList] =
  if list.head.isNil:
    list.tail -> s
  else:
    (list.head, (list.tail -> s).tail)

proc `->`*(head: IOMap, t: tuple[name: string, list: IOList]): Ends[IOMap] =
  var tail = IOMap(name: t.name, list: t.list)

  if head.isNil:
    result = (tail, tail)
  else:
    head.next = tail
    result = (head, tail)

# TODO: Adding a list onto an existing list. E.g. when a template call a proc
# (another template) that returns an IOMap.
# proc `->`*(list: IOList, map: IOMap): IOList =
#   Mmmh, this does not seem so straight forward after all! May just have the called
#   template return a string for now?

proc `->`*(map: Ends[IOMap], t: tuple[name: string, list: IOList]): Ends[IOMap] =
  if map.head.isNil:
    map.tail -> t
  else:
    (map.head, (map.tail -> t).tail)

proc `~>`*(head: IOList, s: string): Ends[IOList] =
  var tail = IOList()

  tail.base.shallowCopy(s)
  tail.base.shallow()

  if head.isNil:
    result = (tail, tail)
  else:
    head.next = tail
    result = (head, tail)

proc `~>`*(list: Ends[IOList], s: string): Ends[IOList] =
  if list.head.isNil:
    list.tail ~> s
  else:
    (list.head, (list.tail ~> s).tail)

proc `|>`*(child, parent: IOMap): IOMap =
  var
    t: Table[string, IOList]
    ends: Ends[IOMap] = (emptyIOMap(), emptyIOMap())

  for name, list in child:
    t[name] = list

  for name, list in parent:
    ends = ends -> (name, if t.hasKey(name): t[name] else: list)

  return ends.head
