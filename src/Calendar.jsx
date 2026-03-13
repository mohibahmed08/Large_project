import './Calendar.css';

//DAY GRID FOR THE CALENDAR
import DayGrid from './DayGrid.jsx';

//USE STATE AND EFFECT FOR AUTO UPDATES & DOM RELOAD SAVE
import { useState } from 'react';

//MAIN CONSTRUCTOR FOR CALENDAR
function Calendar(){

    //HOLDS DATE GENERAL OBJECT
    const date = new Date();
    //HOW MANY DAYS ARE WITHIN THIS MONTH
    const daysInMonth = (new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate());

    //ARRAY OF DAYS WITHIN THE MONTH
    const [daysArr] = useState( 
        //CREATE AN ARRAY OF DAYS IN MONTH LENGTH
        Array.from( {length : daysInMonth}, (_, i) => 
            //THEN TAGS TO DAY GRID SUBCLASS WITH ITERATIVE INFO
            <DayGrid key = {i} dayOfMonth = {i + 1} />
        )
    );

    //ARRAY OF WEEKDAY NAMES FOR TITLES
    const weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
    
    return (
        <>
            {/* WRAPPER FOR THE MAIN CALENDAR THAT HOLDS THE ARRAY OF DAYS */}
            <div className="calendar-wrapper">
            {/* Weekday header */}
            <div className="calendar-weekdays">
                {weekdays.map((day) => (
                <div key={day} className="weekday">
                    {day}
                </div>
                ))}
            </div>

            {/* DayGrid cells */}
            <div className="calendar-calendar-wrapper">
                {daysArr}
            </div>
            </div>
        </>
    );


}

//EXPORTABLE FOR APP (MAIN)
export default Calendar;
