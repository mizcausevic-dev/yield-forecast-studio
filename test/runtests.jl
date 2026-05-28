using Test
using YieldForecastStudio

@testset "yield forecast studio" begin
    scenario = sample_scenario()
    result = optimize_yield(scenario)

    @test result["total_assigned_units"] <= result["total_forecast_units"]
    @test result["coverage_pct"] > 60
    @test length(result["lane_results"]) == 6
    @test length(result["pool_results"]) == 3
    @test any(item["shortfall_units"] > 0 for item in result["lane_results"])
end
