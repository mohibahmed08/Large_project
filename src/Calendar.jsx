//IMPORT CORRESPONDING CSS SHEET
import './Calendar.css';

//IMPORT FOR CALENDAR UI
import CalendarMonth from './CalendarMonth.jsx';

//MAIN EXPORTED FUNCTION
function Calendar({totalNumMonths}){

    //HTML DOM RETURN
    return(
        <div className = "calendar-calendar-background">
            {/* WRAPPER FOR CALENDAR MONTHS TO BE STACKED PROPERLY */}
            {/* SHOW THE CALENDARS FOR FIRST 5 MONTHS */}
            {Array.from({ length: totalNumMonths }, (_, i) => (
                <CalendarMonth key={i} monthsAwayFromNow={i} />
            ))}
        </div>
    );

}

//MAIN EXPORT TO INDEX DOM
export default Calendar;