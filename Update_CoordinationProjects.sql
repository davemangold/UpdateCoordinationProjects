USE [Utility]
GO
/****** Object:  StoredProcedure [dbo].[Update_CoordinationProjectBuffers]    Script Date: 8/17/2018 7:38:48 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[Update_CoordinationProjectBuffers] AS

BEGIN

DECLARE
	@FoCallYears		int = -5,
	@InspectionYears	int = -5,
	@DetailReportRoot varchar(max) = 'http://biprod.usa.org/ReportServer/Pages/ReportViewer.aspx?/SSRS/Reports/GIS/'


/* UPDATE PROJECT INFORMATION */

-- update washington county projects
UPDATE	ProjectBuffer
SET		ProjectBuffer.ProjectName = CountyProject.ProjectName
		,ProjectBuffer.AnticipatedDesignStart = CountyProject.AnticipatedDesignStartDate
		,ProjectBuffer.AnticipatedConstructionStart = CountyProject.AnticipatedConstructionStartDate
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,[SQLLINK].[SharePointStage].[sp].[v_CapitalProjects.CountyCapitalProjectsPrelimAssessment] CountyProject
WHERE	ProjectBuffer.SharePointId = CountyProject.SharePointId
		AND ProjectBuffer.ProjectType = 'Washington County'

-- update storm high priority projects
UPDATE	ProjectBuffer
SET		ProjectBuffer.ProjectName = StormHiPriorityProject.ProjectName
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,[SQLLINK].[SharePointStage].[sp].[v_CapitalProjects.HighPriorityStormProjects] StormHiPriorityProject
WHERE	ProjectBuffer.SharePointId = StormHiPriorityProject.SharePointId
		AND ProjectBuffer.ProjectType = 'CWS High Priority Storm'

/* UPDATE SANI INSPECTION FIELDS */

-- select inspection history into temp table
SELECT	*
INTO	#SaniInspectionHistory
FROM	sde_common.gis.FOSANITVINSPECTIONHISTORY

-- update SRID on inspection history
UPDATE	#SaniInspectionHistory
SET		SHAPE.STSrid = 2913

