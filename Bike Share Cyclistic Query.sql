WITH
-- Combine 12 monthly dataset to 1 yearly dataset
year_data AS
(
  SELECT * FROM dbo.['202103-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202104-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202105-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202106-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202107-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202108-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202109-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202110-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202111-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202112-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202201-cyclistic-tripdata$']
  UNION ALL
  SELECT * FROM dbo.['202202-cyclistic-tripdata$']
  ),

  -- Clear empty cells from the dataset
  null_cleaned AS
  (
    SELECT *
	 FROM year_data WHERE start_station_name NOT LIKE '%NULL%'
	                AND end_station_name NOT LIKE '%NULL%'
					AND start_lat NOT LIKE '%NULL%'
					AND end_lat NOT LIKE '%NULL%'
					AND start_lng NOT LIKE '%NULL%'
					AND end_lng NOT LIKE '%NULL%'
	),
	-- Aggregated rider length as Minutes, and assign respective day of the week 
  aggre_data AS
  ( 
    SELECT *,
	DATEDIFF(MINUTE,started_at, ended_at) as TotalMinutes,
	CASE
	  WHEN day_of_week = 1 THEN 'Sunday'
	  WHEN day_of_week = 2 THEN 'Monday'
      WHEN day_of_week = 3 THEN 'Tuesday'
      WHEN day_of_week = 4 THEN 'Wednesday'
      WHEN day_of_week = 5 THEN 'Thursday'
      WHEN day_of_week = 6 THEN 'Friday'
    ELSE
    'Saturday'
  END
    AS Day_Week
FROM null_cleaned
),

--  Remove Ride_id with characters more than 16
clean_ride_id_data AS
(
  SELECT * FROM aggre_data
  WHERE LEN(ride_id) = 16 AND TotalMinutes > 1
),
--   TRIM station name to ensure no extra space, and to replace (*), (Temp), filter out row with(LBS-WH-TEST) in start station name 
cstart_station_name_data AS
(
  SELECT ride_id,
  TRIM(REPLACE
         (REPLACE 
		    (start_station_name,'(*)', ''),
			    '(TEMP)', '')) AS start_station_name_clean
  FROM clean_ride_id_data
  WHERE start_station_name NOT LIKE '%(LBS-WH-TEST)%'
  ),
--  TRIM station name to ensure no extra space, and to replace (*), (Temp), filter out row with(LBS-WH-TEST) in end station name 
 cend_station_name_data AS
 ( 
   SELECT ride_id,
   TRIM(REPLACE
         (REPLACE
		   (end_station_name,'(*)', ''),
		      '(TEMP)', '')) AS end_station_name_clean
   FROM clean_ride_id_data
   WHERE end_station_name NOT LIKE '%(LBS-WH-TEST)%'
),
-- JOIN both cleaned station column ON ride_id 
station_name AS
(
  SELECT ss.ride_id, ss.start_station_name_clean, es.end_station_name_clean
  FROM cstart_station_name_data as ss
   JOIN cend_station_name_data as es
    ON ss.ride_id = es.ride_id
),

-- JOIN clean station columns to the main dataset ON ride_id
final_table AS
(
  SELECT sn.ride_id, crid.rideable_type, crid.member_casual, crid.Day_Week,
          CAST(crid.started_at AS date) AS date_of_year, crid.ended_at, crid.TotalMinutes,
		   sn.start_station_name_clean, sn.end_station_name_clean,
		    crid.start_lat, crid.start_lng,
			crid.end_lat, crid.end_lng
  FROM clean_ride_id_data as crid
    JOIN station_name as sn
	 ON crid.ride_id = sn.ride_id
),
-- DATA EXPLORATION & ANALYSIS
-- 1)Find out total numbers of member or casual riders DEPARTING from respective stations

casual_department_station AS
(
  SELECT COUNT(member_casual) AS casual, start_station_name_clean
   FROM final_table WHERE member_casual = 'casual'
   GROUP BY start_station_name_clean
),

member_department_station AS
(
  SELECT COUNT(member_casual) AS member, start_station_name_clean
   FROM final_table WHERE member_casual = 'member'
   GROUP BY start_station_name_clean
),

-- Join member & casual riders ON departing bike stations
department_station AS
(
  SELECT cds.start_station_name_clean, cds.casual, mds.member
  FROM casual_department_station AS cds 
  JOIN member_department_station AS mds
  ON cds.start_station_name_clean = mds.start_station_name_clean
),

