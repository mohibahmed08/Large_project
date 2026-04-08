//SHOULD BE WHAT SHOWS AS CENTER CONTENT WHEN YOU CLICK ON A DATE
//WILL HOLD ALL INFO FOR THE DATE CLICKED ON INCLUDING HOURLY WEATHER
//TASKS, REMINDERS, SUGGESTIONS, ADD EVENT, EDIT EVENT, REMOVE EVENT

//REQUIRES THE DATE PASSED IN & ITS CURRENT WEATHER (IF APPLICABLE) 
function EnlargedDate(setSelectedCalendarDate, date, weather){

    

    return(

        //THE OVERALL BUBBLED WRAPPER ENCOMPASSING THE ENLARGED DATE
        <div className = "enlarged-date-wrapper">
            {/* THE DATE TITLE AT THE TOP MIDDLE OF THE WRAPPER */}
            <div className = "enlarged-date-top-title">

            </div>
            {/* HOLDS THE HOURLY WEATHER FOR THE CURRENT DATE SELECTED */}
            <div className = "enlarged-date-hourly-weather-wrapper">

            </div>
            {/* HOLDS THE SUGGESTED CONTENT FOR THE CURRENT DAY */}
            <div className = "enlarged-date-suggested-content-wrapper">

            </div>
            {/* HOLDS THE TASKS/REMINDERS OF THE CURRENT DAY */}
            <div className = "enlarged-date-tasks-wrapper">

            </div>
        </div>

    );
}

export default EnlargedDate;