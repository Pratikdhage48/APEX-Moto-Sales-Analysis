/*==============================================================================
  Project     : APEX Moto Sales Analysis
  Script      : 04_Business Analysis.sql
  Purpose     : Advanced business-analysis queries -- CTEs, window functions,
                ranking, views, a stored procedure, running totals, YoY,
                Top-N, and RFM segmentation.
  Engine      : Microsoft SQL Server 2022

  Contents
  --------
  SECTION A - Reusable Views (01-03)
  SECTION B - Sales Trend & Time Intelligence (04-11)
  SECTION C - Product Analysis (12-19)
  SECTION D - Customer Analysis (20-27)
  SECTION E - Territory Analysis (28-31)
  SECTION F - Return Analysis (32-35)
  SECTION G - RFM Segmentation (36-38)
  SECTION H - Stored Procedure (39)
  SECTION I - Misc Advanced / Top-N (40-42)
==============================================================================*/

USE ApexMotoSales;
GO

/*==============================================================================
  SECTION A -- REUSABLE VIEWS
==============================================================================*/

-- 01. vw_SalesEnriched: one-stop denormalized view joining every dimension.
--     Used as the base for most queries below.
CREATE OR ALTER VIEW dbo.vw_SalesEnriched AS
SELECT
    s.SalesID,
    s.OrderDate,
    s.OrderNumber,
    s.OrderQuantity,
    s.OrderLineItem,
    p.ProductKey,
    p.ProductName,
    p.ModelName,
    p.ProductColor,
    p.ProductCost,
    p.ProductPrice,
    p.ProductMargin,
    sc.SubcategoryName,
    cat.CategoryName,
    c.CustomerKey,
    c.FullName        AS CustomerName,
    c.Gender,
    c.MaritalStatus,
    c.AnnualIncome,
    c.IncomeBand,
    c.Age,
    c.Occupation,
    c.EducationLevel,
    t.Region,
    t.Country,
    t.Continent,
    cal.[Year],
    cal.[Quarter],
    cal.[Month],
    cal.MonthName,
    (s.OrderQuantity * p.ProductPrice)                       AS Revenue,
    (s.OrderQuantity * p.ProductCost)                        AS COGS,
    (s.OrderQuantity * (p.ProductPrice - p.ProductCost))     AS Profit
FROM fact.Sales s
JOIN dim.Product p               ON s.ProductKey  = p.ProductKey
JOIN dim.ProductSubcategory sc    ON p.ProductSubcategoryKey = sc.ProductSubcategoryKey
JOIN dim.ProductCategory cat      ON sc.ProductCategoryKey = cat.ProductCategoryKey
JOIN dim.Customer c               ON s.CustomerKey = c.CustomerKey
JOIN dim.Territory t              ON s.TerritoryKey = t.SalesTerritoryKey
JOIN dim.Calendar cal             ON s.OrderDate    = cal.[Date];
GO

-- 02. vw_ReturnsEnriched
CREATE OR ALTER VIEW dbo.vw_ReturnsEnriched AS
SELECT
    r.ReturnID,
    r.ReturnDate,
    r.ReturnQuantity,
    p.ProductKey,
    p.ProductName,
    sc.SubcategoryName,
    cat.CategoryName,
    t.Region,
    t.Country,
    (r.ReturnQuantity * p.ProductPrice) AS ReturnedRevenueValue
FROM fact.Returns r
JOIN dim.Product p            ON r.ProductKey = p.ProductKey
JOIN dim.ProductSubcategory sc ON p.ProductSubcategoryKey = sc.ProductSubcategoryKey
JOIN dim.ProductCategory cat   ON sc.ProductCategoryKey = cat.ProductCategoryKey
JOIN dim.Territory t           ON r.TerritoryKey = t.SalesTerritoryKey;
GO

-- 03. vw_MonthlySales: pre-aggregated monthly KPI view
CREATE OR ALTER VIEW dbo.vw_MonthlySales AS
SELECT
    [Year], [Month], MonthName,
    SUM(Revenue)  AS TotalRevenue,
    SUM(Profit)   AS TotalProfit,
    COUNT(DISTINCT OrderNumber) AS TotalOrders,
    SUM(OrderQuantity) AS TotalUnits
FROM dbo.vw_SalesEnriched
GROUP BY [Year], [Month], MonthName;
GO


/*==============================================================================
  SECTION B -- SALES TREND & TIME INTELLIGENCE
==============================================================================*/

