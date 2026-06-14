USE nigeria_maternal_health;

-- QUERY 1: Nigeria National MMR Trend — Year on Year Change
-- Source: WHO Global Health Observatory — who_nigeria_mmr
-- Clinical purpose: Establish national trajectory of maternal mortality before drilling into state-level DHS analysis.
-- Determines whether the problem is improving or worsening and at what pace — essential context for any intervention.

WITH mmr_trend AS (
    SELECT
        year,
        mmr_value,
        mmr_value_low,
        mmr_value_high,
        -- Uncertainty range width — wider = less confident estimate
        ROUND(mmr_value_high - mmr_value_low, 0) AS uncertainty_range,
        -- LAG gets previous data point value ordered by year
        LAG(mmr_value) OVER (ORDER BY year) AS prev_mmr
    FROM who_nigeria_mmr
    WHERE location = 'Nigeria'
	AND indicator_code = 'MDG_0000000026'
)
SELECT
    year,
    mmr_value,
    mmr_value_low,
    mmr_value_high,
    uncertainty_range,
    prev_mmr                                            AS previous_mmr,
    ROUND(mmr_value - prev_mmr, 0)                     AS absolute_change,
    ROUND((mmr_value - prev_mmr) / prev_mmr * 100, 1)  AS pct_change,
    CASE
        WHEN prev_mmr IS NULL              THEN 'Baseline'
        WHEN mmr_value < prev_mmr          THEN 'Improving'
        WHEN mmr_value > prev_mmr          THEN 'Worsening'
        ELSE                                    'No Change'
    END                                                 AS trend_direction
FROM mmr_trend
ORDER BY year;
-- QUERY 1 FINDINGS:
-- Nigeria MMR fell from 1,344 (1985) to 992.8 (2023) — 26% reduction in 38 years. However pace is critically insufficient.
-- Most alarming period: 2008-2015 — seven consecutive years of worsening MMR despite economic growth.
-- Recent improvement: consistent decline 2016-2023.
-- SDG target of 70 per 100,000 by 2030 is not achievable at current trajectory — requires 130 point/year reduction vs best ever single year of 46 points.
-- Uncertainty range narrowing — WHO estimates becoming more precise.


-- QUERY 2: State-Level Maternal Death Burden Ranking
-- Sources: fact_maternal_mortality, dim_woman, dim_geography
-- Clinical purpose: Identify which states carry the highest maternal death burden. Drives geographic prioritisation
-- of emergency obstetric care resources and interventions.

WITH state_deaths AS (
    -- CTE 1: Count pregnancy-related deaths and total female respondents per state — the numerator and denominator
    -- for state-level mortality burden calculation
    SELECT
        dg.state_name,
        dg.geopolitical_zone,
        COUNT(DISTINCT dw.woman_id)                    AS total_respondents,
        COUNT(DISTINCT CASE
            WHEN fm.pregnancy_related = 1
            THEN fm.mortality_id END)                  AS maternal_deaths,
        COUNT(DISTINCT CASE
            WHEN fm.pregnancy_related IS NOT NULL
            THEN fm.mortality_id END)                  AS total_female_deaths
    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_maternal_mortality fm
        ON dw.woman_id = fm.woman_id
    GROUP BY
        dg.state_name,
        dg.geopolitical_zone
),
state_rates AS (
    -- CTE 2: Calculate mortality rate and rank states
    -- Rate per 1,000 respondents used as proxy burden indicator
    -- Full MMR calculation requires live birth denominator which will be calculated in Query 3
    SELECT
        state_name,
        geopolitical_zone,
        total_respondents,
        maternal_deaths,
        total_female_deaths,
        ROUND(
            maternal_deaths * 1000.0 / NULLIF(total_respondents, 0)
        , 2)                                           AS deaths_per_1000_respondents,
        RANK() OVER (
            ORDER BY maternal_deaths DESC
        )                                              AS mortality_rank
    FROM state_deaths
)
SELECT
    mortality_rank,
    state_name,
    geopolitical_zone,
    total_respondents,
    maternal_deaths,
    total_female_deaths,
    deaths_per_1000_respondents
