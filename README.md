\# Nigeria Maternal Mortality Diagnostic Dashboard



\*\*Clinical Analytics Portfolio — Project 1 of 9\*\*



\[!\[SQL](https://img.shields.io/badge/SQL-MySQL%208.0-blue)]()

\[!\[Python](https://img.shields.io/badge/Python-3.12-green)]()

\[!\[Power BI](https://img.shields.io/badge/Power%20BI-May%202026-yellow)]()

\[!\[DHS](https://img.shields.io/badge/Data-Nigeria%20DHS%202024-red)]()

\[!\[License](https://img.shields.io/badge/License-MIT-lightgrey)]()



\*\*Muoneke Nwamba — Molecular Geneticist and Healthcare Data Analyst\*\*



Nigeria DHS 2024 | WHO Global Health Observatory | 39,050 Women | 37 States



\---



\## What This Project Is About



Nigeria accounts for roughly 20 percent of all maternal deaths in the world. For every 100,000 Nigerian women who give birth, 993 die. That figure stands 14 times above the global development target and has barely moved in a decade.



This project analyses microdata from the Nigeria Demographic and Health Survey 2024 to answer a specific question: which Nigerian states and facility types have the highest preventable maternal mortality, and what factors predict whether a woman delivers in a facility at all.



The answer is not what most people expect.



Nigeria does not have one maternal health crisis. It has two, and they require completely different interventions.



In the North West and North East, women are dying before they ever reach a health facility. 74.7 percent of North West deliveries happened with no attendant present at all. Not a doctor, not a nurse, not a midwife, not a traditional birth attendant. Nobody. In the three highest-risk states, between 61 and 72 percent of women received zero antenatal care during their entire pregnancy.



In the South West and North Central, a different problem is killing women. 70.9 percent of pregnancy-related deaths in the South West occurred in women who delivered in a health facility. They made it to a hospital or clinic. The facility could not save them.



This distinction matters because the interventions are different. Expanding access programmes in the South will not save women who are already reaching facilities and dying there. Investing in facility quality in the North will not save women who never reach a facility at all.



\---



\## The Business Question



Which Nigerian states and facility types have the highest preventable maternal mortality, and what demographic, geographic, and care-utilisation factors predict pregnancy-related death?



\---



\## Data Sources



| Source | Description | Coverage |

|--------|-------------|----------|

| Nigeria DHS 2024 | Individual Recode microdata | 39,050 women across 37 states |

| WHO GHO — Maternal Mortality Ratio | Modelled estimates with confidence intervals | Nigeria national trend 1985 to 2023 |

| WHO GHO — Skilled Birth Attendant | Survey-based national estimates | Nigeria national trend 2003 to 2024 |



The Nigeria DHS 2024 microdata is not included in this repository. The DHS Programme data use agreement prohibits public sharing of microdata. You can apply for your own access at dhsprogram.com. Registration is free and approval typically takes 24 to 48 hours. When downloading, select the Individual Recode in Stata format.



\---



\## Tools



| Stage | Tool |

|-------|------|

| Relational database | MySQL 8.0 |

| SQL analysis | MySQL Workbench |

| Data processing and modelling | Python 3.12 with Pandas, Scikit-learn, Matplotlib, Seaborn |

| Dashboard | Power BI Desktop May 2026 |



\---



\## Database Structure



The DHS Individual Recode comes as a wide flat file with over 6,000 columns. Rather than working with it directly, the data was structured into seven relational tables that mirror how a real health information system stores this kind of data. This structure enables multi-table SQL analysis that would not be possible on a flat file.



```

Table                           Rows      Description

dim\_geography                     74      37 states by urban and rural

dim\_woman                     39,050      one row per woman surveyed

fact\_birth                   104,557      full birth history per woman

fact\_anc\_delivery             13,968      antenatal and delivery care

fact\_maternal\_mortality        1,516      sibling deaths sisterhood method

who\_nigeria\_sba                    8      WHO skilled birth attendant trend

who\_nigeria\_mmr                   78      WHO maternal mortality ratio trend

```



Foreign key relationships connect all tables. All four referential integrity checks passed in the final verification with zero orphaned rows.



\---



\## SQL Analysis



The SQL file contains 12 documented queries. SQL was the primary analytical tool here, not a data loading utility. The queries answer specific clinical questions using CTEs, window functions, multi-table joins, survey-weighted aggregations, and CASE-based clinical classification.



\*\*File:\*\* sql/project1\_maternal\_mortality\_analysis.sql



A sample of the queries:



Query 1 uses LAG() to calculate year-on-year change in Nigeria's maternal mortality ratio from 1985 to 2023 and flag each year as improving, worsening, or stable.



Query 9 uses three CTEs and RANK() to build a composite obstetric risk score across all 37 states, combining maternal death rate, zero ANC attendance, facility delivery failure, and access barriers into a single prioritisation index. Zamfara ranked first at 71.2.



Query 10 joins five tables to compare facility delivery rates, age at death, education, and poverty levels between zones, which produced the core finding about the two different failure modes.



Query 12 uses a window function to calculate within-zone percentages of delivery attendant type, revealing that 74.7 percent of North West deliveries had no attendant present.



\---



\## Python Analysis



Four outputs were produced in Python after the SQL analysis was complete.



The first is an MMR trend chart with confidence interval bands from 1985 to 2023. Power BI cannot render shaded confidence interval bands natively, which is why this was done in Python.



The second is a care pathway funnel showing dropout at each stage from any ANC attendance through to postnatal care. Only 16.4 percent of women received a postnatal check within two days of delivery.



The third is a delivery attendant chart showing who was present at delivery across the six geopolitical zones.



The fourth is a dual-panel chart showing the ROC curve and feature importance from the predictive model.



\*\*Notebook:\*\* notebooks/project1\_nigeria\_maternal\_health.ipynb



\---



\## Predictive Model



A Random Forest and Logistic Regression model were built to predict facility delivery at the individual woman level.



| Metric | Value |

|--------|-------|

| Sample | 13,968 women with a birth in the last five years |

| Random Forest AUC | 0.824 |

| Logistic Regression AUC | 0.819 |

| Optimal threshold | 0.48 using Youden J statistic |

| Sensitivity at threshold | 80 percent |

| Class imbalance | Handled with class weight balanced |



The class weight adjustment was necessary because only 27.7 percent of women delivered in a facility. Without it, the model predicted home delivery for almost everyone and identified fewer than half of facility deliveries. After adjustment, it correctly identified 80 percent of facility deliveries.



Feature importance from the Random Forest showed education level as the strongest predictor at 0.255, ahead of wealth index at 0.219. This means education predicts facility delivery more strongly than income does, independently of all other factors. A woman with higher education is seven times more likely to deliver in a facility than a woman with no education, regardless of how much money she has. Girls education is a direct maternal health intervention.



\---



\## Dashboard



Five pages built in Power BI Desktop.



The first page shows six national KPI cards, the MMR trend from 1985 to 2023 with the SDG target line, and the care pathway funnel.



The second page shows a Nigeria choropleth map with composite risk scores by state, a zone comparison bar chart, and a top 15 state risk ranking. The North-South divide is immediately visible on the map.



The third page shows the wealth and education gradients through clustered bar charts and a scatter plot of poverty rate against facility delivery rate by state.



The fourth page shows the profile of women who are dying, including the facility delivery rate among maternal deaths by zone. This is where the access versus quality failure distinction is most clearly visible.



The fifth page shows zero ANC attendance and facility delivery rates for all 37 states with a zone slicer for filtering.



\*\*File:\*\* dashboard/project1\_nigeria\_maternal\_mortality\_dashboard.pbix



\---



\## Key Findings



Nigeria MMR in 2023 was 992.8 per 100,000 live births, 14 times above the SDG 3.1 target of 70 by 2030. The best single-year improvement in the 38-year dataset was 46 points. Reaching 70 by 2030 would require approximately 130 points of annual reduction. That is not achievable at current pace.



27.7 percent of Nigerian women with a recent birth delivered in a facility. 27.5 percent attended zero antenatal visits. 49.2 percent delivered with no attendant present. Only 3.2 percent had health insurance.



In the North West, only 11.5 percent of women who died of pregnancy-related causes had delivered in a facility. In the South West, 70.9 percent had. Same mortality burden. Different problems. Different solutions.



The five states requiring immediate emergency designation based on composite risk scoring are Zamfara at 71.2, Kebbi at 58.0, Sokoto at 57.9, Bauchi at 47.5, and Gombe at 46.5.



\---



\## Recommendation



Designate Zamfara, Kebbi, Sokoto, Bauchi, and Gombe as Maternal Health Emergency States and deploy two parallel interventions.



For the North West and North East, the priority is access. Mobile antenatal care teams, conditional transport subsidies to the nearest emergency obstetric care facility, and community health workers targeting women with zero antenatal contact.



For the South West, South East, and North Central, the priority is quality. Blood bank infrastructure, emergency obstetric care equipment, mandatory staff competency training in haemorrhage and eclampsia management, and facility accreditation tied to National Health Insurance Authority reimbursement.



\---



\## Genetics Note



The predictive model captures socioeconomic and behavioural factors. It does not capture biological risk. HbSS genotype, G6PD deficiency, and pre-eclampsia susceptibility variants in genes STOX1, ACVR2A, and FLT1 represent unmeasured biological risk in this population. A future model incorporating genomic risk scores would strengthen the clinical utility of the predictions.



\---



\## How to Reproduce



Create the MySQL database and run the notebook sections in order. The notebook handles everything from loading the DHS file to populating all seven tables and running the full verification check. You will need to apply for DHS 2024 access separately.



```bash

mysql -u root -p -e "CREATE DATABASE nigeria\_maternal\_health;"



pip install pandas sqlalchemy pymysql pyreadstat scikit-learn matplotlib seaborn geopandas folium mapclassify



jupyter notebook notebooks/project1\_nigeria\_maternal\_health.ipynb

```



\---



\## Repository Structure



```

nigeria-maternal-mortality-dashboard/

├── README.md

├── sql/

│   └── project1\_maternal\_mortality\_analysis.sql

├── notebooks/

│   └── project1\_nigeria\_maternal\_health.ipynb

├── data/

│   ├── who\_sba\_nigeria.csv

│   └── who\_mmr\_nigeria.csv

├── powerbi\_data/

│   ├── national\_kpis.csv

│   ├── mmr\_trend.csv

│   ├── care\_pathway\_funnel.csv

│   ├── zone\_summary.csv

│   ├── state\_risk\_scores.csv

│   ├── wealth\_disaggregation.csv

│   ├── education\_disaggregation.csv

│   ├── death\_profile\_zone.csv

│   └── delivery\_attendant\_zone.csv

├── charts/

│   ├── mmr\_trend.png

│   ├── care\_pathway\_funnel.png

│   ├── delivery\_attendant\_zone.png

│   └── roc\_feature\_importance.png

└── dashboard/

&#x20;   └── project1\_nigeria\_maternal\_mortality\_dashboard.pbix

```



\---



\## About



This is Project 1 of a 9-project clinical analytics portfolio. The projects cover maternal mortality in Nigeria, diagnostic lab operations in Nigeria, antimicrobial resistance in West Africa, HIV treatment retention in Nigeria, healthcare facility access in Nigeria, PCR cost-effectiveness in Nigeria, the opioid crisis in the United States, mental health treatment gaps in the European Union, and chronic disease burden among Indigenous Australians.



The portfolio is built to a standard where health ministries, research institutions, and international health organisations can use the outputs directly.



\---



Muoneke Nwamba

Molecular Geneticist and Healthcare Data Analyst

github.com/Neksperfect