-- 04. Overall KPI summary (headline card numbers for the report)
SELECT
    SUM(Revenue)                          AS TotalRevenue,
    SUM(Profit)                           AS TotalProfit,
    COUNT(DISTINCT OrderNumber)           AS TotalOrders,
    SUM(OrderQuantity)                    AS TotalUnitsSold,
    COUNT(DISTINCT CustomerKey)           AS TotalCustomers,
    CAST(SUM(Profit) AS DECIMAL(12,2)) / SUM(Revenue) * 100 AS ProfitMarginPct
FROM dbo.vw_SalesEnriched;
GO

-- 05. Yearly sales trend
SELECT [Year], SUM(Revenue) AS TotalRevenue, SUM(Profit) AS TotalProfit,
       COUNT(DISTINCT OrderNumber) AS TotalOrders
FROM dbo.vw_SalesEnriched
GROUP BY [Year]
ORDER BY [Year];
GO

-- 06. Monthly sales trend (chronological)
SELECT [Year], [Month], MonthName, SUM(Revenue) AS TotalRevenue
FROM dbo.vw_SalesEnriched
GROUP BY [Year], [Month], MonthName
ORDER BY [Year], [Month];
GO

-- 07. Year-over-Year growth % using LAG() window function
WITH YearlyRevenue AS (
    SELECT [Year], SUM(Revenue) AS TotalRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY [Year]
)
SELECT
    [Year],
    TotalRevenue,
    LAG(TotalRevenue) OVER (ORDER BY [Year])                       AS PriorYearRevenue,
    TotalRevenue - LAG(TotalRevenue) OVER (ORDER BY [Year])        AS YoY_Change,
    CAST(
        (TotalRevenue - LAG(TotalRevenue) OVER (ORDER BY [Year]))
        * 100.0 / LAG(TotalRevenue) OVER (ORDER BY [Year])
    AS DECIMAL(6,2))                                                AS YoY_GrowthPct
FROM YearlyRevenue
ORDER BY [Year];
GO

-- 08. Month-over-Month growth % within each year
WITH MonthlyRevenue AS (
    SELECT [Year], [Month], MonthName, SUM(Revenue) AS TotalRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY [Year], [Month], MonthName
)
SELECT
    [Year], [Month], MonthName, TotalRevenue,
    LAG(TotalRevenue) OVER (PARTITION BY [Year] ORDER BY [Month])  AS PriorMonthRevenue,
    CAST(
        (TotalRevenue - LAG(TotalRevenue) OVER (PARTITION BY [Year] ORDER BY [Month]))
        * 100.0 / LAG(TotalRevenue) OVER (PARTITION BY [Year] ORDER BY [Month])
    AS DECIMAL(6,2))                                                AS MoM_GrowthPct
FROM MonthlyRevenue
ORDER BY [Year], [Month];
GO

-- 09. Running total (cumulative) revenue over time - window function
SELECT
    [Year], [Month], MonthName,
    SUM(Revenue) AS MonthlyRevenue,
    SUM(SUM(Revenue)) OVER (ORDER BY [Year], [Month]) AS CumulativeRevenue
FROM dbo.vw_SalesEnriched
GROUP BY [Year], [Month], MonthName
ORDER BY [Year], [Month];
GO

-- 10. Weekday vs weekend sales performance
SELECT
    cal.WeekdayFlag,
    CASE WHEN cal.WeekdayFlag = 1 THEN 'Weekday' ELSE 'Weekend' END AS DayType,
    SUM(v.Revenue) AS TotalRevenue,
    COUNT(DISTINCT v.OrderNumber) AS TotalOrders
FROM dbo.vw_SalesEnriched v
JOIN dim.Calendar cal ON v.OrderDate = cal.[Date]
GROUP BY cal.WeekdayFlag;
GO

-- 11. Seasonality: average revenue by calendar month across all years
SELECT [Month], MonthName, AVG(TotalRevenue) AS AvgMonthlyRevenue
FROM dbo.vw_MonthlySales
GROUP BY [Month], MonthName
ORDER BY [Month];
GO


/*==============================================================================
  SECTION C -- PRODUCT ANALYSIS
==============================================================================*/

-- 12. Revenue and profit by category
SELECT CategoryName, SUM(Revenue) AS TotalRevenue, SUM(Profit) AS TotalProfit,
       SUM(OrderQuantity) AS UnitsSold
FROM dbo.vw_SalesEnriched
GROUP BY CategoryName
ORDER BY TotalRevenue DESC;
GO