-- GROUP departing station name with distinct Latitude and Altitude
depart_latlng AS
(
  SELECT DISTINCT(start_station_name_clean), ROUND(AVG(start_lat),4) AS dep_lat,
  ROUND(AVG(start_lng),4) AS dep_lng
  FROM final_table
  GROUP BY start_station_name_clean
),

-- Join location coordinate data with ridership count
--Export to excel & import to tableau for geo-visualisation
location_viz_dep AS
(
  SELECT dl.start_station_name_clean, ds.casual, ds.member, dl.dep_lat, dl.dep_lng
  FROM department_station ds 
  JOIN depart_latlng dl
  ON ds.start_station_name_clean = dl.start_station_name_clean
),

-- 2. Find out total numbers of member or casual riders ARRIVING for respective stations
casual_arrive_station AS
(
 SELECT COUNT(member_casual) AS casual, end_station_name_clean
 FROM final_table WHERE member_casual = 'casual'
 GROUP BY end_station_name_clean
),

member_arrive_station AS
(
  SELECT COUNT(member_casual) AS member, end_station_name_clean
  FROM final_table WHERE member_casual = 'member'
  GROUP BY end_station_name_clean
),

-- Join member & casual riders ON arriving bike stations
arrive_station AS
(
  SELECT cas.end_station_name_clean, cas.casual, mas.member
  FROM casual_arrive_station cas
  JOIN member_arrive_station mas
  ON cas.end_station_name_clean = mas.end_station_name_clean
),

-- GROUP arriving station name with distinct Latitude and Altitude
arrive_latlng AS
(
  SELECT DISTINCT end_station_name_clean, ROUND(AVG(end_lat),4) AS arri_lat,
            ROUND(AVG(end_lng),4) AS arri_lng
			FROM final_table
			GROUP BY end_station_name_clean
),

-- Join location coordinate data with ridership count 
-- (Export to excel & import to tableau for geo-visualisation
location_viz_arrive AS
(
  SELECT al.end_station_name_clean, ast.casual, ast.member, al.arri_lat, al.arri_lng
   FROM arrive_station ast
   JOIN arrive_latlng al
   ON ast.end_station_name_clean = al.end_station_name_clean
),

-- 3. To find out trips taken by casual & members respectively group by days

day_trips_casual AS
(
  SELECT COUNT(member_casual) AS casual, date_of_year
  FROM final_table WHERE member_casual = 'casual'
  GROUP BY date_of_year
),

day_trips_member AS
(
  SELECT COUNT(member_casual) AS member, date_of_year
  FROM final_table WHERE member_casual = 'member'
  GROUP BY date_of_year
),

day_trip_year AS
(
 SELECT dtc.casual, dtm.member, dtm.date_of_year
 FROM day_trips_casual dtc JOIN
 day_trips_member dtm 
 ON dtc.date_of_year = dtm.date_of_year
 ),

 -- 4. To find out trips taken by casual & members respectively group by the DAY OF THE WEEK
Day_Week_trips_casual As
(
  SELECT COUNT(member_casual) AS casual, Day_Week
  FROM final_table
  WHERE member_casual = 'casual'
  GROUP BY Day_Week
  ),
  Day_Week_trips_member As
(
  SELECT COUNT(member_casual) AS member, Day_Week
  FROM final_table
  WHERE member_casual = 'member'
  GROUP BY Day_Week
  ),

  Day_Week_trips AS
  (
    SELECT dwtc.Day_week, dwtc.casual, dwtm.member
	FROM Day_Week_trips_casual dwtc 
	JOIN Day_Week_trips_member dwtm
	ON dwtc.Day_Week = dwtm.Day_Week
	),
	--5 To find the AVERAGE ride time for Casual & Member Riders

	data_totalmin_casual AS
	(
	  SELECT AVG(TotalMinutes) AS AVG_ride_casual
	  FROM final_table
	  WHERE member_casual = 'casual'
	  ),

	  data_totalmin_member AS
	(
	  SELECT AVG(TotalMinutes) AS AVG_ride_member
	  FROM final_table
	  WHERE member_casual = 'member'
	  ),

	  -- 6. To find the Overall Rider Count for Casual & Member riders

	  totalride_casual AS
	  (
	   SELECT COUNT(member_casual) AS ridership_casual
	   FROM final_table
	   WHERE member_casual = 'casual'
	   ),
	   totalride_member AS
	  (
	   SELECT COUNT(member_casual) AS ridership_member
	   FROM final_table
	   WHERE member_casual = 'member'
	   )
	   SELECT * FROM totalride_member