FROM state_rates
ORDER BY mortality_rank;
-- QUERY 2 FINDINGS:
-- North West and North East dominate absolute maternal death counts.
-- Kano: 30 deaths (highest absolute count).
-- Zamfara: 28.25 per 1,000 respondents (highest rate in Nigeria).
-- Enugu: critical southern outlier — 18.03 rate, demands investigation.
-- South West and South South show consistently low rates.
-- Ondo: zero confirmed deaths — requires contextual investigation.
-- Rate metric more actionable than absolute count for resource allocation — a small state with high rate needs urgent attention.



-- QUERY 3: Care Pathway Analysis by State
-- Sources: fact_anc_delivery, fact_birth, dim_woman, dim_geography
-- Clinical purpose: Identify which states have the weakest care pathways — low ANC, low facility delivery, low skilled
-- attendance. Cross-referencing with Query 2 mortality ranks reveals whether deaths are driven by access failure or
-- care quality failure — critical distinction for intervention.

WITH state_care AS (
    SELECT
        dg.state_name,
        dg.geopolitical_zone,
        -- ANC metrics
        COUNT(DISTINCT fa.anc_id)                      AS women_with_recent_birth,
        ROUND(AVG(fa.anc_visits), 1)                   AS mean_anc_visits,
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                           AS pct_zero_anc,
        ROUND(
            SUM(CASE WHEN fa.first_anc_trimester = 1
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(SUM(CASE WHEN fa.first_anc_trimester
                IS NOT NULL THEN 1 ELSE 0 END), 0)
        , 1)                                           AS pct_first_trimester_anc,
        -- Delivery metrics
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                           AS pct_facility_delivery,
        ROUND(
            SUM(CASE WHEN fa.delivery_assisted_by
                IN ('Doctor', 'Nurse or Midwife',
                    'Auxiliary Midwife')
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                           AS pct_skilled_attendant,
        -- Postnatal care
        ROUND(
            SUM(CASE WHEN fa.postnatal_check = 1
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(SUM(CASE WHEN fa.postnatal_check
                IS NOT NULL THEN 1 ELSE 0 END), 0)
        , 1)                                           AS pct_postnatal_check

    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    GROUP BY
        dg.state_name,
        dg.geopolitical_zone
)
SELECT
    state_name,
    geopolitical_zone,
    women_with_recent_birth,
    mean_anc_visits,
    pct_zero_anc,
    pct_first_trimester_anc,
    pct_facility_delivery,
    pct_skilled_attendant,
    pct_postnatal_check,
    -- Composite care gap flag
    CASE
        WHEN pct_facility_delivery < 20
         AND pct_zero_anc > 30
        THEN 'Critical Care Gap'
        WHEN pct_facility_delivery < 40
         AND pct_zero_anc > 20
        THEN 'Significant Care Gap'
        ELSE 'Moderate'
    END                                                AS care_gap_category
FROM state_care
ORDER BY pct_facility_delivery ASC;
-- QUERY 3 FINDINGS:
-- Complete North-South bifurcation in care access confirmed.
-- Kebbi: 72.3% zero ANC — worst care gap in Nigeria.
-- Zamfara: highest mortality rate + 61.5% zero ANC + 12.8% facility delivery = complete care pathway failure.
-- Enugu anomaly: 49.8% facility delivery + 95.3% skilled attendance BUT high mortality = care quality failure,
--   not access failure. Requires investigation in Query 8.
-- Lagos leads with 73.4% facility delivery but represents urban exception not national norm.
-- Critical Care Gap states: Kebbi, Sokoto, Zamfara, Katsina, Bauchi, Taraba.



-- QUERY 4: Geopolitical Zone Summary — All Care Indicators
-- Sources: All five DHS tables + WHO reference
-- Clinical purpose: Produce zone-level summary for federal ministry and development partner decision making.
-- Interventions and budgets are often allocated at zone level.

WITH zone_summary AS (
    SELECT
        dg.geopolitical_zone,
        COUNT(DISTINCT dw.woman_id)                     AS total_women,
        -- Demographics
        ROUND(AVG(dw.age_at_survey), 1)                 AS mean_age,
        ROUND(
            SUM(CASE WHEN dw.education_level = 'None'
                THEN dw.survey_weight ELSE 0 END)
            / SUM(dw.survey_weight) * 100
        , 1)                                            AS pct_no_education_wtd,
        ROUND(
            SUM(CASE WHEN dw.wealth_index
                IN ('Poorest', 'Poor')
                THEN dw.survey_weight ELSE 0 END)
            / SUM(dw.survey_weight) * 100
        , 1)                                            AS pct_poorest_poor_wtd,
        ROUND(
            SUM(CASE WHEN dw.has_insurance = 1
                THEN dw.survey_weight ELSE 0 END)
            / SUM(dw.survey_weight) * 100
        , 1)                                            AS pct_insured_wtd,
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                THEN dw.survey_weight ELSE 0 END)
            / SUM(dw.survey_weight) * 100
        , 1)                                            AS pct_distance_barrier_wtd,
        -- Care utilisation
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                            AS pct_facility_delivery,
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                            AS pct_zero_anc,
        ROUND(
            SUM(CASE WHEN fa.delivery_assisted_by
                IN ('Doctor','Nurse or Midwife',
                    'Auxiliary Midwife')
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                            AS pct_skilled_attendant,

        -- Mortality burden
        COUNT(DISTINCT CASE
            WHEN fm.pregnancy_related = 1
            THEN fm.mortality_id END)                   AS maternal_deaths,
        ROUND(
            COUNT(DISTINCT CASE
                WHEN fm.pregnancy_related = 1
                THEN fm.mortality_id END) * 1000.0
            / NULLIF(COUNT(DISTINCT dw.woman_id), 0)
        , 2)                                            AS maternal_death_rate

    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    LEFT JOIN fact_maternal_mortality fm
        ON dw.woman_id = fm.woman_id
    GROUP BY
        dg.geopolitical_zone
)
SELECT
    geopolitical_zone,
    total_women,
    mean_age,
    pct_no_education_wtd,
    pct_poorest_poor_wtd,
    pct_insured_wtd,
    pct_distance_barrier_wtd,
    pct_facility_delivery,
    pct_zero_anc,
    pct_skilled_attendant,
    maternal_deaths,
    maternal_death_rate,
    RANK() OVER (
        ORDER BY maternal_death_rate DESC
    )                                                   AS zone_risk_rank
FROM zone_summary
ORDER BY maternal_death_rate DESC;
-- QUERY 4 FINDINGS:
-- North West: highest mortality rate (13.08) — all risk factors converge simultaneously.
-- North East: similar profile, slightly better care access.
-- South East: anomaly — high skilled attendance (89.2%) but 3rd highest mortality — quality failure not access failure.
-- South West: safest zone — best care access, lowest poverty.
-- Insurance low everywhere — systemic national failure.



-- QUERY 5: Care Utilisation by Wealth Quintile
-- Sources: dim_woman, fact_anc_delivery, dim_geography
-- Clinical purpose: Quantify how wealth determines access to maternal care. Poorest women face the highest mortality risk
-- 	  but receive the least care — this query makes that inequality
-- 	  visible and measurable for policy makers.

WITH wealth_care AS (
    SELECT
        dw.wealth_index,
        COUNT(DISTINCT dw.woman_id)                     AS total_women,
        -- Weighted care metrics
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.facility_delivery
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_facility_delivery_wtd,
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.anc_visits
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_zero_anc_wtd,
        ROUND(
            SUM(CASE WHEN fa.delivery_assisted_by
                IN ('Doctor','Nurse or Midwife',
                    'Auxiliary Midwife')
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_skilled_wtd,
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_distance_barrier_wtd,
        ROUND(
            SUM(CASE WHEN dw.has_insurance = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_insured_wtd,
        ROUND(AVG(fa.anc_visits), 1)                    AS mean_anc_visits

    FROM dim_woman dw
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    GROUP BY dw.wealth_index
)
SELECT
    wealth_index,
    total_women,
    mean_anc_visits,
    pct_zero_anc_wtd,
    pct_facility_delivery_wtd,
    pct_skilled_wtd,
    pct_distance_barrier_wtd,
    pct_insured_wtd,
    -- Care inequality gap vs richest
    RANK() OVER (
        ORDER BY pct_facility_delivery_wtd DESC
    )                                                   AS facility_delivery_rank
FROM wealth_care
ORDER BY facility_delivery_rank;
-- QUERY 5 FINDINGS:
-- Richest women: 66.1% facility delivery.
-- Poorest women: 8.2% facility delivery — 8x gap.
-- Zero ANC: 49.4% poorest vs 2.8% richest.
-- Distance barrier: 42.9% poorest vs 12.9% richest.
-- Insurance near zero for poorest women (0.1%).
-- Wealth is the single strongest predictor of care access in this dataset.



-- QUERY 6: Care Utilisation by Education Level
-- Sources: dim_woman, fact_anc_delivery
-- Clinical purpose: Determine whether education independently predicts care utilisation after wealth is accounted for.
-- Education drives health literacy, decision making autonomy, and ability to navigate the health system.

WITH education_care AS (
    SELECT
        dw.education_level,
        COUNT(DISTINCT dw.woman_id)                     AS total_women,
        -- Weighted care metrics
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.facility_delivery
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_facility_delivery_wtd,
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.anc_visits
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_zero_anc_wtd,
        ROUND(
            SUM(CASE WHEN fa.delivery_assisted_by
                IN ('Doctor','Nurse or Midwife',
                    'Auxiliary Midwife')
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_skilled_wtd,
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_distance_barrier_wtd,
        ROUND(
            SUM(CASE WHEN dw.has_insurance = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_insured_wtd,
        ROUND(AVG(fa.anc_visits), 1)                    AS mean_anc_visits,
        ROUND(AVG(dw.age_at_survey), 1)                 AS mean_age

    FROM dim_woman dw
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    GROUP BY dw.education_level
)
SELECT
    education_level,
    total_women,
    mean_age,
    mean_anc_visits,
    pct_zero_anc_wtd,
    pct_facility_delivery_wtd,
    pct_skilled_wtd,
    pct_distance_barrier_wtd,
    pct_insured_wtd,
    RANK() OVER (
        ORDER BY pct_facility_delivery_wtd DESC
    )                                                   AS facility_delivery_rank
FROM education_care
ORDER BY facility_delivery_rank;
-- QUERY 6 FINDINGS:
-- Higher education: 68.2% facility delivery, 2.4% zero ANC.
-- No education: 9.6% facility delivery, 46% zero ANC.
-- 7x facility delivery gap between highest and lowest education.
-- Education predicts care access independently of wealth.
-- Insurance nearly zero among uneducated women (0.3%).
-- Girls education is a direct maternal health intervention.



-- QUERY 7: Skilled Birth Attendant Coverage Trend by Year
-- Source: fact_birth, dim_woman, dim_geography
-- Clinical purpose: Determine whether skilled attendance at delivery is improving over time nationally and by zone.
-- Filters to births 2015-2024 for recent trend analysis.

WITH yearly_sba AS (
    SELECT
        fb.birth_year,
        dg.geopolitical_zone,
        COUNT(fb.birth_id)                              AS total_births,
        SUM(fb.skilled_attendant)                       AS skilled_births,
        ROUND(
            SUM(fb.skilled_attendant) * 100.0
            / NULLIF(COUNT(fb.birth_id), 0)
        , 1)                                            AS pct_skilled
    FROM fact_birth fb
    INNER JOIN dim_woman dw
        ON fb.woman_id = dw.woman_id
    INNER JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    WHERE fb.birth_year BETWEEN 2021 AND 2024
	AND fb.delivery_location IS NOT NULL
    GROUP BY
        fb.birth_year,
        dg.geopolitical_zone
),
national_yearly AS (
    SELECT
        birth_year,
        SUM(total_births)                               AS total_births,
        SUM(skilled_births)                             AS skilled_births,
        ROUND(
            SUM(skilled_births) * 100.0
            / NULLIF(SUM(total_births), 0)
        , 1)                                            AS national_pct_skilled,
        LAG(ROUND(
            SUM(skilled_births) * 100.0
            / NULLIF(SUM(total_births), 0)
        , 1)) OVER (ORDER BY birth_year)                AS prev_year_pct,
        ROUND(
            SUM(skilled_births) * 100.0
            / NULLIF(SUM(total_births), 0)
        , 1) -
        LAG(ROUND(
            SUM(skilled_births) * 100.0
            / NULLIF(SUM(total_births), 0)
        , 1)) OVER (ORDER BY birth_year)                AS yoy_change
    FROM yearly_sba
    GROUP BY birth_year
)
SELECT
    birth_year,
    total_births,
    national_pct_skilled,
    prev_year_pct,
    yoy_change,
    CASE
        WHEN yoy_change > 0  THEN 'Improving'
        WHEN yoy_change < 0  THEN 'Declining'
        WHEN yoy_change = 0  THEN 'Stable'
        ELSE                      'Baseline'
    END                                                 AS trend
FROM national_yearly
ORDER BY birth_year;	
-- QUERY 7 FINDINGS:
-- Skilled attendant coverage flat at 50-53% from 2021-2024.
-- No meaningful improvement trend nationally.
-- 2024 partial year -- 760 births only, treat with caution.
-- National average masks North-South divide confirmed in Query 3.
-- North West states averaging 14-25% skilled attendance while South West averages 83%.



-- QUERY 8: Distance Barrier and Insurance Gap by Zone
-- Sources: dim_woman, dim_geography, fact_anc_delivery
-- Clinical purpose: Map where financial and geographic barriers to care are most severe. Distance and cost are the two most
-- 	  commonly cited reasons Nigerian women avoid facility delivery.

WITH zone_barriers AS (
    SELECT
        dg.geopolitical_zone,
        COUNT(DISTINCT dw.woman_id)                     AS total_women,
        -- Distance barrier
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_distance_barrier,
        -- Insurance coverage
        ROUND(
            SUM(CASE WHEN dw.has_insurance = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_insured,
        -- Uninsured AND distance barrier -- double barrier
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                AND dw.has_insurance = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_double_barrier,
        -- Poorest and uninsured
        ROUND(
            SUM(CASE WHEN dw.wealth_index = 'Poorest'
                AND dw.has_insurance = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_poorest_uninsured,
        -- Zero ANC among those with distance barrier
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                AND fa.anc_visits = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN dw.distance_barrier = 1
                AND fa.anc_visits IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_zero_anc_among_distant,
        -- Facility delivery among those with distance barrier
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                AND fa.facility_delivery = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN dw.distance_barrier = 1
                AND fa.facility_delivery IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_facility_among_distant

    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    GROUP BY dg.geopolitical_zone
)
SELECT
    geopolitical_zone,
    total_women,
    pct_distance_barrier,
    pct_insured,
    pct_double_barrier,
    pct_poorest_uninsured,
    pct_zero_anc_among_distant,
    pct_facility_among_distant,
    RANK() OVER (
        ORDER BY pct_double_barrier DESC
    )                                                   AS barrier_rank
FROM zone_barriers
ORDER BY barrier_rank;
-- QUERY 8 FINDINGS:
-- South East: highest double barrier (30.8%) despite better care utilisation -- women overcoming barriers to reach care.
-- North West: 48.1% zero ANC among women with distance barrier -- distance completely blocking health system entry.
-- North East: 35% poorest uninsured -- cost and distance compounding simultaneously.
-- South West: even distant women achieve 56.6% facility delivery -- infrastructure makes barriers surmountable.



-- QUERY 9: Composite Obstetric Risk Score by State
-- Sources: All five DHS tables + dim_geography
-- Clinical purpose: Rank all 37 states by a composite score combining mortality burden, care access failure, poverty,
-- 	  and distance barriers into one actionable priority index. This is the query a ministry uses to decide where to deploy
-- 	  emergency obstetric care resources first.

WITH state_mortality AS (
    SELECT
        dg.state_name,
        COUNT(DISTINCT dw.woman_id)                     AS total_women,
        COUNT(DISTINCT CASE
            WHEN fm.pregnancy_related = 1
            THEN fm.mortality_id END)                   AS maternal_deaths,
        ROUND(
            COUNT(DISTINCT CASE
                WHEN fm.pregnancy_related = 1
                THEN fm.mortality_id END) * 1000.0
            / NULLIF(COUNT(DISTINCT dw.woman_id), 0)
        , 2)                                            AS death_rate
    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_maternal_mortality fm
        ON dw.woman_id = fm.woman_id
    GROUP BY dg.state_name
),
state_care AS (
    SELECT
        dg.state_name,
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                            AS pct_facility_delivery,
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(DISTINCT fa.anc_id), 0)
        , 1)                                            AS pct_zero_anc,
        ROUND(
            SUM(CASE WHEN dw.distance_barrier = 1
                AND dw.has_insurance = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_double_barrier,
        ROUND(
            SUM(CASE WHEN dw.wealth_index
                IN ('Poorest','Poor')
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS pct_poorest_poor
    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    GROUP BY dg.state_name
),
state_scores AS (
    -- Higher score = higher risk = higher priority
    -- Scoring logic:
    -- 	  Death rate contributes 35% of score
    -- 	  Zero ANC contributes 25% of score
    -- 	  No facility delivery contributes 25% of score
    -- 	  Double barrier contributes 15% of score
    -- 	  All components normalised to 0-100 scale
    SELECT
        sm.state_name,
        sm.total_women,
        sm.maternal_deaths,
        sm.death_rate,
        sc.pct_facility_delivery,
        sc.pct_zero_anc,
        sc.pct_double_barrier,
        sc.pct_poorest_poor,
        -- Composite score -- higher = worse
        ROUND(
            (sm.death_rate / 30.0 * 100 * 0.35) +
            (sc.pct_zero_anc * 0.25) +
            ((100 - sc.pct_facility_delivery) * 0.25) +
            (sc.pct_double_barrier * 0.15)
        , 1)                                            AS composite_risk_score
    FROM state_mortality sm
    JOIN state_care sc
        ON sm.state_name = sc.state_name
)
SELECT
    RANK() OVER (
        ORDER BY composite_risk_score DESC
    )                                                   AS priority_rank,
    state_name,
    total_women,
    maternal_deaths,
    death_rate,
    pct_facility_delivery,
    pct_zero_anc,
    pct_double_barrier,
    composite_risk_score
FROM state_scores
ORDER BY priority_rank;
-- QUERY 9 FINDINGS:
-- Zamfara: highest composite risk score (71.2) -- top priority.
-- Top 13 states all North West, North East, or North Central.
-- No southern state in top 13 -- geographic concentration total.
-- Enugu: anomaly in top 15 despite good access -- quality issue.
-- Plateau: low death count but high vulnerability score --
--   composite scoring captures latent risk not yet visible in mortality counts.
-- Lagos: safest state (13.3) -- facility delivery 73.4%.
-- Top 3 priority states: Zamfara, Kebbi, Sokoto -- all NW.



-- QUERY 10: Maternal Death Profile
-- Sources: fact_maternal_mortality, dim_woman, dim_geography
-- Clinical purpose: Describe who the women dying are -- their age, zone, wealth, education, and care history.
-- Compares women with pregnancy-related deaths against women with no recorded deaths to identify the profile of highest risk women.

WITH death_profile AS (
    SELECT
        dw.woman_id,
        dg.geopolitical_zone,
        dg.state_name,
        dw.education_level,
        dw.wealth_index,
        dw.has_insurance,
        dw.distance_barrier,
        dw.survey_weight,
        fa.anc_visits,
        fa.facility_delivery,
        fa.delivery_assisted_by,
        fm.pregnancy_related,
        fm.sibling_age_at_death,
        -- Classify each woman by death outcome
        CASE
            WHEN fm.pregnancy_related = 1 THEN 'Maternal Death'
            WHEN fm.pregnancy_related = 0 THEN 'Non-Maternal Death'
            WHEN fm.mortality_id IS NULL   THEN 'No Death Recorded'
            ELSE                                'Unknown'
        END                                             AS death_category
    FROM dim_woman dw
    JOIN dim_geography dg
        ON dw.state_id = dg.state_id
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    LEFT JOIN fact_maternal_mortality fm
        ON dw.woman_id = fm.woman_id
),
zone_death_summary AS (
    -- Summarise by zone and death category
    SELECT
        geopolitical_zone,
        death_category,
        COUNT(DISTINCT woman_id)                        AS women_count,
        ROUND(AVG(sibling_age_at_death), 1)             AS mean_age_at_death,
        ROUND(
            SUM(CASE WHEN education_level = 'None'
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(survey_weight), 0) * 100
        , 1)                                            AS pct_no_education,
        ROUND(
            SUM(CASE WHEN wealth_index
                IN ('Poorest','Poor')
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(survey_weight), 0) * 100
        , 1)                                            AS pct_poorest_poor,
        ROUND(
            SUM(CASE WHEN has_insurance = 1
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(survey_weight), 0) * 100
        , 1)                                            AS pct_insured,
        ROUND(
            SUM(CASE WHEN distance_barrier = 1
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(survey_weight), 0) * 100
        , 1)                                            AS pct_distance_barrier,
        ROUND(
            SUM(CASE WHEN facility_delivery = 1
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN facility_delivery
                IS NOT NULL
                THEN survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_facility_delivery,
        ROUND(
            SUM(CASE WHEN anc_visits = 0
                THEN survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN anc_visits
                IS NOT NULL
                THEN survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS pct_zero_anc
    FROM death_profile
    GROUP BY
        geopolitical_zone,
        death_category
)
SELECT
    geopolitical_zone,
    death_category,
    women_count,
    mean_age_at_death,
    pct_no_education,
    pct_poorest_poor,
    pct_insured,
    pct_distance_barrier,
    pct_facility_delivery,
    pct_zero_anc
FROM zone_death_summary
WHERE death_category = 'Maternal Death'
ORDER BY geopolitical_zone, women_count DESC;
-- QUERY 10 FINDINGS:
-- North: women dying outside facilities -- access failure.
--   NW: 11.5% facility delivery among maternal deaths.
--   NE: 8.8% facility delivery -- lowest in Nigeria.
--   Both zones: young (27-28), poor, uneducated, uninsured.
-- South: women dying inside facilities -- quality failure.
--   SW: 70.9% facility delivery among maternal deaths.
--   NC: 52.1% facility delivery among maternal deaths.
-- South East: oldest age at death (36.2) -- high parity
--   deaths, different clinical mechanism.
-- Core finding: North needs access interventions.
--   South needs quality of care interventions.
--   Same mortality burden, completely different solutions.

-- ============================================================


-- QUERY 11: DHS Findings vs WHO National Benchmarks
-- Sources: All DHS tables + who_nigeria_sba + who_nigeria_mmr
-- Clinical purpose: Contextualise DHS microdata findings against WHO national reference figures. Validates our
-- 	  analysis and shows where Nigeria stands against its own historical trajectory and global benchmarks.

WITH dhs_nationals AS (
    -- Calculate national figures from DHS microdata
    SELECT
        -- Facility delivery rate
        ROUND(
            SUM(CASE WHEN fa.facility_delivery = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.facility_delivery
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS dhs_facility_delivery,
        -- Skilled attendant rate recent births
        ROUND(
            SUM(CASE WHEN fb.skilled_attendant = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS dhs_skilled_attendant,
        -- Zero ANC rate
        ROUND(
            SUM(CASE WHEN fa.anc_visits = 0
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.anc_visits
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS dhs_zero_anc,
        -- Mean ANC visits
        ROUND(AVG(fa.anc_visits), 1)                    AS dhs_mean_anc,

        -- Insurance coverage
        ROUND(
            SUM(CASE WHEN dw.has_insurance = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(dw.survey_weight), 0) * 100
        , 1)                                            AS dhs_insurance,
        -- Confirmed maternal deaths
        COUNT(DISTINCT CASE
            WHEN fm.pregnancy_related = 1
            THEN fm.mortality_id END)                   AS dhs_maternal_deaths,
        -- Postnatal care
        ROUND(
            SUM(CASE WHEN fa.postnatal_check = 1
                THEN dw.survey_weight ELSE 0 END)
            / NULLIF(SUM(CASE WHEN fa.postnatal_check
                IS NOT NULL
                THEN dw.survey_weight ELSE 0 END), 0) * 100
        , 1)                                            AS dhs_postnatal_care

    FROM dim_woman dw
    LEFT JOIN fact_anc_delivery fa
        ON dw.woman_id = fa.woman_id
    LEFT JOIN fact_birth fb
        ON dw.woman_id = fb.woman_id
        AND fb.birth_year BETWEEN 2021 AND 2024
        AND fb.delivery_location IS NOT NULL
    LEFT JOIN fact_maternal_mortality fm
        ON dw.woman_id = fm.woman_id
),
who_reference AS (
    -- Pull most recent WHO reference figures
    SELECT
        MAX(CASE WHEN year = 2024
            THEN value END)                             AS who_sba_2024,
        MAX(CASE WHEN year = 2022
            THEN value END)                             AS who_sba_2022,
        MAX(CASE WHEN year = 2018
            THEN value END)                             AS who_sba_2018
    FROM who_nigeria_sba
    WHERE location = 'Nigeria'
),
who_mmr_ref AS (
    SELECT
        MAX(CASE WHEN year = 2023
            THEN mmr_value END)                         AS who_mmr_2023,
        MAX(CASE WHEN year = 2020
            THEN mmr_value END)                         AS who_mmr_2020,
        MAX(CASE WHEN year = 2015
            THEN mmr_value END)                         AS who_mmr_2015
    FROM who_nigeria_mmr
    WHERE location = 'Nigeria'
    AND indicator_code = 'MDG_0000000026'
)
SELECT
    'Skilled Birth Attendant (%)'       AS indicator,
    dn.dhs_skilled_attendant            AS dhs_value,
    wr.who_sba_2024                     AS who_2024,
    wr.who_sba_2022                     AS who_2022,
    wr.who_sba_2018                     AS who_2018,
    CASE
        WHEN dn.dhs_skilled_attendant
            BETWEEN wr.who_sba_2024 - 5
            AND wr.who_sba_2024 + 5
        THEN 'Consistent with WHO'
        WHEN dn.dhs_skilled_attendant
            < wr.who_sba_2024
        THEN 'Below WHO estimate'
        ELSE 'Above WHO estimate'
    END                                 AS vs_who_2024
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'Facility Delivery (%)',
    dn.dhs_facility_delivery,
    NULL, NULL, NULL,
    'DHS specific -- no direct WHO equivalent'
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'Zero ANC Attendance (%)',
    dn.dhs_zero_anc,
    NULL, NULL, NULL,
    'DHS specific -- no direct WHO equivalent'
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'Mean ANC Visits',
    dn.dhs_mean_anc,
    NULL, NULL, NULL,
    CASE
        WHEN dn.dhs_mean_anc >= 4
        THEN 'Meets WHO minimum of 4 visits'
        ELSE 'Below WHO minimum of 4 visits'
    END
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'Health Insurance Coverage (%)',
    dn.dhs_insurance,
    NULL, NULL, NULL,
    'Critically low -- systemic failure'
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'Postnatal Care Within 2 Days (%)',
    dn.dhs_postnatal_care,
    NULL, NULL, NULL,
    'DHS specific -- no direct WHO equivalent'
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr

UNION ALL

SELECT
    'MMR per 100,000 (WHO 2023)',
    wmr.who_mmr_2023,
    wmr.who_mmr_2023,
    wmr.who_mmr_2020,
    wmr.who_mmr_2015,
    CASE
        WHEN wmr.who_mmr_2023 > 70
        THEN 'Far above SDG target of 70'
        ELSE 'Meets SDG target'
    END
FROM dhs_nationals dn, who_reference wr, who_mmr_ref wmr;
-- QUERY 11 FINDINGS:
-- SBA: DHS 19.5% vs WHO 46% -- gap explained by older births in DHS with incomplete attendant data. Current figure
--   from Query 7 (2021-2024) is 50-52% -- consistent with WHO.
-- Facility delivery: 26.7% -- 73.3% of births outside facility.
-- Zero ANC: 27.5% -- 1 in 4 women with no health system contact.
-- Mean ANC: 4.3 -- meets WHO minimum nationally but masks severe North-South inequality.
-- Insurance: 3.2% -- near-zero coverage is a national failure.
-- Postnatal care: 16.2% -- critical gap in highest-risk window.
-- MMR: 992.8 vs SDG target of 70 -- 14x above target.
--   Improvement from 1,168 (2015) to 992.8 (2023) is real
--   but pace is insufficient to meet SDG 3.1 by 2030.

-- ============================================================

-- QUERY 12: Delivery Location Sector Analysis
-- Clinical purpose: Understand the distribution of delivery locations across government, private, and home settings
-- 	  by state and zone. Limited by DHS design to broad sector categories — not facility tier or accreditation level.

SELECT
    dg.geopolitical_zone,
    fa.delivery_assisted_by,
    COUNT(*) AS deliveries,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (
        PARTITION BY dg.geopolitical_zone
    ), 1) AS pct_within_zone
FROM fact_anc_delivery fa
INNER JOIN dim_woman dw ON fa.woman_id = dw.woman_id
INNER JOIN dim_geography dg ON dw.state_id = dg.state_id
WHERE fa.delivery_assisted_by IS NOT NULL
GROUP BY dg.geopolitical_zone, fa.delivery_assisted_by
ORDER BY dg.geopolitical_zone, deliveries DESC;
-- QUERY 12 FINDINGS:
-- NW: 74.7% of deliveries attended by nobody -- complete care absence.
-- NE: 60.7% no attendant -- majority of births in isolation.
-- SE: 72.4% nurse/midwife attended -- near-universal attendance
--     yet mortality remains high -- confirms quality failure.
-- SW: 39.1% doctor-attended -- highest in Nigeria -- sets benchmark.
-- Gradient mirrors mortality burden almost exactly.
-- This finding directly addresses the facility type dimension of the business question within DHS data limitations.