-- 13. Revenue by subcategory (top 15)
SELECT TOP 15 SubcategoryName, CategoryName, SUM(Revenue) AS TotalRevenue
FROM dbo.vw_SalesEnriched
GROUP BY SubcategoryName, CategoryName
ORDER BY TotalRevenue DESC;
GO

-- 14. Top 10 products by revenue - ranking with RANK()
SELECT ProductName,
       RANK() OVER (ORDER BY SUM(Revenue) DESC) AS RevenueRank,
       SUM(Revenue) AS TotalRevenue,
       SUM(OrderQuantity) AS UnitsSold
FROM dbo.vw_SalesEnriched
GROUP BY ProductName
ORDER BY RevenueRank
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
GO

-- 15. Bottom 10 products by revenue (still sold at least once)
SELECT ProductName,
       SUM(Revenue) AS TotalRevenue,
       SUM(OrderQuantity) AS UnitsSold
FROM dbo.vw_SalesEnriched
GROUP BY ProductName
ORDER BY TotalRevenue ASC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
GO

-- 16. Top product within EACH category - ROW_NUMBER() partitioned ranking
WITH RankedProducts AS (
    SELECT
        CategoryName, ProductName, SUM(Revenue) AS TotalRevenue,
        ROW_NUMBER() OVER (PARTITION BY CategoryName ORDER BY SUM(Revenue) DESC) AS rnk
    FROM dbo.vw_SalesEnriched
    GROUP BY CategoryName, ProductName
)
SELECT CategoryName, ProductName, TotalRevenue
FROM RankedProducts
WHERE rnk = 1
ORDER BY TotalRevenue DESC;
GO

-- 17. Pareto / 80-20 analysis: cumulative % of revenue by product
WITH ProductRevenue AS (
    SELECT ProductName, SUM(Revenue) AS TotalRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY ProductName
),
Ranked AS (
    SELECT
        ProductName, TotalRevenue,
        SUM(TotalRevenue) OVER (ORDER BY TotalRevenue DESC) AS RunningRevenue,
        SUM(TotalRevenue) OVER ()                            AS GrandTotalRevenue
    FROM ProductRevenue
)
SELECT
    ProductName, TotalRevenue,
    CAST(RunningRevenue * 100.0 / GrandTotalRevenue AS DECIMAL(6,2)) AS CumulativeRevenuePct
FROM Ranked
ORDER BY TotalRevenue DESC;
GO

-- 18. ABC analysis: classify products into A (top 70% rev), B (next 20%), C (last 10%)
WITH ProductRevenue AS (
    SELECT ProductName, SUM(Revenue) AS TotalRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY ProductName
),
Ranked AS (
    SELECT
        ProductName, TotalRevenue,
        SUM(TotalRevenue) OVER (ORDER BY TotalRevenue DESC) * 100.0
            / SUM(TotalRevenue) OVER ()                        AS CumulativePct
    FROM ProductRevenue
)
SELECT
    ProductName, TotalRevenue,
    CASE
        WHEN CumulativePct <= 70 THEN 'A'
        WHEN CumulativePct <= 90 THEN 'B'
        ELSE 'C'
    END AS ABC_Class
FROM Ranked
ORDER BY TotalRevenue DESC;
GO

-- 19. Product profitability: margin % by product (highest margin first)
SELECT ProductName,
       ProductPrice, ProductCost,
       CAST((ProductPrice - ProductCost) * 100.0 / ProductPrice AS DECIMAL(6,2)) AS MarginPct
FROM dim.Product
ORDER BY MarginPct DESC;
GO


/*==============================================================================
  SECTION D -- CUSTOMER ANALYSIS
==============================================================================*/

-- 20. Top 10 customers by lifetime revenue
SELECT TOP 10 CustomerName, SUM(Revenue) AS LifetimeRevenue, COUNT(DISTINCT OrderNumber) AS OrderCount
FROM dbo.vw_SalesEnriched
GROUP BY CustomerName
ORDER BY LifetimeRevenue DESC;
GO

-- 21. Revenue by gender
SELECT Gender, SUM(Revenue) AS TotalRevenue, COUNT(DISTINCT CustomerKey) AS CustomerCount,
       CAST(SUM(Revenue) / COUNT(DISTINCT CustomerKey) AS DECIMAL(10,2)) AS RevenuePerCustomer
FROM dbo.vw_SalesEnriched
GROUP BY Gender;
GO

