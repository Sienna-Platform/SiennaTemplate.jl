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

"""
Check per-module documentation coverage for `func`.

Returns a list of (module_name, n_methods) for modules that define methods
of `func` but have zero docstring entries for it.
"""
function _find_undocumented_method_modules(func)
    # Count methods per defining module
    mod_method_counts = Dict{Module, Int}()
    for m in methods(func)
        mod_method_counts[m.module] = get(mod_method_counts, m.module, 0) + 1
    end

    undocumented = Vector{Tuple{String, Int}}()  # (module_name, n_methods)
    # The function might be owned by a different module (e.g., IS.serialize
    # extended in PowerSystems). Check bindings for both the method's module
    # and the function's owning module.
    owner_mod = parentmodule(func)
    fname = nameof(func)

    for (mod, n_methods) in mod_method_counts
        # Skip synthetic modules created by @scoped_enum
        endswith(string(nameof(mod)), "Module") && continue
        has_docs = false
        try
            meta = Base.Docs.meta(mod)
            for bind_mod in Set([mod, owner_mod])
                binding = Base.Docs.Binding(bind_mod, fname)
                if haskey(meta, binding) && !isempty(meta[binding].docs)
                    has_docs = true
                    break
                end
            end
        catch
        end
        if !has_docs
            push!(undocumented, (string(mod), n_methods))
        end
    end
    return undocumented
end

function check_all_names(mod, modname; include_private=false)
    missing_types = Vector{String}()
    missing_funcs = Vector{String}()
    reexport_missing_types = Vector{Tuple{String, String}}()   # (name, source_module)
    reexport_missing_funcs = Vector{Tuple{String, String}}()
    # (func_name, [(module_name, n_methods), ...])
    partial_funcs = Vector{Tuple{String, Vector{Tuple{String, Int}}}}()
    skipped_accessors = 0
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
            # Check for partially documented functions: find modules that
            # define methods but have zero doc entries for this function.
            if obj isa Function
                undoc_mods = _find_undocumented_method_modules(obj)
                if !isempty(undoc_mods)
                    sn = string(n)
                    total_methods = length(methods(obj))
                    is_accessor = startswith(sn, "get_") || startswith(sn, "set_")
                    if is_accessor && total_methods > 10
                        skipped_accessors += 1
                    else
                        push!(partial_funcs, (sn, undoc_mods))
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
        skipped_accessors,
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
        for (name, undoc_mods) in Iterators.take(sorted, 12)
            mod_strs = join(["$m ($n methods)" for (m, n) in undoc_mods], ", ")
            println("  $name — undocumented in: $mod_strs")
        end
        remaining = length(sorted) - 12
        if remaining > 0
            println("  ... and $remaining more")
        end
    end
    if r.skipped_accessors > 0
        println("Uniform accessors (get_*/set_*!) skipped: $(r.skipped_accessors)")
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
