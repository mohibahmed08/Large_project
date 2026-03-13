//IMPORT CORRESPONDING CSS SHEET
import './App.css';

//IMPORT FOR CALENDAR UI
import Calendar from './Calendar.jsx';

//MAIN EXPORTED FUNCTION
function App(){

    //HTML DOM RETURN
    return(
        <>
            {/* SHOW THE CALENDARS FOR FIRST 5 MONTHS */}
            {Array.from({ length: 5 }, (_, i) => (
                <Calendar key={i} monthsAwayFromNow={i} />
            ))}
        </>
    );

}

//MAIN EXPORT TO INDEX DOM
export default App;