-- 22. Revenue by income band
SELECT IncomeBand, SUM(Revenue) AS TotalRevenue, COUNT(DISTINCT CustomerKey) AS CustomerCount
FROM dbo.vw_SalesEnriched
GROUP BY IncomeBand
ORDER BY TotalRevenue DESC;
GO

-- 23. Revenue by age band (CASE-based bucketing)
SELECT
    CASE
        WHEN Age < 25              THEN 'Under 25'
        WHEN Age BETWEEN 25 AND 34 THEN '25-34'
        WHEN Age BETWEEN 35 AND 44 THEN '35-44'
        WHEN Age BETWEEN 45 AND 54 THEN '45-54'
        WHEN Age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65+'
    END AS AgeBand,
    SUM(Revenue) AS TotalRevenue,
    COUNT(DISTINCT CustomerKey) AS CustomerCount
FROM dbo.vw_SalesEnriched
GROUP BY
    CASE
        WHEN Age < 25              THEN 'Under 25'
        WHEN Age BETWEEN 25 AND 34 THEN '25-34'
        WHEN Age BETWEEN 35 AND 44 THEN '35-44'
        WHEN Age BETWEEN 45 AND 54 THEN '45-54'
        WHEN Age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65+'
    END
ORDER BY TotalRevenue DESC;
GO

-- 24. Revenue by occupation and education level
SELECT Occupation, EducationLevel, SUM(Revenue) AS TotalRevenue
FROM dbo.vw_SalesEnriched
GROUP BY Occupation, EducationLevel
ORDER BY TotalRevenue DESC;
GO

-- 25. Customer purchase frequency segments (one-time vs repeat buyers)
WITH CustomerOrders AS (
    SELECT CustomerKey, COUNT(DISTINCT OrderNumber) AS OrderCount
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey
)
SELECT
    CASE WHEN OrderCount = 1 THEN 'One-Time Buyer' ELSE 'Repeat Buyer' END AS CustomerType,
    COUNT(*) AS CustomerCount
FROM CustomerOrders
GROUP BY CASE WHEN OrderCount = 1 THEN 'One-Time Buyer' ELSE 'Repeat Buyer' END;
GO

-- 26. Customer lifetime value ranking with NTILE (quartile segmentation)
WITH CustomerRevenue AS (
    SELECT CustomerKey, CustomerName, SUM(Revenue) AS LifetimeRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey, CustomerName
)
SELECT
    CustomerName, LifetimeRevenue,
    NTILE(4) OVER (ORDER BY LifetimeRevenue DESC) AS RevenueQuartile   -- 1 = top spenders
FROM CustomerRevenue
ORDER BY LifetimeRevenue DESC;
GO

-- 27. Average order value (AOV) by marital status
SELECT MaritalStatus,
       SUM(Revenue) / COUNT(DISTINCT OrderNumber) AS AvgOrderValue
FROM dbo.vw_SalesEnriched
GROUP BY MaritalStatus;
GO


/*==============================================================================
  SECTION E -- TERRITORY ANALYSIS
==============================================================================*/

-- 28. Revenue by country
SELECT Country, SUM(Revenue) AS TotalRevenue, SUM(Profit) AS TotalProfit
FROM dbo.vw_SalesEnriched
GROUP BY Country
ORDER BY TotalRevenue DESC;
GO

-- 29. Revenue by region within country
SELECT Country, Region, SUM(Revenue) AS TotalRevenue
FROM dbo.vw_SalesEnriched
GROUP BY Country, Region
ORDER BY Country, TotalRevenue DESC;
GO

-- 30. Territory contribution % of total company revenue
WITH TerritoryRevenue AS (
    SELECT Region, SUM(Revenue) AS TotalRevenue
    FROM dbo.vw_SalesEnriched
    GROUP BY Region
)
SELECT
    Region, TotalRevenue,
    CAST(TotalRevenue * 100.0 / SUM(TotalRevenue) OVER () AS DECIMAL(6,2)) AS ContributionPct
FROM TerritoryRevenue
ORDER BY TotalRevenue DESC;
GO

-- 31. Best-selling category per continent
WITH CatByContinent AS (
    SELECT Continent, CategoryName, SUM(Revenue) AS TotalRevenue,
           ROW_NUMBER() OVER (PARTITION BY Continent ORDER BY SUM(Revenue) DESC) AS rnk
    FROM dbo.vw_SalesEnriched
    GROUP BY Continent, CategoryName
)
SELECT Continent, CategoryName, TotalRevenue
FROM CatByContinent
WHERE rnk = 1;
GO


