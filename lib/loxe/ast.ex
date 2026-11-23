defmodule Loxe.Ast do
  @moduledoc """
  The syntax tree produced by `Loxe.Parser`.

  Every node has a `span` with its location in the source.
  """

  alias __MODULE__.{
    Assign,
    Binary,
    Block,
    Break,
    Call,
    Class,
    Continue,
    ExprStmt,
    For,
    Fun,
    Get,
    Grouping,
    If,
    Lambda,
    Literal,
    Print,
    Return,
    Set,
    Super,
    This,
    Unary,
    Var,
    VarDecl,
    While
  }

  alias Loxe.Span

  @type expr ::
          Literal.t()
          | Grouping.t()
          | Var.t()
          | Lambda.t()
          | This.t()
          | Super.t()
          | Unary.t()
          | Binary.t()
          | Call.t()
          | Get.t()
          | Set.t()
          | Assign.t()

  @type stmt ::
          ExprStmt.t()
          | Print.t()
          | Return.t()
          | Break.t()
          | Continue.t()
          | If.t()
          | While.t()
          | For.t()
          | Block.t()

  @type decl :: VarDecl.t() | Fun.t() | Class.t() | stmt()

  @type binary_op ::
          :or | :and | :eq | :ne | :gt | :ge | :lt | :le | :add | :sub | :mul | :div

  @type unary_op :: :not | :neg

  defmodule Ident do
    @moduledoc """
    A name that isn't a variable reference: a declared name, a parameter or
    the `b` in `a.b`.
    """

    @enforce_keys [:name, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{name: String.t(), span: Span.t()}
  end

  # Expressions

  defmodule Literal do
    @moduledoc """
    A number, string, boolean or `nil` literal. Numbers are always floats.
    """

    @enforce_keys [:value, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{value: nil | boolean() | float() | String.t(), span: Span.t()}
  end

  defmodule Grouping do
    @moduledoc """
    A parenthesized expression, such as `(a + b)`. `span` includes the
    parentheses.
    """

    @enforce_keys [:expr, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{expr: Loxe.Ast.expr(), span: Span.t()}
  end

  defmodule Var do
    @moduledoc """
    A variable reference, such as `x`.
    """

    @enforce_keys [:name, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{name: String.t(), span: Span.t()}
  end

  defmodule Lambda do
    @moduledoc """
    An anonymous function, such as `fun (a) { return a; }`.
    """

    alias Loxe.Ast.{Block, Ident}

    @enforce_keys [:params, :body, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{params: [Ident.t()], body: Block.t(), span: Span.t()}
  end

  defmodule This do
    @moduledoc """
    The `this` keyword.
    """

    @enforce_keys [:span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{span: Span.t()}
  end

  defmodule Super do
    @moduledoc """
    A superclass method access, such as `super.init`.
    """

    alias Loxe.Ast.Ident

    @enforce_keys [:method, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{method: Ident.t(), span: Span.t()}
  end

  defmodule Unary do
    @moduledoc """
    A prefix operator, such as `-x`. `op` is `:not` for `!` and `:neg` for
    `-`.
    """

    @enforce_keys [:op, :expr, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{op: Loxe.Ast.unary_op(), expr: Loxe.Ast.expr(), span: Span.t()}
  end

  defmodule Binary do
    @moduledoc """
    An infix operator, such as `a + b` or `a and b`.
    """

    @enforce_keys [:op, :left, :right, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            op: Loxe.Ast.binary_op(),
            left: Loxe.Ast.expr(),
            right: Loxe.Ast.expr(),
            span: Span.t()
          }
  end

  defmodule Call do
    @moduledoc """
    A call, such as `f(a, b)`.
    """

    @enforce_keys [:callee, :args, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{callee: Loxe.Ast.expr(), args: [Loxe.Ast.expr()], span: Span.t()}
  end

  defmodule Get do
    @moduledoc """
    A property access, such as `a.b`.
    """

    alias Loxe.Ast.Ident

    @enforce_keys [:object, :name, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{object: Loxe.Ast.expr(), name: Ident.t(), span: Span.t()}
  end

  defmodule Set do
    @moduledoc """
    An assignment to a property, such as `a.b = 1`.
    """

    alias Loxe.Ast.Ident

    @enforce_keys [:object, :name, :value, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            object: Loxe.Ast.expr(),
            name: Ident.t(),
            value: Loxe.Ast.expr(),
            span: Span.t()
          }
  end

  defmodule Assign do
    @moduledoc """
    An assignment to a variable, such as `a = 1`.
    """

    @enforce_keys [:name, :value, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{name: String.t(), value: Loxe.Ast.expr(), span: Span.t()}
  end

  # Statements

  defmodule ExprStmt do
    @moduledoc """
    An expression followed by `;`. `span` includes the `;`.
    """

    @enforce_keys [:expr, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{expr: Loxe.Ast.expr(), span: Span.t()}
  end

  defmodule Print do
    @moduledoc """
    A `print` statement.
    """

    @enforce_keys [:expr, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{expr: Loxe.Ast.expr(), span: Span.t()}
  end

  defmodule Return do
    @moduledoc """
    A `return` statement. `expr` is `nil` for a bare `return;`.
    """

    @enforce_keys [:expr, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{expr: Loxe.Ast.expr() | nil, span: Span.t()}
  end

  defmodule Break do
    @moduledoc """
    A `break` statement.
    """

    @enforce_keys [:span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{span: Span.t()}
  end

  defmodule Continue do
    @moduledoc """
    A `continue` statement.
    """

    @enforce_keys [:span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{span: Span.t()}
  end

  defmodule If do
    @moduledoc """
    An `if` statement. `else_branch` is `nil` when there is no `else`.
    """

    @enforce_keys [:condition, :then_branch, :else_branch, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            condition: Loxe.Ast.expr(),
            then_branch: Loxe.Ast.stmt(),
            else_branch: Loxe.Ast.stmt() | nil,
            span: Span.t()
          }
  end

  defmodule While do
    @moduledoc """
    A `while` loop.
    """

    @enforce_keys [:condition, :body, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{condition: Loxe.Ast.expr(), body: Loxe.Ast.stmt(), span: Span.t()}
  end

  defmodule For do
    @moduledoc """
    A `for` loop. Each of `init`, `condition` and `update` is `nil` when
    left out. `init` is a `Loxe.Ast.VarDecl` for `for (var i = 0; ...)`.
    """

    alias Loxe.Ast.VarDecl

    @enforce_keys [:init, :condition, :update, :body, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            init: VarDecl.t() | Loxe.Ast.expr() | nil,
            condition: Loxe.Ast.expr() | nil,
            update: Loxe.Ast.expr() | nil,
            body: Loxe.Ast.stmt(),
            span: Span.t()
          }
  end

  defmodule Block do
    @moduledoc """
    A block, `{ ... }`.
    """

    @enforce_keys [:body, :span]
    defstruct @enforce_keys
    @type t :: %__MODULE__{body: [Loxe.Ast.decl()], span: Span.t()}
  end

  # Declarations

  defmodule VarDecl do
    @moduledoc """
    A variable declaration. `value` is `nil` when there is no initializer.
    """

    alias Loxe.Ast.Ident

    @enforce_keys [:name, :value, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            name: Ident.t(),
            value: Loxe.Ast.expr() | nil,
            span: Span.t()
          }
  end

  defmodule Fun do
    @moduledoc """
    A function declaration.
    """

    alias Loxe.Ast.Block
    alias Loxe.Ast.Ident

    @enforce_keys [:name, :params, :body, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            name: Ident.t(),
            params: [Ident.t()],
            body: Block.t(),
            span: Span.t()
          }
  end

  defmodule Class do
    @moduledoc """
    A class declaration.
    """

    alias Loxe.Ast.Fun
    alias Loxe.Ast.Ident
    alias Loxe.Ast.Var

    @enforce_keys [:name, :super_class, :methods, :static_methods, :getters, :span]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            name: Ident.t(),
            super_class: Var.t() | nil,
            methods: [Fun.t()],
            static_methods: [Fun.t()],
            getters: [Fun.t()],
            span: Span.t()
          }
  end
end