-- select summary of intersecting inspection history into temp table
SELECT		ProjectBuffer.SharePointId
			,ISNULL(MAX(#SaniInspectionHistory.SaniStrQuickRating), '0000') SaniMaxQuickRating
			,ISNULL(SUM(
                CASE 
				WHEN    InspectionDate < DATEADD(year,@InspectionYears,GETDATE()) 
                        OR InspectionDate IS NULL 
                THEN    1 
                ELSE    0 
                END
                ), 0) SaniNoInspectionCount
			,ISNULL(SUM(#SaniInspectionHistory.IniObservationCount), 0) SaniObservedIandICount
			,ISNULL(SUM(#SaniInspectionHistory.StructuralObservationCount), 0) SaniStructuralDefectCount
INTO		#SaniInspectionHistorySummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			#SaniInspectionHistory
ON			ProjectBuffer.SHAPE.STIntersects(#SaniInspectionHistory.SHAPE) = 1
GROUP BY	SharePointId

-- update inspection history counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniMaxQuickRating = #SaniInspectionHistorySummary.SaniMaxQuickRating
		,ProjectBuffer.SaniNoInspectionCount = #SaniInspectionHistorySummary.SaniNoInspectionCount
		,ProjectBuffer.SaniObservedIandICount = #SaniInspectionHistorySummary.SaniObservedIandICount
		,ProjectBuffer.SaniStructuralDefectCount = #SaniInspectionHistorySummary.SaniStructuralDefectCount
FROM	#SaniInspectionHistorySummary
		,sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
WHERE	#SaniInspectionHistorySummary.SharePointId = ProjectBuffer.SharePointId


/* UPDATE STORM INSPECTION FIELDS */

-- select inspection history into temp table
SELECT	*
INTO	#StormInspectionHistory
FROM	sde_common.gis.FOSTORMTVINSPECTIONHISTORY

-- update SRID on inspection history
UPDATE	#StormInspectionHistory
SET		SHAPE.STSrid = 2913

-- summarize intesecting inspection history and select into temp table
SELECT		ProjectBuffer.SharePointId
			,ISNULL(MAX(#StormInspectionHistory.StrQuickRating), '0000') StormMaxQuickRating
			,ISNULL(SUM(
                CASE 
                WHEN    InspectionDate < DATEADD(year,@InspectionYears,GETDATE()) 
                        OR InspectionDate IS NULL 
                THEN    1 
                ELSE    0 
                END
                ), 0) StormNoInspectionCount
INTO		#StormInspectionHistorySummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			#StormInspectionHistory
ON			ProjectBuffer.SHAPE.STIntersects(#StormInspectionHistory.SHAPE) = 1
GROUP BY	SharePointId

-- update inspection history counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.StormMaxQuickRating = #StormInspectionHistorySummary.StormMaxQuickRating
		,ProjectBuffer.StormNoInspectionCount = #StormInspectionHistorySummary.StormNoInspectionCount
FROM	#StormInspectionHistorySummary
		,sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
WHERE	#StormInspectionHistorySummary.SharePointId = ProjectBuffer.SharePointId


/* UPDATE SANI LINE COUNTS */

UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniLineCount = SaniLineSummary.SaniLineCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,(
		SELECT		SharePointId
					,SUM(
                        CASE 
                        WHEN ProjectBuffer.SHAPE.STIntersects(SaniLines.SHAPE) = 1 THEN 1 ELSE 0 
                        END
                        ) SaniLineCount
		FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
					LEFT OUTER JOIN
					sde_common.gis.SANITARYLINESALL SaniLines
		ON			ProjectBuffer.SHAPE.STIntersects(SaniLines.SHAPE) = 1
		GROUP BY	ProjectBuffer.SharePointId
		) AS SaniLineSummary
WHERE	ProjectBuffer.SharePointId = SaniLineSummary.SharePointId


/* UPDATE SANI STRUCTURE COUNTS */

UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniStructureCount = SaniStructureSummary.SaniStructureCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,(
		SELECT		SharePointId
					,SUM(
                        CASE 
                        WHEN ProjectBuffer.SHAPE.STIntersects(SaniStructures.SHAPE) = 1 THEN 1 ELSE 0 
                        END
                        ) SaniStructureCount
		FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
					LEFT OUTER JOIN
					sde_common.gis.SANITARYSTRUCTURESALL SaniStructures
		ON			ProjectBuffer.SHAPE.STIntersects(SaniStructures.SHAPE) = 1
		GROUP BY	ProjectBuffer.SharePointId
		) AS SaniStructureSummary
WHERE	ProjectBuffer.SharePointId = SaniStructureSummary.SharePointId


/* UPDATE STORM LINE COUNTS */

UPDATE	ProjectBuffer
SET		ProjectBuffer.StormLineCount = StormLineSummary.StormLineCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,(
		SELECT		SharePointId
					,SUM(
                        CASE 
                        WHEN ProjectBuffer.SHAPE.STIntersects(StormLines.SHAPE) = 1 THEN 1 ELSE 0 
                        END
                        ) StormLineCount
		FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
					LEFT OUTER JOIN
					sde_common.gis.STORMLINESALL StormLines
		ON			ProjectBuffer.SHAPE.STIntersects(StormLines.SHAPE) = 1
		GROUP BY	ProjectBuffer.SharePointId
		) AS StormLineSummary
WHERE	ProjectBuffer.SharePointId = StormLineSummary.SharePointId


/* UPDATE STORM STRUCTURE COUNTS */

UPDATE	ProjectBuffer
SET		ProjectBuffer.StormStructureCount = StormStructureSummary.StormStructureCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,(
		SELECT		SharePointId
					,SUM(
                        CASE 
                        WHEN ProjectBuffer.SHAPE.STIntersects(StormStructures.SHAPE) = 1 THEN 1 ELSE 0 
                        END
                        ) StormStructureCount
		FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
					LEFT OUTER JOIN
					sde_common.gis.STORMSTRUCTURESALL StormStructures
		ON			ProjectBuffer.SHAPE.STIntersects(StormStructures.SHAPE) = 1
		GROUP BY	ProjectBuffer.SharePointId
		) AS StormStructureSummary
WHERE	ProjectBuffer.SharePointId = StormStructureSummary.SharePointId


/* UPDATE CIP PROJECT COUNTS */

-- select cip projects into temp table
SELECT	ProjectBoundary.UniversalProjectId
		,ProjectBoundary.SHAPE
INTO	#CipProject
FROM	sde_rm.gis.PROJECTBOUNDARY_EVW ProjectBoundary
		,SQLLINK.BiApps.pm.Project CipProject
WHERE	CipProject.IsCapitalProject = 'Y'
		AND ProjectBoundary.UniversalProjectId = CipProject.ProjectId

-- update SRID on cip projects
UPDATE	#CipProject
SET		SHAPE.STSrid = 2913

-- select summary of intersecting cip projects into temp table
SELECT		ProjectBuffer.SharePointId
			,SUM(
                CASE 
                WHEN ProjectBuffer.SHAPE.STIntersects(#CipProject.SHAPE) = 1 THEN 1 ELSE 0 
                END
                ) CipProjectCount
INTO		#CipProjectSummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			#CipProject
ON			ProjectBuffer.SHAPE.STIntersects(#CipProject.SHAPE) = 1
GROUP BY	ProjectBuffer.SharePointId

-- update cip project counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.CipProjectCount = #CipProjectSummary.CipProjectCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#CipProjectSummary
WHERE	ProjectBuffer.SharePointId = #CipProjectSummary.SharePointId


/* UPDATE WORK REQUEST COUNTS */

-- select historical work requests
SELECT	*
INTO	#WorkRequest
FROM	sde_common.gis.FOWORKREQUESTS
WHERE	RequestDate > DATEADD(year,@FoCallYears,GETDATE())

-- update SRID on historical work requests
UPDATE	#WorkRequest
SET		SHAPE.STSrid = 2913

-- select summary of intersecting work requests into temp table
SELECT		ProjectBuffer.SharePointId
			,#WorkRequest.LineOfBusiness
			,SUM(
                CASE 
                WHEN ProjectBuffer.SHAPE.STIntersects(#WorkRequest.SHAPE) = 1 THEN 1 ELSE 0 
                END
                ) WorkRequestCount
INTO		#WorkRequestSummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			#WorkRequest
ON			ProjectBuffer.SHAPE.STIntersects(#WorkRequest.SHAPE) = 1
GROUP BY	ProjectBuffer.SharePointId
			,#WorkRequest.LineOfBusiness

-- update sani historical work request counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniFoCallCount = ISNULL(#WorkRequestSummary.WorkRequestCount, 0)
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		LEFT OUTER JOIN
		#WorkRequestSummary
ON		ProjectBuffer.SharePointId = #WorkRequestSummary.SharePointId
		AND (#WorkRequestSummary.LineOfBusiness = 'Sanitary' 
			OR #WorkRequestSummary.LineOfBusiness IS NULL)

-- update storm historical work request counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.StormFoCallCount = ISNULL(#WorkRequestSummary.WorkRequestCount, 0)
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		LEFT OUTER JOIN
		#WorkRequestSummary
ON		ProjectBuffer.SharePointId = #WorkRequestSummary.SharePointId
		AND (#WorkRequestSummary.LineOfBusiness = 'Storm' 
			OR #WorkRequestSummary.LineOfBusiness IS NULL)


/* UPDATE PCSWMM PRIORITY LINE COUNTS */

-- select pcswmm priority conduits into temp table
SELECT	*
INTO	#PcswmmPriorityLine
FROM	sde_common.gis.PROJECTPRIORITY

-- update SRID on pcswmm priority conduits
UPDATE	#PcswmmPriorityLine
SET		SHAPE.STSrid = 2913

-- select summary of intersecting pcswmm priority conduits into temp table
SELECT		ProjectBuffer.SharePointId
			,SUM(
                CASE 
                WHEN    ProjectBuffer.SHAPE.STIntersects(#PcswmmPriorityLine.SHAPE) = 1 
                        AND #PcswmmPriorityLine.PRIORITY = 'HIGH' 
                THEN    1 
                ELSE    0 
                END
                ) PcswmmHiPriorityLineCount
			,SUM(
                CASE 
                WHEN    ProjectBuffer.SHAPE.STIntersects(#PcswmmPriorityLine.SHAPE) = 1 
                        AND #PcswmmPriorityLine.PRIORITY = 'LOW' 
                THEN    1 
                ELSE    0 
                END
                ) PcswmmLoPriorityLineCount
INTO		#PcswmmPriorityLineSummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			#PcswmmPriorityLine
ON			ProjectBuffer.SHAPE.STIntersects(#PcswmmPriorityLine.SHAPE) = 1
GROUP BY	SharePointId

-- update pcswmm priority conduit counts
UPDATE	ProjectBuffer
SET		ProjectBuffer.PcswmmHiPriorityLineCount = #PcswmmPriorityLineSummary.PcswmmHiPriorityLineCount
		,ProjectBuffer.PcswmmLoPriorityLineCount = #PcswmmPriorityLineSummary.PcswmmLoPriorityLineCount
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#PcswmmPriorityLineSummary
WHERE	ProjectBuffer.SharePointId = #PcswmmPriorityLineSummary.SharePointId


/* UPDATE SANI LINE ATTRIBUTE SUMMARIES */

-- select summary of sani line attributes into temp table
SELECT		ProjectBuffer.SharePointId
			,ISNULL(NULLIF(SaniLine.Maintenance, ''), 'Unknown') Maintenance
			,ISNULL(NULLIF(SaniLine.Material, ''), 'UNK') Material
			,ISNULL(SUM(SaniLine.SHAPE.STLength()), 0) ShapeLength
INTO		#SaniAttributeSummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			sde_common.gis.SANITARYLINESALL SaniLine
ON			ProjectBuffer.SHAPE.STIntersects(SaniLine.SHAPE) = 1
GROUP BY	ProjectBuffer.SharePointId
			,SaniLine.Maintenance
			,SaniLine.Material

-- select maintainer with highest record count for each project into temp table
SELECT		SharePointId
			,Maintenance
INTO		#SaniMaintenanceTop
FROM		(
			SELECT		SharePointId
						,Maintenance
						,ROW_NUMBER() OVER (PARTITION BY SharePointId ORDER BY COUNT(Maintenance) DESC) RowNumber
			FROM		#SaniAttributeSummary
			GROUP BY	SharePointId
						,Maintenance
			) RecordSet
WHERE		RecordSet.RowNumber = 1

-- select material with longest total length for each project into temp table
SELECT		SharePointId
			,Material
INTO		#SaniMaterialTop
FROM		(
			SELECT	SharePointId
					,Material
					,ROW_NUMBER() OVER (PARTITION BY SharePointId ORDER BY ShapeLength DESC) RowNumber
			FROM	#SaniAttributeSummary
			) RecordSet
WHERE		RecordSet.RowNumber = 1

-- update sani primary maintainer
UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniPrimaryMaintainer = #SaniMaintenanceTop.Maintenance
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#SaniMaintenanceTop
WHERE	ProjectBuffer.SharePointId = #SaniMaintenanceTop.SharePointId

-- update sani primary material
UPDATE	ProjectBuffer
SET		ProjectBuffer.SaniPrimaryMaterial = #SaniMaterialTop.Material
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#SaniMaterialTop
WHERE	ProjectBuffer.SharePointId = #SaniMaterialTop.SharePointId


/* UPDATE STORM LINE PRIMARY MATERIAL */

-- select summary of storm line materials into temp table
SELECT		ProjectBuffer.SharePointId
			,ISNULL(NULLIF(StormLine.Maintenance, ''), 'Unknown') Maintenance
			,ISNULL(NULLIF(StormLine.Material, ''), 'UNK') Material
			,ISNULL(SUM(StormLine.SHAPE.STLength()), 0) ShapeLength
INTO		#StormAttributeSummary
FROM		sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
			LEFT OUTER JOIN
			sde_common.gis.STORMLINESALL StormLine
ON			ProjectBuffer.SHAPE.STIntersects(StormLine.SHAPE) = 1
GROUP BY	ProjectBuffer.SharePointId
			,StormLine.Maintenance
			,StormLine.Material

-- select maintainer with highest record count for each project into temp table
SELECT		SharePointId
			,Maintenance
INTO		#StormMaintenanceTop
FROM		(
			SELECT	SharePointId
					,Maintenance
					,ROW_NUMBER() OVER (PARTITION BY SharePointId ORDER BY COUNT(Maintenance) DESC) RowNumber
			FROM	#StormAttributeSummary
			GROUP BY	SharePointId
						,Maintenance
			) RecordSet
WHERE		RecordSet.RowNumber = 1

-- select material with longest total length for each project into temp table
SELECT		SharePointId
			,Material
INTO		#StormMaterialTop
FROM		(
			SELECT	SharePointId
					,Material
					,ROW_NUMBER() OVER (PARTITION BY SharePointId ORDER BY ShapeLength DESC) RowNumber
			FROM	#StormAttributeSummary
			) RecordSet
WHERE		RecordSet.RowNumber = 1

-- update storm primary maintainer
UPDATE	ProjectBuffer
SET		ProjectBuffer.StormPrimaryMaintainer = #StormMaintenanceTop.Maintenance
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#StormMaintenanceTop
WHERE	ProjectBuffer.SharePointId = #StormMaintenanceTop.SharePointId

-- update storm primary material
UPDATE	ProjectBuffer
SET		ProjectBuffer.StormPrimaryMaterial = #StormMaterialTop.Material
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,#StormMaterialTop
WHERE	ProjectBuffer.SharePointId = #StormMaterialTop.SharePointId


/* UPDATE HAS ATTRIBUTE FIELDS */

-- update HasPumpStation based on spatial intersection
UPDATE	sde_common.gis.COORDINATIONPROJECTBUFFER 
SET		HasPumpStation =
            CASE 
            WHEN ProjectBuffer.SHAPE.STIntersects(SaniStructures.SHAPE) = 1 THEN 'Yes' ELSE 'No' 
            END
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,sde_common.gis.SANITARYSTRUCTURESALL SaniStructures
WHERE	SaniStructures.StructureType = 'Pump Station'

-- update HasForceMain based on spatial intersection
UPDATE	sde_common.gis.COORDINATIONPROJECTBUFFER 
SET		HasForceMain = 
            CASE 
            WHEN ProjectBuffer.SHAPE.STIntersects(SaniLines.SHAPE) = 1 THEN 'Yes' ELSE 'No' 
            END
FROM	sde_common.gis.COORDINATIONPROJECTBUFFER ProjectBuffer
		,sde_common.gis.SANITARYLINESALL SaniLines
WHERE	SaniLines.LineType = 'Force Main'


/* UPDATE DETAIL REPORT URLS */

-- update detail report urls
UPDATE	sde_common.gis.COORDINATIONPROJECTBUFFER
SET		SaniLineDetailReport = @DetailReportRoot 
			+ 'CoordinationProjectSaniLineDetail'
			+ '&SharePointId=' + CAST(SharePointId AS varchar(10))
			+ '&ProjectType=' + REPLACE(ProjectType, ' ', '%20')
		,SaniStructureDetailReport = @DetailReportRoot 
			+ 'CoordinationProjectSaniStructureDetail'
			+ '&SharePointId=' + CAST(SharePointId AS varchar(10))
			+ '&ProjectType=' + REPLACE(ProjectType, ' ', '%20')
		,StormLineDetailReport = @DetailReportRoot 
			+ 'CoordinationProjectStormLineDetail'
			+ '&SharePointId=' + CAST(SharePointId AS varchar(10))
			+ '&ProjectType=' + REPLACE(ProjectType, ' ', '%20')
		,StormStructureDetailReport = @DetailReportRoot 
			+ 'CoordinationProjectStormStructureDetail'
			+ '&SharePointId=' + CAST(SharePointId AS varchar(10))
			+ '&ProjectType=' + REPLACE(ProjectType, ' ', '%20')

END

