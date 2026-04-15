// @ts-nocheck
import React, { useState, useEffect } from 'react';
import './login.css';

const RAW_API_BASE = process.env.REACT_APP_API_URL ?? 'http://localhost:5000';
const API_ROOT = RAW_API_BASE.endsWith('/api') ? RAW_API_BASE : `${RAW_API_BASE}/api`;

// ─── Reset Password Page ─────────────────────────────────────────────────────
// Rendered when URL contains ?token=... (user clicked the reset link in email)
export const ResetPasswordPage = () => {
  const params = new URLSearchParams(window.location.search);
  const token  = params.get('token') || '';

  const [newPassword,     setNewPassword]     = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword,    setShowPassword]    = useState(false);
  const [isLoading,       setIsLoading]       = useState(false);
  const [errorMsg,        setErrorMsg]        = useState('');
  const [success,         setSuccess]         = useState(false);

  const passwordsMatch = confirmPassword.length === 0 || newPassword === confirmPassword;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!passwordsMatch || newPassword.length < 6) return;

    setIsLoading(true);
    setErrorMsg('');

    try {
      const res  = await fetch(`${API_ROOT}/resetpassword`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ token, newPassword }),
      });
      const data = await res.json();
      if (!res.ok) {
        setErrorMsg(data.error || 'Reset failed. The link may have expired.');
        return;
      }
      setSuccess(true);
    } catch {
      setErrorMsg('Could not reach the server.');
    } finally {
      setIsLoading(false);
    }
  };

  if (success) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">
        <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700 text-center">
          <div className="modal-icon">✅</div>
          <h2 className="text-2xl font-bold mb-4">Password Updated!</h2>
          <p className="text-gray-400 text-sm mb-6">Your password has been reset. You can now log in with your new password.</p>
          <button
            className="btn-primary"
            onClick={() => window.location.href = '/'}
          >
            Go to Login
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">
      <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700">
        <h2 className="mb-2 text-2xl font-bold text-center">Choose a New Password</h2>
        <p className="text-gray-400 text-sm text-center mb-6">Must be at least 6 characters.</p>

        {errorMsg && (
          <div className="mb-4 rounded-lg bg-red-900/50 border border-red-700 px-4 py-3 text-sm text-red-300">{errorMsg}</div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="relative">
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">NEW PASSWORD</label>
            <input
              type={showPassword ? 'text' : 'password'}
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all"
              placeholder="••••••••"
              required
              minLength={6}
            />
            <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-9 text-[10px] font-bold text-gray-500 hover:text-blue-400">
              {showPassword ? 'HIDE' : 'SHOW'}
            </button>
          </div>

          <div>
            <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">CONFIRM PASSWORD</label>
            <input
              type={showPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className={`w-full rounded-lg border bg-gray-900 p-3 outline-none transition-all ${!passwordsMatch ? 'border-red-500' : 'border-gray-700 focus:border-blue-500'}`}
              placeholder="••••••••"
              required
            />
            {!passwordsMatch && <p className="mt-2 text-xs font-bold text-red-500 animate-pulse">Passwords do not match</p>}
          </div>

          <button
            type="submit"
            disabled={!passwordsMatch || newPassword.length < 6 || isLoading}
            className={`btn-primary mt-6 ${(!passwordsMatch || newPassword.length < 6 || isLoading) ? 'cursor-not-allowed bg-gray-700 text-gray-500' : ''}`}
          >
            {isLoading ? 'Updating…' : 'Set New Password'}
          </button>
        </form>
      </div>
    </div>
  );
};

// ─── Login / Register / Forgot Password Page ─────────────────────────────────
const Login = ({ setIsAuthenticated }) => {
  // 'login' | 'register' | 'forgot'
  const [view, setView] = useState('login');

  const [showPassword, setShowPassword] = useState(false);
  const [showVerifyModal, setShowVerifyModal] = useState(false);
  const [showForgotSentModal, setShowForgotSentModal] = useState(false);

  // Form fields
  const [firstName, setFirstName]           = useState('');
  const [lastName,  setLastName]            = useState('');
  const [email,     setEmail]               = useState('');
  const [password,  setPassword]            = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [forgotEmail, setForgotEmail]       = useState('');

  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg,  setErrorMsg]  = useState('');

  const passwordsMatch =
    view !== 'register' || confirmPassword.length === 0 || password === confirmPassword;

  const switchView = (v) => {
    setView(v);
    setErrorMsg('');
  };

  // ── Handle verified=1 redirect from email click ──────────────────────────
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get('verified') === '1') {
      // clean up the URL and keep user on login tab with a success hint
      window.history.replaceState({}, '', '/');
    }
  }, []);

  // ── Login / Register submit ───────────────────────────────────────────────
  const handleSubmit = async (e) => {
    e.preventDefault();
    if (view === 'register' && !passwordsMatch) return;

    setIsLoading(true);
    setErrorMsg('');

    try {
      if (view === 'login') {
        const res  = await fetch(`${API_ROOT}/login`, {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ login: email, password }),
        });
        const data = await res.json();
        if (!res.ok) { setErrorMsg(data.error || 'Login failed.'); return; }

        localStorage.setItem('jwtToken', data.accessToken ?? '');
        setIsAuthenticated(true);
      } else {
        const res = await fetch(`${API_ROOT}/signup`, {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ firstName, lastName, email, password }),
        });
        if (!res.ok) {
          const data = await res.json();
          setErrorMsg(data.error || 'Registration failed.');
          return;
        }
        setShowVerifyModal(true);
      }
    } catch {
      setErrorMsg('Could not reach the server.');
    } finally {
      setIsLoading(false);
    }
  };

  // ── Forgot password submit ────────────────────────────────────────────────
  const handleForgotSubmit = async (e) => {
    e.preventDefault();
    setIsLoading(true);
    setErrorMsg('');

    try {
      const res = await fetch(`${API_ROOT}/forgotpassword`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ email: forgotEmail }),
      });
      if (!res.ok) {
        const data = await res.json();
        setErrorMsg(data.error || 'Something went wrong.');
        return;
      }
      setShowForgotSentModal(true);
    } catch {
      setErrorMsg('Could not reach the server.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">

      {/* ── Email verification sent modal ─────────────────────────────── */}
      {showVerifyModal && (
        <div className="modal-overlay">
          <div className="modal-content animate-in">
            <div className="modal-icon">📧</div>
            <h3 className="text-xl font-bold mb-2">Verify Your Email</h3>
            <p className="text-gray-400 text-sm mb-6">
              A verification link has been sent to <strong>{email}</strong>.
              Please check your inbox to activate your account.
            </p>
            <button onClick={() => { setShowVerifyModal(false); switchView('login'); }} className="btn-primary">
              Back to Login
            </button>
          </div>
        </div>
      )}

      {/* ── Forgot password sent modal ────────────────────────────────── */}
      {showForgotSentModal && (
        <div className="modal-overlay">
          <div className="modal-content animate-in">
            <div className="modal-icon">🔑</div>
            <h3 className="text-xl font-bold mb-2">Check Your Inbox</h3>
            <p className="text-gray-400 text-sm mb-6">
              If an account exists for <strong>{forgotEmail}</strong>, a password reset link has been sent. Check your spam folder if you don't see it.
            </p>
            <button onClick={() => { setShowForgotSentModal(false); switchView('login'); }} className="btn-primary">
              Back to Login
            </button>
          </div>
        </div>
      )}

      <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700">

        <h1 className="calendar-title">
          Calendar++
        </h1>

        {/* Add this new subtitle line right here! */}
        <p className="calendar-subtitle">
          Stop Planning. Start Doing.
        </p>

        {/* ── Tab switcher (Login / Register only) ────────────────────── */}
        {view !== 'forgot' && (
          <div className="mb-8 flex border-b border-gray-700">
            <button type="button" onClick={() => switchView('login')}
              className={`flex-1 pb-4 text-sm font-semibold transition-all ${view === 'login' ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}>
              LOGIN
            </button>
            <button type="button" onClick={() => switchView('register')}
              className={`flex-1 pb-4 text-sm font-semibold transition-all ${view === 'register' ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}>
              REGISTER
            </button>
          </div>
        )}

        {/* ── Forgot password view ─────────────────────────────────────── */}
        {view === 'forgot' ? (
          <>
            <button type="button" onClick={() => switchView('login')} className="text-gray-400 text-sm hover:text-blue-400 mb-4 flex items-center gap-1">
              ← Back to Login
            </button>
            <h2 className="mb-2 text-2xl font-bold text-center">Reset Password</h2>
            <p className="text-gray-400 text-sm text-center mb-6">
              Enter the email address on your account and we'll send you a reset link.
            </p>

            {errorMsg && (
              <div className="mb-4 rounded-lg bg-red-900/50 border border-red-700 px-4 py-3 text-sm text-red-300">{errorMsg}</div>
            )}

            <form onSubmit={handleForgotSubmit} className="space-y-5">
              <div>
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">EMAIL ADDRESS</label>
                <input
                  type="email"
                  value={forgotEmail}
                  onChange={(e) => setForgotEmail(e.target.value)}
                  className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all"
                  placeholder="johndoe@example.com"
                  required
                />
              </div>
              <button type="submit" disabled={isLoading} className={`btn-primary mt-6 ${isLoading ? 'cursor-not-allowed bg-gray-700 text-gray-500' : ''}`}>
                {isLoading ? 'Sending…' : 'Send Reset Link'}
              </button>
            </form>
          </>
        ) : (
          <>
            {/* ── Login / Register view ─────────────────────────────────── */}
            <h2 className="mb-6 text-2xl font-bold text-center">
              {view === 'login' ? 'Welcome Back' : 'Create Account'}
            </h2>

            {errorMsg && (
              <div className="mb-4 rounded-lg bg-red-900/50 border border-red-700 px-4 py-3 text-sm text-red-300">{errorMsg}</div>
            )}

            <form onSubmit={handleSubmit} className="space-y-5">
              {view === 'register' && (
                <div className="flex gap-3">
                  <div className="flex-1">
                    <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">FIRST NAME</label>
                    <input type="text" value={firstName} onChange={(e) => setFirstName(e.target.value)}
                      className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all"
                      placeholder="Jane" required />
                  </div>
                  <div className="flex-1">
                    <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">LAST NAME</label>
                    <input type="text" value={lastName} onChange={(e) => setLastName(e.target.value)}
                      className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all"
                      placeholder="Doe" required />
                  </div>
                </div>
              )}

              <div>
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">EMAIL ADDRESS</label>
                <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                  className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 outline-none transition-all"
                  placeholder="johndoe@example.com" required />
              </div>

              <div className="relative">
                <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">PASSWORD</label>
                <input type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)}
                  className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch && view === 'register' ? 'border-red-500' : 'border-gray-700 focus:border-blue-500'}`}
                  placeholder="••••••••" required />
                <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-9 text-[10px] font-bold text-gray-500 hover:text-blue-400">
                  {showPassword ? 'HIDE' : 'SHOW'}
                </button>
              </div>

              {view === 'register' && (
                <div>
                  <label className="block text-xs tracking-wider text-gray-400 mb-1 font-bold">CONFIRM PASSWORD</label>
                  <input type={showPassword ? 'text' : 'password'} value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)}
                    className={`w-full rounded-lg border bg-gray-900 p-3 outline-none transition-all ${!passwordsMatch ? 'border-red-500' : 'border-gray-700 focus:border-blue-500'}`}
                    placeholder="••••••••" required />
                  {!passwordsMatch && <p className="mt-2 text-xs font-bold text-red-500 animate-pulse">Passwords do not match</p>}
                </div>
              )}

              {/* Forgot password link — only on login view */}
              {view === 'login' && (
                <div className="text-right">
                  <button type="button" onClick={() => switchView('forgot')}
                    className="text-xs text-gray-400 hover:text-blue-400 transition-colors">
                    Forgot your password?
                  </button>
                </div>
              )}

              <button type="submit" disabled={(!passwordsMatch && view === 'register') || isLoading}
                className={`btn-primary mt-6 ${((!passwordsMatch && view === 'register') || isLoading) ? 'cursor-not-allowed bg-gray-700 text-gray-500' : ''}`}>
                {isLoading ? 'Please wait…' : view === 'login' ? 'Sign In' : 'Get Started'}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
};

export default Login;