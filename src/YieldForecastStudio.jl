# SPDX-License-Identifier: AGPL-3.0-or-later

module YieldForecastStudio

using Dates
using Printf

export InventoryPool, DemandLane, ForecastScenario, sample_scenario, optimize_yield, build_dashboard, write_site

struct InventoryPool
    id::String
    label::String
    capacity::Int
    floor_yield::Float64
    confidence::Float64
end

struct DemandLane
    id::String
    label::String
    pool_index::Int
    forecast_units::Int
    yield_per_unit::Float64
    priority::Float64
    volatility_penalty::Float64
end

struct ForecastScenario
    title::String
    generated_on::Date
    pools::Vector{InventoryPool}
    lanes::Vector{DemandLane}
    rollover_units::Int
end

function sample_scenario()
    pools = [
        InventoryPool("INV-1", "Homepage and feature inventory", 18, 290.0, 0.94),
        InventoryPool("INV-2", "Email and lifecycle inventory", 14, 240.0, 0.91),
        InventoryPool("INV-3", "Commerce promo and partner slots", 11, 330.0, 0.86),
    ]

    lanes = [
        DemandLane("YL-11", "Homepage launch takeover", 1, 9, 470.0, 0.96, 34.0),
        DemandLane("YL-14", "Editorial sponsor recovery", 1, 6, 420.0, 0.92, 39.0),
        DemandLane("YL-21", "Lifecycle retention send", 2, 8, 360.0, 0.94, 26.0),
        DemandLane("YL-27", "Product drop remarketing", 2, 7, 390.0, 0.89, 31.0),
        DemandLane("YL-34", "Partner bundle spotlight", 3, 10, 520.0, 0.87, 48.0),
        DemandLane("YL-39", "Clearance yield rescue", 3, 5, 560.0, 0.91, 55.0),
    ]

    ForecastScenario(
        "Yield forecast studio for publishing, lifecycle, and commerce inventory",
        Date(2026, 5, 28),
        pools,
        lanes,
        13,
    )
end

score_units(lane::DemandLane, units::Int) = units * (lane.yield_per_unit * lane.priority - lane.volatility_penalty)

function optimize_yield(scenario::ForecastScenario)
    capacities = [p.capacity for p in scenario.pools]
    limits = [lane.forecast_units for lane in scenario.lanes]
    best_score = Ref(-Inf)
    best_units = fill(0, length(scenario.lanes))

    function search!(index::Int, current_units::Vector{Int}, used_capacity::Vector{Int}, current_score::Float64)
        if index > length(scenario.lanes)
            if current_score > best_score[]
                best_score[] = current_score
                best_units .= current_units
            end
            return
        end

        lane = scenario.lanes[index]
        pool_slot = lane.pool_index
        max_assignable = min(limits[index], capacities[pool_slot] - used_capacity[pool_slot])

        for units in 0:max_assignable
            current_units[index] = units
            used_capacity[pool_slot] += units
            search!(index + 1, current_units, used_capacity, current_score + score_units(lane, units))
            used_capacity[pool_slot] -= units
        end

        current_units[index] = 0
    end

    search!(1, fill(0, length(scenario.lanes)), fill(0, length(capacities)), 0.0)

    lane_results = Any[]
    for (i, lane) in enumerate(scenario.lanes)
        assigned = best_units[i]
        shortfall = lane.forecast_units - assigned
        utilization = assigned / max(lane.forecast_units, 1)
        push!(lane_results, Dict(
            "id" => lane.id,
            "label" => lane.label,
            "pool" => scenario.pools[lane.pool_index].label,
            "assigned_units" => assigned,
            "forecast_units" => lane.forecast_units,
            "shortfall_units" => shortfall,
            "coverage" => round(utilization * 100; digits=1),
            "priority" => lane.priority,
            "volatility_penalty" => lane.volatility_penalty,
            "score" => round(score_units(lane, assigned); digits=1),
            "status" => shortfall == 0 ? "green" : shortfall <= 2 ? "yellow" : "red",
        ))
    end

    pool_results = Any[]
    for (i, pool) in enumerate(scenario.pools)
        assigned = sum(best_units[j] for (j, lane) in enumerate(scenario.lanes) if lane.pool_index == i)
        utilization = assigned / max(pool.capacity, 1)
        push!(pool_results, Dict(
            "id" => pool.id,
            "label" => pool.label,
            "capacity" => pool.capacity,
            "assigned_units" => assigned,
            "free_units" => pool.capacity - assigned,
            "utilization" => round(utilization * 100; digits=1),
            "confidence" => round(pool.confidence * 100; digits=1),
            "status" => utilization >= 0.95 ? "red" : utilization >= 0.8 ? "yellow" : "green",
        ))
    end

    total_assigned = sum(best_units)
    total_forecast = sum(lane.forecast_units for lane in scenario.lanes)
    total_shortfall = total_forecast - total_assigned
    weighted_yield = round(sum(scenario.lanes[i].yield_per_unit * best_units[i] for i in eachindex(best_units)); digits=1)
    weighted_volatility = round(sum(scenario.lanes[i].volatility_penalty * best_units[i] for i in eachindex(best_units)); digits=1)

    return Dict(
        "scenario_title" => scenario.title,
        "generated_on" => string(scenario.generated_on),
        "score" => round(best_score[]; digits=1),
        "total_assigned_units" => total_assigned,
        "total_forecast_units" => total_forecast,
        "total_shortfall_units" => total_shortfall,
        "coverage_pct" => round(total_assigned / total_forecast * 100; digits=1),
        "weighted_yield" => weighted_yield,
        "weighted_volatility" => weighted_volatility,
        "rollover_units" => scenario.rollover_units,
        "lane_results" => lane_results,
        "pool_results" => pool_results,
    )
