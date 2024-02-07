DROP TABLE IF EXISTS gamification
CREATE TABLE gamification (
	user_id int,
	last_x_weeks int,	
	posts_created int,
	replies_received int,
	thankyous_received int,
	events_created int,
	event_participants int,
	items_gifted int,
	places_recommended int
);


--import the .csv file with 'Import/Export Data' feature by right clicking the table



--PART 1: CALCULATING X VALUES (FOR BADGE CRITERIA)
--create a function for creating corrected tables and calculating descriptive statistics per badge
--badge_data = excel column (variable) of relevance for specific badge
--badge_data_nc = noncumulative version of the variable of relevance (using 4-week time intervals instead of last_x_weeks)
--badge_name = badge name
--badge_name_fixed = data table formatted to be used for analysis
--badge_name_desc = descriptive statistics table
--see line 133 for an example of how to type input variables
CREATE OR REPLACE FUNCTION badge_criteria(
  badge_data text,
  badge_data_nc text,
  badge_name text,
  badge_name_fixed text,
  badge_name_desc text
)
RETURNS VOID AS $$
BEGIN
  --replace null entries with zeros
  EXECUTE 'UPDATE gamification SET ' || badge_data || ' = 0 WHERE ' || badge_data || ' IS NULL';


  --create a temporary table with only the necessary columns for the badge
  --badge_data_nc will be calculated in the next step
  EXECUTE 'DROP TABLE IF EXISTS ' || badge_name;
  EXECUTE 'CREATE TEMPORARY TABLE ' || badge_name || ' (
    user_id int,
    last_x_weeks int,
    ' || badge_data || ' int,
    ' || badge_data_nc || ' int
  )';


  --insert only the weeks 4, 8, and 12 from the general table
  --last_x_weeks = 6 is not used because the analysis will be done over 4-week periods (i.e., weeks 1-4, 5-8, and 9-12)
  --calculate the real (noncumulative) numbers for 4-week periods (badge_data_nc)
  EXECUTE 'INSERT INTO ' || badge_name || '
    SELECT user_id, last_x_weeks, ' || badge_data || ',
    CASE
    	WHEN last_x_weeks = 4 THEN ' || badge_data || '
    	WHEN last_x_weeks = 8 THEN ' || badge_data || ' - LAG(' || badge_data || ') OVER (ORDER BY user_id, last_x_weeks)
    	WHEN last_x_weeks = 12 THEN ' || badge_data || ' - LAG(' || badge_data || ') OVER (ORDER BY user_id, last_x_weeks)
    END ' || badge_data_nc || '
    FROM gamification
    WHERE last_x_weeks != 6
    ORDER BY user_id, last_x_weeks';


  --main table: activity progression over 4-week periods per user
  EXECUTE 'DROP TABLE IF EXISTS ' || badge_name_fixed;
  EXECUTE 'CREATE TABLE ' || badge_name_fixed || ' (
    user_id int,
    week_period varchar(50),
    ' || badge_data_nc || ' int
  )';


  --exclude irrelevant users (who didn't show any activity in any time period)
  EXECUTE 'INSERT INTO ' || badge_name_fixed || '
    SELECT user_id,
    CASE
    	WHEN last_x_weeks = 4 THEN ''Weeks 9-12''
    	WHEN last_x_weeks = 8 THEN ''Weeks 5-8''
    	WHEN last_x_weeks = 12 THEN ''Weeks 1-4''
    END week_period,
    ' || badge_data_nc || '
    FROM ' || badge_name || '
    WHERE user_id NOT IN (
        SELECT user_id
        FROM ' || badge_name || '
        WHERE ' || badge_data_nc || ' = 0
        GROUP BY user_id
        HAVING COUNT(*) = 3
    )
    ORDER BY user_id, last_x_weeks';


  --create descriptive statistics table
  --users count, overall average of badge_data, median, mode, min, max, range, standard deviation, Q1, Q3 (all  variables per week period)
  EXECUTE 'DROP TABLE IF EXISTS ' || badge_name_desc;
  EXECUTE 'CREATE TABLE ' || badge_name_desc || ' (
    week_period varchar(50),
    user_count int,
    mean numeric,
    median numeric,
    mmode int,
    mmin int,
    mmax int,
    rrange int,
    sd numeric,
    q1 numeric,
    q3 numeric
  )';


  EXECUTE 'INSERT INTO ' || badge_name_desc || '
    SELECT 
      week_period, 
      COUNT(user_id) AS user_count,
      AVG(' || badge_data_nc || ') AS mean,
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ' || badge_data_nc || ') AS median,
      MODE() WITHIN GROUP (ORDER BY ' || badge_data_nc || ') AS mmode,
      MIN(' || badge_data_nc || ') AS mmin,
      MAX(' || badge_data_nc || ') AS mmax,
      MAX(' || badge_data_nc || ') - MIN(' || badge_data_nc || ') AS rrange,
      STDDEV(' || badge_data_nc || ') AS sd,
      PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ' || badge_data_nc || ') AS q1,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ' || badge_data_nc || ') AS q3
    FROM ' || badge_name_fixed || '
    GROUP BY week_period';
