# 🏍️ APEX Moto Sales Analysis

An end-to-end data analytics portfolio project covering **SQL Server database design, Python data cleaning & EDA, and Power BI dashboarding** — built on three years (2020–2022) of APEX Moto sales, customer, product, and returns data.

> **Tech Stack:** Microsoft SQL Server 2022 · Python (Pandas, Numpy, Matplotlib, Seaborn) · Jupyter Notebook · Power BI . Excel

---

## 📌 Project Overview

APEX Moto's raw sales exports (three separate yearly CSVs, plus customer/product/territory lookups) needed to be consolidated, cleaned, modeled, and analyzed to answer core business questions: *Which products and regions drive revenue? Who are our best customers? Where are we losing money to returns?*

This project builds the full pipeline from raw CSV → SQL Server star schema → Python EDA → interactive Power BI dashboard, and documents every data-quality issue found along the way.

**Dataset at a glance**
| Metric | Value |
|---|---|
| Sales transactions (line items) | 56,046 |
| Unique orders | 25,164 |
| Date range | Jan 1, 2020 – Jun 30, 2022 |
| Unique customers | 18,148 (post-cleaning) |
| Unique products | 293 |
| Countries / Territories | 6 / 10 |

---

## 🗂️ Project Structure

```
APEX-Moto-Sales-Analysis
│
├── Dataset
│   ├── Raw Data              # Original, unmodified CSV exports
│   └── Cleaned Data           # Analysis-ready CSVs produced by 01_Data_Cleaning.ipynb
│
├── SQL
│   ├── 01_Database Creation.sql    # Schemas, staging tables, star-schema DDL
│   ├── 02_Data Import.sql          # BULK INSERT scripts (raw CSV -> staging)
│   ├── 03_Data Cleaning.sql        # Staging -> cleaned dim/fact tables
│   └── 04_Business Analysis.sql    # 40+ queries: CTEs, window functions, RFM, views, a stored procedure
│
├── Python
│   ├── 01_Data_Cleaning.ipynb      # Load, merge, clean, feature-engineer
│   └── 02_EDA.ipynb                # 27 visualizations across 8 analysis areas
│
├── Power BI
│   └── Apex Moto Report.pbix       # Interactive multi-page dashboard
│
├── Images                          # Dashboard screenshots for this README
├── README.md
└── requirements.txt
```

---

## 🧹 Data Cleaning — What Was Actually Wrong With the Data

Rather than assume the raw data was clean, both the SQL and Python pipelines were built to detect and document real issues found during inspection:

| Issue | Where | Fix |
|---|---|---|
| Customer file encoded as **Windows-1252**, not UTF-8 | `ApexMoto_Customer_Lookup.csv` | Explicit `encoding='latin1'` / `CODEPAGE='1252'` on load |
| **6 corrupted trailer rows** — 3 rows with `CustomerKey = '30---'`, 1 blank row, and 2 export-tool footer lines (`"Export date 20230101..."`, `"Source AW_Cust_Master"`) | Customer Lookup | Detected via numeric coercion (`pd.to_numeric(..., errors='coerce')`) and dropped — 18,154 → 18,148 valid customers |
| 50 missing `ProductColor` values | Product Lookup | Recoded to `'Unknown'` rather than dropped (products still valid) |
| Scattered nulls in `Gender`, `MaritalStatus`, `HomeOwner`, `Occupation`, `EducationLevel` | Customer Lookup | Recoded to `'Unknown'`/`'U'` — customers kept, since dropping them would discard valid transaction history |
| Three separate yearly sales files | Sales Data | Concatenated into a single fact table, tagged with `SourceYear` for traceability |
| 300 customers (1.65%) flagged as income outliers via IQR | Customer Lookup | Kept intentionally — these are real high-income customers, not data errors; removing them would bias revenue-per-customer analysis |

Full detail and code are in [`01_Data_Cleaning.ipynb`](Python/01_Data_Cleaning.ipynb) and [`03_Data Cleaning.sql`](SQL/03_Data%20Cleaning.sql).

