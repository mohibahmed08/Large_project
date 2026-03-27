import React, { useState, useEffect } from 'react';
import './login.css';

const API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';

const Login = ({ setIsAuthenticated }) => {
  // UI State
  const [isLogin, setIsLogin] = useState(true);
  const [showPassword, setShowPassword] = useState(false);

  // Form State
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  // Async / feedback state
  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  // Validation
  const [passwordsMatch, setPasswordsMatch] = useState(true);

  // Password matching logic
  useEffect(() => {
    if (!isLogin && confirmPassword.length > 0) {
      setPasswordsMatch(password === confirmPassword);
    } else {
      setPasswordsMatch(true);
    }
  }, [password, confirmPassword, isLogin]);

  // Clear messages when switching tabs
  const switchTab = (loginMode) => {
    setIsLogin(loginMode);
    setErrorMsg('');
    setSuccessMsg('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!isLogin && !passwordsMatch) return;

    setIsLoading(true);
    setErrorMsg('');
    setSuccessMsg('');

    try {
      if (isLogin) {
        // ── LOGIN ──────────────────────────────────────────────
        const res = await fetch(`${API_BASE}/api/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ login: email, password }),
        });

        const data = await res.json();

        if (!res.ok) {
          setErrorMsg(data.error || 'Login failed. Please try again.');
          return;
        }

        // Store the JWT so the rest of the app can use it
        localStorage.setItem('jwtToken', data.jwtToken ?? '');
        localStorage.setItem('userId', data.id ?? '');
        localStorage.setItem('firstName', data.firstName ?? '');
        localStorage.setItem('lastName', data.lastName ?? '');

        setSuccessMsg('Logged in successfully!');
        setIsAuthenticated(true);
        

      } else {
        // ── REGISTER ───────────────────────────────────────────
        const res = await fetch(`${API_BASE}/api/signup`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ firstName, lastName, email, password }),
        });

        const data = await res.json();

        if (!res.ok) {
          setErrorMsg(data.error || 'Registration failed. Please try again.');
          return;
        }

        setSuccessMsg('Account created! Please check your email to verify your account.');
        switchTab(true);
      }
    } catch {
      setErrorMsg('Could not reach the server. Please check your connection.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">
      <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700">

        {/* Tab Switcher */}
        <div className="mb-8 flex border-b border-gray-700">
          <button
            type="button"
            onClick={() => switchTab(true)}
            className={`flex-1 pb-4 text-sm font-semibold transition-all ${isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}
          >
            LOGIN
          </button>
          <button
            type="button"
            onClick={() => switchTab(false)}
            className={`flex-1 pb-4 text-sm font-semibold transition-all ${!isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}
          >
            REGISTER
          </button>
        </div>

        <h2 className="mb-6 text-2xl font-bold text-center">
          {isLogin ? 'Welcome Back' : 'Create Account'}
        </h2>

        {/* Feedback banners */}
        {errorMsg && (
          <div className="mb-4 rounded-lg bg-red-900/50 border border-red-700 px-4 py-3 text-sm text-red-300">
            {errorMsg}
          </div>
        )}
        {successMsg && (
          <div className="mb-4 rounded-lg bg-green-900/50 border border-green-700 px-4 py-3 text-sm text-green-300">
            {successMsg}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">

          {/* First / Last name — register only */}
          {!isLogin && (
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">FIRST NAME</label>
                <input
                  type="text"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
                  placeholder="Jane"
                  required
                />
              </div>
              <div className="flex-1">
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">LAST NAME</label>
                <input
                  type="text"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
                  placeholder="Doe"
                  required
                />
              </div>
            </div>
          )}

          {/* Email Field */}
          <div>
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">EMAIL ADDRESS</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all"
              placeholder="johndoe@example.com"
              required
            />
          </div>

          {/* Password Field with Show/Hide toggle */}
          <div className="relative">
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">PASSWORD</label>
            <input
              type={showPassword ? "text" : "password"}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch && !isLogin ? 'border-red-500 focus:ring-red-500' : 'border-gray-700 focus:border-blue-500 focus:ring-blue-500'}`}
              placeholder="••••••••"
              required
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-3 top-9 text-[10px] font-bold text-gray-500 hover:text-blue-400 transition-colors"
            >
              {showPassword ? 'HIDE' : 'SHOW'}
            </button>
          </div>

          {/* Confirm Password — register only */}
          {!isLogin && (
            <div>
              <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">CONFIRM PASSWORD</label>
              <input
                type={showPassword ? "text" : "password"}
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch ? 'border-red-500 focus:ring-red-500' : 'border-gray-700 focus:border-blue-500 focus:ring-blue-500'}`}
                placeholder="••••••••"
                required
              />
              {!passwordsMatch && (
                <p className="mt-2 text-xs font-bold text-red-500 animate-pulse">
                  Passwords do not match
                </p>
              )}
            </div>
          )}

          <button
            type="submit"
            disabled={(!passwordsMatch && !isLogin) || isLoading}
            className={`w-full rounded-lg py-3 font-bold shadow-lg transition-all active:scale-[0.98] ${(!passwordsMatch && !isLogin) || isLoading ? 'bg-gray-700 text-gray-500 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-500 text-white shadow-blue-900/20'}`}
          >
            {isLoading ? 'Please wait…' : isLogin ? 'Sign In' : 'Get Started'}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-500">
          {isLogin ? "Don't have an account?" : "Already have an account?"}
          <button
            type="button"
            onClick={() => switchTab(!isLogin)}
            className="ml-1 text-blue-400 hover:underline font-medium"
          >
            {isLogin ? 'Register now' : 'Log in here'}
          </button>
        </p>
      </div>
    </div>
  );
};

export default Login;
