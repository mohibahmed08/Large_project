//IMPORT CORRESPONDING CSS SHEET
import './App.css';
import { useState } from 'react';

//IMPORT FOR CALENDAR UI
import Calendar from './Calendar.jsx';
import Login from './login.jsx'
import Weather from './Weather.jsx'

//MAIN EXPORTED FUNCTION
function App(){
    
    //SET AUTHENTICATED
    const [isAuthenticated, setIsAuthenticated] = useState(false);

    //HTML DOM RETURN
    return(
        <>
            
            {/* PROB GONNA CHANGE, I'M THINKING WE JUST HAVE ONE MONTH AND EDIT */}
            {/* THE TITLE "[MONTH YEAR]" TO ANOTHER MONTH AND YEAR AND HAVE IT CHANGE */}
            {/* OR WE CAN KEEP IT LIKE THIS AND I CAN FIND A WAY TO MAKE IT AUTO CREATE */}
            {/* ONCE SCROLLING, BUT THEN IT MIGHT TAKE TO LONG TO REACH THE DESIRED MONTH & YEAR */}
            {/* THAT THE USER MIGHT BE TRYING TO FIND, BUT FOR NOW I'M MADE THIS MODULAR SO IT */}
            {/* CAN HOPEFULLY BE EMBEDDED IN SOMETHING ELSE OR ANOTHER WRAPPER WITH LITTLE TO NO */}
            {/* PROBLEMS */}
            {/* {isAuthenticated ? (
                <Calendar totalNumMonths={1} />
            ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
            )} */}
            <Calendar totalNumMonths={1} />
            {/* <Calendar totalNumMonths={1} /> */}
            {/* IF TOTAL MONTHS = 1, THEN ARROWS ENABLED, OTHERWISE YOU HAVE TO SCROLL */}
        </>
    );

}

//MAIN EXPORT TO INDEX DOM
export default App;