end

build_dashboard() = optimize_yield(sample_scenario())

escape_html(text) = replace(string(text), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

function json_string(value)
    if value isa Dict
        parts = ["\"$(escape_html(k))\":$(json_string(v))" for (k, v) in value]
        return "{" * join(parts, ",") * "}"
    elseif value isa AbstractVector
        return "[" * join(json_string.(value), ",") * "]"
    elseif value isa String
        return "\"" * replace(value, "\"" => "\\\"") * "\""
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa Number
        return string(value)
    else
        return "\"" * replace(string(value), "\"" => "\\\"") * "\""
    end
end

function base_css()
    return """
    :root{
      --bg:#070a0f; --panel:#0b1220; --panel2:#0a1426;
      --line:rgba(120,255,170,.18); --line2:rgba(120,255,170,.10);
      --text:#e9f3ff; --muted:rgba(233,243,255,.72); --muted2:rgba(233,243,255,.55);
      --bert:#37ff8b; --bert2:#19c7ff; --warn:#ffcc66; --bad:#ff5c7a; --plum:#b88cff;
      --shadow:0 18px 60px rgba(0,0,0,.55); --radius:18px;
      --mono:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Courier New",monospace;
      --sans:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
    }
    *{box-sizing:border-box} html,body{height:100%}
    body{
      margin:0;font-family:var(--sans);color:var(--text);
      background:
        radial-gradient(1200px 600px at 20% -10%, rgba(55,255,139,.18), transparent 60%),
        radial-gradient(900px 520px at 90% 0%, rgba(25,199,255,.16), transparent 55%),
        radial-gradient(1000px 600px at 50% 110%, rgba(55,255,139,.10), transparent 60%),
        linear-gradient(180deg,#05070c 0%,#070a0f 35%,#05070c 100%);
    }
    .grid-bg{position:fixed;inset:0;pointer-events:none;opacity:.12;z-index:-1;background-image:
      linear-gradient(to right, rgba(55,255,139,.14) 1px, transparent 1px),
      linear-gradient(to bottom, rgba(55,255,139,.10) 1px, transparent 1px);
      background-size:46px 46px;mask-image: radial-gradient(900px 600px at 40% 10%, #000 60%, transparent 100%);}
    .wrap{max-width:1280px;margin:0 auto;padding:24px 22px 80px}
    .topbar{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;border-bottom:1px solid var(--line2);padding-bottom:14px;margin-bottom:22px;font-family:var(--mono);font-size:11px;letter-spacing:.16em;color:var(--muted);text-transform:uppercase}
    .topbar .left{color:var(--bert)} .topbar .right{text-align:right}
    .herorow{display:grid;grid-template-columns:1.45fr .85fr;gap:18px} @media (max-width:1000px){.herorow{grid-template-columns:1fr}}
    .hero,.panel,.mini,.tablewrap{
      background:linear-gradient(180deg, rgba(11,18,32,.95), rgba(8,14,26,.92));
      border:1px solid var(--line);border-radius:22px;box-shadow:var(--shadow)
    }
    .hero{padding:28px 28px 24px;border-top:2px solid var(--bert2)}
    .hero h1{font-size:64px;line-height:.95;margin:0 0 18px;font-weight:800;letter-spacing:-.5px}
    @media (max-width:700px){.hero h1{font-size:42px}}
    .hero p,.panel p,.mini p,.tablewrap p{color:var(--muted);font-size:15px;line-height:1.55}
    .chiprow{display:flex;flex-wrap:wrap;gap:8px}
    .meta-chip,.pill{font-family:var(--mono);font-size:11px;padding:7px 12px;border-radius:999px;border:1px solid var(--line);background:rgba(6,10,18,.4);color:var(--muted)}
    .side{display:flex;flex-direction:column;gap:14px}
    .mini{padding:18px}
    .mini .lbl,.section-note{font-family:var(--mono);font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:var(--bert2)}
    .mini h3{margin:8px 0 6px;font-size:28px;line-height:1.02}
    .section{margin-top:34px}
    .sh{display:flex;justify-content:space-between;align-items:baseline;gap:14px;padding-bottom:10px;border-bottom:1px solid var(--line2);margin-bottom:14px}
    .sh h2{margin:0;font-size:24px;font-weight:600}
    .sh .note{font-family:var(--mono);font-size:11px;color:var(--muted2);letter-spacing:.16em;text-transform:uppercase}
    .kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px} @media (max-width:900px){.kpis{grid-template-columns:repeat(2,1fr)}} @media (max-width:640px){.kpis{grid-template-columns:1fr}}
    .kpi,.card{border:1px solid var(--line);border-radius:16px;padding:16px;background:linear-gradient(180deg, rgba(11,18,32,.85), rgba(8,14,26,.65))}
    .kpi .v{font-family:var(--mono);font-size:28px;font-weight:700}
    .kpi .lbl{font-family:var(--mono);font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:var(--muted);margin-top:6px}
    .kpi .h{font-size:12px;color:var(--muted);line-height:1.45;margin-top:8px}
    .green{color:var(--bert)} .cyan{color:var(--bert2)} .warn{color:var(--warn)} .plum{color:var(--plum)} .bad{color:var(--bad)}
    .cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px} @media (max-width:1000px){.cards{grid-template-columns:1fr}}
    .card h3{margin:8px 0 8px;font-size:22px}
    .card .eyebrow{font-family:var(--mono);font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:var(--bert)}
    table{width:100%;border-collapse:collapse} th,td{padding:13px 14px;text-align:left;font-size:13.5px;vertical-align:top}
    thead th{font-family:var(--mono);font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted2);border-bottom:1px solid var(--line);background:rgba(11,18,32,.5)}
    tbody tr:hover{background:rgba(55,255,139,.03)} tbody td{color:var(--muted);border-bottom:1px solid var(--line2)}
    .tablewrap{padding:0;overflow:hidden}
    .status{display:inline-block;padding:4px 9px;border-radius:6px;border:1px solid currentColor;font-family:var(--mono);font-size:10px;letter-spacing:.1em;text-transform:uppercase}
    .quote{margin-top:34px;border:1px solid rgba(55,255,139,.22);background:radial-gradient(700px 200px at 0% 0%, rgba(55,255,139,.10), transparent 60%),linear-gradient(180deg, rgba(11,18,32,.92), rgba(8,14,26,.88));border-radius:18px;padding:24px 26px}
    .quote .lbl{font-family:var(--mono);font-size:11px;color:var(--bert);letter-spacing:.22em;text-transform:uppercase}
    .quote .q{margin-top:12px;font-size:32px;line-height:1.25;font-weight:600;max-width:1000px}
    footer{margin-top:30px;padding-top:14px;border-top:1px dashed var(--line2);display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;font-family:var(--mono);font-size:11px;color:var(--muted2);letter-spacing:.08em}
    a{color:var(--bert2);text-decoration:none}
    """
end

function html_page(title::String, description::String, content::String; canonical::String)
    return """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>$(escape_html(title))</title>
      <meta name="description" content="$(escape_html(description))">
      <meta name="robots" content="index,follow">
      <meta property="og:title" content="$(escape_html(title))">
      <meta property="og:description" content="$(escape_html(description))">
      <meta property="og:type" content="website">
      <meta property="og:url" content="$(canonical)">
      <link rel="canonical" href="$(canonical)">
      <style>$(base_css())</style>
    </head>
    <body>
      <div class="grid-bg"></div>
      <div class="wrap">
        $(content)
      </div>
    </body>
    </html>
    """
end

status_badge(status::String) = "<span class=\"status $(status == "green" ? "green" : status == "yellow" ? "warn" : "bad")\">$(uppercase(status))</span>"

function site_footer(context::String="yield forecast proof surface")
    return """
    <footer>
      <span>$(escape_html(context))</span>
      <span><a href="https://yield.kineticgain.com/">yield.kineticgain.com</a></span>
      <span><a href="https://portfolio.kineticgain.com/">Portfolio</a> · <a href="https://suite.kineticgain.com/">Suite</a> · <a href="https://github.com/mizcausevic-dev/yield-forecast-studio">Repo</a></span>
      <span><a href="https://www.linkedin.com/in/mirzacausevic/">LinkedIn</a> · <a href="https://kineticgain.com/">Kinetic Gain</a></span>
    </footer>
    """
end

function overview_content(result::Dict)
    lane_rows = join([
        """
        <tr>
          <td><b>$(escape_html(item["label"]))</b><br><span class="section-note">$(escape_html(item["id"])) · $(escape_html(item["pool"]))</span></td>
          <td>$(item["assigned_units"]) / $(item["forecast_units"])</td>
          <td>$(item["shortfall_units"])</td>
          <td>$(item["score"])</td>
          <td>$(status_badge(item["status"]))</td>
        </tr>
        """ for item in result["lane_results"]
    ], "\n")

    pool_cards = join([
        """
        <div class="card">
          <div class="eyebrow">$(escape_html(item["id"]))</div>
          <h3>$(escape_html(item["label"]))</h3>
          <p>Assigned <b>$(item["assigned_units"])</b> of <b>$(item["capacity"])</b> units with $(item["free_units"]) units left and forecast confidence of $(item["confidence"])%.</p>
          <p>$(status_badge(item["status"]))</p>
        </div>
        """ for item in result["pool_results"]
    ], "\n")

    return """
    <div class="topbar">
      <div class="left">language atlas · julia forecasting surface</div>
      <div class="right">
        <div>yield.kineticgain.com</div>
        <div>generated $(escape_html(result["generated_on"])) · publishing / commerce yield</div>
      </div>
    </div>

    <div class="herorow">
      <section class="hero">
        <div class="chiprow">
          <span class="meta-chip">Julia forecasting</span>
          <span class="meta-chip">yield planning</span>
          <span class="meta-chip">media / commerce ops</span>
          <span class="meta-chip">inventory posture</span>
        </div>
        <h1>Forecast yield before underfilled inventory turns into revenue drag.</h1>
        <p>A Julia reference implementation for Kinetic Gain OS: allocate limited homepage, lifecycle, and promo inventory across higher-yield demand lanes, quantify shortfall, and publish a buyer-readable operator report from the same model.</p>
        <div class="chiprow">
          <span class="pill">Route: /yield-lane/</span>
          <span class="pill">Route: /forecast-matrix/</span>
          <span class="pill">Route: /inventory-posture/</span>
        </div>
      </section>
      <aside class="side">
        <div class="mini">
          <div class="lbl">coverage</div>
          <h3 class="green">$(result["coverage_pct"])%</h3>
          <p>Forecast demand fulfilled by the current allocation sweep across three monetizable inventory pools and six active lanes.</p>
        </div>
        <div class="mini">
          <div class="lbl">score</div>
          <h3 class="cyan">$(result["score"])</h3>
          <p>Weighted objective combining yield priority and volatility penalty for each campaign lane.</p>
        </div>
        <div class="mini">
          <div class="lbl">shortfall watch</div>
          <h3 class="warn">$(result["total_shortfall_units"])</h3>
          <p>Forecast units left unserved after the optimization pass, with $(result["rollover_units"]) units already in rollover carryover.</p>
        </div>
      </aside>
    </div>

    <section class="section">
      <div class="sh"><h2>Operator KPIs</h2><div class="note">dashboard summary</div></div>
      <div class="kpis">
        <div class="kpi"><div class="v green">$(result["total_assigned_units"])</div><div class="lbl">assigned units</div><div class="h">Units allocated to monetizable lanes in the best plan.</div></div>
        <div class="kpi"><div class="v cyan">$(result["weighted_yield"])</div><div class="lbl">weighted yield</div><div class="h">Modeled revenue protected by the chosen routing plan.</div></div>
        <div class="kpi"><div class="v warn">$(result["weighted_volatility"])</div><div class="lbl">weighted volatility</div><div class="h">Accumulated uncertainty exposure still carried by the assigned plan.</div></div>
        <div class="kpi"><div class="v plum">$(length(result["pool_results"]))</div><div class="lbl">inventory pools</div><div class="h">Inventory surfaces represented in the optimizer sweep.</div></div>
      </div>
    </section>

    <section class="section">
      <div class="sh"><h2>Inventory posture</h2><div class="note">where sell-through is tight</div></div>
      <div class="cards">
        $(pool_cards)
      </div>
    </section>

    <section class="section">
      <div class="sh"><h2>Lane allocation</h2><div class="note">forecast vs constraint</div></div>
      <div class="tablewrap">
        <table>
          <thead>
            <tr><th>Lane</th><th>Assigned</th><th>Shortfall</th><th>Score</th><th>Status</th></tr>
          </thead>
          <tbody>
            $(lane_rows)
          </tbody>
        </table>
      </div>
    </section>

    <section class="section">
      <div class="sh"><h2>Product depth</h2><div class="note">SaaS value architecture and GTM posture</div></div>
      <div class="cards">
        <div class="card">
          <div class="eyebrow">Executive buyer value</div>
          <h3>Yield pressure becomes a revenue decision.</h3>
          <p>Media, lifecycle, commerce, and revenue operations leaders can see where scarce inventory should go before underfilled or mispriced slots turn into revenue drag.</p>
        </div>
        <div class="card">
          <div class="eyebrow">Technical proof</div>
          <h3>One Julia model feeds every route.</h3>
          <p>The same Julia allocation model creates the decision, route pages, dashboard JSON, sitemap, README proof assets, and smoke-testable static site.</p>
        </div>
        <div class="card">
          <div class="eyebrow">Commercial motion</div>
          <h3>From optimizer to monetization packet.</h3>
          <p>This can ladder into yield planning templates, inventory review boards, promotion-mix analysis, campaign recovery packets, and embedded monetization operations.</p>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="sh"><h2>What these repos have in common</h2><div class="note">Kinetic Gain operating pattern</div></div>
      <div class="cards">
        <div class="card">
          <div class="eyebrow">Risk</div>
          <h3>Make drift explicit.</h3>
          <p>Each repo turns a fuzzy operating problem into a named risk surface with score, status, owner-readable context, and next-action language.</p>
        </div>
        <div class="card">
          <div class="eyebrow">Proof</div>
          <h3>Keep evidence attached.</h3>
          <p>The product story, synthetic data contract, generated routes, sitemap, screenshots, and validation path ship together so the claim can be inspected.</p>
        </div>
        <div class="card">
          <div class="eyebrow">Action</div>
          <h3>Route the next move.</h3>
          <p>The output is not another generic dashboard. It is an operator-usable control plane for what to recover, escalate, package, or simplify next.</p>
        </div>
      </div>
    </section>

    <section class="quote">
      <div class="lbl">why this matters</div>
      <div class="q">Kinetic Gain Embedded tie-back: this repo proves the portfolio can carry forecasting and yield logic in Julia while still publishing the same buyer-readable operator surface language for media and commerce teams.</div>
    </section>

    $(site_footer("yield-forecast-studio · Julia 1.12"))
    """
end

function generic_content(title::String, note::String, body::Vector{String}; back::String="/")
    bullet_html = join(["<li>$(escape_html(line))</li>" for line in body], "")
    return """
    <div class="topbar">
      <div class="left">yield forecast studio · julia operator surface</div>
      <div class="right"><div>$(escape_html(title))</div></div>
    </div>
    <section class="hero">
      <div class="section-note">$(escape_html(note))</div>
      <h1>$(escape_html(title))</h1>
      <p>$(join(escape_html.(body), " "))</p>
      <ul style="color:var(--muted);line-height:1.8">$(bullet_html)</ul>
      <p><a href="$(back)">Return to the overview</a></p>
    </section>
    $(site_footer(lowercase(title) * " · generated proof route"))
    """
end

function write_text(path::String, content::String)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, content)
    end
