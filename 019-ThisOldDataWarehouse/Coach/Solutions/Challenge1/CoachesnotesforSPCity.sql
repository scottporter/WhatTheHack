--This code set is for educational purposes only.  Encourage students to use the scripts in /Scripts folder to create the stored procedures.  Feel free to share with students once they complete it but don't deploy these scripts into production.

--DROP PROCEDURE [Integration].[MigrateStagedCityData] 

CREATE PROCEDURE [Integration].[MigrateStagedCityData] 

/* Part 0 - comment out execute as owner.  Not supported in Azure Synapse Analytics*/
--WITH EXECUTE AS OWNER 

AS 

BEGIN 

    SET NOCOUNT ON; 

    SET XACT_ABORT ON; 

 

    DECLARE @EndOfTime datetime2(7) =  '99991231 23:59:59.9999999'; 

 

    BEGIN TRAN; 

 

    DECLARE @LineageKey int = (SELECT TOP(1) [Lineage Key] 

                               FROM Integration.Lineage 

                               WHERE [Table Name] = N'City' 

                               AND [Data Load Completed] IS NULL 

                               ORDER BY [Lineage Key] DESC); 

 

/*  Part 1 - close off old records for Slowing Changing Dimensions Type II  

    My fixes here are to use a CTAS as a Temporary table instad of a CTE  

*/ 

    /*  

--Common Table expression
WITH RowsToCloseOff 

    AS 

    ( 

        SELECT c.[WWI City ID], MIN(c.[Valid From]) AS [Valid From] 

        FROM Integration.City_Staging AS c 

        GROUP BY c.[WWI City ID] 

    ) 

    UPDATE c 

        SET c.[Valid To] = rtco.[Valid From] 

    FROM Dimension.City AS c 

    INNER JOIN RowsToCloseOff AS rtco 

    ON c.[WWI City ID] = rtco.[WWI City ID] 

    WHERE c.[Valid To] = @EndOfTime; 

*/ 
--Create Table as Selet (CTAS) as a replacement for CTE
 

CREATE TABLE Integration.City_Staging_Temp 

WITH (DISTRIBUTION = REPLICATE) 

AS  

SELECT c.[WWI City ID], MIN(c.[Valid From]) AS [Valid From] 

    FROM Integration.City_Staging AS c 

    GROUP BY c.[WWI City ID] 

 
 --ANSI JOINS not supported in Synapse.  Replace with implicit join in the WHERE clause.
UPDATE Dimension.City 

SET c.[Valid To] = rtco.[Valid From] 

    FROM Integration.City_Staging_Temp AS rtco 

    WHERE c.[WWI City ID] = rtco.[WWI City ID]  

AND c.[Valid To] = @EndOfTime; 

/*  Part 2 - Insert dimension records to staging  

No changes 

*/ 

    INSERT Dimension.City 

        ([WWI City ID], City, [State Province], Country, Continent, 

         [Sales Territory], Region, Subregion, [Location], 

         [Latest Recorded Population], [Valid From], [Valid To], 

         [Lineage Key]) 

    SELECT [WWI City ID], City, [State Province], Country, Continent, 

           [Sales Territory], Region, Subregion, [Location], 

           [Latest Recorded Population], [Valid From], [Valid To], 

           @LineageKey 

    FROM Integration.City_Staging; 

 

 

/* Part 3 - Update Load Control tables  

   Just commented out the unnecessary from statement 

*/ 

    UPDATE Integration.Lineage 

        SET [Data Load Completed] = SYSDATETIME(), 

            [Was Successful] = 1 

    WHERE [Lineage Key] = @LineageKey; 

 

 

    UPDATE Integration.[ETL Cutoff] 

        SET [Cutoff Time] = (SELECT TOP 1 [Source System Cutoff Time] 

                             FROM Integration.Lineage 

                             WHERE [Lineage Key] = @LineageKey) 

    --FROM Integration.[ETL Cutoff] 

    WHERE [Table Name] = N'City' 

 

 

/* Step 4 - clean up the CTAS table   

   Added this statement to cleanup the CTAS table that was used instead of a CTE 

*/ 

DROP TABLE Integration.City_Staging_Temp 

 

    COMMIT; 

 

/* Part 4 - comment out return statment, they're unsupported by Azure Synapse */ 

    --RETURN 0 

 

END 