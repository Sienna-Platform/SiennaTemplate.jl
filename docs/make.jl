using Documenter
import DataStructures: OrderedDict
using SiennaTemplate
using DocumenterInterLinks
using Literate

# UPDATE FOR CURRENT MODULE NAME HERE
const _DOCS_BASE_URL = "https://nrel-sienna.github.io/SiennaTemplate.jl/stable"

links = InterLinks(
    # "InfrastructureSystems" => "https://nrel-sienna.github.io/InfrastructureSystems.jl/stable/"
)

# Explicitly defined fallbacks for external docstrings that fail to resolve
fallbacks = ExternalFallbacks(
    # "ComponentContainer" => "@extref InfrastructureSystems.ComponentContainer",
)

include(joinpath(@__DIR__, "make_tutorials.jl"))
make_tutorials()

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Tutorials" => Any["stub" => "tutorials/generated_stub.md"],
    "How to..." => Any["stub" => "how_to_guides/stub.md"],
    "Explanation" => Any["stub" => "explanation/stub.md"],
    "Reference" => Any[ 
        "Developers" => ["Developer Guidelines" => "reference/developer_guidelines.md",
        "Internals" => "reference/internal.md"],
        "Public API" => "reference/public.md",
        "Stub" => "reference/stub.md"
    ],
)

makedocs(
    modules = [SiennaTemplate],
    format = Documenter.HTML(
        prettyurls = haskey(ENV, "GITHUB_ACTIONS"),
        size_threshold = nothing,),
    sitename = "github.com/NREL-Sienna/SiennaTemplate.jl",
    authors = "Freddy Mercury",
    pages = Any[p for p in pages],
    draft = false,
    plugins = [links, fallbacks],
)

deploydocs(
    repo="github.com/NREL-Sienna/SiennaTemplate.jl",
    target="build",
    branch="gh-pages",
    devbranch="main",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)