end

function write_site(result::Dict; domain::String="yield.kineticgain.com", out_dir::String="site")
    root = abspath(out_dir)
    mkpath(root)
    write_text(joinpath(root, "index.html"), html_page(
        "Yield Forecast Studio",
        "Julia operator surface for publishing and commerce yield forecasting, inventory planning, and shortfall posture.",
        overview_content(result);
        canonical="https://$domain/",
    ))

    write_text(joinpath(root, "yield-lane", "index.html"), html_page(
        "Yield Lane",
        "Lane-level allocation view for the Julia yield forecast studio.",
        generic_content("Yield lane", "campaign packet view", [
            "Each demand lane blends forecast volume, expected yield, volatility, and inventory-pool constraints.",
            "The optimizer chooses unit assignments that maximize weighted yield under hard availability limits.",
            "Use this route to explain how monetizable inventory is prioritized when supply is scarce.",
        ]);
        canonical="https://$domain/yield-lane/",
    ))

    write_text(joinpath(root, "forecast-matrix", "index.html"), html_page(
        "Forecast Matrix",
        "Constraint and confidence view for the Julia yield forecast studio.",
        generic_content("Forecast matrix", "inventory pressure", [
            "Pool capacity, lane forecast, and volatility penalties determine the feasible search space.",
            "This route is where operators see whether the bottleneck is homepage inventory, lifecycle sends, or partner-slot mix.",
            "It gives the optimizer a buyer-legible explanation instead of a black-box answer.",
        ]);
        canonical="https://$domain/forecast-matrix/",
    ))

    write_text(joinpath(root, "inventory-posture", "index.html"), html_page(
        "Inventory Posture",
        "Shortfall and recovery posture for the Julia yield forecast studio.",
        generic_content("Inventory posture", "recovery posture", [
            "The chosen plan makes forecast shortfall and rollover pressure explicit.",
            "Recovery posture ties the forecast result back to human escalation and packaging decisions.",
            "This is the buyer-readable layer that turns a Julia model into an operating surface.",
        ]);
        canonical="https://$domain/inventory-posture/",
    ))

    write_text(joinpath(root, "verification", "index.html"), html_page(
        "Verification",
        "Verification notes for the Julia yield forecast studio reference implementation.",
        generic_content("Verification", "release gate", [
            "Pkg.test validates the forecasting core and result invariants.",
            "The site generator publishes crawlable HTML, robots, sitemap, and JSON dashboard data.",
            "GitHub Pages serves the report under a custom kineticgain.com subdomain.",
        ]);
        canonical="https://$domain/verification/",
    ))

    write_text(joinpath(root, "docs", "index.html"), html_page(
        "Docs",
        "Documentation for the Julia yield forecast studio reference implementation.",
        generic_content("Docs", "reference implementation", [
            "This repo expands the language atlas with real Julia code and deployable proof.",
            "It uses a brute-force constrained allocation search to stay auditable and dependency-light.",
            "The output is a static operator report that recruiters and buyers can inspect without a local REPL.",
        ]);
        canonical="https://$domain/docs/",
    ))

    dashboard_json = json_string(result)
    write_text(joinpath(root, "api", "dashboard.json"), dashboard_json)
    write_text(joinpath(root, "CNAME"), domain * "\n")
    write_text(joinpath(root, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: https://$domain/sitemap.xml\n")
    today = string(Dates.today())
    sitemap = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>https://$domain/</loc><lastmod>$today</lastmod></url>
      <url><loc>https://$domain/yield-lane/</loc><lastmod>$today</lastmod></url>
      <url><loc>https://$domain/forecast-matrix/</loc><lastmod>$today</lastmod></url>
      <url><loc>https://$domain/inventory-posture/</loc><lastmod>$today</lastmod></url>
      <url><loc>https://$domain/verification/</loc><lastmod>$today</lastmod></url>
      <url><loc>https://$domain/docs/</loc><lastmod>$today</lastmod></url>
    </urlset>
    """
    write_text(joinpath(root, "sitemap.xml"), sitemap)
    write_text(joinpath(root, "404.html"), read(joinpath(root, "index.html"), String))
    return root
end

end
