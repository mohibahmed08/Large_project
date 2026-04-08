import './CalendarMonth.css';

//DAY GRID FOR THE CALENDAR
import DayGrid from './DayGrid.jsx';
import Weather from './Weather.jsx';

//USE STATE AND EFFECT FOR AUTO UPDATES & DOM RELOAD SAVE
import { useState, useEffect } from 'react';

//MAIN CONSTRUCTOR FOR CALENDAR MONTH
function CalendarMonth({monthsFromNow, setBackgroundWeather, singleMonth, setSelectedCalendarDate, setSelectedCalendarDateWeather}){

    //HOLDS THE CURRENT WEATHER STATE FOR EXTENDED TIME
    const [weather, setWeather] = useState(null);
    
    //HOLDS DATE GENERAL OBJECT
    const date = new Date();

    // COMPUTE THE FIRST DAY OF THE TARGET MONTH
    const targetDate = new Date(date.getFullYear(), date.getMonth() + monthsFromNow, 1);
    // HOW MANY DAYS ARE WITHIN THIS MONTH
    const daysInMonth = new Date(targetDate.getFullYear(), targetDate.getMonth() + 1, 0).getDate();
    // GRID INDENT OF THE FIRST DAY FOR CALENDAR
    const firstDay = targetDate.getDay();
    // CURRENT YEAR (YYYY FORMAT)
    const year = targetDate.getFullYear();

    // WEATHER API RANGE
    const earliestAllowed = new Date(date.getFullYear(), date.getMonth() - 4, date.getDate()); // 4 months ago
    
    const latestAllowed = new Date(date); // today
    latestAllowed.setDate(latestAllowed.getDate() + 15); // 16 days in future

    // CLAMP TARGET MONTH TO WEATHER-ALLOWED RANGE
    const monthStart = targetDate < earliestAllowed ? earliestAllowed : targetDate;
    const monthEndDate = new Date(targetDate.getFullYear(), targetDate.getMonth(), daysInMonth);
    const monthEnd = monthEndDate > latestAllowed ? latestAllowed : monthEndDate;

    // WEATHER ENABLED?
    const weatherEnabled = monthEnd >= monthStart;
    // MAXIMUM WEATHER DAYS
    const maxPastWeatherDays = weatherEnabled ? Math.max(0, Math.floor((date - monthStart) / (1000 * 60 * 60 * 24))) : 0;
    const maxFutureWeatherDays = weatherEnabled ? Math.max(0, Math.floor((monthEnd - date) / (1000 * 60 * 60 * 24))) : 0;

    //GETS THE CURRENT WEATHER IN REAL TIME
    const [currentWeather, setCurrentWeather] = useState(-1);

    //WHEN CURRENT WEATHER CHANGES, PASS UP WEATHER FOR BACKGROUND
    useEffect(()=>{
        //IF WEATHER ISN'T ENABLED OR WEATHER IS NULL, RETURN
        if(!weatherEnabled || !currentWeather) return;
        //PASS BACKGROUND WEATHER UP ON CURRENT WEATHER CHANGE
        setBackgroundWeather(currentWeather);
    }, [currentWeather])

    //ARRAY OF DAYS WITHIN THE MONTH (CONSTANT RERENDER ON DOM CHANGE)
    const realDays =  
        //CREATE AN ARRAY OF DAYS IN MONTH LENGTH
        Array.from( {length : daysInMonth}, (_, i) => 
            //THEN TAGS TO DAY GRID SUBCLASS WITH ITERATIVE INFO
            <DayGrid key = {i} setCurrentWeather = {setCurrentWeather} weather = {weather} maxFutureWeatherDays = {maxFutureWeatherDays} maxPastWeatherDays = {maxPastWeatherDays} dayOfMonth = {i + 1} year = {targetDate.getFullYear()} month = {targetDate.getMonth()} setSelectedCalendarDate = {setSelectedCalendarDate} setSelectedCalendarDateWeather = {setSelectedCalendarDateWeather} />
        );

    // EMPTY DAYS (OFFSET THAT REPLACES INDENTATION)
    const prevMonthDays = singleMonth ? Array.from({ length: firstDay }, (_, i) => {

        //OBTAIN THE PRIOR MONTH DATE TO GET THE DAYS IN PRIOR MONTH AND THEN SUBTRACT FROM THIS MONTHS FIRST DAY
        const prevMonthDate = new Date(year, date.getMonth() + monthsFromNow, 0);
        const daysInPrevMonth = prevMonthDate.getDate();
        const day = daysInPrevMonth - firstDay + i + 1;
        
        //RETURN A COPY OF LAST MONTHS PRIOR DAYS FILLING UP TO CURRENT NEW MONTH DAY (GRAYED OUT)
        return (<DayGrid key={`prev-${i}`} setCurrentWeather={setCurrentWeather} weather={weather} maxFutureWeatherDays={maxFutureWeatherDays} maxPastWeatherDays={maxPastWeatherDays} dayOfMonth={day} year={targetDate.getFullYear()} month={targetDate.getMonth()} isOtherMonth={true} setSelectedCalendarDate = {setSelectedCalendarDate} setSelectedCalendarDateWeather = {setSelectedCalendarDateWeather}/>);
    
    }) : [];

    //COMBINE EMPTY DAYS WITH DAYS ARR
    const dayArr = [...prevMonthDays, ...realDays];

    return (
        <>
            {/* OBTAIN WEATHER FOR THE NEXT 7 DAYS */}
            {weatherEnabled && <Weather setWeather = {setWeather} desiredDate = {monthStart} additionalDays = {maxFutureWeatherDays} priorDays = {maxPastWeatherDays}/>}

            {/* WRAPPER FOR THE MAIN CALENDAR THAT HOLDS THE ARRAY OF DAYS */}
            {/* style={{ '--bg-img': `url(${getWeatherImg(currentWeather)})` }} */}
            <div className="calendar-month-wrapper"> 
                {/* DAYGRID CELLS INDENTED BASED ON START DATE */}
                <div className="calendar-month-day-grid-wrapper" style = {{"--first-day" : !singleMonth ? firstDay + 1 : 0}}>  
                    {dayArr}
                </div>
            </div>
        </>
    );
}

//EXPORTABLE FOR APP (MAIN)
export default CalendarMonth;
