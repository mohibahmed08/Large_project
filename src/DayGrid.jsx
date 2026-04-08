import {useState} from 'react';

//IMMPORT THE STYLE SHEET
import './DayGrid.css';

//THIS CLASS WILL BE ONE DAY INSIDE THE CALENDAR GRID
//I.E. THE BOX THAT IS INTERACTABLE AND SHOWS STUFF
//WITHIN THE CALENDAR U.I.

//SHOULD BE USED AS AN ARRAY OF DAYS WITHIN THE CALENDAR U.I.
function DayGrid( { weather, setCurrentWeather, maxFutureWeatherDays, maxPastWeatherDays, dayOfMonth, year, month, isOtherMonth, setSelectedCalendarDate, setSelectedCalendarDateWeather} ){

    //DATE OBJECT FOR DETERMINING THINGS
    const date = new Date();

    //CHECK IF THIS DAY GRID IS ACTIVE (TODAY == DAY OF MONTH)
    const isToday = dayOfMonth == date.getDate() && year == date.getFullYear() && month == date.getMonth();

    //TARGET DATE FOR DAY INDEX AND WITHIN WEEK
    const targetDate = new Date(year, month, dayOfMonth);
    //NORMALIZE THE HOURS
    targetDate.setHours(0,0,0,0);
    //COMPUTE THE DIFFERENCE IN TIME
    const diffMs = targetDate - date; 
    //CONVERT THAT TO DAYS AND DETERMINE DIFFERENCE IN DAYS
    const diffDays = diffMs / (1000 * 60 * 60 * 24);
    //TRUE IF TARGET DAY IS 7 DAYS AWAY FROM CURRENT
    const isWithinWeather = diffDays >= -maxPastWeatherDays - 1 && diffDays <= maxFutureWeatherDays;
    
    //COMPUTES THE DAY INDEX
    const dayIndex = Math.floor(diffDays + 1);
    //COMPUTES THE START HOUR FOR EACH DAY
    // const hourIndex = dayIndex * 24; // start of the day in hourly array

    //ARRAY OF DAY'S CONTENT (BOTH REMINDERS AND SUGGESTIONS)
    //CURRENT SUBFIELDS: { type, time, stringTitle, stringInfo }
    const [content, setContent] = useState([
        // { time: "9:30am", stringTitle: "Test" },
        // { time: "10:20am", stringTitle: "Work" },
        // { time: "11:15am", stringTitle: "Meeting" },
        // { time: "9:30am", stringTitle: "Test" },
        // { time: "10:20am", stringTitle: "Work" },
        // { time: "11:15am", stringTitle: "Meeting" },
    ]);    
    //SET THE CONTENT OF THE ARRAY THROUGH FETCH
    // getContent(setContent, dayOfMonth);

    //GENERAL WEATHER FOR THE CURRENT DAY
    const generalWeather = weather ? weatherCodeToText(getDailyGeneralWeather(weather.hourly.weathercode, dayIndex)) : "";
    
    //PASS IN THE CURRENT WEATHER FOR TODAY
    if(isToday) setCurrentWeather(generalWeather);

    //RETURN DOM
    return (
        <>
            {/* THE DATE BOX ITSELF CONTAINING SUBINFO AND IF ACTIVE (CURRRENT DAY), OTHER MONTH IF SPACER FROM PRIOR/NEXT MONTH BLEEDING OVER TO THIS ONE */}
            <div className = {`day-grid-wrapper ${isToday ? "active" : ""} ${isOtherMonth ? "other-month" : ""}`} onClick = {()=>{setSelectedCalendarDate(new Date(year, month, dayOfMonth)); setSelectedCalendarDateWeather(weather?.hourly || null);}}>
                {/* TOP LEFT WEATHER OF THE CURRENT DAY */}
                {isWithinWeather && <text className = "day-grid-weather-header">{generalWeather}</text>}
                {/* TOP RIGHT DAY NUMBER IN THE BOX */}
                <text className = "day-grid-day-number">{dayOfMonth}</text>
                {/* SECTION TO HOLD TILED REMINDERS / SUGGESTIONS */}
                <div className = {`day-grid-tile-wrapper`}>
                    {/* IF CONTENT ISN'T EMPTY, THEN CREATE THE LIST */}
                    {content.length > 0 && <ul className = "day-grid-ul">
                        {/* IF CONTENT ISN'T EMPTY, MAP (ITERATE) THROUGH CONTENT */}
                        {content.map((item, index) => (
                            //CREATE A LIST ELEMENT OF TYPE (SUGGESTION OR REMINDER) 
                            //WITH INDEX KEY FOR DIFFERENTIATE
                            <li className = {`day-grid-tile-row ${item.type}`} key = {index}>
                                {/* HAVE THE TIME ON THE LEFT SIDE */}
                                <text className = 'day-grid-tile-time'>{item.time || "No Time"}</text>
                                {/* HAVE THE STRING TITLE ON THE RIGHT SIDE */}
                                <text className = 'day-grid-tile-string-title'>{item.stringTitle || "No Title"}</text>
                            </li>
                        ))}
                    </ul>}
                </div>
            </div>
        </>
    );

}

