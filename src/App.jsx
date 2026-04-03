//IMPORT CORRESPONDING CSS SHEET
import './App.css';
import { useState } from 'react';

//IMPORT FOR CALENDAR UI
import Calendar from './Calendar.jsx';
import Login from './login.jsx'
import Weather from './Weather.jsx'

// IMPORT SIDEBAR ICONS
import leftOpenIcon from './icons/panel-left-open.svg';
import leftCloseIcon from './icons/panel-left-close.svg';
import rightOpenIcon from './icons/panel-right-open.svg';
import rightCloseIcon from './icons/panel-right-close.svg';

//MAIN EXPORTED FUNCTION
function App(){
    
    //SET AUTHENTICATED
    const [isAuthenticated, setIsAuthenticated] = useState(true);

    // SIDEBAR STATES (True = open, False = closed)
    const [leftOpen, setLeftOpen] = useState(true);
    const [rightOpen, setRightOpen] = useState(true);

    // DATE STRINGS FOR SIDEBARS
    const currentDate = new Date();
    const verticalDateString = currentDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    const fullDateString = currentDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });

    //BACKGROUND FOR THE GENERAL APPLICATION
    const [background, setBackground] = useState(null);

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
            {isAuthenticated ? (

                //PASS THE BACKGROUND IMAGE TO THE APPLICATION WRAPPER
                <div className="main-layout" style={{ '--bg-img': `url(${background}`}}>
                    
                    {/* LEFT SIDEBAR (Nav + Date) */}
                    <div className={`sidebar left-sidebar ${leftOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn right-align" onClick={() => setLeftOpen(!leftOpen)}>
                            <img src={leftOpen ? leftCloseIcon : leftOpenIcon} alt="Toggle Left" />
                        </button>
                        
                        {leftOpen ? (
                            <div className="sidebar-content">
                                <div style={{marginBottom: '20px'}}>
                                    <h2 style={{margin: '0 0 5px 0'}}>Today</h2>
                                    <p style={{margin: 0, color: '#60a5fa', fontWeight: 'bold'}}>{fullDateString}</p>
                                </div>

                                <nav style={{display: 'flex', flexDirection: 'column', gap: '5px'}}>
                                    <button className="nav-item"><span className="nav-icon">📅</span> Plan</button>
                                    <button className="nav-item"><span className="nav-icon">✨</span> Event</button>
                                    <button className="nav-item"><span className="nav-icon">✅</span> Task</button>
                                    <hr style={{border: '0', borderTop: '1px solid #2c2c3e', margin: '10px 0'}} />
                                    <button className="nav-item"><span className="nav-icon">⚙️</span> Settings</button>
                                </nav>

                                {/* PROFILE ADDED HERE - margin-top: auto pushes it to the bottom */}
                                <div style={{marginTop: 'auto', paddingTop: '15px', borderTop: '1px solid #2c2c3e', display: 'flex', alignItems: 'center', gap: '12px'}}>
                                    <div style={{width: '35px', height: '35px', borderRadius: '50%', background: '#3b82f6', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', flexShrink: 0}}>
                                        JD
                                    </div>
                                    <span style={{fontWeight: 'bold'}}>John Doe</span>
                                </div>

                            </div>
                        ) : (
                            <div className="vertical-date">
                                {verticalDateString}
                            </div>
                        )}
                    </div>

                    {/* CENTER CONTENT */}
                    <div className="center-content">
                        <div className="calendar-wrapper">
                            <Calendar singleMonth = {false} setBackground = {setBackground}/>
                        </div>
                    </div>

                    {/* RIGHT SIDEBAR (AI) */}
                    <div className={`sidebar right-sidebar ${rightOpen ? 'open' : 'closed'}`}>
                        <button className="toggle-btn left-align" onClick={() => setRightOpen(!rightOpen)}>
                            <img src={rightOpen ? rightCloseIcon : rightOpenIcon} alt="Toggle Right" />
                        </button>
                        {rightOpen && (
                            <div className="sidebar-content" style={{height: 'calc(100vh - 80px)'}}>
                                <h2>AI Assistant</h2>
                                <p style={{fontSize: '0.85rem', color: '#9ca3af'}}>Ask for schedule optimizations.</p>
                                <textarea 
                                    className="ai-input" 
                                    placeholder="e.g. Schedule a meeting..."
                                ></textarea>
                                <button className="ai-send-btn">Send to AI</button>
                            </div>
                        )}
                    </div>

                </div>
            ) : (
                <Login setIsAuthenticated={setIsAuthenticated} />
            )}
            
            {/* IF TOTAL MONTHS = 1, THEN ARROWS ENABLED, OTHERWISE YOU HAVE TO SCROLL */}
        </>
    );

}

//MAIN EXPORT TO INDEX DOM
export default App;