---

## 🗄️ SQL Highlights

Built on **Microsoft SQL Server 2022** using a `stg` → `dim`/`fact` star-schema pattern:

- **Star schema**: `dim.Customer`, `dim.Product`, `dim.ProductCategory`, `dim.ProductSubcategory`, `dim.Territory`, `dim.Calendar`, `fact.Sales`, `fact.Returns` — with FK constraints and indexing on all join/filter columns.
- **40+ business-analysis queries** covering:
  - Sales trend, YoY & MoM growth (`LAG()`), running totals, seasonality
  - Product Pareto (80/20) and ABC classification
  - Customer segmentation via **RFM analysis** (Recency, Frequency, Monetary) with `NTILE()` scoring
  - Territory/geographic contribution %, category performance
  - Return-rate analysis by category and product
  - A parametrized stored procedure (`usp_GetSalesByDateRange`) for on-demand reporting
  - Reusable views (`vw_SalesEnriched`, `vw_ReturnsEnriched`, `vw_MonthlySales`)

See [`SQL/`](SQL/) for all scripts.

---

## 🐍 Python Highlights

**`01_Data_Cleaning.ipynb`** — loads all 10 raw CSVs, merges the 3 yearly sales files, runs a full null/duplicate audit, fixes the issues above, engineers features (`Age`, `AgeBand`, `IncomeBand`, `ProductMargin`, `OrderYearMonth`), and exports 6 cleaned CSVs.

**`02_EDA.ipynb`** — 27 visualizations across 8 sections: sales trend & seasonality, product/category/Pareto/ABC analysis, customer demographics (gender, income, age, occupation), geography, returns, and a correlation heatmap + scatterplots + boxplots.

Both notebooks run end-to-end without modification against the raw data in `Dataset/Raw Data/`.

---

## 📊 Key Findings

- **$24.9M** in total revenue and **$10.5M** in profit across the analysis window — a **42.0%** overall profit margin.
- Revenue grew **45.6%** from 2020 to 2021. 2022 (Jan–Jun only, partial year) is roughly flat against the same period, not a decline — the raw 2022 export simply stops at June 30.
- **Bikes** is the dominant category (**$23.6M**, ~95% of revenue) — Accessories and Clothing drive most of the *order volume* (as seen in the Power BI report) but far less revenue per order.
- **26.9%** of products generate 80% of total revenue (confirmed Pareto effect); ABC segmentation puts 27 products in Class A (70% of revenue) vs. 75 long-tail products in Class C (10% of revenue).
- **United States** is the top country by revenue (**$7.9M**), consistent across the multi-year window.
- Overall **return rate is 2.17%** (1,828 of 84,174 units sold) — helmets and mountain-bike accessories skew highest, consistent with the Power BI report's return-rate breakdown.
- Customer income shows only a weak correlation (**r ≈ 0.16**) with total revenue per customer — income band alone is a poor predictor of customer value.

---

## 📈 Power BI Dashboard

`Power BI/Apex Moto Report.pbix` is a 4-page interactive report (Sales Overview, Geography, Product Deep-Dive, Customer Insights) built on the same data model as the SQL/Python pipeline, with 25+ DAX measures (rolling revenue, adjusted price/profit simulation, YTD, targets, RFM-adjacent segments).

See [`Images/`](Images/) for report screenshots.

---

## ⚙️ How to Reproduce This Project

1. **SQL Server**: Run the scripts in `SQL/` in order (`01` → `04`) against SQL Server 2022. Update the file paths in `02_Data Import.sql` to point at your local `Dataset/Raw Data/` folder.
2. **Python**: 
   ```bash
   pip install -r requirements.txt
   jupyter notebook Python/01_Data_Cleaning.ipynb   # run first
   jupyter notebook Python/02_EDA.ipynb              # run second
   ```
3. **Power BI**: Open `Power BI/Apex Moto Report.pbix` in Power BI Desktop.

---

## 📄 License

This project uses a publicly available sample retail dataset (rebranded as "APEX Moto") for educational/portfolio purposes.
