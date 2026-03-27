import './CalendarMonth.css';

//DAY GRID FOR THE CALENDAR
import DayGrid from './DayGrid.jsx';

//USE STATE AND EFFECT FOR AUTO UPDATES & DOM RELOAD SAVE
import { useState } from 'react';

//MAIN CONSTRUCTOR FOR CALENDAR MONTH
function CalendarMonth({monthsAwayFromNow, singleMonth}){

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

    const [monthDropdown, setMonthDropdown] = useState(false);

    //ARRAY OF WEEKDAY NAMES FOR TITLES
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

    //ARRAY OF DAYS WITHIN THE MONTH (CONSTANT RERENDER ON DOM CHANGE)
    const daysArr =  
        //CREATE AN ARRAY OF DAYS IN MONTH LENGTH
        Array.from( {length : daysInMonth}, (_, i) => 
            //THEN TAGS TO DAY GRID SUBCLASS WITH ITERATIVE INFO
            <DayGrid key = {i} dayOfMonth = {i + 1} year = {year} month = {date.getMonth() + monthsFromNow}/>
        );

    return (
        <>
            {/* WRAPPER FOR THE MAIN CALENDAR THAT HOLDS THE ARRAY OF DAYS */}
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
                    {daysArr}
                </div>
            </div>
        </>
    );


}

//EXPORTABLE FOR APP (MAIN)
export default CalendarMonth;
