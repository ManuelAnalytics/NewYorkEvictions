
SELECT *
FROM [dbo].[legislators]

SELECT *
FROM [dbo].[legislators_terms]


SELECT id_bioguide,
	   min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide
ORDER BY id_bioguide, first_term
-- Defining Cohort

-- Join Method

WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)

SELECT DATEDIFF(YEAR,first_term,term_start) AS period, count(distinct a.id_bioguide)
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
GROUP BY DATEDIFF(YEAR,first_term,b.term_start)
ORDER BY period




---Windows function Method

SELECT DATEDIFF(YEAR,first_term,term_start) AS period, COUNT(DISTINCT id_bioguide) as cohort_retained
FROM(
SELECT id_bioguide,
first_value(term_start) OVER (PARTITION BY id_bioguide
							  ORDER BY term_start) AS first_term,
							  term_start
FROM [dbo].[legislators_terms]
) AS a
GROUP BY DATEDIFF(YEAR,first_term,term_start)
ORDER BY period;




/* Let's first define our cohort as years served (first term start- term start).
From there we will find out how much Legislators are in each cohort (years served) and then 
divide the orginal cohort by the cohort size for each period */


CREATE OR ALTER VIEW dbo.Legislator_Basic_Retention
AS

WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)
,
b AS (
SELECT DATEDIFF(YEAR,first_term,term_start) AS period
	  ,count(distinct a.id_bioguide) AS cohort_retained
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
GROUP BY DATEDIFF(YEAR,first_term,b.term_start)
)
SELECT period
, FIRST_VALUE(cohort_retained) OVER (ORDER BY period) AS cohort_size
, cohort_retained
, CONVERT(DECIMAL(8,2),cohort_retained)/ 
  CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (ORDER BY period)) AS pct_retained
FROM b

GO


SELECT @@SERVERNAME



---- Let's reshape the data as pivot table with years 0-4
--- This can help with analyzing the data a bit better



WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)
,
b AS (
SELECT DATEDIFF(YEAR,first_term,term_start) AS period
	  ,count(distinct a.id_bioguide) AS cohort_retained
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
GROUP BY DATEDIFF(YEAR,first_term,b.term_start)
)
,c AS(
SELECT period
, FIRST_VALUE(cohort_retained) OVER (ORDER BY period) AS cohort_size
, cohort_retained
, CONVERT(DECIMAL(8,2),cohort_retained)/ 
  CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (ORDER BY period)) AS pct_retained
FROM b
)
SELECT cohort_size
	   , MAX(CASE WHEN period = 0 THEN pct_retained END) AS year_0
	   , MAX(CASE WHEN period = 1 THEN pct_retained END) AS year_1
	   , MAX(CASE WHEN period = 2 THEN pct_retained END) AS year_2
	   , MAX(CASE WHEN period = 3 THEN pct_retained END) AS year_3
	   , MAX(CASE WHEN period = 4 THEN pct_retained END) AS year_4
FROM c
GROUP BY cohort_size;



--- Let's create a date dimension table


SELECT generate_series:: date as date
FROM generate_series('1770-12-31','2023-12-31', interval '1 year')


SELECT value
FROM GENERATE_SERIES ( '1770-12-31' , '2020-12-31' ,1) 

CREATE OR ALTER VIEW dbo.CalendarTable 
AS 

WITH dates AS (
SELECT CONVERT(DATE,DATEADD(DAY, value, '1770-01-01')) AS Calendar_Date
FROM GENERATE_SERIES(0, DATEDIFF(DAY, '1770-12-31', '2024-12-31'))
)

SELECT Calendar_Date, DATEPART(DAY,Calendar_Date) AS day_of_month, DATEPART(YEAR,Calendar_Date) AS year, DATEPART(Month,Calendar_Date) AS month
		   , DATENAME(Month,Calendar_Date) AS month_name
FROM dates
GO



--- Let's add a date to cohort data
--- This basically counts the period by years instead of first term - term start

CREATE OR ALTER VIEW dbo.AccurateRetention
AS

WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)

--,shaped_data AS
--(
SELECT a.id_bioguide, a.first_term
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
)
, shaped_data_1 
AS
(
SELECT COALESCE(DATEDIFF(YEAR, first_term,Calendar_Date),0) AS period,
	   COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR,first_term, Calendar_Date),0)
)
SELECT period
,FIRST_VALUE(cohort_retained) OVER (ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (ORDER BY period)) AS pct_retained
FROM shaped_data_1

