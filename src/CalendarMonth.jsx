import './CalendarMonth.css';

//DAY GRID FOR THE CALENDAR
import DayGrid from './DayGrid.jsx';
import Weather from './Weather.jsx'

//PICTURE BACKGROUND IMPORTS
import ClearSky from './weather_backgrounds/ClearSky.jpg';
import Cloudy from './weather_backgrounds/Cloudy.jpg';
import NightClear from './weather_backgrounds/NightClear.jpg';
import NightCloudy from './weather_backgrounds/NightCloudy.jpg';
import NightPartlyCloudy from './weather_backgrounds/NightPartlyCloudy.jpg';
import PartlyCloudy from './weather_backgrounds/PartlyCloudy.jpg';
import SunsetSunriseClearSky from './weather_backgrounds/SunsetSunriseClearSky.png';
import SunsetSunriseCloudy from './weather_backgrounds/SunsetSunriseCloudy.jpg';
import SunsetSunrisePartlyCloudy from './weather_backgrounds/SunsetSunrisePartlyCloudy.jpg';

//USE STATE AND EFFECT FOR AUTO UPDATES & DOM RELOAD SAVE
import { useState } from 'react';

//MAIN CONSTRUCTOR FOR CALENDAR MONTH
function CalendarMonth({monthsAwayFromNow, singleMonth}){

    //HOLDS THE CURRENT WEATHER STATE FOR EXTENDED TIME
    const [weather, setWeather] = useState(null);
    
    //HOLDS DATE GENERAL OBJECT
    const date = new Date();

    //HOLDS MONTHS AWAY FROM NOW (CURRENT DATE)
    const [monthsFromNow, setMonthsFromNow] = useState(monthsAwayFromNow);

    //COMPUTE THE FIRST DAY OF THE TARGET MONTH
    const targetDate = new Date(date.getFullYear(), date.getMonth() + monthsFromNow, 1);
    // HOW MANY DAYS ARE WITHIN THIS MONTH
    const daysInMonth = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0).getDate();
    // GRID INDENT OF THE FIRST DAY FOR CALENDAR
    const firstDay = targetDate.getDay();
    // THE CURRENT MONTH'S NAME
    const monthName = targetDate.toLocaleString('default', { month: 'long' });
    // CURRENT YEAR (YYYY FORMAT)
    const year = targetDate.getFullYear();

    //MAXIMUM WEATHER DAYS DISPLAYED
    const maxFutureWeatherDays = 20;
    const maxPastWeatherDays = 20;

    //ARRAY OF WEEKDAY NAMES FOR TITLES
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    
    //TBD WHEN YOU CLICK THE MONTH/YEAR HEADER
    const [monthDropdown, setMonthDropdown] = useState(false);

    //GETS THE CURRENT WEATHER IN REAL TIME
    const [currentWeather, setCurrentWeather] = useState(-1);

    //GETS THE CURRENT TIME OF DAY
    function getTimeOfDay() {
        const hour = new Date().getHours();
        if (hour >= 6 && hour < 9) return "sunrise";
        if (hour >= 9 && hour < 18) return "day";
        if (hour >= 18 && hour < 21) return "sunset";
        return "night";
    }

    //TURNS THE CURRENT WEATHER INTO A WEATHER IMAGE
    function getWeatherImg(currentWeather){
        
        //OBTAIN THE CURRENT TIME OF THE DAY
        const timeOfDay = getTimeOfDay();

        //CHANGE BACKGROUND BASED ON WEATHER AND TIME OF DAY
        switch(currentWeather){
            //RETURNS THE WEATHER OF THE CURRENT DAY
            case "Clear sky": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunriseClearSky;
                else if(timeOfDay === "day") return ClearSky;
                else return NightClear;
            case "Overcast": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunriseCloudy;
                else if(timeOfDay === "day") return Cloudy;
                else return NightCloudy;
            case "Partly cloudy": 
                //SHOW DIFFERENT IMAGES AT DIFFERENT TIMES OF DAY
                if(timeOfDay === "sunrise" || timeOfDay === "sunset") return SunsetSunrisePartlyCloudy;
                else if(timeOfDay === "day") return PartlyCloudy;
                else return NightPartlyCloudy;
            default: return null;
        }
    }

    //ARRAY OF DAYS WITHIN THE MONTH (CONSTANT RERENDER ON DOM CHANGE)
    const daysArr =  
        //CREATE AN ARRAY OF DAYS IN MONTH LENGTH
        Array.from( {length : daysInMonth}, (_, i) => 
            //THEN TAGS TO DAY GRID SUBCLASS WITH ITERATIVE INFO
            <DayGrid key = {i} setCurrentWeather = {setCurrentWeather} weather = {weather} maxFutureWeatherDays = {maxFutureWeatherDays} maxPastWeatherDays = {maxPastWeatherDays} dayOfMonth = {i + 1} year = {year} month = {date.getMonth() + monthsFromNow}/>
        );

    return (
        <>
            {/* OBTAIN WEATHER FOR THE NEXT 7 DAYS */}
            <Weather setWeather = {setWeather} desiredDate = {targetDate} additionalDays = {maxFutureWeatherDays} priorDays = {maxPastWeatherDays} />

            {/* WRAPPER FOR THE MAIN CALENDAR THAT HOLDS THE ARRAY OF DAYS */}
            <div className="calendar-month-wrapper" style={{ '--bg-img': `url(${getWeatherImg(currentWeather)})` }}>
                {/* THE INTERACTABLE HEADER FOR CALENDAR */}
                <div className="calendar-month-interactable-header">
                    {/* LEFT ARROW TO DECREMENT BY A MONTH (ONLY FOR ONE MONTH) */}
                    {singleMonth && <h1 onClick = {()=>setMonthsFromNow(monthsFromNow - 1)} className = "calendar-month-arrow">{"←"}</h1>}
                    {/* MONTH NAME CORESPONDING TO CURRENT MONTH */}
                    <h1 className = "calendar-month-month-name" onClick = {()=>{singleMonth && setMonthDropdown(!monthDropdown)}}>{monthName + " " + year}</h1>
                    {/* LEFT ARROW TO INCREMENT BY A MONTH (ONLY FOR ONE MONTH) */}
                    {singleMonth && <h1 onClick = {()=>setMonthsFromNow(monthsFromNow + 1)} className = "calendar-month-arrow">{"→"}</h1>}
                </div>
                {/* WEEKDAY HEADER (MONDAY, TUESDAY, ...) */}
                <div className="calendar-weekdays">
                    {/* SHOW THE WEEKDAYS ON THE TOP */}
                    {weekdays.map((day) => (
                    <div key={day} className="weekday">
                        {day}
                    </div>
                    ))}
                </div>
                {/* DAYGRID CELLS INDENTED BASED ON START DATE */}
                <div className="calendar-month-day-grid-wrapper" style = {{"--first-day" : firstDay + 1}}>  
                    {daysArr}
                </div>
            </div>
        </>
    );

}

//EXPORTABLE FOR APP (MAIN)
export default CalendarMonth;
