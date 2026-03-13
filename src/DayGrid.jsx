import {useState} from 'react';

//IMMPORT THE STYLE SHEET
import './DayGrid.css';

//THIS CLASS WILL BE ONE DAY INSIDE THE CALENDAR GRID
//I.E. THE BOX THAT IS INTERACTABLE AND SHOWS STUFF
//WITHIN THE CALENDAR U.I.

//SHOULD BE USED AS AN ARRAY OF DAYS WITHIN THE CALENDAR U.I.
function DayGrid( {dayOfMonth} ){

    //CHECK IF THIS DAY GRID IS ACTIVE (TODAY == DAY OF MONTH)
    const isToday = dayOfMonth == new Date().getDate();

    //ARRAY OF DAY'S CONTENT (BOTH REMINDERS AND SUGGESTIONS)
    //CURRENT SUBFIELDS: { type, time, stringTitle, stringInfo }
    const [content, setContent] = useState([
        { time: "9:30am", stringTitle: "Test" },
        { time: "10:20am", stringTitle: "Work" },
        { time: "11:15am", stringTitle: "Meeting" },
    ]);    
    //SET THE CONTENT OF THE ARRAY THROUGH FETCH
    // getContent(setContent, dayOfMonth);

    //RETURN DOM
    return (
        <>
            {/* THE DATE BOX ITSELF CONTAINING SUBINFO AND IF ACTIVE (CURRRENT DAY) */}
            <div className = {`day-grid-wrapper ${isToday ? "active" : ""}`}>
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