GO



SELECT @@SERVERNAME;


--Practice
-- Creating artifical end dates if date set does not contain one



WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)

SELECT a.id_bioguide, a.first_term,
	   b.term_start, b.term_type,
	   CASE 
	   WHEN b.term_type = 'rep'  THEN DATEADD(YEAR,2,term_start)
	   WHEN b.term_type = 'SEN'  THEN DATEADD(YEAR,6,term_start)
	   END AS term_end
FROM a 
INNER JOIN [dbo].[legislators_terms] AS b
ON b.id_bioguide = a.id_bioguide;

--- Although this code would be useful if we did not have an end date and we know how long legislators serve
--- It fails to capture if a legislator did not finish full 2 or 6 year term 
---because of things like death, promotion, etc.




CREATE OR ALTER VIEW dbo.YearlyLegislatorCohort
AS

WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)
,
shaped_data AS
(
SELECT a.id_bioguide, a.first_term
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
)
, shaped_data_1 
AS
(
SELECT DATEPART(YEAR,first_term) AS first_year,
	   COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period,
	   COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR,first_term, year_end),0), DATEPART(YEAR,first_term)
)
SELECT 
first_year
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_year
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_year ORDER BY period)) AS pct_retained
FROM shaped_data_1
ORDER BY first_year;

GO

--*Data is cohorted by over 200 years, much too many to graph but maybe useful in other analysis 
--where just a few years are selected.

--- Let's instead do this by century which makes the data less granular and easeir to graph

CREATE OR ALTER VIEW dbo.CenturyLegislatorRetention
AS

WITH a AS
(SELECT id_bioguide, min(term_start) AS first_term
FROM [dbo].[legislators_terms]
GROUP BY id_bioguide)
,
shaped_data AS
(
SELECT a.id_bioguide, a.first_term
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
)
, shaped_data_1 
AS
(
SELECT ((DATEPART(YEAR,first_term)-1)/100 + 1) AS first_century,
	   COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period,
	   COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR,first_term, year_end),0), ((DATEPART(YEAR,first_term)-1)/100 + 1)
)
SELECT 
first_century
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_century
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_century ORDER BY period)) AS pct_retained
FROM shaped_data_1
ORDER BY first_century


GO



WITH a AS
(SELECT id_bioguide
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
,first_value(state) OVER (PARTITION BY id_bioguide
						  ORDER BY term_start) AS first_state
FROM [dbo].[legislators_terms])

--- Get the first term started for each legislator 
---as well as the first state they've served in
,
shaped_data AS
(
SELECT a.id_bioguide, a.first_term
	   ,a.first_state
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
)

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
, shaped_data_1 
AS
(
SELECT first_state
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	   ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0), first_state
)

--Count each legislator by period and state

SELECT 
first_state
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state 
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
ORDER BY first_state

--Divide the amount of legislators in a period and state by 
--the very first value for that cohort

-- Before we do our analysis, let's figure out which states had the most amount 
--of legislators?
--- This way we can limit the data to just those states, 
-- and that helps with reducing noise in the data when we plot it in our visual tool.

SELECT TOP 5
COUNT(id_bioguide) AS num_of_leg, state
FROM [dbo].[legislators_terms]
GROUP BY state
ORDER BY num_of_leg desc;

--- Get the first term started for each legislator 
---as well as the first state they've served in

CREATE OR ALTER VIEW dbo.FirstStateRetention
AS

WITH a AS
(SELECT id_bioguide
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
,first_value(state) OVER (PARTITION BY id_bioguide
						  ORDER BY term_start) AS first_state
FROM [dbo].[legislators_terms])

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
,shaped_data AS
(
SELECT a.id_bioguide, a.first_term
	   ,a.first_state
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
)

--Count each legislator by period and state
, shaped_data_1 
AS
(
SELECT first_state
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	   ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0), first_state
)

--Divide the amount of legislators in a period and state by 
--the very first value for that cohort
SELECT 
first_state
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state 
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
WHERE 
shaped_data_1.first_state IN (
SELECT TOP 3 state
FROM [dbo].[legislators_terms]
GROUP BY state
ORDER BY COUNT(id_bioguide) desc
)

