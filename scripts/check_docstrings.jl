"""
Check that all exported symbols in a module have docstrings.
Also reports partially documented functions (where some methods have docstrings but others don't).
Re-exported symbols (defined in another module) are reported separately.

Usage:
    julia --project=. scripts/check_docstrings.jl ModuleName [SubModule1 SubModule2 ...]

Options (via environment variables):
    CHECK_ALL=true    Include non-exported (private) symbols

Examples:
    julia --project=. scripts/check_docstrings.jl InfrastructureSystems
    julia --project=. scripts/check_docstrings.jl InfrastructureSystems Optimization
    julia --project=. scripts/check_docstrings.jl PowerSystems
    CHECK_ALL=true julia --project=. scripts/check_docstrings.jl InfrastructureSystems
"""

function _is_reexported(obj, mod)
    pm = try
        parentmodule(obj)
    catch
        return false
    end
    return pm !== mod && pm !== Base && pm !== Core
end

"""Count how many methods of `func` have their own docstring via Docs.meta."""
function _count_documented_methods(func)
    defining_mods = Set{Module}()
    for m in methods(func)
        push!(defining_mods, m.module)
    end
    push!(defining_mods, parentmodule(func))

    n_documented = 0
    for mod in defining_mods
        local meta
        try
            meta = Base.Docs.meta(mod)
        catch
            continue
        end
        binding = Base.Docs.Binding(mod, nameof(func))
        if haskey(meta, binding)
            n_documented += length(meta[binding].docs)
        end
    end
    return n_documented
end

function check_all_names(mod, modname; include_private=false)
    missing_types = Vector{String}()
    missing_funcs = Vector{String}()
    reexport_missing_types = Vector{Tuple{String, String}}()   # (name, source_module)
    reexport_missing_funcs = Vector{Tuple{String, String}}()
    partial_funcs = Vector{Tuple{String, Int, Int}}()  # (name, documented, total)
    ndoc = 0
    for n in names(mod; all=include_private)
        n == Symbol(modname) && continue
        startswith(string(n), "#") && continue
        n == :eval && continue
        n == :include && continue
        obj = try
            getfield(mod, n)
        catch
            continue
        end
        obj isa Module && continue
        reexported = _is_reexported(obj, mod)
        doc = Base.Docs.doc(obj)
        docstr = string(doc)
        if startswith(docstr, "No documentation found")
            if obj isa Type || obj isa UnionAll
                if reexported
                    src = string(parentmodule(obj))
                    push!(reexport_missing_types, (string(n), src))
                else
                    push!(missing_types, string(n))
                end
            elseif obj isa Function
                if reexported
                    src = string(parentmodule(obj))
                    push!(reexport_missing_funcs, (string(n), src))
                else
                    push!(missing_funcs, string(n))
                end
            end
        else
            if obj isa Type || obj isa UnionAll || obj isa Function
                ndoc += 1
            end
            # Check for partially documented functions (some methods lack docstrings)
            if obj isa Function
                total_methods = length(methods(obj))
                if total_methods > 1
                    n_documented = _count_documented_methods(obj)
                    if n_documented < total_methods && n_documented > 0
                        push!(partial_funcs, (string(n), n_documented, total_methods))
                    end
                end
            end
        end
    end
    return (;
        missing_types,
        missing_funcs,
        reexport_missing_types,
        reexport_missing_funcs,
        partial_funcs,
        ndoc,
    )
end

function _print_list(items; max_items=12)
    sorted = sort(items)
    for item in Iterators.take(sorted, max_items)
        if item isa Tuple
            println("  $(item[1])  (from $(item[2]))")
        else
            println("  $item")
        end
    end
    remaining = length(sorted) - max_items
    if remaining > 0
        println("  ... and $remaining more")
    end
end

function report(mod, modname; include_private=false)
    scope = include_private ? "all" : "exported"
    println("=== $modname ($scope) ===")
    r = check_all_names(mod, modname; include_private)

    if !isempty(r.missing_types)
        println("Types without docs ($(length(r.missing_types))):")
        _print_list(r.missing_types)
        println()
    end

    if !isempty(r.missing_funcs)
        println("Functions without docs ($(length(r.missing_funcs))):")
        _print_list(r.missing_funcs)
        println()
    end

    if !isempty(r.reexport_missing_types)
        println("Re-exported types without docs ($(length(r.reexport_missing_types))):")
        _print_list(r.reexport_missing_types)
        println()
    end

    if !isempty(r.reexport_missing_funcs)
        println("Re-exported functions without docs ($(length(r.reexport_missing_funcs))):")
        _print_list(r.reexport_missing_funcs)
        println()
    end

    println("Documented symbols: $(r.ndoc)")

    if !isempty(r.partial_funcs)
        println("Partially documented functions ($(length(r.partial_funcs))):")
        sorted = sort(r.partial_funcs; by=first)
        for (name, ndoc, ntotal) in Iterators.take(sorted, 12)
            println("  $name: $ndoc/$ntotal methods documented")
        end
        remaining = length(sorted) - 12
        if remaining > 0
            println("  ... and $remaining more")
        end
    end
    println()
end

# --- Main ---
if isempty(ARGS)
    println(stderr,
        "Usage: julia --project=. scripts/check_docstrings.jl ModuleName [SubModule1 ...]")
    exit(1)
end

include_private = get(ENV, "CHECK_ALL", "false") == "true"
pkg_name = ARGS[1]
submodules = ARGS[2:end]

@eval using $(Symbol(pkg_name))
root_mod = getfield(Main, Symbol(pkg_name))

report(root_mod, pkg_name; include_private)

for sub in submodules
    submod = getfield(root_mod, Symbol(sub))
    report(submod, "$pkg_name.$sub"; include_private)
end