END;
$$ LANGUAGE plpgsql;


--BADGE 1: EVENT PLANNER (at least x events with y participants in z weeks)
SELECT badge_criteria('events_created', 'events_created_nc', 'event_planner', 'event_planner_fixed', 'event_planner_desc');


--BADGE 2: CONVERSATION STARTER (at least x posts with y replies in z weeks)
SELECT badge_criteria('posts_created', 'posts_created_nc', 'conversation_starter', 'conversation_starter_fixed', 'conversation_starter_desc');


--BADGE 3: PHILANTHROPIST (at least x items gifted on the marketplace in z weeks)
SELECT badge_criteria('items_gifted', 'items_gifted_nc', 'philanthropist', 'philanthropist_fixed', 'philanthropist_desc');


--BADGE 4: HELPING HAND (at least x thankyou messages received in z weeks)
SELECT badge_criteria('thankyous_received', 'thankyous_received_nc', 'helping_hand', 'helping_hand_fixed', 'helping_hand_desc');


--BADGE 5: LOCAL GUIDE (at least x places recommended in z weeks)
SELECT badge_criteria('places_recommended', 'places_recommended_nc', 'local_guide', 'local_guide_fixed', 'local_guide_desc');


--export 'badge_name_desc' tables to use for data visualization in Tableau



-----PART 2: CALCULATING Y VALUES (FOR BADGE CRITERIA)
--badge 1 (event planner with events_created and event_participants)
--calculating the average participant number per event
UPDATE gamification
SET event_participants = 0
WHERE event_participants IS NULL


--create a table with only the necessary columns for the badge
DROP TABLE IF EXISTS event_planner_2
CREATE TABLE event_planner_2(
user_id int,
last_x_weeks int,
events_created int,
event_participants int
)


--insert only last_12_weeks values (which has all values cumulatively) because we are not interested in change over time this time
--but simply calculating how many participants an event has on average
--select rows which isn't 0 on posts_created
INSERT INTO event_planner_2
SELECT user_id, last_x_weeks, events_created, event_participants
FROM gamification
WHERE last_x_weeks = 12 AND events_created != 0
ORDER BY user_id, last_x_weeks


--table for average
DROP TABLE IF EXISTS event_planner_2_desc
CREATE TABLE event_planner_2_desc (
total_events_created int,
total_event_participants int,
avg_participant_per_event numeric
)


INSERT INTO event_planner_2_desc
SELECT SUM(events_created), SUM(event_participants), CAST(SUM(event_participants) AS numeric) / SUM(events_created)
FROM event_planner_2


--repeat the same steps for badge 2 (conversation starter with posts_created and replies_received)
UPDATE gamification
SET replies_received = 0
WHERE replies_received IS NULL


--create a table with only the necessary columns for the badge
DROP TABLE IF EXISTS conversation_starter_2
CREATE TABLE conversation_starter_2(
user_id int,
last_x_weeks int,
posts_created int,
replies_received int
)


--insert only last_12_weeks values (which has all values cumulatively) because we are not interested in change over time this time
--but simply calculating how many replies a post gets on average
--select rows which isn't 0 on posts_created
INSERT INTO conversation_starter_2
SELECT user_id, last_x_weeks, posts_created, replies_received
FROM gamification
WHERE last_x_weeks = 12 AND posts_created != 0
ORDER BY user_id, last_x_weeks


--table for average
DROP TABLE IF EXISTS conversation_starter_2_desc
CREATE TABLE conversation_starter_2_desc (
total_posts_created int,
total_replies_received int,
avg_reply_per_post numeric
)


INSERT INTO conversation_starter_2_desc
SELECT SUM(posts_created), SUM(replies_received), CAST(SUM(replies_received) AS numeric) / SUM(posts_created)
FROM conversation_starter_2