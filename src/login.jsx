import React, { useState, useEffect } from 'react';
import './login.css';

const API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';

const Login = ({ setIsAuthenticated }) => {
  // UI State
  const [isLogin, setIsLogin] = useState(true);
  const [showPassword, setShowPassword] = useState(false);
  const [showVerifyModal, setShowVerifyModal] = useState(false); // New Modal State

  // Form State
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  // Async / feedback state
  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  // Validation
  const [passwordsMatch, setPasswordsMatch] = useState(true);

  useEffect(() => {
    if (!isLogin && confirmPassword.length > 0) {
      setPasswordsMatch(password === confirmPassword);
    } else {
      setPasswordsMatch(true);
    }
  }, [password, confirmPassword, isLogin]);

  const switchTab = (loginMode) => {
    setIsLogin(loginMode);
    setErrorMsg('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!isLogin && !passwordsMatch) return;

    setIsLoading(true);
    setErrorMsg('');

    try {
      if (isLogin) {
        const res = await fetch(`${API_BASE}/api/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ login: email, password }),
        });

        const data = await res.json();
        if (!res.ok) {
          setErrorMsg(data.error || 'Login failed.');
          return;
        }

        localStorage.setItem('jwtToken', data.jwtToken ?? '');
        setIsAuthenticated(true);
      } else {
        const res = await fetch(`${API_BASE}/api/signup`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ firstName, lastName, email, password }),
        });

        if (!res.ok) {
          const data = await res.json();
          setErrorMsg(data.error || 'Registration failed.');
          return;
        }

        // SUCCESSFUL REGISTER: Show the popup
        setShowVerifyModal(true);
      }
    } catch {
      setErrorMsg('Could not reach the server.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">
      
      {/* VERIFICATION MODAL */}
      {showVerifyModal && (
        <div className="modal-overlay">
          <div className="modal-content animate-in">
            <div className="modal-icon">📧</div>
            <h3 className="text-xl font-bold mb-2">Verify Your Email</h3>
            <p className="text-gray-400 text-sm mb-6">
              A verification link has been sent to <strong>{email}</strong>. 
              Please check your inbox to activate your account.
            </p>
            <button 
              onClick={() => {
                setShowVerifyModal(false);
                switchTab(true); // Take them back to login
              }} 
              className="btn-primary"
            >
              Back to Login
            </button>
          </div>
        </div>
      )}

      <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700">
        {/* ... Rest of your existing Login/Register UI code remains exactly the same ... */}
        
        {/* Tab Switcher */}
        <div className="mb-8 flex border-b border-gray-700">
          <button type="button" onClick={() => switchTab(true)} className={`flex-1 pb-4 text-sm font-semibold transition-all ${isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}>LOGIN</button>
          <button type="button" onClick={() => switchTab(false)} className={`flex-1 pb-4 text-sm font-semibold transition-all ${!isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}>REGISTER</button>
        </div>

        <h2 className="mb-6 text-2xl font-bold text-center">{isLogin ? 'Welcome Back' : 'Create Account'}</h2>

        {errorMsg && (
          <div className="mb-4 rounded-lg bg-red-900/50 border border-red-700 px-4 py-3 text-sm text-red-300">{errorMsg}</div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          {!isLogin && (
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">FIRST NAME</label>
                <input type="text" value={firstName} onChange={(e) => setFirstName(e.target.value)} className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all" placeholder="Jane" required />
              </div>
              <div className="flex-1">
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">LAST NAME</label>
                <input type="text" value={lastName} onChange={(e) => setLastName(e.target.value)} className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all" placeholder="Doe" required />
              </div>
            </div>
          )}

          <div>
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">EMAIL ADDRESS</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all" placeholder="johndoe@example.com" required />
          </div>

          <div className="relative">
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">PASSWORD</label>
            <input type={showPassword ? "text" : "password"} value={password} onChange={(e) => setPassword(e.target.value)} className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch && !isLogin ? 'border-red-500' : 'border-gray-700 focus:border-blue-500'}`} placeholder="••••••••" required />
            <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-9 text-[10px] font-bold text-gray-500 hover:text-blue-400">
              {showPassword ? 'HIDE' : 'SHOW'}
            </button>
          </div>

          {!isLogin && (
            <div>
              <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">CONFIRM PASSWORD</label>
              <input type={showPassword ? "text" : "password"} value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} className={`w-full rounded-lg border bg-gray-900 p-3 outline-none transition-all ${!passwordsMatch ? 'border-red-500' : 'border-gray-700 focus:border-blue-500'}`} placeholder="••••••••" required />
              {!passwordsMatch && <p className="mt-2 text-xs font-bold text-red-500 animate-pulse">Passwords do not match</p>}
            </div>
          )}

          <button type="submit" disabled={(!passwordsMatch && !isLogin) || isLoading} className={`btn-primary mt-6 ${((!passwordsMatch && !isLogin) || isLoading) ? 'cursor-not-allowed bg-gray-700 text-gray-500' : ''}`}>
            {isLoading ? 'Please wait…' : isLogin ? 'Sign In' : 'Get Started'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default Login;