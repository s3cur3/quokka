defmodule Quokka.AliasEnv do
  @moduledoc """
  A datastructure for maintaining something like compiler alias state when traversing AST.

  Not anywhere as correct as what the compiler gives us, but close enough for open source work.

  A alias env is a map from an alias's `as` to its resolution in a context.

  Given the ast for

      alias Foo.Bar

  we'd create the env:

      %{:Bar => [:Foo, :Bar]}
  """
  def define(env \\ %{}, ast)

  def define(env, asts) when is_list(asts), do: Enum.reduce(asts, env, &define(&2, &1))

  def define(env, {:alias, _, aliases}) do
    case aliases do
      [{:__aliases__, _, aliases}] -> define(env, aliases, List.last(aliases))
      [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]] -> define(env, aliases, as)
      # `alias __MODULE__` or other oddities i'm not bothering to get right
      _ -> env
    end
  end

  defp define(env, modules, as), do: Map.put(env, as, do_expand(env, modules))

  # no need to traverse ast if there are no aliases
  def expand(env, ast) when map_size(env) == 0, do: ast

  def expand(env, ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, modules} -> {:__aliases__, meta, do_expand(env, modules)}
      ast -> ast
    end)
  end

  @doc """
  Resolve just the leading module path of an `alias` directive against `env`.

  Unlike `expand/2`, this only rewrites the alias's own module path (and, for brace-multi forms,
  the namespace to the left of the `.{}`). Child segments of a `Foo.{Bar, Baz}` form are not
  aliases in their own right, so they're left untouched.
  """
  def dealias_directive(env, ast, opts \\ [])
  def dealias_directive(env, ast, _opts) when map_size(env) == 0, do: ast
  def dealias_directive(_env, {:alias, m, [{:__aliases__, _, [Elixir | _]} = aliases]}, _), do: {:alias, m, [aliases]}

  def dealias_directive(env, {:alias, m, [{:__aliases__, am, modules} | rest]}, opts) do
    {:alias, m, [{:__aliases__, am, expand_alias_path(env, modules, opts)} | rest]}
  end

  def dealias_directive(env, {:alias, m, [{{:., dm, [{:__aliases__, nm, namespace}, :{}]}, cm, children}]}, opts) do
    {:alias, m, [{{:., dm, [{:__aliases__, nm, expand_alias_path(env, namespace, opts)}, :{}]}, cm, children}]}
  end

  def dealias_directive(_env, ast, _opts), do: ast

  defp expand_alias_path(env, modules, opts) do
    case do_expand(env, modules) do
      ^modules ->
        modules

      expanded ->
        if Access.get(opts, :disambiguate, false) do
          # After sorting, an alias like `B.E` can end up below `alias A.B` even though it was
          # written first and meant top-level `B.E`. Prefix with `Elixir.` to preserve that meaning.
          disambiguate_or_keep(modules)
        else
          expanded
        end
    end
  end

  defp disambiguate_or_keep([first | rest] = modules) when rest != [] and rest != [first], do: [:"Elixir" | modules]
  defp disambiguate_or_keep(modules), do: modules

  defp do_expand(env, [first | rest] = modules) do
    cond do
      # Non-atom segments (e.g. `__MODULE__`) can't be fed to Module.concat / Macro.Env.
      not Enum.all?(modules, &is_atom/1) ->
        modules

      # A self-referential alias (e.g. `alias Foo.Foo`, `alias A.A.A`) resolves its own leading segment
      # back to a path that still begins with that segment. Appending a remainder would deepen the path
      # (`Foo.Bar` → `Foo.Foo.Bar`, then again on later passes). Leave the path alone in that case.
      # Resolving the bare alias name (no remainder) is still fine and goes through Macro.expand_literals.
      rest != [] and match?([^first | _], env[first]) ->
        modules

      true ->
        expand_with_macro(env, modules)
    end
  end

  # Uses Macro.expand_literals to apply the compiler's alias resolution rules, then convert the module atom back to segments.
  defp expand_with_macro(env, modules) do
    aliases =
      env
      |> Enum.filter(fn {_as, path} -> is_list(path) and Enum.all?(path, &is_atom/1) end)
      |> Enum.map(fn {as, path} -> {Module.concat([as]), Module.concat(path)} end)

    macro_env = %{__ENV__ | aliases: aliases, macro_aliases: []}

    Macro.expand_literals({:__aliases__, [], modules}, macro_env)
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end
end