/*==============================================================================
  SECTION F -- RETURN ANALYSIS
==============================================================================*/

-- 32. Overall return rate (units returned / units sold)
SELECT
    (SELECT SUM(ReturnQuantity) FROM fact.Returns)      AS TotalUnitsReturned,
    (SELECT SUM(OrderQuantity)  FROM fact.Sales)        AS TotalUnitsSold,
    CAST((SELECT SUM(ReturnQuantity) FROM fact.Returns) * 100.0
         / (SELECT SUM(OrderQuantity) FROM fact.Sales) AS DECIMAL(6,2)) AS ReturnRatePct;
GO

-- 33. Return rate by product category
SELECT
    cat.CategoryName,
    ISNULL(SUM(r.ReturnQuantity), 0)                            AS UnitsReturned,
    SUM(s.OrderQuantity)                                        AS UnitsSold,
    CAST(ISNULL(SUM(r.ReturnQuantity), 0) * 100.0 / SUM(s.OrderQuantity) AS DECIMAL(6,2)) AS ReturnRatePct
FROM fact.Sales s
JOIN dim.Product p            ON s.ProductKey = p.ProductKey
JOIN dim.ProductSubcategory sc ON p.ProductSubcategoryKey = sc.ProductSubcategoryKey
JOIN dim.ProductCategory cat   ON sc.ProductCategoryKey = cat.ProductCategoryKey
LEFT JOIN fact.Returns r      ON r.ProductKey = p.ProductKey
GROUP BY cat.CategoryName
ORDER BY ReturnRatePct DESC;
GO

-- 34. Top 10 most-returned products
SELECT TOP 10 ProductName, SUM(ReturnQuantity) AS TotalReturned, SUM(ReturnedRevenueValue) AS ReturnedValue
FROM dbo.vw_ReturnsEnriched
GROUP BY ProductName
ORDER BY TotalReturned DESC;
GO

-- 35. Monthly return trend vs sales trend (side-by-side comparison)
SELECT
    cal.[Year], cal.[Month], cal.MonthName,
    ISNULL(SUM(r.ReturnQuantity), 0) AS UnitsReturned,
    (SELECT SUM(s2.OrderQuantity) FROM fact.Sales s2
      WHERE YEAR(s2.OrderDate) = cal.[Year] AND MONTH(s2.OrderDate) = cal.[Month]) AS UnitsSold
FROM fact.Returns r
JOIN dim.Calendar cal ON r.ReturnDate = cal.[Date]
GROUP BY cal.[Year], cal.[Month], cal.MonthName
ORDER BY cal.[Year], cal.[Month];
GO


/*==============================================================================
  SECTION G -- RFM SEGMENTATION (Recency, Frequency, Monetary)
==============================================================================*/

-- 36. Raw RFM metrics per customer
WITH RFM_Base AS (
    SELECT
        CustomerKey,
        CustomerName,
        DATEDIFF(DAY, MAX(OrderDate), (SELECT MAX(OrderDate) FROM dbo.vw_SalesEnriched)) AS Recency,
        COUNT(DISTINCT OrderNumber)                                                      AS Frequency,
        SUM(Revenue)                                                                     AS Monetary
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey, CustomerName
)
SELECT * FROM RFM_Base ORDER BY Monetary DESC;
GO

-- 37. RFM scoring (1-5 scale per dimension via NTILE) and combined score
WITH RFM_Base AS (
    SELECT
        CustomerKey, CustomerName,
        DATEDIFF(DAY, MAX(OrderDate), (SELECT MAX(OrderDate) FROM dbo.vw_SalesEnriched)) AS Recency,
        COUNT(DISTINCT OrderNumber) AS Frequency,
        SUM(Revenue) AS Monetary
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey, CustomerName
),
RFM_Scored AS (
    SELECT
        CustomerKey, CustomerName, Recency, Frequency, Monetary,
        NTILE(5) OVER (ORDER BY Recency ASC)     AS R_Score,     -- lower recency (days) = better = 5
        NTILE(5) OVER (ORDER BY Frequency DESC)  AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary DESC)   AS M_Score
    FROM RFM_Base
)
SELECT
    CustomerKey, CustomerName, Recency, Frequency, Monetary,
    R_Score, F_Score, M_Score,
    (R_Score + F_Score + M_Score) AS RFM_Total