//TURNS THE WEATHER CODE TO MEANINGFUL TEXT 
function weatherCodeToText(code) {
    switch (code) {
        case 0: return "Clear sky";               
        case 1: return "Mostly clear";                 
        case 2: return "Partly cloudy";
        case 3: return "Overcast";
        case 45: case 48: return "Foggy";
        case 51: case 53: case 55: return "Light drizzle";
        case 56: case 57: return "Freezing drizzle";
        case 61: case 63: case 65: return "Rainy";
        case 66: case 67: return "Freezing rain";
        case 71: case 73: case 75: return "Snowy";
        case 77: return "Snow grains";
        case 80: case 81: case 82: return "Rain showers";
        case 85: case 86: return "Snow showers";
        case 95: return "Thunderstorm";
        case 96: case 99: return "Thunderstorm with hail";
        default: return "Unknown";
    }
}

//GETS THE MOST GENERAL WEATHER FOR THE DAY BASED ON CHOOSING 
//THE WEATHERCODE THAT IS MOST OCCURING
function getDailyGeneralWeather(hourlyWeather, dayIndex) {
    const start = dayIndex * 24;
    const dayHours = hourlyWeather.slice(start, start + 24);

    // Count frequency
    const counts = {};
    dayHours.forEach(code => counts[code] = (counts[code] || 0) + 1);

    // Find most frequent
    let maxCount = 0;
    let generalCode = dayHours[0];
    for (const code in counts) {
        if (counts[code] > maxCount) {
            maxCount = counts[code];
            generalCode = parseInt(code);
        }
    }

    return generalCode;
}

//OBTAINS SUGGESTIONS FROM BACKEND THROUGH API CALL
function getContent(setContent, dayOfMonth){
    
    //FETCH COMMAND TO API TO SEARCH THE DATE AND RETURN ANY
    //REMINDERS WITH INFO: { time, stringTitle, stringInfo }

    //THIS METHOD WILL SET THE TYPE OF ANYTHING AT THIS POINT
    //AS A REMINDER TYPE, DYNAMICALLY SUGGESTIONS WILL BE MADE
    //WHILST THE APPLICATION IS RUNNING

    //FETCH AT SPECIFIC PORT (CHANGE WHEN MADE)
    fetch(`https://example.com/${dayOfMonth}/data`)
        //WHAT TO DO WITH THE RESPONSE
        .then((response) => {
            //IF RESPONSES ERRORS, THEN THROW A NEW ERROR
            if (!response.ok) throw new Error(`HTTP ERROR: ${response.status}`);
            //RETURN PROMISE TO RESULTING ARRAY FETCHED
            return response.json();
        })
        //OBTAIN THE FETCHED DATA
        .then((data) => {
            //OTHERWISE OBTAIN THE JSON (ARRAY OF SUBINFO: { time, stringTitle, stringInfo }) 
            //AND OVERRIDE THE CONTENT TO THE NEW ARRAY
            setContent(data != null ? data : []);
        })
        //CATCH EXTRANIOUS ERRORS
        .catch((error) => {
            console.error("Fetch error:", error);
        });    

}

//EXPORT TO OTHER JSX CLASSES FOR USABILITY
export default DayGrid;