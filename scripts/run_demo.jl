include(joinpath(@__DIR__, "..", "src", "YieldForecastStudio.jl"))
using .YieldForecastStudio

result = build_dashboard()
println("Scenario: ", result["scenario_title"])
println("Coverage: ", result["coverage_pct"], "%")
println("Assigned units: ", result["total_assigned_units"])
println("Shortfall units: ", result["total_shortfall_units"])
