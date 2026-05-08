# Sienna Programming Practices

This document describes general programming practices and conventions that apply across all Sienna packages (PowerSystems.jl, PowerSimulations.jl, PowerFlows.jl, PowerNetworkMatrices.jl, InfrastructureSystems.jl, etc.).

## Performance Requirements

**Priority:** Critical. See the [Julia Performance Tips](https://docs.julialang.org/en/v1/manual/performance-tips/).

### Anti-Patterns to Avoid

#### Type instability

Functions must return consistent concrete types. Check with `@code_warntype`.

- Bad: `f(x) = x > 0 ? 1 : 1.0`
- Good: `f(x) = x > 0 ? 1.0 : 1.0`

#### Abstract field types

Struct fields must have concrete types or be parameterized.

- Bad: `struct Foo; data::AbstractVector; end`
- Good: `struct Foo{T<:AbstractVector}; data::T; end`

#### Untyped containers

- Bad: `Vector{Any}()`, `Vector{Real}()`
- Good: `Vector{Float64}()`, `Vector{Int}()`

#### Non-const globals

- Bad: `THRESHOLD = 0.5`
- Good: `const THRESHOLD = 0.5`

#### Unnecessary allocations

- Use views instead of copies (`@view`, `@views`)
- Pre-allocate arrays instead of `push!` in loops
- Use in-place operations (functions ending with `!`)

#### Captured variables

Avoid closures that capture variables causing boxing. Pass variables as function arguments instead.

#### Splatting penalty

Avoid splatting (`...`) in performance-critical code.

#### Abstract return types

Avoid returning `Union` types or abstract types.

### Best Practices

- Use `@inbounds` when bounds are verified
- Use broadcasting (dot syntax) for element-wise operations
- Avoid `try-catch` in hot paths
- Use function barriers to isolate type instability

> Apply these guidelines with judgment. Not every function is performance-critical. Focus optimization efforts on hot paths and frequently called code.

## Code Conventions

Style guide: <https://sienna-platform.github.io/InfrastructureSystems.jl/stable/style/>

Formatter (JuliaFormatter): Use the formatter script provided in each package.

Key rules:

- Constructors: use `function Foo()` not `Foo() = ...`
- Asserts: prefer `InfrastructureSystems.@assert_op` over `@assert`
- Globals: `UPPER_CASE` for constants
- Exports: all exports in main module file
- Comments: complete sentences, describe why not how

## Documentation Practices and Requirements

Framework: [Diataxis](https://diataxis.fr/)

Sienna best practices:
- General formatting: <https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/how-to/general_formatting/>
- Tutorials: <https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/how-to/write_a_tutorial/>
- How-to's: <https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/how-to/write_a_how-to/>

Docstring requirements:

- Scope: all elements of public interface (IS is selective about exports)
- Include: function signatures and arguments list
- Automation: `DocStringExtensions.TYPEDSIGNATURES` (`TYPEDFIELDS` used sparingly in IS)
- See also: add links for functions with same name (multiple dispatch)
- General Do's and Dont's: <https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/how-to/write_docstrings_org_api/#use_autodocs>

API docs:

- Public: typically in `docs/src/reference/public.md` (preferred) or `docs/src/api/public.md` (legacy)
    - Public API is preferrentially organized with `@autodocs` with `Public=true, Private=false`,
    but `@docs` blocks for custom organization is allowable
- Internals: typically in `docs/src/reference/internal.md` (preferred) or `docs/src/api/internal.md` (legacy)

## Design Principles

- Elegance and concision in both interface and implementation
- Fail fast with actionable error messages rather than hiding problems
- Validate invariants explicitly in subtle cases
- Avoid over-adherence to backwards compatibility for internal helpers

## Contribution Workflow

Branch naming: `feature/description` or `fix/description`

1. Create feature branch
2. Follow style guide and run formatter
3. Ensure tests pass
4. Submit pull request

## AI Agent Guidance

**Key priorities:** Read existing patterns first, maintain consistency, use concrete types in hot paths, run formatter, add docstrings to public API, ensure tests pass.

**Critical rules:**
- Always use `julia --project=<env>` (never bare `julia`)
- Never edit auto-generated files directly
- Verify type stability with `@code_warntype` for performance-critical code
- Consider downstream package impact

## Julia Environment Best Practices

**CRITICAL:** Always use `julia --project=<env>` when running Julia code in Sienna repositories. **NEVER** use bare `julia` or `julia --project` without specifying the environment. Each package typically defines dependencies in `test/Project.toml` for testing.

Common patterns:

```sh
# Run tests (using test environment)
julia --project=test test/runtests.jl

# Run specific test
julia --project=test test/runtests.jl test_file_name

# Run expression
julia --project=test -e 'using PackageName; ...'

# Instantiate environment
julia --project=test -e 'using Pkg; Pkg.instantiate()'

# Build docs (using docs environment)
julia --project=docs docs/make.jl
```

**Why this matters:** Running without `--project=<env>` will fail because required packages won't be available in the default environment. The test/docs environments contain all necessary dependencies for their respective tasks.

## Troubleshooting

**Type instability**
- Symptom: Poor performance, many allocations
- Diagnosis: `@code_warntype` on suspect function
- Solution: See performance anti-patterns above

**Formatter fails**
- Symptom: Formatter command returns error
- Solution: Run the formatter script provided in the package (e.g., `julia -e 'include("scripts/formatter/formatter_code.jl")'`)

**Test failures**
- Symptom: Tests fail unexpectedly
- Solution: `julia --project=test -e 'using Pkg; Pkg.instantiate()'`

**Documentation failures**
- General troubleshooting: ≤https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/how-to/troubleshoot/#Troubleshoot-Common-Errors>

- Symptom: `makedocs encountered an error` including `:missing_docs`
- Solution: Determine whether the public API file is formatted using either `@autodocs` or 
    `@docs` blocks and add missing files or type/method/function references accordingly

- Symptom: `makedocs encountered an error` including `:cross_references`
- Potential solutions: 
    - If the referenced function or type is exported, ensure it has a docstring and is
    mapped to the Public API
    - Verify reference syntax <https://documenter.juliadocs.org/stable/man/syntax/#at-ref-at-id-links>
    - If the reference is actually in another package, switch to an `@extref` using `DocumenterInterLinks.jl` and define the package in docs/src/make.jl `InterLinks`
    if absent
    - Add explicit `ExternalFallbacks` in docs/src/make.jl for `@ref`s within `@extref`s <https://juliadocs.org/DocumenterInterLinks.jl/stable/fallback/>

- Symptom: `makedocs encountered an error` including `:external_cross_references`
- Potential solutions:
    - Add the package containing the external cross reference in docs/src/make.jl `InterLinks` definition if absent
    - Verify DocumenterInterLinks.jl's standard syntax is applied correctly: <https://juliadocs.org/DocumenterInterLinks.jl/stable/syntax/>
    - If that fails, find the exact link by searching the inventory: <https://juliadocs.org/DocumenterInterLinks.jl/stable/howtos/#howto-find-extref>
