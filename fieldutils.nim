import std/macros

macro `<-`*(vars, obj: untyped): untyped =
  expectKind(vars, nnkTupleConstr)
  result = newStmtList()
  for v in vars:
    result.add newLetStmt(v, newDotExpr(obj, v))

macro `^`*(T: typedesc, vars: untyped): untyped =
  expectKind(vars, nnkTupleConstr)
  result = newTree(nnkObjConstr, T)
  for v in vars:
    result.add newColonExpr(v, v)
