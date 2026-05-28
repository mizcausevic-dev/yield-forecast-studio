include(joinpath(@__DIR__, "..", "src", "YieldForecastStudio.jl"))
using .YieldForecastStudio

result = build_dashboard()
root = write_site(result)

required = [
    joinpath(root, "index.html"),
    joinpath(root, "yield-lane", "index.html"),
    joinpath(root, "forecast-matrix", "index.html"),
    joinpath(root, "inventory-posture", "index.html"),
    joinpath(root, "verification", "index.html"),
    joinpath(root, "docs", "index.html"),
    joinpath(root, "robots.txt"),
    joinpath(root, "sitemap.xml"),
    joinpath(root, "api", "dashboard.json"),
]

for path in required
    isfile(path) || error("Missing generated asset: " * path)
end

println("Smoke check passed for ", root)
