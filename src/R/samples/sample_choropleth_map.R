#!/usr/bin/env Rscript

###############################
## define team name          ##
team_name <- "betternauts"   ##
###############################

# import packages or install them if they don't exist [helper written by @Shane from stackoverflow]
list.of.packages <- c("yaml", "ggplot2", "RMySQL", "maps", "plyr")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')

require(yaml)
require(ggplot2)
require(RMySQL)
require(maps)
require(plyr)

# define the yml (properties) file, read it in as a list
config_file_path <- "~/rwiz.yml"
print(paste("Using config yml: ", config_file_path))
config <- yaml.load_file(config_file_path)


# define the output parent directory
output_parent_dir <- config$rwizflowy.folders$outputdirectory
# build team path directory name
team_path <- paste0(output_parent_dir,team_name)
# create a team directory in symlink to s3 bucket (just a warning if it already exists)
system(sprintf("mkdir %s",team_path))
# set this new directory as your working directory so all of your outputs will write to it
setwd(team_path)

# set up db con function
dbCon <- function(dbname, user, password, host="localhost", port=3306){
  dbcon <- dbConnect("MySQL", dbname=dbname, user=user,
                     password=password, host=host, port=port)
  dbcon
}

# define connection using the yml properties
con <- dbCon(config$rwizflowy.db.rwizflowy$name,
             config$rwizflowy.db.rwizflowy$username,
             config$rwizflowy.db.rwizflowy$password,
             config$rwizflowy.db.rwizflowy$host,
             config$rwizflowy.db.rwizflowy$port)

# construct query
user_info_query <- "SELECT * from user_info;"

# run the query
user_info <- dbGetQuery(con, user_info_query)

# tell R which columns are dates (they come in as characters by default)
# [as.POSIXlt() is R's way of saying as.Datetime]
user_info$user_signup_started_date <- as.POSIXlt(user_info$user_signup_started_date)
user_info$user_signup_completed_date <- as.POSIXlt(user_info$user_signup_completed_date)
user_info$user_initial_deposit_date <- as.POSIXlt(user_info$user_initial_deposit_date)

# get state shape file from maps package
states_info <- map_data("state")
# get rid of that pesky Washington DC. It's not good for much anyway.
states_info = subset(states_info,group!=8)
# attach state abbreviations for merging to our data
states_info$st <- state.abb[match(states_info$region,tolower(state.name))]

# summarize data by state (sum) (aggregate is in the plyr package)
state_data <- aggregate(user_current_balance ~ user_address_state_abv, data = user_info, FUN=sum)
# rename the values to be consistent with the shape file state names
state_data <- rename(state_data, c("user_address_state_abv"="st", "user_current_balance"="total_balance"))

# merge on values to shape file
merged_info <- merge(x=states_info, y = state_data, by = "st", all = TRUE)

# create the choropleth (heat) map
png(filename="chorolpleth_map_by_state_example.png", width=1440, height=950)

# plot the map!
qplot(
  long, lat, data = merged_info, group = group, 
  fill = total_balance, geom = "polygon" 
)

dev.off()
