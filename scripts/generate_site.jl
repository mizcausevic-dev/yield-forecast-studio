include(joinpath(@__DIR__, "..", "src", "YieldForecastStudio.jl"))
using .YieldForecastStudio

result = build_dashboard()
root = write_site(result)
println("Generated site at: ", root)