FROM RFM_Scored
ORDER BY RFM_Total DESC;
GO

-- 38. RFM customer segmentation labels (Champions / Loyal / At Risk / Lost)
WITH RFM_Base AS (
    SELECT
        CustomerKey, CustomerName,
        DATEDIFF(DAY, MAX(OrderDate), (SELECT MAX(OrderDate) FROM dbo.vw_SalesEnriched)) AS Recency,
        COUNT(DISTINCT OrderNumber) AS Frequency,
        SUM(Revenue) AS Monetary
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey, CustomerName
),
RFM_Scored AS (
    SELECT
        CustomerKey, CustomerName,
        NTILE(5) OVER (ORDER BY Recency ASC)    AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency DESC) AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary DESC)  AS M_Score
    FROM RFM_Base
)
SELECT
    CustomerKey, CustomerName, R_Score, F_Score, M_Score,
    CASE
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champions'
        WHEN R_Score >= 3 AND F_Score >= 3                  THEN 'Loyal Customers'
        WHEN R_Score <= 2 AND F_Score >= 3                  THEN 'At Risk'
        WHEN R_Score <= 2 AND F_Score <= 2                  THEN 'Lost'
        ELSE 'Potential Loyalist'
    END AS RFM_Segment
FROM RFM_Scored
ORDER BY M_Score DESC;
GO


/*==============================================================================
  SECTION H -- STORED PROCEDURE
==============================================================================*/

-- 39. usp_GetSalesByDateRange: parametrized reusable sales report
CREATE OR ALTER PROCEDURE dbo.usp_GetSalesByDateRange
    @StartDate DATE,
    @EndDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        CategoryName,
        SUM(Revenue)  AS TotalRevenue,
        SUM(Profit)   AS TotalProfit,
        COUNT(DISTINCT OrderNumber) AS TotalOrders
    FROM dbo.vw_SalesEnriched
    WHERE OrderDate BETWEEN @StartDate AND @EndDate
    GROUP BY CategoryName
    ORDER BY TotalRevenue DESC;
END
GO

-- Example execution:
-- EXEC dbo.usp_GetSalesByDateRange @StartDate = '2022-01-01', @EndDate = '2022-06-30';


/*==============================================================================
  SECTION I -- MISC ADVANCED / TOP-N
==============================================================================*/

-- 40. Top 5 products by revenue PER YEAR (partitioned Top-N)
WITH YearlyProductRevenue AS (
    SELECT [Year], ProductName, SUM(Revenue) AS TotalRevenue,
           ROW_NUMBER() OVER (PARTITION BY [Year] ORDER BY SUM(Revenue) DESC) AS rnk
    FROM dbo.vw_SalesEnriched
    GROUP BY [Year], ProductName
)
SELECT [Year], ProductName, TotalRevenue
FROM YearlyProductRevenue
WHERE rnk <= 5
ORDER BY [Year], TotalRevenue DESC;
GO

-- 41. First purchase date and days-to-second-purchase per customer (LEAD)
WITH OrderedPurchases AS (
    SELECT
        CustomerKey, OrderNumber, OrderDate,
        ROW_NUMBER() OVER (PARTITION BY CustomerKey ORDER BY OrderDate) AS PurchaseSeq
    FROM dbo.vw_SalesEnriched
    GROUP BY CustomerKey, OrderNumber, OrderDate
)
SELECT
    CustomerKey, OrderDate AS FirstPurchaseDate,
    LEAD(OrderDate) OVER (PARTITION BY CustomerKey ORDER BY OrderDate) AS SecondPurchaseDate,
    DATEDIFF(DAY, OrderDate, LEAD(OrderDate) OVER (PARTITION BY CustomerKey ORDER BY OrderDate)) AS DaysToRepeat
FROM OrderedPurchases
WHERE PurchaseSeq = 1;
GO

-- 42. Products frequently bought in the same order (basic market-basket pairing)
SELECT
    a.ProductName AS ProductA,
    b.ProductName AS ProductB,
    COUNT(*)      AS TimesPairedTogether
FROM dbo.vw_SalesEnriched a
JOIN dbo.vw_SalesEnriched b
    ON a.OrderNumber = b.OrderNumber
   AND a.ProductName < b.ProductName          -- avoid double-counting/self-pairs
GROUP BY a.ProductName, b.ProductName
HAVING COUNT(*) > 1
ORDER BY TimesPairedTogether DESC;
GO

PRINT 'Business analysis queries, views, and stored procedure created successfully.';