GO


select @@SERVERNAME


---- Retention by Gender
CREATE OR ALTER VIEW dbo.GenderRetention
AS
WITH a AS
(SELECT id_bioguide
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
FROM [dbo].[legislators_terms])

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
,shaped_data AS
(
SELECT a.id_bioguide, a.first_term 
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
	   ,d.gender
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
JOIN [dbo].[legislators] AS d 
ON d.id_bioguide = a.id_bioguide
)

--Count each legislator by period and state
, shaped_data_1 
AS
(
SELECT gender
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	   ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0), gender
)

--Divide the amount of legislators in a period and gender by 
--the very first value for that cohort
SELECT 
gender
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY gender
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY gender
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
GO

--- Let's make this comparison more fair by restricting to only 
---legislators whose first_term started since there have been women in Congress

CREATE OR ALTER VIEW dbo.GenderRetention1917to2000
AS
WITH a AS
(SELECT id_bioguide
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
FROM [dbo].[legislators_terms])

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
,shaped_data AS
(
SELECT a.id_bioguide, a.first_term 
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
	   ,d.gender
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
JOIN [dbo].[legislators] AS d 
ON d.id_bioguide = a.id_bioguide
WHERE a.first_term between '1917-01-01' and '1999-12-31'
)

--Count each legislator by period and state
, shaped_data_1 
AS
(
SELECT gender
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	  ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0)
,gender
)

--Divide the amount of legislators in a period and gender by 
--the very first value for that cohort
SELECT 
gender
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY gender
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY gender
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
GO


----

WITH a AS
(SELECT id_bioguide
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
,first_value(state) OVER (PARTITION BY id_bioguide
						  ORDER BY term_start) AS first_state
FROM [dbo].[legislators_terms])

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
,shaped_data AS
(
SELECT a.id_bioguide, a.first_term 
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
	   ,d.gender, a.first_state
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
JOIN [dbo].[legislators] AS d 
ON d.id_bioguide = a.id_bioguide
WHERE a.first_term between '1917-01-01' and '1999-12-31'
)

--Count each legislator by period and state
, shaped_data_1 
AS
(
SELECT gender
	   ,first_state
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	   ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0), gender, first_state
)

--Divide the amount of legislators in a period and gender by 
--the very first value for that cohort
SELECT 
gender
,first_state
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state,gender
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state,gender
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
ORDER BY first_state,gender, period




--- Working with sparse cohorts

WITH a AS
(SELECT id_bioguide
,FIRST_VALUE(state) OVER (PARTITION BY id_bioguide
						  ORDER BY term_start) AS first_state
,min(term_start) OVER (PARTITION BY id_bioguide) AS first_term
FROM [dbo].[legislators_terms])

-- Get each term start and each term end
--Get a date for each year served to have more accurate periods
,shaped_data AS
(
SELECT a.id_bioguide, a.first_term 
	   ,b.term_start, b.term_end
	   ,c.Calendar_Date AS year_end
	   ,d.gender
	   ,a.first_state
FROM a
JOIN [dbo].[legislators_terms] AS b
ON a.id_bioguide = b.id_bioguide
LEFT JOIN [dbo].[CalendarTable] AS c
ON c.Calendar_Date between b.term_start and b.term_end
AND c.month_name = 'December' and c.day_of_month = 31
JOIN [dbo].[legislators] AS d 
ON d.id_bioguide = a.id_bioguide
WHERE a.first_term between '1917-01-01' and '1999-12-31'
)

--Count each legislator by period and state
, shaped_data_1 
AS
(
SELECT gender
	  ,first_state
	   ,COALESCE(DATEDIFF(YEAR, first_term,year_end),0) AS period
	  ,COUNT(DISTINCT id_bioguide) AS cohort_retained
FROM shaped_data
GROUP BY COALESCE(DATEDIFF(YEAR, first_term,year_end),0),first_state
,gender
)

SELECT 
gender
,first_state
,period
,FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state,gender
									ORDER BY period) AS cohort_size
,cohort_retained
,CONVERT(DECIMAL(8,2),cohort_retained)/
CONVERT(DECIMAL(8,2),FIRST_VALUE(cohort_retained) OVER (PARTITION BY first_state,gender
														ORDER BY period)) AS pct_retained
FROM shaped_data_1
ORDER BY first_state,gender, period