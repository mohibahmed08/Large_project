import './CalendarMonth.css';

//DAY GRID FOR THE CALENDAR
import DayGrid from './DayGrid.jsx';
import Weather from './Weather.jsx'

//USE STATE AND EFFECT FOR AUTO UPDATES & DOM RELOAD SAVE
import { useState, useEffect } from 'react';

//MAIN CONSTRUCTOR FOR CALENDAR MONTH
function CalendarMonth({monthsAwayFromNow, singleMonth, setBackgroundWeather}){

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
    const maxFutureWeatherDays = 30;
    const maxPastWeatherDays = 30;

    //ARRAY OF WEEKDAY NAMES FOR TITLES
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    
    //TBD WHEN YOU CLICK THE MONTH/YEAR HEADER
    const [monthDropdown, setMonthDropdown] = useState(false);

    //GETS THE CURRENT WEATHER IN REAL TIME
    const [currentWeather, setCurrentWeather] = useState(-1);

    //WHEN CURRENT WEATHER CHANGES, PASS UP WEATHER FOR BACKGROUND
    useEffect(()=>{
        //PASS BACKGROUND WEATHER UP ON CURRENT WEATHER CHANGE
        setBackgroundWeather(currentWeather);
    }, [currentWeather])

    //ARRAY OF DAYS WITHIN THE MONTH (CONSTANT RERENDER ON DOM CHANGE)
    const realDays =  
        //CREATE AN ARRAY OF DAYS IN MONTH LENGTH
        Array.from( {length : daysInMonth}, (_, i) => 
            //THEN TAGS TO DAY GRID SUBCLASS WITH ITERATIVE INFO
            <DayGrid key = {i} setCurrentWeather = {setCurrentWeather} weather = {weather} maxFutureWeatherDays = {maxFutureWeatherDays} maxPastWeatherDays = {maxPastWeatherDays} dayOfMonth = {i + 1} year = {year} month = {date.getMonth() + monthsFromNow}/>
        );

    // EMPTY DAYS (OFFSET THAT REPLACES INDENTATION)
    const prevMonthDays = Array.from({ length: firstDay }, (_, i) => {

        //OBTAIN THE PRIOR MONTH DATE TO GET THE DAYS IN PRIOR MONTH AND THEN SUBTRACT FROM THIS MONTHS FIRST DAY
        const prevMonthDate = new Date(year, date.getMonth() + monthsFromNow, 0);
        const daysInPrevMonth = prevMonthDate.getDate();
        const day = daysInPrevMonth - firstDay + i + 1;
        
        //RETURN A COPY OF LAST MONTHS PRIOR DAYS FILLING UP TO CURRENT NEW MONTH DAY (GRAYED OUT)
        return (<DayGrid key={`prev-${i}`} setCurrentWeather={setCurrentWeather} weather={weather} maxFutureWeatherDays={maxFutureWeatherDays} maxPastWeatherDays={maxPastWeatherDays} dayOfMonth={day} year={year} month={date.getMonth() + monthsFromNow - 1} isOtherMonth={true}/>);
    
    });

    //COMBINE EMPTY DAYS WITH DAYS ARR
    const dayArr = [...prevMonthDays, ...realDays];

    return (
        <>
            {/* OBTAIN WEATHER FOR THE NEXT 7 DAYS */}
            <Weather setWeather = {setWeather} desiredDate = {targetDate} additionalDays = {maxFutureWeatherDays} priorDays = {maxPastWeatherDays} />

            {/* WRAPPER FOR THE MAIN CALENDAR THAT HOLDS THE ARRAY OF DAYS */}
            {/* style={{ '--bg-img': `url(${getWeatherImg(currentWeather)})` }} */}
            <div className="calendar-month-wrapper"> 
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
                    {dayArr}
                </div>
            </div>
        </>
    );

}

//EXPORTABLE FOR APP (MAIN)
export default CalendarMonth;
