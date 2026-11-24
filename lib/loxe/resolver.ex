defmodule Loxe.Resolver do
  @moduledoc """
  Checks that a program parsed by `Loxe.Parser` follows the scoping rules
  of Lox. Run it before `Loxe.Interpreter.run/2`.

  `check/1` doesn't change the program. It walks it once, without running
  anything: both branches of an `if` and every loop body are checked, and
  every function body is checked where the function is declared, whether
  or not it is ever called.

  The rules:

    * A local variable, function or parameter can't be declared twice in
      the same scope. A function's parameters and its body's top level are
      one scope. Globals can be redeclared.
    * A local variable can't be read in its own initializer, even from
      inside an anonymous function in that initializer.
    * `break` and `continue` must be inside a loop in the same function,
      and `return` must be inside a function.

  Any name that isn't a local in scope is assumed to be a global, and
  globals aren't tracked. So reading a variable that is never declared,
  or a local that is declared further down, is still a runtime error.
  """

  alias Loxe.Ast
  alias Loxe.Ast.Assign
  alias Loxe.Ast.Binary
  alias Loxe.Ast.Block
  alias Loxe.Ast.Break
  alias Loxe.Ast.Call
  alias Loxe.Ast.Continue
  alias Loxe.Ast.ExprStmt
  alias Loxe.Ast.For
  alias Loxe.Ast.Fun
  alias Loxe.Ast.Grouping
  alias Loxe.Ast.Ident
  alias Loxe.Ast.If
  alias Loxe.Ast.Lambda
  alias Loxe.Ast.Literal
  alias Loxe.Ast.Print
  alias Loxe.Ast.Return
  alias Loxe.Ast.Unary
  alias Loxe.Ast.Var
  alias Loxe.Ast.VarDecl
  alias Loxe.Ast.While
  alias Loxe.Resolver.Error

  @doc """
  Returns `:ok` if `decls` follow the scoping rules, or `{:error, error}`
  with a `Loxe.Resolver.Error` for the first rule broken.

  ## Examples

      iex> {:ok, tokens} = Loxe.Lexer.lex("{ var a = 1; var a = 2; }", 0)
      iex> {:ok, decls} = Loxe.Parser.parse(tokens)
      iex> Loxe.Resolver.check(decls)
      {:error,
       %Loxe.Resolver.Error{
         kind: {:already_declared, "a"},
         span: %Loxe.Span{source_id: 0, start: 17, end: 18}
       }}

  """
  @spec check([Ast.decl()]) :: :ok | {:error, Error.t()}
  def check(decls) do
    resolve_all(decls, [], %{function: :none, loops: 0})
    :ok
  rescue
    error in Error -> {:error, error}
  end

  defp resolve_all(decls, scopes, ctx) do
    Enum.reduce(decls, scopes, &resolve(&1, &2, ctx))
  end

  defp declare([], _ident), do: []

  defp declare([scope | rest], %Ident{name: name, span: span}) do
    if Map.has_key?(scope, name) do
      raise Error, kind: {:already_declared, name}, span: span
    end

    [Map.put(scope, name, :declared) | rest]
  end

  defp define([], _ident), do: []

  defp define([scope | rest], %Ident{name: name}) do
    [Map.put(scope, name, :defined) | rest]
  end

  defp resolve(%VarDecl{} = var, scopes, ctx) do
    scopes = declare(scopes, var.name)
    if var.value, do: resolve_expr(var.value, scopes, ctx)
    define(scopes, var.name)
  end

  defp resolve(%Fun{} = fun, scopes, ctx) do
    scopes = scopes |> declare(fun.name) |> define(fun.name)
    resolve_function(fun, scopes, ctx)
    scopes
  end

  defp resolve(%Block{} = block, scopes, ctx) do
    resolve_all(block.body, [%{} | scopes], ctx)
    scopes
  end

  defp resolve(%Print{} = print, scopes, ctx) do
    resolve_expr(print.expr, scopes, ctx)
    scopes
  end

  defp resolve(%ExprStmt{} = stmt, scopes, ctx) do
    resolve_expr(stmt.expr, scopes, ctx)
    scopes
  end

  defp resolve(%If{} = iff, scopes, ctx) do
    resolve_expr(iff.condition, scopes, ctx)
    resolve(iff.then_branch, scopes, ctx)
    if iff.else_branch, do: resolve(iff.else_branch, scopes, ctx)
    scopes
  end

  defp resolve(%While{} = loop, scopes, ctx) do
    resolve_expr(loop.condition, scopes, ctx)
    resolve(loop.body, scopes, %{ctx | loops: ctx.loops + 1})
    scopes
  end

  defp resolve(%For{} = loop, scopes, ctx) do
    inner = [%{} | scopes]

    inner =
      case loop.init do
        nil -> inner
        %VarDecl{} = decl -> resolve(decl, inner, ctx)
        expr -> resolve_expr(expr, inner, ctx) && inner
      end

    if loop.condition, do: resolve_expr(loop.condition, inner, ctx)
    if loop.update, do: resolve_expr(loop.update, inner, ctx)
    resolve(loop.body, inner, %{ctx | loops: ctx.loops + 1})

    scopes
  end

  defp resolve(%Break{} = break, _scopes, %{loops: 0}) do
    raise Error, kind: {:outside_loop, :break}, span: break.span
  end

  defp resolve(%Break{}, scopes, _ctx), do: scopes

  defp resolve(%Return{} = return, _scopes, %{function: :none}) do
    raise Error, kind: :outside_function, span: return.span
  end

  defp resolve(%Return{} = return, scopes, ctx) do
    if return.expr, do: resolve_expr(return.expr, scopes, ctx)
    scopes
  end

  defp resolve(%Continue{} = continue, _scopes, %{loops: 0}) do
    raise Error, kind: {:outside_loop, :continue}, span: continue.span
  end

  defp resolve(%Continue{}, scopes, _ctx), do: scopes

  # Takes a `Fun` or a `Lambda`.
  defp resolve_function(fun, scopes, ctx) do
    scopes = [%{} | scopes]

    scopes =
      Enum.reduce(fun.params, scopes, fn param, scopes ->
        scopes |> declare(param) |> define(param)
      end)

    ctx = %{ctx | function: :function, loops: 0}
    resolve_all(fun.body.body, scopes, ctx)

    :ok
  end

  defp resolve_expr(expr, scopes, ctx)
  defp resolve_expr(%Literal{}, _scopes, _ctx), do: :ok
  defp resolve_expr(%Grouping{expr: e}, scopes, ctx), do: resolve_expr(e, scopes, ctx)
  defp resolve_expr(%Unary{expr: e}, scopes, ctx), do: resolve_expr(e, scopes, ctx)
  defp resolve_expr(%Assign{value: v}, scopes, ctx), do: resolve_expr(v, scopes, ctx)

  defp resolve_expr(%Binary{} = binary, scopes, ctx) do
    resolve_expr(binary.left, scopes, ctx)
    resolve_expr(binary.right, scopes, ctx)
  end

  defp resolve_expr(%Call{} = call, scopes, ctx) do
    resolve_expr(call.callee, scopes, ctx)
    Enum.each(call.args, &resolve_expr(&1, scopes, ctx))
  end

  defp resolve_expr(%Var{name: name, span: span}, scopes, _ctx) do
    case Enum.find(scopes, &Map.has_key?(&1, name)) do
      %{^name => :declared} -> raise Error, kind: {:own_initializer, name}, span: span
      _ -> :ok
    end
  end

  defp resolve_expr(%Lambda{} = fun, scopes, ctx) do
    resolve_function(fun, scopes, ctx)
  end
end
